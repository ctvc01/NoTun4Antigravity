//
//  ProxyPortView.swift
//  NoTun4Antigravity
//

import SwiftUI

struct ProxyPortView: View {
    var onBack: () -> Void

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
            VStack(alignment: .leading, spacing: 13) {
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
                        Text("代理端口设置")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        Text("配置注入进程的本地代理端口")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("默认") {
                        portInput = "\(AntigravityManager.defaultProxyPort)"
                        testResult = nil
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 2)

                // MARK: - Port Input & Health Card
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text("本地监听端口:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        TextField("如 7890", text: $portInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)

                        Button {
                            testConnection()
                        } label: {
                            HStack(spacing: 3) {
                                if isTesting {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                }
                                Text("测试")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.8))
                            )
                        }
                        .buttonStyle(SpringButtonStyle(scale: 0.95))
                        .disabled(isTesting)
                    }

                    if let result = testResult {
                        Text(result)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(result.contains("🟢") ? .green : (result.contains("🔴") ? .red : .secondary))
                            .lineLimit(2)
                            .transition(.opacity)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                        )
                )

                // MARK: - Save Action Button
                Button {
                    submitPort()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("保存并生效")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundColor(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.blue)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                            )
                    )
                    .shadow(color: Color.blue.opacity(0.35), radius: 5, x: 0, y: 2)
                }
                .buttonStyle(SpringButtonStyle(scale: 0.98))
                .keyboardShortcut(.defaultAction)
            }
            .padding(14)
            .frame(width: 310)

            // MARK: - Toast Overlay
            if showToast {
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 12, weight: .bold))
                        Text(toastMessage)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.ultraThickMaterial)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 3)
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                    )
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.94).combined(with: .opacity).animation(.spring(response: 0.28, dampingFraction: 0.78)),
                            removal: .scale(scale: 0.96).combined(with: .opacity).animation(.easeOut(duration: 0.15))
                        )
                    )
                    .padding(.bottom, 2)
                }
            }
        }
        .onAppear {
            portInput = String(proxyPort)
            testConnection()
        }
    }

    private func testConnection() {
        let filtered = portInput.filter { "0123456789".contains($0) }
        guard let p = Int(filtered), p > 0, p <= 65535 else {
            testResult = "⚠️ 请输入有效端口 (1~65535)"
            return
        }

        isTesting = true
        testResult = "正在探测端口 127.0.0.1:\(p)..."
        DispatchQueue.global(qos: .userInitiated).async {
            let isOpen = AntigravityManager.isPortOpen(port: p)
            DispatchQueue.main.async {
                self.isTesting = false
                self.testResult = isOpen ? "🟢 端口就绪 (127.0.0.1:\(p) 正在监听)" : "🔴 未检测到服务，请确认代理客户端已启动"
            }
        }
    }

    private func submitPort() {
        let filtered = portInput.filter { "0123456789".contains($0) }
        guard let p = Int(filtered), p > 0, p <= 65535 else {
            testResult = "⚠️ 请输入有效端口 (1~65535)"
            return
        }

        proxyPort = p
        manager.refreshStatus(port: p)

        if manager.isRunning {
            manager.restart(useProxy: useProxy, proxyPort: p, rawWhitelistText: whitelistRules)
            toastMessage = "端口已设为 \(p)，正在重启生效"
        } else {
            toastMessage = "端口已设为 \(p)，启动时生效"
        }

        withAnimation {
            showToast = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            withAnimation {
                showToast = false
            }
            onBack()
        }
    }
}
