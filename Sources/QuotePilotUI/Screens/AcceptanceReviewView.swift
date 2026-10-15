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
            VStack(alignment: .leading, spacing: 10) {
                Text(review.source == .returnedPDF
                     ? "From \(review.fileName ?? "the returned PDF"). Check the ticks and change any that are wrong, then confirm."
                     : "Tick the lines the client accepted, then confirm.")
                    .font(Win95.body)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(review.problems.enumerated()), id: \.offset) { _, problem in
                    NoteBanner(problem.isBlocking ? problem.message + " Nothing will change." : problem.message, warning: true)
                }
                GroupBox("Lines") {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Accept all", isOn: acceptAll)
                            .toggleStyle(.win95)
                        EtchedLine()
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
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
                        // As tall as its lines, up to 180, then it scrolls: with warnings above it the
                        // whole dialog still fits the smallest window.
                        .frame(maxHeight: 180)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
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
                Text(planNote(quote, accepted: accepted))
                    .font(Win95.small)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Spacer()
                    Button("Confirm") { model.confirmAcceptance(review) }
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

    private func planNote(_ quote: Quote?, accepted: Money) -> String {
        guard accepted > .zero else { return "Nothing is ticked: confirming records that the client declined." }
        switch quote?.plan {
        case .fiftyFifty?:
            return "50/50: confirming also drafts the deposit invoice for \(model.money(accepted.percent(50))) and opens it."
        case .fullAmount?:
            return "Full amount: the invoice is drafted when you click Job Complete."
        case nil:
            return ""
        }
    }
}
