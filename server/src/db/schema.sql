-- Enable PostGIS for geospatial queries
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS postgis;

-- Users
CREATE TABLE IF NOT EXISTS users (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email        TEXT UNIQUE NOT NULL,
  display_name TEXT NOT NULL,
  avatar_url   TEXT,
  password_hash TEXT NOT NULL,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Dogs
CREATE TABLE IF NOT EXISTS dogs (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  breed        TEXT,
  weight_lbs   FLOAT,
  avatar_url   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Collars
CREATE TABLE IF NOT EXISTS collars (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  dog_id           UUID NOT NULL REFERENCES dogs(id) ON DELETE CASCADE,
  provider         TEXT NOT NULL CHECK (provider IN ('fi', 'whistle', 'tractive', 'ble_generic')),
  external_id      TEXT,
  oauth_tokens     JSONB,
  ble_service_uuid TEXT,
  last_synced_at   TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Locations (dog parks, trails, etc.)
CREATE TABLE IF NOT EXISTS locations (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name          TEXT NOT NULL,
  type          TEXT NOT NULL CHECK (type IN ('dog_park', 'trail', 'beach', 'other')),
  coordinates   GEOGRAPHY(POINT, 4326) NOT NULL,
  radius_meters INT NOT NULL DEFAULT 100,
  created_by    UUID REFERENCES users(id) ON DELETE SET NULL,
  is_verified   BOOLEAN NOT NULL DEFAULT FALSE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS locations_coordinates_idx ON locations USING GIST (coordinates);

-- Sessions
CREATE TABLE IF NOT EXISTS sessions (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  dog_id         UUID NOT NULL REFERENCES dogs(id) ON DELETE CASCADE,
  location_id    UUID REFERENCES locations(id) ON DELETE SET NULL,
  started_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at       TIMESTAMPTZ,
  entry_method   TEXT NOT NULL CHECK (entry_method IN ('geofence', 'checkin')),
  total_steps    INT NOT NULL DEFAULT 0,
  max_speed_mph  FLOAT NOT NULL DEFAULT 0,
  avg_speed_mph  FLOAT NOT NULL DEFAULT 0,
  peak_accel_g   FLOAT NOT NULL DEFAULT 0,
  duration_secs  INT
);

-- Metrics (time-series readings per session)
CREATE TABLE IF NOT EXISTS metrics (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  session_id     UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  collar_id      UUID NOT NULL REFERENCES collars(id) ON DELETE CASCADE,
  recorded_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  steps          INT NOT NULL DEFAULT 0,
  speed_mph      FLOAT NOT NULL DEFAULT 0,
  acceleration_g FLOAT NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS metrics_session_idx ON metrics (session_id, recorded_at DESC);

-- Refresh tokens
CREATE TABLE IF NOT EXISTS refresh_tokens (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token_hash TEXT NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
