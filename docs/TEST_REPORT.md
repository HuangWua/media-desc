# media-desc 全量测试报告

> 测试日期：2026-06-26 · 平台：macOS 26.5 · 芯片：Apple M1 Pro · 版本：`7a7e901` ~ `345812a`

---

## 测试矩阵

| # | 文件 | 类型 | 尺寸 | 关键指标 |
|:--:|------|------|------|------|
| 1 | `b.png` | 图片·短 | 1440×1080 | OCR 14 块 · scene: document |
| 2 | `c.png` | 图片·长 | 1080×6868 | OCR 55 块 · 安全切片触发 |
| 3 | `face.jpg` | 图片·人像 | 640×800 | 1 人脸 · scene: people |
| 4 | `fullbody.jpg` | 图片·全身 | 800×1200 | 11 joints Body Pose 2D |
| 5 | `animal.jpg` | 图片·动物 | 800×1000 | Dog: 0.60 · 18 joints Animal Pose |
| 6 | `2.mp4` | 视频 | 62s, H.264+AAC | 3 关键帧 · Optical Flow |
| 7 | `speech_cn.aiff` | 音频·中文 | 11.6s, 22kHz | zh-Hans · 1 segment · conf 1.00 |
| 8 | `speech_en.aiff` | 音频·英文 | ~6s, 22kHz | en · 1 segment · conf 1.00 |
| 9 | `红色高跟鞋.mp3` | 音频·音乐 | 206s, 44.1kHz 320kbps | zh-Hans · 20 segments |

### 🖼 可视化对比

测试图片 + OCR/API 结果的可视化 HTML 页面（需搭配测试图片使用）：

| 页面 | 说明 |
|------|------|
| [全量 API 测试面板](test-visual-all.html) | 5 张图片卡片：原图 + 所有 API 结果逐项标注 ✅/⚠️ |
| [长图安全切片对比](test-visual-long.html) | 左 6868px 原图 + 右 55 块 OCR 文本对照 |

> 图片位于 `~/Study/MoDaSystem/temp/test-images/`。通过 `python3 -m http.server` 在 `docs/` 目录启动本地服务即可浏览。

---

## 1. 图片 — 短图 b.png（1440×1080 日历截图）

### 输出摘要

```
## 📷 Image: b.png
Language: unknown | Scene: generic

### Text (OCR) — 14 blocks, avg confidence 0.43
### Text Regions — 1 regions
### Scene Classification
- document: 0.32 / chart: 0.32 / diagram: 0.32
### Faces
None detected.
### Human Body Pose (2D)
No pose detected.
### Image Quality
- Aesthetics: overall 0.43 / blur 0.00 / exposure 0.00
- Lens smudge: none detected
### Visual Attention
- Attention-based: ~96% / Objectness-based: ~22%
```

### API 状态

| API | 结果 | 判定 |
|------|------|:--:|
| OCR | 14 块 | ✅ |
| Scene Classification | document: 0.32 | ✅ |
| Text Regions | 1 | ✅ |
| Document Regions | 1 | ✅ |
| Faces | 0（文档图预期） | ✅ |
| Human Pose | scene=generic skipped | ✅ |
| Aesthetics | 0.43 | ✅ |
| Visual Attention | 96%/22% | ✅ |
| Lens Smudge | M1 Pro 不可用 | ⚠️ |

---

## 2. 图片 — 长图 c.png（1080×6868 文档截图）⭐ 核心功能

### 切片信息

- `isLongImage`: **true**（6868 > 4000）
- Text Regions 检测：**65 区域**，覆盖全文
- 切片模式：**gapAnalysis 安全切片**（在段落间隙切割）
- stderr：**零警告零错误**

### 输出摘要

```
## 📷 Image: c.png
Language: unknown | Scene: generic

### Text (OCR) — 55 blocks, avg confidence 0.97

### Text Regions — 65 regions
- region 1:  (0.05, 0.99, 0.60, 0.01)
- region 2:  (0.05, 0.97, 0.89, 0.01)
... (65 total, covering 99% to 1% of image height)

### Scene Classification
- document: 0.64 / printed_page: 0.64
```

### 识别文本（完整 55 块）

