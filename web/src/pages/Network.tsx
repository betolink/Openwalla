import { useCallback, useEffect, useState } from 'react'
import {
  Activity,
  Bell,
  Gauge,
  Globe2,
  Network as NetworkIcon,
  RefreshCw,
  Shield,
  Wifi,
} from 'lucide-react'
import {
  api,
  type GeoIPLookupResult,
  type NetworkStatus,
  type NotificationItem,
  type SpeedTestResult,
  type Topology,
} from '../api'
import { Badge, Button, Card, Empty, Input, PageHeader, Stat } from '../components/ui'
import { BlockedElementsModal } from '../components/BlockedElementsModal'
import { formatDateTime } from '../utils/format'

function mbps(value?: number | null) {
  if (value === undefined || value === null) return '—'
  return `${value.toFixed(1)} Mbps`
}

function kbitToMbps(value: number) {
  return `${(value / 1000).toFixed(0)} Mbps`
}

export function Network() {
  const [status, setStatus] = useState<NetworkStatus | null>(null)
  const [topology, setTopology] = useState<Topology | null>(null)
  const [notifications, setNotifications] = useState<NotificationItem[]>([])
  const [blockedOpen, setBlockedOpen] = useState(false)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [countryInput, setCountryInput] = useState('')
  const [lookupIp, setLookupIp] = useState('')
  const [lookupResult, setLookupResult] = useState<GeoIPLookupResult | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const [network, graph, alerts] = await Promise.all([
        api.getNetworkStatus(),
        api.getTopology(),
        api.listNotifications(),
      ])
      setStatus(network)
      setTopology(graph)
      setNotifications(alerts.items)
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to load network')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  const countryKey = status?.geoip.countries.join(' ') ?? ''
  useEffect(() => {
    setCountryInput(countryKey)
  }, [countryKey])

  const saveGeoIP = async (countries: string[]) => {
    setBusy('geoip')
    setError(null)
    setNotice(null)
    try {
      await api.setGeoIP(countries)
      setNotice(
        countries.length
          ? `GeoIP blocking set to ${countries.join(', ').toUpperCase()}`
          : 'GeoIP country blocking cleared',
      )
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'GeoIP update failed')
    } finally {
      setBusy(null)
    }
  }

  const applyCountryInput = () => {
    const countries = countryInput
      .toLowerCase()
      .split(/[\s,]+/)
      .filter(Boolean)
    void saveGeoIP(countries)
  }

  const lookupAddress = async () => {
    const address = lookupIp.trim()
    if (!address) return
    setBusy('lookup')
    setError(null)
    try {
      setLookupResult(await api.lookupGeoIP(address))
    } catch (caught) {
      setError(
        caught instanceof Error ? caught.message : 'GeoIP lookup failed',
      )
      setLookupResult(null)
    } finally {
      setBusy(null)
    }
  }

  const runSpeedtest = async () => {
    setBusy('speedtest')
    setError(null)
    setNotice(null)
    try {
      const result: SpeedTestResult = await api.runSpeedtest()
      setStatus((current) =>
        current
          ? { ...current, speedtests: [result, ...current.speedtests] }
          : current,
      )
      setNotice(
        result.status === 'OK'
          ? `Speed test finished: ${mbps(result.download)} down / ${mbps(result.upload)} up`
          : `Speed test failed: ${result.message}`,
      )
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Speed test failed')
    } finally {
      setBusy(null)
    }
  }

  const sendTest = async () => {
    setBusy('notification')
    setError(null)
    setNotice(null)
    try {
      const result = await api.testNotification()
      const channels = Object.entries(result.channels)
      setNotice(
        channels.length
          ? `Test notification sent: ${channels
              .map(([name, state]) => `${name} ${state}`)
              .join(', ')}`
          : 'Test notification stored. No external channel is configured yet.',
      )
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Notification failed')
    } finally {
      setBusy(null)
    }
  }

  const latest = status?.speedtests?.[0]
  const sqm = status?.sqm
  const banip = status?.banip
  const geoip = status?.geoip

  return (
    <div className="space-y-6">
      <PageHeader
        title="Network"
        subtitle="SQM, speed tests, threat feeds, GeoIP and topology"
        actions={
          <Button onClick={() => void load()} disabled={loading}>
            <span className="flex items-center gap-1.5">
              <RefreshCw size={13} /> Refresh
            </span>
          </Button>
        }
      />

      {error && (
        <div className="rounded-xl border border-[var(--danger)] bg-[var(--danger-soft)] px-4 py-3 text-sm text-[var(--danger)]">
          {error}
        </div>
      )}
      {notice && (
        <div className="rounded-xl border border-[var(--border)] bg-[var(--surface-2)] px-4 py-3 text-sm text-[var(--muted)]">
          {notice}
        </div>
      )}

      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <Stat
          label="SQM / CAKE"
          value={sqm?.enabled ? 'enabled' : 'disabled'}
          hint={
            sqm?.enabled
              ? `${kbitToMbps(sqm.download_kbit)} ↓ / ${kbitToMbps(sqm.upload_kbit)} ↑`
              : 'No shaping configured'
          }
        />
        <Stat
          label="Download"
          value={mbps(latest?.download)}
          hint={latest ? formatDateTime(latest.timestamp) : 'No speed test yet'}
        />
        <Stat
          label="Upload"
          value={mbps(latest?.upload)}
          hint={latest?.server || '—'}
        />
        <Stat
          label="banIP"
          value={banip?.active ? 'active' : banip?.enabled ? 'starting' : 'disabled'}
          hint={`${banip?.element_count ?? 0} blocked elements`}
        />
      </section>

      <div className="grid gap-6 xl:grid-cols-2">
        <Card
          title="SQM / bufferbloat"
          subtitle="CAKE traffic shaping on the WAN"
          actions={<Badge tone={sqm?.enabled ? 'emerald' : 'slate'}>{sqm?.qdisc || 'none'}</Badge>}
        >
          {sqm?.enabled ? (
            <div className="space-y-3 p-4 text-sm">
              <div className="grid grid-cols-2 gap-3">
                <div className="rounded-lg bg-[var(--surface-2)] p-3">
                  <p className="text-xs text-[var(--subtle)]">Download cap</p>
                  <p className="mt-1 text-lg font-semibold text-[var(--text)]">
                    {kbitToMbps(sqm.download_kbit)}
                  </p>
                </div>
                <div className="rounded-lg bg-[var(--surface-2)] p-3">
                  <p className="text-xs text-[var(--subtle)]">Upload cap</p>
                  <p className="mt-1 text-lg font-semibold text-[var(--text)]">
                    {kbitToMbps(sqm.upload_kbit)}
                  </p>
                </div>
              </div>
              <p className="text-xs text-[var(--muted)]">
                Interface <span className="font-mono">{sqm.interface}</span> ·{' '}
                <span className="font-mono">{sqm.script}</span>
              </p>
              <p className="text-xs text-[var(--subtle)]">
                Caps are set to roughly 90% of the measured 843/271 Mbps link.
              </p>
            </div>
          ) : (
            <Empty>SQM is not enabled.</Empty>
          )}
        </Card>

        <Card
          title="Speed tests"
          subtitle="Scheduled daily and on demand"
          actions={
            <Button onClick={() => void runSpeedtest()} disabled={busy !== null}>
              {busy === 'speedtest' ? 'Testing…' : 'Run now'}
            </Button>
          }
        >
          {latest ? (
            <div className="space-y-3 p-4 text-sm">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-xs text-[var(--subtle)]">Latest result</p>
                  <p className="mt-1 text-lg font-semibold text-[var(--text)]">
                    {mbps(latest.download)} ↓ / {mbps(latest.upload)} ↑
                  </p>
                </div>
                <Badge tone={latest.status === 'OK' ? 'emerald' : 'rose'}>
                  {latest.status}
                </Badge>
              </div>
              <p className="text-xs text-[var(--muted)]">
                {latest.server || 'unknown server'} · {formatDateTime(latest.timestamp)}
              </p>
              {latest.message && (
                <p className="text-xs text-[var(--subtle)]">{latest.message}</p>
              )}
            </div>
          ) : (
            <Empty>No speed tests recorded yet.</Empty>
          )}
        </Card>

        <Card
          title="banIP threat feeds"
          subtitle="External IP reputation reports, not local heuristics"
          actions={
            <div className="flex items-center gap-2">
              <Badge tone={banip?.active ? 'emerald' : 'slate'}>
                {banip?.active ? 'active' : 'off'}
              </Badge>
              <Button onClick={() => setBlockedOpen(true)}>
                View blocked
              </Button>
            </div>
          }
        >
          <div className="space-y-3 p-4 text-sm">
            <p className="text-2xl font-semibold text-[var(--text)]">
              {banip?.element_count ?? 0}{' '}
              <span className="text-sm font-normal text-[var(--muted)]">elements</span>
            </p>
            <div className="flex flex-wrap gap-1.5">
              {(banip?.feeds ?? []).map((feed) => (
                <Badge key={feed} tone="sky">
                  {feed}
                </Badge>
              ))}
            </div>
            <p className="text-xs text-[var(--subtle)]">
              Last run: {banip?.last_run || '—'}
            </p>
            <p className="text-xs text-[var(--muted)]">
              Feeds are cached locally; no external GeoIP API is used. Source:
              DShield, Feodo Tracker, ThreatView/ET and bogon lists.
            </p>
          </div>
        </Card>

        <Card
          title="GeoIP country blocks"
          subtitle="IPdeny country sets through banIP"
          actions={<Badge tone={geoip?.countries?.length ? 'amber' : 'slate'}>{geoip?.countries?.length ? 'blocking' : 'none'}</Badge>}
        >
          <div className="space-y-3 p-4 text-sm">
            <div className="flex flex-wrap gap-2">
              <Input
                className="w-44"
                placeholder="ru ir"
                value={countryInput}
                onChange={(event) => setCountryInput(event.target.value)}
              />
              <Button onClick={applyCountryInput} disabled={busy !== null}>
                {busy === 'geoip' ? 'Applying…' : 'Apply'}
              </Button>
              <Button
                onClick={() => void saveGeoIP([])}
                disabled={busy !== null || !geoip?.countries?.length}
              >
                Clear
              </Button>
            </div>
            {geoip?.countries?.length ? (
              <div className="flex flex-wrap gap-1.5">
                {geoip.countries.map((country) => (
                  <Badge key={country} tone="amber">
                    {country.toUpperCase()}
                  </Badge>
                ))}
              </div>
            ) : (
              <p className="text-[var(--muted)]">
                No countries blocked. Country sets are downloaded from IPdeny and
                cached on the router when configured.
              </p>
            )}
            <p className="text-xs text-[var(--subtle)]">
              Two-letter codes (for example <span className="font-mono">ru</span>,{' '}
              <span className="font-mono">cn</span>). Offline recognition uses
              DB-IP Lite/GeoLite2 MMDB; nothing is sent to a per-flow GeoIP service.
            </p>
            <div className="flex flex-wrap gap-2 border-t border-[var(--border)] pt-3">
              <Input
                className="w-44"
                placeholder="Look up 1.1.1.1"
                value={lookupIp}
                onChange={(event) => setLookupIp(event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === 'Enter') void lookupAddress()
                }}
              />
              <Button onClick={() => void lookupAddress()} disabled={busy !== null}>
                {busy === 'lookup' ? 'Looking up…' : 'Lookup'}
              </Button>
              {lookupResult && (
                <span className="self-center text-xs text-[var(--muted)]">
                  {lookupResult.country || 'Unknown'} ({lookupResult.country_code || '—'})
                </span>
              )}
            </div>
          </div>
        </Card>
      </div>

      <Card
        title="Topology"
        subtitle="Router, uplinks and known access points"
        actions={<Badge tone="sky">{topology?.total_devices ?? 0} devices</Badge>}
      >
        {topology ? (
          <div className="grid gap-4 p-4 md:grid-cols-3">
            <div className="rounded-xl border border-[var(--border)] bg-[var(--surface-2)] p-4">
              <p className="flex items-center gap-2 text-sm font-medium text-[var(--text)]">
                <Globe2 size={15} /> {topology.wan.label}
              </p>
              <p className="mt-1 text-xs text-[var(--subtle)]">{topology.wan.detail}</p>
              <div className="my-2 h-px bg-[var(--border)]" />
              <p className="text-sm font-medium text-[var(--text)]">
                {topology.router.name}
              </p>
              <p className="text-xs text-[var(--subtle)]">
                {topology.router.address} · {topology.router.model || 'OpenWrt'}
              </p>
            </div>
            <div className="rounded-xl border border-[var(--border)] bg-[var(--surface-2)] p-4">
              <p className="flex items-center gap-2 text-sm font-medium text-[var(--text)]">
                <NetworkIcon size={15} /> {topology.lan.label}
              </p>
              <p className="mt-1 text-xs text-[var(--subtle)]">{topology.lan.detail}</p>
              <div className="mt-3 space-y-1 text-xs text-[var(--muted)]">
                <p className="flex items-center gap-2">
                  <Wifi size={13} /> {topology.wireless.count} wireless
                </p>
                <p className="flex items-center gap-2">
                  <Activity size={13} /> {topology.wired.count} wired
                </p>
                {topology.unclassified.count > 0 && (
                  <p className="flex items-center gap-2">
                    <NetworkIcon size={13} /> {topology.unclassified.count} unclassified
                  </p>
                )}
              </div>
            </div>
            <div className="rounded-xl border border-[var(--border)] bg-[var(--surface-2)] p-4">
              <p className="flex items-center gap-2 text-sm font-medium text-[var(--text)]">
                <Shield size={15} /> Access points / switches
              </p>
              <div className="mt-2 space-y-1 text-xs text-[var(--muted)]">
                {topology.access_points.length ? (
                  topology.access_points.map((device) => (
                    <p key={device.id}>
                      {device.display_name || device.hostname || device.mac} ·{' '}
                      <span className="font-mono">{device.ipv4 || '—'}</span>
                    </p>
                  ))
                ) : (
                  <p className="text-[var(--subtle)]">No infrastructure devices identified yet.</p>
                )}
              </div>
            </div>
          </div>
        ) : (
          <Empty>No topology data.</Empty>
        )}
      </Card>

      <Card
        title="Alerts"
        subtitle="Notification delivery and test"
        actions={
          <Button onClick={() => void sendTest()} disabled={busy !== null}>
            <span className="flex items-center gap-1.5">
              <Bell size={13} /> Send test
            </span>
          </Button>
        }
      >
        <div className="space-y-3 p-4 text-sm">
          <p className="text-[var(--muted)]">
            Notifications are stored in the control database and can also be
            delivered to ntfy or a generic webhook. Collector disconnects and
            recoveries are monitored automatically.
          </p>
          <div className="space-y-2 border-t border-[var(--border)] pt-3">
            {notifications.slice(0, 5).map((item) => (
              <div
                key={item.id}
                className="rounded-lg bg-[var(--surface-2)] px-3 py-2"
              >
                <div className="flex items-center justify-between gap-2">
                  <p className="text-xs font-medium text-[var(--text)]">
                    {item.title}
                  </p>
                  <span className="text-[10px] text-[var(--subtle)]">
                    {formatDateTime(item.created_at)}
                  </span>
                </div>
                {item.body && (
                  <p className="mt-1 text-xs text-[var(--muted)]">{item.body}</p>
                )}
              </div>
            ))}
            {notifications.length === 0 && (
              <p className="text-xs text-[var(--subtle)]">No notifications yet.</p>
            )}
          </div>
          <p className="text-xs text-[var(--subtle)]">
            Configure <span className="font-mono">OPENWALLA_NTFY_URL</span> or{' '}
            <span className="font-mono">OPENWALLA_WEBHOOK_URL</span> in the API
            environment.
          </p>
          <p className="flex items-center gap-2 text-xs text-[var(--subtle)]">
            <Gauge size={13} /> Speed-test alerts can be layered on this channel next.
          </p>
        </div>
      </Card>

      <BlockedElementsModal
        open={blockedOpen}
        onClose={() => setBlockedOpen(false)}
      />
    </div>
  )
}
