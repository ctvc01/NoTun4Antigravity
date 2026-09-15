//
//  AntigravityManager.swift
//  NoTun4Antigravity
//

import Foundation
import AppKit
import Combine

// MARK: - Node Health Status
struct NodeHealthStatus: Equatable {
    var isChecking: Bool = false
    var googleLatencyMs: Int? = nil          // Google 网页实际速度
    var antigravityLatencyMs: Int? = nil     // Antigravity AI 服务实际速度
    var isAntigravityReady: Bool = false
    var errorMessage: String? = nil
    var lastChecked: Date? = nil

    var isOverallReady: Bool {
        isAntigravityReady || (googleLatencyMs != nil)
    }
}

@MainActor
final class AntigravityManager: ObservableObject {
    static let shared = AntigravityManager()

    // MARK: - Published Properties
    @Published var isRunning: Bool = false
    @Published var currentPID: pid_t? = nil
    @Published var isProxyPortReady: Bool = false
    @Published var statusMessage: String = "Ready"

    // 智能端口与节点真机健康状态
    @Published var activePort: Int = defaultProxyPort
    @Published var isAutoPortEnabled: Bool = true
    @Published var nodeHealth = NodeHealthStatus()

    // MARK: - Nonisolated Defaults (Swift 6 Safe)
    nonisolated static let defaultProxyPort: Int = 20890
    nonisolated static let defaultWhitelistLines: String = ""

    private var pollTimer: Timer?
    private var healthCheckTimer: Timer?
    private var workspaceCancellables = Set<AnyCancellable>()
    private var monitoredPort: Int = defaultProxyPort

    private init() {
        startMonitoring()
        refreshStatus()
        probeCurrentNodeHealth()
    }

    deinit {
        pollTimer?.invalidate()
        healthCheckTimer?.invalidate()
    }

    // MARK: - Monitoring

    func startMonitoring() {
        let center = NSWorkspace.shared.notificationCenter
        center.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.checkProcessStatus() }
            .store(in: &workspaceCancellables)

