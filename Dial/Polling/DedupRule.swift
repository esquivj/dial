enum DedupRule {
  /// A play "counts" once it's been heard for 30s OR ≥50% of its duration.
  /// Matches Spotify's documented "stream" definition.
  static func shouldCount(progressMs: Int, durationMs: Int) -> Bool {
    progressMs >= 30_000 ||
      (durationMs > 0 && Double(progressMs) >= Double(durationMs) * 0.5)
  }
}
