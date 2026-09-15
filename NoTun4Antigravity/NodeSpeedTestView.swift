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
        ZStack {
            VStack(alignment: .leading, spacing: 12) {
                // MARK: - Header
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: "speedometer")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.orange)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("节点真机可用性与测速筛选")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .tracking(-0.2)
                        Text("实测 Google 网页与 Antigravity AI 服务端真实延迟，按速度优选稳定专线")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        NodeSpeedTestWindowManager.shared.close()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }

                // MARK: - 1. 当前连接节点实时体检卡片
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("当前活跃代理 (端口: \(manager.activePort))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)

                        Spacer()

                        Button {
                            manager.probeCurrentNodeHealth()
                        } label: {
                            HStack(spacing: 4) {
                                if manager.nodeHealth.isChecking {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                                Text("立即体检")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(Color(NSColor.controlBackgroundColor).opacity(0.7))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(manager.nodeHealth.isChecking)
                    }

                    HStack(spacing: 12) {
                        // Google 网页状态
                        HStack(spacing: 6) {
                            Circle()
                                .fill(manager.nodeHealth.googleLatencyMs != nil ? Color.green : Color.red)
                                .frame(width: 7, height: 7)
                            Text("Google 网页:")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            if let ms = manager.nodeHealth.googleLatencyMs {
                                Text("\(ms)ms")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.green)
                            } else {
                                Text("断开/无法连接")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.red)
                            }
                        }

                        Divider().frame(height: 12)

                        // Antigravity AI 服务状态
                        HStack(spacing: 6) {
                            Circle()
                                .fill(manager.nodeHealth.isAntigravityReady ? Color.green : Color.red)
                                .frame(width: 7, height: 7)
                            Text("Antigravity AI:")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            if let ms = manager.nodeHealth.antigravityLatencyMs {
                                Text("\(ms)ms (畅通)")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.green)
                            } else if manager.nodeHealth.isAntigravityReady {
                                Text("🟢 畅通就绪")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.green)
                            } else {
                                Text("🔴 受限/被拦截")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(manager.nodeHealth.isOverallReady ? Color.green.opacity(0.3) : Color.red.opacity(0.3), lineWidth: 0.8)
                            )
                    )

                    if !manager.nodeHealth.isOverallReady && !manager.nodeHealth.isChecking {
                        Text("⚠️ 提示：当前代理节点无法直连 Google 服务，请在下方列表选择带有【Gemini】或【AI-Prime】标签的节点并在客户端中切换")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 2)
                    }
                }

                // MARK: - 2. 订阅解析与智能筛选输入区
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("粘贴 Shadowrocket / Trojan / Clash 订阅链接...", text: $subscriptionUrl)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))

                        Button {
                            loadSubscription()
                        } label: {
                            HStack(spacing: 4) {
                                if isLoadingSubscription {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.down.circle.fill")
                                }
                                Text(isLoadingSubscription ? "解析中..." : "解析节点")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6).fill(Color.blue)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoadingSubscription || subscriptionUrl.trimmingCharacters(in: .whitespaces).isEmpty)

                        if !parsedNodes.isEmpty {
                            Button {
                                testAllNodesSpeed()
                            } label: {
                                HStack(spacing: 4) {
                                    if isSpeedTestingAll {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "bolt.fill")
                                    }
                                    Text(isSpeedTestingAll ? "测速中..." : "一键测速")
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6).fill(Color.orange)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isSpeedTestingAll)
                        }
                    }

                    if let err = fetchErrorMessage {
                        Text(err)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                    }

                    // 过滤器与排序控制栏
                    HStack(spacing: 12) {
                        Toggle(isOn: $onlyShowGeminiRecommended) {
                            Text("⭐ 仅高亮 AI / Gemini 专线")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .toggleStyle(.checkbox)

                        Toggle(isOn: $sortBySpeed) {
                            Text("⚡ 按速度由快到慢排序")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .toggleStyle(.checkbox)

                        Spacer()

                        if !parsedNodes.isEmpty {
                            let readyCount = parsedNodes.filter { ($0.latencyMs ?? -1) > 0 }.count
                            Text("共 \(parsedNodes.count) 节点 | 已测速 \(readyCount)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // MARK: - 3. 节点列表展示 (包含实测速度与推荐标签)
                ScrollView {
                    VStack(spacing: 6) {
                        if filteredNodes.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "list.bullet.rectangle.portrait")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary.opacity(0.5))
                                Text(parsedNodes.isEmpty ? "输入上方订阅链接点击「解析节点」，即可实测节点连接速度并标出 Antigravity 专线" : "暂无符合筛选条件的节点，请取消勾选仅高亮专线查看全部")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                            }
                            .frame(maxWidth: .infinity, minHeight: 150)
                        } else {
                            ForEach(filteredNodes) { node in
                                HStack(spacing: 8) {
                                    // 节点名称
                                    Text(node.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)

                                    Spacer()

                                    // 标签徽章
                                    if node.isGeminiDedicated {
                                        Text("Gemini专用")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.purple.opacity(0.18)))
                                            .foregroundColor(.purple)
                                    }

                                    if node.isAIPrime {
                                        Text("AI-Prime")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.blue.opacity(0.18)))
                                            .foregroundColor(.blue)
                                    }

                                    if node.isResidential {
                                        Text("家宽")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.green.opacity(0.18)))
                                            .foregroundColor(.green)
                                    }

                                    // 实测实际速度展示 (ms)
                                    if node.isTesting {
                                        HStack(spacing: 3) {
                                            ProgressView().controlSize(.mini)
                                            Text("测速中")
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                    } else if let ms = node.latencyMs {
                                        let isFast = ms < 180
                                        let isMedium = ms < 350
                                        HStack(spacing: 2) {
                                            Image(systemName: "bolt.fill")
                                                .font(.system(size: 8))
                                            Text("\(ms)ms")
                                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule().fill(
                                                isFast ? Color.green.opacity(0.18) :
                                                (isMedium ? Color.blue.opacity(0.18) : Color.orange.opacity(0.18))
                                            )
                                        )
                                        .foregroundColor(isFast ? .green : (isMedium ? .blue : .orange))
                                    } else if node.hasTested {
                                        Text("超时")
                                            .font(.system(size: 9, weight: .medium))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.red.opacity(0.15)))
                                            .foregroundColor(.red)
                                    }

                                    // 复制按钮
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(node.name, forType: .string)
                                        copiedNodeName = node.name
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                            copiedNodeName = nil
                                        }
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: copiedNodeName == node.name ? "checkmark" : "doc.on.doc")
                                            Text(copiedNodeName == node.name ? "已复制" : "复制")
                                        }
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(copiedNodeName == node.name ? .green : .blue)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(
                                            Capsule().fill(Color(NSColor.controlBackgroundColor))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .help("复制节点全名，方便在客户端中快速搜索切换")
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(NSColor.controlBackgroundColor).opacity((node.isGeminiDedicated || node.isAIPrime) ? 0.75 : 0.4))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke((node.isGeminiDedicated || node.isAIPrime) ? Color.purple.opacity(0.4) : Color.clear, lineWidth: 0.8)
                                        )
                                )
                            }
                        }
                    }
                    .padding(.trailing, 2)
                }
                .frame(height: 190)
            }
            .padding(18)
            .frame(width: 520, height: 460)
        }
        .background(.ultraThinMaterial)
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
