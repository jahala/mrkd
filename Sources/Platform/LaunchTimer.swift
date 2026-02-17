import os.signpost

enum LaunchTimer {
    private static let log = OSLog(subsystem: "com.mrkd.app", category: .pointsOfInterest)

    static func beginPhase(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    static func endPhase(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }
}
