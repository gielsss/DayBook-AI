import Foundation
import AppKit
import PDFKit
import Vision

/// Converts captured images and receipt files into PNG/JPEG data that Ollama vision models accept.
/// PDFs are rendered page by page because Ollama cannot read PDF files directly.
public enum ImageInputPreparer {
    /// Receipts rarely span more pages than this; extra pages would only slow the local model down.
    public static let maxPDFPages = 3
    /// Long edge in pixels for rendered or re-encoded images. Large enough to read small receipt print.
    public static let maxDimension: CGFloat = 1800

    public static func images(fromFile url: URL) throws -> [Data] {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            guard let document = PDFDocument(url: url) else {
                throw AIServiceError(kind: .invalidRequest, statusCode: 0, message: "Could not open the PDF \"\(url.lastPathComponent)\".")
            }
            let pages = renderPDF(document)
            guard !pages.isEmpty else {
                throw AIServiceError(kind: .invalidRequest, statusCode: 0, message: "The PDF \"\(url.lastPathComponent)\" has no readable pages.")
            }
            return pages
        }
        let data = try Data(contentsOf: url)
        return [try image(fromData: data, mimeType: mimeType(forExtension: ext))]
    }

    /// Passes PNG/JPEG through unchanged; converts anything else (HEIC, TIFF, WebP, ...) to JPEG.
    public static func image(fromData data: Data, mimeType: String?) throws -> Data {
        let mime = (mimeType ?? "").lowercased()
        if mime == "image/png" || mime == "image/jpeg" || mime == "image/jpg" {
            return data
        }
        guard let image = NSImage(data: data), let jpeg = jpegData(from: image) else {
            throw AIServiceError(kind: .invalidRequest, statusCode: 0, message: "This image format can't be read. Use a PNG or JPEG.")
        }
        return jpeg
    }

    static func mimeType(forExtension ext: String) -> String {
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "pdf": return "application/pdf"
        default: return "image/\(ext)"
        }
    }

    static func renderPDF(_ document: PDFDocument) -> [Data] {
        var results: [Data] = []
        for index in 0..<min(document.pageCount, maxPDFPages) {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { continue }
            let scale = min(maxDimension / max(bounds.width, bounds.height), 3.0)
            let size = NSSize(width: bounds.width * scale, height: bounds.height * scale)
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: size).fill()
            if let context = NSGraphicsContext.current?.cgContext {
                context.scaleBy(x: scale, y: scale)
                page.draw(with: .mediaBox, to: context)
            }
            image.unlockFocus()
            if let png = pngData(from: image) {
                results.append(png)
            }
        }
        return results
    }

    // MARK: On-device text recognition

    /// Reads printed text from images with macOS's built-in text recognition (no network).
    /// Used when the selected Ollama model can't read images, so screenshots and receipts still work.
    /// Pages are separated by a "--- Page N ---" line when there is more than one image.
    public static func recognizeText(in images: [Data]) async throws -> String {
        let pages = try await Task.detached(priority: .userInitiated) { () -> [String] in
            try images.map { try recognizeTextSync(in: $0) }
        }.value
        if pages.count == 1 { return pages[0] }
        return pages.enumerated().map { "--- Page \($0.offset + 1) ---\n\($0.element)" }.joined(separator: "\n\n")
    }

    nonisolated static func recognizeTextSync(in imageData: Data) throws -> String {
        guard let image = NSImage(data: imageData),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw AIServiceError(kind: .invalidRequest, statusCode: 0, message: "The image couldn't be opened for text recognition.")
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    private static func jpegData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
