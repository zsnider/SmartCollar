-- Migration 001: Add polygon boundary support to locations
-- Run: psql $DATABASE_URL -f src/db/migrations/001_add_boundary.sql

-- Store the OpenStreetMap element ID so re-seeding upserts instead of duplicating
ALTER TABLE locations ADD COLUMN IF NOT EXISTS osm_id TEXT;

-- The actual park boundary as a polygon (or multipolygon) from OSM
-- GEOMETRY (not GEOGRAPHY) so we can use ST_IsValid / ST_MakeValid easily
ALTER TABLE locations ADD COLUMN IF NOT EXISTS boundary GEOMETRY(GEOMETRY, 4326);

-- Quick flag so the geofence query can skip the boundary check for circle-only rows
ALTER TABLE locations ADD COLUMN IF NOT EXISTS has_boundary BOOLEAN NOT NULL DEFAULT FALSE;

-- Unique index on osm_id so seed upserts work correctly
CREATE UNIQUE INDEX IF NOT EXISTS locations_osm_id_idx
  ON locations (osm_id)
  WHERE osm_id IS NOT NULL;

-- Spatial index on the boundary polygon for fast ST_Contains queries
CREATE INDEX IF NOT EXISTS locations_boundary_idx
  ON locations USING GIST (boundary)
  WHERE boundary IS NOT NULL;
