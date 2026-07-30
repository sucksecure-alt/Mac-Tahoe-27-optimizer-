import SwiftUI

enum MFTheme {
    static let accent     = Color(red: 0.45, green: 0.72, blue: 0.95)
    static let accentSoft = Color(red: 0.62, green: 0.83, blue: 1.00)
    static let accentDeep = Color(red: 0.30, green: 0.55, blue: 0.85)
    static let frost      = Color(red: 0.96, green: 0.98, blue: 1.00)
    static let success    = Color(red: 0.40, green: 0.80, blue: 0.60)
    static let warning    = Color(red: 0.95, green: 0.75, blue: 0.40)
    static let danger     = Color(red: 0.90, green: 0.45, blue: 0.45)
    static let lavender   = Color(red: 0.65, green: 0.58, blue: 0.90)
    static let mint       = Color(red: 0.45, green: 0.82, blue: 0.75)

    static var heroGradient: LinearGradient {
        LinearGradient(colors: [
            Color(red: 0.91, green: 0.96, blue: 1.00),
            Color(red: 0.82, green: 0.92, blue: 1.00),
            Color(red: 0.94, green: 0.97, blue: 1.00)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentSoft, accent, accentDeep],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var successGradient: LinearGradient {
        LinearGradient(colors: [Color(red: 0.55, green: 0.88, blue: 0.68), success],
                       startPoint: .top, endPoint: .bottom)
    }

    static var warmGradient: LinearGradient {
        LinearGradient(colors: [
            Color(red: 0.98, green: 0.82, blue: 0.50),
            Color(red: 0.92, green: 0.60, blue: 0.30)
        ], startPoint: .top, endPoint: .bottom)
    }

    static var lavenderGradient: LinearGradient {
        LinearGradient(colors: [
            Color(red: 0.75, green: 0.68, blue: 0.95),
            Color(red: 0.55, green: 0.48, blue: 0.85)
        ], startPoint: .top, endPoint: .bottom)
    }

    static var cardShadow: Color {
        Color(red: 0.35, green: 0.55, blue: 0.85).opacity(0.05)
    }

    static var softShadow: Color {
        Color.black.opacity(0.02)
    }
}

struct MFCard: ViewModifier {
    var pad: CGFloat = 16
    var radius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(pad)
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(.white.opacity(0.88))
                    .shadow(color: MFTheme.cardShadow, radius: 8, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(MFTheme.accent.opacity(0.10), lineWidth: 1)
            )
    }
}

extension View {
    func mfCard(_ pad: CGFloat = 16, _ radius: CGFloat = 16) -> some View {
        modifier(MFCard(pad: pad, radius: radius))
    }
}

struct MFSectionHeader: View {
    let title: String
    let icon: String
    var sub: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(MFTheme.accent)
                Text(title)
                    .font(.headline)
            }
            if let sub {
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct RiskBadge: View {
    let level: Int

    var body: some View {
        let (text, r, g, b): (String, Double, Double, Double) = level == 0
            ? ("Безопасно", 0.40, 0.80, 0.60)
            : level == 1
                ? ("Умеренно", 0.95, 0.75, 0.40)
                : ("Осторожно", 0.90, 0.45, 0.45)

        Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(red: r, green: g, blue: b).opacity(0.10), in: Capsule())
            .foregroundStyle(Color(red: r, green: g, blue: b))
    }
}

struct ImpactDots: View {
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(i < count ? MFTheme.warning : Color.gray.opacity(0.15))
                    .frame(width: 5, height: 5)
            }
        }
    }
}

struct LegendDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).foregroundStyle(.secondary)
        }
    }
}
