import SwiftUI

/// Three-screen flow: drop → layout (configure + preview) → result.
struct RootView: View {
    @EnvironmentObject var model: PDFBrochureModel

    var body: some View {
        ZStack {
            switch model.phase {
            case .drop:
                DropView()
                    .transition(.opacity)
            case .layout:
                LayoutView()
                    .transition(.opacity)
            case .result:
                ResultView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.phase)
    }
}

#if DEBUG
#Preview("RootView — drop") {
    RootView()
        .environmentObject(PDFBrochureModel())
        .frame(width: 760, height: 620)
}

#Preview("RootView — layout") {
    let model = PDFBrochureModel()
    model._setForPreview(
        phase: .layout,
        inputURL: URL(fileURLWithPath: "/tmp/Programme 17 mai.pdf"),
        previewData: PreviewSamples.tinyBookletPDF(pages: 2),
        lastResult: BookletMaker.Result(
            inputPages: 4,
            outputPages: 2,
            sheetSize: CGSize(width: 841.89, height: 595.276)
        )
    )
    return RootView()
        .environmentObject(model)
        .frame(width: 760, height: 620)
}

#Preview("RootView — result (working)") {
    let model = PDFBrochureModel()
    model._setForPreview(
        phase: .result,
        inputURL: URL(fileURLWithPath: "/tmp/Programme 17 mai.pdf"),
        isWorking: true
    )
    return RootView()
        .environmentObject(model)
        .frame(width: 760, height: 620)
}

#Preview("RootView — result (success)") {
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
    return RootView()
        .environmentObject(model)
        .frame(width: 760, height: 620)
}
#endif
