import QuotePilotCore
import SwiftUI

/// The dialog panels Quote Pilot draws over the window. Later tasks add cases.
public enum Dialog: Equatable {
    /// The client has no email yet: ask for it, then carry on sending `document`.
    case emailPrompt(clientID: UUID, document: MailDocument)
    /// Check what the client accepted, then confirm.
    case acceptance(AcceptanceReview)
    /// What an import brought in, and what to do by hand.
    case importReport(ImportReport)
    /// Choose the financial year for the payments CSV.
    case taxExport
    /// Choose a daily backup to restore.
    case restore
    /// File → Start Fresh…: what goes, what stays, and whether clients go too.
    case startFresh
}

/// A Windows 95 dialog: navy title bar, grey body, bevelled edge.
struct DialogPanel<Content: View>: View {
    let title: String
    let icon: PixelIcon
    let width: CGFloat
    let content: Content

    init(title: String, icon: PixelIcon, width: CGFloat = 440, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.width = width
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            TitleBar(title, icon: icon)
                .padding(2)
            content
                .padding(14)
        }
        .frame(width: width)
        .background(Win95.face)
        .overlay(Bevel(.raised))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel(title)
    }
}

/// A top-to-bottom stack in which one child, marked `takesLeftoverHeight()` (a scroll area), is as
/// tall as it wants to be but no taller than what the others leave of the height the stack is
/// offered. A dialog built on it grows with its window and scrolls only when the window has no more
/// room. Offered no height at all, the scroll area is as tall as its contents.
struct LeftoverHeightStack: Layout {
    var spacing: CGFloat = 10

    struct Flexible: LayoutValueKey {
        static let defaultValue = false
    }

    private func heights(width: CGFloat?, height: CGFloat?, _ subviews: Subviews) -> [CGFloat] {
        let ask = ProposedViewSize(width: width, height: nil)
        var heights = subviews.map { $0[Flexible.self] ? 0 : $0.sizeThatFits(ask).height }
        let used = heights.reduce(0, +) + spacing * CGFloat(max(subviews.count - 1, 0))
        for (index, subview) in subviews.enumerated() where subview[Flexible.self] {
            let wanted = subview.sizeThatFits(ask).height
            heights[index] = height.map { min(wanted, max(0, $0 - used)) } ?? wanted
        }
        return heights
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ask = ProposedViewSize(width: proposal.width, height: nil)
        let width = proposal.width ?? subviews.map { $0.sizeThatFits(ask).width }.max() ?? 0
        let heights = heights(width: proposal.width, height: proposal.height, subviews)
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(subviews.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let heights = heights(width: bounds.width, height: bounds.height, subviews)
        var y = bounds.minY
        for (subview, height) in zip(subviews, heights) {
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: height))
            y += height + spacing
        }
    }
}

extension View {
    /// Marks the one child of a `LeftoverHeightStack` that gives way when the stack runs out of height.
    func takesLeftoverHeight() -> some View {
        layoutValue(key: LeftoverHeightStack.Flexible.self, value: true)
    }
}

/// Shows the current dialog over the window; the window behind can't be clicked meanwhile.
struct DialogOverlay: View {
    let model: AppModel
    let dialog: Dialog

    /// The gap kept above and below a dialog, so that one as tall as its window allows still sits
    /// inside it.
    static let verticalMargin: CGFloat = 30

    var body: some View {
        ZStack {
            Color.white.opacity(0.001)
            // A message box over the dialog owns Return and Escape, as the one on top of a Windows 95
            // dialog does: the dialog's own buttons wait until it's answered.
            content
                .padding(.vertical, Self.verticalMargin)
                .disabled(model.message != nil)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch dialog {
        case .emailPrompt(let clientID, let document):
            EmailPromptView(model: model, clientID: clientID, document: document)
        case .acceptance(let review):
            AcceptanceReviewView(model: model, review: review)
        case .importReport(let report):
            ImportReportView(model: model, report: report)
        case .taxExport:
            TaxExportView(model: model)
        case .restore:
            RestoreView(model: model)
        case .startFresh:
            StartFreshView(model: model)
        }
    }
}

/// "Quote Pilot needs this client's email address."
struct EmailPromptView: View {
    let model: AppModel
    let clientID: UUID
    let document: MailDocument
    @State private var email = ""

    var body: some View {
        let name = model.library.client(clientID)?.name ?? "this client"
        DialogPanel(title: "Client's Email", icon: .mail) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Quote Pilot needs \(name)'s email address to start the Mail draft. It's saved to the client for next time.")
                    .font(Win95.body)
                    .foregroundStyle(Win95.text)
                    .fixedSize(horizontal: false, vertical: true)
                Win95FieldRow("Email:", labelWidth: 50) {
                    Win95TextField("Email", text: $email, prompt: "name@example.com")
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button("Save and Continue") {
                        model.saveEmailAndSend(email, clientID: clientID, document: document)
                    }
                    .buttonStyle(.win95Default)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!AppModel.looksLikeEmail(email.trimmingCharacters(in: .whitespacesAndNewlines)))
                    Button("Cancel") { model.dialog = nil }
                        .buttonStyle(.win95)
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
    }
}
