import { db } from '../db/index.js'

export interface NearbyLocation {
  id: string
  name: string
  type: string
  lat: number
  lng: number
  radiusMeters: number
  distanceMeters: number
  isVerified: boolean
}

/**
 * Find all locations whose geofence contains the given coordinate.
 * Uses PostGIS ST_DWithin for indexed spatial lookup.
 */
export async function findNearbyLocations(
  lat: number,
  lng: number,
  searchRadiusMeters: number = 500
): Promise<NearbyLocation[]> {
  const { rows } = await db.query(
    `SELECT id, name, type, radius_meters, is_verified,
            ST_Y(coordinates::geometry) AS lat,
            ST_X(coordinates::geometry) AS lng,
            ST_Distance(coordinates, ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography) AS distance_meters
     FROM locations
     WHERE ST_DWithin(
       coordinates,
       ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography,
       $3
     )
     ORDER BY distance_meters ASC`,
    [lat, lng, searchRadiusMeters]
  )

  return rows.map((r) => ({
    id: r.id,
    name: r.name,
    type: r.type,
    lat: parseFloat(r.lat),
    lng: parseFloat(r.lng),
    radiusMeters: r.radius_meters,
    distanceMeters: parseFloat(r.distance_meters),
    isVerified: r.is_verified,
  }))
}

/**
 * Check whether a coordinate is inside a specific location's geofence.
 */
export async function isInsideGeofence(
  locationId: string,
  lat: number,
  lng: number
): Promise<boolean> {
  const { rows } = await db.query(
    `SELECT ST_DWithin(
       coordinates,
       ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography,
       radius_meters
     ) AS inside
     FROM locations WHERE id = $3`,
    [lat, lng, locationId]
  )
  return rows[0]?.inside ?? false
}
