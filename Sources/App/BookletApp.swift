import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import AppKit

// MARK: - App entry point

@main
struct BookletApp: App {
    @StateObject private var model = BookletModel()

    var body: some Scene {
        WindowGroup("PDF → Booklet") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 620)
        }
        .windowResizability(.contentSize)
    }
}

// MARK: - View model

@MainActor
final class BookletModel: ObservableObject {
    @Published var inputURL: URL?
    @Published var paperSize: PaperSize = .auto
    @Published var fitMode: FitMode = .fit

    @Published private(set) var previewData: Data?
    @Published private(set) var lastResult: BookletMaker.Result?
    @Published private(set) var lastOutputURL: URL?
    @Published private(set) var status: String = ""
    @Published private(set) var isWorking = false

    func adopt(url: URL) {
        inputURL = url
        lastOutputURL = nil
        status = ""
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
        }
    }

    /// One-click create: writes `<input>-booklet.pdf` next to the source.
    /// If that name is already taken, suffixes `-2`, `-3`, … until free —
    /// we never silently overwrite an existing file.
    func createBooklet() async {
        guard let inURL = inputURL else { return }
        isWorking = true
        defer { isWorking = false }

        let outURL = Self.uniqueOutputURL(forInput: inURL)
        let paper = paperSize
        let fit = fitMode

        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try BookletMaker.makeBooklet(input: inURL, output: outURL, paperSize: paper, fitMode: fit)
            }.value
            lastResult = result
            lastOutputURL = outURL
            status = "Saved \(outURL.lastPathComponent) — \(result.outputPages) sheet sides at \(Int(result.sheetSize.width))×\(Int(result.sheetSize.height)) pt."
        } catch {
            status = "Error: \(error.localizedDescription)"
        }
    }

    /// Returns a sibling URL of `inputURL` named `<base>-booklet.pdf`, or
    /// `<base>-booklet-2.pdf`, `-3`, … if earlier candidates already exist.
    /// The check is plain `FileManager.fileExists` — there's an inherent TOCTOU
    /// gap between picking the name and writing, but the disambiguation
    /// covers the realistic case (creating two booklets in a row).
    static func uniqueOutputURL(forInput inputURL: URL) -> URL {
        let dir = inputURL.deletingLastPathComponent()
        let base = inputURL.deletingPathExtension().lastPathComponent + "-booklet"
        let fm = FileManager.default

        let first = dir.appendingPathComponent(base + ".pdf")
        if !fm.fileExists(atPath: first.path) { return first }

        var n = 2
        while true {
            let candidate = dir.appendingPathComponent("\(base)-\(n).pdf")
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}

// MARK: - Root navigation

struct RootView: View {
    @EnvironmentObject var model: BookletModel

    var body: some View {
        ZStack {
            if model.inputURL == nil {
                DropView()
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            } else {
                LayoutView()
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.inputURL)
    }
}

// MARK: - Step 1: drop a PDF

struct DropView: View {
    @EnvironmentObject var model: BookletModel
    @State private var isTargeted = false
    @State private var rejectMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)

            Text("PDF → Booklet")
                .font(.largeTitle.bold())

            Text("Drop a PDF to begin")
                .font(.title3)
                .foregroundStyle(.secondary)

            DropZone(isTargeted: isTargeted, onClick: pickFile)
                .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
                .frame(maxWidth: 520, maxHeight: 320)

            if let msg = rejectMessage {
                Text(msg)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            adopt(url)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            DispatchQueue.main.async {
                guard let url else {
                    rejectMessage = "Could not read the dropped item."
                    return
                }
                adopt(url)
            }
        }
        return true
    }

    private func adopt(_ url: URL) {
        guard url.pathExtension.lowercased() == "pdf" else {
            rejectMessage = "Please drop a PDF file."
            return
        }
        rejectMessage = nil
        model.adopt(url: url)
    }
}

private struct DropZone: View {
    let isTargeted: Bool
    let onClick: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: isTargeted ? 3 : 2, dash: [10, 6])
                )
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.6))
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isTargeted ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.05))
                )

            VStack(spacing: 14) {
                Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "doc.richtext")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                Text(isTargeted ? "Release to load" : "Drop a PDF here")
                    .font(.title3)
                Text("or click to choose a file")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: onClick)
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }
}

// MARK: - Step 2: configure, preview, create

struct LayoutView: View {
    @EnvironmentObject var model: BookletModel

    var body: some View {
        VStack(spacing: 0) {
            // Header bar with back button and source filename.
            HStack(spacing: 12) {
                Button {
                    model.reset()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)

                if let url = model.inputURL {
                    Text(url.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)

            // Layout options.
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sheet size").font(.subheadline).foregroundStyle(.secondary)
                    Picker("", selection: $model.paperSize) {
                        ForEach(PaperSize.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Page placement").font(.subheadline).foregroundStyle(.secondary)
                    Picker("", selection: $model.fitMode) {
                        ForEach(FitMode.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 320)
                }

                Spacer()
            }
            .padding(20)
            .onChange(of: model.paperSize) { _ in Task { await model.regeneratePreview() } }
            .onChange(of: model.fitMode) { _ in Task { await model.regeneratePreview() } }

            Divider()

            // Live preview.
            ZStack {
                if let data = model.previewData {
                    PDFPreview(data: data)
                } else {
                    ProgressView("Rendering preview…")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .underPageBackgroundColor))

            Divider()

            // Footer: status + create button.
            HStack(spacing: 12) {
                if let r = model.lastResult {
                    Text("\(r.inputPages) input pages → \(r.outputPages) sheet sides · \(Int(r.sheetSize.width))×\(Int(r.sheetSize.height)) pt")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !model.status.isEmpty {
                    Text(model.status)
                        .font(.callout)
                        .foregroundStyle(model.lastOutputURL == nil ? .red : .green)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let out = model.lastOutputURL {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([out])
                    }
                }
                Button {
                    Task { await model.createBooklet() }
                } label: {
                    if model.isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Create Booklet", systemImage: "book.closed.fill")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isWorking || model.previewData == nil)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }
}

// MARK: - PDF preview wrapper

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
