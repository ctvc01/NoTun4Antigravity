//
//  AntigravityManager.swift
//  NoTun4Antigravity
//

import Foundation
import AppKit
import Combine

@MainActor
final class AntigravityManager: ObservableObject {
    static let shared = AntigravityManager()

    // MARK: - Published Properties
    @Published var isRunning: Bool = false
    @Published var currentPID: pid_t? = nil
    @Published var isProxyPortReady: Bool = false
    @Published var statusMessage: String = "Ready"

    // MARK: - Nonisolated Defaults (Swift 6 Safe)
    nonisolated static let defaultProxyPort: Int = 20890
    nonisolated static let defaultWhitelistLines: String = ""

    private var pollTimer: Timer?
    private var workspaceCancellables = Set<AnyCancellable>()
    private var monitoredPort: Int = defaultProxyPort

    private init() {
        startMonitoring()
        refreshStatus()
    }

    deinit {
        pollTimer?.invalidate()
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
    }

    func refreshStatus(port: Int? = nil) {
        if let p = port {
            self.monitoredPort = p
        }
        checkProcessStatus()
        checkProxyPort(port: self.monitoredPort)
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

    // MARK: - Port Health Check

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
            let pollResult = poll(&pollFD, 1, 300)
            if pollResult > 0 && (pollFD.revents & Int16(POLLOUT)) != 0 && (pollFD.revents & Int16(POLLERR | POLLHUP | POLLNVAL)) == 0 {
                var error: Int32 = 0
                var len = socklen_t(MemoryLayout<Int32>.size)
                getsockopt(socketFD, SOL_SOCKET, SO_ERROR, &error, &len)
                return error == 0
            }
        }

        return false
    }

    // MARK: - Smart Whitelist Normalization (Multi-level Subdomain & Chromium Bypass)

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

            // IP 或者 CIDR (如 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.1)
            if trimmed.contains("/") || trimmed.allSatisfy({ "0123456789.:".contains($0) }) {
                noProxySet.insert(trimmed)
                chromiumSet.insert(trimmed)
                continue
            }

            // 提取干净的主域名（去除前面的 *. 或 . 或 *）
            var domain = trimmed
            if domain.hasPrefix("*.") {
                domain = String(domain.dropFirst(2))
            } else if domain.hasPrefix(".") {
                domain = String(domain.dropFirst(1))
            } else if domain.hasPrefix("*") {
                domain = String(domain.dropFirst(1))
            }

            guard !domain.isEmpty else { continue }

            // 智能为 POSIX / Node.js / Python / Chromium 生成全场景无死角匹配集
            // 确保多级子域名 (如 product.activity.ctripcorp.com) 100% 命中
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

    // MARK: - Actions

    func launch(
        useProxy: Bool = true,
        proxyPort: Int = defaultProxyPort,
        rawWhitelistText: String = defaultWhitelistLines
    ) {
        if isRunning, let app = findAntigravityApps().first {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: [.activateIgnoringOtherApps])
            }
            statusMessage = "Antigravity brought to front."
            return
        }

        executeOpen(useProxy: useProxy, proxyPort: proxyPort, rawWhitelistText: rawWhitelistText)
    }

    func restart(
        useProxy: Bool = true,
        proxyPort: Int = defaultProxyPort,
        rawWhitelistText: String = defaultWhitelistLines
    ) {
        statusMessage = "正在关闭旧进程..."

        Task {
            // 1. 先发送优雅终止信号
            let runningApps = self.findAntigravityApps()
            for app in runningApps {
                app.terminate()
            }

            // 2. 轮询等待进程真正退出（最多等待 1.5 秒）
            var waitCount = 0
            while waitCount < 15 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                let current = self.findAntigravityApps()
                if current.isEmpty {
                    break
                }
                waitCount += 1
            }

            // 3. 若仍有残留进程未退出，强制强杀（forceTerminate / SIGKILL）
            let remaining = self.findAntigravityApps()
            for app in remaining {
                app.forceTerminate()
            }

            if !remaining.isEmpty {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }

            self.checkProcessStatus()

            // 4. 以最新参数与环境变量干净拉起
            self.statusMessage = "正在以新配置启动..."
            self.executeOpen(useProxy: useProxy, proxyPort: proxyPort, rawWhitelistText: rawWhitelistText)
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

        if useProxy {
            let portStr = String(proxyPort)
            let proxyUrl = "http://127.0.0.1:\(portStr)"
            let socksUrl = "socks5h://127.0.0.1:\(portStr)"

            let (noProxyEnv, chromiumBypass) = Self.normalizeWhitelist(rawText: rawWhitelistText)

            // 1. 通过 open --env 将环境变量显式注入到被拉起的 GUI 应用程序进程树中
            args.append(contentsOf: [
                "--env", "HTTP_PROXY=\(proxyUrl)",
                "--env", "HTTPS_PROXY=\(proxyUrl)",
                "--env", "ALL_PROXY=\(socksUrl)",
                "--env", "http_proxy=\(proxyUrl)",
                "--env", "https_proxy=\(proxyUrl)",
                "--env", "all_proxy=\(socksUrl)",
                "--env", "NO_PROXY=\(noProxyEnv)",
                "--env", "no_proxy=\(noProxyEnv)"
            ])

            // 2. 同时通过 --args 注入 Chromium / Electron 原生命令行代理与绕过列表（双保险）
            args.append(contentsOf: [
                "--args",
                "--proxy-server=\(proxyUrl)",
                "--proxy-bypass-list=\(chromiumBypass)"
            ])
        }

        task.arguments = args

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
