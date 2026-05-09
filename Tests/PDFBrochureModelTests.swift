import XCTest
import PDFKit
import CoreGraphics

/// Tests for the `PDFBrochureModel` state machine and createBrochure paths.
/// The model lives at Sources/App/PDFBrochureModel.swift and is compiled
/// directly into this target (see project.yml) so we don't need
/// `@testable import`.
@MainActor
final class PDFBrochureModelTests: XCTestCase {

    // MARK: - Initial state

    func test_initialState_isDropPhase_withNothingLoaded() {
        let model = PDFBrochureModel()
        XCTAssertEqual(model.phase, .drop)
        XCTAssertNil(model.inputURL)
        XCTAssertNil(model.previewData)
        XCTAssertNil(model.lastResult)
        XCTAssertNil(model.lastOutputURL)
        XCTAssertEqual(model.status, "")
        XCTAssertFalse(model.statusIsError)
        XCTAssertFalse(model.isWorking)
    }

    // MARK: - adopt

    func test_adopt_movesToLayoutAndStoresURL() throws {
        let model = PDFBrochureModel()
        let url = try makeTestPDF(pages: 4)

        model.adopt(url: url)

        XCTAssertEqual(model.phase, .layout)
        XCTAssertEqual(model.inputURL, url)
    }

    func test_adopt_a4Input_picksA4PaperSize() throws {
        let model = PDFBrochureModel()
        let url = try makeTestPDF(pages: 4) // synthesised at A4 portrait

        model.adopt(url: url)

        XCTAssertEqual(model.paperSize, .a4)
    }

    func test_adopt_clearsStaleOutcomeFromPreviousRun() throws {
        let model = PDFBrochureModel()
        // Simulate a successful previous run sitting in the model.
        model._setForPreview(
            phase: .result,
            inputURL: URL(fileURLWithPath: "/tmp/old.pdf"),
            lastOutputURL: URL(fileURLWithPath: "/tmp/old-brochure.pdf"),
            status: "Saved old-brochure.pdf — …"
        )

        let url = try makeTestPDF(pages: 4)
        model.adopt(url: url)

        XCTAssertEqual(model.phase, .layout)
        XCTAssertNil(model.lastOutputURL, "stale Reveal URL must be dropped")
        XCTAssertEqual(model.status, "")
        XCTAssertFalse(model.statusIsError)
    }

    // MARK: - reset / backToLayout

    func test_reset_returnsToDropAndClearsEverything() throws {
        let model = PDFBrochureModel()
        let url = try makeTestPDF(pages: 4)
        model.adopt(url: url)
        model._setForPreview(
            phase: .result,
            inputURL: url,
            lastOutputURL: url,
            status: "Saved"
        )

        model.reset()

        XCTAssertEqual(model.phase, .drop)
        XCTAssertNil(model.inputURL)
        XCTAssertNil(model.previewData)
        XCTAssertNil(model.lastResult)
        XCTAssertNil(model.lastOutputURL)
        XCTAssertEqual(model.status, "")
        XCTAssertFalse(model.statusIsError)
    }

    func test_backToLayout_keepsLoadedPDFButClearsErrorState() throws {
        let model = PDFBrochureModel()
        let url = try makeTestPDF(pages: 4)
        // Pretend createBrochure failed and left the model on the error card.
        model._setForPreview(
            phase: .result,
            inputURL: url,
            paperSize: .a4,
            fitMode: .fit,
            status: "Error: something",
            statusIsError: true
        )

        model.backToLayout()

        XCTAssertEqual(model.phase, .layout)
        XCTAssertEqual(model.inputURL, url, "loaded PDF must be preserved")
        XCTAssertEqual(model.paperSize, .a4, "settings must be preserved")
        XCTAssertEqual(model.status, "")
        XCTAssertFalse(model.statusIsError)
    }

    // MARK: - createBrochure

    func test_createBrochure_success_movesToResultWithFile() async throws {
        let model = PDFBrochureModel()
        let url = try makeTestPDF(pages: 4)
        model.adopt(url: url)

        await model.createBrochure()

        XCTAssertEqual(model.phase, .result)
        XCTAssertFalse(model.isWorking, "should be done by the time `await` returns")
        XCTAssertFalse(model.statusIsError)
        let outURL = try XCTUnwrap(model.lastOutputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outURL.path),
                      "the brochure file should actually exist on disk")
        XCTAssertEqual(outURL.lastPathComponent.hasSuffix("-brochure.pdf"), true)
        XCTAssertNotNil(model.lastResult)
    }

    func test_createBrochure_failure_clearsLastOutputURLAndFlagsError() async throws {
        let model = PDFBrochureModel()
        // Bogus inputURL: BookletMaker.makeBooklet will throw cannotOpen.
        // Pre-seed lastOutputURL with a stale value to verify it gets dropped.
        model._setForPreview(
            phase: .layout,
            inputURL: URL(fileURLWithPath: "/nonexistent/never-was.pdf"),
            lastOutputURL: URL(fileURLWithPath: "/tmp/stale-brochure.pdf")
        )

        await model.createBrochure()

        XCTAssertEqual(model.phase, .result, "must still transition so user sees the error card")
        XCTAssertTrue(model.statusIsError)
        XCTAssertNil(model.lastOutputURL,
                     "must drop the stale Reveal target so the error card doesn't offer a misleading button")
        XCTAssertTrue(model.status.hasPrefix("Error:"))
    }

    func test_createBrochure_withNoInputURL_isANoOp() async {
        let model = PDFBrochureModel()
        // Default state: inputURL == nil. createBrochure() guards against this.

        await model.createBrochure()

        XCTAssertEqual(model.phase, .drop, "must NOT have transitioned to .result")
        XCTAssertNil(model.lastOutputURL)
        XCTAssertEqual(model.status, "")
    }

    // MARK: - helpers

    /// Per-test temp dir, removed in tearDown.
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFBrochureModelTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    /// Synthesises a `pages`-page A4-portrait PDF on disk and returns its URL.
    private func makeTestPDF(pages: Int) throws -> URL {
        let dir = try makeTempDir()
        let url = dir.appendingPathComponent("input-\(pages)p.pdf")

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data) else {
            throw NSError(domain: "Test", code: 1)
        }
        var box = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 portrait
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw NSError(domain: "Test", code: 2)
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
