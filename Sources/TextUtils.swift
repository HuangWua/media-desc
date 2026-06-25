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
