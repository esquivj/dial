// dialax: windows and accessibility tree of one running process, plus AXPress
// on an element found by its words. dialctl compiles it into
// .build/verify/tools on first use and passes Dial Verify's PID; call it
// through dialctl (`dialctl windows`, `dialctl ax tree`, `dialctl ax press`).
//
//   dialax windows <pid>          on-screen windows: id, level, frame, alpha, title
//   dialax tree <pid> [depth]     accessibility tree, one element per line
//   dialax press <pid> [--exact] <text>
//                                 AXPress the one pressable element whose title,
//                                 label, help or identifier contains <text>
//                                 (--exact: whose title or label is <text>)
//   dialax can-capture            exit 0 if this process may save screenshots
//
// Reading windows needs no permission. The tree and press need the
// Accessibility grant of the app running the shell (AXIsProcessTrusted).
import AppKit
import ApplicationServices

func fail(_ message: String, code: Int32 = 1) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(code)
}

func attr(_ element: AXUIElement, _ name: String) -> AnyObject? {
  var value: AnyObject?
  guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
  return value
}

func text(_ element: AXUIElement, _ name: String) -> String {
  switch attr(element, name) {
  case let string as String: return string
  case let number as NSNumber: return number.stringValue
  default: return ""
  }
}

func children(_ element: AXUIElement) -> [AXUIElement] {
  (attr(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}

func frame(_ element: AXUIElement) -> CGRect? {
  guard let position = attr(element, kAXPositionAttribute), let size = attr(element, kAXSizeAttribute),
    CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
  else { return nil }
  var origin = CGPoint.zero
  var extent = CGSize.zero
  AXValueGetValue(position as! AXValue, .cgPoint, &origin)
  AXValueGetValue(size as! AXValue, .cgSize, &extent)
  return CGRect(origin: origin, size: extent)
}

func actions(_ element: AXUIElement) -> [String] {
  var names: CFArray?
  guard AXUIElementCopyActionNames(element, &names) == .success else { return [] }
  return (names as? [String]) ?? []
}

/// The words an element answers to. SwiftUI's accessibilityLabel and
/// NSView.setAccessibilityLabel both land in AXDescription, shown as label.
let wordAttributes: [(String, String)] = [
  ("title", kAXTitleAttribute), ("label", kAXDescriptionAttribute), ("value", kAXValueAttribute),
  ("help", kAXHelpAttribute), ("id", kAXIdentifierAttribute),
]

func describe(_ element: AXUIElement) -> String {
  let role = text(element, kAXRoleAttribute)
  let subrole = text(element, kAXSubroleAttribute)
  var parts = [subrole.isEmpty ? role : "\(role)/\(subrole)"]
  for (key, name) in wordAttributes {
    let value = text(element, name).replacingOccurrences(of: "\n", with: " ")
    if !value.isEmpty { parts.append("\(key)=\"\(value)\"") }
  }
  if let f = frame(element) {
    parts.append(String(format: "@%.0f,%.0f %.0fx%.0f", f.minX, f.minY, f.width, f.height))
  }
  let shown = actions(element).filter { $0 != "AXScrollToVisible" }
  if !shown.isEmpty { parts.append("[" + shown.joined(separator: ",") + "]") }
  return parts.joined(separator: " ")
}

/// The status item lives in the app's extras menu bar; everything else is a
/// window. A window that hides its contents comes back as the application
/// element itself; those are counted, not walked.
func roots(_ pid: pid_t) -> (elements: [AXUIElement], opaqueWindows: Int) {
  let app = AXUIElementCreateApplication(pid)
  var elements: [AXUIElement] = []
  if let extras = attr(app, "AXExtrasMenuBar"), CFGetTypeID(extras) == AXUIElementGetTypeID() {
    elements.append(extras as! AXUIElement)
  }
  var opaque = 0
  for window in (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
    if CFEqual(window, app) { opaque += 1 } else { elements.append(window) }
  }
  return (elements, opaque)
}

var visited: [AXUIElement] = []

func walk(_ element: AXUIElement, depth: Int, maxDepth: Int, _ visit: (AXUIElement, Int) -> Void) {
  guard !visited.contains(where: { CFEqual($0, element) }) else { return }
  visited.append(element)
  visit(element, depth)
  guard depth < maxDepth else { return }
  for child in children(element) where text(child, kAXRoleAttribute) != kAXApplicationRole {
    walk(child, depth: depth + 1, maxDepth: maxDepth, visit)
  }
}

func requireTrust() {
  if !AXIsProcessTrusted() {
    fail("The app running this shell has no Accessibility grant, so Dial's accessibility tree can't be read. Use computer-use app_screenshot / app_click instead.")
  }
}

func pidArgument(_ args: [String]) -> pid_t {
  guard args.count >= 2, let pid = pid_t(args[1]) else { fail("usage: dialax \(args.first ?? "") <pid> …", code: 2) }
  return pid
}

func windowHint(level: Int, size: CGSize) -> String {
  switch level {
  case -20: return "desktop memory"
  case 25: return "menu bar (status item or strip)"
  case 101: return size.width == 440 && size.height == 440 ? "HUD panel" : "pop-up or menu"
  case 3: return "Settings (floating)"
  case 0: return "window"
  default: return ""
  }
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "windows":
  let pid = pidArgument(args)
  let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
  // CoreGraphics hides other apps' window titles without Screen Recording;
  // accessibility has them, matched by frame.
  let axWindows = AXIsProcessTrusted() ? ((attr(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement]) ?? []) : []
  let titles = axWindows.compactMap { window in frame(window).map { ($0, text(window, kAXTitleAttribute)) } }
  print("id\tlevel\tx\ty\tw\th\talpha\twhat\ttitle")
  for window in info where (window[kCGWindowOwnerPID as String] as? Int) == Int(pid) {
    guard let boundsDict = window[kCGWindowBounds as String], let bounds = CGRect(dictionaryRepresentation: boundsDict as! CFDictionary)
    else { continue }
    let id = window[kCGWindowNumber as String] as? Int ?? 0
    let level = window[kCGWindowLayer as String] as? Int ?? 0
    let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
    let title = titles.first { $0.0.equalTo(bounds) }?.1 ?? ""
    print([
      "\(id)", "\(level)", "\(Int(bounds.minX))", "\(Int(bounds.minY))", "\(Int(bounds.width))", "\(Int(bounds.height))",
      String(format: "%.2f", alpha), windowHint(level: level, size: bounds.size), title,
    ].joined(separator: "\t"))
  }

case "tree":
  let pid = pidArgument(args)
  requireTrust()
  let maxDepth = args.count > 2 ? Int(args[2]) ?? 14 : 14
  let found = roots(pid)
  for root in found.elements {
    walk(root, depth: 0, maxDepth: maxDepth) { element, depth in
      print(String(repeating: "  ", count: depth) + describe(element))
    }
  }
  if found.opaqueWindows > 0 {
    print("(\(found.opaqueWindows) window(s) read as the application element; accessibility can't see inside them)")
  }

case "press":
  let pid = pidArgument(args)
  let exact = args.count == 4 && args[2] == "--exact"
  guard args.count == 3 || exact else { fail("usage: dialax press <pid> [--exact] <text>", code: 2) }
  requireTrust()
  let query = args[args.count - 1]
  let needle = query.lowercased()
  var matches: [AXUIElement] = []
  for root in roots(pid).elements {
    walk(root, depth: 0, maxDepth: 40) { element, _ in
      guard actions(element).contains(kAXPressAction) else { return }
      let names = exact
        ? [kAXTitleAttribute, kAXDescriptionAttribute]
        : [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, kAXIdentifierAttribute]
      let words = names.map { text(element, $0).lowercased() }
      if words.contains(where: { exact ? $0 == needle : $0.contains(needle) }) { matches.append(element) }
    }
  }
  guard matches.count == 1 else {
    let listing = matches.map { "  " + describe($0) }.joined(separator: "\n")
    fail(matches.isEmpty
      ? "nothing pressable matches \"\(query)\" (dialctl ax tree lists what is there)"
      : "\(matches.count) pressable elements match \"\(query)\"; use more of the label, or --exact:\n\(listing)")
  }
  let summary = describe(matches[0])
  let result = AXUIElementPerformAction(matches[0], kAXPressAction as CFString)
  guard result == .success else { fail("AXPress failed (\(result.rawValue)) on \(summary)") }
  print("pressed: \(summary)")

case "can-capture":
  exit(CGPreflightScreenCaptureAccess() ? 0 : 1)

default:
  fail("usage: dialax windows|tree|press <pid> … | dialax can-capture", code: 2)
}
