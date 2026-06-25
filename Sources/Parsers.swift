import Vision
import CoreGraphics

// MARK: - Vision → Model Converters

func parseOCR(_ observations: [VNRecognizedTextObservation]) -> [TextBlock] {
    observations.map { obs in
        TextBlock(
            string: obs.topCandidates(1).first?.string ?? "",
            confidence: obs.topCandidates(1).first?.confidence ?? 0,
            boundingBox: obs.boundingBox
        )
    }
}

func parseDocuments(_ observations: [VNDocumentSegmentationObservation]) -> [DocumentRegion] {
    observations.map { obs in
        DocumentRegion(boundingBox: obs.boundingBox, rows: [])
    }
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
