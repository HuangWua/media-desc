import Vision
import CoreGraphics
import CryptoKit
import Foundation

// MARK: - Internal Task Result Enum

/// Each Vision task returns a typed result via this enum. Eliminates mutable shared state.
enum VisionTaskResult {
    case ocr([TextBlock])
    case documents([DocumentRegion])
    case labels([DetectedLabel])
    case barcodes([DetectedBarcode])
    case faceRects([CGRect])
    case faceLandmarks([FaceObservation.Landmarks2D])
    case faceQuality([Float])
    case aesthetics(AestheticsScores)
    case lensSmudge(LensSmudgeResult)
    case attentionSaliency(SaliencyRegion)
    case objectSaliency(SaliencyRegion)
    case humanRects([DetectedRectangle])
    case rectangles([DetectedRectangle])
    case contours([DetectedContour])
    case animals([DetectedAnimal])
    case featureHash(String)
    case textRects([DetectedRectangle])
    case bodyPose2D([Joint2D])
    case bodyPose3D([Joint3D])
    case handPose([Joint2D])
    case animalPose([AnimalPoseInfo])
}

// MARK: - Public API

@available(macOS 26.0, *)
func analyzeImage(_ path: String) async throws -> ImageReport {
    guard let cgImage = loadCGImage(path) else {
        throw MediaError.badImage(path)
    }

    let results: [VisionTaskResult] = try await withThrowingTaskGroup(
        of: VisionTaskResult.self
    ) { group in

        // OCR (zh-Hans + en-US bilingual, .accurate)
        group.addTask {
            do {
                var req = RecognizeTextRequest()
                req.recognitionLanguages = [
                    Locale.Language(identifier: "zh-Hans"),
                    Locale.Language(identifier: "en-US")
                ]
                req.recognitionLevel = .accurate
                let r = try await req.perform(on: cgImage)
                return .ocr(parseOCR(r))
            } catch {
                return .ocr([])
            }
        }
        // Document recognition (macOS 26+)
        group.addTask {
            do {
                let r = try await RecognizeDocumentsRequest().perform(on: cgImage)
                return .documents(parseDocuments(r))
            } catch {
                return .documents([])
            }
        }
        // Scene classification
        group.addTask {
            do {
                let r = try await ClassifyImageRequest().perform(on: cgImage)
                return .labels(parseLabels(r))
            } catch {
                return .labels([])
            }
        }
        // Barcode
        group.addTask {
            do {
                let r = try await DetectBarcodesRequest().perform(on: cgImage)
                return .barcodes(parseBarcodes(r))
            } catch {
                return .barcodes([])
            }
        }
        // Face rectangles
        group.addTask {
            do {
                let r = try await DetectFaceRectanglesRequest().perform(on: cgImage)
                return .faceRects(parseFaceRects(r))
            } catch {
                return .faceRects([])
            }
        }
        // Face landmarks
        group.addTask {
            do {
                let r = try await DetectFaceLandmarksRequest().perform(on: cgImage)
                return .faceLandmarks(parseFaceLandmarks(r))
            } catch {
                return .faceLandmarks([])
            }
        }
        // Face capture quality
        group.addTask {
            do {
                let r = try await DetectFaceCaptureQualityRequest().perform(on: cgImage)
                return .faceQuality(parseFaceQuality(r))
            } catch {
                return .faceQuality([])
            }
        }
        // Aesthetics
        group.addTask {
            do {
                let r = try await CalculateImageAestheticsScoresRequest().perform(on: cgImage)
                // macOS 26.5 SDK: CalculateImageAestheticsScoresRequest returns
                // ImageAestheticsScoresObservation with overallScore (Float) and isUtility (Bool).
                // blur/exposure sub-scores are not exposed in the public API — set to 0.
                let scores = AestheticsScores(
                    overall: r.overallScore,
                    blurScore: 0,
                    exposureScore: 0
                )
                return .aesthetics(scores)
            } catch {
                return .aesthetics(AestheticsScores(overall: 0, blurScore: 0, exposureScore: 0))
            }
        }
        // Lens smudge (macOS 26+)
        group.addTask {
            do {
                return try await detectLensSmudge(cgImage)
            } catch {
                return .lensSmudge(LensSmudgeResult(hasSmudge: false, confidence: 0))
            }
        }
        // Attention saliency
        group.addTask {
            do {
                let r = try await GenerateAttentionBasedSaliencyImageRequest().perform(on: cgImage)
                let box = r.salientObjects.first?.boundingBox.cgRect
                return .attentionSaliency(SaliencyRegion(boundingBox: box, isAttentionBased: true))
            } catch {
                return .attentionSaliency(SaliencyRegion(boundingBox: nil, isAttentionBased: true))
            }
        }
        // Objectness saliency
        group.addTask {
            do {
                let r = try await GenerateObjectnessBasedSaliencyImageRequest().perform(on: cgImage)
                let box = r.salientObjects.first?.boundingBox.cgRect
                return .objectSaliency(SaliencyRegion(boundingBox: box, isAttentionBased: false))
            } catch {
                return .objectSaliency(SaliencyRegion(boundingBox: nil, isAttentionBased: false))
            }
        }
        // Rectangles
        group.addTask {
            do {
                let r = try await DetectRectanglesRequest().perform(on: cgImage)
                return .rectangles(parseRectangles(r))
            } catch {
                return .rectangles([])
            }
        }
        // Contours
        group.addTask {
            do {
                let r = try await DetectContoursRequest().perform(on: cgImage)
                return .contours(parseContours(r))
            } catch {
                return .contours([])
            }
        }
        // Text rectangles
        group.addTask {
            do {
                let r = try await DetectTextRectanglesRequest().perform(on: cgImage)
                return .textRects(parseTextRects(r))
            } catch {
                return .textRects([])
            }
        }
        // Animals
        group.addTask {
            do {
                let r = try await RecognizeAnimalsRequest().perform(on: cgImage)
                return .animals(parseAnimals(r))
            } catch {
                return .animals([])
            }
        }
        // Human body pose 2D
        group.addTask {
            do {
                let r = try await DetectHumanBodyPoseRequest().perform(on: cgImage)
                return .bodyPose2D(parseBodyPose2D(r))
            } catch {
                return .bodyPose2D([])
            }
        }
        // Human hand pose
        group.addTask {
            do {
                let r = try await DetectHumanHandPoseRequest().perform(on: cgImage)
                return .handPose(parseHandPose(r))
            } catch {
                return .handPose([])
            }
        }
        // Human body pose 3D
        group.addTask {
            do {
                let r = try await DetectHumanBodyPose3DRequest().perform(on: cgImage)
                return .bodyPose3D(parseBodyPose3D(r))
            } catch {
                return .bodyPose3D([])
            }
        }
        // Animal body pose
        group.addTask {
            do {
                let r = try await DetectAnimalBodyPoseRequest().perform(on: cgImage)
                return .animalPose(parseAnimalPose(r))
            } catch {
                return .animalPose([])
            }
        }
        // Human rectangles
        group.addTask {
            do {
                let r = try await DetectHumanRectanglesRequest().perform(on: cgImage)
                return .humanRects(parseHumanRects(r))
            } catch {
                return .humanRects([])
            }
        }
        // Image feature print
        group.addTask {
            do {
                let r = try await GenerateImageFeaturePrintRequest().perform(on: cgImage)
                var hasher = SHA256()
                hasher.update(data: r.data)
                let hash = hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
                return .featureHash(hash)
            } catch {
                return .featureHash("")
            }
        }
        // Collect results
        var collected: [VisionTaskResult] = []
        for try await result in group {
            collected.append(result)
        }
        return collected
    }

    // ── Post-process: OCR each detected document region ──
    var finalResults = results
    for (index, result) in results.enumerated() {
        guard case .documents(let docs) = result, !docs.isEmpty else { continue }

        let docsWithOCR: [DocumentRegion] = try await withThrowingTaskGroup(
            of: (Int, DocumentRegion).self
        ) { docGroup in
            for (docIndex, doc) in docs.enumerated() {
                docGroup.addTask {
                    guard let cropped = cropCGImage(cgImage, to: doc.boundingBox) else {
                        return (docIndex, doc)
                    }
                    do {
                        let ocrObservations = try await RecognizeTextRequest().perform(on: cropped)
                        let rows = parseDocumentOCR(ocrObservations)
                        return (docIndex, DocumentRegion(
                            boundingBox: doc.boundingBox,
                            rows: rows
                        ))
                    } catch {
                        return (docIndex, doc)
                    }
                }
            }

            var updated = docs
            for try await (docIndex, updatedDoc) in docGroup {
                updated[docIndex] = updatedDoc
            }
            return updated
        }

        finalResults[index] = .documents(docsWithOCR)
    }

    return assembleImageReport(path: path, results: finalResults)
}

