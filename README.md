# media-desc

**macOS 26 全模态媒体分析 CLI 工具**——为没有视觉/听觉能力的 LLM 提供「眼睛」和「耳朵」。

将图片、视频、音频转为结构化 Markdown，任何 LLM 都能直接理解和分析。

> ⚡ **核心能力：图片分析**（21 Vision API，覆盖 OCR / 场景 / 人脸 / 姿态 / 动物 / 文档 / 美学）。
> 视频和音频支持有限——视频依赖关键帧采样（非逐帧），音频仅对**纯人声对话**处理友好（歌声/背景音乐/多人嘈杂场景识别率显著下降）。如果你主要需要图片→文本，这是最合适的工具。

📋 **[全量测试报告 →](docs/TEST_REPORT.md)** — 9 项测试 × 21 API 状态 × 修复记录

---

## 亮点

### 🚀 速度

21 个 Vision API 全部在 `TaskGroup` 中并行执行，单张图片分析时间取决于最慢的 API（OCR），而非 API 数量之和。

| 图片类型 | 耗时 | 说明 |
|------|:--:|------|
| 短图（1440×1080） | **~2.2s** | 21 API 全并行 |
| 人像/动物/全身（~800×1000） | **~1.0s** | 尺寸小，OCR 快 |
| 长图（1080×6868）安全切片 | **~4.3s** | 两阶段：textRects 检测→切片 OCR→合并 |

> MacBook Pro M1 Pro 实测。视频和音频耗时取决于时长（Speech 框架 ~142× 实时）。

### 📦 零依赖

516KB 单二进制文件。无需 `pip install`、`npm install`、Docker、API Key。全部使用 Apple 原生框架（Vision / Speech / AVFoundation / NaturalLanguage），macOS 内置即用。

### 🔒 本地处理

所有分析在本地完成，图片/视频/音频**不会离开你的设备**。无网络请求，无第三方服务，无用户追踪。适合处理敏感文档、私人照片、机密录音。

### 🧩 长图安全切片

手机截图（1080×6868px）单次 Vision OCR 仅返回 ~9 块。media-desc 用 `DetectTextRectanglesRequest` 找到段落间隙，在安全位置切片后分别 OCR，再坐标还原+Levenshtein去重合并。**从不切断文字**。

### 📝 结构化 Markdown 输出

输出即标准 Markdown，可直接粘贴到 Claude / DeepSeek / ChatGPT 对话中。无需中间格式转换、无需手动排版。

---

## 痛点

DeepSeek V4、Claude 等文本模型 API **没有原生的图片/视频处理能力**。当你需要让 AI 分析一张截图、一段视频、一条录音时，只能手动描述或找第三方工具。

media-desc 填补这个缺口：**本地 Apple 原生框架分析 → 结构化 Markdown → 喂给任何 LLM**。

```
📷 图片  ──→  Vision (21 API)  ──→  OCR + 场景 + 人脸 + 姿态 + ...
🎬 视频  ──→  Vision + Speech   ──→  关键帧分析 + 光流 + 语音转录
🎤 音频  ──→  SpeechAnalyzer   ──→  转录 + 语言检测 + 声音分类
                        ↓
              结构化 Markdown
                        ↓
            Claude / DeepSeek / ChatGPT
```

---

## 环境要求

| 依赖 | 说明 |
|------|------|
| **macOS 26+** | Vision/Speech 新异步 API 需要 |
| **Swift 5.9+** | 仅用于编译（Xcode 或 Command Line Tools） |
| **第三方依赖** | **零**——全部 Apple 原生框架 |
| **安装体积** | 516KB 单二进制文件 |

> ⚠️ 仅支持 Apple Silicon（M1+）。M1 Pro 的 Lens Smudge 检测因缺少 `smudgenet-v1.E5` 模型不可用，其余所有 API 正常。

---

## 快速开始

```bash
# 编译安装
git clone <repo-url> && cd media-desc
make install                    # → /usr/local/bin/media-desc

# 图片分析
media-desc screenshot.png       # OCR + 场景 + 人脸 + 美学 ...

# 视频分析
media-desc video.mp4            # 关键帧 + 光流 + 语音转录

# 音频分析
media-desc speech.wav           # 转录 + 语言检测

# 输出到文件或管道
media-desc photo.png | pbcopy   # 直接拷贝到剪贴板喂给 LLM
media-desc video.mp4 > report.md
```

支持格式：PNG / JPG / HEIC / BMP / GIF / WebP / MP4 / MOV / M4V / M4A / MP3 / WAV / FLAC / AIFF

---

## 图片分析

### 全 21 Vision API 能力矩阵

