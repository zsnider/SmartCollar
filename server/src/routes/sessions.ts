import { FastifyInstance } from 'fastify'
import { requireAuth } from '../middleware/auth.js'
import { db } from '../db/index.js'
import { updateLeaderboard } from '../services/leaderboard.js'

export async function sessionRoutes(app: FastifyInstance) {
  // POST /sessions — start a session (manual check-in or geofence trigger)
  app.post<{
    Body: { dogId: string; locationId?: string; entryMethod: 'geofence' | 'checkin' }
  }>('/sessions', { preHandler: requireAuth }, async (request, reply) => {
    const { userId } = request.user
    const { dogId, locationId, entryMethod } = request.body

    if (!dogId || !entryMethod) {
      return reply.code(400).send({ error: 'dogId and entryMethod are required' })
    }

    // Verify dog ownership
    const { rows: dogRows } = await db.query(
      'SELECT id FROM dogs WHERE id = $1 AND owner_id = $2',
      [dogId, userId]
    )
    if (!dogRows[0]) return reply.code(404).send({ error: 'Dog not found' })

    const { rows } = await db.query(
      `INSERT INTO sessions (dog_id, location_id, entry_method)
       VALUES ($1, $2, $3)
       RETURNING *`,
      [dogId, locationId ?? null, entryMethod]
    )
    return reply.code(201).send(rows[0])
  })

  // PATCH /sessions/:id — update or end a session
  app.patch<{
    Params: { id: string }
    Body: {
      endedAt?: string
      totalSteps?: number
      maxSpeedMph?: number
      avgSpeedMph?: number
      peakAccelG?: number
    }
  }>('/sessions/:id', { preHandler: requireAuth }, async (request, reply) => {
    const { userId } = request.user
    const { endedAt, totalSteps, maxSpeedMph, avgSpeedMph, peakAccelG } = request.body

    const { rows } = await db.query(
      `UPDATE sessions s SET
         ended_at      = COALESCE($3::timestamptz, s.ended_at),
         total_steps   = COALESCE($4, s.total_steps),
         max_speed_mph = COALESCE($5, s.max_speed_mph),
         avg_speed_mph = COALESCE($6, s.avg_speed_mph),
         peak_accel_g  = COALESCE($7, s.peak_accel_g),
         duration_secs = CASE WHEN $3::timestamptz IS NOT NULL
                         THEN EXTRACT(EPOCH FROM ($3::timestamptz - s.started_at))::int
                         ELSE s.duration_secs END
       FROM dogs d
       WHERE s.id = $1 AND s.dog_id = d.id AND d.owner_id = $2
       RETURNING s.*`,
      [request.params.id, userId, endedAt ?? null, totalSteps, maxSpeedMph, avgSpeedMph, peakAccelG]
    )

    if (!rows[0]) return reply.code(404).send({ error: 'Session not found' })

    const session = rows[0]

    // If session just ended and has a location, update leaderboards
    if (endedAt && session.location_id) {
      await updateLeaderboard(session)
    }

    return reply.send(session)
  })

  // GET /sessions/:id
  app.get<{ Params: { id: string } }>(
    '/sessions/:id',
    { preHandler: requireAuth },
    async (request, reply) => {
      const { userId } = request.user
      const { rows } = await db.query(
        `SELECT s.* FROM sessions s
         JOIN dogs d ON s.dog_id = d.id
         WHERE s.id = $1 AND d.owner_id = $2`,
        [request.params.id, userId]
      )
      if (!rows[0]) return reply.code(404).send({ error: 'Session not found' })
      return reply.send(rows[0])
    }
  )

  // GET /dogs/:dogId/sessions — history
  app.get<{
    Params: { dogId: string }
    Querystring: { limit?: string; offset?: string }
  }>('/dogs/:dogId/sessions', { preHandler: requireAuth }, async (request, reply) => {
    const { userId } = request.user
    const { dogId } = request.params
    const limit = parseInt(request.query.limit ?? '20')
    const offset = parseInt(request.query.offset ?? '0')

    const { rows } = await db.query(
      `SELECT s.* FROM sessions s
       JOIN dogs d ON s.dog_id = d.id
       WHERE s.dog_id = $1 AND d.owner_id = $2
       ORDER BY s.started_at DESC
       LIMIT $3 OFFSET $4`,
      [dogId, userId, limit, offset]
    )
    return reply.send(rows)
  })
}
