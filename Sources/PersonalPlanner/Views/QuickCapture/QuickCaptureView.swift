import SwiftUI
import AppKit

public struct QuickCaptureView: View {
    @ObservedObject var appState: AppState
    public var onClose: (() -> Void)? = nil
    
    @State private var selectedTab: QuickCaptureContentType = .text
    @State private var inputImage: NSImage? = nil
    @State private var showCropView: Bool = false
    @State private var showSourcePreview: Bool = false
    @State private var isDropTargeted: Bool = false
    
    public init(appState: AppState, onClose: (() -> Void)? = nil) {
        self.appState = appState
        self.onClose = onClose
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar
            
            Divider()
            
            // Content Body
            ScrollView {
                VStack(spacing: 14) {
                    if let error = appState.quickCaptureError {
                        errorBanner(error)
                    }
                    
                    if appState.isAnalyzingQuickCapture {
                        analyzingStateView
                    } else if !appState.quickCaptureProposals.isEmpty {
                        proposalsReviewView
                    } else {
                        captureInputView
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 460, idealHeight: 580)
        .background(Color.dbBackground)
        .onAppear {
            if appState.quickCaptureDraft.rawText.isEmpty && appState.quickCaptureDraft.imageData == nil {
                appState.readClipboardContentOnce()
            }
            if let data = appState.quickCaptureDraft.imageData {
                inputImage = NSImage(data: data)
                selectedTab = .image
            }
        }
        .onChange(of: appState.quickCaptureDraft.imageData) { newData in
            if let data = newData {
                inputImage = NSImage(data: data)
            } else {
                inputImage = nil
                showCropView = false
            }
        }
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .foregroundColor(.dbAccent)
                .font(.title3)
            
            Text("Quick Capture")
                .font(.headline)
            
            Spacer()
            
            if !appState.quickCaptureProposals.isEmpty {
                Button("Capture Another") {
                    clearEverything()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if hasAnyContent {
                Button(action: {
                    clearEverything()
                }) {
                    Label("Clear All", systemImage: "trash")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Clear both text and image input to start fresh")
            }
            
            if let close = onClose {
                Button("Done") {
                    close()
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.dbSurface)
    }
    
    private var hasAnyContent: Bool {
        !appState.quickCaptureDraft.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        inputImage != nil ||
        appState.quickCaptureDraft.imageData != nil
    }
    
    // MARK: - Input State View
    
    private var captureInputView: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Mode Selector & Paste Button
            HStack {
                Picker("", selection: $selectedTab) {
                    Label("Text", systemImage: "doc.text").tag(QuickCaptureContentType.text)
                    Label("Screenshot / Image", systemImage: "photo").tag(QuickCaptureContentType.image)
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                
                Spacer()
                
                Button(action: {
                    appState.readClipboardContentOnce()
                    if let data = appState.quickCaptureDraft.imageData {
                        inputImage = NSImage(data: data)
                        selectedTab = .image
                    } else {
                        selectedTab = .text
                    }
                }) {
                    Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            
            // Text Editor or Image Viewer
            if selectedTab == .text {
                textViewSection
            } else {
                imageViewSection
            }
            
            // Reference Date & Assumed Timezone
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Text("Reference Date:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    DatePicker(
                        "",
                        selection: $appState.quickCaptureDraft.referenceDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.compact)
                    .font(.caption)
                    .labelsHidden()
                    
                    Spacer()
                    
                    Text("Assumed Timezone: \(appState.preferences.timeZoneIdentifier)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Text("Used to accurately resolve relative dates like 'tomorrow', 'next Wednesday', or 'in 2 hours'.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color.dbSurface.opacity(0.6))
            .cornerRadius(6)
            
            // Privacy Notice & Analyze Button
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lock.shield")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Analyze runs on this Mac with \(appState.ollamaModel) through Ollama. Nothing is sent online. Content is processed strictly as data.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Button(action: {
                    Task {
                        await appState.analyzeQuickCapture()
                    }
                }) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Analyze")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!canAnalyze)
            }
        }
    }
    
    // MARK: - Text Section
    
    private var textViewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $appState.quickCaptureDraft.rawText)
                    .font(.body)
                    .frame(minHeight: 160, maxHeight: 220)
                    .padding(4)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                
                if appState.quickCaptureDraft.rawText.isEmpty {
                    Text("Type or paste message text here (e.g. an email excerpt, assignment prompt, or meeting proposal)...")
                        .font(.body)
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
            
            HStack {
                Text("\(appState.quickCaptureDraft.rawText.count) characters")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !appState.quickCaptureDraft.rawText.isEmpty {
                    Button(role: .destructive, action: {
                        deleteText()
                    }) {
                        Label("Delete Text", systemImage: "trash")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear this text if you entered the wrong thing")
                }
            }
        }
    }
    
    // MARK: - Image Section
    
    private var imageViewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let img = inputImage {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .frame(maxWidth: .infinity)
                        .background(Color.dbSurface)
                        .cornerRadius(8)
                    
                    // Top-right quick actions
                    HStack(spacing: 6) {
                        Button(action: {
                            showCropView.toggle()
                        }) {
                            Label(showCropView ? "Hide Crop" : "Crop", systemImage: "crop")
                                .font(.caption2)
                        }
                        .buttonStyle(.bordered)
                        
                        Button(role: .destructive, action: {
                            deleteImage()
                        }) {
                            Label("Delete", systemImage: "trash")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.bordered)
                        .help("Delete this screenshot / PNG")
                    }
                    .padding(8)
                }
                
                if showCropView {
                    QuickCaptureCropView(originalImage: img) { croppedImg, croppedData in
                        self.inputImage = croppedImg
                        self.appState.quickCaptureDraft.imageData = croppedData
                        self.appState.quickCaptureDraft.imageMimeType = "image/jpeg"
                        self.showCropView = false
                    }
                }
                
                // Status bar with Delete / Replace controls
                HStack {
                    if let data = appState.quickCaptureDraft.imageData {
                        let kb = Double(data.count) / 1024.0
                        Text(String(format: "Screenshot / Image attached (%.1f KB)", kb))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Image attached")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        appState.readClipboardContentOnce()
                        if let data = appState.quickCaptureDraft.imageData {
                            inputImage = NSImage(data: data)
                        }
                    }) {
                        Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    
                    Button(role: .destructive, action: {
                        deleteImage()
                    }) {
                        Label("Delete Image", systemImage: "trash")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete this screenshot / PNG if you captured the wrong thing")
                }
            } else {
                // Drop Target Placeholder
                VStack(spacing: 8) {
                    Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "photo.badge.plus")
                        .font(.system(size: 32))
                        .foregroundColor(isDropTargeted ? .dbAccent : .secondary)
                    Text(isDropTargeted ? "Drop PNG or image here" : "No image on clipboard")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Copy a screenshot to clipboard and click 'Paste', or drag and drop a PNG / image file here.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
                .background(
                    isDropTargeted
                        ? Color.dbAccent.opacity(0.12)
                        : Color.dbSurface.opacity(0.5)
                )
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isDropTargeted ? Color.dbAccent : Color.secondary.opacity(0.3),
                            style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [4])
                        )
                )
                .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers: providers)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func deleteImage() {
        inputImage = nil
        appState.clearQuickCaptureImage()
        showCropView = false
    }
    
