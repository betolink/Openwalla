import type { Device } from '../api'
import { Badge, Button } from './ui'

export function DeviceTable({
  devices,
  onAction,
  onSelect,
  selectedId,
}: {
  devices: Device[]
  onAction?: (device: Device, action: 'block' | 'pause') => void
  onSelect?: (device: Device) => void
  selectedId?: string
}) {
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
                {device.hostname || 'unknown'}
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
