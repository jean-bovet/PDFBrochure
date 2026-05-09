import XCTest
import PDFKit
import CoreGraphics

/// Unit tests for the imposition layer. The test target compiles
/// `Sources/Imposition/BookletMaker.swift` directly (see project.yml), so the
/// tests don't need `@testable import` and don't require a host app — they
/// run as a pure logic bundle.
final class BookletMakerTests: XCTestCase {

    // MARK: - PaperSize

    func test_paperSize_auto_hasNoLandscapePoints() {
        XCTAssertNil(PaperSize.auto.landscapePoints)
    }

    func test_paperSize_a4_isLandscapeAndApproximatelyA4() {
        let pts = PaperSize.a4.landscapePoints
        XCTAssertNotNil(pts)
        guard let pts else { return }
        XCTAssertGreaterThan(pts.width, pts.height, "should be landscape")
        XCTAssertEqual(pts.width, 841.89, accuracy: 0.01)
        XCTAssertEqual(pts.height, 595.276, accuracy: 0.01)
    }

    func test_paperSize_allCasesExceptAutoHaveLandscapePoints() {
        for size in PaperSize.allCases where size != .auto {
            XCTAssertNotNil(size.landscapePoints, "\(size) should have landscape points")
            if let p = size.landscapePoints {
                XCTAssertGreaterThan(p.width, p.height, "\(size) must be landscape")
            }
        }
    }

    func test_paperSize_labelsAreNonEmpty() {
        for size in PaperSize.allCases {
            XCTAssertFalse(size.label.isEmpty, "\(size) should have a label")
        }
    }

    // MARK: - smartDefaultPaper

    func test_smartDefaultPaper_a4_returnsA4() {
        let a4 = CGSize(width: 595.276, height: 841.89)
        XCTAssertEqual(BookletMaker.smartDefaultPaper(forFirstPageSize: a4), .a4)
    }

    func test_smartDefaultPaper_a4Landscape_alsoReturnsA4() {
        // The heuristic uses area, so orientation doesn't matter.
        let a4Landscape = CGSize(width: 841.89, height: 595.276)
        XCTAssertEqual(BookletMaker.smartDefaultPaper(forFirstPageSize: a4Landscape), .a4)
    }

    func test_smartDefaultPaper_a5_returnsAuto() {
        let a5 = CGSize(width: 419.528, height: 595.276)
        XCTAssertEqual(BookletMaker.smartDefaultPaper(forFirstPageSize: a5), .auto)
    }

    func test_smartDefaultPaper_usLetter_returnsAuto() {
        // Close to A4 but ~3% off in area; should still fall outside the 5% band.
        let letter = CGSize(width: 612, height: 792)
        XCTAssertEqual(BookletMaker.smartDefaultPaper(forFirstPageSize: letter), .auto)
    }

    func test_smartDefaultPaper_a3_returnsAuto() {
        let a3 = CGSize(width: 841.89, height: 1190.55)
        XCTAssertEqual(BookletMaker.smartDefaultPaper(forFirstPageSize: a3), .auto)
    }

    // MARK: - uniqueOutputURL

    func test_uniqueOutputURL_noConflict_usesBaseName() throws {
        let dir = try makeTempDir()
        let input = dir.appendingPathComponent("doc.pdf")

        let result = BookletMaker.uniqueOutputURL(forInput: input)

        XCTAssertEqual(result.lastPathComponent, "doc-brochure.pdf")
        XCTAssertEqual(result.deletingLastPathComponent().path, dir.path)
    }

    func test_uniqueOutputURL_existingFile_appendsTwo() throws {
        let dir = try makeTempDir()
        let input = dir.appendingPathComponent("doc.pdf")
        try Data().write(to: dir.appendingPathComponent("doc-brochure.pdf"))

        let result = BookletMaker.uniqueOutputURL(forInput: input)

        XCTAssertEqual(result.lastPathComponent, "doc-brochure-2.pdf")
    }

