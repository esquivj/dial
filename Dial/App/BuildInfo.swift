// Dial/App/BuildInfo.swift
import Foundation

/// Which build this is: version, git commit and build time, as stamped into
/// Info.plist by `scripts/stamp-build-info.sh`. Read the same keys from the
/// command line with
/// `plutil -extract DialGitCommit raw /Applications/Dial.app/Contents/Info.plist`.
struct BuildInfo: Equatable {
  let version: String
  /// Short git SHA, or nil when the build wasn't stamped.
  let commit: String?
  /// Tracked files had uncommitted changes at build time.
  let dirty: Bool
  let builtAt: Date?

  static let current = BuildInfo(infoDictionary: Bundle.main.infoDictionary ?? [:])

  init(version: String, commit: String?, dirty: Bool, builtAt: Date?) {
    self.version = version
    self.commit = commit
    self.dirty = dirty
    self.builtAt = builtAt
  }

  init(infoDictionary info: [String: Any]) {
    let version = (info["CFBundleShortVersionString"] as? String) ?? "?"
    let rawCommit = (info["DialGitCommit"] as? String)?.trimmingCharacters(in: .whitespaces)
    let commit = (rawCommit?.isEmpty == false && rawCommit != "unknown") ? rawCommit : nil
    let builtAt = (info["DialBuildDate"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
    self.init(
      version: version,
      commit: commit,
      dirty: (info["DialGitDirty"] as? Bool) ?? false,
      builtAt: builtAt)
  }

  /// "Dial 0.1.0 · d2997dc · built Nov 11, 2026", with "(modified)" after
  /// the commit for a dirty tree and "unknown" for an unstamped build.
  func summary(timeZone: TimeZone = .current, locale: Locale = .current) -> String {
    var parts = ["Dial \(version)"]
    if let commit {
      parts.append(dirty ? "\(commit) (modified)" : commit)
    } else {
      parts.append("unknown build")
    }
    if let builtAt {
      var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
      style.timeZone = timeZone
      style.locale = locale
      parts.append("built \(builtAt.formatted(style))")
    }
    return parts.joined(separator: " · ")
  }
}
