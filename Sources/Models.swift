import Foundation

// MARK: - Report Protocol

protocol Report {
    var source: String { get }
    var mediaType: MediaType { get }
}

enum MediaType: String {
    case image, video, audio
}

// MARK: - Image Analysis Models

struct TextBlock {
    let string: String
    let confidence: Float
    let boundingBox: CGRect?
}

struct DocumentRegion {
    let boundingBox: CGRect
    let rows: [[String]]
}

struct DetectedLabel {
    let identifier: String
    let confidence: Float
}

struct DetectedBarcode {
    let payload: String
    let symbology: String
    let boundingBox: CGRect?
}

struct DetectedFace {
    let boundingBox: CGRect
    let hasLandmarks: Bool
    let quality: Float?
}

struct AestheticsScores {
    let overall: Float
    let blurScore: Float
    let exposureScore: Float
}

struct LensSmudgeResult {
    let hasSmudge: Bool
    let confidence: Float
}

struct SaliencyRegion {
    let boundingBox: CGRect?
    let isAttentionBased: Bool
}

struct DetectedRectangle {
    let boundingBox: CGRect
    let confidence: Float
}

struct DetectedContour {
    let boundingBox: CGRect
    let pointCount: Int
}

struct DetectedAnimal {
    let identifier: String
    let confidence: Float
}

struct ImageReport: Report {
    let source: String
    let mediaType: MediaType = .image

    let ocrBlocks: [TextBlock]
    let documentRegions: [DocumentRegion]
    let labels: [DetectedLabel]
    let barcodes: [DetectedBarcode]
    let faces: [DetectedFace]
    let animals: [DetectedAnimal]
    let rectangles: [DetectedRectangle]
    let contours: [DetectedContour]
    let horizonAngle: Double?
    let aesthetics: AestheticsScores?
    let lensSmudge: LensSmudgeResult?
    let attentionSaliency: SaliencyRegion?
    let objectSaliency: SaliencyRegion?
    let hasPersonMask: Bool
    let featurePrintHash: String?
}

// MARK: - Video Analysis Models

struct FrameSnapshot {
    let timestamp: TimeInterval
    let ocrBlocks: [TextBlock]
    let labels: [DetectedLabel]
    let attentionSaliency: SaliencyRegion?
}

struct SceneTransition {
    let at: TimeInterval
    let fromLabel: String
    let toLabel: String
}

enum SoundType: String {
    case speech, music, noise, mixed, unknown
}

struct TranscriptSegment {
    let timestamp: TimeInterval
    let duration: TimeInterval
    let text: String
    let confidence: Float
}

struct VideoReport: Report {
    let source: String
    let mediaType: MediaType = .video

    let duration: TimeInterval
    let language: String
    let transcript: [TranscriptSegment]
    let frames: [FrameSnapshot]
    let sceneChanges: [SceneTransition]
    let soundType: SoundType
}

// MARK: - Audio Analysis Models

struct AudioReport: Report {
    let source: String
    let mediaType: MediaType = .audio

    let language: String
    let transcript: [TranscriptSegment]
    let soundType: SoundType
    let overallConfidence: Float
}
