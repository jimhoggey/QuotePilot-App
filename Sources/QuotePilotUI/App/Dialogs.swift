import QuotePilotCore
import SwiftUI

/// The dialog panels Quote Pilot draws over the window. Later tasks add cases.
public enum Dialog: Equatable {
    /// The client has no email yet: ask for it, then carry on sending `document`.
    case emailPrompt(clientID: UUID, document: MailDocument)
    /// Check what the client accepted, then confirm.
    case acceptance(AcceptanceReview)
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

/// Shows the current dialog over the window; the window behind can't be clicked meanwhile.
struct DialogOverlay: View {
    let model: AppModel
    let dialog: Dialog

    var body: some View {
        ZStack {
            Color.white.opacity(0.001)
            // A message box over the dialog owns Return and Escape, as the one on top of a Windows 95
            // dialog does: the dialog's own buttons wait until it's answered.
            content
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
