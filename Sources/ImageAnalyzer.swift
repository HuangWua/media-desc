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
    case personMask(Bool)
    case featureHash(String)
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

        // OCR
        group.addTask {
            do {
                let r = try await RecognizeTextRequest().perform(on: cgImage)
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
        // Animals
        group.addTask {
            do {
                let r = try await RecognizeAnimalsRequest().perform(on: cgImage)
                return .animals(parseAnimals(r))
            } catch {
                return .animals([])
            }
        }
        // Human body pose
        group.addTask {
            do {
                let _ = try await DetectHumanBodyPoseRequest().perform(on: cgImage)
                return .personMask(true)
            } catch {
                return .personMask(false)
            }
        }
        // Human hand pose
        group.addTask {
            do {
                let _ = try await DetectHumanHandPoseRequest().perform(on: cgImage)
                return .personMask(true)
            } catch {
                return .personMask(false)
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
        // Person segmentation
        group.addTask {
            do {
                let _ = try await GeneratePersonSegmentationRequest().perform(on: cgImage)
                return .personMask(true)
            } catch {
                return .personMask(false)
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
    var hasPersonMask = false
    var featureHash: String? = nil

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
        case .personMask(let v): if v { hasPersonMask = true }
        case .featureHash(let v): featureHash = v
        }
    }

    return ImageReport(
        source: URL(fileURLWithPath: path).lastPathComponent,
        ocrBlocks: ocr,
        documentRegions: docs,
        labels: labels,
        barcodes: barcodes,
        faces: assembleFaces(faceRects, faceLandmarks, faceQuality),
        animals: animals,
        rectangles: rects,
        contours: contours,
        aesthetics: aesthetics,
        lensSmudge: lensSmudge,
        attentionSaliency: attnSaliency,
        objectSaliency: objSaliency,
        hasPersonMask: hasPersonMask,
        humanRectangles: humanRects,
        featurePrintHash: featureHash
    )
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
