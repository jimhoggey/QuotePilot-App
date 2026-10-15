import Foundation

public struct ImportReport: Equatable, Sendable {
    public var addedQuotes: [String] = []
    public var addedInvoices: [String] = []
    /// Numbers that were already in the library.
    public var skipped: [String] = []
    public var addedClients: [String] = []
    /// Things that didn't carry over exactly.
    public var notes: [String] = []
    /// The old tool's logo, for the app to save as the brand logo (only when there isn't one yet).
    public var logoData: Data?

    public init() {}

    public var summary: String {
        func count(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        var text = "Imported \(count(addedQuotes.count, "quote")) and \(count(addedInvoices.count, "invoice")) from Invoice Generator"
        if !skipped.isEmpty { text += "; skipped \(skipped.joined(separator: ", ")), already here" }
        return text + "."
    }
}

public enum LegacyImportError: Error, Equatable, Sendable {
    case notABackup
}

/// Reads the JSON that Invoice Generator.html's "Back up to file" button writes.
public enum LegacyImport {
    struct Backup: Decodable {
        struct Settings: Decodable { var logo: String? }
        struct Party: Decodable { var name: String?; var details: String? }
        struct Item: Decodable {
            var title: String?
            var detail: String?
            var qty: Double?
            var unit: String?
            var rate: Double?
        }
        struct Tax: Decodable { var mode: String? }
        struct Discount: Decodable { var value: Double? }
        struct Doc: Decodable {
            var type: String?
            var number: String?
            var issued: String?
            var due: String?
            var reference: String?
            var from: Party?
            var to: Party?
            var items: [Item]?
            var tax: Tax?
            var discount: Discount?
            var paid: Double?
            var summary: String?
            var payment: String?
            var notes: String?
        }
        var settings: Settings?
        var docs: [String: Doc]
    }

    public static func importBackup(_ data: Data, into library: inout Library, today: Day) throws -> ImportReport {
        guard let backup = try? JSONDecoder().decode(Backup.self, from: data) else {
            throw LegacyImportError.notABackup
        }
        var report = ImportReport()
        // Oldest first, so clients and brand details come from the earliest document.
        let docs = backup.docs.values.sorted {
            ($0.issued ?? "", $0.number ?? "") < ($1.issued ?? "", $1.number ?? "")
        }

        for doc in docs {
            guard let number = doc.number?.trimmingCharacters(in: .whitespaces), !number.isEmpty else {
                report.notes.append("Skipped a document with no number.")
                continue
            }
            if library.usedNumbers.contains(number) {
                report.skipped.append(number)
                continue
            }
            let clientID = client(for: doc.to, in: &library, report: &report)
            let issued = doc.issued.flatMap(Day.init(iso:)) ?? today
            let due = doc.due.flatMap(Day.init(iso:)) ?? issued.adding(days: library.brand.paymentDueDays)
            let taxed = doc.tax?.mode == "add"
            if doc.tax?.mode == "incl" {
                report.notes.append("\(number): prices included GST in the old tool; imported as entered, without GST.")
            }
            if let discount = doc.discount?.value, discount > 0 {
                report.notes.append("\(number): its discount wasn't imported; add it as a line if needed.")
            }
            let lines = (doc.items ?? []).enumerated().map { index, item in
                LineItem(code: String(format: "%02d", index + 1), title: item.title ?? "", detail: item.detail ?? "",
                         quantity: decimal(item.qty ?? 1), unit: unit(item.unit), rate: dollars(item.rate ?? 0))
            }

            if doc.type == "quote" {
                library.quotes.append(Quote(number: number, clientID: clientID, title: doc.reference ?? "",
                                            issued: issued, validUntil: due, plan: .fiftyFifty, taxed: taxed,
                                            lines: lines, summary: doc.summary ?? "", terms: doc.notes ?? "",
                                            stage: .sent))
                report.addedQuotes.append(number)
            } else {
                library.invoices.append(Invoice(number: number, clientID: clientID, kind: .standalone,
                                                title: doc.reference ?? "", issued: issued, due: due, taxed: taxed,
                                                lines: lines, terms: doc.notes ?? "", stage: .sent))
                report.addedInvoices.append(number)
                // Payments arrive blank: the old tool never recorded when the money came in.
                if let paid = doc.paid, paid > 0 {
                    report.notes.append("\(number): the old tool showed \(dollars(paid).formatted()) already paid. Record it as a payment with the date it arrived.")
                }
            }
            library.usedNumbers.append(number)
            adoptBrandDetails(from: doc, into: &library.brand)
        }

        if library.brand.logoFile == nil, let logo = backup.settings?.logo {
            report.logoData = dataFromDataURL(logo)
        }
        library.log(report.summary)
        return report
    }

    static func client(for party: Backup.Party?, in library: inout Library, report: inout ImportReport) -> UUID? {
        let name = party?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        if let existing = library.clients.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing.id
        }
        let client = Client(name: name, address: party?.details ?? "")
        library.addClient(client)
        report.addedClients.append(name)
        return client.id
    }

    static func adoptBrandDetails(from doc: Backup.Doc, into brand: inout Brand) {
        if brand.businessName.isEmpty, let name = doc.from?.name, !name.isEmpty {
            brand.businessName = name
            brand.details = doc.from?.details ?? ""
        }
        if brand.paymentDetails.isEmpty, let payment = doc.payment, !payment.isEmpty {
            brand.paymentDetails = payment
        }
    }

    static func unit(_ text: String?) -> Unit {
        switch text {
        case "hr": return .hours
        case "day": return .days
        default: return .units
        }
    }

    static func dollars(_ value: Double) -> Money {
        Money(cents: 100).times(decimal(value))
    }

    /// The number as the old tool showed it: 0.47 stays 0.47 instead of the nearest binary value,
    /// so a true half-cent product still rounds up.
    static func decimal(_ value: Double) -> Decimal {
        Decimal(string: "\(value)", locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(value)
    }

    /// The bytes inside `data:image/png;base64,....`
    static func dataFromDataURL(_ text: String) -> Data? {
        guard text.hasPrefix("data:"), let comma = text.firstIndex(of: ","),
              text[..<comma].hasSuffix(";base64") else { return nil }
        return Data(base64Encoded: String(text[text.index(after: comma)...]))
    }
}
