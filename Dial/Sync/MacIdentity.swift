// Dial/Sync/MacIdentity.swift
import CryptoKit
import Foundation
import IOKit
import SystemConfiguration

/// Which Mac an archive belongs to (docs/design/multi-mac-history.md).
///
/// The id is a hash of the hardware UUID, which belongs to the machine. It
/// isn't stored in the database or in UserDefaults, so neither a copied
/// database nor Migration Assistant can give two Macs the same id.
struct MacIdentity: Equatable {
  let id: String
  let name: String

  static func current() -> MacIdentity {
    let name = computerName()
    // No hardware UUID has never been seen on a real Mac; the name at least
    // keeps the id stable on this one.
    let source = hardwareUUID() ?? "name:\(name)"
    return MacIdentity(id: hashedID(hardwareUUID: source), name: name)
  }

  /// 16 hex characters derived from the hardware UUID.
  static func hashedID(hardwareUUID: String) -> String {
    let digest = SHA256.hash(data: Data("dial-mac-id:\(hardwareUUID)".utf8))
    return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
  }

  private static func hardwareUUID() -> String? {
    let service = IOServiceGetMatchingService(
      kIOMainPortDefault,
      IOServiceMatching("IOPlatformExpertDevice"))
    guard service != 0 else { return nil }
    defer { IOObjectRelease(service) }
    let value = IORegistryEntryCreateCFProperty(
      service,
      "IOPlatformUUID" as CFString,
      kCFAllocatorDefault,
      0)
    return value?.takeRetainedValue() as? String
  }

  private static func computerName() -> String {
    if let name = SCDynamicStoreCopyComputerName(nil, nil) as String?, !name.isEmpty {
      return name
    }
    return "This Mac"
  }
}
