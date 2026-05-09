import SwiftUI

/// Two-screen flow: drop view until a PDF is loaded, then layout view.
struct RootView: View {
    @EnvironmentObject var model: PDFBrochureModel

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

#if DEBUG
#Preview("RootView — empty (drop)") {
    RootView()
        .environmentObject(PDFBrochureModel())
        .frame(width: 760, height: 620)
}

#Preview("RootView — loaded (layout)") {
    let model = PDFBrochureModel()
    model._setForPreview(
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
#endif