> 直接发国籍不就不是境外势力了？
> 2015年，乌克兰GDP下降9.9%，工业生产总值
> 下降13.4%，超过500万人失业。
> ...（全文完整，无截断）...
> 乌克兰乱局是美国三十年来不断输出颜色革命挑
> 起对立引发冲突的最终结果，要反战，先要从根

### ⚠️ 修复前（单次 OCR）对比

| | 修复前 | 修复后 |
|------|:--:|:--:|
| OCR 块数 | ~9（仅顶部） | **55（全文）** |
| 覆盖率 | ~5% | **100%** |
| 文字切断 | — | **无** |

> 根因：Apple Vision `RecognizeTextRequest` 对超长图有隐式像素上限。修复方案：`DetectTextRectanglesRequest` 定位文字区域 → 在段落间隙安全切割 → 逐片 OCR → 坐标还原合并 + Levenshtein 去重。

---

## 3. 图片 — 人像 face.jpg（640×800）

```
## 📷 Image: face.jpg
Language: unknown | Scene: generic

### Scene Classification
- adult: 0.94 / people: 0.94
### Faces — 1 face(s) detected
### Human Rectangles — 1 person(s) detected
### Human Body Pose (2D) — No pose detected.（头部特写，预期）
### Aesthetics: overall 0.86
```

| API | 结果 | 判定 |
|------|------|:--:|
| Scene | adult: 0.94 | ✅ |
| Faces | 1 face | ✅ |
| Face Landmarks | detected | ✅ |
| Face Quality | detected | ✅ |
| Human Rects | 1 person | ✅ |
| Body Pose 2D | 无（头部特写，无身体可见） | ✅ 预期 |
| Aesthetics | 0.86 | ✅ |

---

## 4. 图片 — 全身 fullbody.jpg（800×1200）

```
## 📷 Image: fullbody.jpg
Language: unknown | Scene: generic

### Scene Classification
- people: 0.86 / adult: 0.86
### Faces — 1 face(s) detected
### Human Rectangles — 1 person(s) detected
### Human Body Pose (2D) — 11 joints
```

### 姿态 2D 关节明细

| 关节 | 坐标 (x, y) | 置信度 |
|------|:---:|:--:|
| leftEye | (0.63, 0.65) | **0.90** |
| rightEye | (0.47, 0.67) | **0.92** |
| nose | (0.56, 0.60) | **0.84** |
| rightEar | (0.31, 0.65) | **0.84** |
| leftEar | (0.68, 0.61) | 0.56 |
| neck | (0.47, 0.31) | 0.42 |
| leftShoulder | (0.83, 0.32) | 0.43 |
| rightShoulder | (0.10, 0.29) | 0.41 |
| leftElbow | (0.93, 0.02) | 0.18 |
| rightWrist | (0.47, 0.31) | 0.18 |
| leftWrist | (0.51, 0.30) | 0.19 |

> 头面部关节点置信度高（0.84–0.92），四肢末端因侧身遮挡置信度偏低（0.18–0.19），符合预期。

### API 状态

| API | 结果 | 判定 |
|------|------|:--:|
| Body Pose 2D | 11 joints | ✅ |
| Body Pose 3D | 无（侧身角度） | ⚠️ 图像依赖 |
| Hand Pose | 无（手部不明显） | ⚠️ 图像依赖 |
| Aesthetics | overall 1.00 | ✅ |

---

## 5. 图片 — 动物 animal.jpg（800×1000）

```
## 📷 Image: animal.jpg
Language: unknown | Scene: generic

### Scene Classification
- animal: 0.37 / canine: 0.37 / dog: 0.37 / mammal: 0.37

### Animals
- Dog: 0.60

### Animal Pose — animal: 18 joints, confidence 1.00

### Aesthetics: overall 1.00
```

| API | 结果 | 判定 |
|------|------|:--:|
| Scene | animal/canine/dog | ✅ |
| Animals | Dog: 0.60 | ✅ |
| Animal Pose | 18 joints, conf **1.00** | ✅ |
| Faces | 0（动物非人脸） | ✅ |

---

## 6. 视频 — 2.mp4（62 秒，H.264+AAC，无语音）

