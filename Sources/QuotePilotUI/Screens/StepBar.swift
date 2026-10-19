import QuotePilotCore
import SwiftUI

/// The two switches for the learning aids. View → Show Steps turns the step bar off everywhere; the
/// Getting started box has its own Hide button, and Help → Show Getting Started brings it back.
enum StepPreferences {
    static let showStepsKey = "showSteps"
    static let hideGettingStartedKey = "hideGettingStarted"
    /// Set by Help → Show Getting Started: shows the box even once the library has quotes.
    static let showGettingStartedKey = "showGettingStarted"
}

/// The words of the step bar, apart from how they are drawn. Steps are shown as words in order, never
/// as bare numbers: "Progress: ✓ Draft ▸ Sent ▸ Accepted ▸ Invoiced ▸ Paid".
enum StepProgress {
    /// The label in front of the steps.
    static let label = "Progress:"

    /// The steps as words, in order, such as ["Draft", "Sent", "Accepted", "Invoiced", "Paid"].
    static func words(_ next: NextStep) -> [String] { next.steps.map(\.title) }

    /// The short form for when the whole row doesn't fit: where the document is now, such as
    /// "Sent (step 2 of 5)". A stopped document is just its stop word ("Declined"), and one that has
    /// been through every step says so.
    static func compact(_ next: NextStep) -> String {
        if let stopped = next.steps.first(where: { $0.state == .stopped }) { return stopped.title }
        if let here = next.steps.first(where: { $0.state == .current }) {
            return "\(here.title) (step \(here.number) of \(next.steps.count))"
        }
        return "All steps done"
    }
}

/// The step bar: the steps a quote or invoice goes through, as words in order with the one it is on in
/// bold, and one plain sentence on what to do next. It lives in the first row of an editor's header,
/// in the space between the title block and the total, and takes the place of the `Spacer()` there
/// (with Show Steps off it is that spacer, so the header looks exactly as it did before the step bar).
/// It is a hint. It changes no default and no key.
///
/// **One control per action.** On any one screen an action has exactly one button. When the bar is
/// shown and has a button for an action (its Open button), that is the action's control, and the
/// screen's own button for it is left out (`offersOpen`); with View → Show Steps off, or when the bar
/// has no button for it, the screen's own button shows instead. The same action has the same label
/// everywhere: "Open Q-0001", naming the document, never a generic "Open Quote".
struct StepBar: View {
    enum Document {
        case quote(UUID)
        case invoice(UUID)
    }

    let model: AppModel
    let document: Document
    @AppStorage private var showSteps: Bool

    init(model: AppModel, document: Document, defaults: UserDefaults = .standard) {
        self.model = model
        self.document = document
        _showSteps = AppStorage(wrappedValue: true, StepPreferences.showStepsKey, store: defaults)
    }

    private var next: NextStep? {
        let library = model.library
        switch document {
        case .quote(let id):
            return library.quote(id).map { NextStep.forQuote($0, in: library, today: model.today) }
        case .invoice(let id):
            return library.invoice(id).map { NextStep.forInvoice($0, in: library, today: model.today) }
        }
    }

    var body: some View {
        if showSteps, let next {
            // The first form that fits the room the title block and the total leave: the whole row of
            // steps, then just where the document is now (down to `minimumWidth`, with the word cut
            // short if need be), and below that nothing at all rather than a few cut-off letters.
            ViewThatFits(in: .horizontal) {
                StepBarRegion(next: next, compact: false, open: open)
                StepBarRegion(next: next, compact: true, open: open)
                    .frame(minWidth: StepBarRegion.minimumWidth, idealWidth: StepBarRegion.minimumWidth,
                           maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(height: 0)
            }
            // It takes the room that is left and no more: its ideal width is 0, so it adds nothing to
            // how wide the header wants to be, and its priority is lower than the total's, so the
            // total keeps its width.
            .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
            // The header's first row is centred. This keeps line 1 level with the title even when
            // the sentence takes a second line (the row then grows downward, not both ways).
            .alignmentGuide(VerticalAlignment.center) { _ in StepBarRegion.centreOfTwoLines }
            .layoutPriority(-1)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Steps")
        } else {
            Spacer()
        }
    }

    /// Whether the bar shows a button that opens `id`: it is on (`stepsShown`) and its next step opens
    /// that document. While it does, a screen leaves out its own button for the same document.
    static func offersOpen(_ id: UUID, next: NextStep?, stepsShown: Bool) -> Bool {
        stepsShown && next?.openTarget?.id == id
    }

    /// Opens the invoice or quote the bar's button names.
    private func open(_ id: UUID) {
        if model.library.invoice(id) != nil {
            model.openInvoice(id)
        } else if model.library.quote(id) != nil {
            model.openQuote(id)
        }
    }
}

/// The bar's two lines, leading-aligned: the progress on line 1 and the "Next: …" sentence on line 2,
/// with its button (when it has one) under the sentence. The two lines' heights are the title block's,
/// so they sit level with the title and its status; the button hangs below them.
struct StepBarRegion: View {
    let next: NextStep
    /// Whether line 1 is the short form ("Sent (step 2 of 5)") instead of every step.
    let compact: Bool
    let open: (UUID) -> Void

    /// The least room the short form is shown in. Its widest ("Progress: Accepted (step 3 of 5)")
    /// is a little over 180; below this the bar is left out.
    static let minimumWidth: CGFloat = 130
    /// Air between the title block and the bar.
    static let leadingGap: CGFloat = 8

