import Foundation

// MARK: - Render Entry Point

func renderReport(_ report: any Report) -> String {
    switch report.mediaType {
    case .image: return renderImage(report as! ImageReport)
    case .video: return renderVideo(report as! VideoReport)
    case .audio: return renderAudio(report as! AudioReport)
    }
}

// MARK: - Image

func renderImage(_ r: ImageReport) -> String {
    var out = ""
    out += "## 📷 Image: \(r.source)\n\n"

    // OCR
    if !r.ocrBlocks.isEmpty {
        let avgConf = r.ocrBlocks.map(\.confidence).reduce(0, +) / Float(r.ocrBlocks.count)
        out += "### Text (OCR) — \(r.ocrBlocks.count) blocks, avg confidence \(String(format: "%.2f", avgConf))\n\n"
        for block in r.ocrBlocks {
            out += "> \(block.string)\n"
        }
        out += "\n"
    } else {
        out += "### Text (OCR)\nNo text detected. (unavailable)\n\n"
    }

    // Document regions
    if !r.documentRegions.isEmpty {
        out += "### Document Regions\n\(r.documentRegions.count) region(s) detected.\n\n"
        for doc in r.documentRegions where !doc.rows.isEmpty {
            out += "| " + doc.rows.first!.joined(separator: " | ") + " |\n"
            out += "|" + doc.rows.first!.map { _ in "-------" }.joined(separator: "|") + "|\n"
            for row in doc.rows.dropFirst() {
                out += "| " + row.joined(separator: " | ") + " |\n"
            }
            out += "\n"
        }
    }

    // Document Tables (from RecognizeDocumentsRequest)
    let docsWithTables = r.documentRegions.filter { !$0.rows.isEmpty }
    if !docsWithTables.isEmpty {
        out += "### Document Tables\n"
        for (i, doc) in docsWithTables.enumerated() {
            out += "Table \(i + 1):\n\n"
            for row in doc.rows {
                out += "| " + row.joined(separator: " | ") + " |\n"
            }
            out += "\n"
        }
    }

    // Classification
    if !r.labels.isEmpty {
        out += "### Scene Classification\n"
        for l in r.labels.prefix(5) {
            out += "- \(l.identifier): \(String(format: "%.2f", l.confidence))\n"
        }
        out += "\n"
    } else {
        out += "### Scene Classification\n(unavailable)\n\n"
    }

    // Faces
    if !r.faces.isEmpty {
        out += "### Faces\n\(r.faces.count) face(s) detected\n\n"
    } else {
        out += "### Faces\nNone detected.\n\n"
    }

    // Barcodes
    if !r.barcodes.isEmpty {
        out += "### Barcodes\n"
        for b in r.barcodes {
            out += "- [\(b.symbology)] \(b.payload)\n"
        }
        out += "\n"
    } else {
        out += "### Barcodes\nNone detected.\n\n"
    }

    // Animals
    if !r.animals.isEmpty {
        out += "### Animals\n"
        for a in r.animals {
            out += "- \(a.identifier): \(String(format: "%.2f", a.confidence))\n"
        }
        out += "\n"
    } else {
        out += "### Animals\nNone detected.\n\n"
    }

    // Quality
    out += "### Image Quality\n"
    if let a = r.aesthetics {
        out += "- Aesthetics: overall \(String(format: "%.2f", a.overall))"
        out += " / blur \(String(format: "%.2f", a.blurScore))"
        out += " / exposure \(String(format: "%.2f", a.exposureScore))\n"
    } else {
        out += "- Aesthetics: (unavailable)\n"
    }
    if let s = r.lensSmudge {
        out += "- Lens smudge: \(s.hasSmudge ? "DETECTED (confidence \(String(format: "%.2f", s.confidence)))" : "none detected")\n"
    } else {
        out += "- Lens smudge: (unavailable)\n"
    }
    out += "\n"

    // Saliency
    out += "### Visual Attention\n"
    if let s = r.attentionSaliency, let box = s.boundingBox {
        out += "- Attention-based: (\(String(format: "%.2f", box.origin.x)), \(String(format: "%.2f", box.origin.y))) ~\(String(format: "%.0f", box.width * 100))% of image\n"
    } else {
        out += "- Attention-based: (unavailable)\n"
    }
    if let s = r.objectSaliency, let box = s.boundingBox {
        out += "- Objectness-based: (\(String(format: "%.2f", box.origin.x)), \(String(format: "%.2f", box.origin.y))) ~\(String(format: "%.0f", box.width * 100))% of image\n"
    } else {
        out += "- Objectness-based: (unavailable)\n"
    }

    return out
}

