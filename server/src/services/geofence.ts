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
  hasBoundary: boolean
}

/**
 * Find all locations whose geofence (polygon or circle) contains the given point.
 * For locations with a real OSM boundary polygon, uses ST_Contains.
 * For point-only locations, falls back to ST_DWithin with radius_meters.
 */
export async function findNearbyLocations(
  lat: number,
  lng: number,
  searchRadiusMeters = 500
): Promise<NearbyLocation[]> {
  const { rows } = await db.query(
    `SELECT
       id, name, type, radius_meters, is_verified, has_boundary,
       ST_Y(coordinates::geometry)                                    AS lat,
       ST_X(coordinates::geometry)                                    AS lng,
       ST_Distance(
         coordinates,
         ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography
       )                                                              AS distance_meters
     FROM locations
     WHERE
       -- Polygon check: point is inside the actual park boundary
       (has_boundary = true
        AND ST_Contains(
          boundary,
          ST_SetSRID(ST_MakePoint($2, $1), 4326)
        ))
       OR
       -- Circle fallback: within radius_meters of the centre point
       (has_boundary = false
        AND ST_DWithin(
          coordinates,
          ST_SetSRID(ST_MakePoint($2, $1), 4326)::geography,
          radius_meters
        ))
       OR
       -- Wide search: include everything within searchRadiusMeters so
       -- the /locations/nearby endpoint still returns a useful list
       ST_DWithin(
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
    hasBoundary: r.has_boundary,
  }))
}

/**
 * Check whether a coordinate is strictly inside a specific location's boundary.
 * Uses ST_Contains for polygon locations, ST_DWithin for circle locations.
 * This is the authoritative "is this dog inside the park?" check.
 */
export async function isInsideGeofence(
  locationId: string,
  lat: number,
  lng: number
): Promise<boolean> {
  const { rows } = await db.query(
    `SELECT
       CASE
         WHEN has_boundary THEN
           ST_Contains(
             boundary,
             ST_SetSRID(ST_MakePoint($3, $2), 4326)
           )
         ELSE
           ST_DWithin(
             coordinates,
             ST_SetSRID(ST_MakePoint($3, $2), 4326)::geography,
             radius_meters
           )
       END AS inside
     FROM locations WHERE id = $1`,
    [locationId, lat, lng]
  )
  return rows[0]?.inside ?? false
}
