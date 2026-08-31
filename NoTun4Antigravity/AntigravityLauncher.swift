//
//  AntigravityLauncher.swift
//  NoTun4Antigravity
//

import Foundation

final class AntigravityLauncher {
    @MainActor
    static func launch(useProxy: Bool = true, port: Int = AntigravityManager.defaultProxyPort) {
        AntigravityManager.shared.launch(useProxy: useProxy, proxyPort: port)
    }
}
