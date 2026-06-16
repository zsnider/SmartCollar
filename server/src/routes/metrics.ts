import { FastifyInstance } from 'fastify'
import { requireAuth } from '../middleware/auth.js'
import { db } from '../db/index.js'

interface MetricReading {
  collarId: string
  recordedAt: string
  steps: number
  speedMph: number
  accelerationG: number
}

export async function metricRoutes(app: FastifyInstance) {
  // POST /sessions/:id/metrics — batch ingest from BLE polling
  app.post<{
    Params: { id: string }
    Body: { readings: MetricReading[] }
  }>('/sessions/:id/metrics', { preHandler: requireAuth }, async (request, reply) => {
    const { userId } = request.user
    const { id: sessionId } = request.params
    const { readings } = request.body

    if (!readings?.length) {
      return reply.code(400).send({ error: 'readings array is required and must not be empty' })
    }

    // Verify session belongs to user
    const { rows: sessionRows } = await db.query(
      `SELECT s.id FROM sessions s
       JOIN dogs d ON s.dog_id = d.id
       WHERE s.id = $1 AND d.owner_id = $2 AND s.ended_at IS NULL`,
      [sessionId, userId]
    )
    if (!sessionRows[0]) {
      return reply.code(404).send({ error: 'Active session not found' })
    }

    // Bulk insert
    const values: unknown[] = []
    const placeholders = readings.map((r, i) => {
      const base = i * 6
      values.push(sessionId, r.collarId, r.recordedAt, r.steps, r.speedMph, r.accelerationG)
      return `($${base + 1}, $${base + 2}, $${base + 3}, $${base + 4}, $${base + 5}, $${base + 6})`
    })

    await db.query(
      `INSERT INTO metrics (session_id, collar_id, recorded_at, steps, speed_mph, acceleration_g)
       VALUES ${placeholders.join(', ')}`,
      values
    )

    // Update session aggregate stats
    await db.query(
      `UPDATE sessions SET
         total_steps   = (SELECT COALESCE(MAX(steps), 0) FROM metrics WHERE session_id = $1),
         max_speed_mph = (SELECT COALESCE(MAX(speed_mph), 0) FROM metrics WHERE session_id = $1),
         avg_speed_mph = (SELECT COALESCE(AVG(speed_mph), 0) FROM metrics WHERE session_id = $1),
         peak_accel_g  = (SELECT COALESCE(MAX(acceleration_g), 0) FROM metrics WHERE session_id = $1)
       WHERE id = $1`,
      [sessionId]
    )

    return reply.code(201).send({ inserted: readings.length })
  })
}
