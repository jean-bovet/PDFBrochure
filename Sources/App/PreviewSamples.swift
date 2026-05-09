#if DEBUG
import Foundation
import CoreGraphics
import CoreText

/// Helpers for SwiftUI #Preview blocks. Synthesises tiny PDFs in memory so
/// previews don't depend on external files. Compiled out of Release builds.
enum PreviewSamples {

    /// Returns PDF data for a `pages`-page document at A4-landscape sheet size,
    /// alternating coloured panes and a numbered label per page so the
    /// LayoutView preview's PDF pane has visible content.
    static func tinyBookletPDF(pages: Int) -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else { return Data() }
        var box = CGRect(x: 0, y: 0, width: 841.89, height: 595.276) // A4 landscape
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }

        let halfW = box.width / 2

        for i in 0..<pages {
            ctx.beginPage(mediaBox: &box)

            // White sheet
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(box)

            // Two faintly tinted panes to evoke "two pages on a sheet"
            ctx.setFillColor(CGColor(srgbRed: 0.94, green: 0.97, blue: 0.95, alpha: 1))
            ctx.fill(CGRect(x: 20, y: 20, width: halfW - 40, height: box.height - 40))
            ctx.setFillColor(CGColor(srgbRed: 0.97, green: 0.95, blue: 0.94, alpha: 1))
            ctx.fill(CGRect(x: halfW + 20, y: 20, width: halfW - 40, height: box.height - 40))

            // Centre divider — the spine fold
            ctx.setStrokeColor(CGColor(srgbRed: 0.85, green: 0.85, blue: 0.85, alpha: 1))
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: halfW, y: 20))
            ctx.addLine(to: CGPoint(x: halfW, y: box.height - 20))
            ctx.strokePath()

            // Sheet number, low contrast so it reads as a placeholder
            let label = "Sheet \(i + 1)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: CTFontCreateWithName("Helvetica" as CFString, 36, nil),
                .foregroundColor: CGColor(srgbRed: 0.55, green: 0.55, blue: 0.55, alpha: 1)
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: attrs))
            ctx.textPosition = CGPoint(x: 40, y: 40)
            CTLineDraw(line, ctx)

            ctx.endPage()
        }

        ctx.closePDF()
        return data as Data
    }
}
#endif
