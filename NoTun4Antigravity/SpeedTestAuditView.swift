//
//  SpeedTestAuditView.swift
//  NoTun4Antigravity
//
//  Created by Antigravity on 2026/9/21.
//

import SwiftUI
import AppKit

struct SpeedTestAuditView: View {
    var onBack: () -> Void

    @ObservedObject private var logger = SpeedTestAuditLogger.shared
    @ObservedObject private var manager = AntigravityManager.shared

    @State private var showRawLogSheet: Bool = false
    @State private var copyToastText: String? = nil
    @State private var filterVerdict: AuditVerdictType? = nil

    private var report: AuditCorrelationReport {
        logger.report
    }

    private var displayedComparisons: [AuditComparisonItem] {
        if let filter = filterVerdict {
            return report.recentComparisons.filter { $0.verdictType == filter }
        }
        return report.recentComparisons
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: - Header
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
                    Text("测速质检与连接日志")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text("比对 Antigravity 真实连接与节点测速")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    manager.probeCurrentNodeHealth()
                    manager.sampleActualAntigravityConnection()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9))
                        Text("立即诊断")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)

            // MARK: - 1. 指标仪表卡片 (3 列紧凑网格)
            HStack(spacing: 7) {
                // 真实吻合度
                metricCard(
                    title: "测速真实吻合率",
                    value: String(format: "%.0f%%", report.consistencyRatePercent),
                    color: report.consistencyRatePercent >= 80 ? .green : .orange,
                    subtext: "\(report.alignedComparisonCount) 次样本对齐"
                )

                // 综合可参考度评分
                metricCard(
                    title: "参考可用度评分",
                    value: "\(report.calibratedReliabilityScore)",
                    color: report.calibratedReliabilityScore >= 80 ? .blue : (report.calibratedReliabilityScore >= 60 ? .orange : .red),
                    subtext: report.calibratedReliabilityScore >= 80 ? "结果高可靠" : "存在虚标"
                )

                // 虚假繁荣拦截
                metricCard(
                    title: "测速虚高拦截",
                    value: "\(report.falsePositiveCount)",
                    color: report.falsePositiveCount == 0 ? .green : .red,
                    subtext: "假绿灯/实际断连"
                )
            }

            // MARK: - 2. 状态比对时间线
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("测速预估 vs 实际通信比对记录")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)

                    Spacer()

                    if let filter = filterVerdict {
                        Button {
                            filterVerdict = nil
                        } label: {
                            Text("重置筛选")
                                .font(.system(size: 9))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if displayedComparisons.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text(logger.entries.isEmpty ? "暂无日志数据，正在持续监听通信..." : "已记录 \(logger.entries.count) 条原始日志，等待对齐样本...")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                    .cornerRadius(8)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(displayedComparisons) { item in
                                comparisonRow(item)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(height: 230)
                }
            }

            // MARK: - 3. 底部操作栏 (查看/导出日志、清空日志)
            HStack(spacing: 8) {
                Button {
                    showRawLogSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9))
                        Text("查看原始日志 (\(logger.entries.count))")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    .cornerRadius(6)
                }
                .buttonStyle(SpringButtonStyle(scale: 0.96))

                Button {
                    copyLogsToClipboard()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                        Text(copyToastText ?? "复制日志")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    .cornerRadius(6)
                }
                .buttonStyle(SpringButtonStyle(scale: 0.96))

                Button {
                    logger.clearLogs()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("清空日志记录")
            }
        }
        .padding(14)
        .sheet(isPresented: $showRawLogSheet) {
            rawLogSheetView
        }
    }

    // MARK: - Subviews

    private func metricCard(title: String, value: String, color: Color, subtext: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9.5))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(subtext)
                .font(.system(size: 8))
                .foregroundColor(.secondary.opacity(0.8))
                .lineLimit(1)
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.45))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(color.opacity(0.2), lineWidth: 0.8)
        )
    }

    private func comparisonRow(_ item: AuditComparisonItem) -> some View {
        HStack(alignment: .center, spacing: 8) {
            // 时间
            Text(formatTime(item.timestamp))
                .font(.system(size: 9, weight: .regular, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .leading)

            // 比对数据横向铺开（呼吸感）
            HStack(spacing: 12) {
                HStack(spacing: 3) {
                    Text("预估:")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(item.probeStatus)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary)
                }

                HStack(spacing: 3) {
                    Text("实际:")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text(item.actualStatus)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(item.verdictType == .falsePositive ? .red : .primary)
                }
            }

            Spacer()

            // 结论徽章
            verdictBadge(item.verdictType)
        }
        .padding(6)
        .background(Color(NSColor.textBackgroundColor).opacity(0.3))
        .cornerRadius(6)
    }

    private func verdictBadge(_ type: AuditVerdictType) -> some View {
        let text: String
        let color: Color
        switch type {
        case .consistent:
            text = "吻合"
            color = .green
        case .falsePositive:
            text = "虚高"
            color = .red
        case .falseNegative:
            text = "可用"
            color = .orange
        case .bothFailed:
            text = "均断"
            color = .secondary
        case .pending:
            text = "待定"
            color = .secondary
        }

        return Text(text)
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(color.opacity(0.3), lineWidth: 0.6)
            )
    }

    private var rawLogSheetView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("原始质检日志 (\(logger.entries.count) 条记录)")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Button("关闭") {
                    showRawLogSheet = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
            }

            TextEditor(text: .constant(logger.exportLogsAsText()))
                .font(.system(size: 10, design: .monospaced))
                .padding(4)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)

            HStack {
                Button("复制到剪贴板") {
                    copyLogsToClipboard()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.blue)

                Spacer()

                Button("清空全部") {
                    logger.clearLogs()
                    showRawLogSheet = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundColor(.red)
            }
        }
        .padding(12)
        .frame(width: 420, height: 320)
    }

    // MARK: - Helpers

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func copyLogsToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(logger.exportLogsAsText(), forType: .string)

        withAnimation {
            copyToastText = "已复制!"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation {
                copyToastText = nil
            }
        }
    }
}
