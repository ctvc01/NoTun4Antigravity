//
//  WhitelistView.swift
//  NoTun4Antigravity
//

import SwiftUI

struct WhitelistView: View {
    @AppStorage("whitelistRules") private var whitelistRules: String = AntigravityManager.defaultWhitelistLines
    @AppStorage("proxyPort") private var proxyPort: Int = AntigravityManager.defaultProxyPort
    @AppStorage("useProxy") private var useProxy: Bool = true

    @ObservedObject private var manager = AntigravityManager.shared

    @State private var editorContent: String = ""
    @State private var showToast: Bool = false
    @State private var toastMessage: String = ""

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.16))
                            .frame(width: 32, height: 32)
                        Image(systemName: "shield.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.blue)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("直连白名单规则")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .tracking(-0.2)
                        Text("匹配的域名或 IP 将不走本地代理，保证公司内网直连")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                // Editor Box with Glassmorphism Card
                VStack(alignment: .leading, spacing: 6) {
                    Text("规则列表 (每行一条规则):")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    TextEditor(text: $editorContent)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor).opacity(0.6))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                        )
                }

                // Bottom Actions
                HStack(alignment: .center) {
                    Button("清空规则") {
                        editorContent = ""
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))

                    Spacer()

                    Button("取消") {
                        WhitelistWindowManager.shared.close()
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

                    Button("保存并应用") {
                        submitRules()
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
            .frame(width: 460, height: 380)

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
                        Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.8)
                    )
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.94).combined(with: .opacity).animation(.spring(response: 0.28, dampingFraction: 0.78)),
                            removal: .scale(scale: 0.96).combined(with: .opacity).animation(.easeOut(duration: 0.15))
                        )
                    )
                    .padding(.bottom, 20)
                }
            }
        }
        .background(.ultraThinMaterial)
        .onAppear {
            editorContent = whitelistRules
        }
    }

    private func submitRules() {
        whitelistRules = editorContent

        if manager.isRunning {
            manager.restart(useProxy: useProxy, proxyPort: proxyPort, rawWhitelistText: editorContent)
            toastMessage = "白名单已保存，正在重启 Antigravity 生效..."
        } else {
            toastMessage = "白名单已保存，下次启动时生效。"
        }

        withAnimation {
            showToast = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation {
                showToast = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                WhitelistWindowManager.shared.close()
            }
        }
    }
}
