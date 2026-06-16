/**
 * Seed dog parks and trails from OpenStreetMap for a given city.
 * Uses the Overpass API — no API key required.
 *
 * Usage:
 *   npx tsx src/db/seed-locations.ts
 *   npx tsx src/db/seed-locations.ts "San Francisco"
 */

import 'dotenv/config'
import { db } from './index.js'

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const CITY = process.argv[2] ?? 'San Diego, California'

// Overpass search radius around the city centre in metres
const RADIUS_M = 40_000

// How big a geofence to create for each location (metres)
const DEFAULT_GEOFENCE_RADIUS = 120

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface OverpassElement {
  type: 'node' | 'way' | 'relation'
  id: number
  lat?: number
  lon?: number
  center?: { lat: number; lon: number }
  tags?: Record<string, string>
}

interface OverpassResponse {
  elements: OverpassElement[]
}

interface NominatimResult {
  lat: string
  lon: string
  display_name: string
}

// ---------------------------------------------------------------------------
// Step 1: Geocode the city name → lat/lng
// ---------------------------------------------------------------------------

async function geocodeCity(city: string): Promise<{ lat: number; lng: number }> {
  const url = `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(city)}&format=json&limit=1`
  console.log(`📍 Geocoding "${city}"...`)

  const res = await fetch(url, {
    headers: { 'User-Agent': 'SmartCollarApp/1.0 (seed script)' },
  })
  if (!res.ok) throw new Error(`Nominatim error: ${res.status}`)

  const results = (await res.json()) as NominatimResult[]
  if (!results.length) throw new Error(`City not found: "${city}"`)

  const { lat, lon, display_name } = results[0]
  console.log(`   Found: ${display_name}`)
  return { lat: parseFloat(lat), lng: parseFloat(lon) }
}

// ---------------------------------------------------------------------------
// Step 2: Fetch dog parks + trails from Overpass
// ---------------------------------------------------------------------------

async function fetchDogParks(lat: number, lng: number): Promise<OverpassElement[]> {
  const query = `
    [out:json][timeout:30];
    (
      node["leisure"="dog_park"](around:${RADIUS_M},${lat},${lng});
      way["leisure"="dog_park"](around:${RADIUS_M},${lat},${lng});
      relation["leisure"="dog_park"](around:${RADIUS_M},${lat},${lng});

      node["leisure"="park"]["dog"="yes"](around:${RADIUS_M},${lat},${lng});
      way["leisure"="park"]["dog"="yes"](around:${RADIUS_M},${lat},${lng});

      node["leisure"="nature_reserve"]["dog"="yes"](around:${RADIUS_M},${lat},${lng});
      way["leisure"="nature_reserve"]["dog"="yes"](around:${RADIUS_M},${lat},${lng});

      way["highway"="path"]["dog"="yes"](around:${RADIUS_M},${lat},${lng});
      way["route"="hiking"]["dog"="yes"](around:${RADIUS_M},${lat},${lng});
    );
    out center tags;
  `

  console.log(`\n🌍 Querying OpenStreetMap Overpass API...`)
  const url = `https://overpass-api.de/api/interpreter?data=${encodeURIComponent(query)}`
  const res = await fetch(url, {
    headers: { 'User-Agent': 'SmartCollarApp/1.0 (seed script)' },
  })

  if (!res.ok) {
    const body = await res.text()
    throw new Error(`Overpass error: ${res.status} — ${body.slice(0, 200)}`)
  }
  const data = (await res.json()) as OverpassResponse
  console.log(`   Got ${data.elements.length} raw elements`)
  return data.elements
}

// ---------------------------------------------------------------------------
// Step 3: Normalise elements → location rows
// ---------------------------------------------------------------------------

interface LocationRow {
  name: string
  type: 'dog_park' | 'trail' | 'beach' | 'other'
  lat: number
  lng: number
  radiusMeters: number
}

function normalise(elements: OverpassElement[]): LocationRow[] {
  const seen = new Set<string>()
  const rows: LocationRow[] = []

  for (const el of elements) {
    const tags = el.tags ?? {}
    const name = tags.name ?? tags['name:en'] ?? null

    // Must have a name — unnamed parks aren't useful on a leaderboard
    if (!name) continue

    // Coordinates — nodes have lat/lon directly, ways/relations expose a centroid
    const lat = el.lat ?? el.center?.lat
    const lng = el.lon ?? el.center?.lon
    if (lat == null || lng == null) continue

    // Deduplicate by name + approximate position
    const key = `${name.toLowerCase()}|${lat.toFixed(3)}|${lng.toFixed(3)}`
    if (seen.has(key)) continue
    seen.add(key)

    // Classify
    const leisure = tags.leisure ?? ''
    const highway = tags.highway ?? ''
    const route = tags.route ?? ''
    const naturalTag = tags.natural ?? ''

    let type: LocationRow['type'] = 'other'
    if (leisure === 'dog_park') type = 'dog_park'
    else if (naturalTag === 'beach' || tags.beach) type = 'beach'
    else if (highway === 'path' || route === 'hiking') type = 'trail'
    else if (leisure === 'park' || leisure === 'nature_reserve') type = 'dog_park'

    // Give trails a smaller default geofence (path-shaped, not a polygon)
    const radiusMeters = type === 'trail' ? 60 : DEFAULT_GEOFENCE_RADIUS

    rows.push({ name: name.trim(), type, lat, lng, radiusMeters })
  }

  return rows
}

// ---------------------------------------------------------------------------
// Step 4: Upsert into Postgres
// ---------------------------------------------------------------------------

async function upsertLocations(rows: LocationRow[]): Promise<void> {
  console.log(`\n💾 Inserting ${rows.length} locations into Postgres...`)

  let inserted = 0
  let skipped = 0

  for (const row of rows) {
    try {
      const result = await db.query(
        `INSERT INTO locations (name, type, coordinates, radius_meters, is_verified)
         VALUES ($1, $2, ST_SetSRID(ST_MakePoint($4, $3), 4326), $5, true)
         ON CONFLICT DO NOTHING
         RETURNING id`,
        [row.name, row.type, row.lat, row.lng, row.radiusMeters]
      )
      if (result.rowCount) {
        inserted++
        console.log(`   ✅ ${row.type.padEnd(10)} ${row.name}`)
      } else {
        skipped++
      }
    } catch (err) {
      console.warn(`   ⚠️  Failed to insert "${row.name}":`, (err as Error).message)
    }
  }

  console.log(`\n✨ Done — inserted ${inserted}, skipped ${skipped} duplicates.`)
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  console.log(`\n🐾 SmartCollar Location Seeder`)
  console.log(`   City: ${CITY}\n`)

  try {
    const { lat, lng } = await geocodeCity(CITY)
    const elements = await fetchDogParks(lat, lng)
    const rows = normalise(elements)

    if (!rows.length) {
      console.log('⚠️  No named locations found. Try a different city.')
      process.exit(0)
    }

    await upsertLocations(rows)
  } catch (err) {
    console.error('❌ Seed failed:', (err as Error).message)
    process.exit(1)
  } finally {
    await db.end()
  }
}

main()
