import AppKit
import QuotePilotCore
import SwiftUI

/// The whole window: title bar, toolbar, the section tree, the current section and the status bar,
/// or the unreadable-library screen. Message boxes sit on top.
public struct RootView: View {
    @Bindable var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            // The macOS window buttons sit over the left end of this bar.
            TitleBar(windowTitle, icon: titleIcon, height: 28, leadingInset: 72)
                .overlay(WindowDragArea())
            switch model.loadState {
            case .ready:
                // While a message box is up, nothing behind it takes a click, a Tab or a key.
                Win95Toolbar(model: model)
                    .disabled(boxIsUp)
                HStack(spacing: 4) {
                    SectionTree(model: model)
                        .frame(width: 190)
                        .disabled(boxIsUp)
                    sectionContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .disabled(boxIsUp)
                }
                .padding(4)
                StatusBar(model: model)
            case .unreadable(let reason):
                UnreadableLibraryView(model: model, reason: reason)
                    .disabled(boxIsUp)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 980, minHeight: 620)
        .background(Win95.face)
        .preferredColorScheme(.light)
        .overlay { messageOverlay }
        .fileExporter(isPresented: exporting, document: model.pendingExport.map { PDFFile(data: $0.data) },
                      contentType: .pdf, defaultFilename: model.pendingExport?.fileName) { result in
            model.finishExport(result)
        }
    }

    private var boxIsUp: Bool { model.message != nil || model.dialog != nil }

    private var windowTitle: String {
        if case .unreadable = model.loadState { return "Quote Pilot" }
        return "Quote Pilot - \(model.section.title)"
    }

    private var titleIcon: PixelIcon {
        if case .unreadable = model.loadState { return .warning }
        return model.section.icon
    }

    private var exporting: Binding<Bool> {
        Binding(get: { model.pendingExport != nil }, set: { if !$0 { model.pendingExport = nil } })
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch model.section {
        case .dashboard: DashboardView(model: model)
        case .quotes: QuotesView(model: model)
        case .invoices: InvoicesView(model: model)
        case .clients: ClientsView(model: model)
        case .activity: ActivityView(model: model)
        case .brand: BrandView(model: model)
        }
    }

    /// The dialog, if one is open, with any message box above it.
    @ViewBuilder
    private var messageOverlay: some View {
        ZStack {
            if let dialog = model.dialog {
                DialogOverlay(model: model, dialog: dialog)
            }
            if let box = model.message {
                ZStack {
                    // As with a Windows 95 message box, the window behind stays visible but can't be clicked.
                    Color.white.opacity(0.001)
                    MessageBoxView(box: box) { model.respond($0) }
                }
            }
        }
    }
}

/// The toolbar: square buttons with a pixel icon over a short label. Buttons for plan 2b's work
/// are there but off, so the toolbar's shape doesn't change later.
struct Win95Toolbar: View {
    let model: AppModel
    private let later = "Arrives in the next build"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                tool("New Quote", .quote, help: "Start a new quote (⌘N)") { model.newQuote() }
                tool("New Invoice", .invoice, help: later, enabled: false) {}
                ToolbarSeparator()
                tool("Send", .mail, help: "Open a Mail draft of the open quote or invoice (⌘S)",
                     enabled: model.sendableDocument != nil) {
                    if let document = model.sendableDocument { model.send(document) }
                }
                tool("Read Reply", .folder, help: later, enabled: false) {}
                tool("Payment", .payment, help: later, enabled: false) {}
                ToolbarSeparator()
                tool("Save PDF", .pdf, help: "Save the open quote or invoice as a PDF (⌘P)",
                     enabled: model.canExportPDF) { model.exportPDF() }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            EtchedLine()
        }
        .background(Win95.face)
    }

    private func tool(_ title: String, _ icon: PixelIcon, help: String, enabled: Bool = true,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                PixelIconView(icon, size: 32)
                Text(title)
            }
        }
        .buttonStyle(Win95ToolbarButtonStyle())
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(title)
        .accessibilityHint(help)
    }
}

struct ToolbarSeparator: View {
    var body: some View {
        HStack(spacing: 0) {
            Win95.shadow.frame(width: 1)
            Win95.highlight.frame(width: 1)
        }
        .frame(height: 50)
        .padding(.horizontal, 4)
        .accessibilityHidden(true)
    }
}

