import SwiftUI

/// The app icon drawn live: a list of three apps whose rows show what LaunchSweep is doing.
struct ListMotif: View {
    enum State {
        /// The app icon as it is: the middle row faded, with the badge that removes it.
        case icon
        /// The rows light up in turn.
        case scanning
        /// Every row is solid, with a check mark.
        case clean
        /// The middle row is faded, with a warning.
        case failed
    }

    var state: State

    /// The icon is drawn on an 824-point square, like design/logo.
    private let grid: CGFloat = 824
    private let rows: [(y: CGFloat, width: CGFloat)] = [(162, 364), (352, 190), (542, 300)]

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width, geometry.size.height) / grid
            TimelineView(.animation(paused: state != .scanning)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 185 * scale, style: .continuous)
                        .fill(LinearGradient(
                            colors: [Theme.accent, Theme.accentDeep], startPoint: .top, endPoint: .bottom
                        ))
                        .shadow(color: Theme.accent.opacity(0.45), radius: 155 * scale, y: 66 * scale)
                    ForEach(rows.indices, id: \.self) { index in
                        row(rows[index], scale: scale)
                            .opacity(opacity(ofRow: index, at: time))
                    }
                    if let badge {
                        Image(systemName: badge.symbol)
                            .font(.system(size: 88 * scale, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 168 * scale, height: 168 * scale)
                            .background(badge.color, in: Circle())
                            .shadow(color: .black.opacity(0.3), radius: 10 * scale, y: 8 * scale)
                            .offset(x: 520 * scale, y: 328 * scale)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: grid * scale, height: grid * scale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func row(_ row: (y: CGFloat, width: CGFloat), scale: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 30 * scale, style: .continuous)
                .frame(width: 120 * scale, height: 120 * scale)
                .offset(x: 150 * scale, y: row.y * scale)
            Capsule()
                .frame(width: row.width * scale, height: 44 * scale)
                .offset(x: 310 * scale, y: (row.y + 38) * scale)
        }
        .foregroundStyle(.white)
    }

    private func opacity(ofRow index: Int, at time: TimeInterval) -> Double {
        switch state {
        case .scanning:
            // One row after another, a full pass every 1.5 seconds.
            let phase = (time / 1.5 - Double(index) / 3) * 2 * .pi
            return 0.3 + 0.7 * pow(max(0, cos(phase)), 2)
        case .clean:
            return 1
        case .icon, .failed:
            return index == 1 ? 0.4 : 1
        }
    }

    private var badge: (symbol: String, color: Color)? {
        switch state {
        case .scanning: nil
        case .icon: ("minus", Theme.coral)
        case .clean: ("checkmark", Theme.mint)
        case .failed: ("exclamationmark", Theme.amber)
        }
    }
}
