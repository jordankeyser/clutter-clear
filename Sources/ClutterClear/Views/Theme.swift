import SwiftUI

/// Shared look: brand gradient, avatars, cards and buttons.
enum Brand {
    // Matches the app icon: navy and indigo through electric blue.
    static let indigo = Color(red: 0.20, green: 0.26, blue: 0.82)
    static let accent = Color(red: 0.25, green: 0.50, blue: 1.00)
    static let violet = Color(red: 0.38, green: 0.36, blue: 0.95)
    static let gradient = LinearGradient(colors: [indigo, accent], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let keep = Color(red: 0.18, green: 0.74, blue: 0.47)
    static let remove = Color(red: 0.95, green: 0.30, blue: 0.35)
}

extension Category {
    var color: Color {
        switch self {
        case .promotional: return .blue
        case .repetitive: return .purple
        case .suspicious: return .red
        }
    }
    var icon: String {
        switch self {
        case .promotional: return "megaphone.fill"
        case .repetitive: return "repeat"
        case .suspicious: return "exclamationmark.shield.fill"
        }
    }
}

extension Candidate {
    var methodShort: (icon: String, text: String) {
        if oneClick && !unsubscribeWeb.isEmpty { return ("bolt.fill", "One-click") }
        if !unsubscribeMailto.isEmpty { return ("paperplane.fill", "By email") }
        if !unsubscribeWeb.isEmpty { return ("safari.fill", "Web page") }
        return ("magnifyingglass", "Link in email")
    }
    var latestSubject: String { flagged.max(by: { $0.date < $1.date })?.subject ?? senderEmail }
}

/// A colorful monogram generated from the sender's address.
struct SenderAvatar: View {
    let name: String
    let email: String
    var size: CGFloat = 36

    private var hue: Double {
        let sum = email.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Double(sum % 360) / 360
    }
    private var initial: String {
        let source = name.trimmingCharacters(in: .whitespaces).isEmpty ? email : name
        return source.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 0.95),
                                                  Color(hue: hue + 0.08, saturation: 0.75, brightness: 0.75)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(initial)
                .font(.system(size: size * 0.44, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(hue: hue, saturation: 0.6, brightness: 0.6).opacity(0.25), radius: size * 0.08, y: size * 0.04)
    }
}

struct CategoryPill: View {
    let category: Category
    var body: some View {
        Label(category.label, systemImage: category.icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(category.color.opacity(0.14), in: Capsule())
            .foregroundStyle(category.color)
    }
}

/// Rounded surface used for cards and panels.
struct Surface: ViewModifier {
    var radius: CGFloat = 16
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.background, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.separator.opacity(0.6), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

extension View {
    func surface(radius: CGFloat = 16, padding: CGFloat = 16) -> some View { modifier(Surface(radius: radius, padding: padding)) }
}

/// Large rounded action button with a colored fill.
struct PillButtonStyle: ButtonStyle {
    var tint: Color
    var prominent = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 18)
            .frame(minHeight: 40)
            .foregroundStyle(prominent ? Color.white : tint)
            .background(
                Capsule().fill(prominent ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.13)))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Round icon button used under the card deck.
struct RoundActionButton: View {
    let icon: String
    let label: String
    let tint: Color
    var size: CGFloat = 64
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: size, height: size)
                    .background(Circle().fill(.background))
                    .overlay(Circle().strokeBorder(tint.opacity(0.35), lineWidth: 1.5))
                    .shadow(color: tint.opacity(0.25), radius: 10, y: 4)
                Text(label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(PressScaleStyle())
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Small rounded stat tile.
struct StatTile: View {
    let icon: String
    let value: String
    let label: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.callout.weight(.semibold)).lineLimit(1)
                Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Chooses what happens to a sender's emails. Shown as tappable chips.
struct CleanupPicker: View {
    let options: [DeleteScope]
    @Binding var selection: DeleteScope
    var junk = false

    private func title(_ s: DeleteScope) -> String {
        switch s {
        case .flagged: return junk ? "Junk flagged" : "Delete flagged"
        case .allFromSender: return junk ? "Junk all from them" : "Delete all from them"
        case .none: return "Keep emails"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options) { opt in
                let on = opt == selection
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = opt }
                } label: {
                    Label(title(opt), systemImage: on ? "checkmark.circle.fill" : opt.icon)
                        .font(.callout.weight(on ? .semibold : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .background(Capsule().fill(on ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(.quaternary.opacity(0.6))))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Friendly full-pane message.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let detail: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(Brand.gradient)
                .symbolRenderingMode(.hierarchical)
            Text(title).font(.title2.weight(.semibold))
            if !detail.isEmpty {
                Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(PillButtonStyle(tint: Brand.accent))
                    .padding(.top, 4)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
