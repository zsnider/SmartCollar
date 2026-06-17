import SwiftUI

struct SessionView: View {
    let dog: Dog
    let collar: Collar
    let locationId: String?

    @StateObject private var vm = SessionViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var simulateMode = false

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Status bar
            if vm.isSimulated && vm.isRecording {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                    Text("Simulating collar data")
                }
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(.orange)
            }

            ScrollView {
                VStack(spacing: 28) {
                    // MARK: Dog + location header
                    VStack(spacing: 4) {
                        Text(dog.name)
                            .font(.title.bold())
                        Text(vm.isRecording
                             ? (locationId != nil ? "Session at park" : "Free session")
                             : "Ready to start")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    .padding(.top)

                    // MARK: Timer
                    Text(formattedTime)
                        .font(.system(size: 72, weight: .thin, design: .monospaced))
                        .foregroundStyle(vm.isRecording ? .primary : .secondary)

                    // MARK: Live metric cards
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        LiveMetricCard(
                            icon: "figure.walk",
                            value: "\(vm.currentReading?.steps ?? 0)",
                            label: "Steps",
                            color: .blue
                        )
                        LiveMetricCard(
                            icon: "speedometer",
                            value: String(format: "%.1f mph", vm.currentReading?.speedMph ?? 0),
                            label: "Speed",
                            color: .green
                        )
                        LiveMetricCard(
                            icon: "arrow.up.right",
                            value: String(format: "%.1f mph", vm.peakSpeedMph),
                            label: "Top Speed",
                            color: .orange
                        )
                        LiveMetricCard(
                            icon: "waveform.path",
                            value: String(format: "%.2f G", vm.currentReading?.accelerationG ?? 0),
                            label: "Accel",
                            color: .purple
                        )
                    }
                    .padding(.horizontal)

                    // MARK: Battery
                    if let battery = vm.currentReading?.batteryPct, battery >= 0 {
                        HStack(spacing: 6) {
                            Image(systemName: batteryIcon(battery))
                                .foregroundStyle(battery < 20 ? .red : .secondary)
                            Text(String(format: "Collar battery: %.0f%%", battery))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // MARK: Simulate toggle (only before session starts)
                    if !vm.isRecording {
                        VStack(spacing: 8) {
                            Toggle(isOn: $simulateMode) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Label("Simulate collar data", systemImage: "waveform")
                                        .font(.subheadline.bold())
                                    Text("Generates realistic dog activity for testing")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tint(.orange)
                            .padding()
                            .background(.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .padding(.horizontal)
                    }

                    // MARK: Start / End button
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
                                    entryMethod: locationId != nil ? .geofence : .checkin,
                                    simulate: simulateMode
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
                    .padding(.bottom, 32)
                }
            }
        }
        .navigationTitle("Session")
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
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }

    private func batteryIcon(_ pct: Double) -> String {
        switch pct {
        case 75...: return "battery.100"
        case 50...: return "battery.75"
        case 25...: return "battery.25"
        default:    return "battery.0"
        }
    }
}

struct LiveMetricCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.bold())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }
}
