/**
 * Seed dog parks and trails from OpenStreetMap for a given city.
 * Fetches real polygon boundaries for ways; falls back to circle for point nodes.
 * Re-running is safe — rows are upserted by OSM element ID.
 *
 * Usage:
 *   npm run db:seed                        # defaults to San Diego
 *   npm run db:seed "Los Angeles, CA"
 */

import 'dotenv/config'
import { db } from './index.js'

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const CITY = process.argv[2] ?? 'San Diego, California'
const RADIUS_M = 40_000          // search radius around city centre
const DEFAULT_RADIUS_M = 120     // fallback circle radius for point nodes
const TRAIL_RADIUS_M = 60        // fallback for trails

// ---------------------------------------------------------------------------
// Overpass types
// ---------------------------------------------------------------------------

interface OSMNode {
  lat: number
  lon: number
}

interface OSMMember {
  type: string
  role: string
  geometry?: OSMNode[]
}

interface OverpassElement {
  type: 'node' | 'way' | 'relation'
  id: number
  lat?: number
  lon?: number
  center?: { lat: number; lon: number }
  geometry?: OSMNode[]      // populated by out geom; for ways
  members?: OSMMember[]     // populated by out geom; for relations
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
// Step 1: Geocode city
// ---------------------------------------------------------------------------

async function geocodeCity(city: string): Promise<{ lat: number; lng: number }> {
  const url = `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(city)}&format=json&limit=1`
  console.log(`📍 Geocoding "${city}"...`)
  const res = await fetch(url, { headers: { 'User-Agent': 'SmartCollarApp/1.0' } })
  if (!res.ok) throw new Error(`Nominatim error: ${res.status}`)
  const results = (await res.json()) as NominatimResult[]
  if (!results.length) throw new Error(`City not found: "${city}"`)
  console.log(`   Found: ${results[0].display_name}`)
  return { lat: parseFloat(results[0].lat), lng: parseFloat(results[0].lon) }
}

// ---------------------------------------------------------------------------
// Step 2: Fetch from Overpass with full geometry
// ---------------------------------------------------------------------------

async function fetchElements(lat: number, lng: number): Promise<OverpassElement[]> {
  // Use out geom; to get polygon coordinates for ways.
  // We run two separate queries:
  //   - nodes: just center point (no polygon to fetch)
  //   - ways + relations: full geometry
  const query = `
    [out:json][timeout:60];
    (
      node["leisure"="dog_park"](around:${RADIUS_M},${lat},${lng});
      node["leisure"="park"]["dog"="yes"](around:${RADIUS_M},${lat},${lng});
      node["natural"="beach"]["dog"="yes"](around:${RADIUS_M},${lat},${lng});
    );
    out tags;

    (
      way["leisure"="dog_park"](around:${RADIUS_M},${lat},${lng});
      way["leisure"="park"]["dog"="yes"](around:${RADIUS_M},${lat},${lng});
      way["leisure"="nature_reserve"]["dog"="yes"](around:${RADIUS_M},${lat},${lng});
      way["natural"="beach"]["dog"="yes"](around:${RADIUS_M},${lat},${lng});
      way["highway"="path"]["dog"="yes"](around:${RADIUS_M},${lat},${lng});
      relation["leisure"="dog_park"](around:${RADIUS_M},${lat},${lng});
      relation["leisure"="park"]["dog"="yes"](around:${RADIUS_M},${lat},${lng});
    );
    out geom tags;
  `

  console.log(`\n🌍 Querying OpenStreetMap Overpass API...`)
  const url = `https://overpass-api.de/api/interpreter?data=${encodeURIComponent(query)}`
  const res = await fetch(url, { headers: { 'User-Agent': 'SmartCollarApp/1.0' } })
  if (!res.ok) {
    const body = await res.text()
    throw new Error(`Overpass error: ${res.status} — ${body.slice(0, 300)}`)
  }
  const data = (await res.json()) as OverpassResponse
  console.log(`   Got ${data.elements.length} raw elements`)
  return data.elements
}

// ---------------------------------------------------------------------------
// Step 3: Build WKT polygon from way geometry
// ---------------------------------------------------------------------------

function wayToPolygonWKT(geometry: OSMNode[]): string | null {
  if (geometry.length < 4) return null   // need ≥3 unique points + closing node

  let coords = [...geometry]

  // Ensure ring is closed (first == last)
  const first = coords[0]
  const last = coords[coords.length - 1]
  if (first.lat !== last.lat || first.lon !== last.lon) {
    coords.push(first)
  }

  // WKT uses (lon lat) order
  const ring = coords.map(n => `${n.lon} ${n.lat}`).join(', ')
  return `POLYGON((${ring}))`
}

function relationToMultipolygonWKT(members: OSMMember[]): string | null {
  const outerRings: string[] = []

  for (const member of members) {
    if (member.role !== 'outer') continue
    if (!member.geometry || member.geometry.length < 4) continue

    let coords = [...member.geometry]
    const first = coords[0]
    const last = coords[coords.length - 1]
    if (first.lat !== last.lat || first.lon !== last.lon) {
      coords.push(first)
    }
    const ring = coords.map(n => `${n.lon} ${n.lat}`).join(', ')
    outerRings.push(`((${ring}))`)
  }

  if (!outerRings.length) return null
  if (outerRings.length === 1) return `POLYGON${outerRings[0]}`
  return `MULTIPOLYGON(${outerRings.map(r => `(${r})`).join(', ')})`
}

// ---------------------------------------------------------------------------
// Step 4: Classify and normalise
// ---------------------------------------------------------------------------

type LocationType = 'dog_park' | 'trail' | 'beach' | 'other'

interface LocationRow {
  osmId: string
  name: string
  type: LocationType
  lat: number
  lng: number
  radiusMeters: number
  boundaryWKT: string | null
}

function classifyType(tags: Record<string, string>): LocationType {
  const leisure = tags.leisure ?? ''
  const natural = tags.natural ?? ''
  const highway = tags.highway ?? ''
  const route = tags.route ?? ''

  if (leisure === 'dog_park') return 'dog_park'
  if (natural === 'beach') return 'beach'
  if (highway === 'path' || route === 'hiking') return 'trail'
  if (leisure === 'park' || leisure === 'nature_reserve') return 'dog_park'
  return 'other'
}

function centroid(geometry: OSMNode[]): { lat: number; lng: number } {
  const lat = geometry.reduce((s, n) => s + n.lat, 0) / geometry.length
  const lng = geometry.reduce((s, n) => s + n.lon, 0) / geometry.length
  return { lat, lng }
}

function normalise(elements: OverpassElement[]): LocationRow[] {
  const seen = new Set<string>()
  const rows: LocationRow[] = []

  for (const el of elements) {
    const tags = el.tags ?? {}
    const name = tags.name ?? tags['name:en']
    if (!name) continue

    const osmId = `${el.type}/${el.id}`
    if (seen.has(osmId)) continue
    seen.add(osmId)

    const type = classifyType(tags)
    const defaultRadius = type === 'trail' ? TRAIL_RADIUS_M : DEFAULT_RADIUS_M

    let lat: number | undefined
    let lng: number | undefined
    let boundaryWKT: string | null = null

    if (el.type === 'node') {
      lat = el.lat
      lng = el.lon
    } else if (el.type === 'way' && el.geometry?.length) {
      const c = centroid(el.geometry)
      lat = c.lat
      lng = c.lng
      boundaryWKT = wayToPolygonWKT(el.geometry)
    } else if (el.type === 'relation' && el.members?.length) {
      // Use center tag for pin position, build multipolygon from outer members
      lat = el.center?.lat
      lng = el.center?.lon
      boundaryWKT = relationToMultipolygonWKT(el.members)

      // Fallback: derive centroid from first outer member geometry
      if ((lat == null || lng == null) && el.members[0]?.geometry?.length) {
        const c = centroid(el.members[0].geometry!)
        lat = c.lat
        lng = c.lng
      }
    }

    if (lat == null || lng == null) continue

    rows.push({ osmId, name: name.trim(), type, lat, lng, radiusMeters: defaultRadius, boundaryWKT })
  }

  return rows
}

// ---------------------------------------------------------------------------
// Step 5: Upsert into Postgres
// ---------------------------------------------------------------------------

async function upsertLocations(rows: LocationRow[]): Promise<void> {
  console.log(`\n💾 Upserting ${rows.length} locations into Postgres...`)

  let withBoundary = 0
  let withCircle = 0
  let failed = 0

  for (const row of rows) {
    try {
      await db.query(
        `INSERT INTO locations
           (name, type, coordinates, radius_meters, is_verified, osm_id, boundary, has_boundary)
         VALUES (
           $1, $2,
           ST_SetSRID(ST_MakePoint($4, $3), 4326)::geography,
           $5, true, $6,
           CASE WHEN $7::text IS NOT NULL
                THEN ST_MakeValid(ST_GeomFromText($7, 4326))
                ELSE NULL END,
           $7 IS NOT NULL
         )
         ON CONFLICT (osm_id) WHERE osm_id IS NOT NULL DO UPDATE SET
           name         = EXCLUDED.name,
           coordinates  = EXCLUDED.coordinates,
           boundary     = EXCLUDED.boundary,
           has_boundary = EXCLUDED.has_boundary`,
        [row.name, row.type, row.lat, row.lng, row.radiusMeters, row.osmId, row.boundaryWKT]
      )

      if (row.boundaryWKT) {
        withBoundary++
        console.log(`   ✅ [polygon] ${row.name}`)
      } else {
        withCircle++
        console.log(`   ⭕ [circle ] ${row.name}`)
      }
    } catch (err) {
      failed++
      console.warn(`   ⚠️  Failed "${row.name}": ${(err as Error).message.split('\n')[0]}`)
    }
  }

  console.log(`
✨ Done!
   ${withBoundary} locations with real polygon boundaries
   ${withCircle} locations using fallback circle
   ${failed} failed
  `)
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main() {
  console.log(`\n🐾 SmartCollar Location Seeder (with boundaries)`)
  console.log(`   City: ${CITY}\n`)

  try {
    const { lat, lng } = await geocodeCity(CITY)
    const elements = await fetchElements(lat, lng)
    const rows = normalise(elements)

    if (!rows.length) {
      console.log('⚠️  No named locations found.')
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
