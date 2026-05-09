import SwiftUI
import AppKit

/// Step 2: configure layout, see live preview, write the brochure.
struct LayoutView: View {
    @EnvironmentObject var model: PDFBrochureModel

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
                        .foregroundStyle(model.statusIsError ? .red : .green)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let out = model.lastOutputURL {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([out])
                    }
                }
                Button {
                    Task { await model.createBrochure() }
                } label: {
                    if model.isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Create Brochure", systemImage: "book.closed.fill")
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

#if DEBUG
#Preview("LayoutView — fresh load") {
    let model = PDFBrochureModel()
    model._setForPreview(
        inputURL: URL(fileURLWithPath: "/tmp/Programme 17 mai (A5).pdf"),
        paperSize: .auto,
        fitMode: .fit,
        previewData: PreviewSamples.tinyBookletPDF(pages: 2),
        lastResult: BookletMaker.Result(
            inputPages: 4,
            outputPages: 2,
            sheetSize: CGSize(width: 841.89, height: 595.276)
        )
    )
    return LayoutView()
        .environmentObject(model)
        .frame(width: 760, height: 620)
}

#Preview("LayoutView — after successful save") {
    let model = PDFBrochureModel()
    model._setForPreview(
        inputURL: URL(fileURLWithPath: "/tmp/Programme 17 mai (A5).pdf"),
        paperSize: .a4,
        fitMode: .fit,
        previewData: PreviewSamples.tinyBookletPDF(pages: 2),
        lastResult: BookletMaker.Result(
            inputPages: 4,
            outputPages: 2,
            sheetSize: CGSize(width: 841.89, height: 595.276)
        ),
        lastOutputURL: URL(fileURLWithPath: "/tmp/Programme 17 mai (A5)-brochure.pdf"),
        status: "Saved Programme 17 mai (A5)-brochure.pdf — 2 sheet sides at 841×595 pt.",
        statusIsError: false
    )
    return LayoutView()
        .environmentObject(model)
        .frame(width: 760, height: 620)
}

#Preview("LayoutView — error") {
    let model = PDFBrochureModel()
    model._setForPreview(
        inputURL: URL(fileURLWithPath: "/tmp/broken.pdf"),
        previewData: PreviewSamples.tinyBookletPDF(pages: 2),
        lastResult: BookletMaker.Result(
            inputPages: 4,
            outputPages: 2,
            sheetSize: CGSize(width: 841.89, height: 595.276)
        ),
        status: "Error: Could not create the output PDF.",
        statusIsError: true
    )
    return LayoutView()
        .environmentObject(model)
        .frame(width: 760, height: 620)
}
#endif