// MARK: - Result Assembly (pure function)

func assembleImageReport(path: String, results: [VisionTaskResult]) -> ImageReport {
    var ocr: [TextBlock] = []
    var docs: [DocumentRegion] = []
    var labels: [DetectedLabel] = []
    var barcodes: [DetectedBarcode] = []
    var faceRects: [CGRect] = []
    var faceLandmarks: [FaceObservation.Landmarks2D] = []
    var faceQuality: [Float] = []
    var aesthetics: AestheticsScores? = nil
    var lensSmudge: LensSmudgeResult? = nil
    var attnSaliency: SaliencyRegion? = nil
    var objSaliency: SaliencyRegion? = nil
    var humanRects: [DetectedRectangle] = []
    var rects: [DetectedRectangle] = []
    var contours: [DetectedContour] = []
    var animals: [DetectedAnimal] = []
    var featureHash: String? = nil
    var textRects: [DetectedRectangle] = []
    var bodyPose2D: [Joint2D] = []
    var bodyPose3D: [Joint3D] = []
    var handPose: [Joint2D] = []
    var animalPose: [AnimalPoseInfo] = []

    let scene = deriveSceneTag(labels)

    // Language from OCR text (free — no extra API call)
    let ocrSample = ocr.prefix(5).map(\.string).joined()
    let langCode = detectLanguage(ocrSample)

    for r in results {
        switch r {
        case .ocr(let v): ocr = v
        case .documents(let v): docs = v
        case .labels(let v): labels = v
        case .barcodes(let v): barcodes = v
        case .faceRects(let v): faceRects = v
        case .faceLandmarks(let v): faceLandmarks = v
        case .faceQuality(let v): faceQuality = v
        case .aesthetics(let v): aesthetics = v
        case .lensSmudge(let v): lensSmudge = v
        case .attentionSaliency(let v): attnSaliency = v
        case .objectSaliency(let v): objSaliency = v
        case .humanRects(let v): humanRects = v
        case .rectangles(let v): rects = v
        case .contours(let v): contours = v
        case .animals(let v): animals = v
        case .featureHash(let v): featureHash = v
        case .textRects(let v): textRects = v
        case .bodyPose2D(let v): bodyPose2D = v
        case .bodyPose3D(let v): bodyPose3D = v
        case .handPose(let v): handPose = v
        case .animalPose(let v): animalPose = v
        }
    }

    return ImageReport(
        source: URL(fileURLWithPath: path).lastPathComponent,
        language: langCode,
        scene: scene,
        ocrBlocks: ocr,
        documentRegions: docs,
        labels: labels,
        barcodes: barcodes,
        faces: assembleFaces(faceRects, faceLandmarks, faceQuality),
        animals: animals,
        rectangles: rects,
        contours: contours,
        textRectangles: textRects,
        bodyPoseJoints: bodyPose2D,
        bodyPose3DJoints: bodyPose3D,
        handPoseJoints: handPose,
        animalPose: animalPose,
        aesthetics: aesthetics,
        lensSmudge: lensSmudge,
        attentionSaliency: attnSaliency,
        objectSaliency: objSaliency,
        humanRectangles: humanRects,
        featurePrintHash: featureHash
    )
}

