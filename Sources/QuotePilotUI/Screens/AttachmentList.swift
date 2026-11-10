import SwiftUI

/// An expense's attached quote or invoice as a one-row Windows 95 list: a column header, then the
/// file's icon and name. Double-click opens it; × takes it off the expense (the copy stays in
/// Assets/Expenses).
struct AttachmentList: View {
    let fileName: String
    /// Off while the fee lock is on; opening still works.
    let canRemove: Bool
    let open: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(spacing: 0) {
                Text("Attached file")
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, minHeight: DetailsLayout.headerHeight, alignment: .leading)
                    .background(Win95.face)
                    .overlay(Bevel(.raised))
                HStack(spacing: 6) {
                    PixelIconView(.receipt)
                    Text(fileName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    SquareButton(PixelGlyph.cross, label: "Remove \(fileName) from this expense", action: remove)
                        .disabled(!canRemove)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture(count: 2, perform: open)
                .help("Double-click to open \(fileName)")
            }
            .padding(2)
            .background(Win95.field)
            .overlay(Bevel(.sunken))
            Text("Double-click it to open it.")
                .font(Win95.small)
                .foregroundStyle(Win95.note)
        }
        .font(Win95.body)
        .foregroundStyle(Win95.text)
    }
}
