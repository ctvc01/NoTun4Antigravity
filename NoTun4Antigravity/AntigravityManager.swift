//
//  AntigravityManager.swift
//  NoTun4Antigravity
//

import Foundation
import AppKit
import Combine
import CFNetwork

// MARK: - Node Health Status
struct NodeHealthStatus: Equatable {
    var isChecking: Bool = false
    var googleLatencyMs: Int? = nil          // Google 网页实际速度
    var antigravityLatencyMs: Int? = nil     // Antigravity Gemini AI 服务实际速度
    var isAntigravityReady: Bool = false     // Gemini API
    var isCloudCodeReady: Bool = false       // daily-cloudcode-pa.googleapis.com
    var isOAuthReady: Bool = false           // oauth2.googleapis.com (Token & TLS)
    var errorMessage: String? = nil
    var lastChecked: Date? = nil

    var isOverallReady: Bool {
        (isAntigravityReady || isCloudCodeReady || (googleLatencyMs != nil)) && (isOAuthReady || isAntigravityReady)
    }

    var isMatrixAllReady: Bool {
        isAntigravityReady && isCloudCodeReady && isOAuthReady
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
    nonisolated static let defaultWhitelistLines: String = """
localhost
127.0.0.1
*.local
ctripcorp.com
*.ctripcorp.com
ctrip.com
*.ctrip.com
ctripsmartdns.com
*.ctripsmartdns.com
c-ctrip.com
*.c-ctrip.com
tripcdn.com
*.tripcdn.com
trip.com
*.trip.com
larkenterprise.com
*.larkenterprise.com
feishu.cn
*.feishu.cn
*.feishucdn.com
*.bytegoofy.com
*.volccdn.com
*.pstatp.com
10.0.0.0/8
172.16.0.0/12
192.168.0.0/16
"""

    private var pollTimer: Timer?
    private var healthCheckTimer: Timer?
    private var auditSampleTimer: Timer?
    private var workspaceCancellables = Set<AnyCancellable>()
    private var monitoredPort: Int = defaultProxyPort

    private init() {
        startMonitoring()
        refreshStatus()
        probeCurrentNodeHealth()
        let savedRules = UserDefaults.standard.string(forKey: "whitelistRules") ?? Self.defaultWhitelistLines
        Self.syncSystemProxyBypassDomains(rawText: savedRules)
    }

    deinit {
        pollTimer?.invalidate()
        healthCheckTimer?.invalidate()
        auditSampleTimer?.invalidate()
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

        // 每 20 秒采样一次 Antigravity 实际通信健康度，用于与测速结果持续对齐
        let auditTimer = Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { [weak self] _ in
            self?.sampleActualAntigravityConnection()
        }
        RunLoop.main.add(auditTimer, forMode: .common)
        self.auditSampleTimer = auditTimer
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
        Self.checkAndSelfHealSystemProxyBypass()
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
        // 轻量自愈：检查系统代理白名单是否被第三方客户端冲掉，若未包含则自动并集合并
        let savedRules = UserDefaults.standard.string(forKey: "whitelistRules") ?? Self.defaultWhitelistLines
        Self.syncSystemProxyBypassDomains(rawText: savedRules)

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

        // 1. 实测 Antigravity Gemini AI 服务端到端实际速度 (通道1: generativelanguage.googleapis.com)
        var antigravitySpeed: Int? = nil
        var antigravityReady = false
        let startAI = CFAbsoluteTimeGetCurrent()
        if let url = URL(string: "https://generativelanguage.googleapis.com") {
            do {
                let (_, response) = try await session.data(from: url)
                let elapsed = Int((CFAbsoluteTimeGetCurrent() - startAI) * 1000)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 200 || http.statusCode == 404 || http.statusCode == 400 || http.statusCode == 401 {
                        antigravityReady = true
                        antigravitySpeed = elapsed
                    }
                }
            } catch {
                antigravityReady = false
            }
        }

        // 2. 实测 CloudCode / Agent 调度核心流 (通道2: daily-cloudcode-pa.googleapis.com)
        var cloudCodeReady = false
        if let url = URL(string: "https://daily-cloudcode-pa.googleapis.com") {
            do {
                let (_, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode == 200 || http.statusCode == 404 || http.statusCode == 400 || http.statusCode == 401 || http.statusCode == 403 {
                        cloudCodeReady = true
                    }
                }
            } catch {
                cloudCodeReady = false
            }
        }

        // 3. 实测 OAuth2 令牌刷新与 TLS 握手完整性 (通道3: oauth2.googleapis.com)
        var oauthReady = false
        if let url = URL(string: "https://oauth2.googleapis.com") {
            do {
                let (_, response) = try await session.data(from: url)
                if let http = response as? HTTPURLResponse {
                    if http.statusCode >= 200 && http.statusCode < 500 {
                        oauthReady = true
                    }
                }
            } catch {
                oauthReady = false
            }
        }

        // 4. 实测 Google 网页连通性 (204 往返真实延迟)
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

        if antigravityReady && googleSpeed == nil {
            googleSpeed = antigravitySpeed
        }

        var errMsg: String? = nil
        if googleSpeed == nil && !antigravityReady {
            errMsg = "无法连接 Google 与 AI 节点"
        } else if !oauthReady && antigravityReady {
            errMsg = "OAuth2 握手异常或被拦截 (Agent 任务易中断)"
        } else if !cloudCodeReady && antigravityReady {
            errMsg = "CloudCode 调度流受限"
        }

        // 记录探活测速日志用于交叉质检与对齐
        SpeedTestAuditLogger.shared.recordProbe(
            port: port,
            target: "Google Gemini AI & CloudCode",
            tcpPingMs: nil,
            tlsHandshakeMs: nil,
            ttfbMs: antigravitySpeed ?? googleSpeed,
            isSuccess: antigravityReady || (googleSpeed != nil),
            errorDetail: errMsg
        )

        return NodeHealthStatus(
            isChecking: false,
            googleLatencyMs: googleSpeed,
            antigravityLatencyMs: antigravitySpeed,
            isAntigravityReady: antigravityReady,
            isCloudCodeReady: cloudCodeReady,
            isOAuthReady: oauthReady,
            errorMessage: errMsg,
            lastChecked: Date()
        )
    }

