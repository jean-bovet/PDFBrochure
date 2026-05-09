import SwiftUI
import AppKit

/// Step 3: spinner while `createBrochure` runs, then either a success card
/// (Reveal in Finder / Make another brochure) or an error card (Try again /
/// Start over).
struct ResultView: View {
    @EnvironmentObject var model: PDFBrochureModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            content
                .frame(maxWidth: 520)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var content: some View {
        if model.isWorking {
            workingView
        } else if model.statusIsError {
            errorView
        } else if let outURL = model.lastOutputURL {
            successView(outURL: outURL)
        } else {
            // Shouldn't happen — phase = .result only after createBrochure() runs.
            // Guard against weird states by giving the user a way back.
            fallbackView
        }
    }

    // MARK: - States

    private var workingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text("Generating brochure…")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func successView(outURL: URL) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(.green)

            VStack(spacing: 6) {
                Text("Brochure created")
                    .font(.title2.bold())
                Text(outURL.lastPathComponent)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let r = model.lastResult {
                    Text("\(r.outputPages) sheet sides · \(Int(r.sheetSize.width))×\(Int(r.sheetSize.height)) pt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button("Make another brochure") {
                    model.reset()
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([outURL])
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
    }

    private var errorView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(.red)

            VStack(spacing: 6) {
                Text("Could not create the brochure")
                    .font(.title2.bold())
                Text(model.status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button("Start over") {
                    model.reset()
                }
                Button("Try again") {
                    model.backToLayout()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
    }

    private var fallbackView: some View {
        VStack(spacing: 20) {
            Text("Nothing to show here yet.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Start over") { model.reset() }
        }
    }
}

#if DEBUG
#Preview("ResultView — working") {
    let model = PDFBrochureModel()
    model._setForPreview(
        phase: .result,
        inputURL: URL(fileURLWithPath: "/tmp/Programme 17 mai.pdf"),
        isWorking: true
    )
    return ResultView()
        .environmentObject(model)
        .frame(width: 760, height: 620)
}

#Preview("ResultView — success") {
    let model = PDFBrochureModel()
    model._setForPreview(
        phase: .result,
        inputURL: URL(fileURLWithPath: "/tmp/Programme 17 mai.pdf"),
        lastResult: BookletMaker.Result(
            inputPages: 4,
            outputPages: 2,
            sheetSize: CGSize(width: 841.89, height: 595.276)
        ),
        lastOutputURL: URL(fileURLWithPath: "/tmp/Programme 17 mai-brochure.pdf"),
        status: "Saved Programme 17 mai-brochure.pdf — 2 sheet sides at 841×595 pt."
    )
    return ResultView()
        .environmentObject(model)
        .frame(width: 760, height: 620)
}

#Preview("ResultView — error") {
    let model = PDFBrochureModel()
    model._setForPreview(
        phase: .result,
        inputURL: URL(fileURLWithPath: "/tmp/broken.pdf"),
        status: "Error: Could not create the output PDF.",
        statusIsError: true
    )
    return ResultView()
        .environmentObject(model)
        .frame(width: 760, height: 620)
}
#endif