    private func deleteText() {
        appState.clearQuickCaptureText()
    }
    
    private func clearEverything() {
        inputImage = nil
        showCropView = false
        appState.resetQuickCaptureDraft()
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let fileURL = url else { return }
                Task { @MainActor in
                    loadFile(at: fileURL)
                }
            }
            return true
        } else if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                if let img = image as? NSImage,
                   let tiff = img.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiff),
                   let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
                    Task { @MainActor in
                        self.inputImage = img
                        self.appState.quickCaptureDraft.imageData = jpegData
                        self.appState.quickCaptureDraft.imageMimeType = "image/jpeg"
                        self.appState.quickCaptureDraft.contentType = .image
                        self.selectedTab = .image
                    }
                }
            }
            return true
        }
        return false
    }
    
    private func loadFile(at url: URL) {
        let ext = url.pathExtension.lowercased()
        let imageExtensions = ["png", "jpg", "jpeg", "heic", "webp", "tiff", "gif", "bmp"]
        
        if imageExtensions.contains(ext) {
            if let data = try? Data(contentsOf: url), let img = NSImage(data: data) {
                self.inputImage = img
                let mime = (ext == "png") ? "image/png" : "image/jpeg"
                self.appState.quickCaptureDraft.imageData = data
                self.appState.quickCaptureDraft.imageMimeType = mime
                self.appState.quickCaptureDraft.contentType = .image
                self.selectedTab = .image
            }
        } else {
            if let text = try? String(contentsOf: url) {
                self.appState.quickCaptureDraft.rawText = text
                self.appState.quickCaptureDraft.contentType = .text
                self.selectedTab = .text
            }
        }
    }
    
    private var canAnalyze: Bool {
        if selectedTab == .text {
            return !appState.quickCaptureDraft.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } else {
            return appState.quickCaptureDraft.imageData != nil
        }
    }
    
    // MARK: - Analyzing Progress View
    
    private var analyzingStateView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            
            Text("Extracting tasks and calendar events...")
                .font(.headline)
            
            let activeModel = appState.quickCaptureActiveModel ?? appState.ollamaModel
            Text("Analyzing on this Mac with \(activeModel). Distinguishing tasks from meetings and respecting explicit timezones.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
    
    // MARK: - Proposals Review View
    
    private var proposalsReviewView: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Optional Source Preview Toggle & Discard/Start Over
            HStack {
                Button(action: {
                    showSourcePreview.toggle()
                }) {
                    Label(
                        showSourcePreview ? "Hide Source Content" : "View Source Content",
                        systemImage: showSourcePreview ? "chevron.up" : "chevron.down"
                    )
                    .font(.caption)
                }
                .buttonStyle(.borderless)
                
                Button(role: .destructive, action: {
                    clearEverything()
                }) {
                    Label("Clear & Start Over", systemImage: "arrow.counterclockwise")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Clear proposals and start over with new input")
                
                Spacer()
                
                let count = appState.quickCaptureProposals.filter { !$0.isDiscarded }.count
                Text("\(count) \(count == 1 ? "Proposal" : "Proposals") Found")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            
            if let activeModel = appState.quickCaptureActiveModel {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("Extracted using **\(activeModel)**")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(6)
            }
            
            if showSourcePreview {
                if let data = appState.quickCaptureDraft.imageData, let img = NSImage(data: data) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 140)
                        .cornerRadius(6)
                } else if !appState.quickCaptureDraft.rawText.isEmpty {
                    Text(appState.quickCaptureDraft.rawText)
                        .font(.caption)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.dbSurface)
                        .cornerRadius(6)
                }
            }
            
            // Proposals List
            ForEach($appState.quickCaptureProposals) { $proposal in
                if !proposal.isDiscarded {
                    QuickCaptureProposalCard(
                        proposal: $proposal,
                        timeZone: appState.preferences.timeZone,
                        onSaveTask: { prop in
                            appState.saveQuickCaptureTask(proposal: prop)
                        },
                        onSaveEvent: { prop in
                            appState.saveQuickCaptureEvent(proposal: prop)
                        },
                        onDiscard: { id in
                            appState.discardQuickCaptureProposal(id: id)
                        }
                    )
                }
            }
            
            if appState.quickCaptureProposals.allSatisfy({ $0.isSaved || $0.isDiscarded }) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("All proposals reviewed and resolved.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(10)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Error Banner
    
    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            VStack(alignment: .leading, spacing: 4) {
                Text("Extraction Failed")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("Retry Analysis") {
                    Task {
                        await appState.analyzeQuickCapture()
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.red.opacity(0.08))
        .cornerRadius(8)
    }
}
