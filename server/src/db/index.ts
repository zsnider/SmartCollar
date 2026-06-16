import { Pool } from 'pg'

export const db = new Pool({
  connectionString: process.env.DATABASE_URL,
})

db.on('error', (err) => {
  console.error('Unexpected pg pool error', err)
  process.exit(1)
})
