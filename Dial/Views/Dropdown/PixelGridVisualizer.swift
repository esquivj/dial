// Dial/Views/Dropdown/PixelGridVisualizer.swift
import AppKit
import SwiftUI

/// LED-grid spectrum visualizer that renders directly from `VisualizerEngine`'s
/// FFT bands. Visual contract:
///   - 32 columns × 7 rows of cells, sized to fill the available width
///   - Cyan (`Dial.Palette.amber`) for steady-state lit cells
///   - Magenta (`Dial.Palette.orange`) for the top "hot" band of any column
///     and for the peak-hold marker — reinforces the cyan/magenta two-tone
///     rule used elsewhere (event tone for noteworthy moments)
///   - Unlit cells stay faintly visible at ~5% opacity so the grid reads as
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
  /// Top 30% of any column lights up in magenta — reads as the bar entering
  /// "hot" territory, like the red zone on a VU meter.
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
    let cyan = Dial.Palette.amber
    let magenta = Dial.Palette.orange

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

        let color: Color
        let alpha: Double
        if isPeak {
          // Bright magenta peak marker
          color = magenta
          alpha = 1.0
        } else if isHot {
          // Top of the bar — magenta, slightly dimmer than the peak
          color = magenta
          alpha = 0.85
        } else if isLit {
          // Bulk of the bar — cyan
          color = cyan
          alpha = 0.9
        } else {
          // Off cell — barely visible "ghost" so the grid feels populated
          color = cyan
          alpha = 0.05
        }
        ctx.fill(path, with: .color(color.opacity(alpha)))
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
    .buttonStyle(.plain)
  }

  private func openScreenRecordingPrefs() {
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    {
      NSWorkspace.shared.open(url)
    }
  }
}
