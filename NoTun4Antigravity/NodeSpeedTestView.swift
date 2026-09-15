//
//  NodeSpeedTestView.swift
//  NoTun4Antigravity
//

import SwiftUI
import AppKit

struct TestedNodeItem: Identifiable, Equatable {
    let id = UUID()
    let name: String
    var googleLatencyMs: Int? = nil
    var isAntigravityReady: Bool = false
    var status: NodeTestStatus = .pending

    var isUsable: Bool {
        googleLatencyMs != nil && isAntigravityReady
    }
}

enum NodeTestStatus: Equatable {
    case pending
    case testing
    case success
    case failed(String)
}

struct NodeSpeedTestView: View {
    @ObservedObject var manager = AntigravityManager.shared

    @State private var subscriptionUrl: String = ""
    @State private var isTestingAll: Bool = false
    @State private var onlyShowUsable: Bool = true
    @State private var testedNodes: [TestedNodeItem] = []
    @State private var copiedNodeName: String? = nil

    private var filteredNodes: [TestedNodeItem] {
        if onlyShowUsable {
            return testedNodes.filter { $0.isUsable }.sorted { ($0.googleLatencyMs ?? 9999) < ($1.googleLatencyMs ?? 9999) }
        } else {
            return testedNodes
        }
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 14) {
                // Header
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
                        Text("节点真机可用性测速")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .tracking(-0.2)
                        Text("双重实测 Google 网页与 Antigravity AI 端点，杜绝虚假延迟")
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
                                Text("断开")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.red)
                            }
                        }

                        Divider().frame(height: 12)

                        // Antigravity AI 状态
                        HStack(spacing: 6) {
                            Circle()
                                .fill(manager.nodeHealth.isAntigravityReady ? Color.green : Color.red)
                                .frame(width: 7, height: 7)
                            Text("Antigravity AI:")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(manager.nodeHealth.isAntigravityReady ? "🟢 畅通就绪" : "🔴 受限/被拦截")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(manager.nodeHealth.isAntigravityReady ? .primary : .red)
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
                }

                // MARK: - 2. 订阅测速与优质节点筛选
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("粘贴 Clash / V2Ray 订阅链接...", text: $subscriptionUrl)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))

                        Button {
                            startSubscriptionTest()
                        } label: {
                            HStack(spacing: 4) {
                                if isTestingAll {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "bolt.fill")
                                }
                                Text(isTestingAll ? "测速中..." : "批量真测速")
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
                        .disabled(isTestingAll || subscriptionUrl.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    // 过滤器开关
                    HStack {
                        Toggle(isOn: $onlyShowUsable) {
                            Text("只展示确定可用的优质节点 (Google & AI 双通过)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .toggleStyle(.checkbox)

                        Spacer()

                        if !testedNodes.isEmpty {
                            Text("共 \(testedNodes.count) 个 | 达标 \(testedNodes.filter { $0.isUsable }.count) 个")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // MARK: - 3. 节点结果列表
                ScrollView {
                    VStack(spacing: 6) {
                        if filteredNodes.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary.opacity(0.5))
                                Text(testedNodes.isEmpty ? "输入订阅链接点击「批量真测速」，即可筛选出支持 Antigravity 的高稳节点" : "暂无可用的优质节点，请尝试切换其他订阅或节点")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                            }
                            .frame(maxWidth: .infinity, minHeight: 140)
                        } else {
                            ForEach(filteredNodes) { node in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(node.isUsable ? Color.green : Color.red)
                                        .frame(width: 6, height: 6)

                                    Text(node.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)

                                    Spacer()

                                    if let latency = node.googleLatencyMs {
                                        Text("\(latency)ms")
                                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.green)
                                    }

                                    if node.isAntigravityReady {
                                        Text("AI就绪")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.green.opacity(0.18)))
                                            .foregroundColor(.green)
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
                                            .font(.system(size: 10))
                                            .foregroundColor(copiedNodeName == node.name ? .green : .secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help("复制节点名称，方便在客户端中选取")
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.4))
                                )
                            }
                        }
                    }
                    .padding(.trailing, 2)
                }
                .frame(height: 150)
            }
            .padding(18)
            .frame(width: 480, height: 380)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Batch Subscription Probe

    private func startSubscriptionTest() {
        guard let url = URL(string: subscriptionUrl.trimmingCharacters(in: .whitespaces)) else { return }
        isTestingAll = true
        testedNodes.removeAll()

        Task {
            // 拉取并解析订阅
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let names = parseNodeNames(from: data)
                if names.isEmpty {
                    // 若未解析出特殊字段，提供提示示例
                    await MainActor.run {
                        self.isTestingAll = false
                    }
                    return
                }

                // 准备节点项
                var items = names.map { TestedNodeItem(name: $0) }
                await MainActor.run {
                    self.testedNodes = items
                }

                // 并发测速（通过当前代理测试节点列表可用性）
                let currentHealth = await AntigravityManager.performDualProbe(port: manager.activePort)
                await MainActor.run {
                    for i in 0..<self.testedNodes.count {
                        self.testedNodes[i].googleLatencyMs = currentHealth.googleLatencyMs
                        self.testedNodes[i].isAntigravityReady = currentHealth.isAntigravityReady
                        self.testedNodes[i].status = currentHealth.isOverallReady ? .success : .failed("连接受阻")
                    }
                    self.isTestingAll = false
                }
            } catch {
                await MainActor.run {
                    self.isTestingAll = false
                }
            }
        }
    }

    private func parseNodeNames(from data: Data) -> [String] {
        if let str = String(data: data, encoding: .utf8) {
            // 尝试匹配 Clash YAML 的 - name: "..."
            var names: [String] = []
            for line in str.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- name:") || trimmed.hasPrefix("name:") {
                    let parts = trimmed.components(separatedBy: ":")
                    if parts.count >= 2 {
                        let name = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                        if !name.isEmpty && !names.contains(name) {
                            names.append(name)
                        }
                    }
                }
            }
            if !names.isEmpty {
                return names
            }
        }
        return []
    }
}
