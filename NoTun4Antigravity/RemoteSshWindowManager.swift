//
//  RemoteSshWindowManager.swift
//  NoTun4Antigravity
//

import AppKit
import SwiftUI

@MainActor
final class RemoteSshWindowManager: NSObject, NSWindowDelegate {
    static let shared = RemoteSshWindowManager()

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

        let assistantView = RemoteSshAssistantView()
        let hostingController = NSHostingController(rootView: assistantView)

        let newWindow = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 490),
            styleMask: [.titled, .closable, .miniaturizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newWindow.center()
        newWindow.title = "Remote SSH & IDE Assistant (远程与 SSH 助手)"
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
