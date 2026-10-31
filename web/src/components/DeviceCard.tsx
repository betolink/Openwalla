import {
  Laptop,
  MonitorSmartphone,
  Printer,
  Smartphone,
  Tv,
} from 'lucide-react'
import type { Device } from '../api'
import { Badge, Button } from './ui'

function DeviceIcon({ type }: { type?: string }) {
  const value = (type || '').toLowerCase()
  if (value.includes('phone')) return <Smartphone size={18} />
  if (value.includes('laptop') || value.includes('computer'))
    return <Laptop size={18} />
  if (value.includes('tv') || value.includes('roku')) return <Tv size={18} />
  if (value.includes('print')) return <Printer size={18} />
  return <MonitorSmartphone size={18} />
}

export function DeviceCard({
  device,
  onAction,
  onOpen,
}: {
  device: Device
  onAction?: (device: Device, action: 'block' | 'pause') => void
  onOpen?: (device: Device) => void
}) {
  return (
    <div
      onClick={() => onOpen?.(device)}
      className={`rounded-xl border border-[var(--border)] bg-[var(--surface-2)] p-3 ${
        onOpen ? 'cursor-pointer hover:border-[var(--accent)]' : ''
      }`}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="flex items-center gap-2">
          <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-[var(--surface-2)] text-[var(--text)]">
            <DeviceIcon type={device.device_type} />
          </div>
          <div>
            <p className="text-sm font-medium text-[var(--text)]">
              {device.hostname || 'unknown'}
            </p>
            <p className="text-[11px] text-[var(--subtle)]">{device.ipv4 || '—'}</p>
          </div>
        </div>
        <span
          className={`mt-1 h-2 w-2 rounded-full ${
            device.online ? 'bg-[var(--success)]' : 'bg-[var(--subtle)]'
          }`}
        />
      </div>

      <div className="mt-2 flex flex-wrap gap-1">
        {device.blocked && <Badge tone="rose">blocked</Badge>}
        {device.paused && <Badge tone="amber">paused</Badge>}
        {!device.blocked && !device.paused && (
          <Badge tone="slate">{device.connection || 'unknown'}</Badge>
        )}
      </div>

      <div className="mt-3 flex gap-1.5">
        <Button
          onClick={(event) => {
            event.stopPropagation()
            onAction?.(device, 'block')
          }}
        >
          {device.blocked ? 'Unblock' : 'Block'}
        </Button>
        <Button
          onClick={(event) => {
            event.stopPropagation()
            onAction?.(device, 'pause')
          }}
        >
          {device.paused ? 'Resume' : 'Pause'}
        </Button>
      </div>
    </div>
  )
}
