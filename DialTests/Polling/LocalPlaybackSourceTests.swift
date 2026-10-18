import XCTest
@testable import Dial

/// PollingService with the Spotify app as the primary source. Each test
/// replays one scripted session through both the new service and the old
/// Web-API-only loop (`LegacyPollingService`) and checks counted plays match.
final class LocalPlaybackSourceTests: XCTestCase {
  private typealias World = SimulatedSpotify

  // MARK: Local only

  func test_localOnly_appIsAuthoritative_countsMatchLegacy_fewerWebCalls() async throws {
    let a = World.track("a", seconds: 200), b = World.track("b", seconds: 180)
    let c = World.track("c", seconds: 150), d = World.track("d", seconds: 240)
    let script: (World) -> Void = { w in
      w.play(a, for: 200)
        .play(b, for: 10)                        // skip before 30s: not counted
        .play(c, for: 150)
        .play(d, for: 20).pause(d, atMs: 20_000, for: 60).play(d, for: 220, fromMs: 20_000)
    }

    let current = World(); script(current)
    let run = try await current.runCurrent(for: current.sessionLength)
    let legacy = World(); script(legacy)
    let before = try await legacy.runLegacy(for: legacy.sessionLength)

    XCTAssertEqual(run.countedUris, [a.uri, c.uri, d.uri])
    XCTAssertEqual(run.countedUris, before.countedUris)
    XCTAssertEqual(run.statuses, [.spotifyApp])
    XCTAssertLessThan(run.webCalls, before.webCalls / 5, "web calls: \(run.webCalls) vs \(before.webCalls)")

    // The app gives no artist URIs; the Web API side channel fills them in
    // for the same track without a second count.
    XCTAssertTrue(run.events.contains(.started(
      trackUri: a.uri, name: a.name, artistName: "Artist", artistUri: a.artistUri,
      artists: [.init(name: "Artist", uri: a.artistUri)], albumName: "Album",
      artUrl: "https://i.scdn.co/\(a.uri)", durationMs: a.durationMs, at: run.startedAt(a.uri, withArtist: true)!)))
    XCTAssertEqual(run.events.filter { $0 == .modesChanged(shuffle: false, repeatMode: .off) }.count, 1)
  }

  // MARK: Remote only

  func test_remoteOnly_appClosed_behavesLikeLegacy() async throws {
    let a = World.track("a", seconds: 200), b = World.track("b", seconds: 25), c = World.track("c", seconds: 90)
    let script: (World) -> Void = { w in
      w.appRunning = []
      w.play(a, on: .phone, for: 200).play(b, on: .phone, for: 25).play(c, on: .phone, for: 40)
    }

    let current = World(); script(current)
    let run = try await current.runCurrent(for: current.sessionLength)
    let legacy = World(); script(legacy)
    let before = try await legacy.runLegacy(for: legacy.sessionLength)

    XCTAssertEqual(run.countedUris, [a.uri, b.uri, c.uri])   // b: 25s track, ≥50% heard
    XCTAssertEqual(run.countedUris, before.countedUris)
    XCTAssertEqual(run.statuses, [.webAPI(.appNotRunning)])
    XCTAssertEqual(Double(run.webCalls), Double(before.webCalls), accuracy: 2)
    XCTAssertEqual(run.localReads, run.webCalls, "one cheap app check per web cycle, no extra web calls")
  }

  func test_remoteOnly_appOpenButIdle_findsPhonePlayback() async throws {
    let a = World.track("a", seconds: 200), b = World.track("b", seconds: 160)
    let script: (World) -> Void = { w in
      w.play(a, on: .phone, for: 200).play(b, on: .phone, for: 160)
    }

    let current = World(); script(current)
    let run = try await current.runCurrent(for: current.sessionLength)
    let legacy = World(); script(legacy)
    let before = try await legacy.runLegacy(for: legacy.sessionLength)

    XCTAssertEqual(run.countedUris, [a.uri, b.uri])
    XCTAssertEqual(run.countedUris, before.countedUris)
    XCTAssertEqual(run.statuses.last, .webAPI(.remoteDevice))
  }

  // MARK: Handoff

  func test_handoffMidTrack_countsOnce() async throws {
    let x = World.track("x", seconds: 240), y = World.track("y", seconds: 120), z = World.track("z", seconds: 150)
    let script: (World) -> Void = { w in
      w.play(x, on: .mac, for: 20)                           // Mac → phone before the 30s mark…
        .play(x, on: .phone, for: 40, fromMs: 20_000)        // …crosses 30s on the phone…
        .play(x, on: .mac, for: 180, fromMs: 60_000)         // …and comes back to the Mac.
        .play(y, on: .phone, for: 120)
        .play(z, on: .mac, for: 150)
    }

    let current = World(); script(current)
    let run = try await current.runCurrent(for: current.sessionLength)
    let legacy = World(); script(legacy)
    let before = try await legacy.runLegacy(for: legacy.sessionLength)

    XCTAssertEqual(run.countedUris, [x.uri, y.uri, z.uri])
    XCTAssertEqual(run.countedUris, before.countedUris)
    XCTAssertTrue(run.statuses.contains(.spotifyApp))
    XCTAssertTrue(run.statuses.contains(.webAPI(.remoteDevice)))
  }

