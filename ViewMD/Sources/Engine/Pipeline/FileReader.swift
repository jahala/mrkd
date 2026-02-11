import Foundation

enum FileReader {

    enum ReadResult {
        case content(String)
        case error(String)
    }

    // Read file, choosing strategy based on size tier
    static func read(url: URL) -> ReadResult {
        // Check for binary files first
        if isBinaryFile(at: url) {
            return .error("This file appears to be binary and cannot be displayed as markdown.")
        }

        let tier = FileTierRouter.tier(for: url)

        do {
            switch tier {
            case .small, .medium, .large:
                let content = try String(contentsOf: url, encoding: .utf8)
                return .content(content)
            case .huge:
                // >5MB: memory-mapped read
                return readMapped(url: url)
            }
        } catch {
            return .error("Could not read file: \(error.localizedDescription)")
        }
    }

    private static func readMapped(url: URL) -> ReadResult {
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard let content = String(data: data, encoding: .utf8) else {
                return .error("File is not valid UTF-8 text")
            }
            return .content(content)
        } catch {
            return .error("Could not read file: \(error.localizedDescription)")
        }
    }

    private static func isBinaryFile(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 1024) else { return false }
        return data.contains(0x00) // Null byte indicates binary
    }
}