| API | 用途 | 状态 |
|-----|------|:--:|
| `RecognizeTextRequest` | OCR 文字提取（中英双语 .accurate） | ✅ |
| `DetectTextRectanglesRequest` | 文本区域定位（仅检测，不 OCR） | ✅ |
| `RecognizeDocumentsRequest` | 文档区域 + 表格识别 | ✅ |
| `ClassifyImageRequest` | 场景分类（1000+ 标签） | ✅ |
| `DetectFaceRectanglesRequest` | 人脸边界框 | ✅ |
| `DetectFaceLandmarksRequest` | 人脸特征点（眼/鼻/嘴/耳） | ✅ |
| `DetectFaceCaptureQualityRequest` | 人脸拍摄质量 | ✅ |
| `DetectHumanRectanglesRequest` | 人体检测框 | ✅ |
| `DetectHumanBodyPoseRequest` | 人体 2D 姿态（关节坐标） | ✅ |
| `DetectHumanBodyPose3DRequest` | 人体 3D 姿态（含深度） | ⚠️ 需要正面全身 |
| `DetectHumanHandPoseRequest` | 手势关节检测 | ⚠️ 需要手部特写 |
| `RecognizeAnimalsRequest` | 动物种类识别 | ✅ |
| `DetectAnimalBodyPoseRequest` | 动物姿态（18 关节） | ✅ |
| `DetectBarcodesRequest` | 条码/二维码 | ✅ |
| `DetectRectanglesRequest` | 几何矩形 | ✅ |
| `DetectContoursRequest` | 轮廓检测 | ✅ |
| `CalculateImageAestheticsScoresRequest` | 图像美学评分 | ✅ |
| `GenerateAttentionBasedSaliencyImageRequest` | 注意力热区 | ✅ |
| `GenerateObjectnessBasedSaliencyImageRequest` | 物体显著性 | ✅ |
| `GenerateImageFeaturePrintRequest` | 图像 SHA256 指纹 | ✅ |
| `DetectLensSmudgeRequest` | 镜头污渍检测 | ⚠️ M1 Pro 模型缺失 |

### 长图安全切片

手机截图（如 1080×6868px）用单次 OCR 仅返回 ~9 块。media-desc 使用 `DetectTextRectanglesRequest` 找到文字段落间隙，在安全位置切分图片分别 OCR，再按坐标合并去重。

#### 测试对比：短图 vs 长图

| | b.png (1440×1080) | c.png (1080×6868) |
|------|:--:|:--:|
| 类型 | 短图 | **长图（安全切片）** |
| OCR 块数 | 14 | **55** |
| 平均置信度 | 0.43 | **0.97** |
| Text Regions | 1 | **65** |
| Scene | document | document |
| 切片触发 | `isLongImage: false` | `isLongImage: true` |

> 长图完整识别了全文 55 块文字，无截断、无文字切半。

#### 人体/动物/人脸测试

| | face.jpg (人像) | fullbody.jpg (全身) | animal.jpg (狗) |
|------|:--:|:--:|:--:|
| Faces | **1** ✅ | **1** ✅ | 0 |
| Human Rects | **1** ✅ | **1** ✅ | — |
| Body Pose 2D | 0 (头部特写) | **11 joints** ✅ | — |
| Animal | — | — | **Dog: 0.60** ✅ |
| Animal Pose | — | — | **18 joints** ✅ |

---

## 视频分析

### 处理管线

```
视频文件 → AVAssetImageGenerator 抽取关键帧（最多 12 帧）
         → 每帧并行: OCR + 场景分类 + 注意力显著性
         → TrackOpticalFlowRequest 帧间光流 → 场景切换检测
         → DetectTrajectoriesRequest 运动轨迹
         → 导出音轨 → SpeechAnalyzer 转录 + 语言检测 + 声音分类
         → 画面语言检测（从帧 OCR 聚合）
         → 结构化 Markdown
```

### API 清单

| API | 框架 | 用途 |
|-----|------|------|
| `RecognizeTextRequest` | Vision | 每帧 OCR |
| `ClassifyImageRequest` | Vision | 帧场景分类 |
| `GenerateAttentionBasedSaliencyImageRequest` | Vision | 帧显著性 |
| `TrackOpticalFlowRequest` | Vision | 场景切换检测 |
| `DetectTrajectoriesRequest` | Vision | 运动轨迹 |
| `SpeechAnalyzer` + `Transcriber` + `Detector` | Speech | 语音转录全文 |
| `NLLanguageRecognizer` | NaturalLanguage | 语音语言 + 画面语言（双字段） |

### 输出示例

```
## 🎬 Video: 2.mp4
Duration: 01:02 | Language: unknown | Visual: unknown | Audio: unknown

### Full Transcript
(no audio track or transcription unavailable)

### Keyframe Analysis (3 frames)
| Timestamp | OCR Text | Classification |
|-----------|----------|----------------|
| 00:00 | (unavailable) | people: 0.93 |
| 00:25 | (unavailable) | people: 0.86 |
| 00:50 | (unavailable) | people: 0.61 |

### Scene Changes (Optical Flow)
No significant scene changes detected.
```

---

## 音频分析

### 处理管线

```
音频文件 → AVAudioFile 解码
         → SpeechAnalyzer（Transcriber + Detector 双模块并行）
         → 转录全文 + 时间戳 + 置信度
         → NLLanguageRecognizer 语言检测
         → Sound 类型（speech/music/noise/mixed/unknown）
```

### 测试结果

