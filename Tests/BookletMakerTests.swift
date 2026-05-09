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

// `BookletError: Equatable` is needed for XCTAssertEqual above. The enum has
// no associated values so the synthesised conformance is trivial.
extension BookletError: Equatable {}
