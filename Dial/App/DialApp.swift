// Dial/App/DialApp.swift
import SwiftUI

@main
struct DialApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      if let coord = appDelegate.coordinator {
        SettingsView(
          vm: coord.settings,
          coord: coord,
          onSignIn: { try? await coord.signIn() },
          onImport: { folder in
            Task { await runImport(coord: coord, from: folder) }
          }
        )
      } else {
        Text("Dial — initializing…")
          .padding(40)
      }
    }

    // History and Stats are opened programmatically via WindowsManager
    // (see AppCoordinator.windows). They can't be SwiftUI `Window` scenes
    // because the dropdown lives in an NSPopover, outside the scene tree
    // where `@Environment(\.openWindow)` resolves.
  }

  private func runImport(coord: AppCoordinator, from folder: URL) async {
    let urls = (try? FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: nil)) ?? []
    // Sorted lexicographically, which for Spotify's
    // `Streaming_History_Audio_<year>[_<part>].json` filenames is also
    // chronological. Imports oldest → newest so the streak/XP application
    // walks the play timeline in order.
    let endsongs = urls.filter {
      let n = $0.lastPathComponent
      return n.hasPrefix("endsong_") || n.hasPrefix("Streaming_History_Audio_")
    }.sorted { $0.lastPathComponent < $1.lastPathComponent }

    guard !endsongs.isEmpty else { return }
    let total = endsongs.count

    // Kick the progress bar off zero so SettingsView's `0 < x < 1` predicate
    // shows it immediately. Without this, the bar wouldn't appear until the
    // first file finishes — which on the largest year files is ~5 seconds.
    await MainActor.run { coord.settings.importProgress = 0.001 }

    let importer = Importer(dbq: coord.dbq, engine: coord.engine)
    for (idx, f) in endsongs.enumerated() {
      if let rows = try? EndsongFile.parse(at: f) {
        _ = try? importer.importBatch(rows, sourcePath: f.path)
      }
      let progress = Double(idx + 1) / Double(total)
      await MainActor.run { coord.settings.importProgress = progress }
    }

    // Surface the most recent import entry so SettingsView's
    // "Last import: N rows" line populates. Then refresh the in-memory
    // models that just had ~years-of-data poured into the DB underneath
    // them — without this, the dropdown's plays30d / pet stage would stay
    // stale until the next live-poll event.
    let last = (try? ImportsLogDAO(dbq: coord.dbq).last()) ?? nil
    await MainActor.run {
      coord.settings.lastImport = last
      coord.settings.importProgress = 0  // ProgressView hides at 0 or 1
      coord.pet.syncFromStore(dbq: coord.dbq)
      coord.aggCache.refresh(
        trackUri: coord.nowPlaying.track?.uri,
        artistUri: coord.nowPlaying.track?.artistUri)
      coord.nowPlaying.plays30d = coord.aggCache.plays30d
    }
  }
}
