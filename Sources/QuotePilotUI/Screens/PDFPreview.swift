import AppKit
import PDFKit
import QuotePilotCore
import QuotePilotPDF
import SwiftUI
import UniformTypeIdentifiers

/// A file for the save panel: a PDF, the tax-time CSV, or a copy of the library.
struct ExportFile: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf, .commaSeparatedText, .json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// PDF data in a PDFView on Windows 95 grey, the page fitted to the width.
struct PDFPreview: NSViewRepresentable {
    let data: Data?

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = NSColor(Win95.shadow)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard context.coordinator.shown != data else { return }
        context.coordinator.shown = data
        view.document = data.flatMap(PDFDocument.init(data:))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var shown: Data?
    }
}

/// What a preview shows. The brand counts too, because the logo, font and colour aren't in the
/// document's content.
struct PreviewKey: Equatable {
    var content: DocumentContent?
    var brand: Brand
}

/// A preview that redraws itself shortly after the document or the brand changes.
struct LivePDFPreview: View {
    let model: AppModel
    let content: DocumentContent?
    /// The brand to draw in: the library's when nil. The Brand screen passes its `previewBrand`.
    var brand: Brand?
    @State private var pdf: Data?

    var body: some View {
        PDFPreview(data: pdf)
            .overlay(Bevel(.sunken))
            .task(id: PreviewKey(content: content, brand: brand ?? model.library.brand)) {
                // Wait for a pause in typing before redrawing, except the first time.
                if pdf != nil {
                    try? await Task.sleep(for: .milliseconds(300))
                    if Task.isCancelled { return }
                }
                pdf = content.map { model.pdf($0, brand: brand) }
            }
    }
}
