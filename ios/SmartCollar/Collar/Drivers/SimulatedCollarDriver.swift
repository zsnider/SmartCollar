import Foundation

/// Generates realistic fake collar data for testing without a physical device.
/// Simulates a dog running around a dog park — bursts of speed, then rest.
final class SimulatedCollarDriver: CollarDriver {
    let provider = "simulated"
    private(set) var isConnected = false

    private var cumulativeSteps = 0
    private var phase: DogPhase = .trotting
    private var phaseTimer = 0

    private enum DogPhase {
        case sprinting, trotting, sniffing
    }

    func connect() async throws {
        isConnected = true
    }

    func fetchReading() async throws -> CollarReadingBLE {
        advancePhase()

        let (speed, accel, steps) = metricsForCurrentPhase()
        cumulativeSteps += steps

        // Small random jitter to make it look like real sensor data
        let jitter = Double.random(in: -0.05...0.05)

        return CollarReadingBLE(
            collarId: "simulated-collar",
            timestamp: Date(),
            steps: cumulativeSteps,
            speedMph: max(0, speed + jitter * speed),
            accelerationG: max(0, accel + jitter),
            batteryPct: 85
        )
    }

    func disconnect() {
        isConnected = false
    }

    // MARK: - Phase simulation

    private func advancePhase() {
        phaseTimer += 1
        if phaseTimer >= phaseDuration {
            phaseTimer = 0
            phase = nextPhase()
        }
    }

    private var phaseDuration: Int {
        switch phase {
        case .sprinting: return Int.random(in: 3...8)   // short bursts
        case .trotting:  return Int.random(in: 8...20)  // medium trots
        case .sniffing:  return Int.random(in: 5...15)  // nose down
        }
    }

    private func nextPhase() -> DogPhase {
        switch phase {
        case .sprinting: return Bool.random() ? .trotting : .sniffing
        case .trotting:  return Bool.random() ? .sprinting : .sniffing
        case .sniffing:  return .trotting
        }
    }

    /// Returns (speedMph, accelerationG, stepsThisTick)
    private func metricsForCurrentPhase() -> (Double, Double, Int) {
        switch phase {
        case .sprinting:
            return (
                Double.random(in: 12...22),   // dogs sprint up to 22 mph
                Double.random(in: 2.0...4.0),
                Int.random(in: 12...20)
            )
        case .trotting:
            return (
                Double.random(in: 4...9),
                Double.random(in: 0.8...1.8),
                Int.random(in: 6...12)
            )
        case .sniffing:
            return (
                Double.random(in: 0...1.5),
                Double.random(in: 0.1...0.5),
                Int.random(in: 0...3)
            )
        }
    }
}