/// Derive scene category from top classification labels for output routing.
func deriveSceneTag(_ labels: [DetectedLabel]) -> String {
    let top3 = labels.prefix(3).map { $0.identifier.lowercased() }
    let documentKeywords = ["document", "screenshot", "printed_page", "receipt", "chart", "diagram", "webpage", "text"]
    let peopleKeywords = ["people", "portrait", "person", "face", "crowd", "indoor", "selfie"]

    for keyword in documentKeywords {
        if top3.contains(where: { $0.contains(keyword) }) { return "document" }
    }
    for keyword in peopleKeywords {
        if top3.contains(where: { $0.contains(keyword) }) { return "people" }
    }
    return "generic"
}

// MARK: - macOS 26 Gated & Fallback Requests

func detectLensSmudge(_ cgImage: CGImage) async throws -> VisionTaskResult {
    if #available(macOS 26, *) {
        let r = try await DetectLensSmudgeRequest().perform(on: cgImage)
        // SmudgeObservation has confidence but no explicit hasSmudge boolean.
        // Infer: any detection with confidence > 0 indicates smudge presence.
        let hasSmudge = r.confidence > 0.5
        return .lensSmudge(LensSmudgeResult(hasSmudge: hasSmudge, confidence: r.confidence))
    }
    throw VisionUnavailableError()
}

