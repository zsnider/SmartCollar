export interface CollarReading {
  collarId: string
  timestamp: Date
  steps: number          // cumulative since session start
  speedMph: number       // instantaneous
  accelerationG: number  // instantaneous (g-force)
  batteryPct: number
  rawProvider: string    // 'fi' | 'whistle' | 'tractive' | 'ble_generic'
}

export interface CollarDriver {
  readonly provider: string

  /**
   * Authenticate / initialise connection (OAuth token exchange, BLE connect, etc.)
   */
  connect(credentials: Record<string, string>): Promise<void>

  /**
   * Pull the latest reading for a specific collar device.
   */
  fetchReading(externalDeviceId: string): Promise<CollarReading>

  /**
   * Disconnect and clean up resources.
   */
  disconnect(): Promise<void>
}
