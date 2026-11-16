import Foundation
import AppKit
import PDFKit

/// Reads the text of files linked from Canvas assignments (instructions, rubrics, worksheets), so time
/// estimates see what the assignment really asks for. Read-only: files are downloaded with the link
/// Canvas gives in the file's details (`/api/v1/files/:id` → `url`, which carries its own access
/// token) through a cookie-free session, never saved to disk, and each file version is read only
/// once per app run.
@MainActor
public final class CanvasAttachmentReader {
    public enum Outcome: Equatable {
        case text(name: String, text: String)
        case unreadable(name: String, reason: String)
    }

    /// Largest file read (15 MB); lower in tests.
    public var maxBytes = 15_000_000
    public static let maxCharacters = 6000
    public static let maxPages = 20

    let session: URLSession
    private var cache: [String: Outcome] = [:]
    /// Downloads made (tests check that cached files aren't fetched again).
    public private(set) var downloads = 0

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Text of one Canvas file, given its details from `/api/v1/files/:id`.
    public func read(fileId: Int, info: [String: Any]) async -> Outcome {
        let name = (info["display_name"] as? String) ?? (info["filename"] as? String) ?? "file \(fileId)"
        let cacheKey = "\(fileId)@\(info["updated_at"] as? String ?? "")"
        if let cached = cache[cacheKey] { return cached }
        let outcome = await download(name: name, info: info)
        cache[cacheKey] = outcome
        return outcome
    }

    private func download(name: String, info: [String: Any]) async -> Outcome {
        if info["locked_for_user"] as? Bool == true {
            return .unreadable(name: name, reason: "locked in Canvas")
        }
        let type = (info["content-type"] as? String) ?? (info["mime_class"] as? String) ?? ""
        guard Self.kind(name: name, contentType: type) != nil else {
            return .unreadable(name: name, reason: "not a document DayBook AI can read")
        }
        if let size = (info["size"] as? NSNumber)?.intValue, size > maxBytes {
            return .unreadable(name: name, reason: "too large")
        }
        guard let link = info["url"] as? String, let url = URL(string: link), url.scheme == "https" else {
            return .unreadable(name: name, reason: "Canvas gave no download link")
        }
        do {
            var request = URLRequest(url: url, timeoutInterval: 30)
            request.httpMethod = "GET"
            let (bytes, response) = try await session.bytes(for: request)
            downloads += 1
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .unreadable(name: name, reason: "Canvas didn't send the file")
            }
            guard http.expectedContentLength <= Int64(maxBytes) else { return .unreadable(name: name, reason: "too large") }
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxBytes { return .unreadable(name: name, reason: "too large") }
            }
            let text = Self.extractText(from: data, name: name, contentType: type)
            guard let text, !text.isEmpty else {
                return .unreadable(name: name, reason: Self.looksLikeWebPage(data) ? "Canvas asked to sign in for this file" : "no readable text")
            }
            return .text(name: name, text: text)
        } catch {
            return .unreadable(name: name, reason: "couldn't download")
        }
    }

    enum Kind { case pdf, word, rtf, plain, image }

    static func kind(name: String, contentType: String) -> Kind? {
        let ext = (name as NSString).pathExtension.lowercased()
        let type = contentType.lowercased()
        if ext == "pdf" || type.contains("pdf") { return .pdf }
        if ["docx", "doc"].contains(ext) || type.contains("wordprocessingml") || type == "application/msword" || type == "doc" { return .word }
        if ext == "rtf" || type.contains("rtf") { return .rtf }
        if ["txt", "md", "csv"].contains(ext) || type.hasPrefix("text/plain") || type == "text/markdown" { return .plain }
        if ["png", "jpg", "jpeg", "heic", "tiff", "gif"].contains(ext) || type.hasPrefix("image/") || type == "image" { return .image }
        return nil
    }

    static func looksLikeWebPage(_ data: Data) -> Bool {
        let head = String(decoding: data.prefix(200), as: UTF8.self).lowercased()
        return head.contains("<!doctype html") || head.contains("<html")
    }

    /// Plain text of a document, tidied and cut to `maxCharacters`. Nil when it can't be read.
    static func extractText(from data: Data, name: String, contentType: String) -> String? {
        guard let kind = kind(name: name, contentType: contentType), !looksLikeWebPage(data) || kind == .plain else { return nil }
        var text: String?
        switch kind {
        case .pdf:
            guard let doc = PDFDocument(data: data) else { return nil }
            text = (0..<min(doc.pageCount, maxPages)).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
        case .word:
            let docType: NSAttributedString.DocumentType = data.starts(with: [0x50, 0x4B]) ? .officeOpenXML : .docFormat
            text = (try? NSAttributedString(data: data, options: [.documentType: docType], documentAttributes: nil))?.string
        case .rtf:
            text = (try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil))?.string
        case .plain:
            text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        case .image:
            text = try? ImageInputPreparer.recognizeTextSync(in: data)
        }
        guard let raw = text else { return nil }
        let tidy = raw
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return tidy.isEmpty ? nil : String(tidy.prefix(maxCharacters))
    }
}