    func test_uniqueOutputURL_threeExisting_returnsFour() throws {
        let dir = try makeTempDir()
        let input = dir.appendingPathComponent("doc.pdf")
        try Data().write(to: dir.appendingPathComponent("doc-brochure.pdf"))
        try Data().write(to: dir.appendingPathComponent("doc-brochure-2.pdf"))
        try Data().write(to: dir.appendingPathComponent("doc-brochure-3.pdf"))

        let result = BookletMaker.uniqueOutputURL(forInput: input)

        XCTAssertEqual(result.lastPathComponent, "doc-brochure-4.pdf")
    }

    func test_uniqueOutputURL_gapsAreFilled() throws {
        // If "doc-brochure.pdf" exists but "doc-brochure-2.pdf" does NOT, the
        // helper picks 2 (next free, not next-after-highest).
        let dir = try makeTempDir()
        let input = dir.appendingPathComponent("doc.pdf")
        try Data().write(to: dir.appendingPathComponent("doc-brochure.pdf"))
        try Data().write(to: dir.appendingPathComponent("doc-brochure-5.pdf"))

        let result = BookletMaker.uniqueOutputURL(forInput: input)

        XCTAssertEqual(result.lastPathComponent, "doc-brochure-2.pdf")
    }

    func test_uniqueOutputURL_customSuffix() throws {
        let dir = try makeTempDir()
        let input = dir.appendingPathComponent("doc.pdf")

        let result = BookletMaker.uniqueOutputURL(forInput: input, suffix: "imposed")

        XCTAssertEqual(result.lastPathComponent, "doc-imposed.pdf")
    }

    func test_uniqueOutputURL_filenameWithSpacesPreserved() throws {
        let dir = try makeTempDir()
        let input = dir.appendingPathComponent("Programme 17 mai.pdf")

        let result = BookletMaker.uniqueOutputURL(forInput: input)

        XCTAssertEqual(result.lastPathComponent, "Programme 17 mai-brochure.pdf")
    }

    // MARK: - makeBookletData (page counts and sheet sizing)

    func test_makeBookletData_4pages_produces2sheetSides() throws {
        let url = try makeTestPDF(pages: 4)

        let (data, result) = try BookletMaker.makeBookletData(
            input: url, paperSize: .auto, fitMode: .fit
        )

        XCTAssertEqual(result.inputPages, 4)
        XCTAssertEqual(result.outputPages, 2)
        let doc = PDFDocument(data: data)
        XCTAssertEqual(doc?.pageCount, 2)
    }

    func test_makeBookletData_5pages_padsTo8andProduces4sheetSides() throws {
        let url = try makeTestPDF(pages: 5)

        let (data, result) = try BookletMaker.makeBookletData(
            input: url, paperSize: .auto, fitMode: .fit
        )

        XCTAssertEqual(result.inputPages, 5)
        XCTAssertEqual(result.outputPages, 4) // padded=8, sheets=2, sides=4
        let doc = PDFDocument(data: data)
        XCTAssertEqual(doc?.pageCount, 4)
    }

    func test_makeBookletData_8pages_produces4sheetSides() throws {
        let url = try makeTestPDF(pages: 8)

        let (_, result) = try BookletMaker.makeBookletData(
            input: url, paperSize: .auto, fitMode: .fit
        )

        XCTAssertEqual(result.inputPages, 8)
        XCTAssertEqual(result.outputPages, 4)
    }

    func test_makeBookletData_1page_padsTo4andProduces2sheetSides() throws {
        let url = try makeTestPDF(pages: 1)

        let (_, result) = try BookletMaker.makeBookletData(
            input: url, paperSize: .auto, fitMode: .fit
        )

        XCTAssertEqual(result.inputPages, 1)
        XCTAssertEqual(result.outputPages, 2)
    }

    func test_makeBookletData_a4PaperSize_producesA4LandscapeSheets() throws {
        let url = try makeTestPDF(pages: 4)

        let (data, result) = try BookletMaker.makeBookletData(
            input: url, paperSize: .a4, fitMode: .fit
        )

        XCTAssertEqual(result.sheetSize.width, 841.89, accuracy: 0.01)
        XCTAssertEqual(result.sheetSize.height, 595.276, accuracy: 0.01)
        let doc = PDFDocument(data: data)
        let firstBox = doc?.page(at: 0)?.bounds(for: .mediaBox)
        XCTAssertEqual(firstBox?.width ?? 0, 841.89, accuracy: 0.01)
        XCTAssertEqual(firstBox?.height ?? 0, 595.276, accuracy: 0.01)
    }

