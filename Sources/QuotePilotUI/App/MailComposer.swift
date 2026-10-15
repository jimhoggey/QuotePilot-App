import AppKit
import Foundation

/// Opens Mail drafts. Quote Pilot never sends anything: you press Send in Mail (spec §8).
public protocol MailComposer {
    /// Opens a new message with the PDF attached. False when the compose service isn't available.
    func compose(to: String, subject: String, body: String, attachment: URL) -> Bool
    /// When Mail can't open a draft: show the PDF in Finder and put the message on the clipboard.
    func setAside(message: String, attachment: URL)
}

/// macOS's own "compose email" share service.
public struct SystemMailComposer: MailComposer {
    public init() {}

    public func compose(to: String, subject: String, body: String, attachment: URL) -> Bool {
        guard let service = NSSharingService(named: .composeEmail) else { return false }
        service.recipients = to.isEmpty ? [] : [to]
        service.subject = subject
        let items: [Any] = [body as NSString, attachment as NSURL]
        guard service.canPerform(withItems: items) else { return false }
        service.perform(withItems: items)
        return true
    }

    public func setAside(message: String, attachment: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([attachment])
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message, forType: .string)
    }
}

/// A document that goes out by Mail.
public enum MailDocument: Equatable, Hashable {
    case quote(UUID)
    case invoice(UUID)
    case receipt(UUID)
}
