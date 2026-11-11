import SwiftUI

/// One stale app. Clicking anywhere on the row selects it.
struct AppRow: View {
    let app: StaleApp
    @Binding var isSelected: Bool
    let model: RegistrationModel

    @State private var isHovered = false

    var body: some View {
        Button {
            isSelected.toggle()
        } label: {
            HStack(spacing: 14) {
                icon
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(app.name)
                            .font(.body.weight(.semibold))
                        if let version = app.version {
                            Text(version)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(app.path)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !details.isEmpty {
                        Text(details)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 12)
                SelectionMark(isOn: isSelected)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.white.opacity(isHovered ? 0.06 : 0), in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(app.path)
        .contextMenu {
            if app.mayExist {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
                }
            }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(app.path, forType: .string)
            }
            if canMoveToTrash {
                Divider()
                Button("Move to Trash and Unregister") {
                    Task { await model.moveToTrash(app) }
                }
            }
        }
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    @ViewBuilder
    private var icon: some View {
        if app.mayExist {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
        } else {
            // Nothing is left on disk to take an icon from.
            Image(systemName: "app.dashed")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
        }
    }

    private var details: String {
        var parts: [String] = []
        if let identifier = app.identifier { parts.append(identifier) }
        if app.helperCount > 0 {
            parts.append(String(localized: "\(app.helperCount) helper apps"))
        }
        if let registered = app.registered {
            parts.append(String(localized: "registered \(registered.formatted(date: .abbreviated, time: .omitted))"))
        }
        return parts.joined(separator: " · ")
    }

    /// Copies that would only be registered again; apps in the Trash or on another volume are left where they are.
    private var canMoveToTrash: Bool {
        app.mayExist && [.temporary, .buildOutput, .duplicate].contains(app.issue)
    }
}
