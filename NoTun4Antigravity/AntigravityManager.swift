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

        // 主线程定时轮询，无并发闭包捕获开销
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

    private func findAntigravityApps() -> [NSRunningApplication] {
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

            if let name = app.localizedName?.lowercased(), name == "antigravity" {
                return true
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
        statusMessage = "Restarting Antigravity..."
        terminateAllAntigravity()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.executeOpen(useProxy: useProxy, proxyPort: proxyPort, rawWhitelistText: rawWhitelistText)
        }
    }

    func terminate() {
        terminateAllAntigravity()
        statusMessage = "Antigravity terminated."
    }

    private func terminateAllAntigravity() {
        let runningApps = findAntigravityApps()
        for app in runningApps {
            app.terminate()
        }
        checkProcessStatus()
    }

    private func executeOpen(useProxy: Bool, proxyPort: Int, rawWhitelistText: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "Antigravity"]

        var environment = ProcessInfo.processInfo.environment

        if useProxy {
            let portStr = String(proxyPort)
            let proxyUrl = "http://127.0.0.1:\(portStr)"
            let socksUrl = "socks5h://127.0.0.1:\(portStr)"

            environment["HTTP_PROXY"] = proxyUrl
            environment["HTTPS_PROXY"] = proxyUrl
            environment["ALL_PROXY"] = socksUrl
            environment["http_proxy"] = proxyUrl
            environment["https_proxy"] = proxyUrl
            environment["all_proxy"] = socksUrl

            let rules = rawWhitelistText
                .components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ",")))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let noProxyFormatted = rules.isEmpty ? "localhost,127.0.0.1" : rules.joined(separator: ",")

            environment["NO_PROXY"] = noProxyFormatted
            environment["no_proxy"] = noProxyFormatted
        } else {
            environment.removeValue(forKey: "HTTP_PROXY")
            environment.removeValue(forKey: "HTTPS_PROXY")
            environment.removeValue(forKey: "ALL_PROXY")
            environment.removeValue(forKey: "http_proxy")
            environment.removeValue(forKey: "https_proxy")
            environment.removeValue(forKey: "all_proxy")
        }

        task.environment = environment

        do {
            try task.run()
            statusMessage = useProxy ? "Launched with proxy (Port \(proxyPort))" : "Launched cleanly (No proxy)"
        } catch {
            statusMessage = "Launch failed: \(error.localizedDescription)"
            print("Failed to launch Antigravity: \(error)")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkProcessStatus()
        }
    }
}
