---
name: media-desc
description: macOS 26 全模态媒体分析 CLI — 图片(21 Vision API)/视频/音频 → Markdown。用于将图片/视频/音频转为 LLM 可读的结构化文本。
user-invocable: true
---

# media-desc

macOS 26 原生 CLI 工具，将图片、视频、音频转为结构化 Markdown。

## 使用方式

用户通过 `/media-desc <文件路径>` 调用。

### 自动模式

```bash
media-desc <文件路径>
```

自动检测文件类型（图片/视频/音频），输出 Markdown 报告。

### 强制模式

```bash
media-desc --image <路径>    # 图片
media-desc --video <路径>    # 视频
media-desc --audio <路径>    # 音频
```

## 输出到对话

收到用户指令后，执行 `media-desc <路径>`，将完整 Markdown 输出返回给用户。如执行出错，报告错误信息并提示可能原因（文件不存在、格式不支持、macOS 版本不足等）。

## 支持格式

图片：png, jpg, jpeg, heic, bmp, gif, webp
视频：mp4, mov, m4v
音频：m4a, mp3, wav, flac, aiff

## 环境要求

macOS 26+，Apple Silicon（M1+）。如检测到不满足条件，提示用户升级系统或换设备。

## 能力范围

| 模态 | 能力 | 成熟度 |
|------|------|:--:|
| 图片 | 21 Vision API（OCR/场景/人脸/姿态/动物/文档/条码/美学/显著性） | ⭐ 主力 |
| 长图 | 安全切片（段落间隙切割，不切断文字） | ⭐ 特色 |
| 视频 | 关键帧采样+光流+语音转录 | ⚠️ 有限 |
| 音频 | 语音转录+语言检测 | ⚠️ 仅纯人声 |

## 注意事项

- 执行时间：图片 ~1-4s，视频/音频取决于时长
- 输出直接展示给用户，不做二次截断或摘要
- 2>/dev/null 抑制 stderr（Vision E5 模型警告为 M1 Pro 已知问题）
