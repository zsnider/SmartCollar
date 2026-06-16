import { FastifyInstance } from 'fastify'
import { getLeaderboard } from '../services/leaderboard.js'

type Metric = 'totalSteps' | 'maxSpeedMph' | 'avgSpeedMph' | 'peakAccelG' | 'sessionCount'
type Period = 'daily' | 'weekly' | 'alltime'

const VALID_METRICS: Metric[] = ['totalSteps', 'maxSpeedMph', 'avgSpeedMph', 'peakAccelG', 'sessionCount']
const VALID_PERIODS: Period[] = ['daily', 'weekly', 'alltime']

export async function leaderboardRoutes(app: FastifyInstance) {
  // GET /locations/:id/leaderboard?metric=maxSpeedMph&period=weekly
  app.get<{
    Params: { id: string }
    Querystring: { metric?: string; period?: string; limit?: string }
  }>('/locations/:id/leaderboard', async (request, reply) => {
    const { id: locationId } = request.params
    const metric = (request.query.metric ?? 'totalSteps') as Metric
    const period = (request.query.period ?? 'weekly') as Period
    const limit = parseInt(request.query.limit ?? '50')

    if (!VALID_METRICS.includes(metric)) {
      return reply.code(400).send({ error: `metric must be one of: ${VALID_METRICS.join(', ')}` })
    }
    if (!VALID_PERIODS.includes(period)) {
      return reply.code(400).send({ error: `period must be one of: ${VALID_PERIODS.join(', ')}` })
    }

    const entries = await getLeaderboard(locationId, metric, period, limit)
    return reply.send({ locationId, metric, period, entries })
  })
}
