import Foundation

/// Persistent bounded diagnostics for hard-to-reproduce mobile lifecycle/game issues.
///
/// Rolling files live in Application Support and are capped at 3 x 2 MiB. They are
/// intentionally not user-visible. `saveSnapshot()` merges the current rolling window
/// into one .txt file under Documents/MarbleLogs so it can be picked from the Files app.
final class MobileDiagnosticLog {
    static let shared = MobileDiagnosticLog()

    private enum DiagnosticError: LocalizedError {
        case noDocumentsDirectory
        case noApplicationSupportDirectory

        var errorDescription: String? {
            switch self {
            case .noDocumentsDirectory:
                return "진단 로그 저장 위치를 찾을 수 없습니다."
            case .noApplicationSupportDirectory:
                return "진단 로그 임시 저장 위치를 찾을 수 없습니다."
            }
        }
    }

    private let queue = DispatchQueue(label: "com.jsj.marble.mobile.diagnostic-log", qos: .utility)
    private let fileManager = FileManager.default
    private let segmentLimitBytes: UInt64 = 2 * 1024 * 1024
    private let maximumLineBytes = 32 * 1024
    private var currentHandle: FileHandle?

    private init() {
        record("APP", "diagnostic logger initialized")
    }

    func record(_ category: String, _ message: String) {
        let timestamp = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        queue.async { [weak self] in
            self?.appendRecord(timestamp: timestamp, uptime: uptime, category: category, message: message)
        }
    }

    func recordWire(direction: String, object: [String: Any]) {
        let sanitized = Self.sanitizedWireObject(object)
        let text: String
        if JSONSerialization.isValidJSONObject(sanitized),
           let data = try? JSONSerialization.data(withJSONObject: sanitized, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            text = json
        } else {
            text = "type=\(object["type"] as? String ?? "unknown") keys=\(object.keys.sorted())"
        }
        record("WS_\(direction)", text)
    }

