import AppKit

/// Coordinates sampling, formatting, and the overlay window lifecycle.
final class OverlayManager: NSObject {
    private var window: DesktopOverlayWindow?
    private var view: PerformStatView?
    private let settings = SettingsModel.shared

    private var timer: Timer?
    private var lastDisk: DiskSample?
    private var lastNet: NetSample?
    private var lastCPURefresh = Date.distantPast
    private var lastGPURefresh = Date.distantPast
    private var lastMemoryRefresh = Date.distantPast
    private var lastHeavyRefresh = Date.distantPast

    // latest sampled values
    private var cpuPercent: Double?
    private var gpuPercent: Double?
    private var memUsed: Double?
    private var memTotal: Double = 0
    private var swapGB: Double = 0
    private var diskRead: Double = 0
    private var diskWrite: Double = 0
    private var netIn: Double = 0
    private var netOut: Double = 0
    private var power: PowerSample?
    private var pressureLabelValue = "normal"

    override init() {
        super.init()
        memTotal = Double(SystemMonitor.facts.totalMemory) / 1_073_741_824.0
        power = PowerMonitor.sample()
        MemoryPressureMonitor.start { [weak self] label in
            self?.pressureLabelValue = label
        }
        rebuildWindow()
        applyVisibility()
    }

    func start() {
        restartTimer()
        // prime deltas so the first visible frame has real numbers
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            _ = SystemMonitor.cpuLoad()
            _ = DiskMonitor.sample().map { self.lastDisk = $0 }
            _ = NetworkMonitor.sample().map { self.lastNet = $0 }
            DispatchQueue.main.async { [weak self] in self?.refresh(force: true) }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: window lifecycle

    func rebuildWindow() {
        guard let screen = preferredScreen() else { return }
        // tear down any previous window first so we never stack duplicates
        if let old = window {
            old.orderOut(nil)
            old.contentView = nil
            window = nil
            view = nil
        }
        let newWindow = DesktopOverlayWindow(screen: screen)
        let contentView = PerformStatView(frame: NSRect(x: 0, y: 0, width: 900, height: 120))
        newWindow.contentView = contentView
        window = newWindow
        view = contentView
        newWindow.positionIn(screen, settings: settings)
        reposition()
    }

    private func preferredScreen() -> NSScreen? {
        if settings.preferredScreen == "main" {
            return NSScreen.main ?? NSScreen.screens.first
        }
        for screen in NSScreen.screens.dropFirst() {
            if String(screen.localizedName.hashValue) == settings.preferredScreen {
                return screen
            }
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    func reposition() {
        guard let window, let screen = preferredScreen() else { return }
        window.positionIn(screen, settings: settings)
        window.assertDesktopLevel()
    }

    func applyVisibility() {
        if settings.isVisible {
            window?.alphaValue = 1
            window?.orderFrontRegardless()
            window?.assertDesktopLevel()
        } else {
            window?.orderOut(nil)
        }
    }

    func applySettingsChange() {
        restartTimer()
        applyVisibility()
        reposition()
        refresh(force: true)
    }

    private func restartTimer() {
        timer?.invalidate()
        let interval = max(settings.updateInterval, 0.25)
        let t = Timer(timeInterval: interval, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: sampling

    @objc private func tick() {
        refresh(force: false)
    }

    private func refresh(force: Bool) {
        guard settings.isVisible else { return }
        let now = Date()
        let interval = max(settings.updateInterval, 0.25)

        // lightweight every tick
        if force || now.timeIntervalSince(lastCPURefresh) >= interval {
            lastCPURefresh = now
            cpuPercent = SystemMonitor.cpuLoad().map { $0 * 100 }
        }
        if force || now.timeIntervalSince(lastGPURefresh) >= interval {
            lastGPURefresh = now
            gpuPercent = GPUMonitor.utilization()
        }

        // medium cadence: every ~2 ticks
        if force || now.timeIntervalSince(lastMemoryRefresh) >= max(interval * 2, 1.0) {
            lastMemoryRefresh = now
            if let m = MemoryMonitor.sample() {
                memUsed = m.usedGB
                swapGB = m.swapGB
            }
        }

        // battery: every ~4 ticks, min 2 s (bundled with the heavy pass)
        let heavy = max(interval * 4, 2.0)
        if force || now.timeIntervalSince(lastHeavyRefresh) >= heavy {
            lastHeavyRefresh = now
            if let d = DiskMonitor.sample() {
                if let last = lastDisk {
                    let dt = d.timestamp.timeIntervalSince(last.timestamp)
                    if dt > 0.2 {
                        diskRead = Double(d.bytesRead &- last.bytesRead) / dt
                        diskWrite = Double(d.bytesWritten &- last.bytesWritten) / dt
                    }
                }
                lastDisk = d
            }
            if let n = NetworkMonitor.sample() {
                if let last = lastNet {
                    let dt = n.timestamp.timeIntervalSince(last.timestamp)
                    if dt > 0.2 {
                        netIn = Double(n.bytesIn &- last.bytesIn) / dt
                        netOut = Double(n.bytesOut &- last.bytesOut) / dt
                    }
                }
                lastNet = n
            }
            power = PowerMonitor.sample()
        }

        let lines = buildLines()
        view?.update(lines: lines)

        // PERFORMSTAT_DEBUG=1 prints the live lines to stderr (used for headless verification)
        if ProcessInfo.processInfo.environment["PERFORMSTAT_DEBUG"] == "1", force || Int(now.timeIntervalSince1970) % 5 == 0 {
            FileHandle.standardError.write(lines.joined(separator: "\n").appending("\n\n").data(using: .utf8)!)
        }
    }

    // MARK: formatting

    private func pressureLabel(_ level: String) -> String {
        level
    }

    private func batteryLabel() -> String? {
        guard let p = power, p.hasBattery else { return nil }
        var s = "battery: \(p.percent)%"
        if p.isCharging { s += " ⚡" }
        else if p.onAC { s += " (ac)" }
        else if p.timeToEmpty > 0 {
            s += String(format: " (%dh %02dm)", p.timeToEmpty / 60, p.timeToEmpty % 60)
        }
        return s
    }

    private func buildLines() -> [String] {
        var lines: [String] = []
        let flags = settings.enabledStats
        let f = SystemMonitor.facts

        func pct(_ value: Double?) -> String {
            guard let v = value else { return "--" }
            return String(format: "%.0f%%", v)
        }

        if flags.contains(.system) {
            lines.append("performstat v1.0 — \(f.chipModel.lowercased())")  // HUD stays lowercase
            lines.append("\(f.osVersion.lowercased()) · \(f.cpuCoreCount) cores · \(String(format: "%.0f", memTotal)) gb ram")
        }

        if flags.contains(.cpu) {
            lines.append("cpu: \(pct(cpuPercent))")
        }
        if flags.contains(.gpu) {
            lines.append("gpu: \(pct(gpuPercent))")
        }
        if flags.contains(.memory) {
            lines.append("memory: \(String(format: "%.1f", memUsed ?? 0)) / \(String(format: "%.1f", memTotal)) gb")
        }
        if flags.contains(.pressure) {
            lines.append("memory pressure: \(pressureLabel(pressureLabelValue))")
        }
        if flags.contains(.swap) {
            lines.append("swap: \(String(format: "%.1f", swapGB)) gb")
        }
        if flags.contains(.disk) {
            lines.append("disk read: \(String.bytes(diskRead))/s")
            lines.append("disk write: \(String.bytes(diskWrite))/s")
        }
        if flags.contains(.network) {
            lines.append("network ↓ \(String.bytes(netIn))/s ↑ \(String.bytes(netOut))/s")
        }
        if flags.contains(.uptime) {
            let up = SystemMonitor.uptime
            let h = Int(up) / 3600, m = (Int(up) % 3600) / 60
            lines.append("uptime: \(h)h \(String(format: "%02dm", m))")
        }
        if flags.contains(.thermal) {
            lines.append("thermal: \(ThermalState.label())")
        }
        if flags.contains(.battery), let b = batteryLabel() {
            lines.append(b)
        }
        return lines
    }
}
