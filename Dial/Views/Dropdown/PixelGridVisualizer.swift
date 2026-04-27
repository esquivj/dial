// Dial/Views/Dropdown/PixelGridVisualizer.swift
import AppKit
import SwiftUI

/// LED-grid spectrum visualizer that renders directly from `VisualizerEngine`'s
/// FFT bands. Visual contract:
///   - 32 columns × 7 rows of cells, sized to fill the available width
///   - All cells in mint (`Dial.Palette.amber`) at varied alpha to suggest
///     intensity — peak (1.0) > hot top band (0.95) > bulk lit (0.80) >
///     off ghost (0.06). Single-color matches mockup render.
///   - Unlit cells stay faintly visible at ~6% opacity so the grid reads as
///     a populated LED matrix at rest, not a black void
///
/// Renders inside a `TimelineView(.animation)` so paint is decoupled from
/// the audio thread's update cadence — keeps redraws steady at 30fps even
/// when audio buffers arrive irregularly.
struct PixelGridVisualizer: View {
  @Bindable var engine: VisualizerEngine

  private let columns = VisualizerEngine.bandCount  // 32
  private let rows = 7
  private let gap: CGFloat = 1
  /// Top 30% of any column gets a brighter alpha — reads as the bar entering
  /// "hot" territory, like the lit zone on a VU meter. Within the mint family
  /// rather than a magenta accent (mockup is single-tone).
  private let hotZoneFraction: Double = 0.30

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      header
      grid
    }
    .padding(EdgeInsets(top: 0, leading: 14, bottom: 12, trailing: 14))
  }

  // MARK: - Header (label row matches SessionTimeline's prior rhythm)

  private var header: some View {
    HStack {
      Text("SPECTRUM")
        .font(Dial.Typography.monoLabel)
        .tracking(1.4)
        .foregroundStyle(Dial.Palette.muted)
      Spacer()
      Text(rightLabel)
        .font(Dial.Typography.monoLabel)
        .foregroundStyle(Dial.Palette.muted)
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
      let cellSize = max(2, (proxy.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns))
      ZStack {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { _ in
          Canvas { ctx, _ in
            draw(into: ctx, cellSize: cellSize)
          }
        }
        if engine.state == .denied || engine.state == .error {
          permissionOverlay
        }
      }
    }
    .frame(height: CGFloat(rows) * cellHeight + CGFloat(rows - 1) * gap)
  }

  /// Cell height tracks cell width — square cells read most LED-like.
  /// Computed via a sentinel width to avoid a chicken-and-egg with frame.
  private var cellHeight: CGFloat { 7 }

  // MARK: - Painting

  private func draw(into ctx: GraphicsContext, cellSize: CGFloat) {
    let cellH = cellHeight
    let cellW = cellSize
    let mint = Dial.Palette.amber

    for col in 0..<columns {
      let height = engine.bands[col]
      let litRows = Int((Double(height) * Double(rows)).rounded())
      let peakLevel = engine.peaks[col]
      let peakRow = max(0, min(rows - 1, Int((Double(peakLevel) * Double(rows)).rounded()) - 1))
      let hasPeak = peakLevel > 0.02

      for row in 0..<rows {
        // Row 0 is the bottom of the visual; flip y so row N draws at the top.
        let y = (CGFloat(rows - 1 - row)) * (cellH + gap)
        let x = CGFloat(col) * (cellW + gap)
        let rect = CGRect(x: x, y: y, width: cellW, height: cellH)
        let path = Path(roundedRect: rect, cornerRadius: 1)

        let isLit = row < litRows
        let isPeak = hasPeak && row == peakRow
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
          .foregroundStyle(Dial.Palette.amber)
        if engine.state == .denied {
          Text("System Settings → Screen Recording")
            .font(Dial.Typography.monoLabel)
            .foregroundStyle(Dial.Palette.muted)
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
