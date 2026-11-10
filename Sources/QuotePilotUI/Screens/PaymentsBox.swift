import QuotePilotCore
import SwiftUI

/// An invoice's payments, what's paid so far, and where a new payment is entered: no dialog, so
/// there is one place to look. A sent invoice with money owing shows the New payment area under
/// the list; the editor's Record Payment, at the top, records it. Send Receipt… is up there too,
/// once a payment exists, and the box says when the receipt went.
struct PaymentsBox: View {
    let model: AppModel
    let invoice: Invoice
    /// The New payment area's entry, which the editor keeps; nil when the invoice can't take a payment.
    let payment: Binding<PaymentEntry>?

    var body: some View {
        let share = invoice.amount.cents > 0 ? Double(invoice.paid.cents) / Double(invoice.amount.cents) : 0
        GroupBox("Payments") {
            VStack(alignment: .leading, spacing: 6) {
                if invoice.payments.isEmpty {
                    Text("No payments recorded yet.")
                }
                ForEach(invoice.payments) { payment in
                    HStack(spacing: 8) {
                        Text(payment.date.short)
                            .frame(width: 100, alignment: .leading)
                        Text(payment.method.label)
                            .frame(width: 100, alignment: .leading)
                        Text(payment.note)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                        Text(model.money(payment.amount))
                            .font(Win95.money)
                        SquareButton(PixelGlyph.cross,
                                     label: "Remove the \(model.money(payment.amount)) payment of \(payment.date.short)") {
                            model.removePayment(payment.id, from: invoice.id)
                        }
                    }
                }
                EtchedLine()
                HStack(spacing: 8) {
                    Text("Paid \(model.money(invoice.paid)) of \(model.money(invoice.amount))")
                    Spacer(minLength: 0)
                    Win95Progress(fraction: share)
                        .frame(width: 160)
                }
                if invoice.stage == .sent, invoice.owing <= .zero {
                    Text("Paid in full.")
                }
                if let sent = invoice.receiptSentAt {
                    Text("Receipt sent \(Day(sent).short)")
                }
                if let payment {
                    EtchedLine()
                    NewPaymentArea(entry: payment) { model.recordPayment($0) }
                }
            }
            .font(Win95.body)
            .foregroundStyle(Win95.text)
        }
    }
}

/// Date, amount, method and note for the next payment. The editor's Record Payment, at the top,
/// records it, and so does Return in any of the fields. Two or three short rows, so it fits the
/// editor form at its narrowest (500 pt).
struct NewPaymentArea: View {
    @Binding var entry: PaymentEntry
    let record: (PaymentEntry) -> Void

    private static let labelWidth: CGFloat = 58

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("New payment")
                    .font(Win95.label)
                Text("Press Record Payment at the top to record it.")
                    .font(Win95.small)
                    .foregroundStyle(Win95.note)
            }
            HStack(spacing: 16) {
                Win95FieldRow("Date:", labelWidth: Self.labelWidth) {
                    DayPicker(label: "Payment date", day: $entry.date)
                }
                Win95FieldRow("Amount:", labelWidth: Self.labelWidth) {
                    Win95TextField("Amount", text: $entry.amount)
                        .frame(width: 110)
                }
                Spacer(minLength: 0)
            }
            Win95FieldRow("Method:", labelWidth: Self.labelWidth) {
                Win95RadioGroup(selection: $entry.method,
                                options: PaymentMethod.allCases.map { ($0, $0.label) }, axis: .horizontal)
            }
            Win95FieldRow("Note:", labelWidth: Self.labelWidth) {
                Win95TextField("Note", text: $entry.note, prompt: "Optional, e.g. a reference")
            }
        }
        // Return in any of the fields records it, as the outlined Record Payment says. It takes no
        // shortcut of its own, so Return elsewhere on the screen doesn't record a payment.
        .onSubmit { record(entry) }
    }
}
