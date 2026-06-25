import Foundation

// MARK: - Public API

@available(macOS 26.0, *)
func analyzeAudio(_ path: String) async throws -> AudioReport {
    let url = URL(fileURLWithPath: path)

    let (transcript, soundType) = try await analyzeSpeechFile(url)

    let fullText = transcript.map(\.text).joined()
    let lang = detectLanguage(fullText)
    let conf = averageConfidence(transcript)

    return AudioReport(
        source: url.lastPathComponent,
        language: lang,
        transcript: transcript,
        soundType: soundType,
        overallConfidence: conf
    )
}

// MARK: - Sound Classification

func classifySoundFile(_ url: URL) async throws -> SoundType {
    // SoundAnalysis SNClassifySoundRequest — minimal implementation
    // Returns .unknown for now; enhance with actual SNClassifySoundRequest API later
    return .unknown
}

// MARK: - Helpers

func averageConfidence(_ segments: [TranscriptSegment]) -> Float {
    guard !segments.isEmpty else { return 0 }
    return segments.map(\.confidence).reduce(0, +) / Float(segments.count)
}
