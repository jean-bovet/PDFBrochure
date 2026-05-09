import SwiftUI
import PDFKit

@MainActor
final class PDFBrochureModel: ObservableObject {
    @Published var inputURL: URL?
    @Published var paperSize: PaperSize = .auto
    @Published var fitMode: FitMode = .fit

    @Published private(set) var previewData: Data?
    @Published private(set) var lastResult: BookletMaker.Result?
    @Published private(set) var lastOutputURL: URL?
    @Published private(set) var status: String = ""
    @Published private(set) var statusIsError = false
    @Published private(set) var isWorking = false

    func adopt(url: URL) {
        inputURL = url
        lastOutputURL = nil
        status = ""
        statusIsError = false
        // Pick a sensible default sheet size from the input.
        if let doc = PDFDocument(url: url), let first = doc.page(at: 0) {
            paperSize = BookletMaker.smartDefaultPaper(forFirstPageSize: first.bounds(for: .mediaBox).size)
        } else {
            paperSize = .auto
        }
        fitMode = .fit
        Task { await regeneratePreview() }
    }

    func reset() {
        inputURL = nil
        previewData = nil
        lastResult = nil
        lastOutputURL = nil
        status = ""
        statusIsError = false
    }

    /// Re-renders the preview off the main actor whenever options change.
    func regeneratePreview() async {
        guard let url = inputURL else { return }
        let paper = paperSize
        let fit = fitMode
        do {
            let (data, result) = try await Task.detached(priority: .userInitiated) {
                try BookletMaker.makeBookletData(input: url, paperSize: paper, fitMode: fit)
            }.value
            self.previewData = data
            self.lastResult = result
        } catch {
            self.previewData = nil
            self.status = "Preview error: \(error.localizedDescription)"
            self.statusIsError = true
        }
    }

    /// One-click create: writes `<input>-brochure.pdf` next to the source.
    /// If that name is already taken, suffixes `-2`, `-3`, … until free —
    /// we never silently overwrite an existing file.
    func createBrochure() async {
        guard let inURL = inputURL else { return }
        isWorking = true
        defer { isWorking = false }

        let outURL = BookletMaker.uniqueOutputURL(forInput: inURL)
        let paper = paperSize
        let fit = fitMode

        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try BookletMaker.makeBooklet(input: inURL, output: outURL, paperSize: paper, fitMode: fit)
            }.value
            lastResult = result
            lastOutputURL = outURL
            status = "Saved \(outURL.lastPathComponent) — \(result.outputPages) sheet sides at \(Int(result.sheetSize.width))×\(Int(result.sheetSize.height)) pt."
            statusIsError = false
        } catch {
            // Drop the stale Reveal-in-Finder target — its URL belongs to a
            // previous successful save, not this failed attempt.
            lastOutputURL = nil
            status = "Error: \(error.localizedDescription)"
            statusIsError = true
        }
    }

    #if DEBUG
    /// For SwiftUI #Preview blocks only. Bypasses adopt → render so previews
    /// can show LayoutView in different states without async I/O.
    func _setForPreview(
        inputURL: URL?,
        paperSize: PaperSize = .auto,
        fitMode: FitMode = .fit,
        previewData: Data? = nil,
        lastResult: BookletMaker.Result? = nil,
        lastOutputURL: URL? = nil,
        status: String = "",
        statusIsError: Bool = false
    ) {
        self.inputURL = inputURL
        self.paperSize = paperSize
        self.fitMode = fitMode
        self.previewData = previewData
        self.lastResult = lastResult
        self.lastOutputURL = lastOutputURL
        self.status = status
        self.statusIsError = statusIsError
    }
    #endif
}
