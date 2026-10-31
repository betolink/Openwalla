import { useCallback, useEffect, useMemo, useState } from 'react'
import { api, type Device, type Group, type Policy } from '../api'
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

export function Policies() {
  const [groups, setGroups] = useState<Group[]>([])
  const [policies, setPolicies] = useState<Policy[]>([])
  const [devices, setDevices] = useState<Device[]>([])
  const [groupName, setGroupName] = useState('')
  const [groupMembers, setGroupMembers] = useState<string[]>([])
  const [name, setName] = useState('')
  const [scope, setScope] = useState<'device' | 'group' | 'all'>('group')
  const [groupId, setGroupId] = useState('')
  const [deviceId, setDeviceId] = useState('')
  const [enabled, setEnabled] = useState(true)
  const [days, setDays] = useState<string[]>([])
  const [start, setStart] = useState('')
  const [end, setEnd] = useState('')
  const [editingGroup, setEditingGroup] = useState<string | null>(null)
  const [memberDraft, setMemberDraft] = useState<string[]>([])
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const [groupList, policyList, deviceList] = await Promise.all([
        api.listGroups(),
        api.listPolicies(),
        api.listDevices({ limit: 500 }),
      ])
      setGroups(groupList.items)
      setPolicies(policyList.items)
      setDevices(deviceList.items)
      setGroupId((current) => current || groupList.items[0]?.id || '')
      setDeviceId((current) => current || deviceList.items[0]?.id || '')
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

  const addGroup = async (event: React.FormEvent) => {
    event.preventDefault()
    if (!groupName.trim()) return
    setBusy(true)
    setError(null)
    try {
      await api.createGroup({
        name: groupName.trim(),
        member_ids: groupMembers,
      })
      setGroupName('')
      setGroupMembers([])
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to create group')
    } finally {
      setBusy(false)
    }
  }

  const addPolicy = async (event: React.FormEvent) => {
    event.preventDefault()
    if (!name.trim()) return
    setBusy(true)
    setError(null)
    try {
      const targetIds =
        scope === 'group'
          ? groupId
            ? [groupId]
            : []
          : scope === 'device'
            ? deviceId
              ? [deviceId]
              : []
            : []
      const schedule =
        days.length && start && end ? { days, start, end } : {}
      await api.createPolicy({
        name: name.trim(),
        scope,
        enabled,
        target_ids: targetIds,
        rules: [{ type: 'internet', value: 'all', action: 'block' }],
        schedule,
      })
      setName('')
      setDays([])
      setStart('')
      setEnd('')
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to create policy')
    } finally {
      setBusy(false)
    }
  }

  const toggle = async (policy: Policy) => {
    setBusy(true)
    setError(null)
    try {
      await api.updatePolicy(policy.id, { enabled: !policy.enabled })
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to update policy')
    } finally {
      setBusy(false)
    }
  }

  const removePolicy = async (policy: Policy) => {
    setBusy(true)
    setError(null)
    try {
      await api.deletePolicy(policy.id)
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to delete policy')
    } finally {
      setBusy(false)
    }
  }

  const removeGroup = async (group: Group) => {
    setBusy(true)
    setError(null)
    try {
      await api.deleteGroup(group.id)
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to delete group')
    } finally {
      setBusy(false)
    }
  }

  const beginGroupMembers = (group: Group) => {
    setEditingGroup(group.id)
    setMemberDraft([...group.member_ids])
  }

  const saveGroupMembers = async (group: Group) => {
    setBusy(true)
    setError(null)
    try {
      await api.updateGroup(group.id, { member_ids: memberDraft })
      setEditingGroup(null)
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to update group')
    } finally {
      setBusy(false)
    }
  }

  const targetLabel = (policy: Policy) => {
    if (policy.scope === 'all') return 'all devices'
    if (policy.scope === 'group') {
      return (
        policy.target_ids
          .map((id) => groupMap.get(id)?.name || id)
          .join(', ') || 'no group'
      )
    }
    return (
      policy.target_ids
        .map((id) => {
          const device = deviceMap.get(id)
          return device ? deviceLabel(device) : id
        })
        .join(', ') || 'no device'
    )
  }

  const scheduleLabel = (policy: Policy) => {
    const schedule = policy.schedule
    if (!schedule?.days?.length || !schedule.start || !schedule.end) {
      return 'always'
    }
    return `${schedule.start}–${schedule.end} · ${schedule.days.join(', ')}`
  }

  const groupMemberNames = (group: Group) =>
    group.member_ids
      .map((id) => {
        const device = deviceMap.get(id)
        return device ? deviceLabel(device) : id
      })
      .join(', ')

  return (
    <div className="space-y-6">
      <PageHeader
        title="Policies & groups"
        subtitle="Internet-block policies for devices and groups"
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

      <div className="grid gap-6 lg:grid-cols-2">
        <Card title="Groups">
          <form
            onSubmit={(event) => void addGroup(event)}
            className="grid gap-3 border-b border-[var(--border)] px-4 py-3"
          >
            <Field label="New group">
              <Input
                value={groupName}
                placeholder="Children"
                onChange={(event) => setGroupName(event.target.value)}
              />
            </Field>
            <Field label="Members">
              <select
                multiple
                value={groupMembers}
                onChange={(event) =>
                  setGroupMembers(
                    Array.from(
                      event.target.selectedOptions,
                      (option) => option.value,
                    ),
                  )
                }
                className="min-h-24 w-full rounded-lg border border-[var(--border)] bg-[var(--input-bg)] px-3 py-2 text-sm text-[var(--text)] outline-none focus:border-[var(--accent)]"
              >
                {devices.map((device) => (
                  <option key={device.id} value={device.id}>
                    {deviceLabel(device)} · {device.ipv4 || device.mac}
                  </option>
                ))}
              </select>
            </Field>
            <Button type="submit" disabled={busy || loading}>
              Add group
            </Button>
          </form>

          <div className="divide-y divide-[var(--border)]">
            {groups.map((group) => (
              <div key={group.id} className="px-4 py-2 text-sm">
                <div className="flex items-center justify-between gap-2">
                  <div>
                    <span className="text-[var(--text)]">{group.name}</span>
                    <span className="ml-2 text-xs text-[var(--subtle)]">
                      {group.member_ids.length} member(s)
                    </span>
                    {group.member_ids.length > 0 && (
                      <p className="mt-1 text-xs text-[var(--muted)]">
                        {groupMemberNames(group)}
                      </p>
                    )}
                  </div>
                  <div className="flex gap-2">
                    <Button onClick={() => beginGroupMembers(group)} disabled={busy}>
                      Members
                    </Button>
                    <Button
                      variant="danger"
                      onClick={() => void removeGroup(group)}
                      disabled={busy}
                    >
                      Delete
                    </Button>
                  </div>
                </div>
                {editingGroup === group.id && (
                  <div className="mt-3 rounded-lg border border-[var(--border)] bg-[var(--surface-2)] p-3">
                    <select
                      multiple
                      value={memberDraft}
                      onChange={(event) =>
                        setMemberDraft(
                          Array.from(
                            event.target.selectedOptions,
                            (option) => option.value,
                          ),
                        )
                      }
                      className="min-h-28 w-full rounded-lg border border-[var(--border)] bg-[var(--input-bg)] px-3 py-2 text-sm text-[var(--text)] outline-none focus:border-[var(--accent)]"
                    >
                      {devices.map((device) => (
                        <option key={device.id} value={device.id}>
                          {deviceLabel(device)} · {device.ipv4 || device.mac}
                        </option>
                      ))}
                    </select>
                    <div className="mt-2 flex gap-2">
                      <Button
                        variant="primary"
                        onClick={() => void saveGroupMembers(group)}
                        disabled={busy}
                      >
                        Save members
                      </Button>
                      <Button onClick={() => setEditingGroup(null)} disabled={busy}>
                        Cancel
                      </Button>
                    </div>
                  </div>
                )}
              </div>
            ))}
            {groups.length === 0 && <Empty>No groups yet.</Empty>}
          </div>
        </Card>

        <Card title="Internet-block policies">
          <form
            onSubmit={(event) => void addPolicy(event)}
            className="grid gap-3 border-b border-[var(--border)] px-4 py-3"
          >
            <Field label="Policy name">
              <Input
                value={name}
                placeholder="Bedtime"
                onChange={(event) => setName(event.target.value)}
              />
            </Field>
            <div className="grid grid-cols-2 gap-3">
              <Field label="Scope">
                <Select
                  value={scope}
                  onChange={(event) =>
                    setScope(event.target.value as 'device' | 'group' | 'all')
                  }
                >
                  <option value="group">Group</option>
                  <option value="device">Device</option>
                  <option value="all">All devices</option>
                </Select>
              </Field>
              {scope === 'group' && (
                <Field label="Target group">
                  <Select
                    value={groupId}
                    onChange={(event) => setGroupId(event.target.value)}
                  >
                    {groups.map((group) => (
                      <option key={group.id} value={group.id}>
                        {group.name}
                      </option>
                    ))}
                  </Select>
                </Field>
              )}
              {scope === 'device' && (
                <Field label="Target device">
                  <Select
                    value={deviceId}
                    onChange={(event) => setDeviceId(event.target.value)}
                  >
                    {devices.map((device) => (
                      <option key={device.id} value={device.id}>
                        {deviceLabel(device)}
                      </option>
                    ))}
                  </Select>
                </Field>
              )}
            </div>
            <div className="grid gap-3 sm:grid-cols-3">
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
                  {weekdays.map(([value, label]) => (
                    <label
                      key={value}
                      className="flex items-center gap-1 text-xs text-[var(--muted)]"
                    >
                      <input
                        type="checkbox"
                        checked={days.includes(value)}
                        onChange={(event) =>
                          setDays((current) =>
                            event.target.checked
                              ? [...current, value]
                              : current.filter((day) => day !== value),
                          )
                        }
                      />
                      {label}
                    </label>
                  ))}
                </div>
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
              Add policy
            </Button>
            <p className="text-[11px] text-[var(--subtle)]">
              No schedule = block always. With a schedule, the policy blocks
              internet during that window.
            </p>
          </form>

          <div className="divide-y divide-[var(--border)]">
            {policies.map((policy) => (
              <div
                key={policy.id}
                className="flex flex-wrap items-center justify-between gap-2 px-4 py-2 text-sm"
              >
                <div>
                  <span className="text-[var(--text)]">{policy.name}</span>{' '}
                  <Badge tone={policy.enabled ? 'emerald' : 'slate'}>
                    {policy.enabled ? 'enabled' : 'disabled'}
                  </Badge>
                  <p className="text-xs text-[var(--subtle)]">
                    {targetLabel(policy)} · {scheduleLabel(policy)}
                  </p>
                </div>
                <div className="flex gap-2">
                  <Button onClick={() => void toggle(policy)} disabled={busy}>
                    {policy.enabled ? 'Disable' : 'Enable'}
                  </Button>
                  <Button
                    variant="danger"
                    onClick={() => void removePolicy(policy)}
                    disabled={busy}
                  >
                    Delete
                  </Button>
                </div>
              </div>
            ))}
            {policies.length === 0 && <Empty>No policies yet.</Empty>}
          </div>
        </Card>
      </div>
    </div>
  )
}