  func test_spotifyQuitMidTrack_webTakesOverWithoutRecount() async throws {
    let x = World.track("x", seconds: 240)
    let script: (World) -> Void = { w in
      w.appRunning = [0...50]
      w.play(x, on: .mac, for: 45)                       // counted locally at 30s
        .play(x, on: .phone, for: 150, fromMs: 45_000)   // app quits; phone carries on
    }

    let current = World(); script(current)
    let run = try await current.runCurrent(for: current.sessionLength)
    let legacy = World(); script(legacy)
    let before = try await legacy.runLegacy(for: legacy.sessionLength)

    XCTAssertEqual(run.countedUris, [x.uri])
    XCTAssertEqual(run.countedUris, before.countedUris)
    XCTAssertEqual(run.statuses.last, .webAPI(.appNotRunning))
  }

  // MARK: Permission

  func test_accessDenied_fallsBackToWebAPI_countsMatchLegacy() async throws {
    let a = World.track("a", seconds: 200), b = World.track("b", seconds: 15), c = World.track("c", seconds: 180)
    let script: (World) -> Void = { w in
      w.forcedLocalReading = .accessDenied
      w.play(a, for: 200).play(b, for: 5).play(c, for: 180)
    }

    let current = World(); script(current)
    let run = try await current.runCurrent(for: current.sessionLength)
    let legacy = World(); script(legacy)
    let before = try await legacy.runLegacy(for: legacy.sessionLength)

    XCTAssertEqual(run.countedUris, [a.uri, c.uri])
    XCTAssertEqual(run.countedUris, before.countedUris)
    XCTAssertEqual(run.statuses, [.webAPI(.accessDenied)])
    XCTAssertFalse(run.statuses.last!.readsSpotifyApp, "raw notifications must keep feeding the HUD")
    // Notifications still wake the loop, but they never buy extra web calls.
    XCTAssertLessThanOrEqual(run.webCalls, before.webCalls + 1)
  }

  func test_accessPending_usesWebAPIUntilAnswered() async throws {
    let a = World.track("a", seconds: 200)
    let world = World()
    world.forcedLocalReading = .accessPending
    world.play(a, for: 200)
    let run = try await world.runCurrent(for: 200)
    XCTAssertEqual(run.statuses, [.webAPI(.accessPending)])
    XCTAssertEqual(run.countedUris, [a.uri])
  }

  // MARK: 30-minute session

  /// A realistic half hour: full plays, early and late skips, a pause, a
  /// short track, a hop to the phone and back, and Spotify quitting at the
  /// end. Counted plays must match the old loop exactly; the play start
  /// time may move by the Web API's lag, nothing more.
  func test_thirtyMinuteSession_countedPlaysMatchLegacy() async throws {
    let tracks = (0..<12).map { World.track("s\($0)", seconds: [214, 187, 243, 25, 198, 176, 305, 162, 221, 190, 233, 201][$0]) }
    let script: (World) -> Void = { w in
      w.appRunning = [0...1_700]   // quits after s10, before s11 on the phone
      w.play(tracks[0], for: 214)
        .play(tracks[1], for: 12)                                 // early skip
        .play(tracks[2], for: 243)
        .play(tracks[3], for: 25)                                 // short track, full
        .play(tracks[4], for: 41)                                 // late skip, counts
        .play(tracks[5], for: 70).pause(tracks[5], atMs: 70_000, for: 95).play(tracks[5], for: 106, fromMs: 70_000)
        .play(tracks[6], for: 305)
        .play(tracks[7], on: .phone, for: 162)                     // walked away with the phone
        .play(tracks[8], on: .phone, for: 50).play(tracks[8], on: .mac, for: 171, fromMs: 50_000)
        .play(tracks[9], for: 8)                                  // skip
        .play(tracks[10], for: 190)
        .play(tracks[11], on: .phone, for: 201)                    // app quit near the end
    }

    let current = World(); script(current)
    XCTAssertGreaterThanOrEqual(current.sessionLength, 1_800)
    let run = try await current.runCurrent(for: current.sessionLength)
    let legacy = World(); script(legacy)
    let before = try await legacy.runLegacy(for: legacy.sessionLength)

    let expected = [0, 2, 3, 4, 5, 6, 7, 8, 10, 11].map { tracks[$0].uri }
    XCTAssertEqual(before.countedUris, expected)
    XCTAssertEqual(run.countedUris, expected)
    for (now, then) in zip(run.countedPlays, before.countedPlays) {
      XCTAssertEqual(Double(now.at), Double(then.at), accuracy: 3, "\(now.uri) start time")
    }
    XCTAssertLessThan(run.webCalls, before.webCalls / 3, "web calls: \(run.webCalls) vs \(before.webCalls)")
    print("[30-min session] counted \(run.countedUris.count) == \(before.countedUris.count); web calls \(run.webCalls) vs \(before.webCalls)")
  }

