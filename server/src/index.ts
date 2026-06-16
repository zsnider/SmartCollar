import 'dotenv/config'
import Fastify from 'fastify'
import cors from '@fastify/cors'
import jwt from '@fastify/jwt'
import websocket from '@fastify/websocket'

import { authRoutes } from './routes/auth.js'
import { dogRoutes } from './routes/dogs.js'
import { sessionRoutes } from './routes/sessions.js'
import { locationRoutes } from './routes/locations.js'
import { leaderboardRoutes } from './routes/leaderboards.js'
import { metricRoutes } from './routes/metrics.js'
import { websocketHandlers } from './websocket/handlers.js'

const app = Fastify({ logger: true })

// Plugins
await app.register(cors, { origin: true })
await app.register(jwt, { secret: process.env.JWT_SECRET ?? 'dev-secret' })
await app.register(websocket)

// Routes
await app.register(authRoutes)
await app.register(dogRoutes)
await app.register(sessionRoutes)
await app.register(locationRoutes)
await app.register(leaderboardRoutes)
await app.register(metricRoutes)
await app.register(websocketHandlers)

// Health check
app.get('/health', async () => ({ status: 'ok' }))

const port = parseInt(process.env.PORT ?? '3000')
try {
  await app.listen({ port, host: '0.0.0.0' })
  console.log(`SmartCollar API running on port ${port}`)
} catch (err) {
  app.log.error(err)
  process.exit(1)
}
