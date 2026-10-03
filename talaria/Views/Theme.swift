import SwiftUI

/// Glass: a soft tinted background, translucent layers with hairline borders, tight corners,
/// no drop shadows. Colors carry meaning: accent for chat, red for recording.
enum Theme {
    static let corner: CGFloat = 14
    static let small: CGFloat = 12
    static let line = Color.primary.opacity(0.09)
    static let accent = Color.accentColor
    static let rec = Color.red
}

struct GlassBackground: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
            RadialGradient(colors: [Color.pink.opacity(0.13), .clear], center: UnitPoint(x: 0.1, y: 0.0), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color.blue.opacity(0.13), .clear], center: UnitPoint(x: 1.0, y: 1.0), startRadius: 0, endRadius: 620)
        }
        .ignoresSafeArea()
    }
}

private struct GlassCard: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View {
        content
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.line))
    }
}

extension View {
    /// A translucent panel with a hairline border.
    func glass(_ radius: CGFloat = Theme.corner) -> some View { modifier(GlassCard(radius: radius)) }
}

/// A symbol on a tinted rounded square, used in inbox rows.
struct IconBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 30
    var filled = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(filled ? Color.white : color)
            .frame(width: size, height: size)
            .background(filled ? color : color.opacity(0.13), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// A small colored label, e.g. "running" or "live".
struct StatusBadge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption2.weight(.semibold)).foregroundStyle(.white)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
