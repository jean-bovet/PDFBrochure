import Foundation
import PDFKit
import CoreGraphics

// MARK: - Options

enum PaperSize: String, CaseIterable, Identifiable {
    case auto, a4, a3, usLetter, usTabloid
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Auto (2× input page, landscape)"
        case .a4: return "A4 landscape (2 × A5)"
        case .a3: return "A3 landscape (2 × A4)"
        case .usLetter: return "US Letter landscape (2 × Half-Letter)"
        case .usTabloid: return "US Tabloid landscape (2 × Letter)"
        }
    }
    /// Returns the *landscape* sheet size in PDF points, or nil for auto.
    var landscapePoints: CGSize? {
        switch self {
        case .auto: return nil
        case .a4: return CGSize(width: 841.89, height: 595.276)
        case .a3: return CGSize(width: 1190.55, height: 841.89)
        case .usLetter: return CGSize(width: 792, height: 612)
        case .usTabloid: return CGSize(width: 1224, height: 792)
        }
    }
}

enum FitMode: String, CaseIterable, Identifiable {
    case fit, fill, original
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fit: return "Fit (preserve aspect, may letterbox)"
        case .fill: return "Fill (preserve aspect, may crop)"
        case .original: return "Original size (centered, may clip)"
        }
    }
}

// MARK: - Errors

enum BookletError: LocalizedError {
    case cannotOpen, noPages, cannotCreateOutput
    var errorDescription: String? {
        switch self {
        case .cannotOpen: return "Could not open the input PDF."
        case .noPages: return "The input PDF has no pages."
        case .cannotCreateOutput: return "Could not create the output PDF."
        }
    }
}

// MARK: - Imposition

struct BookletMaker {
    struct Result {
        let inputPages: Int
        let outputPages: Int
        let sheetSize: CGSize
    }

    /// Returns a freshly imposed booklet PDF as data (no file I/O).
    /// Used by the live preview.
    static func makeBookletData(
        input: URL,
        paperSize: PaperSize,
        fitMode: FitMode
    ) throws -> (Data, Result) {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else {
            throw BookletError.cannotCreateOutput
        }
        let result = try renderBooklet(
            input: input,
            paperSize: paperSize,
            fitMode: fitMode
        ) { mediaBox in
            CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        }
        return (data as Data, result)
    }

    /// Writes the imposed booklet PDF to `output`.
    @discardableResult
    static func makeBooklet(
        input: URL,
        output: URL,
        paperSize: PaperSize,
        fitMode: FitMode
    ) throws -> Result {
        return try renderBooklet(
            input: input,
            paperSize: paperSize,
            fitMode: fitMode
        ) { mediaBox in
            CGContext(output as CFURL, mediaBox: &mediaBox, nil)
        }
    }

    /// Shared body for both APIs. The caller supplies a context factory so we
    /// can target either a file URL or an in-memory data consumer without
    /// duplicating the page-imposition logic.
    ///
    /// For an N-page document padded up to a multiple of 4, sheet k (1-indexed) holds:
    ///   • outer side: page (N − 2k + 2)  |  page (2k − 1)
    ///   • inner side: page (2k)          |  page (N − 2k + 1)
    private static func renderBooklet(
        input: URL,
        paperSize: PaperSize,
        fitMode: FitMode,
        makeContext: (inout CGRect) -> CGContext?
    ) throws -> Result {
        guard let doc = PDFDocument(url: input) else { throw BookletError.cannotOpen }
        let n = doc.pageCount
        guard n > 0 else { throw BookletError.noPages }

        let padded = ((n + 3) / 4) * 4
        let sheets = padded / 4

        var order: [Int] = []
        order.reserveCapacity(padded)
        for k in 1...sheets {
            order.append(padded - 2*k + 2) // outer left
            order.append(2*k - 1)          // outer right
            order.append(2*k)              // inner left
            order.append(padded - 2*k + 1) // inner right
        }

        let firstBox = doc.page(at: 0)!.bounds(for: .mediaBox)
        let sheetSize: CGSize = paperSize.landscapePoints
            ?? CGSize(width: firstBox.width * 2, height: firstBox.height)

        var mediaBox = CGRect(origin: .zero, size: sheetSize)
        guard let ctx = makeContext(&mediaBox) else {
            throw BookletError.cannotCreateOutput
        }

        let halfWidth = sheetSize.width / 2
        let outputPageCount = order.count / 2

        for outIdx in 0..<outputPageCount {
            let leftPage = order[outIdx * 2]
            let rightPage = order[outIdx * 2 + 1]

            ctx.beginPage(mediaBox: &mediaBox)

            // White background — keeps results identical regardless of how
            // a viewer treats a PDF media box's default background.
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(mediaBox)

            let leftSlot  = CGRect(x: 0,         y: 0, width: halfWidth, height: sheetSize.height)
            let rightSlot = CGRect(x: halfWidth, y: 0, width: halfWidth, height: sheetSize.height)

            draw(doc: doc, page1: leftPage,  pageCount: n, into: ctx, slot: leftSlot,  fit: fitMode)
            draw(doc: doc, page1: rightPage, pageCount: n, into: ctx, slot: rightSlot, fit: fitMode)

            ctx.endPage()
        }

        ctx.closePDF()

        return Result(inputPages: n, outputPages: outputPageCount, sheetSize: sheetSize)
    }

    /// Draws a single source page into the given slot of the output context.
    /// `page1` is 1-indexed; values greater than `pageCount` produce a blank slot.
    private static func draw(
        doc: PDFDocument,
        page1: Int,
        pageCount: Int,
        into ctx: CGContext,
        slot: CGRect,
        fit: FitMode
    ) {
        guard page1 >= 1, page1 <= pageCount,
              let page = doc.page(at: page1 - 1),
              let cgPage = page.pageRef
        else { return } // blank

        let box = page.bounds(for: .mediaBox)
        let rotation = page.rotation
        let rotated = (rotation % 180 != 0)
        let pageW = rotated ? box.height : box.width
        let pageH = rotated ? box.width  : box.height

        let scale: CGFloat = {
            switch fit {
            case .fit:      return min(slot.width / pageW, slot.height / pageH)
            case .fill:     return max(slot.width / pageW, slot.height / pageH)
            case .original: return 1
            }
        }()

        let drawW = pageW * scale
        let drawH = pageH * scale
        let dx = slot.origin.x + (slot.width  - drawW) / 2
        let dy = slot.origin.y + (slot.height - drawH) / 2

        ctx.saveGState()
        if fit == .fill {
            ctx.addRect(slot)
            ctx.clip()
        }
        ctx.translateBy(x: dx, y: dy)
        ctx.scaleBy(x: scale, y: scale)

        switch rotation {
        case 90:
            ctx.translateBy(x: 0, y: pageH)
            ctx.rotate(by: -.pi / 2)
        case 180:
            ctx.translateBy(x: pageW, y: pageH)
            ctx.rotate(by: .pi)
        case 270:
            ctx.translateBy(x: pageW, y: 0)
            ctx.rotate(by: .pi / 2)
        default:
            break
        }
        ctx.translateBy(x: -box.origin.x, y: -box.origin.y)
        ctx.drawPDFPage(cgPage)
        ctx.restoreGState()
    }

    /// Suggests a sensible default sheet size from the source page dimensions.
    /// A4 input → A4 landscape (two-up to A5). Anything else → auto (preserve size).
    static func smartDefaultPaper(forFirstPageSize size: CGSize) -> PaperSize {
        let area = Double(size.width * size.height)
        let a4 = 595.276 * 841.89
        return abs(area - a4) / a4 < 0.05 ? .a4 : .auto
    }
}
