import QuotePilotCore
import SwiftUI

/// Which of the three first steps a new library has done. The Dashboard shows the box while there are
/// no quotes; once one exists the box is gone for good.
struct GettingStarted: Equatable {
    enum Item: CaseIterable {
        case business, client, quote

        var title: String {
            switch self {
            case .business: return "Fill in your business details"
            case .client: return "Add your first client"
            case .quote: return "Make your first quote"
            }
        }

        var detail: String {
            switch self {
            case .business: return "Your name and payment details print on every document."
            case .client: return "Who the quote is for. Add more any time."
            case .quote: return "Add the work as lines, then send it to the client."
            }
        }

        var buttonTitle: String {
            switch self {
            case .business: return "Go to Brand"
            case .client: return "New Client"
            case .quote: return "New Quote"
            }
        }
    }

    private let business: Bool
    private let client: Bool
    private let quote: Bool

    init(library: Library) {
        // A name made only of spaces is no name.
        business = !library.brand.businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        client = !library.clients.isEmpty
        quote = !library.quotes.isEmpty
    }

    func isDone(_ item: Item) -> Bool {
        switch item {
        case .business: return business
        case .client: return client
        case .quote: return quote
        }
    }

    /// The first step not done yet: its button is the one drawn as the default.
    var first: Item? { Item.allCases.first { !isDone($0) } }

    /// The box shows until the first quote exists.
    var isShowing: Bool { !quote }

    /// What each step's button does.
    @MainActor
    static func perform(_ item: Item, in model: AppModel) {
        switch item {
        case .business: model.go(to: .brand)
        case .client: model.newClient()
        case .quote: model.newQuote()
        }
    }

    /// The sentence under the box. It points at the step bar, so it stops mentioning it when the bar is off.
    static func footnote(stepsShown: Bool) -> String {
        let base = "After that: send the quote, read the client's ticked reply, invoice, and record payments."
        return stepsShown ? base + " Each quote shows its next step." : base
    }
}

/// The "Getting started" group box at the top of a new library's Dashboard, with its Hide button and
/// the sentence under it. It is a hint: it can be hidden, and it hides itself when the first quote exists.
struct GettingStartedBox: View {
    let model: AppModel
    @AppStorage private var hidden: Bool
    @AppStorage private var stepsShown: Bool

    init(model: AppModel, defaults: UserDefaults = .standard) {
        self.model = model
        _hidden = AppStorage(wrappedValue: false, StepPreferences.hideGettingStartedKey, store: defaults)
        _stepsShown = AppStorage(wrappedValue: true, StepPreferences.showStepsKey, store: defaults)
    }

    var body: some View {
        let steps = GettingStarted(library: model.library)
        if steps.isShowing && !hidden {
            VStack(alignment: .leading, spacing: 6) {
                GroupBox("Getting started") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(GettingStarted.Item.allCases.enumerated()), id: \.offset) { index, item in
                            row(number: index + 1, item: item, done: steps.isDone(item), isFirst: steps.first == item)
                        }
                    }
                    // Room under the Hide button, which sits on the box's top edge.
                    .padding(.top, 3)
                }
                // On the box's top edge, to the right, like its title on the left.
                .overlay(alignment: .topTrailing) {
                    Button("Hide") { hidden = true }
                        .buttonStyle(.win95Small)
                        .padding(.trailing, 8)
                        .help("Hide this box. It also goes by itself once you have a quote.")
                }
                Text(GettingStarted.footnote(stepsShown: stepsShown))
                    .font(Win95.body)
                    .foregroundStyle(Win95.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(number: Int, item: GettingStarted.Item, done: Bool, isFirst: Bool) -> some View {
        HStack(spacing: 8) {
            // A sunken square with a tick once it's done, as a Windows 95 check box looks.
            ZStack {
                Win95.field
                if done {
                    PixelGlyph(PixelGlyph.tick, color: Win95.dark)
                        .frame(width: 7, height: 7)
                }
            }
            .frame(width: 13, height: 13)
            .overlay(Bevel(.sunken))
            .accessibilityLabel(done ? "Done" : "Not done yet")
            Text("\(number). \(item.title)")
                .font(Win95.label)
                .foregroundStyle(Win95.text)
                .lineLimit(1)
            Text(item.detail)
                .font(Win95.small)
                .foregroundStyle(Win95.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            // The first step still to do gets the heavy outline. As with Send by Mail… in the editors
            // this is a mark only: Return on the Dashboard still does nothing it did not do before.
            Button(item.buttonTitle) { GettingStarted.perform(item, in: model) }
                .buttonStyle(Win95ButtonStyle(isDefault: isFirst))
                .frame(width: 104, alignment: .trailing)
        }
    }
}
