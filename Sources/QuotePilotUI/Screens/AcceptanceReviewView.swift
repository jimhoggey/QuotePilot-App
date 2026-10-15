import QuotePilotCore
import SwiftUI

/// Every line as the PDF reported it (or unticked, by hand). Change any tick, check the client's
/// name and date, then confirm.
struct AcceptanceReviewView: View {
    let model: AppModel
    @State private var review: AcceptanceReview

    init(model: AppModel, review: AcceptanceReview) {
        self.model = model
        _review = State(initialValue: review)
    }

    var body: some View {
        let quote = model.library.quote(review.quoteID)
        let accepted = Totals(subtotal: review.lines.filter(\.accepted).reduce(.zero) { $0 + $1.amount },
                              taxed: quote?.taxed ?? false).total
        DialogPanel(title: "Record Acceptance - \(quote?.number ?? "")", icon: .quote, width: 600) {
            // The warnings and the lines share one scroll area. It's as tall as its contents, or as
            // tall as the window leaves room for (the overlay keeps the dialog inside it), and then
            // it scrolls. The warnings come first, so a blocking one is the first thing seen.
            LeftoverHeightStack(spacing: 10) {
                Text(review.intro)
                    .font(Win95.body)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = review.replacementNote {
                    Text(note)
                        .font(Win95.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(review.problems.enumerated()), id: \.offset) { _, problem in
                            NoteBanner(problem.isBlocking ? problem.message + " Nothing will change." : problem.message,
                                       warning: true)
                        }
                        GroupBox("Lines") {
                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("Accept all", isOn: acceptAll)
                                    .toggleStyle(.win95)
                                EtchedLine()
                                ForEach($review.lines) { $line in
                                    HStack {
                                        Toggle("\(line.code)  \(line.title.isEmpty ? "(untitled)" : line.title)", isOn: $line.accepted)
                                            .toggleStyle(.win95)
                                        Spacer()
                                        Text(model.money(line.amount))
                                            .font(Win95.money)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .takesLeftoverHeight()
                HStack(spacing: 6) {
                    Text("Accepted:").font(Win95.label)
                    Text(model.money(accepted)).font(Win95.money)
                    Text("of \(model.money(quote?.totals.total ?? .zero))").font(Win95.body)
                }
                Win95FieldRow("Client's name:", labelWidth: 110) {
                    Win95TextField("Client's name", text: $review.clientName)
                }
                Win95FieldRow("Date:", labelWidth: 110) {
                    Win95TextField("Date the client signed", text: $review.clientDate)
                }
                Text(Self.planNote(plan: quote?.plan, accepted: accepted, currencyCode: model.currencyCode))
                    .font(Win95.small)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Spacer()
                    // With nothing ticked this records a decline, and the button says so.
                    Button(review.confirmTitle) { model.confirmAcceptance(review) }
                        .buttonStyle(.win95Default)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!review.canBeConfirmed)
                    Button("Cancel") { model.dialog = nil }
                        .buttonStyle(.win95)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .foregroundStyle(Win95.text)
        }
        .groupBoxStyle(.win95)
    }

    private var acceptAll: Binding<Bool> {
        Binding(get: { review.lines.allSatisfy(\.accepted) },
                set: { value in
                    for index in review.lines.indices { review.lines[index].accepted = value }
                })
    }

    /// What confirming will do beyond recording the ticks. The deposit is the plan's own percentage,
    /// the one `draftNextInvoice` uses.
    static func planNote(plan: PaymentPlan?, accepted: Money, currencyCode: String) -> String {
        guard accepted > .zero else {
            return "Nothing is ticked: this records that the client declined every line."
        }
        guard let plan else { return "" }
        if let percent = plan.depositPercent {
            return "\(percent)% deposit: confirming also drafts the deposit invoice for "
                + "\(accepted.percent(percent).formatted(currencyCode: currencyCode)) and opens it."
        }
        return "Full amount: the invoice is drafted when you click Job Complete."
    }
}
