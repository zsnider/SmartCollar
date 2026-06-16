# SmartCollar

A social fitness app for dogs. Integrates with any smart collar (Fi, Whistle, Tractive, or generic BLE) and creates location-based leaderboards at dog parks, trails, and other spots.

## Repo structure

```
smartcollar/
├── server/       Node.js + TypeScript API (Fastify, PostgreSQL + PostGIS, Redis)
├── ios/          Native iOS app (SwiftUI, CoreBluetooth, CoreLocation)
├── docker-compose.yml
└── README.md
```

## Quick start — backend

### Prerequisites
- Node.js 20+
- Docker + Docker Compose

### Run

```bash
# 1. Start Postgres + Redis
docker compose up -d

# 2. Install dependencies
cd server && npm install

# 3. Configure environment
cp .env.example .env  # edit as needed

# 4. Start dev server
npm run dev
```

The API will be live at `http://localhost:3000`. Health check: `GET /health`.

The database schema is applied automatically on first `docker compose up` via the init script.

## Quick start — iOS

### Prerequisites
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

### Generate and open project

```bash
cd ios
xcodegen generate
open SmartCollar.xcodeproj
```

Set your Apple Developer Team ID in `ios/project.yml` under `settings.base.DEVELOPMENT_TEAM`, then build and run on a device or simulator.

> **Note:** BLE collar reading requires a physical device. The simulator can test all other flows.

## Architecture

See [ARCHITECTURE.md](../SmartCollar/ARCHITECTURE.md) for full system design, data models, and API reference.