    func test_makeBookletData_autoPaperSize_doublesInputWidth() throws {
        // Test PDF is A4 portrait (595×842). Auto should give 1190×842.
        let url = try makeTestPDF(pages: 4)

        let (_, result) = try BookletMaker.makeBookletData(
            input: url, paperSize: .auto, fitMode: .fit
        )

        XCTAssertEqual(result.sheetSize.width, 1190, accuracy: 1.0)
        XCTAssertEqual(result.sheetSize.height, 842, accuracy: 1.0)
    }

    // MARK: - makeBookletData errors

    func test_makeBookletData_nonexistentInput_throwsCannotOpen() {
        let bogus = URL(fileURLWithPath: "/nonexistent/never-was.pdf")
        XCTAssertThrowsError(
            try BookletMaker.makeBookletData(input: bogus, paperSize: .auto, fitMode: .fit)
        ) { error in
            guard let e = error as? BookletError else {
                XCTFail("expected BookletError, got \(error)")
                return
            }
            XCTAssertEqual(e, BookletError.cannotOpen)
        }
    }

    // MARK: - makeBooklet (file output) round-trips through makeBookletData

    func test_makeBooklet_writesFileWithSamePageCount() throws {
        let url = try makeTestPDF(pages: 4)
        let dir = try makeTempDir()
        let outURL = dir.appendingPathComponent("out.pdf")

        let result = try BookletMaker.makeBooklet(
            input: url, output: outURL, paperSize: .a4, fitMode: .fit
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outURL.path))
        XCTAssertEqual(result.outputPages, 2)
        let doc = PDFDocument(url: outURL)
        XCTAssertEqual(doc?.pageCount, 2)
    }

    // MARK: - imposition page order
    //
    // For an N-page document padded up to a multiple of 4, sheet k (1-indexed)
    // holds:
    //   outer side: page (N − 2k + 2) | page (2k − 1)
    //   inner side: page (2k)         | page (N − 2k + 1)
    // We verify this by giving every input page a distinct solid-colour
    // background, rendering the output sheets to a bitmap, and sampling a
    // centre pixel from each half of each sheet. Auto paper size is used so
    // each input page fills its slot edge-to-edge with no scaling/letterbox,
    // making centre-pixel sampling unambiguous.

    func test_makeBookletData_4page_correctImpositionOrder() throws {
        // page 1=red, 2=green, 3=blue, 4=yellow
        let colors: [SamplePixel] = [.red, .green, .blue, .yellow]
        let input = try makeColoredTestPDF(perPageColors: colors)

        let (data, _) = try BookletMaker.makeBookletData(
            input: input, paperSize: .auto, fitMode: .fit
        )
        let doc = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(doc.pageCount, 2)

        // Sheet 1 outer (output page 0): left=page 4, right=page 1
        let outer = try XCTUnwrap(doc.page(at: 0))
        assertCenterColor(of: outer, half: .left,  matches: .yellow, "outer left  → page 4 (yellow)")
        assertCenterColor(of: outer, half: .right, matches: .red,    "outer right → page 1 (red)")

        // Sheet 1 inner (output page 1): left=page 2, right=page 3
        let inner = try XCTUnwrap(doc.page(at: 1))
        assertCenterColor(of: inner, half: .left,  matches: .green,  "inner left  → page 2 (green)")
        assertCenterColor(of: inner, half: .right, matches: .blue,   "inner right → page 3 (blue)")
    }

    func test_makeBookletData_8page_correctImpositionOrder() throws {
        // 8 distinct colours, one per input page.
        let colors: [SamplePixel] = [.red, .green, .blue, .yellow, .magenta, .cyan, .orange, .lime]
        let input = try makeColoredTestPDF(perPageColors: colors)

        let (data, _) = try BookletMaker.makeBookletData(
            input: input, paperSize: .auto, fitMode: .fit
        )
        let doc = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(doc.pageCount, 4)

        // For N=8: sheet 1: outer (8|1), inner (2|7); sheet 2: outer (6|3), inner (4|5)
        // (Output PDF page index → sheet side: 0=s1.outer, 1=s1.inner, 2=s2.outer, 3=s2.inner)
        let p = try (0..<4).map { try XCTUnwrap(doc.page(at: $0)) }

        assertCenterColor(of: p[0], half: .left,  matches: colors[7], "s1 outer L → input p8")
        assertCenterColor(of: p[0], half: .right, matches: colors[0], "s1 outer R → input p1")
        assertCenterColor(of: p[1], half: .left,  matches: colors[1], "s1 inner L → input p2")
        assertCenterColor(of: p[1], half: .right, matches: colors[6], "s1 inner R → input p7")
        assertCenterColor(of: p[2], half: .left,  matches: colors[5], "s2 outer L → input p6")
        assertCenterColor(of: p[2], half: .right, matches: colors[2], "s2 outer R → input p3")
        assertCenterColor(of: p[3], half: .left,  matches: colors[3], "s2 inner L → input p4")
        assertCenterColor(of: p[3], half: .right, matches: colors[4], "s2 inner R → input p5")
    }

    func test_makeBookletData_5page_paddedTo8_blankSlotsAreWhite() throws {
        // For N=5, padded=8. The padded indices 6, 7, 8 (1-indexed) reference
        // pages that don't exist and should render as the white sheet
        // background. Using sheet imposition formula:
        //   sheet 1 outer: 8|1 → blank | red
        //   sheet 1 inner: 2 | 7 → green | blank
        //   sheet 2 outer: 6 | 3 → blank | blue
        //   sheet 2 inner: 4 | 5 → yellow | magenta
        let colors: [SamplePixel] = [.red, .green, .blue, .yellow, .magenta]
        let input = try makeColoredTestPDF(perPageColors: colors)

        let (data, _) = try BookletMaker.makeBookletData(
            input: input, paperSize: .auto, fitMode: .fit
        )
        let doc = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(doc.pageCount, 4)

        let p = try (0..<4).map { try XCTUnwrap(doc.page(at: $0)) }

        assertCenterColor(of: p[0], half: .left,  matches: .white,    "s1 outer L → blank (page 8 doesn't exist)")
        assertCenterColor(of: p[0], half: .right, matches: colors[0], "s1 outer R → input p1")
        assertCenterColor(of: p[1], half: .left,  matches: colors[1], "s1 inner L → input p2")
        assertCenterColor(of: p[1], half: .right, matches: .white,    "s1 inner R → blank (page 7)")
        assertCenterColor(of: p[2], half: .left,  matches: .white,    "s2 outer L → blank (page 6)")
        assertCenterColor(of: p[2], half: .right, matches: colors[2], "s2 outer R → input p3")
        assertCenterColor(of: p[3], half: .left,  matches: colors[3], "s2 inner L → input p4")
        assertCenterColor(of: p[3], half: .right, matches: colors[4], "s2 inner R → input p5")
    }

    // MARK: - helpers

    /// Per-test temp dir, removed in tearDown.
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFBrochureTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    /// Synthesises a `pages`-page A4-portrait PDF on disk and returns its URL.
    /// Used as input to `makeBookletData` / `makeBooklet`.
    private func makeTestPDF(pages: Int) throws -> URL {
        let dir = try makeTempDir()
        let url = dir.appendingPathComponent("input-\(pages)p.pdf")

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "no consumer"])
        }
        var box = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 portrait
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "no context"])
        }
        for _ in 0..<pages {
            ctx.beginPage(mediaBox: &box)
            ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(box)
            ctx.endPage()
        }
        ctx.closePDF()

        try (data as Data).write(to: url)
        return url
    }
}

