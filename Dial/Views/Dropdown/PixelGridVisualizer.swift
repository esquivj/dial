// Dial/Views/Dropdown/PixelGridVisualizer.swift
import AppKit
import SwiftUI

/// LED-grid spectrum visualizer that renders directly from `VisualizerEngine`'s
/// FFT bands. Visual contract:
///   - Configurable columns × 8 rows of compact cells, sized to fill the width
///   - All cells in mint (`Dial.Palette.accent`) at varied alpha to suggest
///     intensity — peak (1.0) > hot top band (0.95) > bulk lit (0.80) >
///     off ghost (0.06). Single-color matches mockup render.
///   - Unlit cells stay faintly visible at ~6% opacity so the grid reads as
///     a populated LED matrix at rest, not a black void
///
/// Renders from throttled spectrum snapshots. The engine owns cadence; the
/// view should not force a display-link redraw loop of its own.
struct PixelGridVisualizer: View {
  @Bindable var engine: VisualizerEngine

  private let rows = Dial.Layout.Spectrum.rows
  private let gap = Dial.Layout.Spectrum.cellGap
  /// Top 30% of any column gets a brighter alpha — reads as the bar entering
  /// "hot" territory, like the lit zone on a VU meter. Within the mint family
  /// rather than a magenta accent (mockup is single-tone).
  private let hotZoneFraction = Dial.Layout.Spectrum.hotZoneFraction

  var body: some View {
    VStack(alignment: .leading, spacing: Dial.Layout.Spectrum.labelGridSpacing) {
      header
      grid
    }
    // The readout cards above this row have a soft shadow. Give the
    // spectrum label its own gutter so the copy does not visually crash
    // into that chrome.
    .padding(Dial.Layout.Spectrum.padding)
  }

  // MARK: - Header (label row matches SessionTimeline's prior rhythm)

  private var header: some View {
    HStack {
      Text("SPECTRUM")
        .font(Dial.Typography.monoLabel)
        .tracking(1.4)
        .foregroundStyle(Dial.Palette.textMuted)
      Spacer()
      Text(rightLabel)
        .font(Dial.Typography.monoLabel)
        .foregroundStyle(Dial.Palette.textMuted)
        .contentTransition(.opacity)
    }
  }

  private var rightLabel: String {
    switch engine.state {
    case .idle:    return "—"
    case .running: return "LIVE · 48k"
    case .denied:  return "PERMISSION"
    case .error:   return "OFFLINE"
    }
  }

  // MARK: - Grid

  private var grid: some View {
    GeometryReader { proxy in
      let bands = engine.bands
      let peaks = engine.peaks
      let columns = max(1, min(engine.bandCount, bands.count, peaks.count))
      let cellSize = max(2, (proxy.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns))
      let showPeakMarkers = engine.showPeakMarkers
      ZStack {
        Canvas { ctx, _ in
          draw(
            into: ctx,
            cellSize: cellSize,
            columns: columns,
            bands: bands,
            peaks: peaks,
            showPeakMarkers: showPeakMarkers)
        }
        if engine.state == .denied || engine.state == .error {
          permissionOverlay
        }
      }
    }
    .frame(height: CGFloat(rows) * cellHeight + CGFloat(rows - 1) * gap)
  }

  /// Slightly shorter than the computed cell width at the HUD's normal size.
  /// Keeps detailed densities from making the spectrum strip taller.
  private var cellHeight: CGFloat { Dial.Layout.Spectrum.cellHeight }

  // MARK: - Painting

  private func draw(
    into ctx: GraphicsContext,
    cellSize: CGFloat,
    columns: Int,
    bands: [Float],
    peaks: [Float],
    showPeakMarkers: Bool
  ) {
    let cellH = cellHeight
    let cellW = cellSize
    let cornerRadius = min(0.8, min(cellW, cellH) * 0.16)
    let mint = Dial.Palette.accent

    for col in 0..<columns {
      let height = bands[col]
      let litRows = Int((Double(height) * Double(rows)).rounded())
      let peakLevel = peaks[col]
      let peakRow = max(0, min(rows - 1, Int((Double(peakLevel) * Double(rows)).rounded()) - 1))
      let hasPeak = peakLevel > 0.02

      for row in 0..<rows {
        // Row 0 is the bottom of the visual; flip y so row N draws at the top.
        let y = (CGFloat(rows - 1 - row)) * (cellH + gap)
        let x = CGFloat(col) * (cellW + gap)
        let rect = CGRect(x: x, y: y, width: cellW, height: cellH)
        let path = Path(roundedRect: rect, cornerRadius: cornerRadius)

        let isLit = row < litRows
        let isPeak = showPeakMarkers && hasPeak && row == peakRow
        let isHot = isLit && (Double(row) / Double(rows)) >= (1 - hotZoneFraction)

        // Single-color spectrum (mint at varied alpha). Mockup spec shows
        // all mint bars; the prior cyan/magenta two-tone was a creative
        // choice that didn't match the render. Hot zone + peak get
        // brighter alpha for visual interest, just within the mint family.
        // Increased peak/lit contrast (1.0 vs 0.65, was 1.0 vs 0.80) so
        // the "lit zone" reads as clearly distinct from the "hot top."
        let alpha: Double
        if isPeak {
          alpha = 1.0
        } else if isHot {
          alpha = 0.92
        } else if isLit {
          alpha = 0.65
        } else {
          alpha = 0.06          // off cell — faint grid ghost
        }
        ctx.fill(path, with: .color(mint.opacity(alpha)))
      }
    }
  }

  // MARK: - Permission overlay

  private var permissionOverlay: some View {
    Button {
      openScreenRecordingPrefs()
    } label: {
      VStack(spacing: 4) {
        Text(engine.state == .denied ? "ENABLE VISUALIZER" : "VISUALIZER OFFLINE")
          .font(Dial.Typography.monoLabel)
          .tracking(1.4)
          .foregroundStyle(Dial.Palette.accent)
        if engine.state == .denied {
          Text("System Settings → Screen Recording")
            .font(Dial.Typography.monoLabel)
            .foregroundStyle(Dial.Palette.textMuted)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Dial.Palette.ground.opacity(0.85))
    }
    .buttonStyle(.pressable)
  }

  private func openScreenRecordingPrefs() {
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    {
      NSWorkspace.shared.open(url)
    }
  }
}
