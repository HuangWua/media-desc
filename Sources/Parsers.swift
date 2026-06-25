import Vision
import CoreGraphics

// MARK: - Legacy VN Type Parsers (macOS 15 fallback, unused by ImageAnalyzer but kept for completeness)

func parseOCR(_ observations: [VNRecognizedTextObservation]) -> [TextBlock] {
    observations.map { obs in
        TextBlock(
            string: obs.topCandidates(1).first?.string ?? "",
            confidence: obs.topCandidates(1).first?.confidence ?? 0,
            boundingBox: obs.boundingBox
        )
    }
}

// MARK: - New Async Vision Type Parsers (macOS 15+)

func parseOCR(_ observations: [RecognizedTextObservation]) -> [TextBlock] {
    observations.map { obs in
        let text: String
        if #available(macOS 26, *) {
            text = obs.transcript
        } else {
            text = ""
        }
        return TextBlock(
            string: text,
            confidence: obs.confidence,
            boundingBox: obs.boundingBox.cgRect
        )
    }
}

func parseDocuments(_ observation: DetectedDocumentObservation?) -> [DocumentRegion] {
    guard let obs = observation else { return [] }
    return [DocumentRegion(
        boundingBox: obs.boundingBox.cgRect,
        rows: []
    )]
}

func parseLabels(_ observations: [ClassificationObservation]) -> [DetectedLabel] {
    observations.map {
        DetectedLabel(identifier: $0.identifier, confidence: $0.confidence)
    }
}

func parseBarcodes(_ observations: [BarcodeObservation]) -> [DetectedBarcode] {
    observations.compactMap { obs -> DetectedBarcode? in
        guard let payload = obs.payloadString else { return nil }
        return DetectedBarcode(
            payload: payload,
            symbology: String(describing: obs.symbology),
            boundingBox: obs.boundingBox.cgRect
        )
    }
}

func assembleFaces(
    _ rects: [CGRect],
    _ landmarks: [FaceObservation.Landmarks2D],
    _ qualities: [Float]
) -> [DetectedFace] {
    let maxCount = max(rects.count, landmarks.count, qualities.count)
    return (0..<maxCount).map { i in
        DetectedFace(
            boundingBox: i < rects.count ? rects[i] : .zero,
            hasLandmarks: i < landmarks.count,
            quality: i < qualities.count ? qualities[i] : nil
        )
    }
}

// MARK: - Legacy VN Type Parsers (kept for compatibility)

func parseDocuments(_ observations: [DetectedDocumentObservation]) -> [DocumentRegion] {
    observations.map { obs in
        DocumentRegion(boundingBox: obs.boundingBox.cgRect, rows: [])
    }
}

// MARK: - Document Region OCR

/// Run OCR on a cropped document region and parse results into rows of text.
/// Groups observations by vertical position (overlapping Y → same row),
/// sorts rows top-to-bottom, text within each row left-to-right.
func parseDocumentOCR(_ observations: [RecognizedTextObservation]) -> [[String]] {
    // Extract text blocks with positional metadata
    let blocks: [(text: String, centerY: CGFloat, minX: CGFloat, lineHeight: CGFloat)] = observations.compactMap { obs in
        let text: String
        if #available(macOS 26, *) {
            text = obs.transcript
        } else {
            return nil
        }
        guard !text.isEmpty else { return nil }
        let rect = obs.boundingBox.cgRect
        return (text, rect.origin.y + rect.height / 2, rect.origin.x, rect.height)
    }

    guard !blocks.isEmpty else { return [] }

    // Sort top-to-bottom (descending centerY — Vision uses bottom-left origin)
    let sorted = blocks.sorted { $0.centerY > $1.centerY }

    var rows: [[String]] = []
    var currentRow: [(text: String, minX: CGFloat)] = []
    var currentCenterY = sorted[0].centerY
    var currentLineHeight = sorted[0].lineHeight

    for block in sorted {
        if abs(block.centerY - currentCenterY) < currentLineHeight * 0.5 {
            currentRow.append((block.text, block.minX))
        } else {
            // Flush current row (left-to-right within row)
            rows.append(currentRow.sorted { $0.minX < $1.minX }.map { $0.text })
            currentRow = [(block.text, block.minX)]
            currentCenterY = block.centerY
            currentLineHeight = block.lineHeight
        }
    }
    // Flush final row
    rows.append(currentRow.sorted { $0.minX < $1.minX }.map { $0.text })

    return rows
}

func parseLabels(_ observations: [VNClassificationObservation]) -> [DetectedLabel] {
    observations.map {
        DetectedLabel(identifier: $0.identifier, confidence: $0.confidence)
    }
}

func parseBarcodes(_ observations: [VNBarcodeObservation]) -> [DetectedBarcode] {
    observations.compactMap { obs in
        guard let payload = obs.payloadStringValue else { return nil }
        return DetectedBarcode(
            payload: payload,
            symbology: obs.symbology.rawValue,
            boundingBox: obs.boundingBox
        )
    }
}

func assembleFaces(
    _ rects: [CGRect],
    _ landmarks: [VNFaceLandmarks2D],
    _ qualities: [Float]
) -> [DetectedFace] {
    let maxCount = max(rects.count, landmarks.count, qualities.count)
    return (0..<maxCount).map { i in
        DetectedFace(
            boundingBox: i < rects.count ? rects[i] : .zero,
            hasLandmarks: i < landmarks.count,
            quality: i < qualities.count ? qualities[i] : nil
        )
    }
}
