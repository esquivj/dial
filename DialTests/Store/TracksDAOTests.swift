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

  // MARK: - Merge upsert contract
  //
  // These guard the COALESCE behavior in Track.mergeUpsert. The previous
  // INSERT OR REPLACE semantics would clobber enriched metadata (album art,
  // artists, duration) with NULLs every time a live poll fired against an
  // already-enriched track. The fix is the entire reason we have these
  // tests — if anyone reverts to plain `save()`, the second test below
  // catches it immediately.

  func test_mergeUpsert_preservesEnrichedFieldsAgainstSparseUpsert() throws {
    let dbq = try InMemoryDatabase.make()
    let dao = TracksDAO(dbq: dbq)

    // Seed with a fully enriched track (e.g., what MetadataEnricher would
    // write after a successful /v1/tracks fetch).
    try dao.upsert(.init(
      uri: "spotify:track:A",
      name: "Original",
      albumName: "Original Album",
      albumArtUrl: "https://image.url/cover.jpg",
      durationMs: 200_000,
      artistsJson: "[{\"name\":\"Artist\",\"uri\":\"artist:1\"}]"))

    // Sparse upsert — simulating a live-poll write that came in with
    // partial metadata (or a re-import that doesn't have artwork).
    try dao.upsert(.init(
      uri: "spotify:track:A",
      name: nil,
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: nil))

    let t = try dao.fetch(uri: "spotify:track:A")
    // Every enriched field must survive the sparse upsert untouched.
    XCTAssertEqual(t?.name, "Original")
    XCTAssertEqual(t?.albumName, "Original Album")
    XCTAssertEqual(t?.albumArtUrl, "https://image.url/cover.jpg")
    XCTAssertEqual(t?.durationMs, 200_000)
    XCTAssertEqual(t?.artistsJson, "[{\"name\":\"Artist\",\"uri\":\"artist:1\"}]")
  }

  func test_mergeUpsert_fillsExistingNullFieldsFromIncoming() throws {
    let dbq = try InMemoryDatabase.make()
    let dao = TracksDAO(dbq: dbq)

    // Seed sparse — the state after Importer creates a row from the
    // Streaming History dump (no artwork or duration in that data).
    try dao.upsert(.init(
      uri: "spotify:track:A",
      name: "From import",
      albumName: nil,
      albumArtUrl: nil,
      durationMs: nil,
      artistsJson: nil))

    // Enrichment — MetadataEnricher fills the gaps from /v1/tracks.
    try dao.upsert(.init(
      uri: "spotify:track:A",
      name: "From import",
      albumName: "Album",
      albumArtUrl: "https://art.url",
      durationMs: 180_000,
      artistsJson: "[{\"name\":\"Artist\"}]"))

    let t = try dao.fetch(uri: "spotify:track:A")
    XCTAssertEqual(t?.name, "From import")
    XCTAssertEqual(t?.albumName, "Album")
    XCTAssertEqual(t?.albumArtUrl, "https://art.url")
    XCTAssertEqual(t?.durationMs, 180_000)
    XCTAssertEqual(t?.artistsJson, "[{\"name\":\"Artist\"}]")
  }
}
