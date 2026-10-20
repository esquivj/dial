import ServiceManagement
import XCTest
@testable import Dial

@MainActor
final class LaunchAtLoginTests: XCTestCase {
  func test_theSwitchFollowsMacOSLoginItemStatus() {
    XCTAssertTrue(LaunchAtLogin.isOn(.enabled))
    XCTAssertTrue(LaunchAtLogin.isOn(.requiresApproval), "Registered, waiting for the user's OK")
    XCTAssertFalse(LaunchAtLogin.isOn(.notRegistered))
    XCTAssertFalse(LaunchAtLogin.isOn(.notFound), "What macOS reports before the first registration")
  }

  func test_startsOffAndRegistersNothingOnItsOwn() {
    let service = FakeLoginItemService(status: .notRegistered)
    let launchAtLogin = LaunchAtLogin(service: service)
    launchAtLogin.refresh()

    XCTAssertFalse(launchAtLogin.isOn)
    XCTAssertFalse(launchAtLogin.needsApproval)
    XCTAssertEqual(service.calls, [])
  }

  func test_turningOnRegistersAndTurningOffUnregisters() {
    let service = FakeLoginItemService(status: .notRegistered)
    let launchAtLogin = LaunchAtLogin(service: service)

    launchAtLogin.setOn(true)
    XCTAssertTrue(launchAtLogin.isOn)
    XCTAssertEqual(launchAtLogin.status, .enabled)

    launchAtLogin.setOn(false)
    XCTAssertFalse(launchAtLogin.isOn)
    XCTAssertEqual(service.calls, ["register", "unregister"])
    XCTAssertNil(launchAtLogin.problem)
  }

  func test_saysWhenMacOSWantsApprovalAfterTurningOn() {
    let service = FakeLoginItemService(status: .notRegistered)
    service.statusAfterRegister = .requiresApproval
    let launchAtLogin = LaunchAtLogin(service: service)

    launchAtLogin.setOn(true)

    XCTAssertTrue(launchAtLogin.isOn)
    XCTAssertTrue(launchAtLogin.needsApproval)
  }

  func test_aFailedChangeExplainsItselfAndKeepsTheRealStatus() {
    let service = FakeLoginItemService(status: .notRegistered)
    service.registerError = NSError(
      domain: "SMAppServiceErrorDomain", code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Operation not permitted"])
    let launchAtLogin = LaunchAtLogin(service: service)

    launchAtLogin.setOn(true)
    XCTAssertFalse(launchAtLogin.isOn)
    XCTAssertEqual(launchAtLogin.problem, "macOS couldn't turn on launch at login: Operation not permitted")

    service.registerError = nil
    launchAtLogin.setOn(true)
    XCTAssertTrue(launchAtLogin.isOn)
    XCTAssertNil(launchAtLogin.problem)
  }

  func test_refreshPicksUpAChangeMadeInSystemSettings() {
    let service = FakeLoginItemService(status: .enabled)
    let launchAtLogin = LaunchAtLogin(service: service)
    XCTAssertTrue(launchAtLogin.isOn)

    service.status = .requiresApproval
    launchAtLogin.refresh()
    XCTAssertTrue(launchAtLogin.needsApproval)

    service.status = .notRegistered
    launchAtLogin.refresh()
    XCTAssertFalse(launchAtLogin.isOn)
    XCTAssertEqual(service.calls, [])
  }
}

private final class FakeLoginItemService: LoginItemService {
  var status: SMAppService.Status
  var statusAfterRegister: SMAppService.Status = .enabled
  var registerError: Error?
  private(set) var calls: [String] = []

  init(status: SMAppService.Status) {
    self.status = status
  }

  func register() throws {
    calls.append("register")
    if let registerError { throw registerError }
    status = statusAfterRegister
  }

  func unregister() throws {
    calls.append("unregister")
    status = .notRegistered
  }
}
