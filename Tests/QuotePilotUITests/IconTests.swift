import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@Suite struct IconTests {
    @Test func everyIconIsSixteenBySixteenInThePalette() {
        for icon in PixelIcon.allCases {
            #expect(icon.grid.count == 16, "\(icon) has \(icon.grid.count) rows")
            for (index, row) in icon.grid.enumerated() {
                #expect(row.count == 16, "\(icon) row \(index) has \(row.count) pixels")
                #expect(row.allSatisfy { $0 == "." || PixelIcon.palette[$0] != nil }, "\(icon) row \(index) uses a colour outside the palette")
            }
            #expect(icon.grid.joined().contains { $0 != "." }, "\(icon) is blank")
        }
    }

    @Test func everyIconLooksDifferent() {
        #expect(Set(PixelIcon.allCases.map(\.grid)).count == PixelIcon.allCases.count)
    }

    @Test func everyStatusHasAnIconAndAWord() {
        let quoteStatuses: [QuoteStatus] = [.draft, .sent, .expired, .declined, .accepted(partly: false), .accepted(partly: true)]
        for status in quoteStatuses {
            #expect(!status.label.isEmpty)
            _ = status.icon
        }
        let invoiceStatuses: [InvoiceStatus] = [.draft, .sent, .partPaid, .paid, .void, .overdue(daysLate: 5)]
        for status in invoiceStatuses {
            #expect(!status.listLabel.isEmpty)
            _ = status.icon
        }
        #expect(InvoiceStatus.overdue(daysLate: 5).listLabel == "Overdue 5 d")
        #expect(InvoiceStatus.overdue(daysLate: 5).isAlert)
        #expect(!InvoiceStatus.paid.isAlert)
        #expect(QuoteStatus.expired.icon == .warning)
        #expect(InvoiceStatus.paid.icon == .tick)
    }

    @MainActor @Test func theIconSheetDraws() {
        let rep = Snapshot.render(IconSheet(), size: CGSize(width: 640, height: 150), name: "icons")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}

/// Every icon at 16 and 32 points, for the screenshot.
struct IconSheet: View {
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(72)), count: 8), spacing: 8) {
            ForEach(PixelIcon.allCases, id: \.self) { icon in
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        PixelIconView(icon)
                        PixelIconView(icon, size: 32)
                    }
                    Text(icon.rawValue).font(Win95.small).foregroundStyle(Win95.text)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Win95.face)
    }
}
