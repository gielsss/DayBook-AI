import Foundation
import AppKit

public struct RetainedCaptureMetadata: Codable, Identifiable {
    public let id: String
    public let date: Date
    public let contentType: String
    public let previewSnippet: String
    public let relativeFilePath: String?
}

public final class QuickCaptureStorageService {
    public let baseURL: URL
    private let fileManager = FileManager.default
    
    public init(customBaseURL: URL? = nil) {
        if let custom = customBaseURL {
            self.baseURL = custom
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.baseURL = appSupport.appendingPathComponent("PersonalPlanner/QuickCaptures", isDirectory: true)
        }
        try? fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }
    
    public func retainCapture(
        id: String,
        text: String?,
        imageData: Data?,
        mimeType: String?
    ) throws -> RetainedCaptureMetadata {
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let now = Date()
        var relPath: String? = nil
        let contentType: String
        let previewSnippet: String
        
        if let data = imageData {
            let ext = mimeType?.contains("png") == true ? "png" : "jpg"
            let fileName = "\(id).\(ext)"
            let fileURL = baseURL.appendingPathComponent(fileName)
            try data.write(to: fileURL)
            relPath = fileName
            contentType = "Image (\(ext.uppercased()))"
            previewSnippet = text?.prefix(100).description ?? "Screenshot capture (\(data.count / 1024) KB)"
        } else {
            let fileName = "\(id).txt"
            let fileURL = baseURL.appendingPathComponent(fileName)
            let txt = text ?? ""
            try txt.data(using: .utf8)?.write(to: fileURL)
            relPath = fileName
            contentType = "Text"
            previewSnippet = txt.prefix(120).description
        }
        
        let meta = RetainedCaptureMetadata(
            id: id,
            date: now,
            contentType: contentType,
            previewSnippet: previewSnippet,
            relativeFilePath: relPath
        )
        
        let metaURL = baseURL.appendingPathComponent("\(id)_meta.json")
        let metaData = try JSONEncoder().encode(meta)
        try metaData.write(to: metaURL)
        return meta
    }
    
    public func listRetainedCaptures() -> [RetainedCaptureMetadata] {
        guard let files = try? fileManager.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil) else {
            return []
        }
        var metas: [RetainedCaptureMetadata] = []
        for file in files where file.lastPathComponent.hasSuffix("_meta.json") {
            if let data = try? Data(contentsOf: file),
               let meta = try? JSONDecoder().decode(RetainedCaptureMetadata.self, from: data) {
                metas.append(meta)
            }
        }
        return metas.sorted { $0.date > $1.date }
    }
    
    public func deleteRetainedCapture(id: String) {
        let metaURL = baseURL.appendingPathComponent("\(id)_meta.json")
        if let data = try? Data(contentsOf: metaURL),
           let meta = try? JSONDecoder().decode(RetainedCaptureMetadata.self, from: data),
           let rel = meta.relativeFilePath {
            try? fileManager.removeItem(at: baseURL.appendingPathComponent(rel))
        }
        try? fileManager.removeItem(at: metaURL)
    }
    
    public func deleteAllRetainedCaptures() {
        if let files = try? fileManager.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil) {
            for f in files {
                try? fileManager.removeItem(at: f)
            }
        }
    }
}
