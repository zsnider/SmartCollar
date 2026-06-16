import Foundation
import Combine

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var activeSession: Session?
    @Published var currentReading: CollarReadingBLE?
    @Published var isRecording = false
    @Published var elapsedSeconds = 0
    @Published var errorMessage: String?

    private let api = APIClient.shared
    private let bleManager = BLECollarManager.shared
    private let locationManager = LocationManager.shared

    private var timer: Task<Void, Never>?
    private var bleSubscription: AnyCancellable?
    private var metricsBuffer: [MetricPayload] = []
    private var flushTask: Task<Void, Never>?

    func startSession(dog: Dog, collar: Collar, locationId: String?, entryMethod: EntryMethod) async {
        do {
            let session = try await api.startSession(
                dogId: dog.id,
                locationId: locationId,
                entryMethod: entryMethod.rawValue
            )
            activeSession = session
            isRecording = true
            elapsedSeconds = 0
            startTimer()
            subscribeToBLE(collar: collar)
            startFlushLoop(sessionId: session.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func endSession() async {
        guard let session = activeSession else { return }

        // Flush remaining metrics
        await flushMetrics(sessionId: session.id)

        let stats = SessionStats(
            endedAt: Date(),
            totalSteps: currentReading?.steps ?? session.totalSteps,
            maxSpeedMph: session.maxSpeedMph,
            avgSpeedMph: session.avgSpeedMph,
            peakAccelG: session.peakAccelG
        )

        do {
            let updated = try await api.endSession(sessionId: session.id, stats: stats)
            activeSession = updated
        } catch {
            errorMessage = error.localizedDescription
        }

        stopRecording()
    }

    // MARK: - Private

    private func startTimer() {
        timer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                elapsedSeconds += 1
            }
        }
    }

    private func subscribeToBLE(collar: Collar) {
        bleSubscription = bleManager.readingSubject
            .receive(on: RunLoop.main)
            .sink { [weak self] reading in
                self?.currentReading = reading
                self?.bufferReading(reading)
            }
    }

    private func bufferReading(_ reading: CollarReadingBLE) {
        metricsBuffer.append(MetricPayload(
            collarId: reading.collarId,
            recordedAt: reading.timestamp,
            steps: reading.steps,
            speedMph: reading.speedMph,
            accelerationG: reading.accelerationG
        ))
    }

    private func startFlushLoop(sessionId: String) {
        flushTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30)) // flush every 30s
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
            // Put back on failure
            metricsBuffer.insert(contentsOf: batch, at: 0)
        }
    }

    private func stopRecording() {
        timer?.cancel()
        flushTask?.cancel()
        bleSubscription?.cancel()
        isRecording = false
    }
}
