import QuotePilotCore
import SwiftUI

/// Which of the three first steps a new library has done. The Dashboard shows the box while there are
/// no quotes; once one exists it goes, until Help → Show Getting Started brings it back.
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
            case .quote: return "Press New Quote in the toolbar, add the work as lines, then send it."
            }
        }

        /// The row's button, or none when the toolbar already has one for the same thing: New Quote
        /// is the toolbar's, right above the box (one control per action).
        var buttonTitle: String? {
            switch self {
            case .business: return "Go to Brand"
            case .client: return "New Client"
            case .quote: return nil
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

    /// Whether the library alone shows the box: until the first quote exists.
    var isShowing: Bool { Self.isVisible(hasQuotes: quote, hidden: false, shownFromHelp: false) }

    /// The one rule for the box: it shows while there are no quotes and it isn't hidden, or whenever
    /// Help → Show Getting Started has asked for it.
    static func isVisible(hasQuotes: Bool, hidden: Bool, shownFromHelp: Bool) -> Bool {
        (!hasQuotes && !hidden) || shownFromHelp
    }

    /// Help → Show Getting Started: clears Hide, shows the box even with quotes, and goes to the
    /// Dashboard. Like every menu command it waits while a message box is up.
    @MainActor
    static func showAgain(in model: AppModel, defaults: UserDefaults = .standard) {
        model.whenFree {
            defaults.set(false, forKey: StepPreferences.hideGettingStartedKey)
            defaults.set(true, forKey: StepPreferences.showGettingStartedKey)
            model.go(to: .dashboard)
        }
    }

    /// The box's Hide button: hidden again, and no longer held open by the Help menu.
    static func hide(in defaults: UserDefaults) {
        defaults.set(true, forKey: StepPreferences.hideGettingStartedKey)
        defaults.set(false, forKey: StepPreferences.showGettingStartedKey)
    }

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
/// Help → Show Getting Started brings it back, quotes or not, until Hide is pressed again.
struct GettingStartedBox: View {
    let model: AppModel
    private let defaults: UserDefaults
    @AppStorage private var hidden: Bool
    @AppStorage private var shownFromHelp: Bool
    @AppStorage private var stepsShown: Bool

    init(model: AppModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
        _hidden = AppStorage(wrappedValue: false, StepPreferences.hideGettingStartedKey, store: defaults)
        _shownFromHelp = AppStorage(wrappedValue: false, StepPreferences.showGettingStartedKey, store: defaults)
        _stepsShown = AppStorage(wrappedValue: true, StepPreferences.showStepsKey, store: defaults)
    }

    var body: some View {
        let steps = GettingStarted(library: model.library)
        if GettingStarted.isVisible(hasQuotes: steps.isDone(.quote), hidden: hidden, shownFromHelp: shownFromHelp) {
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
                    Button("Hide") { GettingStarted.hide(in: defaults) }
                        .buttonStyle(.win95Small)
                        .padding(.trailing, 8)
                        .help("Hide this box. Help → Show Getting Started brings it back.")
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
            // A step without a button keeps the button's room, so the rows stay the same height.
            if let title = item.buttonTitle {
                Button(title) { GettingStarted.perform(item, in: model) }
                    .buttonStyle(Win95ButtonStyle(isDefault: isFirst))
                    .frame(width: 104, alignment: .trailing)
                    // New Client and New Quote wait for the fee lock; the Brand step only goes there.
                    .disabled(item != .business && !model.canEdit)
            } else {
                Color.clear.frame(width: 104, height: 23)
            }
        }
    }
}