    /// Line 1 is as high as the title's line (16); line 2 is as high as the status row under it (16).
    /// With the 2 pt between, a one-line sentence makes the bar as tall as the title block (34).
    static let progressHeight: CGFloat = 16
    static let sentenceHeight: CGFloat = 16
    static let lineGap: CGFloat = 2
    /// Between the sentence and the button under it.
    static let buttonGap: CGFloat = 4
    /// Halfway down the two lines: where the title block's own centre is.
    static let centreOfTwoLines: CGFloat = (progressHeight + lineGap + sentenceHeight) / 2

    /// The small right-pointing arrow between the steps, drawn in pixels like the tick.
    static let arrow = ["k...", "kk..", "kkk.", "kkkk", "kkk.", "kk..", "k..."]

    /// Later steps: dark grey, not faded. (Black at 70% over the window grey; it reads at about 6:1
    /// where the palette's own mid grey would be 2:1.)
    static let laterText = Win95.text.opacity(0.7)

    var body: some View {
        VStack(alignment: .leading, spacing: Self.lineGap) {
            StepProgressRow(next: next, compact: compact)
                .frame(height: Self.progressHeight)
            sentence
        }
        .padding(.leading, Self.leadingGap)
    }

    /// Line 2, and under it the bar's button on a line of its own, both on the same left edge as line
    /// 1. Its ideal width is 0: the sentence takes the width it is given, so a long one wraps (to two
    /// lines at most) instead of making the bar ask for more room than the header has.
    private var sentence: some View {
        VStack(alignment: .leading, spacing: Self.buttonGap) {
            Text(next.sentence)
                .font(Win95.small)
                .foregroundStyle(Win95.text)
                // Two lines at the most, so it never pushes the total or the buttons. What doesn't
                // fit is cut with "…", and the whole sentence is in the tooltip.
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, minHeight: Self.sentenceHeight, alignment: .leading)
                .help(next.sentence)
            if let target = next.openTarget {
                // The bar's only button: small, plain, never the default.
                Button("Open \(target.number)") { open(target.id) }
                    .buttonStyle(.win95Small)
                    .fixedSize()
                    .help("Open \(target.kind) \(target.number)")
            }
        }
        .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
    }
}

/// Line 1: "Progress:" and then either every step in order, joined by arrows, or (when that is too wide)
/// just the one it is on.
struct StepProgressRow: View {
    let next: NextStep
    let compact: Bool

    var body: some View {
        HStack(spacing: 3) {
            Text(StepProgress.label)
                .font(Win95.small)
                .foregroundStyle(Win95.text)
                .lineLimit(1)
                .fixedSize()
                .padding(.trailing, 3)
            if compact {
                Text(StepProgress.compact(next))
                    .font(Win95.small.weight(.bold))
                    .foregroundStyle(next.steps.contains { $0.state == .stopped } ? Win95.overdue : Win95.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(StepProgress.words(next).joined(separator: " ▸ "))
            } else {
                ForEach(next.steps, id: \.number) { step in
                    StepChip(step: step, total: next.steps.count)
                    if step.number != next.steps.last?.number {
                        // The "▸" between two steps: a pixel arrow, which stays crisp at this size.
                        PixelGlyph(StepBarRegion.arrow, color: StepBarRegion.laterText)
                            .frame(width: 4, height: 7)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }
}

/// One step: a tick when it is done, bold in a light sunken bevel when it is the current one, dark
/// grey when it is still to come, dark red for Declined, Expired and Void. Only its word is shown.
struct StepChip: View {
    let step: NextStep.Step
    let total: Int

    var body: some View {
        HStack(spacing: 3) {
            if step.state == .done {
                PixelGlyph(PixelGlyph.tick, color: Win95.text)
                    .frame(width: 7, height: 7)
            }
            Text(step.title)
                .font(isHere ? Win95.small.weight(.bold) : Win95.small)
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .frame(height: StepBarRegion.progressHeight)
        .overlay(isHere ? ThinSunkenBevel() : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.number) of \(total), \(step.title), \(stateWord)")
    }

    private var isHere: Bool { step.state == .current || step.state == .stopped }

    private var color: Color {
        switch step.state {
        case .done, .current: return Win95.text
        case .todo: return StepBarRegion.laterText
        case .stopped: return Win95.overdue
        }
    }

    private var stateWord: String {
        switch step.state {
        case .done: return "done"
        case .current: return "this is where it is now"
        case .todo: return "still to come"
        case .stopped: return "it stopped here"
        }
    }
}

/// A one-pixel sunken frame, lighter than the kit's two-line bevel: shadow top and left, white
/// bottom and right.
struct ThinSunkenBevel: View {
    var body: some View {
        Canvas { context, size in
            guard size.width > 2, size.height > 2 else { return }
            context.fill(Path(CGRect(x: 0, y: 0, width: size.width - 1, height: 1)), with: .color(Win95.shadow))
            context.fill(Path(CGRect(x: 0, y: 0, width: 1, height: size.height - 1)), with: .color(Win95.shadow))
            context.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)), with: .color(Win95.highlight))
            context.fill(Path(CGRect(x: size.width - 1, y: 0, width: 1, height: size.height)), with: .color(Win95.highlight))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
