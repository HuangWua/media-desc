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