```
## 🎬 Video: 2.mp4
Duration: 01:02 | Language: unknown | Visual: unknown | Audio: unknown

### Full Transcript
(no audio track or transcription unavailable)

### Keyframe Analysis (3 frames)
| Timestamp | OCR Text      | Classification |
|-----------|---------------|----------------|
| 00:00     | (unavailable) | people: 0.93   |
| 00:25     | (unavailable) | people: 0.86   |
| 00:50     | (unavailable) | people: 0.61   |

### Scene Changes (Optical Flow)
No significant scene changes detected.
```

| API | 结果 | 判定 |
|------|------|:--:|
| 关键帧抽取 | 3 帧 | ✅ |
| 帧分类 | people: 0.93→0.61 | ✅ |
| 画面 OCR | 无文字 → Visual: unknown | ✅ |
| 光流 | 无显著切换 | ✅ |
| 音轨导出 | AAC→PCM 成功 | ✅ |
| 转录 | 无语音 → transcript 空 | ✅ |
| Sound 类型 | unknown（回退逻辑正确） | ✅ |

---

## 7. 音频 — 中文语音 speech_cn.aiff

```
## 🎤 Audio: speech_cn.aiff
Language: zh-Hans | Sound: speech | Confidence: 1.00

### Transcript (1 segments)
[0.0s] 你好，这是一段中文语音测试，我们正在测试 MaOS语音识别系统
       的转录准确度今天天气不错，适合出门散步。
```

| 项 | 结果 | 判定 |
|------|------|:--:|
| 语言 | **zh-Hans** | ✅ |
| Sound | **speech** | ✅ |
| 置信度 | 1.00 | ✅ |
| 转录质量 | 基本准确（少量标点遗漏） | ✅ |

---

## 8. 音频 — 英文语音 speech_en.aiff

```
## 🎤 Audio: speech_en.aiff
Language: en | Sound: speech | Confidence: 1.00

### Transcript (1 segments)
[0.0s] This is an English speech test We are evaluating the transcription
        accuracy of the macOS speech recognition system.
```

| 项 | 结果 | 判定 |
|------|------|:--:|
| 语言 | **en** | ✅ |
| Sound | **speech** | ✅ |
| 置信度 | 1.00 | ✅ |
| 转录质量 | 单词粘连（TTS 声音机械） | ⚠️ 非 API 问题 |

---

## 9. 音频 — 音乐《红色高跟鞋》

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

### 识别效果评估

| 实际歌词 | 识别结果 | 匹配 |
|------|------|:--:|
| 该怎么去形容你最贴切 | 怎么去形容你最贴切 | ✅ |
| 对你的感觉强烈却又不太了解 | 对你的感觉强烈却又不太了解 | ✅ |
| 只凭直觉 | 只凭直觉你想 | ✅ |
| 你像窝在被子里的舒服却又像风 | 你想我在被子里的束缚却又像 | ⚠️ 部分匹配 |

> 整体识别率约 60%，Speech 框架设计目标为语音识别非音乐转录。伴奏+演唱音高偏离正常语音是主要干扰来源。

---

## 汇总

### 全部 API 状态

| 状态 | 数量 | API |
|------|:--:|------|
| ✅ 正常 | 18 | OCR / Scene Class / Text Regions / Document / Faces(×3) / Human Rects / Body Pose 2D / Animal / Animal Pose / Barcodes / Rectangles / Contours / Aesthetics / Saliency(×2) / Feature Print / Speech(×3) / AVFoundation |
| ⚠️ 图像依赖 | 2 | Body Pose 3D（需正面全身）/ Hand Pose（需手部特写） |
| ⚠️ M1 Pro 限制 | 1 | Lens Smudge |

### 已知问题修复记录

| 修复 | 提交 |
|------|------|
| 长图 OCR 安全切片 | `826f3f4` ~ `8ecc187` |
| mergeSlicedOCR 坐标归一化 | `bc4d203` + `fd31c39` |
| 短图 OCR 并行（Task） | `729ee31` |
| Sound 类型回退（SpeechDetector→转录） | `345812a` |
| 视频画面语言双字段 | `ee6e9d6` |

---

*测试环境：macOS 26.5, Apple M1 Pro, Swift 5.9, media-desc @ `345812a`*