struct VisionUnavailableError: Error {}

// MARK: - Long Image OCR Support

/// Classify image as "long" needing sliced OCR.
func isLongImage(_ cgImage: CGImage) -> Bool {
    let h = CGFloat(cgImage.height)
    let w = CGFloat(cgImage.width)
    return h > 4000 || (w > 0 && h / w > 3)
}

/// Single-pass OCR (exact same logic as current TaskGroup OCR task).
@available(macOS 26.0, *)
func singlePassOCR(_ cgImage: CGImage) async throws -> [TextBlock] {
    var req = RecognizeTextRequest()
    req.recognitionLanguages = [
        Locale.Language(identifier: "zh-Hans"),
        Locale.Language(identifier: "en-US")
    ]
    req.recognitionLevel = .accurate
    let r = try await req.perform(on: cgImage)
    return parseOCR(r)
}

/// Crop a horizontal slice from CGImage at pixel Y (top-left origin).
func cropSlicePixel(_ image: CGImage, yStart: CGFloat, yEnd: CGFloat) -> CGImage? {
    let imgW = CGFloat(image.width)
    let imgH = CGFloat(image.height)
    let rect = CGRect(x: 0, y: yStart, width: imgW, height: yEnd - yStart)
    let clamped = rect.integral.intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))
    guard clamped.width > 0, clamped.height > 0 else { return nil }
    return image.cropping(to: clamped)
}

/// Compute safe slice boundaries from text region distribution.
/// Returns array of (yStart, yEnd) pixel tuples, or nil if fallback needed.
func gapAnalysis(
    _ textRects: [DetectedRectangle],
    imageHeight: CGFloat,
    targetSliceHeight: CGFloat = 3000
) -> [(yStart: CGFloat, yEnd: CGFloat)]? {
    guard !textRects.isEmpty else { return nil }

    // Convert to pixel coords (Vision normalized → top-left pixel)
    // Vision: y=0 bottom, y=1 top. Pixel: y=0 top, y=height bottom.
    let pixelRects: [(minY: CGFloat, maxY: CGFloat)] = textRects.map { r in
        let normY = r.boundingBox.origin.y
        let normH = r.boundingBox.height
        let topPixel = (1.0 - normY - normH) * imageHeight   // top of rect in pixels
        let bottomPixel = (1.0 - normY) * imageHeight         // bottom of rect in pixels
        return (max(0, topPixel), min(imageHeight, bottomPixel))
    }.sorted { $0.minY < $1.minY }

    // Coverage check: last rect must reach at least 30% down the image
    if let lastMaxY = pixelRects.last?.maxY, lastMaxY < imageHeight * 0.30 {
        return nil
    }

    // Median line height
    let heights = pixelRects.map { $0.maxY - $0.minY }.sorted()
    let lineH = heights.isEmpty ? 20 : heights[heights.count / 2]
    let gapThreshold = lineH * 2.0

    // Find safe cut points (midpoints of gaps >= gapThreshold)
    var safeCutYs: [CGFloat] = []
    for i in 0..<(pixelRects.count - 1) {
        let gap = pixelRects[i+1].minY - pixelRects[i].maxY
        if gap >= gapThreshold {
            safeCutYs.append(pixelRects[i].maxY + gap / 2.0)
        }
    }

    // If no safe gaps found, fallback
    guard !safeCutYs.isEmpty else { return nil }

    // Build slices: cut at safeCutYs. Only merge slices smaller than 1500px.
    var slices: [(CGFloat, CGFloat)] = []
    var sliceStart: CGFloat = 0
    let minSliceHeight: CGFloat = 1500

    for cutY in safeCutYs {
        if cutY - sliceStart < minSliceHeight { continue } // too small, merge
        slices.append((sliceStart, cutY))
        sliceStart = cutY
    }
    // Final slice to bottom
    if sliceStart < imageHeight {
        slices.append((sliceStart, imageHeight))
    }

    // Add 5% padding on both sides of each slice (but clamp to [0, imageHeight])
    var paddedSlices: [(CGFloat, CGFloat)] = []
    for (start, end) in slices {
        let sliceH = end - start
        let pad = sliceH * 0.05
        let paddedStart = max(0, start - pad)
        let paddedEnd = min(imageHeight, end + pad)
        paddedSlices.append((paddedStart, paddedEnd))
    }

    return paddedSlices.isEmpty ? nil : paddedSlices
}

