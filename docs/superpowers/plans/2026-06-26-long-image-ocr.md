# Long Image OCR — 安全切片实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 超长图 (height > 4000px 或 宽高比 > 1:3) 通过 DetectTextRectanglesRequest 引导的安全切片实现完整 OCR，不切断文字。

**Architecture:** OCR 从 TaskGroup 移除 → 收集 20 个 Vision 任务结果后串行执行 → 短图走现有单次 OCR，长图走 `longImageOCR()`：先用 textRects 做 gapAnalysis 找安全切割线，在段落间隙处切片逐片 OCR → 坐标还原合并 + Levenshtein 去重。无自然间隙时回退固定切片。

**Tech Stack:** Swift 5.9+, macOS 26 Vision, CoreGraphics, NaturalLanguage

---

### Task 1: TextUtils.swift — Levenshtein 距离

**Files:**
- Modify: `~/Study/media-desc/Sources/TextUtils.swift` (append at end)

- [ ] **Step 1: Add Levenshtein distance function**

在文件末尾追加：

```swift
// MARK: - String Distance

/// Levenshtein distance between two strings. Returns normalized similarity in [0.0, 1.0].
/// 1.0 = identical, 0.0 = completely different.
func levenshteinSimilarity(_ s1: String, _ s2: String) -> Double {
    let a = Array(s1), b = Array(s2)
    let n = a.count, m = b.count
    guard max(n, m) > 0 else { return 1.0 }
    guard n > 0 else { return 0.0 }
    guard m > 0 else { return 0.0 }

    var prev = Array(0...m)
    var curr = Array(repeating: 0, count: m + 1)

    for i in 1...n {
        curr[0] = i
        for j in 1...m {
            if a[i-1] == b[j-1] {
                curr[j] = prev[j-1]
            } else {
                curr[j] = 1 + min(prev[j], min(curr[j-1], prev[j-1]))
            }
        }
        swap(&prev, &curr)
    }

    return 1.0 - Double(prev[m]) / Double(max(n, m))
}
```

- [ ] **Step 2: Build to verify**

```bash
cd ~/Study/media-desc && swift build 2>&1 | tail -3
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd ~/Study/media-desc && git add Sources/TextUtils.swift && git commit -m "feat: add levenshteinSimilarity for OCR text dedup"
```

---

### Task 2: ImageAnalyzer.swift — 辅助函数 + gapAnalysis

**Files:**
- Modify: `~/Study/media-desc/Sources/ImageAnalyzer.swift`

- [ ] **Step 1: Add isLongImage(), singlePassOCR(), cropSlicePixel()**

在 `VisionUnavailableError` struct 之后（文件最末尾）追加：

```swift
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
    // This way any safe gap above 1500px becomes a cut — much better than
    // crashing into Vision's 19000px limit on a single giant slice.
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
```

- [ ] **Step 2: Build to verify**

```bash
cd ~/Study/media-desc && swift build 2>&1
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd ~/Study/media-desc && git add Sources/ImageAnalyzer.swift && git commit -m "feat: add isLongImage, singlePassOCR, cropSlicePixel, gapAnalysis"
```

---

### Task 3: ImageAnalyzer.swift — mergeSlicedOCR + longImageOCR + 固定切片回退

**Files:**
- Modify: `~/Study/media-desc/Sources/ImageAnalyzer.swift`

- [ ] **Step 1: Add mergeSlicedOCR() and longImageOCR()**

在 Task 2 添加的代码之后追加：

```swift
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
```

- [ ] **Step 2: Build to verify**

```bash
cd ~/Study/media-desc && swift build 2>&1
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd ~/Study/media-desc && git add Sources/ImageAnalyzer.swift && git commit -m "feat: add mergeSlicedOCR, longImageOCR, fixedHeightOCR fallback"
```

---

### Task 4: ImageAnalyzer.swift — 修改 analyzeImage() 集成新 OCR 流程

**Files:**
- Modify: `~/Study/media-desc/Sources/ImageAnalyzer.swift` (lines 41-59, the OCR TaskGroup task)

- [ ] **Step 1: Remove OCR task from TaskGroup, add OCR after collection**

Replace the entire `analyzeImage()` function（line 36-297）.

**Replace line 45 line "// OCR (zh-Hans + en-US bilingual, .accurate)" through line 59:**

Before (current code, lines 45-59):
```swift
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
```

After (remove the OCR task):
```swift
        // OCR moved OUT of TaskGroup — runs after collection
        // (long images need textRects result before slicing)
```

**Replace the "Collect results" lines ~253-258:**

Before:
```swift
        // Collect results
        var collected: [VisionTaskResult] = []
        for try await result in group {
            collected.append(result)
        }
        return collected
    }
```

