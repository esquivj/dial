// Dial/App/AppDelegate.swift
import AppKit
import Combine
import CoreText
import Foundation
import GRDB
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
  @Published var coordinator: AppCoordinator?
  private var statusBar: StatusBarController?
  private var dockIcon: DockIconController?
  private var desktopMemory: DesktopMemoryController?
  private var perfAutomationTask: Task<Void, Never>?
  private static let perfAutomationFlagURL = URL(fileURLWithPath: "/tmp/dial-perf-automation")

  func applicationDidFinishLaunching(_ notification: Notification) {
    Self.registerBundledFonts()

    if Self.isRunningUnitTests {
      return
    }

    ProcessInfo.processInfo.disableAutomaticTermination(
      "Dial is running a menu bar UI or headless enrichment job.")
    ProcessInfo.processInfo.disableSuddenTermination()

    // Multi-Mac history (docs/design/multi-mac-history.md):
    // `--export-archive <file>` writes a snapshot for another Mac to merge;
    // `--merge-archive <file> [--dry-run] [--source-name <name>]` merges one.
    if let request = archiveRequestFromArgs() {
      runHeadlessArchive(request)
      return
    }

    // Headless import path: `--import <folder>` runs the same Importer that
    // the Settings UI uses, then exits. Skips all menubar / polling /
    // visualizer setup so the binary acts as a one-shot CLI tool. Useful
    // for bulk-loading the Spotify Extended Streaming History dump without
    // sitting through the UI's progress bar.
    if let importFolder = importFolderFromArgs() {
      runHeadlessImport(folderPath: importFolder)
      return
    }

    if let request = backfillRequestFromArgs() {
      runHeadlessBackfill(request)
      return
    }

    if let tagLimit = tagLimitFromArgs() {
      runHeadlessTagEnrichment(limit: tagLimit)
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
      let statusBar = StatusBarController(coord: coord)
      self.statusBar = statusBar
      self.dockIcon = DockIconController(coord: coord)
      self.desktopMemory = DesktopMemoryController(coord: coord) { [weak statusBar] in
        statusBar?.openHUD()
      }

      // If a token's already in the keychain, start polling immediately.
      // Otherwise present Settings so the user can sign in — without a token,
      // polling would just churn 401s every 3 seconds.
      if coord.settings.signedIn {
        coord.start()
      } else {
        openSettings()
      }
      runPerfAutomationIfRequested(coord: coord)
      Task { await DialFocusFilter.syncState() }
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

  /// Returns the limit passed via `--enrich-tags <limit>` or
  /// `--enrich-tags=<limit>`. Defaults to 250 if the flag is present without
  /// a value.
  private func tagLimitFromArgs() -> Int? {
    let args = CommandLine.arguments
    if let idx = args.firstIndex(of: "--enrich-tags") {
      guard idx + 1 < args.count else { return 250 }
      return Int(args[idx + 1]) ?? 250
    }
    if let arg = args.first(where: { $0.hasPrefix("--enrich-tags=") }) {
      return Int(arg.dropFirst("--enrich-tags=".count)) ?? 250
    }
    return nil
  }

  private struct BackfillRequest {
    let auditOnly: Bool
    let continuous: Bool
    let limit: Int?
  }

  /// `--backfill` runs a durable Spotify/Last.fm enrichment worker.
  /// `--backfill-once` runs one bounded pass.
  /// `--backfill-audit` prints current coverage without making network calls.
  ///
  /// Optional caps: `--backfill=500`, `--backfill 500`, or
  /// `--backfill-limit=500`.
  private func backfillRequestFromArgs() -> BackfillRequest? {
    let args = CommandLine.arguments
    if args.contains("--backfill-audit") {
      return BackfillRequest(auditOnly: true, continuous: false, limit: nil)
    }

    let continuous = args.contains("--backfill")
      || args.contains(where: { $0.hasPrefix("--backfill=") })
    let once = args.contains("--backfill-once")
      || args.contains(where: { $0.hasPrefix("--backfill-once=") })

    guard continuous || once else { return nil }

    let flag = continuous ? "--backfill" : "--backfill-once"
    let inlineLimit = args
      .first(where: { $0.hasPrefix("\(flag)=") })
      .flatMap { Int($0.dropFirst("\(flag)=".count)) }
    let nextLimit: Int? = {
      guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
      return Int(args[idx + 1])
    }()
    let explicitLimit = args
      .first(where: { $0.hasPrefix("--backfill-limit=") })
      .flatMap { Int($0.dropFirst("--backfill-limit=".count)) }

    return BackfillRequest(
      auditOnly: false,
      continuous: continuous,
      limit: explicitLimit ?? inlineLimit ?? nextLimit)
  }

  /// One-shot import that runs the production Importer against the user's
  /// real DB at ~/Library/Application Support/Dial/dial.sqlite, then exits.
  /// Logs progress to stderr so the caller can tail it; bypasses the UI
  /// entirely so this works while the GUI app is *not* running.
  ///
  /// Refuses to run if another Dial process is alive: SQLite WAL handles
  /// concurrent readers fine, but two writers race on the 500ms busy_timeout
  /// and chunks of the import would silently fall through. Better to fail
  /// loudly with a clear "quit Dial first" message than half-import.
  private func runHeadlessImport(folderPath: String) {
    let myPID = ProcessInfo.processInfo.processIdentifier
    let bundleID = Bundle.main.bundleIdentifier ?? "com.dial.Dial"
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
      .filter { $0.processIdentifier != myPID }
    if !others.isEmpty {
      let pids = others.map { String($0.processIdentifier) }.joined(separator: ", ")
      stderr("✗ Dial is already running (PID \(pids)). Quit it first:")
      stderr("    killall Dial && \"$0\" --import \"\(folderPath)\"")
      stderr("  Concurrent writes against the SQLite WAL can drop import rows.")
      exit(1)
    }

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

  private func runHeadlessTagEnrichment(limit: Int) {
    let myPID = ProcessInfo.processInfo.processIdentifier
    let bundleID = Bundle.main.bundleIdentifier ?? "com.dial.Dial"
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
      .filter { $0.processIdentifier != myPID }
    if !others.isEmpty {
      let pids = others.map { String($0.processIdentifier) }.joined(separator: ", ")
      stderr("✗ Dial is already running (PID \(pids)). Quit it first.")
      exit(1)
    }

    let key = LastFMAPIKeyStorage.load()
    guard !key.isEmpty else {
      stderr("✗ Missing Last.fm API key. Save one in Settings first.")
      exit(1)
    }

    Task { @MainActor in
      do {
        let dbURL = try DatabaseStack.defaultURL()
        let dbq = try DatabaseStack(url: dbURL).dbq
        stderr("→ DB: \(dbURL.path)")
        stderr("→ Enriching up to \(limit) artists with Last.fm tags")
        let start = Date()
        let enricher = TagEnricher(dbq: dbq, lastFM: LastFMClient(apiKey: key))
        try await enricher.enrichMissingArtists(rateLimitPerSec: 1, limit: limit)
        let elapsed = Date().timeIntervalSince(start)
        stderr(String(format: "✓ Tag enrichment done in %.1fs", elapsed))
        exit(0)
      } catch {
        stderr("✗ Tag enrichment failed: \(error)")
        exit(1)
      }
    }
  }

  private func runHeadlessBackfill(_ request: BackfillRequest) {
    let myPID = ProcessInfo.processInfo.processIdentifier
    let bundleID = Bundle.main.bundleIdentifier ?? "com.dial.Dial"
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
      .filter { $0.processIdentifier != myPID }
    if !request.auditOnly && !others.isEmpty {
      let pids = others.map { String($0.processIdentifier) }.joined(separator: ", ")
      stderr("✗ Dial is already running (PID \(pids)). Quit it first.")
      stderr("  The backfill worker is a writer; it should not compete with the live menu bar app.")
      exit(1)
    }

    Task { @MainActor in
      do {
        let dbURL = try DatabaseStack.defaultURL()
        let dbq = try DatabaseStack(url: dbURL).dbq
        let clientID = (Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String) ?? ""
        #if DEBUG
        let tokens: TokenStore = FileTokenStore()
        #else
        let tokens: TokenStore = KeychainTokenStore()
        #endif
        let auth = SpotifyAuthService(clientID: clientID, tokenStore: tokens)
        let client = SpotifyClient(tokenStore: tokens, refresh: { try await auth.refresh() })
        let key = LastFMAPIKeyStorage.load()
        let runner = EnrichmentBackfillRunner(
          dbq: dbq,
          client: client,
          lastFMKey: key,
          logger: { [self] message in self.stderr(message) })

        stderr("→ DB: \(dbURL.path)")
        if request.auditOnly {
          let audit = try await runner.audit()
          stderr("→ \(audit.compactSummary)")
          stderr("→ Spotify states: \(Self.formatCounts(audit.spotifyStateCounts))")
          stderr("→ Last.fm states: \(Self.formatCounts(audit.lastFMStateCounts))")
          exit(0)
        }

        guard try tokens.load() != nil else {
          stderr("✗ Missing Spotify token. Open Dial Settings and connect Spotify first.")
          exit(1)
        }

        let mode = request.continuous ? "continuous" : "one-pass"
        let cap = request.limit.map { ", capped at \($0) attempts" } ?? ""
        stderr("→ Backfill mode: \(mode)\(cap)")
        try await runner.run(continuous: request.continuous, maxAttempts: request.limit)
        stderr("✓ Backfill worker finished.")
        exit(0)
      } catch {
        stderr("✗ Backfill failed: \(error)")
        exit(1)
      }
    }
  }

  // MARK: - Headless archive export and merge

  private enum ArchiveRequest {
    case export(path: String)
    case merge(path: String, dryRun: Bool, sourceName: String?)
  }

  private func archiveRequestFromArgs() -> ArchiveRequest? {
    let args = CommandLine.arguments
    if let path = Self.argumentValue("--export-archive", in: args) {
      return .export(path: path)
    }
    if let path = Self.argumentValue("--merge-archive", in: args) {
      return .merge(
        path: path,
        dryRun: args.contains("--dry-run"),
        sourceName: Self.argumentValue("--source-name", in: args))
    }
    return nil
  }

  /// The value given as `--flag value` or `--flag=value`.
  private static func argumentValue(_ flag: String, in args: [String]) -> String? {
    if let idx = args.firstIndex(of: flag), idx + 1 < args.count {
      return args[idx + 1]
    }
    return args.first { $0.hasPrefix("\(flag)=") }.map { String($0.dropFirst(flag.count + 1)) }
  }

  /// Export and dry runs only read the archive, so they're safe while the
  /// menu bar app is running. A real merge swaps the archive file, so it
  /// refuses to run until Dial is quit.
  private func runHeadlessArchive(_ request: ArchiveRequest) {
    if case let .merge(_, dryRun, _) = request, !dryRun {
      let myPID = ProcessInfo.processInfo.processIdentifier
      let bundleID = Bundle.main.bundleIdentifier ?? "com.dial.Dial"
      let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .filter { $0.processIdentifier != myPID }
      if !others.isEmpty {
        let pids = others.map { String($0.processIdentifier) }.joined(separator: ", ")
        stderr("✗ Dial is already running (PID \(pids)). Quit it first, or add --dry-run.")
        exit(1)
      }
    }

    Task { @MainActor in
      do {
        let archiveURL = try DatabaseStack.defaultURL()
        switch request {
        case let .export(path):
          let destination = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
          stderr("→ Exporting \(archiveURL.path)")
          let info = try ArchiveExporter.export(archiveAt: archiveURL, to: destination)
          stderr("✓ Wrote \(destination.path): \(info.playCount.formatted()) plays from \(info.macName)")
        case let .merge(path, dryRun, sourceName):
          var options = ArchiveMerger.Options()
          options.dryRun = dryRun
          options.sourceName = sourceName
          options.log = { [self] line in self.stderr(line) }
          let snapshot = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
          stderr("→ Merging into \(archiveURL.path)\(dryRun ? " (dry run)" : "")")
          let report = try ArchiveMerger(archiveURL: archiveURL, snapshotURL: snapshot, options: options).run()
          for line in report.summaryLines() {
            stderr(line)
          }
        }
        exit(0)
      } catch {
        stderr("✗ \(error)")
        exit(1)
      }
    }
  }

  /// stderr-only logging for the headless import path. Keeps stdout clean
  /// so callers can pipe / parse output if they want.
  private nonisolated func stderr(_ s: String) {
    FileHandle.standardError.write(Data((s + "\n").utf8))
  }

  private static func formatCounts(_ counts: [String: Int]) -> String {
    guard !counts.isEmpty else { return "none" }
    return counts
      .sorted { $0.key < $1.key }
      .map { "\($0.key)=\($0.value.formatted())" }
      .joined(separator: ", ")
  }

  private static func registerBundledFonts() {
    for fontName in ["GeistMono-Regular", "GeistMono-Medium", "GeistPixel-Square"] {
      guard let url = Bundle.main.url(forResource: fontName, withExtension: "ttf") else {
        NSLog("[Dial] missing bundled font: \(fontName)")
        continue
      }
      CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
  }

  private static var isRunningUnitTests: Bool {
    let env = ProcessInfo.processInfo.environment
    return env["XCTestConfigurationFilePath"] != nil
      || NSClassFromString("XCTestCase") != nil
      || NSClassFromString("XCTest.XCTestCase") != nil
  }

  // MARK: - Perf automation

  private struct PerfAutomationRequest {
    let quitWhenDone: Bool
  }

  private func perfAutomationRequestFromArgs() -> PerfAutomationRequest? {
    let args = CommandLine.arguments
    let env = ProcessInfo.processInfo.environment
    let fileRequested = Self.consumePerfAutomationFlag()
    let requested = args.contains("--perf-automation")
      || args.contains(where: { $0.hasPrefix("--perf-automation=") })
      || env["DIAL_PERF_AUTOMATION"] != nil
      || fileRequested
    guard requested else { return nil }

    let keepRunning = args.contains("--perf-automation-no-quit")
      || env["DIAL_PERF_AUTOMATION_NO_QUIT"] == "1"
    return PerfAutomationRequest(quitWhenDone: !keepRunning)
  }

  private static func consumePerfAutomationFlag() -> Bool {
    let url = perfAutomationFlagURL
    guard FileManager.default.fileExists(atPath: url.path) else { return false }
    try? FileManager.default.removeItem(at: url)
    return true
  }

  private func runPerfAutomationIfRequested(coord: AppCoordinator) {
    guard let request = perfAutomationRequestFromArgs(), let statusBar else { return }
    perfAutomationTask?.cancel()
    perfAutomationTask = Task { @MainActor [weak statusBar] in
      guard let statusBar else { return }
      DialPerf.event("perf_automation.started")
      try? await Task.sleep(nanoseconds: 800_000_000)

      for screen in [DropdownScreen.hud, .history, .stats, .pet, .hud] {
        statusBar.showPanelForAutomation(screen: screen)
        try? await Task.sleep(nanoseconds: 280_000_000)
        statusBar.hidePanelForAutomation()
        try? await Task.sleep(nanoseconds: 120_000_000)
      }

      SettingsWindowPresenter.shared.show(coord: coord)
      try? await Task.sleep(nanoseconds: 350_000_000)
      for tab in [SettingsTab.menuBar, .hud, .pet, .general, .hud, .menuBar] {
        NotificationCenter.default.post(name: .dialSelectSettingsTab, object: tab.rawValue)
        try? await Task.sleep(nanoseconds: 250_000_000)
      }

      DialPerf.event("perf_automation.finished")
      if request.quitWhenDone {
        try? await Task.sleep(nanoseconds: 350_000_000)
        NSApp.terminate(nil)
      }
    }
  }

  // MARK: - Settings

  /// Opens (or focuses) the SwiftUI Settings scene.
  private func openSettings() {
    guard let coordinator else { return }
    SettingsWindowPresenter.shared.show(coord: coordinator)
  }
}

@MainActor
final class SettingsWindowPresenter: NSObject, NSWindowDelegate {
  static let shared = SettingsWindowPresenter()

  private var window: NSWindow?

  func show(coord: AppCoordinator) {
    if let window {
      closeDuplicateSettingsWindows(except: window)
      present(window)
      return
    }

    closeDuplicateSettingsWindows()

    let root = SettingsView(
      vm: coord.settings,
      coord: coord,
      onSignIn: { try? await coord.signIn() },
      onImport: { folder in
        Task { await coord.importHistory(from: folder) }
      }
    )

    let hosting = NSHostingController(rootView: root)
    let window = NSWindow(contentViewController: hosting)
    window.title = "Dial Settings"
    window.styleMask = [.titled, .closable, .miniaturizable]
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.setContentSize(NSSize(width: 700, height: 540))
    window.minSize = NSSize(width: 700, height: 540)
    window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    window.center()
    self.window = window
    present(window)
  }

  /// Settings floats so it opens in front, but that would also keep it over
  /// System Settings when a button sends the user there. Drops it to the
  /// normal level until the next `show`.
  func stopFloating() {
    window?.level = .normal
  }

  func windowWillClose(_ notification: Notification) {
    window = nil
  }

  private func present(_ window: NSWindow) {
    NSApp.activate(ignoringOtherApps: true)
    window.level = .floating
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
  }

  private func closeDuplicateSettingsWindows(except expectedWindow: NSWindow? = nil) {
    for candidate in NSApp.windows where candidate !== expectedWindow && candidate.title == "Dial Settings" {
      candidate.close()
    }
  }
}
