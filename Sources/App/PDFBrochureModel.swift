import Foundation
import Combine
import PDFKit

@MainActor
final class PDFBrochureModel: ObservableObject {

    /// The three-screen flow: drop → layout (configure + preview) → result
    /// (spinner + outcome). RootView switches on this directly.
    enum Phase: Equatable {
        case drop
        case layout
        case result
    }

    @Published private(set) var phase: Phase = .drop

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
        phase = .layout
        Task { await regeneratePreview() }
    }

    /// Full reset back to the drop view — used by both the LayoutView "Back"
    /// button and the ResultView "Make another brochure" / "Start over" buttons.
    func reset() {
        inputURL = nil
        previewData = nil
        lastResult = nil
        lastOutputURL = nil
        status = ""
        statusIsError = false
        phase = .drop
    }

    /// "Try again" from the result screen on error: keep the loaded PDF and
    /// previewed settings, drop the error message, return to layout.
    func backToLayout() {
        status = ""
        statusIsError = false
        phase = .layout
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
    /// we never silently overwrite an existing file. Switches to the result
    /// phase before doing the work so the user sees the spinner immediately.
    func createBrochure() async {
        guard let inURL = inputURL else { return }
        phase = .result
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
    /// can show any screen in any state without async I/O.
    func _setForPreview(
        phase: Phase = .layout,
        inputURL: URL?,
        paperSize: PaperSize = .auto,
        fitMode: FitMode = .fit,
        previewData: Data? = nil,
        lastResult: BookletMaker.Result? = nil,
        lastOutputURL: URL? = nil,
        status: String = "",
        statusIsError: Bool = false,
        isWorking: Bool = false
    ) {
        self.phase = phase
        self.inputURL = inputURL
        self.paperSize = paperSize
        self.fitMode = fitMode
        self.previewData = previewData
        self.lastResult = lastResult
        self.lastOutputURL = lastOutputURL
        self.status = status
        self.statusIsError = statusIsError
        self.isWorking = isWorking
    }
    #endif
}
