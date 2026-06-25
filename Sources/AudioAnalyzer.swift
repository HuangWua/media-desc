import Foundation

// MARK: - Public API

func analyzeAudio(_ path: String) async throws -> AudioReport {
    let url = URL(fileURLWithPath: path)

    // transcribeFile defined in VideoAnalyzer.swift (shared within module)
    async let segments = transcribeFile(url)
    async let sound = classifySoundFile(url)

    let (transcript, soundType) = try await (segments, sound)

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
