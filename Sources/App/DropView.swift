import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// Step 1: drop a PDF (or click to pick).
struct DropView: View {
    @EnvironmentObject var model: PDFBrochureModel
    @State private var isTargeted = false
    @State private var rejectMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)

            Text("Drop a PDF to make a brochure")
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

#if DEBUG
#Preview("DropView") {
    DropView()
        .environmentObject(PDFBrochureModel())
        .frame(width: 760, height: 620)
}

#Preview("DropZone — idle") {
    DropZone(isTargeted: false, onClick: {})
        .frame(width: 520, height: 320)
        .padding(40)
}

#Preview("DropZone — drag-over") {
    DropZone(isTargeted: true, onClick: {})
        .frame(width: 520, height: 320)
        .padding(40)
}
#endif
