import Foundation

@main
@available(macOS 26.0, *)
struct MediaDesc {
    static func main() async {
        let args = CommandLine.arguments

        // Parse flags
        if args.contains("--help") || args.contains("-h") || args.count < 2 {
            printUsage()
            exit(args.count < 2 ? 1 : 0)
        }

        var forceType: MediaType? = nil
        var filePath: String? = nil

        var i = 1
        while i < args.count {
            switch args[i] {
            case "--image": forceType = .image
            case "--video": forceType = .video
            case "--audio": forceType = .audio
            default:
                if !args[i].hasPrefix("--") { filePath = args[i] }
            }
            i += 1
        }

        guard let path = filePath else {
            fputs("错误: 未指定文件路径\n", stderr)
            printUsage()
            exit(2)
        }

        // Check file existence
        guard FileManager.default.fileExists(atPath: path) else {
            fputs("\(MediaError.fileNotFound(path).errorDescription!)\n", stderr)
            exit(2)
        }

        // Determine media type
        let mediaType = forceType ?? detectMediaType(path)
        guard let mt = mediaType else {
            let ext = URL(fileURLWithPath: path).pathExtension
            fputs("\(MediaError.unsupportedFormat(ext).errorDescription!)\n", stderr)
            exit(2)
        }

        // Dispatch
        do {
            let report: any Report = try await {
                switch mt {
                case .image: return try await analyzeImage(path)
                case .video: return try await analyzeVideo(path)
                case .audio: return try await analyzeAudio(path)
                }
            }()

            print(renderReport(report))
        } catch let error as MediaError {
            fputs("\(error.errorDescription!)\n", stderr)
            exit(1)
        } catch {
            fputs("未知错误: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    static func printUsage() {
        print("""
        media-desc — macOS 26 全模态媒体分析工具

        用法:
          media-desc <路径>              自动检测类型并分析
          media-desc --image <路径>      强制图片模式
          media-desc --video <路径>      强制视频模式
          media-desc --audio <路径>      强制音频模式
          media-desc --help              显示此帮助

        支持格式:
          图片: png, jpg, jpeg, heic, bmp, gif, webp
          视频: mp4, mov, m4v
          音频: m4a, mp3, wav, flac, aiff

        示例:
          media-desc screenshot.png | pbcopy
          media-desc video.mp4
        """)
    }
}
