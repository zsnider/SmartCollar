import Foundation
import Combine

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var activeSession: Session?
    @Published var currentReading: CollarReadingBLE?
    @Published var isRecording = false
    @Published var elapsedSeconds = 0
    @Published var errorMessage: String?
    @Published var isSimulated = false

    // Live aggregates (updated each tick for display)
    @Published var peakSpeedMph: Double = 0
    @Published var peakAccelG: Double = 0

    private let api = APIClient.shared
    private let bleManager = BLECollarManager.shared

    private var simulatedDriver: SimulatedCollarDriver?
    private var timerTask: Task<Void, Never>?
    private var simulateTask: Task<Void, Never>?
    private var bleSubscription: AnyCancellable?
    private var metricsBuffer: [MetricPayload] = []
    private var flushTask: Task<Void, Never>?

    // MARK: - Public

    func startSession(dog: Dog, collar: Collar, locationId: String?, entryMethod: EntryMethod, simulate: Bool) async {
        isSimulated = simulate
        do {
            let session = try await api.startSession(
                dogId: dog.id,
                locationId: locationId,
                entryMethod: entryMethod.rawValue
            )
            activeSession = session
            isRecording = true
            elapsedSeconds = 0
            peakSpeedMph = 0
            peakAccelG = 0

            startTimer()
            startFlushLoop(sessionId: session.id)

            if simulate {
                startSimulation()
            } else {
                subscribeToBLE(collar: collar)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func endSession() async {
        guard let session = activeSession else { return }

        stopRecording()
        await flushMetrics(sessionId: session.id)

        let stats = SessionStats(
            endedAt: Date(),
            totalSteps: currentReading?.steps ?? session.totalSteps,
            maxSpeedMph: peakSpeedMph,
            avgSpeedMph: session.avgSpeedMph,
            peakAccelG: peakAccelG
        )

        do {
            let updated = try await api.endSession(sessionId: session.id, stats: stats)
            activeSession = updated
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Simulate

    private func startSimulation() {
        let driver = SimulatedCollarDriver()
        simulatedDriver = driver
        Task { try? await driver.connect() }

        simulateTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let reading = try? await driver.fetchReading() else { continue }
                handleReading(reading)
            }
        }
    }

    // MARK: - BLE

    private func subscribeToBLE(collar: Collar) {
        bleSubscription = bleManager.readingSubject
            .receive(on: RunLoop.main)
            .sink { [weak self] reading in
                self?.handleReading(reading)
            }
    }

    // MARK: - Reading handler (shared by BLE and simulate)

    private func handleReading(_ reading: CollarReadingBLE) {
        currentReading = reading
        peakSpeedMph = max(peakSpeedMph, reading.speedMph)
        peakAccelG = max(peakAccelG, reading.accelerationG)
        metricsBuffer.append(MetricPayload(
            collarId: reading.collarId,
            recordedAt: reading.timestamp,
            steps: reading.steps,
            speedMph: reading.speedMph,
            accelerationG: reading.accelerationG
        ))
    }

    // MARK: - Timer

    private func startTimer() {
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                elapsedSeconds += 1
            }
        }
    }

    // MARK: - Metric flush

    private func startFlushLoop(sessionId: String) {
        flushTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await flushMetrics(sessionId: sessionId)
            }
        }
    }

    private func flushMetrics(sessionId: String) async {
        guard !metricsBuffer.isEmpty else { return }
        let batch = metricsBuffer
        metricsBuffer.removeAll()
        do {
            try await api.ingestMetrics(sessionId: sessionId, readings: batch)
        } catch {
            metricsBuffer.insert(contentsOf: batch, at: 0)
        }
    }

    // MARK: - Cleanup

    private func stopRecording() {
        timerTask?.cancel()
        flushTask?.cancel()
        simulateTask?.cancel()
        bleSubscription?.cancel()
        simulatedDriver?.disconnect()
        simulatedDriver = nil
        isRecording = false
    }
}
