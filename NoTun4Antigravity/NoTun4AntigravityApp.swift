//
//  NoTun4AntigravityApp.swift
//  NoTun4Antigravity
//

import SwiftUI

@main
struct NoTun4AntigravityApp: App {
    @StateObject private var manager = AntigravityManager.shared

    var body: some Scene {
        MenuBarExtra {
            ControlCenterView(manager: manager)
        } label: {
            Image(systemName: manager.isRunning ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle")
        }
        .menuBarExtraStyle(.window)
    }
}
