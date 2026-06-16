import { FastifyInstance } from 'fastify'
import { getLeaderboard } from '../services/leaderboard.js'
import { redis } from '../services/leaderboard.js'

type Metric = 'totalSteps' | 'maxSpeedMph' | 'avgSpeedMph' | 'peakAccelG' | 'sessionCount'
type Period = 'daily' | 'weekly' | 'alltime'

interface SubscribeLeaderboardMsg {
  type: 'subscribe_leaderboard'
  locationId: string
  metric: Metric
  period: Period
}

interface UnsubscribeMsg {
  type: 'unsubscribe'
}

type ClientMessage = SubscribeLeaderboardMsg | UnsubscribeMsg

export async function websocketHandlers(app: FastifyInstance) {
  app.get('/ws', { websocket: true }, (socket) => {
    let subscriber: ReturnType<typeof redis.duplicate> | null = null

    socket.on('message', async (raw: Buffer | string) => {
      let msg: ClientMessage
      try {
        msg = JSON.parse(raw.toString()) as ClientMessage
      } catch {
        return
      }

      if (msg.type === 'subscribe_leaderboard') {
        // Clean up previous subscription
        if (subscriber) {
          await subscriber.quit()
          subscriber = null
        }

        const { locationId, metric, period } = msg

        // Send current snapshot immediately
        const entries = await getLeaderboard(locationId, metric, period, 50)
        socket.send(JSON.stringify({ type: 'leaderboard_snapshot', locationId, metric, period, entries }))

        // Subscribe to Redis keyspace notifications for leaderboard updates
        subscriber = redis.duplicate()
        const channel = `__keyevent@0__:zadd`
        const keyPattern = `leaderboard:${locationId}:${metric}:${period}`

        await subscriber.subscribe(channel)
        subscriber.on('message', async (_ch: string, key: string) => {
          if (key !== keyPattern) return
          const updated = await getLeaderboard(locationId, metric, period, 50)
          if (socket.readyState === socket.OPEN) {
            socket.send(JSON.stringify({ type: 'leaderboard_update', locationId, metric, period, entries: updated }))
          }
        })
      }

      if (msg.type === 'unsubscribe') {
        if (subscriber) {
          await subscriber.quit()
          subscriber = null
        }
      }
    })

    socket.on('close', async () => {
      if (subscriber) {
        await subscriber.quit()
        subscriber = null
      }
    })
  })
}
