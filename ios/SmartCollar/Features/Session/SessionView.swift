import SwiftUI

struct SessionView: View {
    let dog: Dog
    let collar: Collar
    let locationId: String?

    @StateObject private var vm = SessionViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 4) {
                Text(dog.name)
                    .font(.title.bold())
                Text(vm.isRecording ? "Session in progress" : "Ready to start")
                    .foregroundStyle(.secondary)
            }

            // Timer
            Text(formattedTime)
                .font(.system(size: 64, weight: .thin, design: .monospaced))

            // Live metrics
            HStack(spacing: 24) {
                MetricCard(
                    label: "Steps",
                    value: "\(vm.currentReading?.steps ?? 0)",
                    icon: "figure.walk"
                )
                MetricCard(
                    label: "Speed",
                    value: String(format: "%.1f mph", vm.currentReading?.speedMph ?? 0),
                    icon: "speedometer"
                )
                MetricCard(
                    label: "Accel",
                    value: String(format: "%.2f G", vm.currentReading?.accelerationG ?? 0),
                    icon: "waveform.path"
                )
            }

            Spacer()

            // Start / Stop button
            Button {
                Task {
                    if vm.isRecording {
                        await vm.endSession()
                        dismiss()
                    } else {
                        await vm.startSession(
                            dog: dog,
                            collar: collar,
                            locationId: locationId,
                            entryMethod: locationId != nil ? .checkin : .checkin
                        )
                    }
                }
            } label: {
                Text(vm.isRecording ? "End Session" : "Start Session")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(vm.isRecording ? Color.red : Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal)
        }
        .padding()
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var formattedTime: String {
        let h = vm.elapsedSeconds / 3600
        let m = (vm.elapsedSeconds % 3600) / 60
        let s = vm.elapsedSeconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

struct MetricCard: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.orange)
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
