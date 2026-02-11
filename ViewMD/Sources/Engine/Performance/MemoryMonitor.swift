import Foundation
import os.log

final class MemoryMonitor: @unchecked Sendable {

    static let shared = MemoryMonitor()

    private let logger = Logger(subsystem: "com.mrkd", category: "memory")
    private let budgetBytes: Int64 = 120 * 1024 * 1024 // 120MB hard cap
    private let warningRatio: Double = 0.8              // warn at 80%

    private init() {}

    /// Current process resident memory in bytes.
    var currentMemoryBytes: Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int64(info.resident_size)
    }

    var isNearBudget: Bool {
        Double(currentMemoryBytes) > Double(budgetBytes) * warningRatio
    }

    var isOverBudget: Bool {
        currentMemoryBytes > budgetBytes
    }

    /// Log a warning if memory is near or over budget.
    func checkAndLog() {
        let mb = Double(currentMemoryBytes) / (1024 * 1024)
        if isOverBudget {
            logger.warning("Memory over budget: \(mb, format: .fixed(precision: 1))MB / 120MB")
        } else if isNearBudget {
            logger.info("Memory near budget: \(mb, format: .fixed(precision: 1))MB / 120MB")
        }
    }
}
