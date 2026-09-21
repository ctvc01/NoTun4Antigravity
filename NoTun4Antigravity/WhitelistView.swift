//
//  WhitelistView.swift
//  NoTun4Antigravity
//

import SwiftUI

struct WhitelistView: View {
    var onBack: () -> Void

    @AppStorage("whitelistRules") private var whitelistRules: String = AntigravityManager.defaultWhitelistLines
    @AppStorage("proxyPort") private var proxyPort: Int = AntigravityManager.defaultProxyPort
    @AppStorage("useProxy") private var useProxy: Bool = true

    @ObservedObject private var manager = AntigravityManager.shared

    @State private var editorContent: String = ""
    @State private var showToast: Bool = false
    @State private var toastMessage: String = ""

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 11) {
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
                        Text("直连白名单规则")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        Text("跳过代理直接走物理网卡")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("清空") {
                        editorContent = ""
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 2)

                // MARK: - Rules Editor
                VStack(alignment: .leading, spacing: 7) {
                    TextEditor(text: $editorContent)
                        .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                        .frame(height: 230)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor).opacity(0.45))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("支持每行一条: *.ctripcorp.com, 10.0.0.0/8, 公司内部网段等")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary.opacity(0.85))
                        HStack(spacing: 3) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 8.5))
                                .foregroundColor(.blue)
                            Text("保存自动与 macOS 系统网络代理白名单做并集合并，防客户端冲掉")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.leading, 2)
                }

                // MARK: - Save Action
                Button {
                    submitRules()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("保存并应用规则")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
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

            // MARK: - Toast Feedback
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
            editorContent = whitelistRules
        }
    }

    private func submitRules() {
        whitelistRules = editorContent

        // ponytail: 保存时无论 Antigravity 是否运行，均立即将白名单合并同步至 macOS 系统网络代理，防第三方代理软件冲掉
        AntigravityManager.syncSystemProxyBypassDomains(rawText: editorContent)

        if manager.isRunning {
            manager.restart(useProxy: useProxy, proxyPort: proxyPort, rawWhitelistText: editorContent)
            toastMessage = "已保存并与系统代理白名单合并"
        } else {
            toastMessage = "已保存并与系统代理白名单合并"
        }

        withAnimation {
            showToast = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            withAnimation {
                showToast = false
            }
            onBack()
        }
    }
}
