import AVFoundation
import Vision
@preconcurrency import Speech
import CoreGraphics

// MARK: - Tuning

let kVideoMaxKeyframes = 12

func keyframeInterval(duration: TimeInterval) -> TimeInterval {
    switch duration {
    case ..<60:  return 5
    case ..<300: return 25
    default:     return duration / Double(kVideoMaxKeyframes)
    }
}

// MARK: - Public API

@available(macOS 26.0, *)
func analyzeVideo(_ path: String) async throws -> VideoReport {
    let url = URL(fileURLWithPath: path)
    let asset = AVURLAsset(url: url)

    guard try await asset.load(.isPlayable) else {
        throw MediaError.badVideo(path)
    }
    let duration = try await asset.load(.duration).seconds

    // Phase 1: keyframes + audio export + speech analysis
    async let frames = extractKeyframes(asset, maxFrames: kVideoMaxKeyframes)

    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("wav")

    let transcript: [TranscriptSegment]
    let soundType: SoundType
    if let track = try? await asset.loadTracks(withMediaType: .audio).first {
        do {
            try await exportAudioTrack(track, to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            (transcript, soundType) = try await analyzeSpeechFile(tempURL)
        } catch {
            (transcript, soundType) = ([], .unknown)
        }
    } else {
        (transcript, soundType) = ([], .unknown)
    }

    let frameImages = try await frames

    // Phase 2: per-frame Vision analysis (unchanged)
    let snapshots = await withTaskGroup(of: FrameSnapshot.self) { group in
        for (ts, img) in frameImages {
            group.addTask { await analyzeFrame(timestamp: ts, image: img) }
        }
        return await group.reduce(into: [FrameSnapshot]()) { $0.append($1) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    // Phase 3: scene change detection — optical flow (macOS 26+)
    let changes = await detectSceneChangesOpticalFlow(frameImages)
    let trajectories = await detectTrajectories(frameImages)

    return VideoReport(
        source: url.lastPathComponent,
        duration: duration,
        language: detectLanguage(transcript.map(\.text).joined()),
        transcript: transcript,
        frames: snapshots,
        sceneChanges: changes,
        trajectories: trajectories,
        opticalFlowSummary: formatOpticalFlowSummary(changes),
        soundType: soundType
    )
}

// MARK: - Keyframe Extraction

func extractKeyframes(_ asset: AVAsset, maxFrames: Int) async throws -> [(TimeInterval, CGImage)] {
    let duration = try await asset.load(.duration).seconds
    guard duration > 0 else { return [] }

    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero

    let interval = keyframeInterval(duration: duration)
    let timePoints = stride(from: 0.0, through: duration, by: interval).prefix(maxFrames)

    var result: [(TimeInterval, CGImage)] = []
    for t in timePoints {
        let cmTime = CMTime(seconds: t, preferredTimescale: 600)
        if let (image, _) = try? await generator.image(at: cmTime) {
            result.append((t, image))
        }
    }
    return result
}

// MARK: - Single Frame Analysis

@available(macOS 26, *)
func analyzeFrame(timestamp: TimeInterval, image: CGImage) async -> FrameSnapshot {
    // Start OCR + classification concurrently; saliency runs inline (avoids type-inference compiler crash)
    async let ocr = try? RecognizeTextRequest().perform(on: image)
    async let cls = try? ClassifyImageRequest().perform(on: image)

    let saliencyBox: CGRect?
    do {
        let sal = try await GenerateAttentionBasedSaliencyImageRequest().perform(on: image)
        saliencyBox = sal.salientObjects.first?.boundingBox.cgRect
    } catch {
        saliencyBox = nil
    }

    let (ocrResult, clsResult) = await (ocr, cls)

    return FrameSnapshot(
        timestamp: timestamp,
        ocrBlocks: ocrResult.map(parseOCR) ?? [],
        labels: clsResult.map(parseLabels) ?? [],
        attentionSaliency: saliencyBox.map {
            SaliencyRegion(boundingBox: $0, isAttentionBased: true)
        }
    )
}

// MARK: - Scene Change Detection

func detectSceneChanges(_ snapshots: [FrameSnapshot]) -> [SceneTransition] {
    guard snapshots.count > 1 else { return [] }
    var changes: [SceneTransition] = []
    for i in 1..<snapshots.count {
        let prev = snapshots[i-1].labels.first
        let curr = snapshots[i].labels.first
        if let p = prev, let c = curr,
           p.identifier != c.identifier,
           p.confidence > 0.5, c.confidence > 0.5 {
            changes.append(SceneTransition(
                at: snapshots[i].timestamp,
                fromLabel: p.identifier,
                toLabel: c.identifier
            ))
        }
    }
    return changes
}

// MARK: - Optical Flow Scene Detection (macOS 26+)

@available(macOS 26.0, *)
func detectSceneChangesOpticalFlow(_ frameImages: [(TimeInterval, CGImage)]) async -> [SceneTransition] {
    guard frameImages.count >= 2 else { return [] }

    var changes: [SceneTransition] = []

    var prevImage: CGImage? = nil
    var prevLabel: String = ""

    for (ts, image) in frameImages {
        defer { prevImage = image }

        guard prevImage != nil else {
            // First frame: get classification label as baseline
            if let r = try? await ClassifyImageRequest().perform(on: image),
               let top = r.first {
                prevLabel = top.identifier
            }
            continue
        }

        // Create new request per frame pair (stateless usage)
        let request = TrackOpticalFlowRequest()
        request.computationAccuracy = .medium

        guard let flow = try? await request.perform(on: image, orientation: CGImagePropertyOrientation.up) else { continue }

        let motion = computeGlobalMotion(flow)
        let threshold: Float = 0.25

        if motion > threshold {
            let currLabel = (try? await ClassifyImageRequest().perform(on: image))?.first?.identifier ?? ""
            changes.append(SceneTransition(at: ts, fromLabel: prevLabel, toLabel: currLabel))
            prevLabel = currLabel
        }
    }

    return changes
}

func computeGlobalMotion(_ flow: OpticalFlowObservation) -> Float {
    // Compute mean displacement magnitude by sampling flow vectors
    // across a normalized 8x8 grid using the flow(at:) query API.
    var sum: Float = 0.0
    var count: Int = 0
    let gridSize = 8
    for i in 0..<gridSize {
        for j in 0..<gridSize {
            let px = CGFloat(i) / CGFloat(gridSize - 1)
            let py = CGFloat(j) / CGFloat(gridSize - 1)
            let (dx, dy) = flow.flow(at: NormalizedPoint(x: px, y: py))
            sum += sqrt(dx * dx + dy * dy)
            count += 1
        }
    }
    return count > 0 ? sum / Float(count) : 0.0
}

// MARK: - Trajectory Detection (macOS 26+)

@available(macOS 26.0, *)
func detectTrajectories(_ frameImages: [(TimeInterval, CGImage)]) async -> [TrajectoryInfo] {
    var trajectories: [TrajectoryInfo] = []

    for (ts, image) in frameImages {
        let request = DetectTrajectoriesRequest(trajectoryLength: 8)

        guard let observations = try? await request.perform(on: image, orientation: CGImagePropertyOrientation.up) else { continue }
        for obs in observations {
            let desc = describeTrajectory(obs)
            let obsDuration = obs.timeRange?.duration.seconds ?? 0
            trajectories.append(TrajectoryInfo(
                startTime: ts - obsDuration,
                duration: obsDuration,
                description: desc,
                confidence: obs.confidence
            ))
        }
    }

    return trajectories
}

func describeTrajectory(_ obs: TrajectoryObservation) -> String {
    // Describe parabolic trajectory in human terms.
    // The observation contains the detected motion path.
    let coeffs = obs.equationCoefficients
    if coeffs != .zero {
        return "parabolic motion (coefficients: 3)"
    }
    return "motion detected"
}

func formatOpticalFlowSummary(_ changes: [SceneTransition]) -> String? {
    guard !changes.isEmpty else { return "No significant scene changes detected." }
    return changes.map { c in
        "\(String(format: "%.0f", c.at))s: \(c.fromLabel) -> \(c.toLabel)"
    }.joined(separator: "; ")
}

// MARK: - Audio Track Export

func exportAudioTrack(_ track: AVAssetTrack, to url: URL) async throws {
    let asset = track.asset!
    let reader = try AVAssetReader(asset: asset)

    let outputSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]

    let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
    reader.add(output)
    guard reader.startReading() else {
        throw reader.error ?? MediaError.noAudioTrack("unknown")
    }

    let writer = try AVAssetWriter(url: url, fileType: .wav)
    let input = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    while let sample = output.copyNextSampleBuffer() {
        while !input.isReadyForMoreMediaData { await Task.yield() }
        input.append(sample)
    }

    input.markAsFinished()
    await writer.finishWriting()
}

// MARK: - Speech Analysis (macOS 26 SpeechAnalyzer)
// (requires @preconcurrency import Speech at top of file)

@available(macOS 26.0, *)
func analyzeSpeechFile(_ url: URL) async throws -> (segments: [TranscriptSegment], soundType: SoundType) {
    let locale = await SpeechTranscriber.supportedLocale(
        equivalentTo: Locale(identifier: "zh-CN")
    ) ?? Locale(identifier: "zh-CN")

    let transcriber = SpeechTranscriber(
        locale: locale,
        preset: .transcription
    )
    let detector = SpeechDetector(
        detectionOptions: SpeechDetector.DetectionOptions(
            sensitivityLevel: .medium
        ),
        reportResults: true
    )

    let audioFile = try AVAudioFile(forReading: url)
    _ = try await SpeechAnalyzer(
        inputAudioFile: audioFile,
        modules: [transcriber, detector],
        finishAfterFile: true
    )

    // Serial collection — SpeechAnalyzer is an actor; concurrent AsyncSequence iteration
    // on the same actor may not be truly parallel. Given 142x realtime, this is fine.
    let segments = try await collectSegments(transcriber)
    let soundType = try await collectSoundType(detector)
    return (segments, soundType)
}

@available(macOS 26.0, *)
func collectSegments(_ transcriber: SpeechTranscriber) async throws -> [TranscriptSegment] {
    var segments: [TranscriptSegment] = []
    for try await result in transcriber.results {
        guard result.isFinal else { continue }
        let text = String(result.text.characters)
        let timestamp = result.range.start.seconds
        let duration = result.range.duration.seconds
        var confidence: Float = 1.0
        // Extract confidence from AttributedString attributes.
        if let attr = result.text.runs.first {
            confidence = Float(attr.transcriptionConfidence ?? 1.0)
        }
        segments.append(TranscriptSegment(
            timestamp: timestamp, duration: duration,
            text: text, confidence: confidence
        ))
    }
    return segments
}

@available(macOS 26.0, *)
func collectSoundType(_ detector: SpeechDetector) async throws -> SoundType {
    var hasSpeech = false
    for try await detection in detector.results {
        if detection.speechDetected { hasSpeech = true }
    }
    return hasSpeech ? .speech : .unknown
}
