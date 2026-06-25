import Foundation

// MARK: - Public API

@available(macOS 26.0, *)
func analyzeAudio(_ path: String) async throws -> AudioReport {
    let url = URL(fileURLWithPath: path)

    // analyzeSpeechFile defined in VideoAnalyzer.swift (shared within module)
    let (segments, soundType) = try await analyzeSpeechFile(url)

    let fullText = segments.map(\.text).joined()
    let lang = detectLanguage(fullText)
    let conf = averageConfidence(segments)

    return AudioReport(
        source: url.lastPathComponent,
        language: lang,
        transcript: segments,
        soundType: soundType,
        overallConfidence: conf
    )
}

// MARK: - Helpers

func averageConfidence(_ segments: [TranscriptSegment]) -> Float {
    guard !segments.isEmpty else { return 0 }
    return segments.map(\.confidence).reduce(0, +) / Float(segments.count)
}
