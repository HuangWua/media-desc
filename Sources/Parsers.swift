import Vision
import CoreGraphics

// MARK: - Observation → Model Converters
// All types verified against docs/macos26-vision-api-reference.md (M1 Pro / macOS 26.5)

// ── 文字/文档 ──

@available(macOS 26, *)
func parseOCR(_ observations: [RecognizedTextObservation]) -> [TextBlock] {
    observations.map { obs in
        TextBlock(
            string: obs.transcript,
            confidence: obs.confidence,
            boundingBox: obs.boundingBox.cgRect
        )
    }
}

@available(macOS 26, *)
func parseDocuments(_ observations: [DocumentObservation]) -> [DocumentRegion] {
    observations.map { doc in
        let rows: [[String]] = doc.document.tables.flatMap { table in
            table.rows.map { row in
                row.map { $0.content.text.transcript }
            }
        }
        let region = doc.document.boundingRegion
        let bbox: CGRect = {
            let pts = region.normalizedPoints
            guard !pts.isEmpty else { return .zero }
            var minX: Float = 1, minY: Float = 1, maxX: Float = 0, maxY: Float = 0
            for pt in pts {
                if pt.x < minX { minX = pt.x }
                if pt.y < minY { minY = pt.y }
                if pt.x > maxX { maxX = pt.x }
                if pt.y > maxY { maxY = pt.y }
            }
            return CGRect(x: CGFloat(minX), y: CGFloat(minY),
                          width: CGFloat(maxX - minX), height: CGFloat(maxY - minY))
        }()
        return DocumentRegion(
            boundingBox: bbox,
            rows: rows
        )
    }
}

// ── 图像理解 ──

func parseLabels(_ observations: [ClassificationObservation]) -> [DetectedLabel] {
    observations.map {
        DetectedLabel(identifier: $0.identifier, confidence: $0.confidence)
    }
}

func parseBarcodes(_ observations: [BarcodeObservation]) -> [DetectedBarcode] {
    observations.compactMap { obs in
        guard let payload = obs.payloadString else { return nil }
        return DetectedBarcode(
            payload: payload,
            symbology: String(describing: obs.symbology),
            boundingBox: obs.boundingBox.cgRect
        )
    }
}

func parseAnimals(_ observations: [RecognizedObjectObservation]) -> [DetectedAnimal] {
    observations.map { obs in
        DetectedAnimal(
            identifier: obs.labels.first?.identifier ?? "unknown",
            confidence: obs.confidence
        )
    }
}

func parseRectangles(_ observations: [RectangleObservation]) -> [DetectedRectangle] {
    observations.map {
        DetectedRectangle(
            boundingBox: $0.boundingBox.cgRect,
            confidence: $0.confidence
        )
    }
}

func parseContours(_ observation: ContoursObservation) -> [DetectedContour] {
    observation.topLevelContours.compactMap { contour in
        guard !contour.normalizedPoints.isEmpty else { return nil }
        var minX: Float = 1.0, minY: Float = 1.0, maxX: Float = 0.0, maxY: Float = 0.0
        for pt in contour.normalizedPoints {
            if pt.x < minX { minX = pt.x }
            if pt.y < minY { minY = pt.y }
            if pt.x > maxX { maxX = pt.x }
            if pt.y > maxY { maxY = pt.y }
        }
        return DetectedContour(
            boundingBox: CGRect(x: CGFloat(minX), y: CGFloat(minY),
                                width: CGFloat(maxX - minX), height: CGFloat(maxY - minY)),
            pointCount: contour.pointCount
        )
    }
}

// ── 人脸 ──

func parseFaceRects(_ observations: [FaceObservation]) -> [CGRect] {
    observations.map { $0.boundingBox.cgRect }
}

func parseFaceLandmarks(_ observations: [FaceObservation]) -> [FaceObservation.Landmarks2D] {
    observations.compactMap { $0.landmarks }
}

func parseFaceQuality(_ observations: [FaceObservation]) -> [Float] {
    observations.compactMap { $0.captureQuality?.score }
}

func assembleFaces(_ rects: [CGRect], _ landmarks: [FaceObservation.Landmarks2D], _ qualities: [Float]) -> [DetectedFace] {
    let count = max(rects.count, max(landmarks.count, qualities.count))
    return (0..<count).map { i in
        DetectedFace(
            boundingBox: i < rects.count ? rects[i] : .zero,
            hasLandmarks: i < landmarks.count,
            quality: i < qualities.count ? qualities[i] : nil
        )
    }
}

// ── 人体 ──

func parseHumanRects(_ observations: [HumanObservation]) -> [DetectedRectangle] {
    observations.map {
        DetectedRectangle(boundingBox: $0.boundingBox.cgRect, confidence: $0.confidence)
    }
}

// MARK: - Document Region OCR

/// Run OCR on a cropped document region and parse results into rows of text.
@available(macOS 26, *)
func parseDocumentOCR(_ observations: [RecognizedTextObservation]) -> [[String]] {
    let blocks: [(text: String, centerY: CGFloat, minX: CGFloat, lineHeight: CGFloat)] = observations.compactMap { obs in
        let text = obs.transcript
        guard !text.isEmpty else { return nil }
        let rect = obs.boundingBox.cgRect
        return (text, rect.origin.y + rect.height / 2, rect.origin.x, rect.height)
    }

    guard !blocks.isEmpty else { return [] }

    let sorted = blocks.sorted { $0.centerY > $1.centerY }

    var rows: [[String]] = []
    var currentRow: [(text: String, minX: CGFloat)] = []
    var currentCenterY = sorted[0].centerY
    var currentLineHeight = sorted[0].lineHeight

    for block in sorted {
        if abs(block.centerY - currentCenterY) < currentLineHeight * 0.5 {
            currentRow.append((block.text, block.minX))
        } else {
            rows.append(currentRow.sorted { $0.minX < $1.minX }.map { $0.text })
            currentRow = [(block.text, block.minX)]
            currentCenterY = block.centerY
            currentLineHeight = block.lineHeight
        }
    }
    rows.append(currentRow.sorted { $0.minX < $1.minX }.map { $0.text })

    return rows
}
