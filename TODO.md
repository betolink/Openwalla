# OpenWalla TODO

Updated: 2026-10-31

## Now — API backend (TDD)

- [x] Control-plane SQLite schema + tests (`app/control_db.py`)
- [x] LuCI RPC client + tests (`app/router_client.py`)
- [x] OpenAPI 3.0 contract (`openwalla-server/openapi.yaml`)
- [x] API tests written first (`tests/test_control_api.py`, currently red)
- [x] Shared auth/agent dependencies (`app/deps.py`)
- [x] Routers / devices / interfaces routes
- [x] Policies / groups / parental routes
- [x] Adblock / agent / events / auth routes
- [x] Wire `api_router` into `app/main.py` + `app.state`
- [x] Full server test suite green (42 tests)
- [x] Commit + push the backend slice

## Next — Web dashboard (primary deliverable)

- [ ] Scaffold `web/` (Vite + React + TypeScript + Tailwind)
- [ ] API client generated/typed from `openapi.yaml`
- [ ] Overview page (WAN/LAN, devices online, live throughput)
- [ ] Devices list + device detail + pause/block
- [ ] Traffic history/live charts
- [ ] Policies + groups builder
- [ ] Parental profiles/schedules/quotas
- [ ] Adblock status/settings
- [ ] Events + notifications
- [ ] System/settings page
- [ ] Auth login/logout
- [ ] Deploy at `net.betolink.cloud` via Traefik + Cloudflare Access

## Next — Router integration

- [ ] Register betowrt in the API (`POST /api/v1/routers`)
- [ ] Sync devices/interfaces from `192.168.0.1` over LuCI RPC
- [ ] Dedicated router API user + minimal ACL
- [ ] Agent/tunnel for remote routers (outbound only)
- [ ] Enforce device actions through the agent (`openwalla-device-access`)

## Next — Mobile (OpenWalla base)

- [ ] Build `betolink/Openwalla` against betowrt
- [ ] Confirm luci-mobile client also connects
- [ ] Merge `cogwheel0/luci-mobile` incrementally:
  - [ ] `pubspec` (Riverpod 3, secure_storage 11)
  - [ ] `lib/services` + `lib/state`
  - [ ] screens/widgets
  - [ ] platform/binary files
- [ ] Add web/API features to the app where useful

## Later — Deployment, security, reliability

- [ ] API container in Docker Swarm
- [ ] Traefik router for `net.betolink.cloud`
- [ ] Cloudflare Access policy + MFA
- [ ] Secrets in vault
- [ ] Backups (API DB, OpenWrt config, switch config)
- [ ] Health checks + rollback procedure
- [ ] Postgres evaluation for multi-router

## Known placeholders (do not ship as final)

- Device traffic endpoint returns empty samples.
- Live traffic SSE endpoint not implemented yet.
- Device actions update desired state in SQLite; router enforcement is pending.
- Vendor lookup is empty; `clients.md`/OUI can seed it.
- Multi-router server support is single-DB first.
