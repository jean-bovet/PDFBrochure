import SwiftUI
import PDFKit

/// `PDFView` wrapped for SwiftUI — the live brochure preview.
struct PDFPreview: NSViewRepresentable {
    let data: Data

    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = .underPageBackgroundColor
        return v
    }

    func updateNSView(_ v: PDFView, context: Context) {
        // Swap in the new document but keep the user's current scroll position
        // when the option change only altered rendering, not page count.
        let oldDoc = v.document
        if let newDoc = PDFDocument(data: data) {
            v.document = newDoc
            if let oldDoc, oldDoc.pageCount == newDoc.pageCount {
                // Document layout stayed the same — autoScales redraws in place.
            } else {
                v.goToFirstPage(nil)
            }
        }
    }
}

#if DEBUG
#Preview("PDFPreview") {
    PDFPreview(data: PreviewSamples.tinyBookletPDF(pages: 2))
        .frame(width: 700, height: 400)
}
#endif
