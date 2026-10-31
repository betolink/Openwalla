import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  api,
  type Device,
  type FilteringCatalog,
  type FilteringRule,
  type Group,
} from '../api'
import {
  Badge,
  Button,
  Card,
  Empty,
  Field,
  Input,
  PageHeader,
  Select,
} from '../components/ui'
import { formatDateTime } from '../utils/format'

const weekdays = [
  ['mon', 'Mon'],
  ['tue', 'Tue'],
  ['wed', 'Wed'],
  ['thu', 'Thu'],
  ['fri', 'Fri'],
  ['sat', 'Sat'],
  ['sun', 'Sun'],
] as const

function deviceLabel(device: Device) {
  return device.display_name || device.hostname || device.mac
}

export function Filtering() {
  const [rules, setRules] = useState<FilteringRule[]>([])
  const [catalog, setCatalog] = useState<FilteringCatalog | null>(null)
  const [devices, setDevices] = useState<Device[]>([])
  const [groups, setGroups] = useState<Group[]>([])
  const [name, setName] = useState('')
  const [targetType, setTargetType] = useState<'device' | 'group' | 'all'>(
    'device',
  )
  const [targetId, setTargetId] = useState('')
  const [kind, setKind] = useState<'service' | 'category' | 'domain'>('service')
  const [value, setValue] = useState('')
  const [action, setAction] = useState<'block' | 'allow'>('block')
  const [enabled, setEnabled] = useState(true)
  const [days, setDays] = useState<string[]>([])
  const [start, setStart] = useState('')
  const [end, setEnd] = useState('')
  const [expiresMinutes, setExpiresMinutes] = useState(0)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const [ruleList, catalogResult, deviceList, groupList] =
        await Promise.all([
          api.listFilteringRules(),
          api.getFilteringCatalog(),
          api.listDevices({ limit: 500 }),
          api.listGroups(),
        ])
      setRules(ruleList.items)
      setCatalog(catalogResult)
      setDevices(deviceList.items)
      setGroups(groupList.items)
      setTargetId(
        (current) =>
          current ||
          deviceList.items[0]?.id ||
          groupList.items[0]?.id ||
          '',
      )
      setValue((current) => {
        if (current) return current
        return catalogResult.services[0]?.id || ''
      })
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to load')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  const deviceMap = useMemo(
    () => new Map(devices.map((device) => [device.id, device])),
    [devices],
  )
  const groupMap = useMemo(
    () => new Map(groups.map((group) => [group.id, group])),
    [groups],
  )

  const targetOptions =
    targetType === 'group'
      ? groups.map((group) => ({ id: group.id, label: group.name }))
      : devices.map((device) => ({ id: device.id, label: deviceLabel(device) }))

  const targetLabel = (rule: FilteringRule) => {
    if (rule.target_type === 'all') return 'all devices'
    return rule.target_ids
      .map((id) => {
        if (rule.target_type === 'group') {
          return groupMap.get(id)?.name || id
        }
        const device = deviceMap.get(id)
        return device ? deviceLabel(device) : id
      })
      .join(', ')
  }

  const scheduleLabel = (rule: FilteringRule) => {
    const parts: string[] = []
    if (rule.schedule?.days?.length && rule.schedule.start && rule.schedule.end) {
      parts.push(
        `${rule.schedule.start}–${rule.schedule.end} · ${rule.schedule.days.join(', ')}`,
      )
    } else {
      parts.push('always')
    }
    if (rule.expires_at) {
      parts.push(`expires ${formatDateTime(rule.expires_at)}`)
    }
    return parts.join(' · ')
  }

  const add = async (event: React.FormEvent) => {
    event.preventDefault()
    if (!value.trim()) return
    setBusy(true)
    setError(null)
    setNotice(null)
    try {
      await api.createFilteringRule({
        name: name.trim() || value.trim(),
        target_type: targetType,
        target_ids:
          targetType === 'all' ? [] : targetId ? [targetId] : [],
        kind,
        value: value.trim(),
        action,
        enabled,
        schedule:
          days.length && start && end ? { days, start, end } : {},
        expires_minutes: expiresMinutes || 0,
      })
      setName('')
      setDays([])
      setStart('')
      setEnd('')
      setExpiresMinutes(0)
      setNotice('Filtering rule applied.')
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to create rule')
    } finally {
      setBusy(false)
    }
  }

  const toggle = async (rule: FilteringRule) => {
    setBusy(true)
    setError(null)
    try {
      await api.updateFilteringRule(rule.id, { enabled: !rule.enabled })
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to update rule')
    } finally {
      setBusy(false)
    }
  }

  const remove = async (rule: FilteringRule) => {
    setBusy(true)
    setError(null)
    try {
      await api.deleteFilteringRule(rule.id)
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to delete rule')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="DNS & filtering"
        subtitle="Per-device apps, categories, websites, schedules and temporary blocks"
        actions={
          <Button onClick={() => void load()} disabled={loading}>
            Refresh
          </Button>
        }
      />

      {error && (
        <div className="rounded-lg border border-[var(--danger)] bg-[var(--danger-soft)] px-4 py-3 text-sm text-[var(--danger)]">
          {error}
        </div>
      )}
      {notice && (
        <div className="rounded-lg border border-[var(--border)] bg-[var(--surface-2)] px-4 py-3 text-sm text-[var(--muted)]">
          {notice}
        </div>
      )}

      <Card title="Add filtering rule">
        <form onSubmit={(event) => void add(event)} className="grid gap-4 p-4">
          <div className="grid gap-3 md:grid-cols-3">
            <Field label="Name">
              <Input
                value={name}
                placeholder={value || 'Bedtime games'}
                onChange={(event) => setName(event.target.value)}
              />
            </Field>
            <Field label="Target">
              <Select
                value={targetType}
                onChange={(event) => {
                  const next = event.target.value as 'device' | 'group' | 'all'
                  setTargetType(next)
                  setTargetId(
                    next === 'group'
                      ? groups[0]?.id || ''
                      : devices[0]?.id || '',
                  )
                }}
              >
                <option value="device">Device</option>
                <option value="group">Group</option>
                <option value="all">All devices</option>
              </Select>
            </Field>
            {targetType !== 'all' && (
              <Field label={targetType === 'group' ? 'Group' : 'Device'}>
                <Select
                  value={targetId}
                  onChange={(event) => setTargetId(event.target.value)}
                >
                  {targetOptions.map((option) => (
                    <option key={option.id} value={option.id}>
                      {option.label}
                    </option>
                  ))}
                </Select>
              </Field>
            )}
          </div>

          <div className="grid gap-3 md:grid-cols-3">
            <Field label="Rule type">
              <Select
                value={kind}
                onChange={(event) => {
                  const next = event.target.value as
                    | 'service'
                    | 'category'
                    | 'domain'
                  setKind(next)
                  setValue(
                    next === 'service'
                      ? catalog?.services[0]?.id || ''
                      : next === 'category'
                        ? Object.keys(catalog?.categories ?? {})[0] || ''
                        : '',
                  )
                }}
              >
                <option value="service">App / service</option>
                <option value="category">Category</option>
                <option value="domain">Website / domain</option>
              </Select>
            </Field>
            <Field label="App / category / domain">
              {kind === 'service' ? (
                <Select
                  value={value}
                  onChange={(event) => setValue(event.target.value)}
                >
                  {(catalog?.services ?? []).map((service) => (
                    <option key={service.id} value={service.id}>
                      {service.name}
                    </option>
                  ))}
                </Select>
              ) : kind === 'category' ? (
                <Select
                  value={value}
                  onChange={(event) => setValue(event.target.value)}
                >
                  {Object.entries(catalog?.categories ?? {}).map(
                    ([id, category]) => (
                      <option key={id} value={id}>
                        {category.name}
                      </option>
                    ),
                  )}
                </Select>
              ) : (
                <Input
                  value={value}
                  placeholder="instagram.com"
                  onChange={(event) => setValue(event.target.value)}
                />
              )}
            </Field>
            <Field label="Action">
              <Select
                value={action}
                onChange={(event) =>
                  setAction(event.target.value as 'block' | 'allow')
                }
              >
                <option value="block">Block</option>
                <option value="allow">Allow</option>
              </Select>
            </Field>
          </div>

          <div className="grid gap-3 md:grid-cols-4">
            <Field label="Block from">
              <Input
                type="time"
                value={start}
                onChange={(event) => setStart(event.target.value)}
              />
            </Field>
            <Field label="Block until">
              <Input
                type="time"
                value={end}
                onChange={(event) => setEnd(event.target.value)}
              />
            </Field>
            <Field label="Days">
              <div className="flex flex-wrap gap-2 pt-2">
                {weekdays.map(([day, label]) => (
                  <label
                    key={day}
                    className="flex items-center gap-1 text-xs text-[var(--muted)]"
                  >
                    <input
                      type="checkbox"
                      checked={days.includes(day)}
                      onChange={(event) =>
                        setDays((current) =>
                          event.target.checked
                            ? [...current, day]
                            : current.filter((value) => value !== day),
                        )
                      }
                    />
                    {label}
                  </label>
                ))}
              </div>
            </Field>
            <Field label="Expires in (minutes)">
              <Input
                type="number"
                min={0}
                value={expiresMinutes}
                onChange={(event) =>
                  setExpiresMinutes(Number(event.target.value))
                }
              />
            </Field>
          </div>

          <label className="flex items-center gap-2 text-sm text-[var(--muted)]">
            <input
              type="checkbox"
              checked={enabled}
              onChange={(event) => setEnabled(event.target.checked)}
            />
            Enabled
          </label>
          <Button type="submit" variant="primary" disabled={busy || loading}>
            {busy ? 'Applying…' : 'Apply filter'}
          </Button>
        </form>
      </Card>

      <Card title="Active filtering rules">
        <div className="divide-y divide-[var(--border)]">
          {rules.map((rule) => (
            <div
              key={rule.id}
              className="flex flex-wrap items-center justify-between gap-3 px-4 py-3"
            >
              <div>
                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-sm font-medium text-[var(--text)]">
                    {rule.name}
                  </span>
                  <Badge tone={rule.enabled ? 'emerald' : 'slate'}>
                    {rule.enabled ? 'enabled' : 'disabled'}
                  </Badge>
                  <Badge tone="sky">{rule.kind}</Badge>
                  <Badge tone={rule.action === 'block' ? 'rose' : 'amber'}>
                    {rule.action}
                  </Badge>
                </div>
                <p className="mt-1 text-xs text-[var(--muted)]">
                  {rule.value} · {targetLabel(rule)}
                </p>
                <p className="mt-1 text-xs text-[var(--subtle)]">
                  {scheduleLabel(rule)}
                </p>
              </div>
              <div className="flex gap-2">
                <Button onClick={() => void toggle(rule)} disabled={busy}>
                  {rule.enabled ? 'Disable' : 'Enable'}
                </Button>
                <Button
                  variant="danger"
                  onClick={() => void remove(rule)}
                  disabled={busy}
                >
                  Delete
                </Button>
              </div>
            </div>
          ))}
          {rules.length === 0 && <Empty>No filtering rules yet.</Empty>}
        </div>
      </Card>
    </div>
  )
}
