// Dial/App/AppDelegate.swift
import AppKit
import Foundation
import GRDB

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  var coordinator: AppCoordinator?
  private var statusBar: StatusBarController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Headless import path: `--import <folder>` runs the same Importer that
    // the Settings UI uses, then exits. Skips all menubar / polling /
    // visualizer setup so the binary acts as a one-shot CLI tool. Useful
    // for bulk-loading the Spotify Extended Streaming History dump without
    // sitting through the UI's progress bar.
    if let importFolder = importFolderFromArgs() {
      runHeadlessImport(folderPath: importFolder)
      return
    }

    do {
      let url = try DatabaseStack.defaultURL()
      let dbq = try DatabaseStack(url: url).dbq
      let clientID = (Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String) ?? ""
      // DEBUG builds use a flat-file token store to avoid the macOS keychain
      // permission prompt that fires on every Xcode re-signed binary.
      // Release builds keep the keychain path (stable signature, real security).
      #if DEBUG
      let tokens: TokenStore = FileTokenStore()
      #else
      let tokens: TokenStore = KeychainTokenStore()
      #endif
      let auth = SpotifyAuthService(clientID: clientID, tokenStore: tokens)
      let client = SpotifyClient(tokenStore: tokens, refresh: { try await auth.refresh() })
      let coord = AppCoordinator(dbq: dbq, client: client, auth: auth, tokenStore: tokens)
      self.coordinator = coord
      self.statusBar = StatusBarController(coord: coord)

      // If a token's already in the keychain, start polling immediately.
      // Otherwise present Settings so the user can sign in — without a token,
      // polling would just churn 401s every 3 seconds.
      if coord.settings.signedIn {
        coord.start()
      } else {
        openSettings()
      }
    } catch {
      NSLog("[Dial] bootstrap failed: \(error)")
    }
  }

  // MARK: - Headless import

  /// Returns the folder path passed via `--import <path>`, or nil if the
  /// flag isn't present. Supports both space-separated (`--import /foo`)
  /// and `=`-separated (`--import=/foo`) forms.
  private func importFolderFromArgs() -> String? {
    let args = CommandLine.arguments
    if let idx = args.firstIndex(of: "--import"), idx + 1 < args.count {
      return args[idx + 1]
    }
    if let arg = args.first(where: { $0.hasPrefix("--import=") }) {
      return String(arg.dropFirst("--import=".count))
    }
    return nil
  }

  /// One-shot import that runs the production Importer against the user's
  /// real DB at ~/Library/Application Support/Dial/dial.sqlite, then exits.
  /// Logs progress to stderr so the caller can tail it; bypasses the UI
  /// entirely so this works while the GUI app is *not* running. (If the
  /// GUI is running, kill it first — SQLite WAL handles concurrent readers
  /// fine but a write transaction will trip the 500ms busy_timeout.)
  private func runHeadlessImport(folderPath: String) {
    Task { @MainActor in
      do {
        let folder = URL(fileURLWithPath: folderPath)
        let dbURL = try DatabaseStack.defaultURL()
        let dbq = try DatabaseStack(url: dbURL).dbq
        let engine = PetEngine(dbq: dbq)
        let importer = Importer(dbq: dbq, engine: engine)

        let urls =
          (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil)) ?? []
        let files = urls.filter {
          let n = $0.lastPathComponent
          return n.hasPrefix("endsong_") || n.hasPrefix("Streaming_History_Audio_")
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !files.isEmpty else {
          stderr("No endsong_*.json or Streaming_History_Audio_*.json files in \(folder.path)")
          exit(1)
        }

        stderr("→ DB: \(dbURL.path)")
        stderr("→ Importing \(files.count) files from \(folder.path)")

        let start = Date()
        var totalInserted = 0
        var totalParsed = 0
        for (idx, f) in files.enumerated() {
          let rows = try EndsongFile.parse(at: f)
          let inserted = try importer.importBatch(rows, sourcePath: f.path)
          totalInserted += inserted
          totalParsed += rows.count
          stderr(
            String(
              format: "  [%2d/%d] %@: %d inserted (%d parsed)",
              idx + 1, files.count, f.lastPathComponent, inserted, rows.count))
        }

        let elapsed = Date().timeIntervalSince(start)
        stderr(
          String(
            format: "✓ Done in %.1fs — %d new plays, %d parsed (deduped: %d)",
            elapsed, totalInserted, totalParsed, totalParsed - totalInserted))
        exit(0)
      } catch {
        stderr("✗ Import failed: \(error)")
        exit(1)
      }
    }
  }

  /// stderr-only logging for the headless import path. Keeps stdout clean
  /// so callers can pipe / parse output if they want.
  private nonisolated func stderr(_ s: String) {
    FileHandle.standardError.write(Data((s + "\n").utf8))
  }

  // MARK: - Settings

  /// Opens (or focuses) the SwiftUI Settings scene.
  private func openSettings() {
    NSApp.activate(ignoringOtherApps: true)
    // macOS 14+: the Settings selector is `showSettingsWindow:`. On older macOS it's `showPreferencesWindow:`.
    let primary = Selector(("showSettingsWindow:"))
    let fallback = Selector(("showPreferencesWindow:"))
    if NSApp.responds(to: primary) {
      NSApp.sendAction(primary, to: nil, from: nil)
    } else {
      NSApp.sendAction(fallback, to: nil, from: nil)
    }
  }
}