// MARK: - Page-order test helpers

/// Distinct solid colours used to tag each input page so we can identify
/// where it ends up on the imposed sheet by sampling a centre pixel.
enum SamplePixel: Equatable {
    case red, green, blue, yellow, magenta, cyan, orange, lime, white

    var rgb: (r: UInt8, g: UInt8, b: UInt8) {
        switch self {
        case .red:     return (255,   0,   0)
        case .green:   return (  0, 200,   0) // not pure green to dodge anti-alias confusion with cyan
        case .blue:    return (  0,   0, 255)
        case .yellow:  return (255, 240,   0)
        case .magenta: return (240,   0, 240)
        case .cyan:    return (  0, 200, 240)
        case .orange:  return (240, 140,   0)
        case .lime:    return (140, 240,  60)
        case .white:   return (255, 255, 255)
        }
    }

    var cgColor: CGColor {
        let (r, g, b) = rgb
        return CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    /// Match within ±20 per channel — generous enough to absorb PDF
    /// rasterisation rounding while still distinguishing every entry above.
    func approximatelyEquals(_ rgb: (r: UInt8, g: UInt8, b: UInt8)) -> Bool {
        func near(_ a: UInt8, _ b: UInt8) -> Bool { abs(Int(a) - Int(b)) <= 20 }
        return near(self.rgb.r, rgb.r) && near(self.rgb.g, rgb.g) && near(self.rgb.b, rgb.b)
    }
}

enum Half { case left, right }

extension BookletMakerTests {