After:
```swift
        // Collect results (20 tasks, no OCR)
        var collected: [VisionTaskResult] = []
        for try await result in group {
            collected.append(result)
        }
        return collected
    }

    // ── OCR Phase (after TaskGroup, serial) ──
    let ocrBlocks: [TextBlock]
    if isLongImage(cgImage) {
        // Extract textRects from collected results for gap analysis
        var textRects: [DetectedRectangle] = []
        for result in results {
            if case .textRects(let rects) = result {
                textRects = rects
                break
            }
        }
        do {
            ocrBlocks = try await longImageOCR(cgImage, textRects)
        } catch {
            ocrBlocks = []
        }
    } else {
        do {
            ocrBlocks = try await singlePassOCR(cgImage)
        } catch {
            ocrBlocks = []
        }
    }

    // Append OCR result to collected results
    var finalResults = results
    finalResults.append(.ocr(ocrBlocks))
```

**Also remove the `var finalResults = results` line at ~261** (it's now above, so the document post-processing loop uses `finalResults` directly):

After the OCR append (above), insert:

```swift

    // ── Post-process: OCR each detected document region ──
    for (index, result) in finalResults.enumerated() {
```

These three are the exact same post-processing loop as before.

<details>
<summary>Reference: complete new analyzeImage() for verification</summary>

Here is the complete new `analyzeImage()` function for verification:

```swift
@available(macOS 26.0, *)
func analyzeImage(_ path: String) async throws -> ImageReport {
    guard let cgImage = loadCGImage(path) else {
        throw MediaError.badImage(path)
    }

    let results: [VisionTaskResult] = try await withThrowingTaskGroup(
        of: VisionTaskResult.self
    ) { group in

        // OCR moved OUT of TaskGroup — runs after collection
        // (long images need textRects result before slicing)

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
        // Collect results (20 tasks, no OCR)
        var collected: [VisionTaskResult] = []
        for try await result in group {
            collected.append(result)
        }
        return collected
    }

    // ── OCR Phase (after TaskGroup, serial) ──
    let ocrBlocks: [TextBlock]
    if isLongImage(cgImage) {
        var textRects: [DetectedRectangle] = []
        for result in results {
            if case .textRects(let rects) = result {
                textRects = rects
                break
            }
        }
        do {
            ocrBlocks = try await longImageOCR(cgImage, textRects)
        } catch {
            ocrBlocks = []
        }
    } else {
        do {
            ocrBlocks = try await singlePassOCR(cgImage)
        } catch {
            ocrBlocks = []
        }
    }

    // Append OCR result
    var finalResults = results
    finalResults.append(.ocr(ocrBlocks))

    // ── Post-process: OCR each detected document region ──
    for (index, result) in finalResults.enumerated() {
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
```
</details>

- [ ] **Step 2: Build**

```bash
cd ~/Study/media-desc && swift build 2>&1
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
cd ~/Study/media-desc && git add Sources/ImageAnalyzer.swift && git commit -m "feat: integrate longImageOCR into analyzeImage — OCR runs after TaskGroup"
```

---

### Task 5: Build, Install, Regression Test

- [ ] **Step 1: Full build and install**

```bash
cd ~/Study/media-desc && swift build 2>&1 && cp .build/debug/media-desc ~/bin/ && echo "installed OK"
```

- [ ] **Step 2: Regression test — normal (short) image must work identically**

```bash
# Test with a normal image — output should match pre-change behavior
media-desc /tmp/media-compare/imgs/c.png > /tmp/media-compare/c_after.md 2>/tmp/media-compare/c_after.err
echo "=== Block count ===" && grep "blocks" /tmp/media-compare/c_after.md | head -1
# Expected: 56 blocks, avg confidence ~0.90 (same as before)
```

- [ ] **Step 3: Stderr check**

```bash
cat /tmp/media-compare/c_after.err
# Expected: no stderr output (no warnings)
```

- [ ] **Step 4: Long image test**

Find or use the long phone screenshot from the previous test session (1242×19362px JPEG). If not available, generate a tall test image:

```bash
# If long test image exists:
media-desc <long_image_path> > /tmp/media-compare/long_after.md 2>/tmp/media-compare/long_after.err
echo "=== Block count ===" && grep "blocks" /tmp/media-compare/long_after.md | head -1
# Expect: significantly more blocks than before (was 9)
```

- [ ] **Step 5: Diff comparison — normal image regression**

```bash
diff <(grep "blocks\|Text (OCR)" /tmp/media-compare/c.md) <(grep "blocks\|Text (OCR)" /tmp/media-compare/c_after.md)
# Expected: identical or trivially different (same block count)
```

- [ ] **Step 6: Commit final working state**

```bash
cd ~/Study/media-desc && git add -A && git commit -m "test: regression test passes — normal image OCR unchanged"
```
