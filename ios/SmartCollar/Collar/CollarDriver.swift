import Foundation

/// Normalized reading emitted by every collar driver
struct CollarReadingBLE {
    let collarId: String
    let timestamp: Date
    let steps: Int
    let speedMph: Double
    let accelerationG: Double
    let batteryPct: Double
}

/// Every collar integration must implement this protocol
protocol CollarDriver: AnyObject {
    var provider: String { get }
    var isConnected: Bool { get }

    /// Called when the user pairs a collar. Implement BLE scan or OAuth initiation here.
    func connect() async throws

    /// Returns the latest reading for the bound device
    func fetchReading() async throws -> CollarReadingBLE

    /// Clean up BLE/network resources
    func disconnect()
}
