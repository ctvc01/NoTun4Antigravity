//
//  NodeSpeedTestView.swift
//  NoTun4Antigravity
//

import SwiftUI
import AppKit
import Darwin

struct TestedNodeItem: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
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
    var isUnsupportedType: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, host, port, latencyMs, isTesting, hasTested
        case isGeminiDedicated, isResidential, isNative, isAIPrime, isUnsupportedType
    }

    init(
        id: UUID = UUID(),
        name: String,
        host: String = "",
        port: Int = 0,
        latencyMs: Int? = nil,
        isTesting: Bool = false,
        hasTested: Bool = false,
        isGeminiDedicated: Bool = false,
        isResidential: Bool = false,
        isNative: Bool = false,
        isAIPrime: Bool = false,
        isUnsupportedType: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.latencyMs = latencyMs
        self.isTesting = isTesting
        self.hasTested = hasTested
        self.isGeminiDedicated = isGeminiDedicated
        self.isResidential = isResidential
        self.isNative = isNative
        self.isAIPrime = isAIPrime
        self.isUnsupportedType = isUnsupportedType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.host = (try? container.decode(String.self, forKey: .host)) ?? ""
        self.port = (try? container.decode(Int.self, forKey: .port)) ?? 0
        self.latencyMs = try? container.decode(Int.self, forKey: .latencyMs)
        self.isTesting = false
        self.hasTested = (try? container.decode(Bool.self, forKey: .hasTested)) ?? (latencyMs != nil)

        // 提取专线、AI-Prime、原生等优质能力标识作为列表辅助参考
        let meta = Self.resolveMetadata(name: self.name)
        self.isGeminiDedicated = meta.isGemini
        self.isResidential = meta.isHome
        self.isNative = meta.isNat
        self.isAIPrime = meta.isAIPrime
        self.isUnsupportedType = false
    }

    static func resolveMetadata(name: String) -> (isGemini: Bool, isHome: Bool, isNat: Bool, isAIPrime: Bool) {
        let lower = name.lowercased()

        // 识别支持 Antigravity / Gemini 原生直连的优质能力特征（仅作为视觉标识，不作为一刀切过滤依据）
        let isGemini = lower.contains("gemini")
        let isDedicatedLine = name.contains("专线") || name.contains("專線") || lower.contains("iplc") || lower.contains("iepl")
        let isExplicitAI = isGemini || lower.contains("ai-prime") || lower.contains("ai_prime") || lower.contains("claude") || lower.contains("gpt")
        let isAIPrime = isExplicitAI || isDedicatedLine
        let isNat = name.contains("原生") || lower.contains("native")
        let isHome = name.contains("家寬") || name.contains("家宽") || lower.contains("home") || lower.contains("residential")

        return (isGemini, isHome, isNat, isAIPrime)
    }
}

struct NodeSpeedTestView: View {
    var onBack: () -> Void
    var onNavigateAudit: (() -> Void)? = nil

    @ObservedObject var manager = AntigravityManager.shared
    @ObservedObject var auditLogger = SpeedTestAuditLogger.shared

    @AppStorage("savedSubscriptionUrl") private var savedSubscriptionUrl: String = ""
    @AppStorage("lastSubscriptionUpdateTime") private var lastSubscriptionUpdateTime: Double = 0

    @State private var subscriptionUrl: String = ""
    @State private var isEditingSubscriptionUrl: Bool = false
    @State private var editUrlDraft: String = ""
    @State private var isLoadingSubscription: Bool = false
    @State private var sortBySpeed: Bool = true
    @State private var isSpeedTestingAll: Bool = false
    @State private var parsedNodes: [TestedNodeItem] = []
    @State private var copiedNodeName: String? = nil
    @State private var fetchErrorMessage: String? = nil

    private static let cacheKey = "cachedSubscriptionNodes"

    private var lastUpdateText: String {
        guard lastSubscriptionUpdateTime > 0 else { return "未同步" }
        let date = Date(timeIntervalSince1970: lastSubscriptionUpdateTime)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "更新于 " + formatter.string(from: date)
    }

