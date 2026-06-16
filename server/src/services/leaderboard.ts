import { Redis } from 'ioredis'
import { db } from '../db/index.js'

export const redis = new Redis(process.env.REDIS_URL ?? 'redis://localhost:6379')

type Metric = 'totalSteps' | 'maxSpeedMph' | 'avgSpeedMph' | 'peakAccelG' | 'sessionCount'
type Period = 'daily' | 'weekly' | 'alltime'

const METRIC_COLUMN: Record<Metric, string> = {
  totalSteps: 'total_steps',
  maxSpeedMph: 'max_speed_mph',
  avgSpeedMph: 'avg_speed_mph',
  peakAccelG: 'peak_accel_g',
  sessionCount: 'session_count',
}

function redisKey(locationId: string, metric: Metric, period: Period): string {
  return `leaderboard:${locationId}:${metric}:${period}`
}

function periodStart(period: Period): Date | null {
  const now = new Date()
  if (period === 'daily') {
    return new Date(now.getFullYear(), now.getMonth(), now.getDate())
  }
  if (period === 'weekly') {
    const day = now.getDay()
    const diff = now.getDate() - day + (day === 0 ? -6 : 1) // Monday
    return new Date(now.getFullYear(), now.getMonth(), diff)
  }
  return null // alltime
}

export interface LeaderboardEntry {
  rank: number
  dogId: string
  dogName: string
  ownerName: string
  value: number
  sessionId: string
}

/**
 * Rebuild and cache a leaderboard in Redis from Postgres.
 * Called after a session ends. TTL: 5 minutes (results are refreshed on next session end).
 */
export async function updateLeaderboard(session: {
  id: string
  location_id: string
  dog_id: string
  total_steps: number
  max_speed_mph: number
  avg_speed_mph: number
  peak_accel_g: number
}): Promise<void> {
  const locationId = session.location_id
  const periods: Period[] = ['daily', 'weekly', 'alltime']
  const metrics: Metric[] = ['totalSteps', 'maxSpeedMph', 'avgSpeedMph', 'peakAccelG']

  for (const period of periods) {
    const since = periodStart(period)
    for (const metric of metrics) {
      const col = METRIC_COLUMN[metric]
      const key = redisKey(locationId, metric, period)

      const { rows } = await db.query(
        `SELECT s.id AS session_id, s.dog_id, d.name AS dog_name,
                u.display_name AS owner_name, s.${col} AS value
         FROM sessions s
         JOIN dogs d ON s.dog_id = d.id
         JOIN users u ON d.owner_id = u.id
         WHERE s.location_id = $1
           AND s.ended_at IS NOT NULL
           ${since ? 'AND s.started_at >= $2' : ''}
         ORDER BY s.${col} DESC
         LIMIT 100`,
        since ? [locationId, since] : [locationId]
      )

      if (!rows.length) continue

      const pipeline = redis.pipeline()
      pipeline.del(key)
      for (const row of rows) {
        pipeline.zadd(key, row.value, JSON.stringify({
          dogId: row.dog_id,
          dogName: row.dog_name,
          ownerName: row.owner_name,
          sessionId: row.session_id,
          value: row.value,
        }))
      }
      pipeline.expire(key, 300) // 5 min TTL
      await pipeline.exec()
    }
  }
}

/**
 * Fetch a ranked leaderboard from Redis (falls back to Postgres if cold).
 */
export async function getLeaderboard(
  locationId: string,
  metric: Metric,
  period: Period,
  limit: number
): Promise<LeaderboardEntry[]> {
  const key = redisKey(locationId, metric, period)
  const raw = await redis.zrevrange(key, 0, limit - 1, 'WITHSCORES')

  if (!raw.length) {
    // Cold cache — build from Postgres
    const col = METRIC_COLUMN[metric]
    const since = periodStart(period)
    const { rows } = await db.query(
      `SELECT s.id AS session_id, s.dog_id, d.name AS dog_name,
              u.display_name AS owner_name, s.${col} AS value
       FROM sessions s
       JOIN dogs d ON s.dog_id = d.id
       JOIN users u ON d.owner_id = u.id
       WHERE s.location_id = $1
         AND s.ended_at IS NOT NULL
         ${since ? 'AND s.started_at >= $2' : ''}
       ORDER BY s.${col} DESC
       LIMIT $${since ? 3 : 2}`,
      since ? [locationId, since, limit] : [locationId, limit]
    )

    return rows.map((r, i) => ({
      rank: i + 1,
      dogId: r.dog_id,
      dogName: r.dog_name,
      ownerName: r.owner_name,
      value: parseFloat(r.value),
      sessionId: r.session_id,
    }))
  }

  // Parse Redis response (alternating member/score)
  const entries: LeaderboardEntry[] = []
  for (let i = 0; i < raw.length; i += 2) {
    const data = JSON.parse(raw[i]) as Omit<LeaderboardEntry, 'rank'>
    entries.push({ rank: entries.length + 1, ...data })
  }
  return entries
}