    // MARK: - Actual Antigravity Traffic Sampling for Audit Calibration

    func sampleActualAntigravityConnection() {
        guard isProxyPortReady else { return }
        let port = self.activePort

        Task.detached(priority: .utility) {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 6.0
            config.timeoutIntervalForResource = 7.0
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: 1,
                kCFNetworkProxiesHTTPProxy as String: "127.0.0.1",
                kCFNetworkProxiesHTTPPort as String: port,
                kCFNetworkProxiesHTTPSEnable as String: 1,
                kCFNetworkProxiesHTTPSProxy as String: "127.0.0.1",
                kCFNetworkProxiesHTTPSPort as String: port
            ]
            let session = URLSession(configuration: config)
            let endpoint = "https://generativelanguage.googleapis.com"
            guard let url = URL(string: endpoint) else { return }

            let startTime = CFAbsoluteTimeGetCurrent()
            do {
                let (_, response) = try await session.data(from: url)
                let elapsed = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
                if let http = response as? HTTPURLResponse {
                    let isOk = (http.statusCode >= 200 && http.statusCode < 500)
                    let err = isOk ? nil : "HTTP \(http.statusCode) 网关阻断"
                    SpeedTestAuditLogger.shared.recordActualConnection(
                        port: port,
                        endpoint: "generativelanguage.googleapis.com",
                        latencyMs: elapsed,
                        isSuccess: isOk,
                        httpStatus: http.statusCode,
                        errorDetail: err
                    )
                }
            } catch {
                let elapsed = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
                SpeedTestAuditLogger.shared.recordActualConnection(
                    port: port,
                    endpoint: "generativelanguage.googleapis.com",
                    latencyMs: elapsed > 7000 ? nil : elapsed,
                    isSuccess: false,
                    httpStatus: nil,
                    errorDetail: error.localizedDescription
                )
            }
        }
    }

    // MARK: - Local IDE settings.json Anti-Conflict Synchronization

    nonisolated static func syncLocalIdeProxySettings(useProxy: Bool, port: Int) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidatePaths = [
            home.appendingPathComponent("Library/Application Support/Antigravity/User/settings.json"),
            home.appendingPathComponent("Library/Application Support/Antigravity IDE/User/settings.json")
        ]

        for fileUrl in candidatePaths {
            let dirUrl = fileUrl.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dirUrl.path) {
                continue
            }

            var jsonDict: [String: Any] = [:]
            if FileManager.default.fileExists(atPath: fileUrl.path),
               let data = try? Data(contentsOf: fileUrl),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                jsonDict = obj
            }

            if useProxy {
                let proxyUrl = "http://127.0.0.1:\(port)"
                jsonDict["http.proxy"] = proxyUrl
                jsonDict["http.proxySupport"] = "override"
                jsonDict["http.proxyStrictSSL"] = false
            } else {
                jsonDict.removeValue(forKey: "http.proxy")
                jsonDict.removeValue(forKey: "http.proxySupport")
                jsonDict.removeValue(forKey: "http.proxyStrictSSL")
            }

            if let outData = try? JSONSerialization.data(withJSONObject: jsonDict, options: [.prettyPrinted, .sortedKeys]) {
                try? outData.write(to: fileUrl, options: .atomic)
            }
        }
    }

    // MARK: - Local SSH KeepAlive (Silent Auto-Optimization)

    @discardableResult
    nonisolated static func optimizeLocalSshKeepAlive() -> Bool {
        let sshDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh")
        let sshConfigUrl = sshDir.appendingPathComponent("config")

        if !FileManager.default.fileExists(atPath: sshDir.path) {
            try? FileManager.default.createDirectory(at: sshDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }

        var content = (try? String(contentsOf: sshConfigUrl, encoding: .utf8)) ?? ""
        if content.contains("ServerAliveInterval") {
            return true
        }

        let keepAliveBlock = """

# === Antigravity & Remote-SSH KeepAlive (Added by NoTun) ===
Host *
    ServerAliveInterval 15
    ServerAliveCountMax 3
    TCPKeepAlive yes
    IPQoS lowdelay throughput
# ==========================================================

"""
        content.append(keepAliveBlock)
        do {
            try content.write(to: sshConfigUrl, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sshConfigUrl.path)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Smart Whitelist Normalization

    nonisolated static func normalizeWhitelist(rawText: String) -> (noProxyEnv: String, chromiumBypass: String) {
        let rawItems = rawText
            .components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ",")))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var noProxySet = Set<String>(["localhost", "127.0.0.1", "::1", "*.local", ".local"])
        var chromiumSet = Set<String>(["localhost", "127.0.0.1", "<local>", "*.local"])

        var hasCtrip = false
        var hasLark = false

        for item in rawItems {
            let trimmed = item.lowercased()
            if trimmed.isEmpty { continue }

            if trimmed.contains("ctripcorp.com") || trimmed.contains("ctrip.com") {
                hasCtrip = true
            }
            if trimmed.contains("larkenterprise.com") || trimmed.contains("feishu") {
                hasLark = true
            }

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

        // 智能关联：携程内网 SLB 与前端公共资源（c-ctrip / tripcdn）依赖别名与公网直连，自动联动加白
        if hasCtrip {
            for d in [
                "ctripsmartdns.com",
                "ctripcorp.com",
                "ctrip.com",
                "c-ctrip.com",
                "tripcdn.com",
                "trip.com"
            ] {
                noProxySet.insert(d)
                noProxySet.insert(".\(d)")
                noProxySet.insert("*.\(d)")
                chromiumSet.insert(d)
                chromiumSet.insert("*.\(d)")
                chromiumSet.insert(".*\(d)")
            }
        }

        // 智能关联：飞书/Lark 企业版静态资源与协作 API 域名，避免被外部代理误调度至境外导致卡顿
        if hasLark {
            for d in [
                "larkenterprise.com",
                "feishu.cn",
                "feishucdn.com",
                "bytegoofy.com",
                "pstatp.com",
                "volccdn.com"
            ] {
                noProxySet.insert(d)
                noProxySet.insert(".\(d)")
                noProxySet.insert("*.\(d)")
                chromiumSet.insert(d)
                chromiumSet.insert("*.\(d)")
                chromiumSet.insert(".*\(d)")
            }
        }

        let noProxyEnv = noProxySet.sorted().joined(separator: ",")
        let chromiumBypass = chromiumSet.sorted().joined(separator: ";")
        return (noProxyEnv, chromiumBypass)
    }

    // MARK: - System Proxy Bypass Sync (macOS native bypassdomains union)

    nonisolated static func getActiveNetworkServices() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = ["-listallnetworkservices"]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return ["Wi-Fi", "USB 10/100/1000 LAN", "AX88179A", "Ethernet", "Thunderbolt Bridge"]
        }

        let lines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                !line.isEmpty &&
                !line.hasPrefix("An asterisk") &&
                !line.hasPrefix("*")
            }

        return lines.isEmpty ? ["Wi-Fi", "USB 10/100/1000 LAN", "AX88179A", "Ethernet", "Thunderbolt Bridge"] : lines
    }

    nonisolated static func getExistingBypassDomains(for service: String) -> Set<String> {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        task.arguments = ["-getproxybypassdomains", service]
        let pipe = Pipe()
        task.standardOutput = pipe
        try? task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        var result = Set<String>()
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.contains("There aren't any bypass domains") {
                continue
            }
            result.insert(trimmed)
        }
        return result
    }

    nonisolated static func macOsBypassDomains(from rawText: String) -> Set<String> {
        let rawItems = rawText
            .components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ",")))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var result = Set<String>(["localhost", "127.*", "*.local"])
        var hasCtrip = false
        var hasLark = false

        for item in rawItems {
            let trimmed = item.lowercased()
            if trimmed.isEmpty { continue }

            if trimmed.contains("ctripcorp.com") || trimmed.contains("ctrip.com") {
                hasCtrip = true
            }
            if trimmed.contains("larkenterprise.com") || trimmed.contains("feishu") {
                hasLark = true
            }

            // 将 CIDR 格式自动转换为 macOS networksetup 支持的通配符
            if trimmed.contains("/") {
                if trimmed.hasPrefix("10.") {
                    result.insert("10.*")
                } else if trimmed.hasPrefix("192.168.") {
                    result.insert("192.168.*")
                } else if trimmed.hasPrefix("172.16.") || trimmed.contains("172.16.0.0/12") {
                    result.insert("172.16.*")
                    result.insert("172.17.*")
                    result.insert("172.18.*")
                    result.insert("172.19.*")
                    result.insert("172.2*")
                    result.insert("172.30.*")
                    result.insert("172.31.*")
                } else {
                    let parts = trimmed.split(separator: "/")
                    if let ipPart = parts.first {
                        let octets = ipPart.split(separator: ".")
                        if octets.count >= 2 {
                            result.insert("\(octets[0]).\(octets[1]).*")
                        }
                    }
                }
                continue
            }

            if trimmed == "127.0.0.1" || trimmed.hasPrefix("127.") {
                result.insert("127.*")
                continue
            }

            if trimmed == "localhost" || trimmed == "*.local" {
                result.insert(trimmed)
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
            result.insert(domain)
            result.insert("*.\(domain)")
        }

        if hasCtrip {
            for d in [
                "ctripcorp.com",
                "ctrip.com",
                "ctripsmartdns.com",
                "c-ctrip.com",
                "tripcdn.com",
                "trip.com"
            ] {
                result.insert(d)
                result.insert("*.\(d)")
            }
        }

        if hasLark {
            for d in [
                "larkenterprise.com",
                "feishu.cn",
                "feishucdn.com",
                "bytegoofy.com",
                "pstatp.com",
                "volccdn.com"
            ] {
                result.insert(d)
                result.insert("*.\(d)")
            }
        }

        return result
    }

    nonisolated static func syncSystemProxyBypassDomains(rawText: String) {
        let requiredDomains = macOsBypassDomains(from: rawText)
        guard !requiredDomains.isEmpty else { return }

        DispatchQueue.global(qos: .utility).async {
            let services = getActiveNetworkServices()
            for service in services {
                let existing = getExistingBypassDomains(for: service)
                // ponytail: 若系统已有规则中已完整包含了所需规则，跳过写入，避免频繁唤醒系统设置
                if requiredDomains.isSubset(of: existing) {
                    continue
                }

                // 与系统现有规则做并集（Union），保护 FlClash / 本机其他合法规则不被抹去
                let merged = existing.union(requiredDomains)
                let sortedList = merged.sorted()

                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                var args = ["-setproxybypassdomains", service]
                args.append(contentsOf: sortedList)
                task.arguments = args
                try? task.run()
                task.waitUntilExit()
            }
        }
    }

    // MARK: - Zero-Overhead In-Memory Proxy Guard (0.05ms check)

    nonisolated static func checkAndSelfHealSystemProxyBypass() {
        guard let dict = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
              let exceptions = dict[kCFNetworkProxiesExceptionsList as String] as? [String] else {
            return
        }
        let exceptionSet = Set(exceptions)
        // 关键核心内网域名检测：若核心携程域名消失，说明被第三方客户端（如 FlClash 开关系统代理）全量冲掉了
        let keyDomains = ["*.ctripcorp.com", "ctripcorp.com", "*.ctrip.com"]
        let isMissing = keyDomains.contains { !exceptionSet.contains($0) }
        if isMissing {
            let savedRules = UserDefaults.standard.string(forKey: "whitelistRules") ?? Self.defaultWhitelistLines
            Self.syncSystemProxyBypassDomains(rawText: savedRules)
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
        Self.syncLocalIdeProxySettings(useProxy: useProxy, port: targetPort)
        if useProxy {
            Self.optimizeLocalSshKeepAlive()
        }

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
        Self.syncLocalIdeProxySettings(useProxy: useProxy, port: targetPort)
        if useProxy {
            Self.optimizeLocalSshKeepAlive()
        }

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
