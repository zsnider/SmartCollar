import { FastifyInstance } from 'fastify'
import bcrypt from 'bcryptjs'
import { v4 as uuidv4 } from 'uuid'
import { db } from '../db/index.js'

export async function authRoutes(app: FastifyInstance) {
  // POST /auth/register
  app.post<{
    Body: { email: string; displayName: string; password: string }
  }>('/auth/register', async (request, reply) => {
    const { email, displayName, password } = request.body

    if (!email || !displayName || !password) {
      return reply.code(400).send({ error: 'email, displayName, and password are required' })
    }

    const passwordHash = await bcrypt.hash(password, 12)

    try {
      const { rows } = await db.query(
        `INSERT INTO users (email, display_name, password_hash)
         VALUES ($1, $2, $3)
         RETURNING id, email, display_name, created_at`,
        [email.toLowerCase(), displayName, passwordHash]
      )
      const user = rows[0]
      const token = app.jwt.sign({ userId: user.id, email: user.email })
      return reply.code(201).send({ token, user })
    } catch (err: unknown) {
      if ((err as { code?: string }).code === '23505') {
        return reply.code(409).send({ error: 'Email already registered' })
      }
      throw err
    }
  })

  // POST /auth/login
  app.post<{
    Body: { email: string; password: string }
  }>('/auth/login', async (request, reply) => {
    const { email, password } = request.body

    const { rows } = await db.query(
      'SELECT id, email, display_name, password_hash FROM users WHERE email = $1',
      [email.toLowerCase()]
    )

    const user = rows[0]
    if (!user || !(await bcrypt.compare(password, user.password_hash))) {
      return reply.code(401).send({ error: 'Invalid credentials' })
    }

    const token = app.jwt.sign({ userId: user.id, email: user.email })
    const refreshToken = uuidv4()
    const refreshHash = await bcrypt.hash(refreshToken, 10)

    await db.query(
      `INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
       VALUES ($1, $2, NOW() + INTERVAL '30 days')`,
      [user.id, refreshHash]
    )

    return reply.send({
      token,
      refreshToken,
      user: { id: user.id, email: user.email, displayName: user.display_name },
    })
  })

  // POST /auth/refresh
  app.post<{
    Body: { refreshToken: string }
  }>('/auth/refresh', async (request, reply) => {
    const { refreshToken } = request.body
    if (!refreshToken) return reply.code(400).send({ error: 'refreshToken required' })

    // Find a matching non-expired token by comparing all active tokens
    // In production, use a faster lookup (e.g. store token prefix unencrypted)
    const { rows } = await db.query(
      `SELECT rt.*, u.email FROM refresh_tokens rt
       JOIN users u ON rt.user_id = u.id
       WHERE rt.expires_at > NOW()`
    )

    let match: { user_id: string; email: string; id: string } | null = null
    for (const row of rows) {
      if (await bcrypt.compare(refreshToken, row.token_hash)) {
        match = row
        break
      }
    }

    if (!match) return reply.code(401).send({ error: 'Invalid or expired refresh token' })

    await db.query('DELETE FROM refresh_tokens WHERE id = $1', [match.id])

    const newToken = app.jwt.sign({ userId: match.user_id, email: match.email })
    const newRefreshToken = uuidv4()
    const newHash = await bcrypt.hash(newRefreshToken, 10)

    await db.query(
      `INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
       VALUES ($1, $2, NOW() + INTERVAL '30 days')`,
      [match.user_id, newHash]
    )

    return reply.send({ token: newToken, refreshToken: newRefreshToken })
  })
}
