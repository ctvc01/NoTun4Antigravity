//
//  RemoteSshAssistantView.swift
//  NoTun4Antigravity
//

import SwiftUI
import AppKit

struct RemoteSshAssistantView: View {
    @ObservedObject var manager = AntigravityManager.shared

    @State private var isSshConfigured: Bool = false
    @State private var sshStatusMessage: String? = nil

    @State private var knownHosts: [String] = []
    @State private var selectedHost: String = ""
    @State private var customTarget: String = ""
    @State private var remotePort: String = ""

    @State private var isRepairingRemote: Bool = false
    @State private var remoteRepairResult: (success: Bool, message: String)? = nil

    @State private var isSyncingLocalIde: Bool = false
    @State private var localIdeSyncMessage: String? = nil
    @State private var showManualCommand: Bool = false
    @State private var copiedCommand: Bool = false

    private var effectiveTarget: String {
        let trimmed = customTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return selectedHost
    }

    private var effectivePort: Int {
        if let p = Int(remotePort.trimmingCharacters(in: .whitespacesAndNewlines)), p > 0 {
            return p
        }
        return manager.activePort
    }

    private var manualBashCommand: String {
        let p = effectivePort
        return "bash -c 'PORT=\(p); BASHRC=\"$HOME/.bashrc\"; [ -f \"$BASHRC\" ] && { sed -i \"\" -e \"/http_proxy/d\" -e \"/https_proxy/d\" -e \"/all_proxy/d\" \"$BASHRC\" 2>/dev/null || true; printf \"# Antigravity Proxy\\nexport HTTP_PROXY=\\\"http://127.0.0.1:%s\\\"\\nexport HTTPS_PROXY=\\\"http://127.0.0.1:%s\\\"\\nexport ALL_PROXY=\\\"socks5://127.0.0.1:%s\\\"\\n\" \"$PORT\" \"$PORT\" \"$PORT\" | cat - \"$BASHRC\" > /tmp/brc && mv /tmp/brc \"$BASHRC\"; }; killall -9 language_server_linux_x64 antigravity-ide-server node 2>/dev/null; echo \"[✔] 完成！\"'"
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 13) {
                // MARK: - Header
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.indigo.opacity(0.18))
                            .frame(width: 32, height: 32)
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.indigo)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("远程开发与 SSH 保活助手")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .tracking(-0.2)
                        Text("一键解决远程开发断连、非交互式 SSH 代理丢失与 IDE 设置冲突")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        RemoteSshWindowManager.shared.close()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }

                ScrollView {
                    VStack(spacing: 12) {
                        // MARK: - 1. 本地 SSH 心跳防断连保活卡片
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "bolt.horizontal.fill")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 12))
                                Text("本地 SSH 长连接保活 (~/.ssh/config)")
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(isSshConfigured ? Color.green : Color.orange)
                                        .frame(width: 6, height: 6)
                                    Text(isSshConfigured ? "已启用保活" : "未优化")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(isSshConfigured ? .green : .orange)
                                }
                            }

                            Text("写入 ServerAliveInterval 15 等心跳参数，防止 VPN 闲置时 SSH 会话静默断开。")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)

                            HStack {
                                if let msg = sshStatusMessage {
                                    Text(msg)
                                        .font(.system(size: 10))
                                        .foregroundColor(.green)
                                }

                                Spacer()

                                Button {
                                    let res = AntigravityManager.optimizeLocalSshKeepAlive()
                                    isSshConfigured = AntigravityManager.checkSshKeepAliveStatus()
                                    sshStatusMessage = res.message
                                } label: {
                                    Text(isSshConfigured ? "重新优化" : "一键优化本地 SSH 保活")
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule().fill(Color.blue.opacity(0.18))
                                        )
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.blue.opacity(0.2), lineWidth: 0.8)
                                )
                        )

                        // MARK: - 2. 本地 IDE settings.json 代理智能防死锁
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "gearshape.2.fill")
                                    .foregroundColor(.purple)
                                    .font(.system(size: 12))
                                Text("本地 Antigravity IDE 代理防冲突托管")
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text("自动同步当前端口: \(manager.activePort)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }

                            Text("自动同步 settings.json 中的代理与 override 开关，消除 TLS 握手损坏报错。")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)

                            HStack {
                                if let msg = localIdeSyncMessage {
                                    Text(msg)
                                        .font(.system(size: 10))
                                        .foregroundColor(.green)
                                }

                                Spacer()

                                Button {
                                    isSyncingLocalIde = true
                                    AntigravityManager.syncLocalIdeProxySettings(useProxy: true, port: manager.activePort)
                                    localIdeSyncMessage = "已成功写入 settings.json 并解决冲突！"
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                        isSyncingLocalIde = false
                                        localIdeSyncMessage = nil
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        if isSyncingLocalIde {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            Image(systemName: "arrow.triangle.2.circlepath")
                                        }
                                        Text("手动立即解冲突")
                                    }
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule().fill(Color.purple.opacity(0.18))
                                    )
                                    .foregroundColor(.purple)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.purple.opacity(0.2), lineWidth: 0.8)
                                )
                        )

                        // MARK: - 3. 远程 Linux 服务器一键极速修复 (免终端)
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Image(systemName: "server.rack")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 12))
                                Text("远程 Linux 服务器代理环境一键修复")
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text("免终端一键穿透")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                                    .foregroundColor(.orange)
                            }

                            Text("解决 ~/.bashrc 中非交互式 SSH 会话跳过代理，导致远程 Agent 无法调用的问题。")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)

                            // 目标输入
                            VStack(spacing: 6) {
                                HStack(spacing: 8) {
                                    Text("SSH 目标:")
                                        .font(.system(size: 11, weight: .medium))
                                        .frame(width: 65, alignment: .leading)

                                    if !knownHosts.isEmpty {
                                        Picker("", selection: $selectedHost) {
                                            Text("已配置的主机...").tag("")
                                            ForEach(knownHosts, id: \.self) { host in
                                                Text(host).tag(host)
                                            }
                                        }
                                        .frame(width: 140)
                                    }

                                    TextField("或输入 user@192.168.x.x / 主机名", text: $customTarget)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11))
                                }

                                HStack(spacing: 8) {
                                    Text("代理端口:")
                                        .font(.system(size: 11, weight: .medium))
                                        .frame(width: 65, alignment: .leading)

                                    TextField(String(manager.activePort), text: $remotePort)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 11, design: .monospaced))
                                        .frame(width: 80)

                                    Text("(默认跟随当前代理端口: \(manager.activePort))")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)

                                    Spacer()
                                }
                            }

                            // 一键执行按钮
                            HStack {
                                Spacer()

                                Button {
                                    let target = effectiveTarget
                                    guard !target.isEmpty else { return }
                                    isRepairingRemote = true
                                    remoteRepairResult = nil

                                    Task {
                                        let res = await AntigravityManager.executeRemoteSshFix(target: target, proxyPort: effectivePort)
                                        await MainActor.run {
                                            self.isRepairingRemote = false
                                            self.remoteRepairResult = res
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        if isRepairingRemote {
                                            ProgressView().controlSize(.small)
                                            Text("正在通过 SSH 修复远程环境...")
                                        } else {
                                            Image(systemName: "paperplane.fill")
                                            Text("🚀 一键修复远程 Linux 服务器")
                                        }
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7)
                                            .fill(effectiveTarget.isEmpty ? Color.gray : Color.orange)
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(isRepairingRemote || effectiveTarget.isEmpty)
                            }

                            // 执行结果反馈
                            if let result = remoteRepairResult {
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: result.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                        .foregroundColor(result.success ? .green : .red)
                                        .font(.system(size: 12))
                                    Text(result.message)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(result.success ? .green : .red)
                                        .lineLimit(4)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(result.success ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                                )
                            }

                            // 备用命令查看
                            DisclosureGroup(isExpanded: $showManualCommand) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(manualBashCommand)
                                        .font(.system(size: 9, design: .monospaced))
                                        .padding(6)
                                        .background(Color.black.opacity(0.2))
                                        .cornerRadius(4)

                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(manualBashCommand, forType: .string)
                                        copiedCommand = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                            copiedCommand = false
                                        }
                                    } label: {
                                        Text(copiedCommand ? "✔ 已复制命令" : "复制命令至剪贴板")
                                            .font(.system(size: 10))
                                            .foregroundColor(.blue)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.top, 4)
                            } label: {
                                Text("查看备用手动命令 (若未配置 SSH 免密 Key)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.orange.opacity(0.2), lineWidth: 0.8)
                                )
                        )
                    }
                    .padding(.trailing, 2)
                }
            }
            .padding(18)
            .frame(width: 520, height: 490)
        }
        .background(.ultraThinMaterial)
        .onAppear {
            isSshConfigured = AntigravityManager.checkSshKeepAliveStatus()
            knownHosts = AntigravityManager.getKnownSshHosts()
            if let first = knownHosts.first {
                selectedHost = first
            }
        }
    }
}
