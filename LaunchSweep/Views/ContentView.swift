import SwiftUI

/// The window: a centered screen while scanning or when there is nothing to show, otherwise the stale apps
/// grouped by issue, with the action bar floating at the bottom.
struct ContentView: View {
    @State private var model = RegistrationModel()

    var body: some View {
        ZStack {
            Backdrop(mood: mood)
            content
        }
        .overlay(alignment: .top) { topBar }
        .ignoresSafeArea()
        .frame(minWidth: 640, minHeight: 480)
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.5), value: mood)
        .task { await model.scan() }
    }

    private var mood: Mood {
        switch model.phase {
        case .failed: .failed
        case .scanning where model.apps.isEmpty: .scanning
        default: model.apps.isEmpty ? .clean : .stale
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .failed(let message):
            Hero(motif: .failed, title: "Scan Failed", message: Text(verbatim: message), onScan: scan)
        case .scanning where model.apps.isEmpty:
            Hero(motif: .scanning, title: "Scanning registered apps…")
        case .loaded where model.apps.isEmpty:
            Hero(
                motif: .clean,
                title: "Nothing to Clean Up",
                message: Text("Every app registered with macOS is still on disk and in a usual place."),
                notice: model.notice,
                onScan: scan
            )
        default:
            results
        }
    }

    // MARK: Top bar

    /// Sits below the title bar strip, which stays free for the window buttons and for dragging.
    private var topBar: some View {
        HStack {
            Color.clear.frame(width: 32, height: 32)
            Spacer()
            HStack(spacing: 7) {
                ListMotif(state: .icon)
                    .frame(width: 20, height: 20)
                Text("LaunchSweep")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
            }
            .padding(.leading, 9)
            .padding(.trailing, 13)
            .padding(.vertical, 6)
            .background(.white.opacity(0.08), in: Capsule())
            Spacer()
            Button(action: scan) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(CircleButtonStyle())
            .keyboardShortcut("r")
            .help("Scan the Launch Services database again")
            .accessibilityLabel("Scan Again")
            .disabled(model.isBusy)
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
    }

    // MARK: Results

    private var results: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                summary
                ForEach(Issue.allCases, id: \.self) { issue in
                    let apps = model.apps.filter { $0.issue == issue }
                    if !apps.isEmpty {
                        header(for: issue, apps: apps, isOnlySection: apps.count == model.apps.count)
                        ForEach(apps) { app in
                            AppRow(app: app, isSelected: isSelected(app), model: model)
                                .padding(.horizontal, -12)
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 84)
            .padding(.bottom, 104)
            .disabled(model.isBusy)
            .opacity(model.isWorking ? 0.5 : 1)
        }
        // Rows fade out under the top bar instead of running into it.
        .mask {
            VStack(spacing: 0) {
                LinearGradient(stops: [.init(color: .clear, location: 0.6), .init(color: .black, location: 1)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 78)
                Color.black
            }
        }
        .overlay(alignment: .bottom) { actionBar }
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: model.apps.count.formatted())
                .font(.system(size: 52, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            // Two separate texts, not plural variations: those must contain the number, which is shown apart.
            Text(
                model.apps.count == 1
                    ? String(localized: "Stale Registration")
                    : String(localized: "Stale Registrations")
            )
                .font(.system(.title3, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func header(for issue: Issue, apps: [StaleApp], isOnlySection: Bool) -> some View {
        let paths = Set(apps.map(\.path))
        let allSelected = paths.isSubset(of: model.selection)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: issue.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text(issue.title)
                    .font(.headline)
                Text(verbatim: apps.count.formatted())
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                // With a single section, the action bar's button already does this.
                if !isOnlySection {
                    Button {
                        if allSelected { model.selection.subtract(paths) } else { model.selection.formUnion(paths) }
                    } label: {
                        selectAllLabel(allSelected: allSelected)
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }
            Text(issue.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 28)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func selectAllLabel(allSelected: Bool) -> some View {
        if allSelected { Text("Deselect All") } else { Text("Select All") }
    }

    // MARK: Action bar

    private var actionBar: some View {
        HStack(spacing: 16) {
            if model.isBusy {
                ProgressView().controlSize(.small)
            }
            Text(status)
                .font(.callout)
                .foregroundStyle(model.notice == nil ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText())
            Button {
                model.selection = allSelected ? [] : Set(model.apps.map(\.path))
            } label: {
                selectAllLabel(allSelected: allSelected)
            }
            .buttonStyle(QuietButtonStyle())
            Button("Unregister") {
                Task { await model.unregisterSelected() }
            }
            .buttonStyle(PillButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(model.selection.isEmpty)
        }
        .disabled(model.isBusy)
        .padding(.leading, 22)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(.white.opacity(0.12)) }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .padding(.horizontal, 32)
        .padding(.bottom, 22)
        .animation(.snappy, value: model.selection.count)
    }

    private var allSelected: Bool { model.selection.count == model.apps.count }

    private var status: String {
        model.notice ?? String(localized: "\(model.selection.count) of \(model.apps.count) selected")
    }

    private func isSelected(_ app: StaleApp) -> Binding<Bool> {
        Binding {
            model.selection.contains(app.path)
        } set: { isSelected in
            if isSelected { model.selection.insert(app.path) } else { model.selection.remove(app.path) }
        }
    }

    private func scan() {
        Task { await model.scan() }
    }
}

/// The centered screen shown while scanning, when nothing is stale, and when the scan failed.
private struct Hero: View {
    var motif: ListMotif.State
    var title: LocalizedStringKey
    var message: Text?
    /// What the last action did.
    var notice: String?
    var onScan: (() -> Void)?

    var body: some View {
        VStack(spacing: 26) {
            ListMotif(state: motif)
                .frame(width: 148, height: 148)
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                if let message {
                    message
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                if let notice {
                    Text(notice)
                        .foregroundStyle(Theme.mint)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                        .padding(.top, 4)
                }
            }
            if let onScan {
                Button("Scan Again", action: onScan)
                    .buttonStyle(PillButtonStyle())
                    .padding(.top, 4)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
