//
//  SpeedTestAuditLogger.swift
//  NoTun4Antigravity
//
//  Created by Antigravity on 2026/9/21.
//

import Foundation
import Combine

// MARK: - Audit Models

enum AuditLogCategory: String, Codable {
    case probeTest = "测速探活"
    case actualConnection = "实际通信"
}

enum AuditVerdictType: String, Codable {
    case consistent = "吻合有效"
    case falsePositive = "测速虚高(实际断连)"
    case falseNegative = "测速低估(实际可用)"
    case bothFailed = "一致断连"
    case pending = "待对比"
}

struct AuditLogEntry: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var category: AuditLogCategory
    var target: String
    var port: Int
    var latencyMs: Int?
    var tcpPingMs: Int?
    var tlsHandshakeMs: Int?
    var aiTtfbMs: Int?
    var isSuccess: Bool
    var httpStatus: Int?
    var errorDetail: String?
    var verdictType: AuditVerdictType = .pending
}

struct AuditComparisonItem: Identifiable, Equatable {
    var id: UUID = UUID()
    var timestamp: Date
    var probeEstimatedLatency: Int?
    var probeStatus: String
    var actualLatency: Int?
    var actualStatus: String
    var verdict: String
    var verdictType: AuditVerdictType
}

struct AuditCorrelationReport: Equatable {
    var totalProbeCount: Int = 0
    var totalActualCount: Int = 0
    var alignedComparisonCount: Int = 0
    var consistencyRatePercent: Double = 100.0
    var falsePositiveCount: Int = 0
    var calibratedReliabilityScore: Int = 100
    var recentComparisons: [AuditComparisonItem] = []
}

// MARK: - Audit Logger Engine

final class SpeedTestAuditLogger: ObservableObject {
    static let shared = SpeedTestAuditLogger()

    @Published private(set) var entries: [AuditLogEntry] = []
    @Published private(set) var report: AuditCorrelationReport = AuditCorrelationReport()

    private let maxEntries = 400
    private let logFileUrl: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("NoTun4Antigravity/logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.logFileUrl = dir.appendingPathComponent("speed_test_audit.jsonl")

        loadFromDisk()
        recalculateReport()
    }

    // MARK: - Logging APIs

    func recordProbe(
        port: Int,
        target: String = "Google Gemini AI",
        tcpPingMs: Int? = nil,
        tlsHandshakeMs: Int? = nil,
        ttfbMs: Int? = nil,
        isSuccess: Bool,
        errorDetail: String? = nil
    ) {
        let entry = AuditLogEntry(
            category: .probeTest,
            target: target,
            port: port,
            latencyMs: ttfbMs ?? tlsHandshakeMs ?? tcpPingMs,
            tcpPingMs: tcpPingMs,
            tlsHandshakeMs: tlsHandshakeMs,
            aiTtfbMs: ttfbMs,
            isSuccess: isSuccess,
            httpStatus: isSuccess ? 200 : nil,
            errorDetail: errorDetail
        )
        appendEntry(entry)
    }

    func recordActualConnection(
        port: Int,
        endpoint: String,
        latencyMs: Int?,
        isSuccess: Bool,
        httpStatus: Int?,
        errorDetail: String? = nil
    ) {
        let entry = AuditLogEntry(
            category: .actualConnection,
            target: endpoint,
            port: port,
            latencyMs: latencyMs,
            isSuccess: isSuccess,
            httpStatus: httpStatus,
            errorDetail: errorDetail
        )
        appendEntry(entry)
    }

    // MARK: - Internal Append & Save

    private func appendEntry(_ entry: AuditLogEntry) {
        DispatchQueue.main.async {
            self.entries.insert(entry, at: 0)
            if self.entries.count > self.maxEntries {
                self.entries.removeLast(self.entries.count - self.maxEntries)
            }
            self.recalculateReport()
            self.appendToFile(entry: entry)
        }
    }

