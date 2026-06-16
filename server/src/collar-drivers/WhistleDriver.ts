import { CollarDriver, CollarReading } from './CollarDriver.js'

const WHISTLE_API_BASE = 'https://app.whistle.com/api'

/**
 * Whistle collar driver — uses Whistle's REST API.
 * Tokens are obtained via the Whistle OAuth flow in /auth/collar-oauth/whistle.
 */
export class WhistleDriver implements CollarDriver {
  readonly provider = 'whistle'
  private accessToken: string | null = null

  async connect(credentials: Record<string, string>): Promise<void> {
    this.accessToken = credentials.accessToken
    if (!this.accessToken) throw new Error('WhistleDriver: accessToken is required')
  }

  async fetchReading(externalDeviceId: string): Promise<CollarReading> {
    if (!this.accessToken) throw new Error('WhistleDriver: not connected')

    const res = await fetch(`${WHISTLE_API_BASE}/pets/${externalDeviceId}/activity_summaries`, {
      headers: { Authorization: `Bearer ${this.accessToken}` },
    })

    if (!res.ok) throw new Error(`WhistleDriver: API error ${res.status}`)

    const json = (await res.json()) as {
      activity_summaries?: Array<{
        steps?: number
        distance?: number
        calories?: number
      }>
      device?: { battery_level?: number }
    }

    const latest = json.activity_summaries?.[0]

    return {
      collarId: externalDeviceId,
      timestamp: new Date(),
      steps: latest?.steps ?? 0,
      speedMph: 0, // Whistle API does not expose real-time speed
      accelerationG: 0,
      batteryPct: json.device?.battery_level ?? -1,
      rawProvider: 'whistle',
    }
  }

  async disconnect(): Promise<void> {
    this.accessToken = null
  }
}
