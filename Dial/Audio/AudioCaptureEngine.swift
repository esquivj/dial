// Dial/Audio/AudioCaptureEngine.swift
import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Captures *system* audio via ScreenCaptureKit and forwards Float32 mono
/// samples to a callback. ScreenCaptureKit is the only first-party path on
/// macOS that gives us real-time audio for any source — Spotify Desktop,
/// Web Player, YouTube, anything routed through the system mixer.
///
/// The engine intentionally registers only the `.audio` stream output: a
/// minimal video config is still required by the API but no frames are
/// consumed, so the cost stays in the audio path.
///
/// Errors thrown from `start()` correspond to either:
///   - Screen-recording permission denied (most common — surface the state
///     to the UI as "tap to enable").
///   - No display available (extremely rare; usually means the user is in
///     a degenerate state like a remote session).
/// What `VisualizerEngine` needs from a capture source. `AudioCaptureEngine`
/// is the only production conformer; tests drive the engine's start/stop
/// lifecycle with a fake.
protocol AudioCapturing: AnyObject, Sendable {
  var onSamples: (@Sendable ([Float]) -> Void)? { get set }
  var shouldProcessSamples: (@Sendable () -> Bool)? { get set }
  var onStop: (@Sendable (Error) -> Void)? { get set }
  func start() async throws
  func stop() async
}

