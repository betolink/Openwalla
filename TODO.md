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

## Now — Local dashboard

- [x] Web scaffold (Vite + React + TS + Tailwind)
- [x] Typed API client
- [x] Overview + Devices + Router setup pages
- [x] Firewalla-style layout: sidebar, network hero, device cards
- [x] Dark/light theme switch (light = Material purple palette)
- [x] Traffic timeseries chart on Overview and Traffic
- [x] Click-through from Overview/Devices to a device detail page
- [x] Device detail: 1h / 12h / 1d / 7d ranges, MB totals, chart
- [x] Device detail: most-visited websites (Netify) and device info
- [x] Overview device cards expose a “View details” link
- [x] Devices table + detail header allow renaming (persists across router syncs)
- [x] Fixed nlbwmon separator parsing and netlink buffer (MB data flows)
- [x] Moved Netify + bandwidth DBs to `/overlay` SSD; 7-day retention
- [x] Single collector instance (init kills stale worker processes)
- [x] Web tests + production build green (11 tests)
- [x] Run backend locally and connect betowrt (26 devices synced)
- [x] Netify flows wired to the API (flows + 5-minute series)
- [x] Ansible deployment playbook (`clusterfunk/playbooks/29-openwalla.yml`)
- [x] Adblock page backed by router state (network-wide)
- [x] Parental profiles backed by router state (members, pause, daily limit,
      schedules)
- [x] Policy/group internet-block enforcement
- [x] Device block/pause and adblock enforcement
- [x] Backups + restore archive (scheduled, 14-day retention)
- [x] Enforcement-failure notifications
- [x] Reproducible router helper bootstrap in Ansible
- [x] Monthly DB-IP GeoIP refresh
- [x] Deduped flow counts + real per-device traffic endpoint
- [x] Live SSE traffic stream
- [ ] Per-client content filtering / safe search (AdGuard cutover)
- [ ] Upgrade/rollback and E2E/reboot tests
- [x] Dashboard deployed at `net.betolink.cloud` with app login + basic auth
- [x] Dedicated host1 → betowrt SSH key mounted into the API container

## Phase 2-A — implemented 2026-10-31

- [x] SQM/CAKE enabled on `eth1` at 720/230 Mbps (90% of measured link)
- [x] `speedtest-go` installed; daily monitor writes to
      `/overlay/openwalla/openwalla-speedtest-monitor.txt`
- [x] Network page: SQM, speed tests, banIP, GeoIP, topology, alerts
- [x] banIP enabled with `dshield feodo threat bogon` (~4k elements)
- [x] GeoIP country blocking via banIP/IPdeny; set/clear from dashboard
- [x] Offline GeoIP lookup (DB-IP Lite MMDB) via API
- [x] Notification storage + ntfy/webhook delivery + test button
- [x] Collector disconnect/recovery alert monitor
- [x] Basic topology from inventory and AP hostnames

## Phase 2-B — next

- [ ] AdGuard Home per-client DNS + safe search
- [ ] NordVPN policy routing for one test VLAN/device
- [ ] Per-device bandwidth limits
- [ ] Then per-app/category rules

## Feature wiring status

| Feature | Dashboard | Router side |
|---------|-----------|-------------|
| Router list / sync | yes | LuCI RPC |
| Device inventory | yes | LuCI RPC + collectors |
| Device rename | yes | control DB display-name override |
| Device detail (1h/12h/1d/7d) | yes | router bandwidth DB via SSH |
| Top websites per device | yes | Netify flows (7d on SSD) |
| Device block / pause | yes | enforced via `device-access` + nftables/firewall |
| Adblock | yes | network-wide OpenWrt adblock engine (350k domains) |
| Parental / policies | yes | parental + internet-block policies enforced |
| Backups | yes | daily SQLite/env/router archive, 14-day retention |
| Live traffic | yes | SSE `/traffic/live` |
| Content filtering | no | AdGuard Home cutover pending |
| Traffic / flows | yes | Netify collector connected |
| Traffic timeseries | yes | `flow_raw` 5-minute buckets |
| Policies / groups | UI only (control DB) | enforcement pending |
| Events | yes (control DB) | router event sync pending |
| SQM / bufferbloat | yes | CAKE on `eth1` (720/230 Mbps) |
| Speed tests | yes | `speedtest-go` daily + on demand |
| banIP threat feeds | yes | dshield/feodo/threat/bogon |
| GeoIP country blocks | yes | banIP + IPdeny; offline MMDB lookup |
| Notifications | yes | ntfy/webhook + control DB |
| Topology | basic | inventory + AP hostnames |
| AdGuard | no | adblock active instead |
| Suricata | no | not packaged in 25.12 |

## Next — Web dashboard (primary deliverable)

- [ ] Generate a typed client from `openapi.yaml` (replace hand-written client)
- [ ] Traffic history/live charts
- [ ] Policies + groups builder
- [ ] Parental profiles/schedules/quotas
- [ ] Adblock status/settings
- [ ] Events + notifications
- [ ] System/settings page
- [ ] Deploy at `net.betolink.cloud` via Traefik + Cloudflare Access

## Next — Router integration

- [x] Register betowrt in the API (`POST /api/v1/routers`)
- [x] Sync devices/interfaces from `192.168.0.1` over LuCI RPC
- [x] Provision a dedicated SSH key from the API host to betowrt for
      helper reads and enforcement
- [x] Install feature packages on betowrt:
      `sqlite3-cli conntrack nlbwmon vnstat2 netifyd banip sqm-scripts`
- [x] Install OpenWalla helpers via Router Setup (devices, bandwidth, parental,
      scheduler, blocking, conntrack, netify, quarantine, notifications)
- [x] Configure Netify LAN listener + backend collector (flows flowing)
- [x] Adblock active (350k domains; adguard/adguard_tracking/certpl feeds)
- [ ] Choose AdGuard Home **or** keep adblock (adblock is active now)
- [ ] Enable banIP and configure SQM on WAN
- [ ] Agent sync for adblock/parental/device data into the API
- [ ] Suricata feasibility: not packaged in 25.12 (build/external sensor/later)
- [ ] Screen-time caveat: counts network-active minutes, not screen-on
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
