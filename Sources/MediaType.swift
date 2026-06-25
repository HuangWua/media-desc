import UniformTypeIdentifiers
import Foundation

// MARK: - File Type Detection

func detectMediaType(_ path: String) -> MediaType? {
    let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
    guard !ext.isEmpty else { return nil }

    if let utType = UTType(filenameExtension: ext) {
        if utType.conforms(to: .image) { return .image }
        if utType.conforms(to: .movie) || utType.conforms(to: .video) { return .video }
        if utType.conforms(to: .audio) { return .audio }
    }

    // Fallback extension matching for types UTType may not cover
    switch ext {
    case "m4v": return .video
    case "m4a", "flac", "aiff", "wav": return .audio
    case "heic", "webp", "bmp", "gif": return .image
    default: return nil
    }
}

// MARK: - Error Types

enum MediaError: LocalizedError {
    case unsupportedFormat(String)
    case fileNotFound(String)
    case badImage(String)
    case badVideo(String)
    case badAudio(String)
    case allRecognizersFailed(String)
    case speechNotAuthorized
    case noAudioTrack(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "不支持的文件格式: .\(ext)\n支持的格式: 图片(png/jpg/heic/bmp/gif) 视频(mp4/mov/m4v) 音频(m4a/mp3/wav/flac/aiff)"
        case .fileNotFound(let path):
            return "文件不存在: \(path)"
        case .badImage(let path):
            return "无法加载图片: \(path)"
        case .badVideo(let path):
            return "无法打开视频: \(path)"
        case .badAudio(let path):
            return "无法打开音频: \(path)"
        case .allRecognizersFailed(let path):
            return "无法分析此文件: 所有识别器均失败 — \(path)"
        case .speechNotAuthorized:
            return "语音识别未授权。请在 系统设置 > 隐私与安全性 > 语音识别 中授权终端"
        case .noAudioTrack(let path):
            return "文件中无音轨: \(path)"
        }
    }
}