    private func appendToFile(entry: AuditLogEntry) {
        DispatchQueue.global(qos: .utility).async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(entry),
                  var line = String(data: data, encoding: .utf8) else { return }
            line.append("\n")

            if let handle = try? FileHandle(forWritingTo: self.logFileUrl) {
                handle.seekToEndOfFile()
                if let lineData = line.data(using: .utf8) {
                    handle.write(lineData)
                }
                try? handle.close()
            } else {
                try? line.write(to: self.logFileUrl, atomically: true, encoding: .utf8)
            }
        }
    }

    private func loadFromDisk() {
        guard let content = try? String(contentsOf: logFileUrl, encoding: .utf8) else { return }
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var loaded: [AuditLogEntry] = []
        for line in lines.suffix(maxEntries) {
            if let data = line.data(using: .utf8), let entry = try? decoder.decode(AuditLogEntry.self, from: data) {
                loaded.append(entry)
            }
        }
        self.entries = loaded.reversed()
    }

    func clearLogs() {
        entries.removeAll()
        report = AuditCorrelationReport()
        try? FileManager.default.removeItem(at: logFileUrl)
    }

    func exportLogsAsText() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines: [String] = []
        lines.append("=== NoTun4Antigravity 实际连接与测速质检日志 ===")
        lines.append("导出时间: \(formatter.string(from: Date()))")
        lines.append("对齐吻合率: \(String(format: "%.1f", report.consistencyRatePercent))% | 虚高拦截: \(report.falsePositiveCount)次 | 可参考得分: \(report.calibratedReliabilityScore)/100")
        lines.append("--------------------------------------------------")

        for item in entries {
            let timeStr = formatter.string(from: item.timestamp)
            let statusStr = item.isSuccess ? "成功" : "失败 (\(item.errorDetail ?? "网络中断"))"
            let latStr = item.latencyMs != nil ? "\(item.latencyMs!)ms" : "-"
            lines.append("[\(timeStr)] [\(item.category.rawValue)] 目标:\(item.target) 端口:\(item.port) 耗时:\(latStr) 状态:\(statusStr)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Correlation & Calibration Engine

    func recalculateReport() {
        let probes = entries.filter { $0.category == .probeTest }
        let actuals = entries.filter { $0.category == .actualConnection }

        var comparisons: [AuditComparisonItem] = []
        var consistentCount = 0
        var falsePositiveCount = 0
        var totalCompared = 0

        // 以滑动时间窗口（5分钟内）将每次探活与实际 IDE 连接进行交叉关联对齐
        for probe in probes {
            let probeTime = probe.timestamp.timeIntervalSince1970
            // 查找与该测速时间相邻（±300秒内）的实际通信事件
            let matchedActuals = actuals.filter {
                abs($0.timestamp.timeIntervalSince1970 - probeTime) <= 300.0
            }

            guard let closest = matchedActuals.min(by: {
                abs($0.timestamp.timeIntervalSince1970 - probeTime) < abs($1.timestamp.timeIntervalSince1970 - probeTime)
            }) else {
                continue
            }

            totalCompared += 1
            let verdict: String
            let verdictType: AuditVerdictType

            if probe.isSuccess && closest.isSuccess {
                verdict = "吻合有效"
                verdictType = .consistent
                consistentCount += 1
            } else if probe.isSuccess && !closest.isSuccess {
                verdict = "测速虚高(实际断连)"
                verdictType = .falsePositive
                falsePositiveCount += 1
            } else if !probe.isSuccess && closest.isSuccess {
                verdict = "测速低估(实际可用)"
                verdictType = .falseNegative
                consistentCount += 1
            } else {
                verdict = "一致断连"
                verdictType = .bothFailed
                consistentCount += 1
            }

            comparisons.append(AuditComparisonItem(
                timestamp: probe.timestamp,
                probeEstimatedLatency: probe.latencyMs,
                probeStatus: probe.isSuccess ? "全通 (\(probe.latencyMs ?? 0)ms)" : "失败",
                actualLatency: closest.latencyMs,
                actualStatus: closest.isSuccess ? "通畅 (\(closest.latencyMs ?? 0)ms)" : "断连 (\(closest.errorDetail ?? "502"))",
                verdict: verdict,
                verdictType: verdictType
            ))

            if comparisons.count >= 40 { break }
        }

        let rate = totalCompared > 0 ? (Double(consistentCount) / Double(totalCompared)) * 100.0 : 100.0

        // 校准后综合可用性得分：基础分为实际成功率，若虚高误报频繁，大幅扣除虚假信任分
        var baseScore = 95
        if totalCompared > 0 {
            let penalty = falsePositiveCount * 18
            baseScore = max(10, min(100, Int(rate) - penalty))
        }

        self.report = AuditCorrelationReport(
            totalProbeCount: probes.count,
            totalActualCount: actuals.count,
            alignedComparisonCount: totalCompared,
            consistencyRatePercent: rate,
            falsePositiveCount: falsePositiveCount,
            calibratedReliabilityScore: baseScore,
            recentComparisons: comparisons
        )
    }
}