        center.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.checkProcessStatus() }
            .store(in: &workspaceCancellables)

        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.pollTimer = timer

        // 每 30 秒自动对当前节点进行一次真机双探活，确保状态最新
        let healthTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            self?.probeCurrentNodeHealth()
        }
        RunLoop.main.add(healthTimer, forMode: .common)
        self.healthCheckTimer = healthTimer
    }

    func refreshStatus(port: Int? = nil) {
        if let p = port {
            self.monitoredPort = p
            self.activePort = p
        } else if isAutoPortEnabled {
            if let detected = Self.detectSystemProxyPort() {
                self.monitoredPort = detected
                self.activePort = detected
            }
        }

        checkProcessStatus()
        checkProxyPort(port: self.activePort)
    }

    // MARK: - Process Inspection

    func findAntigravityApps() -> [NSRunningApplication] {
        let currentAppPID = NSRunningApplication.current.processIdentifier
        return NSWorkspace.shared.runningApplications.filter { app in
            if app.processIdentifier == currentAppPID {
                return false
            }

            if let bundleID = app.bundleIdentifier?.lowercased() {
                if bundleID.contains("notun") {
                    return false
                }
                if bundleID.contains("antigravity") {
                    return true
                }
            }

            if let name = app.localizedName?.lowercased() {
                if name == "antigravity" {
                    return true
                }
            }

            return false
        }
    }

    func checkProcessStatus() {
        let runningApps = findAntigravityApps()
        let newIsRunning = !runningApps.isEmpty
        let newPID = runningApps.first?.processIdentifier

        if self.isRunning != newIsRunning || self.currentPID != newPID {
            self.isRunning = newIsRunning
            self.currentPID = newPID
        }
    }

    // MARK: - Port Health Check & Auto Detection

    func checkProxyPort(port: Int) {
        DispatchQueue.global(qos: .userInitiated).async {
            let isOpen = Self.isPortOpen(port: port)
            Task { @MainActor in
                if self.isProxyPortReady != isOpen {
                    self.isProxyPortReady = isOpen
                }
            }
        }
    }

    nonisolated static func isPortOpen(port: Int) -> Bool {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else { return false }
        defer { close(socketFD) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)

        let flags = fcntl(socketFD, F_GETFL, 0)
        _ = fcntl(socketFD, F_SETFL, flags | O_NONBLOCK)

        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if connectResult == 0 {
            return true
        }

        if errno == EINPROGRESS {
            var pollFD = pollfd(fd: socketFD, events: Int16(POLLOUT), revents: 0)
            let pollResult = poll(&pollFD, 1, 1000)
            if pollResult > 0 && (pollFD.revents & Int16(POLLOUT)) != 0 && (pollFD.revents & Int16(POLLERR | POLLHUP | POLLNVAL)) == 0 {
                var error: Int32 = 0
                var len = socklen_t(MemoryLayout<Int32>.size)
                getsockopt(socketFD, SOL_SOCKET, SO_ERROR, &error, &len)
                return error == 0
            }
        }

        return false
    }

    nonisolated static func detectSystemProxyPort() -> Int? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        task.arguments = ["--proxy"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8) {
            for line in output.components(separatedBy: .newlines) {
                if line.contains("HTTPPort :") || line.contains("HTTPSPort :") || line.contains("SOCKSPort :") {
                    let parts = line.components(separatedBy: ":")
                    if parts.count >= 2, let port = Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)), port > 0 {
                        // 系统代理设置已明确指定该端口，直接采纳
                        return port
                    }
                }
            }
        }

        let candidateRanges = [20890...20899, 7890...7895, 10808...10809]
        for range in candidateRanges {
            for port in range {
                if isPortOpen(port: port) {
                    return port
                }
            }
        }
        return nil
    }

    // MARK: - Dual Real-World Health Check (Google + Antigravity AI)

    func probeCurrentNodeHealth() {
        guard !nodeHealth.isChecking else { return }
        nodeHealth.isChecking = true
        let port = self.activePort

        Task.detached(priority: .userInitiated) {
            let result = await Self.performDualProbe(port: port)
            await MainActor.run {
                self.nodeHealth = result
            }
        }
    }

    nonisolated static func performDualProbe(port: Int) async -> NodeHealthStatus {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 7.0
        config.timeoutIntervalForResource = 8.0
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: 1,
            kCFNetworkProxiesHTTPProxy as String: "127.0.0.1",
            kCFNetworkProxiesHTTPPort as String: port,
            kCFNetworkProxiesHTTPSEnable as String: 1,
            kCFNetworkProxiesHTTPSProxy as String: "127.0.0.1",
            kCFNetworkProxiesHTTPSPort as String: port
        ]
        let session = URLSession(configuration: config)

        // 1. 实测 Antigravity Gemini AI 服务端到端实际速度
        var antigravitySpeed: Int? = nil
        var antigravityReady = false
        let startAI = CFAbsoluteTimeGetCurrent()
        if let url = URL(string: "https://generativelanguage.googleapis.com") {
            do {
                let (_, response) = try await session.data(from: url)
                let elapsed = Int((CFAbsoluteTimeGetCurrent() - startAI) * 1000)
                if let http = response as? HTTPURLResponse {
                    // 状态码为 200, 404, 400, 401 表明成功抵达 Google AI 服务器未被阻断
                    if http.statusCode == 200 || http.statusCode == 404 || http.statusCode == 400 || http.statusCode == 401 {
                        antigravityReady = true
                        antigravitySpeed = elapsed
                    }
                }
            } catch {
                antigravityReady = false
            }
        }

        // 2. 实测 Google 网页连通性 (204 往返真实延迟)
        var googleSpeed: Int? = nil
        let startGoogle = CFAbsoluteTimeGetCurrent()
        let probeUrls = [
            "https://www.gstatic.com/generate_204",
            "https://www.google.com/generate_204"
        ]
        for probeUrlStr in probeUrls {
            if let url = URL(string: probeUrlStr) {
                do {
                    let (_, response) = try await session.data(from: url)
                    let elapsed = Int((CFAbsoluteTimeGetCurrent() - startGoogle) * 1000)
                    if let http = response as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 204) {
                        googleSpeed = elapsed
                        break
                    }
                } catch {
                    continue
                }
            }
        }

        // 若 Antigravity 通畅，但网页探测因节点分流规则暂未响应，以 Antigravity 为准回填
        if antigravityReady && googleSpeed == nil {
            googleSpeed = antigravitySpeed
        }

        let errMsg: String? = (googleSpeed == nil && !antigravityReady) ? "无法连接 Google 与 AI 节点" : nil

        return NodeHealthStatus(
            isChecking: false,
            googleLatencyMs: googleSpeed,
            antigravityLatencyMs: antigravitySpeed,
            isAntigravityReady: antigravityReady,
            errorMessage: errMsg,
            lastChecked: Date()
        )
    }

    // MARK: - Smart Whitelist Normalization

    nonisolated static func normalizeWhitelist(rawText: String) -> (noProxyEnv: String, chromiumBypass: String) {
        let rawItems = rawText
            .components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ",")))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var noProxySet = Set<String>(["localhost", "127.0.0.1", "::1", "*.local", ".local"])
        var chromiumSet = Set<String>(["localhost", "127.0.0.1", "<local>", "*.local"])

        for item in rawItems {
            let trimmed = item.lowercased()
            if trimmed.isEmpty { continue }

            if trimmed.contains("/") || trimmed.allSatisfy({ "0123456789.:".contains($0) }) {
                noProxySet.insert(trimmed)
                chromiumSet.insert(trimmed)
                continue
            }

            var domain = trimmed
            if domain.hasPrefix("*.") {
                domain = String(domain.dropFirst(2))
            } else if domain.hasPrefix(".") {
                domain = String(domain.dropFirst(1))
            } else if domain.hasPrefix("*") {
                domain = String(domain.dropFirst(1))
            }

            guard !domain.isEmpty else { continue }

            noProxySet.insert(domain)
            noProxySet.insert(".\(domain)")
            noProxySet.insert("*.\(domain)")

            chromiumSet.insert(domain)
            chromiumSet.insert("*.\(domain)")
            chromiumSet.insert(".*\(domain)")
        }

        let noProxyEnv = noProxySet.sorted().joined(separator: ",")
        let chromiumBypass = chromiumSet.sorted().joined(separator: ";")
        return (noProxyEnv, chromiumBypass)
    }

    // MARK: - System Proxy Bypass Sync

    nonisolated static func syncSystemProxyBypassDomains(rawText: String) {
        let (noProxyEnv, _) = normalizeWhitelist(rawText: rawText)
        let domains = noProxyEnv.components(separatedBy: ",").filter { !$0.isEmpty }
        guard !domains.isEmpty else { return }

        let commonServices = ["Wi-Fi", "USB 10/100/1000 LAN", "AX88179A", "Ethernet", "Thunderbolt Bridge"]

        DispatchQueue.global(qos: .utility).async {
            for service in commonServices {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                var args = ["-setproxybypassdomains", service]
                args.append(contentsOf: domains)
                task.arguments = args
                try? task.run()
                task.waitUntilExit()
            }
        }
    }

    // MARK: - Actions

    func launch(
        useProxy: Bool = true,
        proxyPort: Int = defaultProxyPort,
        rawWhitelistText: String = defaultWhitelistLines
    ) {
        Self.syncSystemProxyBypassDomains(rawText: rawWhitelistText)
        let targetPort = isAutoPortEnabled ? self.activePort : proxyPort

        if isRunning, let app = findAntigravityApps().first {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: [.activateIgnoringOtherApps])
            }
            statusMessage = "Antigravity brought to front."
            return
        }

        executeOpen(useProxy: useProxy, proxyPort: targetPort, rawWhitelistText: rawWhitelistText)
    }

    func restart(
        useProxy: Bool = true,
        proxyPort: Int = defaultProxyPort,
        rawWhitelistText: String = defaultWhitelistLines
    ) {
        statusMessage = "正在关闭旧进程..."
        Self.syncSystemProxyBypassDomains(rawText: rawWhitelistText)
        let targetPort = isAutoPortEnabled ? self.activePort : proxyPort

        Task {
            let runningApps = self.findAntigravityApps()
            for app in runningApps {
                app.terminate()
            }

            var waitCount = 0
            while waitCount < 15 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                let current = self.findAntigravityApps()
                if current.isEmpty {
                    break
                }
                waitCount += 1
            }

            let remaining = self.findAntigravityApps()
            for app in remaining {
                app.forceTerminate()
            }

            if !remaining.isEmpty {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }

            self.checkProcessStatus()

            self.statusMessage = "正在以新配置启动..."
            self.executeOpen(useProxy: useProxy, proxyPort: targetPort, rawWhitelistText: rawWhitelistText)
            self.probeCurrentNodeHealth()
        }
    }

    func terminate() {
        let runningApps = findAntigravityApps()
        for app in runningApps {
            app.terminate()
        }
        checkProcessStatus()
        statusMessage = "Antigravity terminated."
    }

    private func executeOpen(useProxy: Bool, proxyPort: Int, rawWhitelistText: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")

        var args: [String] = ["-n", "-a", "Antigravity"]
        var environment = ProcessInfo.processInfo.environment

        if useProxy {
            let portStr = String(proxyPort)
            let proxyUrl = "http://127.0.0.1:\(portStr)"
            let socksUrl = "socks5h://127.0.0.1:\(portStr)"

            let (noProxyEnv, chromiumBypass) = Self.normalizeWhitelist(rawText: rawWhitelistText)

            environment["HTTP_PROXY"] = proxyUrl
            environment["HTTPS_PROXY"] = proxyUrl
            environment["ALL_PROXY"] = socksUrl
            environment["http_proxy"] = proxyUrl
            environment["https_proxy"] = proxyUrl
            environment["all_proxy"] = socksUrl
            environment["NO_PROXY"] = noProxyEnv
            environment["no_proxy"] = noProxyEnv
            environment["GRPC_KEEPALIVE_TIME_MS"] = "10000"
            environment["GRPC_KEEPALIVE_TIMEOUT_MS"] = "5000"
            environment["GRPC_KEEPALIVE_PERMIT_WITHOUT_CALLS"] = "1"
            environment["GRPC_HTTP2_MIN_SENT_PING_INTERVAL_WITHOUT_DATA_MS"] = "5000"

            args.append(contentsOf: [
                "--env", "HTTP_PROXY=\(proxyUrl)",
                "--env", "HTTPS_PROXY=\(proxyUrl)",
                "--env", "ALL_PROXY=\(socksUrl)",
                "--env", "http_proxy=\(proxyUrl)",
                "--env", "https_proxy=\(proxyUrl)",
                "--env", "all_proxy=\(socksUrl)",
                "--env", "NO_PROXY=\(noProxyEnv)",
                "--env", "no_proxy=\(noProxyEnv)",
                "--env", "GRPC_KEEPALIVE_TIME_MS=10000",
                "--env", "GRPC_KEEPALIVE_TIMEOUT_MS=5000",
                "--env", "GRPC_KEEPALIVE_PERMIT_WITHOUT_CALLS=1"
            ])

            args.append(contentsOf: [
                "--args",
                "--proxy-server=\(proxyUrl)",
                "--proxy-bypass-list=\(chromiumBypass)",
                "--disable-quic",
                "--ssl-version-min=tls1.2"
            ])
        } else {
            environment.removeValue(forKey: "HTTP_PROXY")
            environment.removeValue(forKey: "HTTPS_PROXY")
            environment.removeValue(forKey: "ALL_PROXY")
            environment.removeValue(forKey: "http_proxy")
            environment.removeValue(forKey: "https_proxy")
            environment.removeValue(forKey: "all_proxy")
            environment.removeValue(forKey: "NO_PROXY")
            environment.removeValue(forKey: "no_proxy")
            environment.removeValue(forKey: "GRPC_KEEPALIVE_TIME_MS")
            environment.removeValue(forKey: "GRPC_KEEPALIVE_TIMEOUT_MS")
            environment.removeValue(forKey: "GRPC_KEEPALIVE_PERMIT_WITHOUT_CALLS")
            environment.removeValue(forKey: "GRPC_HTTP2_MIN_SENT_PING_INTERVAL_WITHOUT_DATA_MS")
        }

        task.arguments = args
        task.environment = environment

        do {
            try task.run()
            statusMessage = useProxy ? "已应用代理 (端口 \(proxyPort)) 并启动" : "已直连干净启动 (无代理)"
        } catch {
            statusMessage = "启动失败: \(error.localizedDescription)"
            print("Failed to execute open for Antigravity: \(error)")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.checkProcessStatus()
        }
    }
}