final class AudioCaptureEngine: NSObject, AudioCapturing, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
  enum CaptureError: Error {
    case noDisplay
    case formatUnavailable
  }

  /// Background queue dedicated to audio buffer delivery. Keeping FFT work
  /// here off the main thread is critical — the main thread drives SwiftUI.
  private let queue = DispatchQueue(label: "com.dial.audio.capture", qos: .userInitiated)
  private var stream: SCStream?

  /// Called on the audio queue with each new chunk of left-channel mono
  /// samples. The engine takes a copy before posting to keep ownership
  /// simple — the Float arrays are inexpensive at the typical 1–4k frame
  /// counts we see from SCStream.
  var onSamples: (@Sendable ([Float]) -> Void)?

  /// Cheap gate checked before extracting/copying audio samples. This lets
  /// the visualizer keep ScreenCaptureKit alive for permission stability
  /// without allocating buffers while no HUD view is watching.
  var shouldProcessSamples: (@Sendable () -> Bool)?

  /// Called on the SCStream's internal queue when the system stops the
  /// stream out from under us — most commonly because the user revoked
  /// Screen Recording permission while we were running, but also covers
  /// "screen sharing took over" and other system-initiated stops.
  ///
  /// VisualizerEngine listens to this and flips its `state` so the UI
  /// shows the "ENABLE VISUALIZER" overlay instead of pretending to be
  /// running over a dead stream.
  var onStop: (@Sendable (Error) -> Void)?

  func start() async throws {
    let content = try await SCShareableContent.excludingDesktopWindows(
      false, onScreenWindowsOnly: false)
    guard let display = content.displays.first else {
      throw CaptureError.noDisplay
    }
    let filter = SCContentFilter(
      display: display, excludingApplications: [], exceptingWindows: [])

    let config = SCStreamConfiguration()
    config.capturesAudio = true
    config.sampleRate = 48_000
    config.channelCount = 2
    // Minimal video config — still required even though we don't register
    // a `.screen` output. 2×2 at 1fps is the smallest the API will accept
    // without complaining.
    config.width = 2
    config.height = 2
    config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
    config.queueDepth = 6
    // Don't capture our own audio output (we have none, but cheap insurance
    // against ever shipping a feature with audio that would feed back).
    config.excludesCurrentProcessAudio = true

    let s = SCStream(filter: filter, configuration: config, delegate: self)
    try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
    // Register a no-op `.screen` output too. SCStream's video subsystem
    // produces frames regardless of intent — if no handler is registered
    // for `.screen`, the runtime floods the console with
    //   _SCStream_RemoteVideoQueueOperationHandlerWithError:1459
    //   stream output NOT found. Dropping frame
    // every frame. The 2×2 @ 1fps config above keeps this cost trivial,
    // and `didOutputSampleBuffer`'s `type == .audio` guard discards the
    // frames as soon as they arrive.
    try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
    try await s.startCapture()
    self.stream = s
  }

  func stop() async {
    if let s = stream {
      try? await s.stopCapture()
    }
    stream = nil
  }

  // MARK: - SCStreamOutput

  func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .audio else { return }
    guard shouldProcessSamples?() ?? true else { return }
    guard let samples = Self.extractLeftChannel(from: sampleBuffer) else { return }
    onSamples?(samples)
  }

  // MARK: - SCStreamDelegate

  func stream(_ stream: SCStream, didStopWithError error: Error) {
    // The previous comment here claimed the UI would "detect via
    // permissionGranted falling stale" — that was wishful thinking,
    // there's no such polling path. Without surfacing this signal,
    // the visualizer would render bars frozen on whatever the last
    // FFT produced and the header label would still say `LIVE · 48k`
    // long after the stream had died.
    //
    // Now: clear our reference to the dead stream and notify whoever
    // owns the engine. VisualizerEngine reads CGPreflightScreenCaptureAccess()
    // to distinguish "user revoked permission" (.denied) from "some
    // other system-initiated stop" (.error).
    self.stream = nil
    onStop?(error)
  }

  // MARK: - Helpers

  /// Pulls the left-channel samples from a non-interleaved Float32 stereo
  /// CMSampleBuffer (the format ScreenCaptureKit delivers per the docs).
  /// Mono mixdown isn't worth the cost for a visualizer — the left channel
  /// already captures the full spectrum for any reasonably mastered track.
  private static func extractLeftChannel(from sampleBuffer: CMSampleBuffer) -> [Float]? {
    guard let formatDescription = sampleBuffer.formatDescription,
      let asbd = formatDescription.audioStreamBasicDescription
    else { return nil }
    let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
    guard frameCount > 0 else { return nil }
    let channels = max(1, Int(asbd.mChannelsPerFrame))
    let flags = asbd.mFormatFlags
    let isFloatPCM = asbd.mFormatID == kAudioFormatLinearPCM
      && (flags & kAudioFormatFlagIsFloat) != 0
    let isUsableLayout = channels == 1
      || (flags & kAudioFormatFlagIsNonInterleaved) != 0
    guard isFloatPCM, isUsableLayout else { return nil }

    // AudioBufferList is a flexible struct — a stereo non-interleaved frame
    // wants two AudioBuffer entries past the nominal one. Allocate raw
    // storage of the right size and bind once.
    let listSize =
      MemoryLayout<AudioBufferList>.size + max(0, channels - 1) * MemoryLayout<AudioBuffer>.size
    let raw = UnsafeMutableRawPointer.allocate(
      byteCount: listSize,
      alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    let listPtr = raw.bindMemory(to: AudioBufferList.self, capacity: 1)

    var blockBuffer: CMBlockBuffer?
    let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer,
      bufferListSizeNeededOut: nil,
      bufferListOut: listPtr,
      bufferListSize: listSize,
      blockBufferAllocator: nil,
      blockBufferMemoryAllocator: nil,
      flags: 0,
      blockBufferOut: &blockBuffer)
    guard status == noErr else { return nil }

    let buffers = UnsafeMutableAudioBufferListPointer(listPtr)
    guard let leftBuffer = buffers.first, let leftData = leftBuffer.mData else { return nil }
    let sampleCount = min(
      frameCount,
      Int(leftBuffer.mDataByteSize) / MemoryLayout<Float>.stride)
    guard sampleCount > 0 else { return nil }
    let floatPtr = leftData.bindMemory(to: Float.self, capacity: sampleCount)
    return Array(UnsafeBufferPointer(start: floatPtr, count: sampleCount))
  }
}
