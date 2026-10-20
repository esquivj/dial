// DialTests/Sync/MacIdentityTests.swift
import XCTest
@testable import Dial

final class MacIdentityTests: XCTestCase {
  func test_hashedID_isStableHexThatDoesNotRevealTheUUID() {
    let uuid = "12345678-90AB-CDEF-1234-567890ABCDEF"
    let id = MacIdentity.hashedID(hardwareUUID: uuid)

    XCTAssertEqual(id, MacIdentity.hashedID(hardwareUUID: uuid))
    XCTAssertEqual(id.count, 16)
    XCTAssertTrue(id.allSatisfy(\.isHexDigit))
    XCTAssertFalse(uuid.lowercased().replacingOccurrences(of: "-", with: "").contains(id))
    XCTAssertNotEqual(id, MacIdentity.hashedID(hardwareUUID: "12345678-90AB-CDEF-1234-567890ABCDEE"))
  }

  func test_current_isStableOnThisMac() {
    let identity = MacIdentity.current()
    XCTAssertEqual(identity, MacIdentity.current())
    XCTAssertEqual(identity.id.count, 16)
    XCTAssertFalse(identity.name.isEmpty)
  }
}
