import { FastifyInstance } from 'fastify'
import { requireAuth } from '../middleware/auth.js'
import { db } from '../db/index.js'

export async function dogRoutes(app: FastifyInstance) {
  // GET /dogs
  app.get('/dogs', { preHandler: requireAuth }, async (request, reply) => {
    const { userId } = request.user
    const { rows } = await db.query(
      `SELECT id, name, breed, weight_lbs, avatar_url, created_at
       FROM dogs WHERE owner_id = $1 ORDER BY created_at`,
      [userId]
    )
    return reply.send(rows)
  })

  // POST /dogs
  app.post<{
    Body: { name: string; breed?: string; weightLbs?: number }
  }>('/dogs', { preHandler: requireAuth }, async (request, reply) => {
    const { userId } = request.user
    const { name, breed, weightLbs } = request.body

    if (!name) return reply.code(400).send({ error: 'name is required' })

    const { rows } = await db.query(
      `INSERT INTO dogs (owner_id, name, breed, weight_lbs)
       VALUES ($1, $2, $3, $4)
       RETURNING id, name, breed, weight_lbs, avatar_url, created_at`,
      [userId, name, breed ?? null, weightLbs ?? null]
    )
    return reply.code(201).send(rows[0])
  })

  // GET /dogs/:id
  app.get<{ Params: { id: string } }>(
    '/dogs/:id',
    { preHandler: requireAuth },
    async (request, reply) => {
      const { userId } = request.user
      const { rows } = await db.query(
        'SELECT * FROM dogs WHERE id = $1 AND owner_id = $2',
        [request.params.id, userId]
      )
      if (!rows[0]) return reply.code(404).send({ error: 'Dog not found' })
      return reply.send(rows[0])
    }
  )

  // PATCH /dogs/:id
  app.patch<{
    Params: { id: string }
    Body: { name?: string; breed?: string; weightLbs?: number; avatarUrl?: string }
  }>('/dogs/:id', { preHandler: requireAuth }, async (request, reply) => {
    const { userId } = request.user
    const { name, breed, weightLbs, avatarUrl } = request.body

    const { rows } = await db.query(
      `UPDATE dogs SET
         name       = COALESCE($3, name),
         breed      = COALESCE($4, breed),
         weight_lbs = COALESCE($5, weight_lbs),
         avatar_url = COALESCE($6, avatar_url)
       WHERE id = $1 AND owner_id = $2
       RETURNING *`,
      [request.params.id, userId, name, breed, weightLbs, avatarUrl]
    )
    if (!rows[0]) return reply.code(404).send({ error: 'Dog not found' })
    return reply.send(rows[0])
  })

  // DELETE /dogs/:id
  app.delete<{ Params: { id: string } }>(
    '/dogs/:id',
    { preHandler: requireAuth },
    async (request, reply) => {
      const { userId } = request.user
      const { rowCount } = await db.query(
        'DELETE FROM dogs WHERE id = $1 AND owner_id = $2',
        [request.params.id, userId]
      )
      if (!rowCount) return reply.code(404).send({ error: 'Dog not found' })
      return reply.code(204).send()
    }
  )

  // GET /dogs/:dogId/collars
  app.get<{ Params: { dogId: string } }>(
    '/dogs/:dogId/collars',
    { preHandler: requireAuth },
    async (request, reply) => {
      const { userId } = request.user
      const { rows } = await db.query(
        `SELECT c.id, c.provider, c.external_id, c.ble_service_uuid, c.last_synced_at
         FROM collars c
         JOIN dogs d ON c.dog_id = d.id
         WHERE c.dog_id = $1 AND d.owner_id = $2`,
        [request.params.dogId, userId]
      )
      return reply.send(rows)
    }
  )

  // POST /dogs/:dogId/collars
  app.post<{
    Params: { dogId: string }
    Body: { provider: string; externalId?: string; bleServiceUUID?: string }
  }>('/dogs/:dogId/collars', { preHandler: requireAuth }, async (request, reply) => {
    const { userId } = request.user
    const { dogId } = request.params
    const { provider, externalId, bleServiceUUID } = request.body

    // Verify the dog belongs to the user
    const { rows: dogRows } = await db.query(
      'SELECT id FROM dogs WHERE id = $1 AND owner_id = $2',
      [dogId, userId]
    )
    if (!dogRows[0]) return reply.code(404).send({ error: 'Dog not found' })

    const { rows } = await db.query(
      `INSERT INTO collars (dog_id, provider, external_id, ble_service_uuid)
       VALUES ($1, $2, $3, $4)
       RETURNING id, provider, external_id, ble_service_uuid, created_at`,
      [dogId, provider, externalId ?? null, bleServiceUUID ?? null]
    )
    return reply.code(201).send(rows[0])
  })

  // DELETE /dogs/:dogId/collars/:collarId
  app.delete<{ Params: { dogId: string; collarId: string } }>(
    '/dogs/:dogId/collars/:collarId',
    { preHandler: requireAuth },
    async (request, reply) => {
      const { userId } = request.user
      const { dogId, collarId } = request.params
      const { rowCount } = await db.query(
        `DELETE FROM collars c
         USING dogs d
         WHERE c.id = $1 AND c.dog_id = $2 AND d.id = c.dog_id AND d.owner_id = $3`,
        [collarId, dogId, userId]
      )
      if (!rowCount) return reply.code(404).send({ error: 'Collar not found' })
      return reply.code(204).send()
    }
  )
}
