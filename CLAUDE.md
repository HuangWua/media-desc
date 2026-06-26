# CLAUDE.md

media-desc — macOS 26 全模态媒体分析 CLI 工具。

## 硬约束

- **禁止自动 git commit**。代码修改完成后不自动提交，等用户明确说 commit 再提交。
- 所有分析均使用 Apple 原生框架（Vision / Speech / AVFoundation / NaturalLanguage），不引入第三方依赖。

## Commands

```bash
make build          # 编译 Release 版本
make install        # 编译 + 安装到 /usr/local/bin/
swift build         # Debug 版本（开发用）
```

## Skills

| 命令 | 类型 | 用途 |
|------|------|------|
| `/media-desc <文件>` | user-invocable | CLI 工具本身——在对话中用 `/media-desc <路径>` 分析图片/视频/音频 |

## Architecture

```
Sources/
├── CLI.swift              # 入口 + 参数解析
├── ImageAnalyzer.swift    # 图片分析：21 Vision API + 长图安全切片
├── VideoAnalyzer.swift    # 视频分析：关键帧/光流/轨迹/音轨/转录
├── AudioAnalyzer.swift    # 音频分析：SpeechAnalyzer 封装
├── Parsers.swift          # Vision Observation → 数据模型
├── ReportRenderer.swift   # Markdown 渲染
├── Models.swift           # 数据模型
├── TextUtils.swift        # 语言检测 + 情感分析 + Levenshtein
├── MediaType.swift        # 文件类型检测
└── CGImage+Loader.swift   # 图片加载/裁剪

docs/
├── TEST_REPORT.md         # 全量测试报告（9项 × 21API）
├── test-visual-all.html   # 全量API可视化对比
├── test-visual-long.html  # 长图切片可视化
└── imgs/                  # 测试图片
```

## Key Details

- **21 Vision API** 全部在 `TaskGroup` 中并行执行，单图 ~1-4s
- **长图安全切片**：`DetectTextRectanglesRequest` 定位文字→段落间隙切→逐片 OCR→Levenshtein 去重合并
- **图片语言检测**：从 OCR 文本前 5 块采样 `NLLanguageRecognizer`
- **视频语言检测**：语音转录 + 帧 OCR 双字段（`language` / `visualLanguage`）
- **Sound 类型**：`SpeechDetector` 结果为空时回退到转录判断（有文字→speech，无→unknown）
- **`make install`** 安装到 `/usr/local/bin/`（需 sudo），单文件 516KB
