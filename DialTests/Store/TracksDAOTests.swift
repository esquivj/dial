// DialTests/Store/TracksDAOTests.swift
import XCTest
import GRDB
@testable import Dial

final class TracksDAOTests: XCTestCase {
  func test_upsert_insertsAndUpdates() throws {
    let dbq = try InMemoryDatabase.make()
    let dao = TracksDAO(dbq: dbq)
    try dao.upsert(.init(uri: "spotify:track:A", name: "Old", albumName: nil, albumArtUrl: nil, durationMs: 200000, artistsJson: nil))
    try dao.upsert(.init(uri: "spotify:track:A", name: "New", albumName: nil, albumArtUrl: nil, durationMs: 200000, artistsJson: nil))
    let t = try dao.fetch(uri: "spotify:track:A")
    XCTAssertEqual(t?.name, "New")
  }
  func test_missingUris_returnsNotIn() throws {
    let dbq = try InMemoryDatabase.make()
    let dao = TracksDAO(dbq: dbq)
    try dao.upsert(.init(uri: "A", name: "x", albumName: nil, albumArtUrl: nil, durationMs: nil, artistsJson: nil))
    XCTAssertEqual(try dao.missingUris(among: ["A","B","C"]), ["B","C"])
  }
}
