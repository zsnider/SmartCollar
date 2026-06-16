import CoreBluetooth
import Combine

/// Manages BLE scanning and connection for generic collar devices.
/// Manufacturer-specific drivers (FiDriver, WhistleDriver) subclass or wrap this.
@MainActor
final class BLECollarManager: NSObject, ObservableObject {
    static let shared = BLECollarManager()

    @Published var isScanning = false
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var connectedPeripheral: CBPeripheral?

    /// Emits a reading every time characteristic data is updated
    let readingSubject = PassthroughSubject<CollarReadingBLE, Never>()

    private var centralManager: CBCentralManager!
    private var targetServiceUUID: CBUUID?
    private var pendingPeripheral: CBPeripheral?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan(serviceUUID: String? = nil) {
        guard centralManager.state == .poweredOn else { return }
        targetServiceUUID = serviceUUID.map { CBUUID(string: $0) }
        let services = targetServiceUUID.map { [$0] }
        centralManager.scanForPeripherals(withServices: services, options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false,
        ])
        isScanning = true
    }

    func stopScan() {
        centralManager.stopScan()
        isScanning = false
    }

    func connect(peripheral: CBPeripheral) {
        pendingPeripheral = peripheral
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect() {
        if let p = connectedPeripheral { centralManager.cancelPeripheralConnection(p) }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLECollarManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            if central.state == .poweredOn && self.isScanning {
                self.startScan(serviceUUID: self.targetServiceUUID?.uuidString)
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            if !self.discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
                self.discoveredDevices.append(peripheral)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.connectedPeripheral = peripheral
            peripheral.delegate = self
            peripheral.discoverServices(self.targetServiceUUID.map { [$0] })
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            if self.connectedPeripheral?.identifier == peripheral.identifier {
                self.connectedPeripheral = nil
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLECollarManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics where char.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: char)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard let data = characteristic.value else { return }
        // Parse generic BLE collar data packet
        // Override in manufacturer-specific drivers for custom formats
        if let reading = parseGenericPacket(data: data, collarId: peripheral.identifier.uuidString) {
            Task { @MainActor in
                self.readingSubject.send(reading)
            }
        }
    }

    private nonisolated func parseGenericPacket(data: Data, collarId: String) -> CollarReadingBLE? {
        // Generic 20-byte packet format:
        // [0-3]  steps (UInt32 LE)
        // [4-7]  speed in cm/s (UInt32 LE)
        // [8-11] acceleration in milli-g (Int32 LE)
        // [12]   battery percent (UInt8)
        guard data.count >= 13 else { return nil }

        let steps = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self).littleEndian }
        let speedCmps = data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self).littleEndian }
        let accelMg = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: Int32.self).littleEndian }
        let battery = data[12]

        return CollarReadingBLE(
            collarId: collarId,
            timestamp: Date(),
            steps: Int(steps),
            speedMph: Double(speedCmps) * 0.0223694, // cm/s → mph
            accelerationG: Double(accelMg) / 1000.0,
            batteryPct: Double(battery)
        )
    }
}
