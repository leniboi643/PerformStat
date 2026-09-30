import Foundation

/// Kernel-notified memory pressure via DISPATCH_SOURCE_TYPE_MEMORYPRESSURE.
/// Event-driven: no polling at all; fires only when the system pressure class changes.
enum MemoryPressureMonitor {
    private static var source: DispatchSourceMemoryPressure?
    private static let lock = NSLock()
    private static var currentLabel = "normal"

    static func start(onChange: @escaping (String) -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard source == nil else { return }
        let src = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        src.setEventHandler { [weak src] in
            let label: String
            switch src?.data ?? 0 {
            case DispatchSource.MemoryPressureEvent.critical.rawValue:
                label = "critical"
            case DispatchSource.MemoryPressureEvent.warning.rawValue:
                label = "warning"
            default:
                label = "normal"
            }
            currentLabel = label
            onChange(label)
        }
        src.resume()
        source = src
        // dispatch sources don't report the initial class; read it once via proc_pidinfo
        currentLabel = systemPressureClass()
        onChange(currentLabel)
    }

    static var label: String { lock.lock(); defer { lock.unlock() }; return currentLabel }

    private static func systemPressureClass() -> String {
        // cheap heuristic from mach memory status: compressor-heavy systems are under pressure
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutableBytes(of: &vm) { raw -> kern_return_t in
            host_statistics64(SystemMonitor.hostPort, HOST_VM_INFO64, raw.bindMemory(to: integer_t.self).baseAddress!, &count)
        }
        if kr == KERN_SUCCESS {
            // compressor-heavy systems are effectively under pressure
            let pageSize = UInt64(vm_kernel_page_size)
            let total = SystemMonitor.facts.totalMemory
            let compressed = UInt64(vm.compressor_page_count) * pageSize
            let ratio = total > 0 ? Double(compressed) / Double(total) : 0
            if ratio > 0.30 { return "warning" }
        }
        return "normal"
    }
}
