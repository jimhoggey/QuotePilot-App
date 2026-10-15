import QuotePilotCore
import SwiftUI

/// Everything that has happened, newest first. Double-click an entry to open its quote or invoice.
struct ActivityView: View {
    let model: AppModel
    @State private var selection: UUID?

    var body: some View {
        DetailsList(model.library.activity, id: \.id, columns: [
            .text("When", width: .fixed(180), sortValue: { .number(Int($0.at.timeIntervalSince1970)) }) { Self.when($0.at) },
            .text("Number", width: .fixed(90)) { $0.number ?? "" },
            .text("What happened", width: .flexible(min: 240)) { $0.message },
        ], selection: $selection, sort: DetailsSort(column: 0, ascending: false),
        emptyText: "Nothing has happened yet. Every change you make is noted here.",
        onOpen: { id in
            if let number = model.library.activity.first(where: { $0.id == id })?.number {
                model.openDocument(number: number)
            }
        })
        .padding(8)
    }

    /// "15 Oct 2026 at 2:41 pm"
    static func when(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "en_AU")))
    }
}
