import { CollarDriver, CollarReading } from './CollarDriver.js'

const FI_API_BASE = 'https://api.tryfi.com/graphql'

/**
 * Fi collar driver — uses Fi's GraphQL API via OAuth2.
 * Fi does not publish an official public API; this targets their mobile-app API.
 * Tokens are obtained via the Fi OAuth flow in /auth/collar-oauth/fi.
 */
export class FiDriver implements CollarDriver {
  readonly provider = 'fi'
  private accessToken: string | null = null

  async connect(credentials: Record<string, string>): Promise<void> {
    this.accessToken = credentials.accessToken
    if (!this.accessToken) throw new Error('FiDriver: accessToken is required')
  }

  async fetchReading(externalDeviceId: string): Promise<CollarReading> {
    if (!this.accessToken) throw new Error('FiDriver: not connected')

    const query = `
      query GetDeviceStats($deviceId: String!) {
        device(id: $deviceId) {
          id
          battery { percent }
          activitySummary {
            stepGoal
            totalSteps
            distance
          }
          lastLocation {
            speed
          }
        }
      }
    `

    const res = await fetch(FI_API_BASE, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${this.accessToken}`,
      },
      body: JSON.stringify({ query, variables: { deviceId: externalDeviceId } }),
    })

    if (!res.ok) throw new Error(`FiDriver: API error ${res.status}`)

    const json = (await res.json()) as {
      data?: {
        device?: {
          battery?: { percent?: number }
          activitySummary?: { totalSteps?: number }
          lastLocation?: { speed?: number }
        }
      }
    }

    const device = json.data?.device
    if (!device) throw new Error(`FiDriver: device ${externalDeviceId} not found`)

    return {
      collarId: externalDeviceId,
      timestamp: new Date(),
      steps: device.activitySummary?.totalSteps ?? 0,
      speedMph: device.lastLocation?.speed ?? 0,
      accelerationG: 0, // Fi API does not expose raw accelerometer
      batteryPct: device.battery?.percent ?? -1,
      rawProvider: 'fi',
    }
  }

  async disconnect(): Promise<void> {
    this.accessToken = null
  }
}
