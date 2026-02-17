import Foundation

enum FileTier: Int, Comparable {
    case small = 1    // <50KB — full immediate render
    case medium = 2   // 50KB-500KB — progressive render
    case large = 3    // 500KB-5MB — progressive render, first-screen priority
    case huge = 4     // >5MB — mmap read + progressive render

    static func < (lhs: FileTier, rhs: FileTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum FileTierRouter {

    static func tier(for url: URL) -> FileTier {
        let size = fileSize(at: url)
        switch size {
        case ..<50_000:
            return .small
        case 50_000..<500_000:
            return .medium
        case 500_000..<5_000_000:
            return .large
        default:
            return .huge
        }
    }

    static func fileSize(at url: URL) -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else {
            return 0
        }
        return size
    }
}
