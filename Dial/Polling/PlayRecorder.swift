import GRDB

struct PlayRecorder {
  let dbq: DatabaseQueue
  func handle(_ event: PlaybackEvent) throws {
    guard case let .countedPlay(uri, ms, at) = event else { return }
    try dbq.write { db in
      var p = Play(playedAt: at, trackUri: uri, msPlayed: ms, source: "live")
      try p.insert(db)
    }
  }
}
