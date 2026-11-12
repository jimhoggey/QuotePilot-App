import CoreGraphics

/// The five-step tour: the Pilot points at one thing a step and says a line or two about it. It only
/// moves between sections, so nothing in the library changes. A step whose section isn't showing asks
/// for it to be clicked first; Next clicks it for them (the user, 12 Nov 2026: short, optional,
/// interactive, never annoying).
public struct Tour: Equatable, Sendable {
    /// What a step points at. Each is marked on its view with `tourTarget(_:)`.
    public enum Target: Hashable, Sendable {
        case section(AppSection), totals, newQuote, readReply, invoiceList, content
    }

    /// Where the Pilot and the balloon go around the target.
    public enum Placement: Sendable {
        /// To its right, level with it: the section tree's rows.
        case beside
        /// Under it, from its left edge: the toolbar and the Dashboard's totals.
        case below
        /// In its middle: a list or a whole section.
        case center
    }

    public struct Step: Equatable, Sendable {
        public let section: AppSection
        public let target: Target
        public let placement: Placement
        public let text: String
    }

    public static let steps: [Step] = [
        Step(section: .dashboard, target: .totals, placement: .below,
             text: "Welcome aboard! These four boxes are your money, left to right: quoted, still to invoice, waiting to be paid and received."),
        Step(section: .quotes, target: .newQuote, placement: .below,
             text: "New Quote starts one. Your client ticks the lines they want on the PDF you send, and sends it back."),
        Step(section: .quotes, target: .readReply, placement: .below,
             text: "When their PDF comes back, drop it anywhere on this window, or press Read Reply. Quote Pilot reads their ticks."),
        Step(section: .invoices, target: .invoiceList, placement: .center,
             text: "Press Record Payment on an invoice when they pay. To email several receipts at once, ⌘-click paid invoices, then right-click."),
        Step(section: .brand, target: .content, placement: .center,
             text: "Your logo, details and email wording live here. That's the tour. Happy quoting!"),
    ]

    public private(set) var index = 0

    public init() {}

    public var step: Step { Self.steps[index] }
    public var isLast: Bool { index == Self.steps.count - 1 }
    /// "2 of 5"
    public var count: String { "\(index + 1) of \(Self.steps.count)" }

    /// The next step; nil after the last.
    func advanced() -> Tour? {
        guard !isLast else { return nil }
        var next = self
        next.index += 1
        return next
    }

    /// What the balloon says and points at with `showing` on screen: the step itself, or, while its
    /// section isn't showing, a prompt to click that section in the tree.
    public func shown(in showing: AppSection) -> (text: String, target: Target, placement: Placement) {
        guard showing == step.section else {
            return ("Click \(step.section.title) on the left.", .section(step.section), .beside)
        }
        return (step.text, step.target, step.placement)
    }

    /// The balloon's default button: Finish on the last step once Brand shows, Next otherwise.
    public func nextTitle(in showing: AppSection) -> String {
        isLast && showing == step.section ? "Finish" : "Next >"
    }

    // MARK: Layout

    static let pilotSize: CGFloat = 64
    static let balloonWidth: CGFloat = 300
    /// About a three-line balloon with its buttons: enough to keep the pair inside the window.
    static let balloonHeight: CGFloat = 120
    static let gap: CGFloat = 16
    static let margin: CGFloat = 8
    static var pairWidth: CGFloat { pilotSize + gap + balloonWidth }

    /// Where the Pilot-and-balloon pair goes: its centre, and whether the Pilot leads (on the left,
    /// facing the target) or trails the balloon. With no target, the window's middle. Always inside
    /// the window with `margin` to spare.
    static func pairCenter(around target: CGRect?, placement: Placement, in window: CGSize) -> (center: CGPoint, pilotLeads: Bool) {
        let half = CGSize(width: pairWidth / 2, height: balloonHeight / 2)
        var center: CGPoint
        var pilotLeads = true
        if let r = target {
            switch placement {
            case .beside:
                center = CGPoint(x: r.maxX + margin + half.width, y: r.midY)
            case .below:
                center = CGPoint(x: r.minX + half.width, y: r.maxY + margin + half.height)
            case .center:
                center = CGPoint(x: r.midX, y: r.midY)
                pilotLeads = false
            }
        } else {
            center = CGPoint(x: window.width / 2, y: window.height / 2)
            pilotLeads = false
        }
        center.x = min(max(center.x, margin + half.width), max(margin + half.width, window.width - margin - half.width))
        center.y = min(max(center.y, margin + half.height), max(margin + half.height, window.height - margin - half.height))
        return (center, pilotLeads)
    }
}
