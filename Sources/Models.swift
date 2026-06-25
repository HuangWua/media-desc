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

struct Joint2D {
    let name: String        // joint name e.g. "right_shoulder", "left_elbow"
    let x: Float
    let y: Float
    let confidence: Float
}

struct Joint3D {
    let name: String
    let x: Float
    let y: Float
    let z: Float           // depth in meters
    let confidence: Float
}

struct AnimalPoseInfo {
    let identifier: String  // "Dog" / "Cat"
    let joints: [Joint2D]
    let confidence: Float
}

struct ImageReport: Report {
    let source: String
    let mediaType: MediaType = .image

    let language: String                          // 🆕 detected language
    let scene: String                             // 🆕 scene classification
    let ocrBlocks: [TextBlock]
    let documentRegions: [DocumentRegion]
    let labels: [DetectedLabel]
    let barcodes: [DetectedBarcode]
    let faces: [DetectedFace]
    let animals: [DetectedAnimal]
    let rectangles: [DetectedRectangle]
    let contours: [DetectedContour]
    let textRectangles: [DetectedRectangle]       // 🆕 DetectTextRectanglesRequest
    let bodyPoseJoints: [Joint2D]                // 🔧 was hasPersonMask
    let bodyPose3DJoints: [Joint3D]              // 🆕 DetectHumanBodyPose3DRequest
    let handPoseJoints: [Joint2D]                // 🔧 was hasPersonMask
    let animalPose: [AnimalPoseInfo]             // 🆕 DetectAnimalBodyPoseRequest
    let horizonAngle: Double? = nil
    let aesthetics: AestheticsScores?
    let lensSmudge: LensSmudgeResult?
    let attentionSaliency: SaliencyRegion?
    let objectSaliency: SaliencyRegion?
    let humanRectangles: [DetectedRectangle]
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

struct TrajectoryInfo {
    let startTime: TimeInterval
    let duration: TimeInterval
    let description: String
    let confidence: Float
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
    let visualLanguage: String         // 🆕 from frame OCR text
    let transcript: [TranscriptSegment]
    let frames: [FrameSnapshot]
    let sceneChanges: [SceneTransition]
    let trajectories: [TrajectoryInfo]       // 🆕
    let opticalFlowSummary: String?          // 🆕
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
