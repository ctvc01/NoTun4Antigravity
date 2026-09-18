//
//  NodeSpeedTestView.swift
//  NoTun4Antigravity
//

import SwiftUI
import AppKit
import Darwin

struct TestedNodeItem: Identifiable, Equatable {
    let id = UUID()
    let name: String
    var host: String = ""
    var port: Int = 0
    var latencyMs: Int? = nil
    var isTesting: Bool = false
    var hasTested: Bool = false
    var isGeminiDedicated: Bool = false
    var isResidential: Bool = false
    var isNative: Bool = false
    var isAIPrime: Bool = false
}

struct NodeSpeedTestView: View {
    var onBack: () -> Void

    @ObservedObject var manager = AntigravityManager.shared

    @AppStorage("savedSubscriptionUrl") private var savedSubscriptionUrl: String = ""
    @State private var subscriptionUrl: String = ""
    @State private var isLoadingSubscription: Bool = false
    @State private var onlyShowGeminiRecommended: Bool = false
    @State private var sortBySpeed: Bool = true
    @State private var isSpeedTestingAll: Bool = false
    @State private var parsedNodes: [TestedNodeItem] = []
    @State private var copiedNodeName: String? = nil
    @State private var fetchErrorMessage: String? = nil

    private var filteredNodes: [TestedNodeItem] {
        var list = parsedNodes
        if onlyShowGeminiRecommended {
            list = list.filter { $0.isGeminiDedicated || $0.isAIPrime || $0.isResidential }
        }
        if sortBySpeed {
            list.sort { a, b in
                switch (a.latencyMs, b.latencyMs) {
                case let (ms1?, ms2?):
                    return ms1 < ms2
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return false
                }
            }
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: - Navigation Header (Control Center Style)
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 24, height: 24)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                        )
                }
                .buttonStyle(SpringButtonStyle(scale: 0.92))
                .keyboardShortcut(.cancelAction)

                VStack(alignment: .leading, spacing: 1) {
                    Text("节点真机测速与筛选")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text("实测 Google 网页与 AI 服务端真实延迟")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    manager.probeCurrentNodeHealth()
                } label: {
                    HStack(spacing: 3) {
                        if manager.nodeHealth.isChecking {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        Text("体检")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(manager.nodeHealth.isChecking)
            }
            .padding(.horizontal, 2)

            // MARK: - 1. 当前连接节点实时体检卡片 (紧凑型)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    // Google 网页状态
                    Circle()
                        .fill(manager.nodeHealth.googleLatencyMs != nil ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text("Google:")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if let ms = manager.nodeHealth.googleLatencyMs {
                        Text("\(ms)ms")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.green)
                    } else {
                        Text("断开")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.red)
                    }

                    Spacer()

                    // Antigravity AI 服务状态
                    Circle()
                        .fill(manager.nodeHealth.isAntigravityReady ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text("AI服务:")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if let ms = manager.nodeHealth.antigravityLatencyMs {
                        Text("\(ms)ms")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.green)
                    }

                    if manager.nodeHealth.isMatrixAllReady {
                        Text("全通")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.green.opacity(0.18)))
                            .foregroundColor(.green)
                    } else if !manager.nodeHealth.isOAuthReady && manager.nodeHealth.isAntigravityReady {
                        Text("OAuth受限")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.18)))
                            .foregroundColor(.orange)
                    } else if !manager.nodeHealth.isAntigravityReady {
                        Text("受限")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.red.opacity(0.18)))
                            .foregroundColor(.red)
                    }
                }

                if let err = manager.nodeHealth.errorMessage, !manager.nodeHealth.isChecking {
                    Text("⚠️ \(err)")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(manager.nodeHealth.isOverallReady ? Color.green.opacity(0.25) : Color.red.opacity(0.25), lineWidth: 0.8)
                    )
            )

            // MARK: - 2. 订阅解析与测速操作栏
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    TextField("粘贴订阅链接...", text: $subscriptionUrl)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10))

                    Button {
                        loadSubscription()
                    } label: {
                        HStack(spacing: 2) {
                            if isLoadingSubscription {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                            }
                            Text(isLoadingSubscription ? "..." : "解析")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.blue)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingSubscription || subscriptionUrl.trimmingCharacters(in: .whitespaces).isEmpty)

                    if !parsedNodes.isEmpty {
                        Button {
                            testAllNodesSpeed()
                        } label: {
                            HStack(spacing: 2) {
                                if isSpeedTestingAll {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "bolt.fill")
                                }
                                Text(isSpeedTestingAll ? "..." : "测速")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.orange)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isSpeedTestingAll)
                    }
                }

                if let err = fetchErrorMessage {
                    Text(err)
                        .font(.system(size: 9))
                        .foregroundColor(.red)
                        .lineLimit(1)
                }

                // 筛选栏
                HStack(spacing: 8) {
                    Toggle(isOn: $onlyShowGeminiRecommended) {
                        Text("仅专线")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .toggleStyle(.checkbox)

                    Spacer()

                    if !parsedNodes.isEmpty {
                        let readyCount = parsedNodes.filter { ($0.latencyMs ?? -1) > 0 }.count
                        Text("\(parsedNodes.count) 节点 | 已测 \(readyCount)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }

            // MARK: - 3. 节点垂直列表 (类似 macOS Wi-Fi 列表)
            ScrollView {
                VStack(spacing: 4) {
                    if filteredNodes.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "list.bullet.rectangle.portrait")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary.opacity(0.4))
                            Text(parsedNodes.isEmpty ? "输入上方订阅链接点击「解析」，即可在此实测节点速度" : "暂无符合筛选条件的节点")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 10)
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        ForEach(filteredNodes) { node in
                            HStack(spacing: 6) {
                                Text(node.name)
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                Spacer()

                                if node.isGeminiDedicated || node.isAIPrime {
                                    Text("专线")
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.purple.opacity(0.18)))
                                        .foregroundColor(.purple)
                                }

                                if node.isTesting {
                                    ProgressView().controlSize(.mini)
                                } else if let ms = node.latencyMs {
                                    let isFast = ms < 180
                                    let isMedium = ms < 350
                                    Text("\(ms)ms")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(
                                            Capsule().fill(
                                                isFast ? Color.green.opacity(0.18) :
                                                (isMedium ? Color.blue.opacity(0.18) : Color.orange.opacity(0.18))
                                            )
                                        )
                                        .foregroundColor(isFast ? .green : (isMedium ? .blue : .orange))
                                } else if node.hasTested {
                                    Text("超时")
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundColor(.red)
                                }

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(node.name, forType: .string)
                                    copiedNodeName = node.name
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                        copiedNodeName = nil
                                    }
                                } label: {
                                    Image(systemName: copiedNodeName == node.name ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 9))
                                        .foregroundColor(copiedNodeName == node.name ? .green : .secondary)
                                }
                                .buttonStyle(.plain)
                                .help("复制节点全名")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.45))
                            )
                        }
                    }
                }
                .padding(.trailing, 2)
            }
            .frame(height: 170)
        }
        .padding(14)
        .frame(width: 310)
        .onAppear {
            if !savedSubscriptionUrl.isEmpty {
                subscriptionUrl = savedSubscriptionUrl
                loadSubscription()
            }
        }
    }

    // MARK: - Direct Fetch & Robust Parsing

    private func loadSubscription() {
        let trimmed = subscriptionUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            fetchErrorMessage = "请输入有效的订阅 URL"
            return
        }

        savedSubscriptionUrl = trimmed
        isLoadingSubscription = true
        fetchErrorMessage = nil

        Task {
            // 采用纯净无代理 Direct Session 拉取（避免因当前代理故障导致拉取失败）
            let config = URLSessionConfiguration.ephemeral
            config.connectionProxyDictionary = [:] // 显式禁用代理，直连拉取
            config.timeoutIntervalForRequest = 8.0
            let directSession = URLSession(configuration: config)

            do {
                let (data, _) = try await directSession.data(from: url)
                let nodes = parseNodesFromRawData(data)
                await MainActor.run {
                    self.isLoadingSubscription = false
                    if nodes.isEmpty {
                        self.fetchErrorMessage = "已成功拉取，但未解析出有效节点，请确认链接类型"
                    } else {
                        self.parsedNodes = nodes
                        // 自动触发一次测速
                        self.testAllNodesSpeed()
                    }
                }
            } catch {
                // 若直连失败，尝试通过系统默认代理拉取
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let nodes = parseNodesFromRawData(data)
                    await MainActor.run {
                        self.isLoadingSubscription = false
                        self.parsedNodes = nodes
                        self.testAllNodesSpeed()
                    }
                } catch let retryErr {
                    await MainActor.run {
                        self.isLoadingSubscription = false
                        self.fetchErrorMessage = "拉取失败: \(retryErr.localizedDescription)"
                    }
                }
            }
        }
    }

    // MARK: - Concurrent Speed Testing Engine

    private func testAllNodesSpeed() {
        guard !parsedNodes.isEmpty, !isSpeedTestingAll else { return }
        isSpeedTestingAll = true

        Task {
            for i in parsedNodes.indices {
                parsedNodes[i].isTesting = true
            }

            await withTaskGroup(of: (UUID, Int?).self) { group in
                var iterator = parsedNodes.makeIterator()

                func addNextTask() {
                    if let nextNode = iterator.next() {
                        let id = nextNode.id
                        let host = nextNode.host
                        let port = nextNode.port
                        group.addTask {
                            let speed = await Self.measureSocketLatency(host: host, port: port)
                            return (id, speed)
                        }
                    }
                }

                let maxConcurrent = 8
                for _ in 0..<maxConcurrent {
                    addNextTask()
                }

                while let (id, speed) = await group.next() {
                    await MainActor.run {
                        if let index = parsedNodes.firstIndex(where: { $0.id == id }) {
                            parsedNodes[index].latencyMs = speed
                            parsedNodes[index].isTesting = false
                            parsedNodes[index].hasTested = true
                        }
                    }
                    addNextTask()
                }
            }

            await MainActor.run {
                self.isSpeedTestingAll = false
            }
        }
    }

    nonisolated static func measureSocketLatency(host: String, port: Int, timeoutMs: Int32 = 1800) async -> Int? {
        guard !host.isEmpty, port > 0, port <= 65535 else { return nil }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var hints = addrinfo(
                    ai_flags: 0,
                    ai_family: AF_INET,
                    ai_socktype: SOCK_STREAM,
                    ai_protocol: IPPROTO_TCP,
                    ai_addrlen: 0,
                    ai_canonname: nil,
                    ai_addr: nil,
                    ai_next: nil
                )
                var res: UnsafeMutablePointer<addrinfo>?
                let start = CFAbsoluteTimeGetCurrent()
                guard getaddrinfo(host, String(port), &hints, &res) == 0, let info = res else {
                    continuation.resume(returning: nil)
                    return
                }
                defer { freeaddrinfo(res) }

                let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
                guard fd >= 0 else {
                    continuation.resume(returning: nil)
                    return
                }
                defer { close(fd) }

                let flags = fcntl(fd, F_GETFL, 0)
                _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

                let ret = connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen)
                if ret == 0 {
                    let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                    continuation.resume(returning: max(1, elapsed))
                    return
                }

                if errno == EINPROGRESS {
                    var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                    let pollRes = poll(&pfd, 1, timeoutMs)
                    if pollRes > 0 && (pfd.revents & Int16(POLLOUT)) != 0 && (pfd.revents & Int16(POLLERR | POLLHUP | POLLNVAL)) == 0 {
                        var err: Int32 = 0
                        var len = socklen_t(MemoryLayout<Int32>.size)
                        getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
                        if err == 0 {
                            let elapsed = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
                            continuation.resume(returning: max(1, elapsed))
                            return
                        }
                    }
                }
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - Parser for Multi-Protocol Subscription Data

    private func parseNodesFromRawData(_ data: Data) -> [TestedNodeItem] {
        var rawText = String(data: data, encoding: .utf8) ?? ""

        // 尝试 Base64 解码
        let cleaned = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let decodedData = Data(base64Encoded: cleaned, options: [.ignoreUnknownCharacters]),
           let decodedString = String(data: decodedData, encoding: .utf8),
           decodedString.contains("://") || decodedString.contains("- name:") {
            rawText = decodedString
        }

        var results: [TestedNodeItem] = []

        // 1. 逐行解析 URL 格式 (trojan://, vless://, ss://, vmess://)
        for line in rawText.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let item = parseSingleUrlLine(trimmed) {
                if !results.contains(where: { $0.name == item.name }) {
                    results.append(item)
                }
            }
        }

        if !results.isEmpty {
            return results
        }

        // 2. 尝试按 Clash YAML 格式解析
        var currentName: String? = nil
        var currentServer: String? = nil
        var currentPort: Int? = nil

        for line in rawText.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- name:") || trimmed.hasPrefix("name:") {
                if let name = currentName, !results.contains(where: { $0.name == name }) {
                    results.append(createNodeItem(name: name, host: currentServer ?? "", port: currentPort ?? 0))
                }
                currentName = trimmed.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                currentServer = nil
                currentPort = nil
            } else if trimmed.hasPrefix("server:") {
                currentServer = trimmed.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            } else if trimmed.hasPrefix("port:") {
                let portStr = trimmed.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                currentPort = Int(portStr)
            }
        }

        if let name = currentName, !results.contains(where: { $0.name == name }) {
            results.append(createNodeItem(name: name, host: currentServer ?? "", port: currentPort ?? 0))
        }

        return results
    }

    private func parseSingleUrlLine(_ line: String) -> TestedNodeItem? {
        // 分离 # 后的节点名
        guard let hashIdx = line.firstIndex(of: "#") else {
            // 处理没有 # 的情况，例如 vmess://
            if line.hasPrefix("vmess://") {
                return parseVmessNode(line)
            }
            return nil
        }

        let encodedName = String(line[line.index(after: hashIdx)...])
        let nodeName = encodedName.removingPercentEncoding ?? encodedName
        guard !nodeName.isEmpty else { return nil }

        let preHash = String(line[..<hashIdx])
        var host = ""
        var port = 0

        // 解析 host 和 port: scheme://[auth@]host:port[?...]
        if let atIdx = preHash.firstIndex(of: "@") {
            let hostAndPortPart = String(preHash[preHash.index(after: atIdx)...])
            let cleanHostPort = hostAndPortPart.components(separatedBy: "?").first ?? hostAndPortPart
            let parts = cleanHostPort.components(separatedBy: ":")
            if parts.count >= 2 {
                host = parts[0]
                port = Int(parts[1]) ?? 0
            }
        } else if preHash.hasPrefix("ss://") {
            // ss://base64#Name
            let base64Part = String(preHash.dropFirst(5))
            if let decodedData = Data(base64Encoded: base64Part, options: [.ignoreUnknownCharacters]),
               let decoded = String(data: decodedData, encoding: .utf8) {
                // method:pass@host:port
                if let at = decoded.firstIndex(of: "@") {
                    let hp = String(decoded[decoded.index(after: at)...])
                    let parts = hp.components(separatedBy: ":")
                    if parts.count >= 2 {
                        host = parts[0]
                        port = Int(parts[1]) ?? 0
                    }
                }
            }
        }

        return createNodeItem(name: nodeName, host: host, port: port)
    }

    private func parseVmessNode(_ line: String) -> TestedNodeItem? {
        let base64Part = String(line.dropFirst(8))
        guard let decodedData = Data(base64Encoded: base64Part, options: [.ignoreUnknownCharacters]),
              let json = try? JSONSerialization.jsonObject(with: decodedData) as? [String: Any] else {
            return nil
        }

        let name = (json["ps"] as? String) ?? "VMess Node"
        let host = (json["add"] as? String) ?? ""
        var port = 0
        if let pInt = json["port"] as? Int {
            port = pInt
        } else if let pStr = json["port"] as? String, let pInt = Int(pStr) {
            port = pInt
        }

        return createNodeItem(name: name, host: host, port: port)
    }

    private func createNodeItem(name: String, host: String = "", port: Int = 0) -> TestedNodeItem {
        let lower = name.lowercased()
        let isGemini = lower.contains("gemini")
        let isAIPrime = lower.contains("ai-prime") || lower.contains("ai_prime") || lower.contains("ai")
        let isHome = name.contains("家寬") || name.contains("家宽") || lower.contains("home") || lower.contains("residential")
        let isNat = name.contains("原生") || lower.contains("native")

        return TestedNodeItem(
            name: name,
            host: host,
            port: port,
            isGeminiDedicated: isGemini,
            isResidential: isHome,
            isNative: isNat,
            isAIPrime: isAIPrime
        )
    }
}
