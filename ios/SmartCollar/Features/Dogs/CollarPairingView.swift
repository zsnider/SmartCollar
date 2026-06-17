import SwiftUI
import CoreBluetooth

@MainActor
final class CollarPairingViewModel: ObservableObject {
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var isScanning = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var connectedPeripheral: CBPeripheral?

    private let bleManager = BLECollarManager.shared
    private let api = APIClient.shared
    private var cancellables = Set<AnyCancellable>()

    func startScan() {
        bleManager.startScan()
        isScanning = true

        // Mirror BLE manager's discovered devices
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else { timer.invalidate(); return }
                self.discoveredDevices = self.bleManager.discoveredDevices
                if !self.isScanning { timer.invalidate() }
            }
        }
    }

    func stopScan() {
        bleManager.stopScan()
        isScanning = false
    }

    func pair(peripheral: CBPeripheral, dogId: String, onSuccess: @escaping (Collar) -> Void) async {
        isSaving = true
        bleManager.connect(peripheral: peripheral)
        connectedPeripheral = peripheral

        // Give BLE a moment to connect and discover services
        try? await Task.sleep(for: .seconds(2))

        do {
            let serviceUUID = peripheral.services?.first?.uuid.uuidString
            let collar = try await api.addCollar(
                dogId: dogId,
                provider: "ble_generic",
                bleServiceUUID: serviceUUID ?? peripheral.identifier.uuidString
            )
            onSuccess(collar)
        } catch {
            errorMessage = "Could not save collar: \(error.localizedDescription)"
        }
        isSaving = false
    }
}

import Combine

struct CollarPairingView: View {
    let dog: Dog
    let onPaired: (Collar) -> Void

    @StateObject private var vm = CollarPairingViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPeripheral: CBPeripheral?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Scan status banner
                HStack(spacing: 10) {
                    if vm.isScanning {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Scanning for collars...")
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("Scan stopped")
                    }
                    Spacer()
                    Button(vm.isScanning ? "Stop" : "Scan") {
                        vm.isScanning ? vm.stopScan() : vm.startScan()
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }
                .padding()
                .background(.orange.opacity(0.06))

                if vm.discoveredDevices.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "wave.3.right")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange.opacity(0.5))
                        Text(vm.isScanning ? "Looking for nearby collars…" : "No devices found.\nMake sure your collar is powered on.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    Spacer()
                } else {
                    List(vm.discoveredDevices, id: \.identifier) { peripheral in
                        PeripheralRow(
                            peripheral: peripheral,
                            isConnecting: vm.isSaving && selectedPeripheral?.identifier == peripheral.identifier
                        ) {
                            selectedPeripheral = peripheral
                            vm.stopScan()
                            Task {
                                await vm.pair(peripheral: peripheral, dogId: dog.id) { collar in
                                    onPaired(collar)
                                    dismiss()
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }

                // Manual entry option
                Divider()
                Button {
                    Task {
                        if let fakeCollar = try? await APIClient.shared.addCollar(
                            dogId: dog.id,
                            provider: "ble_generic",
                            bleServiceUUID: nil
                        ) {
                            onPaired(fakeCollar)
                            dismiss()
                        }
                    }
                } label: {
                    Label("Add collar manually (no BLE)", systemImage: "plus.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Pair a Collar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { vm.stopScan(); dismiss() }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
            .onAppear { vm.startScan() }
            .onDisappear { vm.stopScan() }
        }
    }
}

struct PeripheralRow: View {
    let peripheral: CBPeripheral
    let isConnecting: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.orange)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(peripheral.name ?? "Unknown Device")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(peripheral.identifier.uuidString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isConnecting {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Text("Pair")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
            .padding(.vertical, 4)
        }
        .disabled(isConnecting)
    }
}
