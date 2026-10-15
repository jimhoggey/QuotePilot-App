import QuotePilotCore
import SwiftUI

/// An invoice's payments, what's paid so far, and where a new payment is entered: no dialog, so
/// there is one place to look. A sent invoice with money owing shows the New payment area under
/// the list. Send Receipt… appears once a payment exists.
struct PaymentsBox: View {
    let model: AppModel
    let invoice: Invoice

    /// The area starts fresh for each invoice and after each payment, taking the new amount owing,
    /// and keeps what was typed after a refusal (the payment count hasn't changed).
    static func areaID(_ invoice: Invoice) -> String {
        "\(invoice.id.uuidString)-\(invoice.payments.count)"
    }

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
                if !invoice.payments.isEmpty {
                    HStack(spacing: 8) {
                        Button("Send Receipt…") { model.send(.receipt(invoice.id)) }
                            .buttonStyle(.win95)
                            .help("Open a Mail draft with a receipt for the payments so far")
                        if let sent = invoice.receiptSentAt {
                            Text("Receipt sent \(Day(sent).short)")
                        }
                    }
                }
                if let start = model.newPaymentEntry(for: invoice.id) {
                    EtchedLine()
                    NewPaymentArea(model: model, entry: start)
                        .id(Self.areaID(invoice))
                }
            }
            .font(Win95.body)
            .foregroundStyle(Win95.text)
        }
    }
}

/// Date, amount, method and note for the next payment, and the button that records it. Two or three
/// short rows, so it fits the editor form at its narrowest (500 pt).
struct NewPaymentArea: View {
    let model: AppModel
    @State private var entry: PaymentEntry

    init(model: AppModel, entry: PaymentEntry) {
        self.model = model
        _entry = State(initialValue: entry)
    }

    private static let labelWidth: CGFloat = 58

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("New payment")
                .font(Win95.label)
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Win95FieldRow("Note:", labelWidth: Self.labelWidth) {
                    Win95TextField("Note", text: $entry.note, prompt: "Optional, e.g. a reference")
                }
                Button("Record Payment") { model.recordPayment(entry) }
                    .buttonStyle(.win95)
                    .help("Record this payment against the invoice")
            }
        }
        // Return in any of the fields records it too.
        .onSubmit { model.recordPayment(entry) }
    }
}
