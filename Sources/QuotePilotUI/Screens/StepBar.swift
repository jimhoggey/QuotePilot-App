import QuotePilotCore
import SwiftUI

/// The two switches for the learning aids. View → Show Steps turns the step bar off everywhere; the
/// Getting started box has its own Hide button.
enum StepPreferences {
    static let showStepsKey = "showSteps"
    static let hideGettingStartedKey = "hideGettingStarted"
}

/// A quiet strip under an editor's header: the steps a quote or invoice goes through, with the one it
/// is on in bold, and one plain sentence on what to do next. It is a hint. It changes no button, no
/// default and no key, and View → Show Steps takes it away, leaving the editor exactly as it was.
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
            // The steps and the sentence share one line when they fit it; at the smallest window a long
            // sentence goes under the steps, and one longer still wraps there rather than being cut.
            ViewThatFits(in: .horizontal) {
                StepBarContent(next: next, stacked: false, open: open)
                StepBarContent(next: next, stacked: true, open: open)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Win95.face)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Steps")
        }
    }

    private func open(_ invoiceID: UUID) {
        model.openInvoice(invoiceID)
    }
}

/// The strip's contents: the steps, then the sentence beside them or under them.
struct StepBarContent: View {
    let next: NextStep
    /// Whether the sentence sits under the steps instead of beside them.
    let stacked: Bool
    let open: (UUID) -> Void

    /// The height of one row of the strip. With the strip's 1 pt above and below, a one-line strip
    /// is 20 high.
    static let rowHeight: CGFloat = 18

    /// Later steps: dark grey, not faded. (Black at 70% over the window grey; it reads at about 6:1
    /// where the palette's own mid grey would be 2:1.)
    static let laterText = Win95.text.opacity(0.7)

    var body: some View {
        if stacked {
            VStack(alignment: .leading, spacing: 0) {
                steps
                sentence
            }
        } else {
            HStack(alignment: .center, spacing: 12) {
                steps
                Spacer(minLength: 8)
                sentence
            }
        }
    }

    private var steps: some View {
        HStack(spacing: 3) {
            ForEach(next.steps, id: \.number) { step in
                StepChip(step: step, total: next.steps.count)
                if step.number != next.steps.last?.number {
                    Text("▸")
                        .font(Win95.small)
                        .foregroundStyle(Self.laterText)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(height: Self.rowHeight)
    }

    private var sentence: some View {
        HStack(spacing: 8) {
            Text(next.sentence)
                .font(Win95.small)
                .foregroundStyle(Win95.text)
                // Wraps to the width it is given, and takes the height it needs, so it is never cut.
                .fixedSize(horizontal: false, vertical: true)
            if case .openInvoice(let id, let number) = next.action {
                // The strip's only button: small, plain, never the default.
                Button("Open \(number)") { open(id) }
                    .buttonStyle(.win95Small)
                    .help("Open invoice \(number)")
            }
        }
        .frame(minHeight: stacked ? 16 : Self.rowHeight)
    }
}

/// One step: a tick when it is done, bold in a light sunken bevel when it is the current one, dark
/// grey when it is still to come, dark red for Declined, Expired and Void.
struct StepChip: View {
    let step: NextStep.Step
    let total: Int

    var body: some View {
        HStack(spacing: 3) {
            if step.state == .done {
                PixelGlyph(PixelGlyph.tick, color: Win95.text)
                    .frame(width: 7, height: 7)
            }
            Text(step.label)
                .font(isHere ? Win95.small.weight(.bold) : Win95.small)
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .frame(height: 16)
        .overlay(isHere ? ThinSunkenBevel() : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.number) of \(total), \(step.title), \(stateWord)")
    }

    private var isHere: Bool { step.state == .current || step.state == .stopped }

    private var color: Color {
        switch step.state {
        case .done, .current: return Win95.text
        case .todo: return StepBarContent.laterText
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
