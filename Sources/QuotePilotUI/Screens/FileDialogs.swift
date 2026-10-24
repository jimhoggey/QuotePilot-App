import QuotePilotCore
import SwiftUI

/// What came in from Invoice Generator, and anything to finish by hand.
struct ImportReportView: View {
    let model: AppModel
    let report: ImportReport

    var body: some View {
        DialogPanel(title: "Import from Invoice Generator", icon: .folder, width: 520) {
            VStack(alignment: .leading, spacing: 10) {
                Text(report.summary)
                    .fixedSize(horizontal: false, vertical: true)
                if !report.addedClients.isEmpty {
                    Text("New clients: \(report.addedClients.joined(separator: ", ")).")
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !report.notes.isEmpty {
                    Text("To finish by hand:").font(Win95.label)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(report.notes.enumerated()), id: \.offset) { _, note in
                                NoteBanner(note)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
                HStack {
                    Spacer()
                    Button("OK") { model.dialog = nil }
                        .buttonStyle(.win95Default)
                        .keyboardShortcut(.defaultAction)
                }
                // The lone OK is both the default and the way out, so Escape needs a home too (as in
                // MessageBoxView): a button has only one keyboard shortcut. In the background, so it
                // adds no height.
                .background {
                    Button("") { model.dialog = nil }
                        .keyboardShortcut(.cancelAction)
                        .opacity(0)
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                }
            }
            .font(Win95.body)
            .foregroundStyle(Win95.text)
        }
    }
}

/// Which financial year's payments to export.
struct TaxExportView: View {
    let model: AppModel
    @State private var year: FinancialYear?

    var body: some View {
        let years = model.taxYears
        DialogPanel(title: "Export Payments for Tax Time", icon: .payment) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Quote Pilot saves a spreadsheet (CSV) of every payment received in the year: date, client, invoice, amount, method and note.")
                    .fixedSize(horizontal: false, vertical: true)
                Win95RadioGroup(selection: Binding(get: { year ?? years.first }, set: { year = $0 }),
                                options: years.map { (Optional($0), $0.label) })
                HStack(spacing: 8) {
                    Spacer()
                    Button("Export…") {
                        if let chosen = year ?? years.first { model.exportPayments(for: chosen) }
                    }
                    .buttonStyle(.win95Default)
                    .keyboardShortcut(.defaultAction)
                    Button("Cancel") { model.dialog = nil }
                        .buttonStyle(.win95)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .font(Win95.body)
            .foregroundStyle(Win95.text)
        }
    }
}

/// File → Start Fresh…, in one dialog: what it removes, what it keeps, the backup it makes first, and
/// a tick box for the clients. Cancel is the default button, as for anything that removes work.
struct StartFreshView: View {
    let model: AppModel
    @State private var removeClients = false

    /// What the dialog says.
    static let text = "Start Fresh removes every quote, invoice, payment and expense, and the Activity list. Numbering starts again at Q-0001 and INV-0001. Brand settings are kept.\n\nQuote Pilot backs up the library first, so File → Restore Backup… can bring it all back."

    var body: some View {
        DialogPanel(title: "Start Fresh", icon: .folder, width: 460) {
            VStack(alignment: .leading, spacing: 12) {
                Text(Self.text)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Also remove clients", isOn: $removeClients)
                    .toggleStyle(.win95)
                HStack(spacing: 8) {
                    Spacer()
                    Button("Start Fresh") { model.startFresh(removingClients: removeClients) }
                        .buttonStyle(.win95)
                    Button("Cancel") { model.dialog = nil }
                        .buttonStyle(.win95Default)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .font(Win95.body)
            .foregroundStyle(Win95.text)
        }
    }
}

/// The daily backups, newest first; restore one. It restores straight away, with no question: the
/// text says the library it replaces is kept beside it, and the status bar says what came back.
struct RestoreView: View {
    let model: AppModel
    @State private var selection: URL?

    var body: some View {
        let backups = model.store.backups()
        DialogPanel(title: "Restore Backup", icon: .folder, width: 480) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Quote Pilot backs up the library once a day and keeps the last 30. Restoring replaces the library with the one you choose; the current one is kept beside it.")
                    .fixedSize(horizontal: false, vertical: true)
                DetailsList(backups, id: \.self, columns: [
                    .text("Backup", width: .flexible(min: 160)) { AppModel.backupLabel($0) },
                ], selection: $selection, emptyText: "No backups yet.")
                    .frame(height: 220)
                HStack(spacing: 8) {
                    Spacer()
                    Button("Restore") { if let selection { model.restore(from: selection) } }
                        .buttonStyle(.win95Default)
                        .keyboardShortcut(.defaultAction)
                        .disabled(selection == nil)
                    Button("Cancel") { model.dialog = nil }
                        .buttonStyle(.win95)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .font(Win95.body)
            .foregroundStyle(Win95.text)
        }
    }
}
