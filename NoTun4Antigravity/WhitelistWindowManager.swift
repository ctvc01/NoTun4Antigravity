//
//  WhitelistWindowManager.swift
//  NoTun4Antigravity
//

import AppKit
import SwiftUI

@MainActor
final class WhitelistWindowManager: NSObject, NSWindowDelegate {
    static let shared = WhitelistWindowManager()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func show() {
        // 如果窗口已存在且可见，直接置顶激活
        if let existing = window, existing.isVisible {
            existing.orderFrontRegardless()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let whitelistView = WhitelistView()
        let hostingController = NSHostingController(rootView: whitelistView)

        let newWindow = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 380),
            styleMask: [.titled, .closable, .miniaturizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newWindow.center()
        newWindow.title = "Whitelist Rules (直连白名单配置)"
        newWindow.contentViewController = hostingController
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating // 置顶浮动，确保不会被全屏或前台窗口遮挡
        newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newWindow.delegate = self

        self.window = newWindow

        // 确保在菜单关闭后平滑展现并获得输入焦点
        DispatchQueue.main.async {
            newWindow.center()
            newWindow.orderFrontRegardless()
            newWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func close() {
        window?.close()
        window = nil
    }

    // MARK: - NSWindowDelegate
    nonisolated func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            self.window = nil
        }
    }
}