    /// Synthesises a PDF where page i has its background filled with
    /// `perPageColors[i]`. Returns the file URL.
    fileprivate func makeColoredTestPDF(perPageColors colors: [SamplePixel]) throws -> URL {
        let dir = try makeTempDir()
        let url = dir.appendingPathComponent("colored-\(colors.count)p.pdf")
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else {
            throw NSError(domain: "Test", code: 10)
        }
        var box = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 portrait
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw NSError(domain: "Test", code: 11)
        }
        for color in colors {
            ctx.beginPage(mediaBox: &box)
            ctx.setFillColor(color.cgColor)
            ctx.fill(box)
            ctx.endPage()
        }
        ctx.closePDF()
        try (data as Data).write(to: url)
        return url
    }

    /// Renders a PDFPage to a low-res RGB bitmap and reads the pixel at the
    /// centre of the chosen half-sheet. Used to verify which input page
    /// landed in each imposition slot.
    fileprivate func sampleCenterPixel(of page: PDFPage, half: Half) -> (r: UInt8, g: UInt8, b: UInt8) {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 0.1                             // 0.1 pt → pixel
        let pxW = Int(bounds.width * scale)
        let pxH = Int(bounds.height * scale)
        let bytesPerRow = pxW * 4
        var buffer = [UInt8](repeating: 0, count: pxH * bytesPerRow)

        let cs = CGColorSpaceCreateDeviceRGB()
        let bmpInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let ctx = CGContext(
            data: &buffer,
            width: pxW,
            height: pxH,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: cs,
            bitmapInfo: bmpInfo.rawValue
        )!

        // White background — anywhere the page doesn't cover (e.g. blank slot)
        // will sample as white.
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: pxW, height: pxH))

        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)

        // Sample at the geometric centre of the chosen half. Page coordinates
        // are bottom-left origin; CGContext's bitmap is also bottom-left after
        // we scaleBy, so the pixel index is (x, h-1-y) flipped.
        let centerXPage: CGFloat = (half == .left)
            ? bounds.width * 0.25
            : bounds.width * 0.75
        let centerYPage: CGFloat = bounds.height * 0.5

        let px = Int(centerXPage * scale)
        let pyFromBottom = Int(centerYPage * scale)
        let pyFromTop = pxH - 1 - pyFromBottom
        let i = pyFromTop * bytesPerRow + px * 4
        return (buffer[i], buffer[i + 1], buffer[i + 2])
    }

    fileprivate func assertCenterColor(
        of page: PDFPage,
        half: Half,
        matches expected: SamplePixel,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let actual = sampleCenterPixel(of: page, half: half)
        XCTAssertTrue(
            expected.approximatelyEquals(actual),
            "\(message): expected \(expected) ~= \(expected.rgb) but got rgb=\(actual)",
            file: file,
            line: line
        )
    }
}

// `BookletError: Equatable` is needed for XCTAssertEqual above. The enum has
// no associated values so the synthesised conformance is trivial.
extension BookletError: Equatable {}