#### 🇨🇳 中文语音（macOS TTS Tingting 生成）

```
## 🎤 Audio: speech_cn.aiff
Language: zh-Hans | Sound: speech | Confidence: 1.00

### Transcript (1 segments)
[0.0s] 你好，这是一段中文语音测试，我们正在测试 MaOS语音识别系统
       的转录准确度今天天气不错，适合出门散步。
```

#### 🇺🇸 英文语音（macOS TTS Samantha 生成）

```
## 🎤 Audio: speech_en.aiff
Language: en | Sound: speech | Confidence: 1.00

### Transcript (1 segments)
[0.0s] This is an English speech test We are evaluating the transcription
        accuracy of the macOS speech recognition system.
```

> 中文 TTS 识别率较高，英文 TTS 词间粘连——TTS 合成语音缺乏自然停顿，真人录音效果会好很多。

#### 🎵 音乐（蔡健雅《红色高跟鞋》，320kbps MP3）

```
## 🎤 Audio: 1-04 红色高跟鞋.mp3
Language: zh-Hans | Sound: speech | Confidence: 1.00

### Transcript (20 segments)
[22.8s] 怎么去形容你最贴切
[28.1s] 要什么跟你做比较的算特别对你的感觉强烈却又不太了解
[39.2s] 只凭直觉你想
[134.9s] 你想我在被子里的束缚却又像
[143.9s] 享受
```

> 歌声识别率约 60%，主歌副歌核心句捕获。Speech 框架优化目标为说话而非唱歌。

---

## 项目结构

```
Sources/
├── CLI.swift              入口 + 参数解析
├── ImageAnalyzer.swift     图片分析（21 Vision API + 长图切片）
├── VideoAnalyzer.swift     视频分析（关键帧/光流/轨迹/音轨/转录）
├── AudioAnalyzer.swift     音频分析（SpeechAnalyzer 封装）
├── Parsers.swift           Vision Observation → 数据模型
├── ReportRenderer.swift     Markdown 渲染
├── Models.swift            数据模型定义
├── TextUtils.swift          语言检测 + 情感分析 + Levenshtein 距离
├── MediaType.swift          文件类型检测
└── CGImage+Loader.swift    图片加载 + 裁剪
```

2069 行 Swift，10 个文件，零第三方依赖。

---

## 能力定位与局限

### 图片 ⭐ 主力

21 个 Vision API 全覆盖，是 media-desc 最成熟的能力。特别适用于手机截图、文档扫描、照片分析。长图安全切片解决了 Vision 对超长图（>4000px）的隐式限制。

### 视频 ⚠️ 有限

视频分析受限于**关键帧采样**（最多 12 帧，非逐帧），会丢失画面细节。适合快速浏览视频内容概览，不适合精确的逐帧分析。画面语言检测依赖帧内 OCR 文本——无文字的视频画面无法检测语言。

### 音频 ⚠️ 仅对纯人声友好

| 场景 | 效果 | 说明 |
|------|:--:|------|
| 单人清晰语音 | ✅ | 中英文识别率高，时间戳准确 |
| 会议/访谈 | ⚠️ | 多人说话混淆，Speaker 不分离 |
| 歌曲/音乐 | ⚠️ | 识别率 ~60%，伴奏干扰严重 |
| 嘈杂环境 | ❌ | 背景噪声大幅降低识别率 |
| 纯音乐/BGM | ❌ | 无语音输出，Sound 类型回退到 transcript 判断 |

音频处理链路依赖 macOS Speech 框架，该框架设计目标为**单人清晰语音转录**，非通用音频理解。

### 已知技术限制

| 问题 | 说明 |
|------|------|
| Lens Smudge | M1 Pro 缺少 `smudgenet-v1.E5` 模型，始终返回无污渍 |
| Body Pose 3D | 需要正面全身照，侧身/半身返回空 |
| Hand Pose | 需要手部在画面中足够大 |
| Aesthetics 子分数 | blur/exposure 在 macOS 26 API 中不暴露 |
| Aesthetics 长图 | 部分长图 overall 返回 0.00（API 行为） |

---

## 自行增强

media-desc 是一个 **vibe coding 产物**——在 M1 Pro + macOS 26 上用 Swift 几个小时搭出来的原型。它远非完美，但开了一个口子：**让本地 AI 能力直接服务于 LLM 文本交互**。

如果你是有能力的开发者，这里有些可以深入的方向：

- **M3+/M4 设备**：`DetectLensSmudgeRequest`、`GenerateForegroundInstanceMaskRequest` 等 M1 Pro 不可用的 API 在更新芯片上可以解锁
- **视频逐帧分析**：当前仅采样 12 帧，可以改为全帧率处理（代价是时间）
- **Speaker 分离**：Speech 框架支持多说话人标注，可以增强会议/访谈转录
- **更多输出格式**：JSON、JSON-LD、结构化 schema 等
- **Swift 跨平台**：Vision/Speech 是 Apple 独占，但输出管线可以扩展 Linux/Windows

M1 Pro 只是起点。Fork it, vibe it, ship it. 🚀

---

## License

MIT
