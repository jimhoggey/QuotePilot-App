import Foundation

// A draft's own number, typed in: to carry on from another tool's numbering, say. A number on any
// quote or invoice in the library is refused; one from a deleted document may be used again, and is
// noted as used before. Automatic numbering carries on from the highest number used.

extension Library {
    /// What Activity adds to a number change when the new number was used before.
    static let usedBeforeNote = " (used before)"

    /// `text` as a number of `kind`: "Q-0012" from "Q-0012", "q-12" or "12". Nil when it's anything
    /// else, or zero.
    public static func parseNumber(_ text: String, _ kind: DocumentKind) -> String? {
        var digits = Substring(text.trimmingCharacters(in: .whitespaces))
        let prefix = kind.prefix
        if digits.uppercased().hasPrefix(prefix) { digits = digits.dropFirst(prefix.count) }
        guard !digits.isEmpty, digits.count <= 9, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let value = Int(digits), value > 0 else { return nil }
        return prefix + String(format: "%04d", value)
    }

    /// Whether `number` is on a quote or invoice in the library, other than the one `except` names.
    public func numberInUse(_ number: String, except id: UUID? = nil) -> Bool {
        quotes.contains { $0.id != id && $0.number.caseInsensitiveCompare(number) == .orderedSame }
            || invoices.contains { $0.id != id && $0.number.caseInsensitiveCompare(number) == .orderedSame }
    }

    /// Whether `number` was on another quote or invoice before (one since deleted or renumbered), so
    /// its document was given it by hand afterwards. The editor says so in grey.
    public func numberUsedBefore(_ number: String) -> Bool {
        activity.contains { $0.number == number && $0.message.hasSuffix(Self.usedBeforeNote) }
    }

    /// Gives a draft quote the number typed for it.
    public mutating func renumber(quote id: UUID, to text: String) throws {
        let index = try quoteIndex(id)
        guard quotes[index].stage == .draft else { throw LibraryError.numberOnlyOnDrafts }
        let number = try checkedNumber(text, .quote, for: id)
        let old = quotes[index].number
        guard number != old else { return }
        let usedBefore = Set(usedNumbers).contains(number)
        quotes[index].number = number
        keepUsed([number])
        log("Changed quote \(old)'s number to \(number)" + (usedBefore ? Self.usedBeforeNote : ""), number: number)
    }

    /// Gives a draft invoice the number typed for it. A deposit a final invoice deducts keeps its
    /// number, as the final names it.
    public mutating func renumber(invoice id: UUID, to text: String) throws {
        let index = try invoiceIndex(id)
        guard invoices[index].stage == .draft else { throw LibraryError.numberOnlyOnDrafts }
        if let final = liveFinalDeducting(invoices[index]) { throw LibraryError.deductedByFinal(final.number) }
        let number = try checkedNumber(text, .invoice, for: id)
        let old = invoices[index].number
        guard number != old else { return }
        let usedBefore = Set(usedNumbers).contains(number)
        invoices[index].number = number
        keepUsed([number])
        log("Changed invoice \(old)'s number to \(number)" + (usedBefore ? Self.usedBeforeNote : ""), number: number)
    }

    private func checkedNumber(_ text: String, _ kind: DocumentKind, for id: UUID) throws -> String {
        guard let number = Self.parseNumber(text, kind) else { throw LibraryError.notANumber(text, kind.prefix) }
        if numberInUse(number, except: id) { throw LibraryError.numberInUse(number) }
        return number
    }
}
