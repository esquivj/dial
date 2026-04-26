// Dial/Views/Settings/SettingsView.swift
import SwiftUI
import AppKit

/// Hosted by the SwiftUI `Settings` scene in `DialApp`.
/// `onSignIn` runs the full coordinator-level sign-in (auth → mark signed in → start polling).
/// `onImport` is invoked after the user picks a folder via `NSOpenPanel`.
struct SettingsView: View {
  @Bindable var vm: SettingsViewModel
  /// Diagnostic data source — exposes lastSuccessfulPoll, the visualizer
  /// state, and the dbq for enrichment-progress queries. Lifted in here so
  /// the Status section can render without duplicating state through
  /// SettingsViewModel.
  @Bindable var coord: AppCoordinator
  let onSignIn: () async -> Void
  let onImport: (URL) -> Void

  @State private var showDisconnectAlert = false
  @State private var enrichment: StatsQueries.EnrichmentProgress = .init(total: 0, enriched: 0)

  var body: some View {
    Form {
      Section("Spotify account") {
        if vm.signedIn {
          Button("Disconnect") { showDisconnectAlert = true }
            .alert("Disconnect from Spotify?", isPresented: $showDisconnectAlert) {
              Button("Cancel", role: .cancel) {}
              Button("Disconnect", role: .destructive) { vm.markSignedOut() }
            } message: {
              Text("You'll need to reconnect to keep tracking listens. Your local history stays.")
            }
        } else {
          Button("Connect Spotify") { Task { await onSignIn() } }
        }
      }
      Section("History import") {
        if vm.importProgress > 0, vm.importProgress < 1 {
          ProgressView(value: vm.importProgress)
        }
        Button("Choose folder…") {
          let panel = NSOpenPanel()
          panel.canChooseDirectories = true
          panel.canChooseFiles = false
          if panel.runModal() == .OK, let url = panel.url { onImport(url) }
        }
        if let last = vm.lastImport {
          Text("Last import: \(last.rowsInserted) rows")
            .font(Dial.Typography.sansCaption)
        }
      }
      Section("Status") {
        // TimelineView ticks once a second so "5 sec ago" updates live
        // while the user has the Settings window open. Outside the window,
        // no work happens — the closure only re-evaluates on date change.
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
          statusGrid(now: ctx.date)
        }
      }
      Section("About") {
        Text("Dial 0.1").foregroundStyle(Dial.Palette.muted)
      }
    }
    .padding(20)
    .frame(width: 400)
    .task {
      // One-shot enrichment progress fetch on Settings open. Could refresh
      // on a slower cadence (this query touches the full plays table) but
      // the values change at backfill speed (~3 batches/sec), so once-on-
      // open is enough to convey progress.
      enrichment = (try? StatsQueries(dbq: coord.dbq).enrichmentProgress())
        ?? .init(total: 0, enriched: 0)
    }
  }

  // MARK: - Status grid

  private func statusGrid(now: Date) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      statusRow("Last sync", value: lastSyncLabel(now: now))
      statusRow("Visualizer", value: visualizerLabel)
      statusRow("Enriched", value: enrichmentLabel)
    }
  }

  private func statusRow(_ label: String, value: String) -> some View {
    HStack {
      Text(label)
        .foregroundStyle(Dial.Palette.muted)
      Spacer()
      Text(value)
        .font(.system(.body, design: .monospaced))
        .contentTransition(.numericText())
    }
    .font(Dial.Typography.sansCaption)
  }

  private func lastSyncLabel(now: Date) -> String {
    guard let last = coord.lastSuccessfulPoll else { return "never" }
    let elapsed = now.timeIntervalSince(last)
    if elapsed < 5 { return "just now" }
    if elapsed < 60 { return "\(Int(elapsed)) sec ago" }
    if elapsed < 3600 { return "\(Int(elapsed / 60)) min ago" }
    return "\(Int(elapsed / 3600))h ago"
  }

  private var visualizerLabel: String {
    switch coord.visualizer.state {
    case .idle:    return "idle"
    case .running: return "live"
    case .denied:  return "permission denied"
    case .error:   return "offline"
    }
  }

  private var enrichmentLabel: String {
    if enrichment.total == 0 { return "—" }
    let done = enrichment.enriched.formatted(.number.notation(.compactName))
    let total = enrichment.total.formatted(.number.notation(.compactName))
    return "\(done) / \(total) tracks"
  }
}
