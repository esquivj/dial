import GRDB
import SwiftUI

/// Loads the idle memory and keeps it fresh: reloads when plays change and
/// ticks once a minute so `12M AGO` stays honest. Snapshots pass
/// `initialMemory` and pin the clock with `dialFrozenDate`.
struct IdleMemoryPanel: View {
  let dbq: DatabaseQueue?
  var initialMemory: StatsQueries.IdleMemory? = nil
  let onOpenHistory: () -> Void
  let onOpenStats: () -> Void
  @Environment(\.dialFrozenDate) private var frozenDate
  @State private var memory: StatsQueries.IdleMemory?

  var body: some View {
    Group {
      if let frozenDate {
        strip(now: frozenDate)
      } else {
        TimelineView(.periodic(from: .now, by: 60)) { context in
          strip(now: context.date)
        }
      }
    }
    .task(id: dbq.map(ObjectIdentifier.init)) {
      guard let dbq else { return }
      await reload(dbq)
      do {
        for try await _ in StatsQueries(dbq: dbq).observePlaysChanges().values(in: dbq) {
          await reload(dbq)
        }
      } catch {
        // Keep the last good memory; the strip still renders.
      }
    }
  }

  private func strip(now: Date) -> some View {
    IdleMemoryStrip(
      memory: memory ?? initialMemory,
      now: now,
      onOpenHistory: onOpenHistory,
      onOpenStats: onOpenStats)
  }

  private func reload(_ dbq: DatabaseQueue) async {
    let loaded = await withCheckedContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        continuation.resume(returning: try? StatsQueries(dbq: dbq).idleMemory())
      }
    }
    if let loaded { memory = loaded }
  }
}

/// The idle HUD's memory strip (PLA-105): the last counted play and today's
/// listening, in the readouts' raised-rail material. Sits under the READY
/// card so the screen you see between songs still says something personal.
struct IdleMemoryStrip: View {
  let memory: StatsQueries.IdleMemory?
  let now: Date
  let onOpenHistory: () -> Void
  let onOpenStats: () -> Void
  @Environment(\.dialTheme) private var theme

  var body: some View {
    HStack(spacing: 0) {
      Button(action: onOpenHistory) {
        cell(label: "LAST SPIN", stamp: lastSpinStamp, value: lastSpinValue)
      }
      .buttonStyle(.pressable)
      .frame(maxWidth: .infinity)
      .help("Your last counted play. Opens History.")
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(lastSpinAccessibility)
      .accessibilityAddTraits(.isButton)

      ReadoutDivider()

      Button(action: onOpenStats) {
        cell(label: "TODAY", stamp: todayStamp, value: todayValue)
      }
      .buttonStyle(.pressable)
      .frame(width: Self.todayWidth)
      .help("Counted plays and time listened today. Opens Stats.")
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Today: \(Self.todayLine(plays: memory?.todayPlays ?? 0, ms: memory?.todayMs ?? 0))")
      .accessibilityAddTraits(.isButton)
    }
    .padding(Dial.Layout.Readouts.railPadding)
    .dialRaisedGel(
      shape: RoundedRectangle(cornerRadius: Dial.Layout.Readouts.railCornerRadius, style: .continuous),
      fill: theme.surface.opacity(0.54),
      edgeOpacity: 0.24,
      fillTopOpacity: 0.08,
      fillBottomOpacity: 0.018,
      sheenOpacity: 0.24,
      sheenLineWidth: 0.55,
      contactShadowOpacity: 0.18,
      contactShadowRadius: 1.5,
      contactShadowY: 0.75,
      innerShadowOpacity: 0.10)
  }

  static let todayWidth: CGFloat = 112

  private func cell(label: String, stamp: String?, value: String) -> some View {
    VStack(alignment: .leading, spacing: Dial.Layout.Readouts.cellLabelValueSpacing) {
      HStack(spacing: 6) {
        Text(label)
          .font(Dial.Typography.pixelLabel)
          .tracking(Dial.Tracking.label)
          .foregroundStyle(theme.textFaint)
          .lineLimit(1)
        Spacer(minLength: 0)
        if let stamp {
          Text(stamp)
            .font(Dial.Typography.pixelLabel)
            .tracking(Dial.Tracking.label)
            .foregroundStyle(theme.accent)
            .lineLimit(1)
            .fixedSize()
        }
      }
      Text(value)
        .font(.custom("GeistMono-Medium", size: 12))
        .foregroundStyle(theme.textPrimary)
        .lineLimit(1)
        .truncationMode(.tail)
    }
    .padding(.horizontal, Dial.Layout.Readouts.cellHorizontalPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
  }

  // MARK: Values

  private var lastSpinValue: String {
    guard let spin = memory?.lastSpin else { return "No spins yet" }
    return Self.titleLine(name: spin.trackName, artist: spin.artistName)
  }

  private var lastSpinStamp: String? {
    guard let spin = memory?.lastSpin else { return nil }
    return Self.agoStamp(playedAt: spin.playedAt, now: now)
  }

  private var lastSpinAccessibility: String {
    guard let spin = memory?.lastSpin else { return "Last spin: no spins yet" }
    let who = spin.artistName.isEmpty ? "" : " by \(spin.artistName)"
    let when = Self.agoStamp(playedAt: spin.playedAt, now: now).lowercased()
    return "Last spin: \(spin.trackName)\(who), \(when)"
  }

  private var todayValue: String {
    Self.playsLine(memory?.todayPlays ?? 0)
  }

  private var todayStamp: String? {
    guard let memory, memory.todayPlays > 0 else { return nil }
    return Self.listenedStamp(ms: memory.todayMs)
  }

  // MARK: Formatting (static for tests)

  static func titleLine(name: String, artist: String) -> String {
    let title = name.isEmpty ? "Unknown track" : name
    return artist.isEmpty ? title : "\(title) · \(artist)"
  }

  /// `NOW`, `12M AGO`, `3H AGO`, `YESTERDAY`, `4D AGO`, `2Y AGO`.
  static func agoStamp(playedAt: Int64, now: Date, calendar: Calendar = .current) -> String {
    let then = Date(timeIntervalSince1970: TimeInterval(playedAt))
    let seconds = max(0, Int(now.timeIntervalSince(then)))
    if seconds < 60 { return "NOW" }
    if seconds < 3_600 { return "\(seconds / 60)M AGO" }
    let days = calendar.dateComponents(
      [.day], from: calendar.startOfDay(for: then), to: calendar.startOfDay(for: now)).day ?? 0
    if days == 0 { return "\(seconds / 3_600)H AGO" }
    if days == 1 { return "YESTERDAY" }
    if days < 365 { return "\(days)D AGO" }
    return "\(days / 365)Y AGO"
  }

  static func playsLine(_ plays: Int) -> String {
    "\(plays) \(plays == 1 ? "play" : "plays")"
  }

  /// `3M`, `52M`, `1H 05M`.
  static func listenedStamp(ms: Int64) -> String {
    let minutes = Int(ms / 60_000)
    return minutes < 60 ? "\(minutes)M" : "\(minutes / 60)H \(String(format: "%02d", minutes % 60))M"
  }

  /// Spoken form: `0 plays`, `1 play · 3M`, `14 plays · 52M`.
  static func todayLine(plays: Int, ms: Int64) -> String {
    plays > 0 ? "\(playsLine(plays)) · \(listenedStamp(ms: ms))" : playsLine(plays)
  }
}