    private func saveCachedNodes(_ nodes: [TestedNodeItem]) {
        let clean = nodes.map { item -> TestedNodeItem in
            var copy = item
            copy.isTesting = false
            return copy
        }
        if let data = try? JSONEncoder().encode(clean) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
    }

    private func loadCachedNodes() -> [TestedNodeItem]? {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let list = try? JSONDecoder().decode([TestedNodeItem].self, from: data) else {
            return nil
        }
        return list
    }

    private var filteredNodes: [TestedNodeItem] {
        var list = parsedNodes.filter { node in
            let isActive = (manager.activeNodeName != nil && manager.activeNodeName == node.name)
            // 1. 当前正在使用的活动节点始终保留在列表中置顶展示（即便断连或AI受限也展示，以便用户明确感知当前状态并排查切换）
            if isActive {
                return true
            }

            // 2. 核心端到端防护：凡是在历史或最新实测中被证实无法连接 Antigravity（如 TLS 阻断、AI 区域受限、OAuth 拦截）的节点，坚决过滤排除！
            if let record = auditLogger.nodeHealthRecords[node.name], !record.isAntigravityReady {
                return false
            }

            // 3. 架构特征过滤：排除「特殊｜」系列实验节点（加拿大A、德国A、美国A等在日志中已证实 100% 存在 gRPC/TLS/310 隧道不兼容）
            let isSpecialFamily = node.name.contains("特殊｜") || node.name.contains("特殊|") || (node.name.contains("特殊") && !node.isGeminiDedicated && !node.isAIPrime)
            if isSpecialFamily {
                return false
            }

            // 4. 以最新真实测速检测结果为准（动态过滤与解除过滤）：
            if node.hasTested {
                // 真实测速断连、超时的节点，自动过滤隐藏
                guard let ms = node.latencyMs, ms > 0 else {
                    return false
                }
                // 真实测速超高延迟（> 2000ms 高丢包假通），自动过滤隐藏
                if ms > 2000 {
                    return false
                }
                // 最新测速中恢复可连通且延迟合格的节点，自动解除过滤重新展示！
                return true
            }
            // 尚未测速的节点保留在列表中等待全量审查测速
            return true
        }

        if sortBySpeed {
            list.sort { a, b in
                // 当前正在使用的活动节点置顶展示
                if let active = manager.activeNodeName {
                    if a.name == active { return true }
                    if b.name == active { return false }
                }
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

                if let onNavigateAudit = onNavigateAudit {
                    Button(action: onNavigateAudit) {
                        HStack(spacing: 3) {
                            Image(systemName: "chart.xyaxis.line")
                            Text("质检日志")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

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
                        let err = manager.nodeHealth.errorMessage ?? ""
                        let tagText = err.contains("310") ? "310熔断" : (err.contains("TLS") ? "TLS阻断" : "受限")
                        Text(tagText)
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

                // 测速校准与真实通信质量指标
                if auditLogger.report.alignedComparisonCount > 0 {
                    HStack(spacing: 5) {
                        Text("质检校准:")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)

                        Text("吻合率 \(String(format: "%.0f", auditLogger.report.consistencyRatePercent))%")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(auditLogger.report.consistencyRatePercent >= 80 ? .green : .orange)

                        Text("• 评分 \(auditLogger.report.calibratedReliabilityScore)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(auditLogger.report.calibratedReliabilityScore >= 70 ? .green : .red)

                        if auditLogger.report.falsePositiveCount > 0 {
                            Text("⚠️ 拦截虚高 \(auditLogger.report.falsePositiveCount)次")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.red)
                        }

                        Spacer()

                        if let onNavigateAudit = onNavigateAudit {
                            Button(action: onNavigateAudit) {
                                Text("详情 ›")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)
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

            // MARK: - 2. 订阅与测速操作栏 (紧凑折叠 / 展开编辑)
            VStack(alignment: .leading, spacing: 6) {
                if isEditingSubscriptionUrl {
                    // 编辑状态：输入框 + 保存/取消
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("配置订阅链接")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.primary)
                            Spacer()
                            Button {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    isEditingSubscriptionUrl = false
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        HStack(spacing: 6) {
                            TextField("粘贴订阅链接 (HTTP/HTTPS)...", text: $editUrlDraft)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 10))

                            Button("保存并刷新") {
                                let trimmed = editUrlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                                subscriptionUrl = trimmed
                                savedSubscriptionUrl = trimmed
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    isEditingSubscriptionUrl = false
                                }
                                loadSubscription()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.blue))
                            .disabled(editUrlDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    )
                } else {
                    // 常态：折叠显示订阅信息 + 刷新按钮 + 测速按钮
                    HStack(spacing: 6) {
                        // 订阅状态与编辑按钮
                        HStack(spacing: 4) {
                            Image(systemName: "link.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.blue)

                            if savedSubscriptionUrl.isEmpty {
                                Text("未配置订阅")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            } else {
                                Text(lastUpdateText)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            Button {
                                editUrlDraft = savedSubscriptionUrl
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                    isEditingSubscriptionUrl = true
                                }
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.blue)
                                    .padding(3)
                                    .background(Color.blue.opacity(0.12))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help(savedSubscriptionUrl.isEmpty ? "添加订阅链接" : "修改订阅链接")
                        }

                        Spacer()

                        // 手动刷新订阅按钮
                        Button {
                            loadSubscription()
                        } label: {
                            HStack(spacing: 2) {
                                if isLoadingSubscription {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("刷新订阅")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.primary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.75))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoadingSubscription || savedSubscriptionUrl.isEmpty)

                        // 测速按钮
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
                }

                if let err = fetchErrorMessage {
                    Text(err)
                        .font(.system(size: 9))
                        .foregroundColor(.red)
                        .lineLimit(1)
                }

                // 智能状态与可用节点统计栏 (默认工业级过滤)
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.green)
                        Text("动态实测质检: 过滤断连、超时、>2s假通与特殊/不可用节点")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if !parsedNodes.isEmpty {
                        let readyCount = filteredNodes.filter { ($0.latencyMs ?? -1) > 0 }.count
                        let filteredOutCount = max(0, parsedNodes.count - filteredNodes.count)
                        if filteredOutCount > 0 {
                            Text("\(filteredNodes.count) 连通 (已滤 \(filteredOutCount) 不可用)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(filteredNodes.count) 节点 | 已测 \(readyCount)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
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
                            Text(parsedNodes.isEmpty ? "输入上方订阅链接点击「解析」，即可在此实测节点速度" : "暂无符合筛选条件的可用节点")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 10)
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                    } else {
                        ForEach(filteredNodes) { node in
                            let isActiveNode = (manager.activeNodeName != nil && manager.activeNodeName == node.name)
                            HStack(spacing: 6) {
                                if isActiveNode {
                                    Text("使用中")
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.blue))
                                        .foregroundColor(.white)
                                }

                                Text(node.name)
                                    .font(.system(size: 10, weight: isActiveNode ? .bold : .medium))
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

                                nodeLatencyBadge(node, isActive: isActiveNode)

                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(node.name, forType: .string)
                                    copiedNodeName = node.name
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                        copiedNodeName = nil
                                    }
                                } label: {
                                    Image(systemName: copiedNodeName == node.name ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 10))
                                        .foregroundColor(copiedNodeName == node.name ? .green : .secondary)
                                }
                                .buttonStyle(.plain)
                                .help("复制节点全名")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isActiveNode ? Color.blue.opacity(0.12) : Color(NSColor.controlBackgroundColor).opacity(0.45))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(isActiveNode ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(.trailing, 2)
            }
            .frame(height: 270)
        }
        .padding(14)
        .onAppear {
            subscriptionUrl = savedSubscriptionUrl
            // 优先读取本地持久化缓存，避免每次打开重新拉取
            if let cached = loadCachedNodes(), !cached.isEmpty {
                self.parsedNodes = cached
            } else if !savedSubscriptionUrl.isEmpty {
                // 仅在首次本地无缓存且配置了订阅链接时自动拉取
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
                        self.lastSubscriptionUpdateTime = Date().timeIntervalSince1970
                        self.saveCachedNodes(nodes)
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
                        self.lastSubscriptionUpdateTime = Date().timeIntervalSince1970
                        self.saveCachedNodes(nodes)
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

        // 每次手动测速时，同步刷新当前活动节点的端到端 AI 真机体检
        manager.probeCurrentNodeHealth()

        Task {
            // 对底层所有订阅节点全部重新审查并置为正在测速状态
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
                self.saveCachedNodes(self.parsedNodes)
            }
        }
    }

    nonisolated static func measureSocketLatency(host: String, port: Int, timeoutMs: Int32 = 1500) async -> Int? {
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
        let meta = TestedNodeItem.resolveMetadata(name: name)
        return TestedNodeItem(
            name: name,
            host: host,
            port: port,
            isGeminiDedicated: meta.isGemini,
            isResidential: meta.isHome,
            isNative: meta.isNat,
            isAIPrime: meta.isAIPrime,
            isUnsupportedType: false
        )
    }

    @ViewBuilder
    private func nodeLatencyBadge(_ node: TestedNodeItem, isActive: Bool) -> some View {
        if isActive {
            activeNodeLatencyBadge()
        } else if node.isTesting {
            ProgressView().controlSize(.mini)
        } else if let rec = auditLogger.nodeHealthRecords[node.name], rec.isAntigravityReady, let aiMs = rec.realAILatencyMs {
            HStack(spacing: 2) {
                Text("实测AI")
                    .font(.system(size: 7, weight: .bold))
                Text("\(aiMs)ms")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(Color.green.opacity(0.18)))
            .foregroundColor(.green)
            .help("该节点经端到端真机实测，可正常连接 Google Gemini API")
        } else if let ms = node.latencyMs {
            let isFast = ms < 180
            Text("接入 \(ms)ms")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(isFast ? Color.blue.opacity(0.15) : Color.orange.opacity(0.15)))
                .foregroundColor(isFast ? .primary : .orange)
                .help("到节点入口服务器的 TCP 握手延迟 (非 Google 端到端)")
        } else if node.hasTested {
            Text("断连")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.red)
        }
    }

    private var activeNodeFailureTag: String {
        let err = manager.nodeHealth.errorMessage ?? ""
        if err.contains("310") || err.contains("隧道超时") {
            return "310熔断"
        } else if err.contains("TLS") {
            return "TLS阻断"
        } else if err.contains("区域受限") {
            return "AI受限"
        } else {
            return "AI不可用"
        }
    }

    @ViewBuilder
    private func activeNodeLatencyBadge() -> some View {
        if manager.nodeHealth.isChecking {
            ProgressView().controlSize(.mini)
        } else if !manager.nodeHealth.isAntigravityReady {
            Text(activeNodeFailureTag)
                .font(.system(size: 8, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(Color.red.opacity(0.2)))
                .foregroundColor(.red)
                .help(manager.nodeHealth.errorMessage ?? "当前节点无法正常连接 Google Gemini / Antigravity 服务")
        } else if let realMs = manager.nodeHealth.antigravityLatencyMs {
            let isFast = realMs < 500
            HStack(spacing: 2) {
                Text("AI")
                    .font(.system(size: 7, weight: .bold))
                Text("\(realMs)ms")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(isFast ? Color.green.opacity(0.2) : Color.orange.opacity(0.2)))
            .foregroundColor(isFast ? .green : .orange)
            .help("当前活动节点访问 Google Gemini API 端到端真实响应速度")
        } else {
            Text("不可用")
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.red)
        }
    }
}
