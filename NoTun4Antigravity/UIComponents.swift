//
//  UIComponents.swift
//  NoTun4Antigravity
//

import SwiftUI

// MARK: - Emil Design Engineering Spring Button Style
struct SpringButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    var feedbackBrightness: Double = -0.04

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .brightness(configuration.isPressed ? feedbackBrightness : 0.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

// MARK: - Custom Fluid Glass Capsule Switch
struct FluidGlassToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.75)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(
                        isOn
                            ? LinearGradient(
                                colors: [Color(red: 0.15, green: 0.52, blue: 0.98), Color(red: 0.1, green: 0.42, blue: 0.88)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color.secondary.opacity(0.22), Color.secondary.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                    )
                    .frame(width: 36, height: 21)
                    .overlay(
                        Capsule()
                            .stroke(
                                isOn ? Color.white.opacity(0.28) : Color.white.opacity(0.1),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(color: isOn ? Color.blue.opacity(0.3) : .clear, radius: 4, x: 0, y: 1)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white, Color(white: 0.92)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 17, height: 17)
                    .padding(2)
                    .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reusable Glassmorphism Card Container
struct GlassCard<Content: View>: View {
    var isHovered: Bool = false
    let content: Content

    init(isHovered: Bool = false, @ViewBuilder content: () -> Content) {
        self.isHovered = isHovered
        self.content = content()
    }

    var body: some View {
        content
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(isHovered ? 0.65 : 0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isHovered ? 0.32 : 0.2),
                                        Color.white.opacity(isHovered ? 0.08 : 0.04)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
            )
            .animation(.easeOut(duration: 0.16), value: isHovered)
    }
}
