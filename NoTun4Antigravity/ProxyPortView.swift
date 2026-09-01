//
//  ProxyPortView.swift
//  NoTun4Antigravity
//

import SwiftUI

struct ProxyPortView: View {
    @AppStorage("proxyPort") private var proxyPort: Int = AntigravityManager.defaultProxyPort
    @AppStorage("useProxy") private var useProxy: Bool = true
    @AppStorage("whitelistRules") private var whitelistRules: String = AntigravityManager.defaultWhitelistLines

    @ObservedObject private var manager = AntigravityManager.shared

    @State private var portInput: String = ""
    @State private var testResult: String? = nil
    @State private var isTesting: Bool = false
    @State private var showToast: Bool = false
    @State private var toastMessage: String = ""

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.cyan.opacity(0.2))
                            .frame(width: 34, height: 34)
                        Image(systemName: "network")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.cyan)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("代理端口设置 (Proxy Port)")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .tracking(-0.2)
                        Text("配置拉起 Antigravity 时注入的本地代理监听端口")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                // Input & Health Check Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Text("本地代理端口:")
                            .font(.system(size: 12, weight: .medium))

                        TextField("例如 20890", text: $portInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .frame(width: 110)

                        Button {
                            testConnection()
                        } label: {
                            HStack(spacing: 4) {
                                if isTesting {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                }
                                Text("测试端口")
                            }
                            .font(.system(size: 11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(NSColor.controlBackgroundColor))
                            )
                        }
                        .buttonStyle(SpringButtonStyle(scale: 0.96))
                        .disabled(isTesting)
                    }

                    if let result = testResult {
                        HStack(spacing: 6) {
                            Text(result)
                                .font(.system(size: 11))
                                .monospacedDigit()
                        }
                        .padding(.vertical, 2)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                        )
                )

                // Bottom Action Buttons
                HStack {
                    Button("恢复默认 (20890)") {
                        portInput = "\(AntigravityManager.defaultProxyPort)"
                        testResult = nil
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))

                    Spacer()

                    Button("取消") {
                        ProxyPortWindowManager.shared.close()
                    }
                    .buttonStyle(SpringButtonStyle())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    )
                    .keyboardShortcut(.cancelAction)

                    Button("保存并生效") {
                        submitPort()
                    }
                    .buttonStyle(SpringButtonStyle(scale: 0.96))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
                            )
                    )
                    .shadow(color: Color.blue.opacity(0.35), radius: 4, x: 0, y: 2)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 4)
            }
            .padding(18)
            .frame(width: 420, height: 210)

            // MARK: - Toast Overlay
            if showToast {
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 14, weight: .bold))
                        Text(toastMessage)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThickMaterial)
                    .cornerRadius(20)
                    .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                    )
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.94).combined(with: .opacity).animation(.spring(response: 0.28, dampingFraction: 0.78)),
                            removal: .scale(scale: 0.96).combined(with: .opacity).animation(.easeOut(duration: 0.15))
                        )
                    )
                    .padding(.bottom, 16)
                }
            }
        }
        .background(.ultraThinMaterial)
        .onAppear {
            portInput = String(proxyPort)
            testConnection()
        }
    }

    private func testConnection() {
        let filtered = portInput.filter { "0123456789".contains($0) }
        guard let p = Int(filtered), p > 0, p <= 65535 else {
            testResult = "⚠️ 请输入有效的端口号 (1~65535)"
            return
        }

        isTesting = true
        testResult = "正在探测端口 127.0.0.1:\(p)..."
        DispatchQueue.global(qos: .userInitiated).async {
            let isOpen = AntigravityManager.isPortOpen(port: p)
            DispatchQueue.main.async {
                self.isTesting = false
                self.testResult = isOpen ? "🟢 端口就绪 (127.0.0.1:\(p) 正在监听)" : "🔴 未检测到服务，请确认代理软件已启动"
            }
        }
    }

    private func submitPort() {
        let filtered = portInput.filter { "0123456789".contains($0) }
        guard let p = Int(filtered), p > 0, p <= 65535 else {
            testResult = "⚠️ 请输入有效的端口号 (1~65535)"
            return
        }

        proxyPort = p
        manager.refreshStatus(port: p)

        if manager.isRunning {
            manager.restart(useProxy: useProxy, proxyPort: p, rawWhitelistText: whitelistRules)
            toastMessage = "端口已保存为 \(p)，正在重启 Antigravity 生效..."
        } else {
            toastMessage = "端口已保存为 \(p)，下次启动时生效。"
        }

        withAnimation {
            showToast = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation {
                showToast = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                ProxyPortWindowManager.shared.close()
            }
        }
    }
}