    func saveSnapshot() throws -> URL {
        let result: Result<URL, Error> = queue.sync {
            do {
                appendRecord(
                    timestamp: Date(),
                    uptime: ProcessInfo.processInfo.systemUptime,
                    category: "USER",
                    message: "diagnostic log snapshot requested"
                )
                currentHandle?.synchronizeFile()

                guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    throw DiagnosticError.noDocumentsDirectory
                }
                let exportDirectory = documents.appendingPathComponent("MarbleLogs", isDirectory: true)
                try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.timeZone = .current
                formatter.dateFormat = "yyyyMMdd-HHmmss"
                let baseName = "MarbleDiagnostic-\(formatter.string(from: Date()))"
                var destination = exportDirectory.appendingPathComponent("\(baseName).txt")
                var suffix = 2
                while fileManager.fileExists(atPath: destination.path) {
                    destination = exportDirectory.appendingPathComponent("\(baseName)-\(suffix).txt")
                    suffix += 1
                }

                var output = Data()
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
                let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
                let header = "MarbleMobile diagnostic log\nversion=\(version) build=\(build)\nrolling_window_max_bytes=\(segmentLimitBytes * 3)\n---\n"
                output.append(Data(header.utf8))

                for (label, url) in orderedSegmentURLs() where fileManager.fileExists(atPath: url.path) {
                    output.append(Data("\n===== \(label) =====\n".utf8))
                    if let segment = try? Data(contentsOf: url) {
                        output.append(segment)
                    }
                }
                try output.write(to: destination, options: .atomic)
                return .success(destination)
            } catch {
                return .failure(error)
            }
        }
        return try result.get()
    }

    private func appendRecord(timestamp: Date, uptime: TimeInterval, category: String, message: String) {
        do {
            let line = formatLine(timestamp: timestamp, uptime: uptime, category: category, message: message)
            var data = Data(line.utf8)
            if data.count > maximumLineBytes {
                let suffix = Data(" …<truncated>\n".utf8)
                let prefixCount = max(0, maximumLineBytes - suffix.count)
                data = data.prefix(prefixCount) + suffix
            }
            try rotateIfNeeded(adding: UInt64(data.count))
            let handle = try openCurrentHandle()
            handle.seekToEndOfFile()
            handle.write(data)
        } catch {
            // Diagnostics must never alter gameplay or connection behavior.
        }
    }

    private func formatLine(timestamp: Date, uptime: TimeInterval, category: String, message: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let safeCategory = category.replacingOccurrences(of: "\n", with: " ")
        let safeMessage = message.replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n")
        return "\(formatter.string(from: timestamp)) uptime=\(String(format: "%.3f", uptime)) [\(safeCategory)] \(safeMessage)\n"
    }

    private func rotateIfNeeded(adding bytes: UInt64) throws {
        let current = try currentURL()
        let existing = ((try? fileManager.attributesOfItem(atPath: current.path)[.size]) as? NSNumber)?.uint64Value ?? 0
        guard existing > 0, existing + bytes > segmentLimitBytes else { return }

        currentHandle?.closeFile()
        currentHandle = nil
        let previous1 = try rollingDirectory().appendingPathComponent("rolling-1.txt")
        let previous2 = try rollingDirectory().appendingPathComponent("rolling-2.txt")
        if fileManager.fileExists(atPath: previous2.path) { try? fileManager.removeItem(at: previous2) }
        if fileManager.fileExists(atPath: previous1.path) { try? fileManager.moveItem(at: previous1, to: previous2) }
        if fileManager.fileExists(atPath: current.path) { try? fileManager.moveItem(at: current, to: previous1) }
        _ = fileManager.createFile(atPath: current.path, contents: nil)
    }

    private func openCurrentHandle() throws -> FileHandle {
        if let currentHandle { return currentHandle }
        let url = try currentURL()
        if !fileManager.fileExists(atPath: url.path) {
            _ = fileManager.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        currentHandle = handle
        return handle
    }

    private func currentURL() throws -> URL {
        try rollingDirectory().appendingPathComponent("rolling-current.txt")
    }

    private func rollingDirectory() throws -> URL {
        guard let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw DiagnosticError.noApplicationSupportDirectory
        }
        let directory = root.appendingPathComponent("MarbleDiagnosticRolling", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func orderedSegmentURLs() -> [(String, URL)] {
        guard let directory = try? rollingDirectory() else { return [] }
        return [
            ("oldest rolling-2", directory.appendingPathComponent("rolling-2.txt")),
            ("previous rolling-1", directory.appendingPathComponent("rolling-1.txt")),
            ("current rolling-current", directory.appendingPathComponent("rolling-current.txt")),
        ]
    }

    private static func sanitizedWireObject(_ object: [String: Any]) -> [String: Any] {
        let type = object["type"] as? String ?? ""
        let redactCommunicationBody = [
            "chat", "chat_sent", "room_chat", "note_send", "note_sent", "note_received"
        ].contains(type)
        return sanitizeDictionary(object, redactCommunicationBody: redactCommunicationBody)
    }

    private static func sanitizeDictionary(
        _ dictionary: [String: Any],
        redactCommunicationBody: Bool
    ) -> [String: Any] {
        var result: [String: Any] = [:]
        for (key, value) in dictionary {
            let lower = key.lowercased()
            if lower.contains("token") || lower.contains("password") {
                result[key] = "<redacted>"
                continue
            }
            if redactCommunicationBody && ["message", "content", "body", "text"].contains(lower) {
                result[key] = "<redacted>"
                continue
            }
            result[key] = sanitizeValue(value, redactCommunicationBody: redactCommunicationBody)
        }
        return result
    }

    private static func sanitizeValue(_ value: Any, redactCommunicationBody: Bool) -> Any {
        if let dictionary = value as? [String: Any] {
            return sanitizeDictionary(dictionary, redactCommunicationBody: redactCommunicationBody)
        }
        if let array = value as? [Any] {
            return array.map { sanitizeValue($0, redactCommunicationBody: redactCommunicationBody) }
        }
        if value is String || value is NSNumber || value is NSNull { return value }
        return String(describing: value)
    }
}
