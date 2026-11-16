import SwiftUI

public struct EmailSourceBadge: View {
    public let email: EmailSource
    @State private var isExpanded: Bool = false
    
    public init(email: EmailSource) {
        self.email = email
    }
    
    private var categoryColor: Color {
        switch email.category {
        case .assignment: return .dbNavy
        case .ambiguous: return .orange
        case .newsletter: return .dbAccent
        case .deadlineChange: return .green
        case .quickCapture: return .dbAccent
        case .canvas: return .red
        case .gradescope: return .dbAccent
        }
    }
    
    private var categoryIcon: String {
        switch email.category {
        case .quickCapture: return "bolt.fill"
        case .canvas: return "graduationcap.fill"
        case .gradescope: return "checkmark.rectangle.stack.fill"
        default: return "envelope.fill"
        }
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: email.receivedDate)
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: categoryIcon)
                    .foregroundColor(categoryColor)
                    .font(.system(size: 14))
                    .padding(.top, 2)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(email.senderName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Text("<\(email.senderEmail)>")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(email.category.rawValue)
                            .font(.caption.weight(.medium))
                            .foregroundColor(categoryColor)
                    }
                    
                    Text(email.subject)
                        .font(.body)
                        .fontWeight(.medium)
                    
                    Text(formattedDate)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Collapsible email body
            DisclosureGroup(
                isExpanded: $isExpanded,
                content: {
                    VStack(alignment: .leading, spacing: 6) {
                        Divider()
                            .padding(.vertical, 4)
                        
                        Text("Simulated Raw Email Content:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        
                        ScrollView {
                            Text(email.fullBody)
                                .font(.system(.caption, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                                .cornerRadius(6)
                        }
                        .frame(maxHeight: 180)
                    }
                },
                label: {
                    Text(isExpanded ? "Hide Original Email Body" : "View Original Email Body")
                        .font(.caption)
                        .foregroundColor(.dbAccent)
                }
            )
        }
        .padding(12)
        .background(Color.dbSurface)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(categoryColor.opacity(0.3), lineWidth: 1)
        )
    }
}
