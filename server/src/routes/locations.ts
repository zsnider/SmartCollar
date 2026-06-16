import { FastifyInstance } from 'fastify'
import { requireAuth } from '../middleware/auth.js'
import { db } from '../db/index.js'
import { findNearbyLocations } from '../services/geofence.js'

export async function locationRoutes(app: FastifyInstance) {
  // GET /locations — all curated/verified locations
  app.get('/locations', async (_request, reply) => {
    const { rows } = await db.query(
      `SELECT id, name, type,
              ST_Y(coordinates::geometry) AS lat,
              ST_X(coordinates::geometry) AS lng,
              radius_meters, is_verified, created_at
       FROM locations
       ORDER BY is_verified DESC, name`
    )
    return reply.send(rows)
  })

  // GET /locations/nearby
  app.get<{
    Querystring: { lat: string; lng: string; radiusMeters?: string }
  }>('/locations/nearby', async (request, reply) => {
    const { lat, lng, radiusMeters } = request.query
    if (!lat || !lng) return reply.code(400).send({ error: 'lat and lng are required' })

    const results = await findNearbyLocations(
      parseFloat(lat),
      parseFloat(lng),
      parseInt(radiusMeters ?? '500')
    )
    return reply.send(results)
  })

  // GET /locations/:id
  app.get<{ Params: { id: string } }>('/locations/:id', async (request, reply) => {
    const { rows } = await db.query(
      `SELECT id, name, type,
              ST_Y(coordinates::geometry) AS lat,
              ST_X(coordinates::geometry) AS lng,
              radius_meters, is_verified, created_at
       FROM locations WHERE id = $1`,
      [request.params.id]
    )
    if (!rows[0]) return reply.code(404).send({ error: 'Location not found' })
    return reply.send(rows[0])
  })

  // POST /locations — user-submitted location
  app.post<{
    Body: {
      name: string
      type: string
      lat: number
      lng: number
      radiusMeters?: number
    }
  }>('/locations', { preHandler: requireAuth }, async (request, reply) => {
    const { userId } = request.user
    const { name, type, lat, lng, radiusMeters } = request.body

    if (!name || !type || lat == null || lng == null) {
      return reply.code(400).send({ error: 'name, type, lat, and lng are required' })
    }

    const { rows } = await db.query(
      `INSERT INTO locations (name, type, coordinates, radius_meters, created_by)
       VALUES ($1, $2, ST_SetSRID(ST_MakePoint($4, $3), 4326), $5, $6)
       RETURNING id, name, type, radius_meters, is_verified, created_at,
                 ST_Y(coordinates::geometry) AS lat,
                 ST_X(coordinates::geometry) AS lng`,
      [name, type, lat, lng, radiusMeters ?? 100, userId]
    )
    return reply.code(201).send(rows[0])
  })
}