/// Merge OCR results from multiple slices: remap Y to original image space, dedup overlapping blocks.
func mergeSlicedOCR(_ slices: [(yStart: CGFloat, blocks: [TextBlock])]) -> [TextBlock] {
    // Remap each block's Y coordinate to original image space
    var allBlocks: [TextBlock] = []
    for (yStart, blocks) in slices {
        for block in blocks {
            let originalY = (block.boundingBox?.origin.y ?? 0) + yStart
            let originalRect: CGRect?
            if let box = block.boundingBox {
                originalRect = CGRect(
                    x: box.origin.x,
                    y: originalY,
                    width: box.width,
                    height: box.height
                )
            } else {
                originalRect = nil
            }
            allBlocks.append(TextBlock(
                string: block.string,
                confidence: block.confidence,
                boundingBox: originalRect
            ))
        }
    }

    // Sort by Y
    let sorted = allBlocks.sorted { ($0.boundingBox?.origin.y ?? 0) < ($1.boundingBox?.origin.y ?? 0) }

    // Dedup: if two adjacent blocks have Y diff < 3px and string similarity > 0.6, keep higher confidence
    guard sorted.count > 1 else { return sorted }

    var deduped: [TextBlock] = [sorted[0]]
    for i in 1..<sorted.count {
        let prev = deduped.last!
        let curr = sorted[i]
        let prevY = prev.boundingBox?.origin.y ?? 0
        let currY = curr.boundingBox?.origin.y ?? 0

        if abs(currY - prevY) < 3 && levenshteinSimilarity(prev.string, curr.string) > 0.6 {
            // Duplicate: keep the one with higher confidence
            if curr.confidence > prev.confidence {
                deduped[deduped.count - 1] = curr
            }
        } else {
            deduped.append(curr)
        }
    }

    return deduped
}

/// Fixed-height slicing fallback: 3000px slices with 20% overlap.
@available(macOS 26.0, *)
func fixedHeightOCR(_ cgImage: CGImage) async throws -> [TextBlock] {
    let imgH = CGFloat(cgImage.height)
    let sliceHeight: CGFloat = 3000
    let overlapRatio: CGFloat = 0.20
    let step = sliceHeight * (1.0 - overlapRatio)

    var slices: [(CGFloat, [TextBlock])] = []
    var y: CGFloat = 0

    while y < imgH {
        let yEnd = min(y + sliceHeight, imgH)
        if let cropped = cropSlicePixel(cgImage, yStart: y, yEnd: yEnd) {
            do {
                let blocks = try await singlePassOCR(cropped)
                slices.append((y, blocks))
            } catch {
                // Skip failed slice, continue
            }
        }
        y += step
    }

    return mergeSlicedOCR(slices)
}

/// Long-image OCR orchestrator: gap-guided slicing with fixed-height fallback.
@available(macOS 26.0, *)
func longImageOCR(_ cgImage: CGImage, _ textRects: [DetectedRectangle]) async throws -> [TextBlock] {
    let imgH = CGFloat(cgImage.height)

    // Phase 1: Try gap-guided slicing
    if let sliceBounds = gapAnalysis(textRects, imageHeight: imgH) {
        var slices: [(CGFloat, [TextBlock])] = []
        for (yStart, yEnd) in sliceBounds {
            if let cropped = cropSlicePixel(cgImage, yStart: yStart, yEnd: yEnd) {
                do {
                    let blocks = try await singlePassOCR(cropped)
                    slices.append((yStart, blocks))
                } catch {
                    // Skip failed slice
                }
            }
        }
        if !slices.isEmpty {
            return mergeSlicedOCR(slices)
        }
    }

    // Phase 2: Fallback — fixed-height slicing
    return try await fixedHeightOCR(cgImage)
}
