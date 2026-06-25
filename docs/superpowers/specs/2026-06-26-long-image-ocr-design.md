# Long Image OCR — 超长图安全切片设计

> Spec for media-desc v4 long image OCR enhancement.
> Builds on v4 baseline (commit `1b2e17a`): 21 Vision APIs, scene router, Chinese OCR fix.

## Problem

`RecognizeTextRequest` (.accurate, zh-Hans+en-US) returns severely truncated results for ultra-tall images (e.g., phone screenshots at 1242×19362 pixels) — only 9 OCR blocks instead of the ~120+ expected. Normal-size images (1440×1080) work perfectly (56 blocks, 0.90 avg confidence).

Root cause: Vision has implicit per-request processing limits for pixel volume or text region count. Ultra-tall images exceed this limit invisibly (no error, just fewer results).

## Goal

Long images (phone screenshots primarily) must yield complete OCR coverage without cutting text lines at tile boundaries. Normal images must experience zero behavioral change.

## Design

### Trigger

Image is classified as "long" when **either**:
- `height > 4000` pixels, **or**
- `aspect ratio > 1:3` (height > 3× width)

### Two-Phase Pipeline

```
analyzeImage(cgImage)
│
├─ TaskGroup: 20 Vision APIs (all EXCEPT OCR)
│   ├─ textRects  ← DetectTextRectanglesRequest
│   ├─ labels, faces, barcodes, aesthetics, ...
│   └─ collect all results
│
└─ OCR Phase (serial, after TaskGroup results collected):
    │
    ├─ Short image → singlePassOCR(cgImage)  [existing logic, zero change]
    │
    └─ Long image → longImageOCR(cgImage, textRects):
        ├─ Phase 1: gapAnalysis(textRects) → text coverage + safe cut points
        │   │
        │   ├─ Coverage OK (last rect.maxY > 30% of image height)
        │   │   └─ Find gaps > lineH×2 between consecutive textRects
        │   │       ├─ Has gaps → Phase 2a: gap-guided slicing
        │   │       └─ No gaps  → Phase 2b: fallback (fixed-height slicing)
        │   │
        │   └─ Coverage insufficient (textRects only cover top portion)
        │       └─ Phase 2b: fallback
        │
        └─ Phase 2a (gap-guided):
            ├─ Split at gap midpoints, target slice height ~3000px
            ├─ Expand each slice by 5% on both sides for padding
            ├─ Crop → RecognizeTextRequest → parseOCR
            └─ Merge: remap Y coordinates to original image space
        │
        └─ Phase 2b (fixed-height fallback):
            ├─ 3000px slices, 20% overlap between adjacent slices
            ├─ Crop → RecognizeTextRequest → parseOCR
            └─ Merge + dedup: Levenshtein > 0.6 AND Y diff < 3px → keep higher confidence
```

### Gap Analysis Algorithm

```
Input: textRects sorted by Y (ascending)
Output: safe cut Y positions

1. lineH = median height of all textRects
2. gapThreshold = lineH × 2.0

3. For each consecutive pair (rect[i], rect[i+1]):
     gap = rect[i+1].minY - rect[i].maxY
     if gap >= gapThreshold:
       safeCutY = rect[i].maxY + gap/2  (midpoint of gap)

4. From safeCutYs, pick cut points that keep each slice ≤ 3000px tall
   (merge adjacent small gaps to avoid too many slices)

5. Each slice expanded +5% height on both sides (padding against edge effects)
```

### Merge & Dedup

After all slices are OCR'd:

1. Each TextBlock's Y coordinate remapped: `block.rect.origin.y += slice.originY`
2. All blocks sorted by Y
3. Adjacent dedup: if two blocks have `|Y diff| < 3` AND Levenshtein(text1, text2) > 0.6 AND the OCR strings differ only in whitespace/confidence, keep the one with higher confidence
4. Return merged array

### File Changes

Only `Sources/ImageAnalyzer.swift`:

| Function | Action |
|----------|--------|
| `analyzeImage()` | Modify: OCR task moves out of TaskGroup. Short path unchanged; long path calls `longImageOCR()` |
| `singlePassOCR(_ cgImage:)` | New: extract existing OCR closure into a named function |
| `longImageOCR(_ cgImage:, _ textRects:)` | New: orchestrates Phase 1–2 pipeline |
| `gapAnalysis(_ textRects:, _ imageHeight:)` | New: compute safe cut points from text regions |
| `isLongImage(_ cgImage:)` | New: height > 4000 or aspect > 3× |
| TextUtils.swift `levenshtein(_:, _:)` | New: Levenshtein distance for dedup |

### Zipf's Law / Edge Cases

| Case | Behavior |
|------|----------|
| textRects returns 0 | Fallback to Phase 2b |
| textRects only covers top 30% | Vision limit hit on text detection too → Phase 2b |
| No gap ≥ lineH×2 in entire image | Dense text wall → Phase 2b |
| Single text line across entire image | Not realistic for phone screenshots; Phase 2b |
| Slice OCR fails | Skip slice, log warning, continue with remaining slices |
| All slices fail | Return empty OCR array (matches current error behavior) |
| Image < 100px tall | `isLongImage` returns false → short path |

### Performance Budget

- Short image: 0ms overhead (identical code path)
- Long image, gap-guided (2 slices): +1–2 DetectTextRectanglesRequest overhead (already running) + ~2s per extra slice → ~3–5s total
- Long image, Phase 2b (4–7 slices): ~5–10s total
- textRects result already collected from TaskGroup — no extra cost for detection phase

### Testing

Manual test with the 1242×19362px phone screenshot + visualization HTML:

```bash
media-desc /tmp/media-compare/imgs/long_phone_screenshot.png
# Expect: 100+ OCR blocks in output MD, no half-cut text
# Compare HTML: before vs after side-by-side
```

## Non-Goals

- Not changing short-image behavior (zero regression)
- Not adding tiling for non-OCR Vision APIs (labels/faces/barcodes not affected by image height)
- Not modifying Models.swift (OCR output format unchanged)
- No new dependencies
