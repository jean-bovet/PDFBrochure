import Foundation
import PDFKit

// Headless wrapper around BookletMaker for testing and scripting.
// Usage:
//   pdfbrochurecli <input.pdf> <output.pdf> [auto|a4|a3|letter|tabloid] [fit|fill|original]

func usage() -> Never {
    let msg = "usage: pdfbrochurecli <input.pdf> <output.pdf> [auto|a4|a3|letter|tabloid] [fit|fill|original]\n"
    FileHandle.standardError.write(Data(msg.utf8))
    exit(2)
}

let args = CommandLine.arguments
guard args.count >= 3 else { usage() }

let inURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])

let paper: PaperSize = {
    guard args.count > 3 else { return .auto }
    switch args[3].lowercased() {
    case "a4":      return .a4
    case "a3":      return .a3
    case "letter":  return .usLetter
    case "tabloid": return .usTabloid
    case "auto":    return .auto
    default:        usage()
    }
}()

let fit: FitMode = {
    guard args.count > 4 else { return .fit }
    switch args[4].lowercased() {
    case "fit":      return .fit
    case "fill":     return .fill
    case "original": return .original
    default:         usage()
    }
}()

do {
    let r = try BookletMaker.makeBooklet(
        input: inURL,
        output: outURL,
        paperSize: paper,
        fitMode: fit
    )
    print("ok: \(r.inputPages) input pages → \(r.outputPages) output pages, sheet \(Int(r.sheetSize.width))×\(Int(r.sheetSize.height)) pt")
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
