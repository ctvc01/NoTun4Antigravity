//
//  NodeSpeedTestWindowManager.swift
//  NoTun4Antigravity
//

import AppKit
import SwiftUI

@MainActor
final class NodeSpeedTestWindowManager: NSObject, NSWindowDelegate {
    static let shared = NodeSpeedTestWindowManager()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func show() {
        if let existing = window, existing.isVisible {
            existing.orderFrontRegardless()
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let speedTestView = NodeSpeedTestView()
        let hostingController = NSHostingController(rootView: speedTestView)

        let newWindow = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
            styleMask: [.titled, .closable, .miniaturizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newWindow.center()
        newWindow.title = "Node Health & Speed Test (节点真机测速)"
        newWindow.contentViewController = hostingController
        newWindow.isReleasedWhenClosed = false
        newWindow.level = .floating
        newWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newWindow.delegate = self

        self.window = newWindow

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
