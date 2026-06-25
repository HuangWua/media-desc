# Video/Audio Visual Language Detection

> media-desc v5 — 视频增加画面语言检测，音频已有语言检测无需变更。

## Problem

视频当前仅从语音转录检测 `language`。无语音/BGM视频的语言始终为 `unknown`。视频画面中的文字（OCR）未被用于语言检测。

## Goal

视频输出双语言字段：`language`（语音） + `visualLanguage`（画面文字），各自独立。

## Design

### 数据流

```
analyzeVideo(path)
│
├─ async let frames = extractKeyframes(...)       // Phase 1: 关键帧
├─ exportAudio → analyzeSpeechFile → transcript   // Phase 1: 语音（并行）
│
├─ Phase 2: per-frame Vision（OCR + 分类 + 显著性）
│
├─ 🆕 聚合帧 OCR → detectLanguage → visualLanguage
│    snapshots.prefix(10).flatMap { ocrBlocks.prefix(5) }.joined()
│
└─ VideoReport(language: transcriptLang, visualLanguage: visualLang, ...)
```

### Models

`VideoReport` 新增：

```swift
let visualLanguage: String   // 🆕 from frame OCR text
```

### VideoAnalyzer

在 `return VideoReport(...)` 之前插入（3 行）：

```swift
// Phase 4: detect visual language from frame OCR
let frameText = snapshots.prefix(10).flatMap { $0.ocrBlocks.prefix(5).map(\.string) }.joined()
let visualLanguage = detectLanguage(frameText)
```

### ReportRenderer

视频标题行：

```
Language: {lang} | Visual: {visualLang} | Audio: {soundType}
```

## Performance

| 操作 | 开销 |
|------|------|
| 帧 OCR 文本聚合 | <1ms（内存，无新 API） |
| `NLLanguageRecognizer` | ~0.1ms（本地模型） |
| **总增量** | **<2ms** |

## Files

| 文件 | 变更 |
|------|------|
| `Sources/Models.swift` | `VideoReport` +1 字段 |
| `Sources/VideoAnalyzer.swift` | +3 行聚合 + 传参 |
| `Sources/ReportRenderer.swift` | +1 处渲染 |

## Non-Goals

- `AudioReport` 不改（只有语音来源）
- `ImageReport` 不改（已有 `language` 字段）
- 不改帧分析流程（OCR 本就运行）