  // MARK: Calls per hour

  func test_webCallsPerHour() async throws {
    func hour(_ build: (World) -> Void) async throws -> (now: Int, before: Int) {
      let a = World(); build(a)
      let b = World(); build(b)
      return (try await a.runCurrent(for: 3_600).webCalls, try await b.runLegacy(for: 3_600).webCalls)
    }
    let tracks = (0..<20).map { World.track("h\($0)", seconds: 200) }

    let macPlaying = try await hour { w in tracks.forEach { w.play($0, for: 200) } }
    let appIdle = try await hour { w in w.pause(tracks[0], atMs: 40_000, for: 3_700) }
    let phonePlaying = try await hour { w in tracks.forEach { w.play($0, on: .phone, for: 200) } }
    let appClosed = try await hour { w in w.appRunning = []; tracks.forEach { w.play($0, on: .phone, for: 200) } }

    print("""
      [web calls/hour] Spotify app playing: \(macPlaying.now) (was \(macPlaying.before))
      [web calls/hour] Spotify app idle:    \(appIdle.now) (was \(appIdle.before))
      [web calls/hour] phone, app open:     \(phonePlaying.now) (was \(phonePlaying.before))
      [web calls/hour] Spotify app closed:  \(appClosed.now) (was \(appClosed.before))
      """)
    XCTAssertLessThan(macPlaying.now, 200)
    XCTAssertLessThan(appIdle.now, 400)
    XCTAssertLessThanOrEqual(phonePlaying.now, phonePlaying.before)
    XCTAssertLessThanOrEqual(appClosed.now, appClosed.before)
  }

  // MARK: Pieces

  func test_wakeEndsWaitEarly() async {
    let scheduler = WakeablePollScheduler()
    let started = Date()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { scheduler.wake() }
    await scheduler.wait(upTo: 5)
    XCTAssertLessThan(Date().timeIntervalSince(started), 1)
  }

  func test_wakeBeforeWaitIsRemembered() async {
    let scheduler = WakeablePollScheduler()
    scheduler.wake()
    let started = Date()
    await scheduler.wait(upTo: 5)
    XCTAssertLessThan(Date().timeIntervalSince(started), 1)
  }

  func test_countableTrackURI_matchesWebAPIItems() {
    XCTAssertEqual(SpotifyAppleEventsSource.countableTrackURI("spotify:track:abc"), "spotify:track:abc")
    XCTAssertEqual(SpotifyAppleEventsSource.countableTrackURI("spotify:local:A:B:C:120"), "spotify:local:A:B:C:120")
    XCTAssertNil(SpotifyAppleEventsSource.countableTrackURI("spotify:episode:abc"))
    XCTAssertNil(SpotifyAppleEventsSource.countableTrackURI("spotify:ad:abc"))
    XCTAssertNil(SpotifyAppleEventsSource.countableTrackURI(""))
  }

  func test_propertySpecifier_isAnObjectSpecifierLikeAppleScriptBuilds() {
    let code: FourCharCode = 0x70506C53  // 'pPlS' player state
    let track: FourCharCode = 0x7054726B // 'pTrk' current track
    let spec = SpotifyAppleEventsSource.propertySpecifier(code, of: .null())
    XCTAssertEqual(spec.descriptorType, DescType(typeObjectSpecifier))
    XCTAssertEqual(spec.forKeyword(AEKeyword(keyAEDesiredClass))?.typeCodeValue, DescType(typeProperty))
    XCTAssertEqual(spec.forKeyword(AEKeyword(keyAEKeyForm))?.enumCodeValue, DescType(formPropertyID))
    XCTAssertEqual(spec.forKeyword(AEKeyword(keyAEKeyData))?.typeCodeValue, code)
    XCTAssertEqual(spec.forKeyword(AEKeyword(keyAEContainer))?.descriptorType, DescType(typeNull))

    let nested = SpotifyAppleEventsSource.propertySpecifier(code, of: SpotifyAppleEventsSource.propertySpecifier(track, of: .null()))
    XCTAssertEqual(nested.forKeyword(AEKeyword(keyAEContainer))?.forKeyword(AEKeyword(keyAEKeyData))?.typeCodeValue, track)
  }

  func test_durationMilliseconds_acceptsBothUnits() {
    XCTAssertEqual(SpotifyAppleEventsSource.durationMilliseconds(214_000), 214_000)
    XCTAssertEqual(SpotifyAppleEventsSource.durationMilliseconds(214), 214_000)
    XCTAssertEqual(SpotifyAppleEventsSource.durationMilliseconds(0), 0)
  }
}

private extension SimulationRun {
  func startedAt(_ uri: String, withArtist: Bool) -> Int64? {
    for e in events {
      if case let .started(u, _, _, artistUri, _, _, _, _, at) = e, u == uri, (artistUri != nil) == withArtist {
        return at
      }
    }
    return nil
  }
}
