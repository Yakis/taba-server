import Foundation

/// Writes report.md and the raw response bodies. Only bodies are written, never headers.
enum ProbeReport {
    static func write(records: [ProbeRecord], model: String, outputPath: String, requestLimit: Int) -> Int32 {
        let directory = URL(fileURLWithPath: outputPath, isDirectory: true)
        let raw = directory.appendingPathComponent("raw", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        } catch {
            complain("Could not create \(outputPath).")
            return 1
        }
        var lines = [
            "# ChatGPT plan probe",
            "",
            "- Model: \(model)",
            "- Requests made: at most \(requestLimit)",
            ""
        ]
        for record in records {
            lines.append("## \(record.title)")
            lines.append("")
            lines.append(record.line)
            lines.append(contentsOf: record.detail.map { "- \($0)" })
            lines.append("")
            if let body = record.rawBody {
                let file = raw.appendingPathComponent("\(record.key).txt")
                try? body.write(to: file, atomically: true, encoding: .utf8)
            }
        }
        let reportURL = directory.appendingPathComponent("report.md")
        try? (lines.joined(separator: "\n") + "\n").write(to: reportURL, atomically: true, encoding: .utf8)
        print("Wrote \(reportURL.path) and raw bodies in \(raw.path).")
        return 0
    }
}