// MARK: - Video

func renderVideo(_ r: VideoReport) -> String {
    var out = ""
    out += "## 🎬 Video: \(r.source)\n\n"

    let mins = Int(r.duration) / 60
    let secs = Int(r.duration) % 60
    out += "Duration: \(String(format: "%02d:%02d", mins, secs))"
    out += " | Language: \(r.language)"
    out += " | Audio: \(r.soundType.rawValue)\n\n"

    if !r.transcript.isEmpty {
        let avgConf = r.transcript.map(\.confidence).reduce(0, +) / Float(r.transcript.count)
        out += "### Full Transcript (\(r.transcript.count) segments, confidence \(String(format: "%.2f", avgConf)))\n"
        for seg in r.transcript {
            let ts = String(format: "%.1f", seg.timestamp)
            out += "[\(ts)] \(seg.text)\n"
        }
        out += "\n"
    } else {
        out += "### Full Transcript\n(no audio track or transcription unavailable)\n\n"
    }

    if !r.frames.isEmpty {
        out += "### Keyframe Analysis (\(r.frames.count) frames)\n"
        out += "| Timestamp | OCR Text | Classification |\n"
        out += "|-----------|----------|----------------|\n"
        for f in r.frames {
            let label = f.labels.first.map { "\($0.identifier): \(String(format: "%.2f", $0.confidence))" } ?? "(unavailable)"
            let ocrSnippet = f.ocrBlocks.first?.string.prefix(30) ?? "(unavailable)"
            let ts = String(format: "%02d:%02d", Int(f.timestamp) / 60, Int(f.timestamp) % 60)
            out += "| \(ts) | \(ocrSnippet) | \(label) |\n"
        }
        out += "\n"
    }

    if !r.sceneChanges.isEmpty {
        out += "### Scene Transitions\n"
        let parts = r.sceneChanges.map { c in
            let ts = String(format: "%02d:%02d", Int(c.at) / 60, Int(c.at) % 60)
            return "\(ts) → \(c.toLabel)"
        }
        out += parts.joined(separator: " > ")
        out += "\n"
    }

    if !r.trajectories.isEmpty {
        out += "### Motion Trajectories\n"
        for t in r.trajectories {
            out += "- [\(String(format: "%.0f", t.startTime))-\(String(format: "%.0f", t.startTime + t.duration))s] \(t.description) (confidence: \(String(format: "%.2f", t.confidence)))\n"
        }
        out += "\n"
    }

    if let flow = r.opticalFlowSummary {
        out += "### Scene Changes (Optical Flow)\n\(flow)\n\n"
    }

    return out
}

// MARK: - Audio

func renderAudio(_ r: AudioReport) -> String {
    var out = ""
    out += "## 🎤 Audio: \(r.source)\n\n"
    out += "Language: \(r.language)"
    out += " | Sound: \(r.soundType.rawValue)"
    out += " | Confidence: \(String(format: "%.2f", r.overallConfidence))\n\n"

    if !r.transcript.isEmpty {
        out += "### Transcript (\(r.transcript.count) segments)\n"
        for seg in r.transcript {
            let ts = String(format: "%.1f", seg.timestamp)
            out += "[\(ts)] \(seg.text)\n"
        }
    } else {
        out += "### Transcript\nNo speech detected. (silence or unrecognized)\n"
    }

    return out
}
