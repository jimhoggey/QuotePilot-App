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
    /// The Quote Pilot fee's lock: choosing its password, or typing it to change the fee's settings.
    case feePassword(FeePasswordStep)
}

public enum FeePasswordStep: Equatable {
    case choose, unlock
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
        case .feePassword(let step):
            FeePasswordView(model: model, step: step)
        }
    }
}

/// Choosing the Quote Pilot fee's password (typed twice, so a slip can't lock you out), or typing it
/// to change the fee's settings. A wrong one says so here, with no second box.
struct FeePasswordView: View {
    let model: AppModel
    let step: FeePasswordStep
    @State private var password = ""
    @State private var again = ""
    @State private var wrong = false

    private var ready: Bool { !password.isEmpty && (step == .unlock || password == again) }

    var body: some View {
        DialogPanel(title: step == .choose ? "Lock the Quote Pilot Fee" : "Unlock the Quote Pilot Fee", icon: .lock) {
            VStack(alignment: .leading, spacing: 12) {
                Text(step == .choose
                     ? "Choose a password. After that, the fee's settings (the tick, the percentage, the first name and the email) can only be changed once it's typed. Quote Pilot keeps a scrambled fingerprint of it, never the password itself."
                     : "Type the password to change the fee's settings. They lock again when you leave Settings.")
                    .fixedSize(horizontal: false, vertical: true)
                Win95FieldRow("Password:", labelWidth: 70) {
                    Win95TextField("Password", text: $password, secure: true)
                }
                if step == .choose {
                    Win95FieldRow("Again:", labelWidth: 70) {
                        Win95TextField("Password again", text: $again, secure: true)
                    }
                    if !again.isEmpty, again != password {
                        Text("The two passwords don't match yet.")
                            .font(Win95.small)
                    }
                }
                if wrong {
                    Text("That's not the password.")
                        .foregroundStyle(Win95.overdue)
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button(step == .choose ? "Lock" : "Unlock") { submit() }
                        .buttonStyle(.win95Default)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!ready)
                    Button("Cancel") { model.dialog = nil }
                        .buttonStyle(.win95)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .font(Win95.body)
            .foregroundStyle(Win95.text)
        }
    }

    private func submit() {
        switch step {
        case .choose:
            model.lockFeeSettings(password: password)
        case .unlock:
            wrong = !model.unlockFeeSettings(password: password)
            if wrong { password = "" }
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
