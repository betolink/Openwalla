import { useCallback, useEffect, useState } from 'react'
import { ChevronLeft, ChevronRight, Search, ShieldCheck, X } from 'lucide-react'
import {
  api,
  type BlockedElement,
  type BlockedElementsResponse,
} from '../api'
import { Badge, Button, Empty, Input } from './ui'

const PAGE_SIZE = 100

const feedDescriptions: Record<string, string> = {
  dshield: 'DShield top attacking networks',
  feodo: 'Feodo Tracker botnet command-and-control',
  threat: 'ThreatView / emerging threat IPs',
  bogon: 'reserved / bogon address space',
  country: 'IPdeny country blocks',
}

function feedDescription(feed: string) {
  return feedDescriptions[feed] ?? 'external reputation feed'
}

export function BlockedElementsModal({
  open,
  onClose,
}: {
  open: boolean
  onClose: () => void
}) {
  const [data, setData] = useState<BlockedElementsResponse | null>(null)
  const [queryInput, setQueryInput] = useState('')
  const [appliedSearch, setAppliedSearch] = useState('')
  const [feed, setFeed] = useState('')
  const [offset, setOffset] = useState(0)
  const [loading, setLoading] = useState(false)
  const [busyIp, setBusyIp] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)

  const load = useCallback(
    async (nextOffset: number) => {
      setLoading(true)
      setError(null)
      try {
        setData(
          await api.getBlockedElements({
            search: appliedSearch,
            feed,
            limit: PAGE_SIZE,
            offset: nextOffset,
          }),
        )
        setOffset(nextOffset)
      } catch (caught) {
        setError(
          caught instanceof Error ? caught.message : 'Unable to load blocked elements',
        )
      } finally {
        setLoading(false)
      }
    },
    [appliedSearch, feed],
  )

  useEffect(() => {
    if (open) void load(0)
  }, [open, load])

  if (!open) return null

  const allow = async (item: BlockedElement) => {
    setBusyIp(item.ip)
    setError(null)
    setNotice(null)
    try {
      const result = await api.allowBlockedIP(item.ip)
      setNotice(
        result.changed
          ? `${item.ip} added to the allowlist and banIP reloaded.`
          : `${item.ip} was already allowlisted.`,
      )
      await load(offset)
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Allowlist failed')
    } finally {
      setBusyIp(null)
    }
  }

  const total = data?.total ?? 0
  const pageStart = total === 0 ? 0 : offset + 1
  const pageEnd = Math.min(offset + PAGE_SIZE, total)

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
      onClick={onClose}
      role="presentation"
    >
      <div
        className="flex max-h-[88vh] w-full max-w-6xl flex-col overflow-hidden rounded-2xl border border-[var(--border)] bg-[var(--surface)] shadow-2xl"
        onClick={(event) => event.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-label="Blocked elements"
      >
        <div className="flex items-start justify-between gap-4 border-b border-[var(--border)] px-5 py-4">
          <div>
            <h2 className="text-lg font-semibold text-[var(--text-strong)]">
              Blocked elements
            </h2>
            <p className="mt-1 text-xs text-[var(--subtle)]">
              External reputation feeds — not local heuristics. Click allow to
              add an address or CIDR to the banIP allowlist.
            </p>
          </div>
          <Button onClick={onClose}>
            <span className="flex items-center gap-1.5">
              <X size={13} /> Close
            </span>
          </Button>
        </div>

        <div className="space-y-3 border-b border-[var(--border)] px-5 py-3">
          <div className="flex flex-wrap items-center gap-2">
            <Input
              className="w-64"
              placeholder="Search IP or feed"
              value={queryInput}
              onChange={(event) => setQueryInput(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === 'Enter') {
                  setAppliedSearch(queryInput.trim())
                }
              }}
            />
            <Button
              onClick={() => setAppliedSearch(queryInput.trim())}
              disabled={loading}
            >
              <span className="flex items-center gap-1.5">
                <Search size={13} /> Search
              </span>
            </Button>
            <Button
              onClick={() => {
                setQueryInput('')
                setAppliedSearch('')
              }}
              disabled={loading || (!queryInput && !appliedSearch)}
            >
              Reset
            </Button>
            <span className="text-xs text-[var(--subtle)]">
              {total.toLocaleString()} blocked · {pageStart}–{pageEnd}
            </span>
          </div>
          <div className="flex flex-wrap gap-1.5">
            <button
              type="button"
              onClick={() => setFeed('')}
              className={`rounded-full px-2.5 py-1 text-[11px] ${
                feed === ''
                  ? 'bg-[var(--accent-soft)] text-[var(--accent-text)]'
                  : 'bg-[var(--surface-2)] text-[var(--muted)]'
              }`}
            >
              all
            </button>
            {(data?.feeds ?? []).map((item) => (
              <button
                key={item.name}
                type="button"
                onClick={() => setFeed(item.name)}
                className={`rounded-full px-2.5 py-1 text-[11px] ${
                  feed === item.name
                    ? 'bg-[var(--accent-soft)] text-[var(--accent-text)]'
                    : 'bg-[var(--surface-2)] text-[var(--muted)]'
                }`}
                title={feedDescription(item.name)}
              >
                {item.name} · {item.count.toLocaleString()}
              </button>
            ))}
          </div>
          {feed && (
            <p className="text-[11px] text-[var(--subtle)]">
              {feedDescription(feed)}
            </p>
          )}
        </div>

        {error && (
          <div className="mx-5 mt-3 rounded-lg border border-[var(--danger)] bg-[var(--danger-soft)] px-3 py-2 text-xs text-[var(--danger)]">
            {error}
          </div>
        )}
        {notice && (
          <div className="mx-5 mt-3 rounded-lg border border-[var(--border)] bg-[var(--surface-2)] px-3 py-2 text-xs text-[var(--muted)]">
            {notice}
          </div>
        )}

        <div className="min-h-0 flex-1 overflow-auto">
          <table className="min-w-full text-left text-sm">
            <thead className="sticky top-0 bg-[var(--surface)] text-xs uppercase tracking-wide text-[var(--subtle)]">
              <tr>
                <th className="px-4 py-2">Address</th>
                <th className="px-4 py-2">Feed</th>
                <th className="px-4 py-2">Family</th>
                <th className="px-4 py-2">Hits</th>
                <th className="px-4 py-2">Action</th>
              </tr>
            </thead>
            <tbody>
              {(data?.items ?? []).map((item) => (
                <tr
                  key={`${item.feed}-${item.ip}`}
                  className="border-t border-[var(--border)]"
                >
                  <td className="px-4 py-2 font-mono text-xs text-[var(--text)]">
                    {item.ip}
                  </td>
                  <td className="px-4 py-2">
                    <Badge tone="sky">{item.feed}</Badge>
                  </td>
                  <td className="px-4 py-2 text-xs text-[var(--muted)]">
                    {item.family}
                  </td>
                  <td className="px-4 py-2 text-xs text-[var(--muted)]">
                    {item.packets.toLocaleString()} packets
                  </td>
                  <td className="px-4 py-2">
                    <Button
                      onClick={() => void allow(item)}
                      disabled={busyIp !== null}
                    >
                      <span className="flex items-center gap-1">
                        <ShieldCheck size={12} />
                        {busyIp === item.ip ? 'Allowing…' : 'Allow'}
                      </span>
                    </Button>
                  </td>
                </tr>
              ))}
              {(data?.items ?? []).length === 0 && (
                <tr>
                  <td colSpan={5}>
                    <Empty>
                      {loading ? 'Loading blocked elements…' : 'No blocked elements match.'}
                    </Empty>
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>

        <div className="flex items-center justify-between gap-3 border-t border-[var(--border)] px-5 py-3">
          <span className="text-xs text-[var(--subtle)]">
            {loading ? 'Loading…' : data?.source ?? ''}
          </span>
          <div className="flex gap-2">
            <Button
              onClick={() => void load(Math.max(0, offset - PAGE_SIZE))}
              disabled={loading || offset === 0}
            >
              <span className="flex items-center gap-1">
                <ChevronLeft size={13} /> Prev
              </span>
            </Button>
            <Button
              onClick={() => void load(offset + PAGE_SIZE)}
              disabled={loading || offset + PAGE_SIZE >= total}
            >
              <span className="flex items-center gap-1">
                Next <ChevronRight size={13} />
              </span>
            </Button>
          </div>
        </div>
      </div>
    </div>
  )
}
