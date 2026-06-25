import NaturalLanguage

/// Detect the dominant language of `text`. Returns BCP-47 code like "zh-Hans", "en", "ja";
/// returns "unknown" for empty or indeterminate text.
func detectLanguage(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "unknown" }

    let recognizer = NLLanguageRecognizer()
    recognizer.processString(trimmed)
    return recognizer.dominantLanguage?.rawValue ?? "unknown"
}

/// Sentiment polarity score in [-1.0, 1.0]. Negative = negative sentiment, positive = positive, 0 = neutral.
func sentimentScore(_ text: String) -> Double {
    let tagger = NLTagger(tagSchemes: [.sentimentScore])
    tagger.string = text
    let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
    return Double(tag?.rawValue ?? "0") ?? 0
}

import Vision
import CoreGraphics

// MARK: - Image Language Detection

/// Fast OCR on image → NLLanguageRecognizer → Vision recognitionLanguages mapping.
/// Used to configure RecognizeTextRequest for accurate Chinese/Japanese/English OCR.
func detectImageLanguage(_ cgImage: CGImage) async -> (code: String, visionLanguages: [Locale.Language]) {
    // 1. Fast OCR: accuracy=.fast, Chinese+English bilingual
    let req = RecognizeTextRequest()
    req.recognitionLanguages = [
        Locale.Language(identifier: "zh-Hans"),
        Locale.Language(identifier: "en-US")
    ]
    req.recognitionLevel = .fast
    guard let observations = try? await req.perform(on: cgImage) else {
        return ("unknown", [
            Locale.Language(identifier: "zh-Hans"),
            Locale.Language(identifier: "en-US")
        ])
    }

    // 2. Take first 200 characters from top-5 text blocks
    let sample = observations.prefix(5).map(\.transcript).joined()
    guard !sample.isEmpty else {
        return ("unknown", [
            Locale.Language(identifier: "zh-Hans"),
            Locale.Language(identifier: "en-US")
        ])
    }

    // 3. NLLanguageRecognizer
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(sample)
    let dominant = recognizer.dominantLanguage

    // 4. Map to Vision Locale.Language (dominant first, English fallback)
    switch dominant?.rawValue {
    case "zh-Hans":
        return ("zh-Hans", [
            Locale.Language(identifier: "zh-Hans"),
            Locale.Language(identifier: "en-US")
        ])
    case "ja":
        return ("ja", [
            Locale.Language(identifier: "ja"),
            Locale.Language(identifier: "zh-Hans"),
            Locale.Language(identifier: "en-US")
        ])
    case "ko":
        return ("ko", [
            Locale.Language(identifier: "ko"),
            Locale.Language(identifier: "en-US")
        ])
    case "en":
        return ("en-US", [
            Locale.Language(identifier: "en-US"),
            Locale.Language(identifier: "zh-Hans")
        ])
    default:
        return (dominant?.rawValue ?? "unknown", [
            Locale.Language(identifier: "zh-Hans"),
            Locale.Language(identifier: "en-US")
        ])
    }
}
