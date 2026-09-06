//
// macSubtitleOCRTests.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/19/24.
// Copyright © 2024-2026 Ethan Dye. All rights reserved.
//

import Foundation
@testable import macSubtitleOCR
import Testing

let goodSRTPath = Bundle.module.url(forResource: "sintel.srt", withExtension: nil)!.path
let goodJSONPath = Bundle.module.url(forResource: "sintel.json", withExtension: nil)!.path
#if GITHUB_ACTIONS // Lower thread count for CI to avoid timeouts
let options = ["--json", "--max-threads", "1"]
#else
let options = ["--json"]
#endif

#if FFMPEG
@Test(.serialized, arguments: TestFilePaths.allCases.map(\.path))
func ffmpegDecoder(path: String) async throws {
    let outputPath = URL.temporaryDirectory.path
    let options = [path, outputPath, "--ffmpeg-decoder"] + options
    try await runTest(with: options)
}
#endif

@Test(.serialized, arguments: TestFilePaths.allCases.map(\.path))
func internalDecoder(path: String) async throws {
    let outputPath = URL.temporaryDirectory.path
    let options = [path, outputPath] + options
    try await runTest(with: options)
}

private func runTest(with options: [String]) async throws {
    let outputPath = options[1]

    // Run tests
    var runner = try macSubtitleOCR.parse(options)
    await runner.run()

    try compareOutputs(with: outputPath, track: 0)

    // Compare output for track 1 if it's an MKV file
    if options[0].contains(".mks") {
        try compareOutputs(with: outputPath, track: 1)
    }
}

private func compareOutputs(with outputPath: String, track: Int) throws {
    let srtExpectedOutput = try String(contentsOfFile: goodSRTPath, encoding: .utf8)
    let jsonExpectedOutput = try String(contentsOfFile: goodJSONPath, encoding: .utf8)
    let srtActualOutput = try String(contentsOfFile: "\(outputPath)/track_\(track).srt", encoding: .utf8)
    let jsonActualOutput = try String(contentsOfFile: "\(outputPath)/track_\(track).json", encoding: .utf8)

    let srtMatch = similarityPercentage(of: srtExpectedOutput, and: srtActualOutput)
    let jsonMatch = similarityPercentage(of: jsonExpectedOutput, and: jsonActualOutput)

    #expect(srtMatch >= 85.0) // Lower threshold due to timestamp differences
    #expect(jsonMatch >= 95.0)
}

/// A PGS stream that ends mid-segment must be rejected or parsed, never read past the end of the buffer.
@Test func truncatedPGSStreamIsRejectedNotTrapped() throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: TestFilePaths.sup.path))
    var parsedAnySubtitles = false

    for length in stride(from: 16, to: data.count, by: 4003) {
        let truncated = data.prefix(length)
        do {
            let pgs = try truncated.withUnsafeBytes { try PGS($0) }
            parsedAnySubtitles = parsedAnySubtitles || !pgs.subtitles.isEmpty
            for subtitle in pgs.subtitles {
                _ = subtitle.makeImageSource()
            }
        } catch is macSubtitleOCRError {
            // Reporting malformed input is fine; trapping on it is not.
        }
    }

    // Guard against the parser passing this test by rejecting everything.
    #expect(parsedAnySubtitles)
}

/// Builds a PGS segment: 2 byte magic, 4 byte PTS, 4 byte DTS, 1 byte type, 2 byte payload length.
private func pgsSegment(type: UInt8, payload: [UInt8]) -> [UInt8] {
    var segment: [UInt8] = Array("PG".utf8) + [0, 0, 0, 0] + [0, 0, 0, 0] + [type]
    segment += [UInt8(payload.count >> 8), UInt8(payload.count & 0xFF)]
    return segment + payload
}

/// An object claiming to be larger than the video it is composited onto must be rejected, because
/// decoding it would reserve a buffer of `objectWidth * objectHeight`.
@Test func oversizedObjectIsRejected() throws {
    // Presentation composition segment declaring a 1920x1080 video.
    let presentation = pgsSegment(type: 0x16, payload: [0x07, 0x80, 0x04, 0x38] + [UInt8](repeating: 0, count: 7))
    // Palette definition segment holding a single entry, so a subtitle can be assembled.
    let palette = pgsSegment(type: 0x14, payload: [0x00, 0x00] + [0x00, 0x80, 0x80, 0x80, 0xFF])
    // Object definition segment, first and last in its sequence, claiming the largest dimensions the
    // 16 bit width and height fields allow.
    let object = pgsSegment(type: 0x15, payload: [0x00, 0x00, 0x00, 0xC0] + [0x00, 0x00, 0x04] +
        [0xFF, 0xFF, 0xFF, 0xFF] + [0x00, 0x00])

    let stream = Data(presentation + palette + object + pgsSegment(type: 0x80, payload: []))

    do {
        _ = try stream.withUnsafeBytes { try PGS($0) }
        Issue.record("Expected the oversized object to be rejected")
    } catch macSubtitleOCRError.invalidODSDimensions {
        // Expected: rejected on its dimensions, before anything is decoded for it.
    }
}
