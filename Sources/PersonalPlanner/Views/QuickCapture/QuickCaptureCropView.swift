import SwiftUI
import AppKit

public struct QuickCaptureCropView: View {
    public let originalImage: NSImage
    public let onCropApplied: (NSImage, Data) -> Void
    
    @State private var insetTop: Double = 0
    @State private var insetBottom: Double = 0
    @State private var insetLeft: Double = 0
    @State private var insetRight: Double = 0
    @State private var croppedPreview: NSImage? = nil
    
    public init(originalImage: NSImage, onCropApplied: @escaping (NSImage, Data) -> Void) {
        self.originalImage = originalImage
        self.onCropApplied = onCropApplied
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Crop Screenshot / Image")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button("Reset Crop") {
                    insetTop = 0
                    insetBottom = 0
                    insetLeft = 0
                    insetRight = 0
                    updatePreview()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            
            // Image Preview Container
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.dbSurface)
                    .frame(height: 180)
                
                if let preview = croppedPreview ?? generateCroppedImage() {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 170)
                        .cornerRadius(6)
                }
            }
            
            // Crop Inset Sliders
            VStack(spacing: 6) {
                HStack {
                    Text("Top: \(Int(insetTop))%")
                        .font(.caption2)
                        .frame(width: 60, alignment: .leading)
                    Slider(value: $insetTop, in: 0...45, step: 1)
                        .onChange(of: insetTop) { _ in updatePreview() }
                    
                    Text("Bottom: \(Int(insetBottom))%")
                        .font(.caption2)
                        .frame(width: 70, alignment: .leading)
                    Slider(value: $insetBottom, in: 0...45, step: 1)
                        .onChange(of: insetBottom) { _ in updatePreview() }
                }
                
                HStack {
                    Text("Left: \(Int(insetLeft))%")
                        .font(.caption2)
                        .frame(width: 60, alignment: .leading)
                    Slider(value: $insetLeft, in: 0...45, step: 1)
                        .onChange(of: insetLeft) { _ in updatePreview() }
                    
                    Text("Right: \(Int(insetRight))%")
                        .font(.caption2)
                        .frame(width: 70, alignment: .leading)
                    Slider(value: $insetRight, in: 0...45, step: 1)
                        .onChange(of: insetRight) { _ in updatePreview() }
                }
            }
            
            HStack {
                Spacer()
                Button("Apply Crop") {
                    if let cropped = generateCroppedImage(),
                       let tiff = cropped.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiff),
                       let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) {
                        onCropApplied(cropped, jpeg)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.dbBackground.opacity(0.8))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            updatePreview()
        }
    }
    
    private func updatePreview() {
        croppedPreview = generateCroppedImage()
    }
    
    private func generateCroppedImage() -> NSImage? {
        let size = originalImage.size
        guard size.width > 0, size.height > 0 else { return originalImage }
        
        let cropX = size.width * (insetLeft / 100.0)
        let cropY = size.height * (insetBottom / 100.0)
        let cropW = max(10, size.width * (1.0 - (insetLeft + insetRight) / 100.0))
        let cropH = max(10, size.height * (1.0 - (insetTop + insetBottom) / 100.0))
        
        let cropRect = NSRect(x: cropX, y: cropY, width: cropW, height: cropH)
        
        let cropped = NSImage(size: cropRect.size)
        cropped.lockFocus()
        originalImage.draw(
            in: NSRect(origin: .zero, size: cropRect.size),
            from: cropRect,
            operation: .copy,
            fraction: 1.0
        )
        cropped.unlockFocus()
        return cropped
    }
}
