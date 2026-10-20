import Carbon.HIToolbox
import XCTest
@testable import Dial

@MainActor
final class HotkeyControllerTests: XCTestCase {
  private var suiteName: String!
  private var defaults: UserDefaults!
  private var settings: HotkeySettings!
  private var center: FakeHotkeyCenter!
  private var performed: [HotkeyAction] = []
  private var controller: HotkeyController!

  override func setUp() async throws {
    suiteName = "HotkeyControllerTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
    settings = HotkeySettings(defaults: defaults)
    center = FakeHotkeyCenter()
    performed = []
    let menubar = MenubarStripViewModel()
    let router = HotkeyActionRouter(
      menubar: menubar,
      transport: FakeTransport(),
      library: FakeLibrary(),
      openHUD: { [weak self] in self?.performed.append(.openHUD) },
      toggleDesktopMemory: { [weak self] in
        self?.performed.append(.toggleDesktopMemory)
        return true
      },
      flash: { _ in })
    controller = HotkeyController(settings: settings, router: router, center: center)
  }

  override func tearDown() async throws {
    controller = nil
    defaults.removePersistentDomain(forName: suiteName)
  }

  func test_registersEveryDefaultOnLaunch() {
    XCTAssertEqual(center.registered, settings.activeBindings)
    XCTAssertEqual(center.registered.count, HotkeyAction.allCases.count)
  }

  func test_turningShortcutsOffUnregistersThem() async {
    settings.enabled = false
    await settleObservation()
    XCTAssertTrue(center.registered.isEmpty)

    settings.enabled = true
    await settleObservation()
    XCTAssertEqual(center.registered.count, HotkeyAction.allCases.count)
  }

  func test_recordingPausesRegistrationSoThePressReachesSettings() async {
    settings.isRecording = true
    await settleObservation()
    XCTAssertTrue(center.registered.isEmpty)

    settings.isRecording = false
    await settleObservation()
    XCTAssertEqual(center.registered.count, HotkeyAction.allCases.count)
  }

  func test_changedShortcutIsReregistered() async {
    let custom = KeyShortcut(keyCode: kVK_ANSI_K, modifiers: [.control, .option, .command])
    settings.set(custom, for: .like)
    await settleObservation()
    XCTAssertEqual(center.registered[.like], custom)

    settings.set(nil, for: .like)
    await settleObservation()
    XCTAssertNil(center.registered[.like])
  }

  func test_refusedShortcutsAreReportedToSettings() async {
    center.refuse = [HotkeyAction.next.defaultShortcut]
    settings.set(HotkeyAction.next.defaultShortcut, for: .next)  // no-op change…
    settings.enabled = false                                       // …so force a re-register
    await settleObservation()
    settings.enabled = true
    await settleObservation()
    XCTAssertEqual(settings.unavailable, [.next])
  }

  /// Settings changes reach the controller through a main-actor hop.
  private func settleObservation() async {
    for _ in 0..<10 { await Task.yield() }
  }

  func test_pressIsRoutedToTheAction() async throws {
    center.onPress?(.openHUD)
    await settleObservation()
    XCTAssertEqual(performed, [.openHUD])

    center.onPress?(.toggleDesktopMemory)
    await settleObservation()
    XCTAssertEqual(performed, [.openHUD, .toggleDesktopMemory])
  }
}

final class FakeHotkeyCenter: HotkeyRegistering {
  var onPress: ((HotkeyAction) -> Void)?
  var registered: [HotkeyAction: KeyShortcut] = [:]
  var refuse: Set<KeyShortcut> = []

  func register(_ bindings: [HotkeyAction: KeyShortcut]) -> Set<HotkeyAction> {
    registered = bindings.filter { !refuse.contains($0.value) }
    return Set(bindings.filter { refuse.contains($0.value) }.keys)
  }

  func unregisterAll() { registered = [:] }
}