/// The Explorer-style tree on the left: the business at the top, the six sections under it.
struct SectionTree: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                PixelIconView(.folder)
                Text(model.library.brand.businessName.isEmpty ? "Quote Pilot" : model.library.brand.businessName)
                    .font(Win95.label)
                    .foregroundStyle(Win95.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 4)
            .frame(height: 22)
            ForEach(AppSection.allCases) { section in
                row(section, isLast: section == AppSection.allCases.last)
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Win95.field)
        .overlay(Bevel(.sunken))
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.upArrow) { step(-1) }
        .onKeyPress(.downArrow) { step(1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sections")
    }

    private func row(_ section: AppSection, isLast: Bool) -> some View {
        let selected = model.section == section
        return HStack(spacing: 4) {
            TreeConnector(isLast: isLast)
                .frame(width: 16, height: 22)
            PixelIconView(section.icon)
            Text(section.title)
                .font(Win95.body)
                .foregroundStyle(selected ? Win95.highlight : Win95.text)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(selected ? Win95.selection : Color.clear)
                .overlay(selected && focused ? FocusRect() : nil)
            Spacer(minLength: 0)
        }
        .padding(.leading, 10)
        .frame(height: 22)
        .contentShape(Rectangle())
        .onTapGesture {
            model.go(to: section)
            focused = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.go(to: section) }
    }

    private func step(_ delta: Int) -> KeyPress.Result {
        // A message box or dialog owns the keyboard; the tree is disabled behind it, this is a second guard.
        guard model.message == nil, model.dialog == nil else { return .ignored }
        let all = AppSection.allCases
        let index = all.firstIndex(of: model.section) ?? 0
        model.go(to: all[min(max(index + delta, 0), all.count - 1)])
        return .handled
    }
}

/// Explorer's dotted tree lines.
struct TreeConnector: View {
    let isLast: Bool

    var body: some View {
        Canvas { context, size in
            let x = (size.width / 2).rounded(.down) + 0.5
            let middle = (size.height / 2).rounded(.down) + 0.5
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: isLast ? middle : size.height))
            path.move(to: CGPoint(x: x, y: middle))
            path.addLine(to: CGPoint(x: size.width, y: middle))
            context.stroke(path, with: .color(Win95.shadow), style: StrokeStyle(lineWidth: 1, dash: [1, 1]))
        }
        .accessibilityHidden(true)
    }
}

/// What the status bar says, on every screen.
enum StatusBarText {
    static func items(_ dashboard: Dashboard, lastSaved: Date?, currencyCode: String) -> [String] {
        let overdue = dashboard.waiting.filter { $0.daysLate > 0 }.count
        let saved = lastSaved.map {
            "Saved " + $0.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "en_AU")))
        }
        return [
            "Waiting: \(dashboard.waitingTotal.formatted(currencyCode: currencyCode))",
            overdue == 1 ? "1 invoice overdue" : "\(overdue) invoices overdue",
            "Received \(dashboard.financialYear.label): \(dashboard.receivedThisYear.formatted(currencyCode: currencyCode))",
            saved ?? "No changes yet",
        ]
    }
}

struct StatusBar: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(StatusBarText.items(model.dashboard, lastSaved: model.lastSaved, currencyCode: model.currencyCode),
                    id: \.self) { item in
                StatusPanel(item)
            }
        }
        .padding(2)
        .background(Win95.face)
    }
}

/// Shown instead of the app when the library file can't be read. Nothing is saved from here; the
/// only way on is restoring a backup.
struct UnreadableLibraryView: View {
    let model: AppModel
    let reason: String

    var body: some View {
        ZStack {
            Win95.desktop
            VStack(spacing: 0) {
                TitleBar("Quote Pilot", icon: .warning)
                    .padding(2)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 14) {
                        PixelIconView(.warning, size: 32)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quote Pilot can't open your library.")
                                .font(Win95.label)
                            Text(reason)
                            Text("The file has been left exactly as it is, and Quote Pilot won't save over it.")
                            Text(model.store.libraryURL.path)
                                .font(Win95.small.monospaced())
                                .textSelection(.enabled)
                            if let backup = model.latestBackup {
                                Text("The latest backup is \(backup.lastPathComponent).")
                            } else {
                                Text("There are no backups to restore.")
                            }
                        }
                        .font(Win95.body)
                        .foregroundStyle(Win95.text)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        Spacer()
                        Button("Restore Latest Backup") { model.restoreLatestBackup() }
                            .buttonStyle(.win95Default)
                            .keyboardShortcut(.defaultAction)
                            .disabled(model.latestBackup == nil)
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([model.store.libraryURL])
                        }
                        .buttonStyle(.win95)
                        Button("Quit") { NSApp.terminate(nil) }
                            .buttonStyle(.win95)
                    }
                }
                .padding(16)
            }
            .frame(width: 560)
            .background(Win95.face)
            .overlay(Bevel(.raised))
        }
    }
}
