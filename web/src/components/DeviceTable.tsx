import { useState } from 'react'
import { Check, Pencil, X } from 'lucide-react'
import type { Device } from '../api'
import { Badge, Button, Input } from './ui'

function deviceLabel(device: Device) {
  return device.display_name || device.hostname || 'unknown'
}

export function DeviceTable({
  devices,
  onAction,
  onSelect,
  onRename,
  selectedId,
}: {
  devices: Device[]
  onAction?: (device: Device, action: 'block' | 'pause') => void
  onSelect?: (device: Device) => void
  onRename?: (device: Device, name: string) => Promise<void> | void
  selectedId?: string
}) {
  const [editingId, setEditingId] = useState<string | null>(null)
  const [draft, setDraft] = useState('')
  const [saving, setSaving] = useState(false)

  const beginEdit = (event: { stopPropagation: () => void }, device: Device) => {
    event.stopPropagation()
    setEditingId(device.id)
    setDraft(device.display_name || device.hostname || '')
  }

  const cancelEdit = (event?: { stopPropagation: () => void }) => {
    event?.stopPropagation()
    setEditingId(null)
    setDraft('')
  }

  const saveEdit = async (
    event: { stopPropagation: () => void },
    device: Device,
  ) => {
    event.stopPropagation()
    if (!onRename || saving) return
    setSaving(true)
    try {
      await onRename(device, draft.trim())
      setEditingId(null)
      setDraft('')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="overflow-x-auto">
      <table className="min-w-full text-left text-sm">
        <thead className="text-xs uppercase tracking-wide text-[var(--subtle)]">
          <tr>
            <th className="px-3 py-2">Device</th>
            <th className="px-3 py-2">IP</th>
            <th className="px-3 py-2">MAC</th>
            <th className="px-3 py-2">Type</th>
            <th className="px-3 py-2">State</th>
            {onAction && <th className="px-3 py-2">Actions</th>}
          </tr>
        </thead>
        <tbody>
          {devices.map((device) => (
            <tr
              key={device.id}
              onClick={() => onSelect?.(device)}
              className={`border-t border-[var(--border)] ${
                onSelect ? 'cursor-pointer hover:bg-[var(--surface-3)]' : ''
              } ${selectedId === device.id ? 'bg-[var(--surface-2)]' : ''}`}
            >
              <td className="px-3 py-2 font-medium text-[var(--text)]">
                {editingId === device.id ? (
                  <div
                    className="flex flex-wrap items-center gap-1.5"
                    onClick={(event) => event.stopPropagation()}
                  >
                    <Input
                      autoFocus
                      className="w-44 py-1"
                      value={draft}
                      placeholder="Display name"
                      onChange={(event) => setDraft(event.target.value)}
                      onKeyDown={(event) => {
                        if (event.key === 'Enter') {
                          void saveEdit(event, device)
                        }
                        if (event.key === 'Escape') cancelEdit()
                      }}
                    />
                    <Button
                      onClick={(event) => void saveEdit(event, device)}
                      disabled={saving}
                    >
                      <Check size={13} />
                    </Button>
                    <Button onClick={cancelEdit}>
                      <X size={13} />
                    </Button>
                  </div>
                ) : (
                  <div className="flex items-center gap-1.5">
                    <span>{deviceLabel(device)}</span>
                    {onRename && (
                      <button
                        type="button"
                        aria-label={`Rename ${deviceLabel(device)}`}
                        title="Rename device"
                        onClick={(event) => beginEdit(event, device)}
                        className="rounded p-1 text-[var(--subtle)] hover:bg-[var(--surface-3)] hover:text-[var(--accent-text)]"
                      >
                        <Pencil size={12} />
                      </button>
                    )}
                  </div>
                )}
                {device.display_name && device.hostname && (
                  <p className="mt-0.5 text-[10px] font-normal text-[var(--subtle)]">
                    hostname: {device.hostname}
                  </p>
                )}
              </td>
              <td className="px-3 py-2 text-[var(--muted)]">{device.ipv4 || '—'}</td>
              <td className="px-3 py-2 font-mono text-xs text-[var(--subtle)]">
                {device.mac}
              </td>
              <td className="px-3 py-2 text-[var(--muted)]">
                {device.device_type || device.connection || '—'}
              </td>
              <td className="px-3 py-2">
                <div className="flex flex-wrap gap-1">
                  <Badge tone={device.online ? 'emerald' : 'slate'}>
                    {device.online ? 'online' : 'offline'}
                  </Badge>
                  {device.blocked && <Badge tone="rose">blocked</Badge>}
                  {device.paused && <Badge tone="amber">paused</Badge>}
                </div>
              </td>
              {onAction && (
                <td className="px-3 py-2">
                  <div className="flex flex-wrap gap-1.5">
                    <Button
                      onClick={(event) => {
                        event.stopPropagation()
                        onAction(device, 'block')
                      }}
                    >
                      {device.blocked ? 'Unblock' : 'Block'}
                    </Button>
                    <Button
                      onClick={(event) => {
                        event.stopPropagation()
                        onAction(device, 'pause')
                      }}
                    >
                      {device.paused ? 'Resume' : 'Pause'}
                    </Button>
                  </div>
                </td>
              )}
            </tr>
          ))}
          {devices.length === 0 && (
            <tr>
              <td
                className="px-3 py-6 text-center text-[var(--subtle)]"
                colSpan={onAction ? 6 : 5}
              >
                No devices match.
              </td>
            </tr>
          )}
        </tbody>
      </table>
    </div>
  )
}
