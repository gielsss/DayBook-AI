import Foundation

public final class SimulatedEmailRetrievalService: EmailRetrievalServiceProtocol {
    public init() {}
    
    public func fetchRecentMessages() async throws -> [EmailSource] {
        // Simulates network latency when polling Gmail
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3s
        return DemoDataFactory.makeSampleEmails()
    }
}
