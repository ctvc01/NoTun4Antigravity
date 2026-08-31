//
//  NoTun4AntigravityTests.swift
//  NoTun4AntigravityTests
//

import Testing
@testable import NoTun4Antigravity

struct NoTun4AntigravityTests {

    @Test func testDefaultConfiguration() async throws {
        #expect(AntigravityManager.defaultProxyPort == 20890)
    }

}
