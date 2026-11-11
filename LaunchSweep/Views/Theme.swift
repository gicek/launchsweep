import SwiftUI

/// The window's colors. LaunchSweep is always dark: an ink background tinted by what the scan found.
enum Theme {
    static let ink = Color(red: 0.05, green: 0.06, blue: 0.13)
    /// The blue of the app icon.
    static let accent = Color(red: 0.36, green: 0.55, blue: 0.96)
    static let accentDeep = Color(red: 0.17, green: 0.25, blue: 0.65)
    /// The red of the app icon's badge; marks what will be unregistered.
    static let coral = Color(red: 0.97, green: 0.38, blue: 0.32)
    static let mint = Color(red: 0.32, green: 0.82, blue: 0.66)
    static let amber = Color(red: 0.93, green: 0.66, blue: 0.26)
}

/// What the window is showing, which sets the tint of the background.
enum Mood: Equatable {
    case scanning
    case stale
    case clean
    case failed

    var tint: Color {
        switch self {
        case .scanning: Theme.accent
        case .stale: Color(red: 0.80, green: 0.30, blue: 0.40)
        case .clean: Color(red: 0.18, green: 0.62, blue: 0.60)
        case .failed: Color(red: 0.78, green: 0.52, blue: 0.20)
        }
    }
}

/// The window's background: ink, with the mood's tint glowing from the top.
struct Backdrop: View {
    var mood: Mood

    var body: some View {
        ZStack {
            Theme.ink
            LinearGradient(
                colors: [mood.tint.opacity(0.34), mood.tint.opacity(0.04)], startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [mood.tint.opacity(0.30), mood.tint.opacity(0)],
                center: UnitPoint(x: 0.5, y: -0.15),
                startRadius: 0,
                endRadius: 640
            )
        }
    }
}

/// The main action: a white capsule.
struct PillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 22)
            .padding(.vertical, 9)
            .background(.white, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.3)
            .contentShape(Capsule())
    }
}

/// A round button that holds a symbol.
struct CircleButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(isEnabled ? 0.9 : 0.35))
            .frame(width: 32, height: 32)
            .background(.white.opacity(configuration.isPressed ? 0.2 : 0.1), in: Circle())
            .contentShape(Circle())
    }
}

/// A quiet text button, for secondary actions such as selecting everything.
struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.white.opacity(isEnabled ? (configuration.isPressed ? 0.5 : 0.7) : 0.3))
            .contentShape(Rectangle())
    }
}

/// The round mark at the end of a row: filled when the app will be unregistered.
struct SelectionMark: View {
    var isOn: Bool

    var body: some View {
        ZStack {
            if isOn {
                Circle().fill(Theme.coral)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1.5)
            }
        }
        .frame(width: 22, height: 22)
    }
}

extension Issue {
    var symbol: String {
        switch self {
        case .missing: "questionmark.app.dashed"
        case .trash: "trash"
        case .temporary: "clock.arrow.circlepath"
        case .buildOutput: "hammer"
        case .volume: "externaldrive"
        case .duplicate: "square.on.square"
        }
    }
}
