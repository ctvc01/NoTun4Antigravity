//
//  ControlCenterView.swift
//  NoTun4Antigravity
//

import SwiftUI

struct ControlCenterView: View {
    @ObservedObject var manager = AntigravityManager.shared

    @AppStorage("proxyPort") private var proxyPort: Int = AntigravityManager.defaultProxyPort
    @AppStorage("useProxy") private var useProxy: Bool = true
    @AppStorage("whitelistRules") private var whitelistRules: String = AntigravityManager.defaultWhitelistLines

    @State private var isHoveringProxyCard = false
    @State private var isHoveringWhitelist = false
    @State private var isHoveringRestart = false
    @State private var isHoveringQuit = false

    // 动态计算当前生效中的白名单规则数量
    private var activeRuleCount: Int {
        whitelistRules
            .components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: ",")))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    // 动态读取版本号
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        VStack(spacing: 12) {
            // MARK: - 1. Top Header: Brand & Live Status
            HStack(alignment: .center, spacing: 10) {
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 1)

                VStack(alignment: .leading, spacing: 1) {
                    Text("NoTun")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .tracking(-0.2)
                    Text("Antigravity Launcher")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Status Pill Badge (Direct & Clear)
                HStack(spacing: 5) {
                    Circle()
                        .fill(manager.isRunning ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 7, height: 7)
                        .shadow(color: manager.isRunning ? Color.green.opacity(0.8) : .clear, radius: 4)

                    Text(manager.isRunning ? "运行中" : "已停止")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(manager.isRunning ? .primary : .secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                        )
                )
            }
            .padding(.horizontal, 4)

            // MARK: - 2. Proxy Hub Card (Title + Subtitle with Dot & Port & Edit Link)
            GlassCard(isHovered: isHoveringProxyCard) {
                HStack(spacing: 11) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(useProxy ? Color.blue.opacity(0.16) : Color.secondary.opacity(0.12))
                            .frame(width: 28, height: 28)

                        Image(systemName: "globe.americas.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(useProxy ? Color.blue : Color.secondary)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Antigravity代理")
                            .font(.system(size: 12, weight: .semibold))

                        // 副标题：状态圆点 + 代理端口 20890 + 「修改」文字链
                        HStack(spacing: 5) {
                            Circle()
                                .fill(manager.isProxyPortReady ? Color.green : Color.orange)
                                .frame(width: 5, height: 5)
                                .shadow(color: manager.isProxyPortReady ? Color.green.opacity(0.6) : Color.orange.opacity(0.6), radius: 2)

                            Text("代理端口 \(String(proxyPort))")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundColor(.secondary)

                            Button {
                                ProxyPortWindowManager.shared.show()
                            } label: {
                                Text("修改")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer()

                    FluidGlassToggle(isOn: $useProxy)
                }
            }
            .onHover { isHoveringProxyCard = $0 }

            // MARK: - 3. Whitelist Rules Card (Dynamic "n 条规则生效中")
            Button {
                WhitelistWindowManager.shared.show()
            } label: {
                GlassCard(isHovered: isHoveringWhitelist) {
                    HStack(spacing: 11) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.blue.opacity(0.16))
                                .frame(width: 28, height: 28)

                            Image(systemName: "shield.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color.blue)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text("直连白名单规则")
                                .font(.system(size: 12, weight: .semibold))

                            Text("\(activeRuleCount) 条规则生效中")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
            }
            .buttonStyle(SpringButtonStyle(scale: 0.98))
            .onHover { isHoveringWhitelist = $0 }

            // MARK: - 4. Footer Actions
            HStack(alignment: .center, spacing: 8) {
                // Version Info
                Text("v\(appVersion)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.leading, 2)

                Spacer()

                // Apply & Restart Button
                Button {
                    manager.restart(useProxy: useProxy, proxyPort: proxyPort, rawWhitelistText: whitelistRules)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                        Text("应用配置&重启")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(isHoveringRestart ? 0.85 : 0.45))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                            )
                    )
                }
                .buttonStyle(SpringButtonStyle())
                .onHover { isHoveringRestart = $0 }

                // Quit Button
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "power")
                            .font(.system(size: 10, weight: .semibold))
                        Text("退出")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(isHoveringQuit ? 0.85 : 0.35))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                            )
                    )
                }
                .buttonStyle(SpringButtonStyle())
                .keyboardShortcut("q", modifiers: [.command])
                .onHover { isHoveringQuit = $0 }
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 310)
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.14),
                        Color.white.opacity(0.02),
                        Color.black.opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.38), Color.white.opacity(0.09)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}
