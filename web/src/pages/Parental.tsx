import { useCallback, useEffect, useMemo, useState } from 'react'
import { api, type Device, type ParentalProfile } from '../api'
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

export function Parental() {
  const [profiles, setProfiles] = useState<ParentalProfile[]>([])
  const [devices, setDevices] = useState<Device[]>([])
  const [name, setName] = useState('')
  const [limit, setLimit] = useState(120)
  const [filter, setFilter] = useState<'none' | 'safe' | 'adult'>('safe')
  const [members, setMembers] = useState<string[]>([])
  const [days, setDays] = useState<string[]>([])
  const [start, setStart] = useState('')
  const [end, setEnd] = useState('')
  const [editingMembers, setEditingMembers] = useState<string | null>(null)
  const [memberDraft, setMemberDraft] = useState<string[]>([])
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const [profileList, deviceList] = await Promise.all([
        api.listParentalProfiles(),
        api.listDevices({ limit: 500 }),
      ])
      setProfiles(profileList.items)
      setDevices(deviceList.items)
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

  const memberNames = (profile: ParentalProfile) =>
    profile.member_ids
      .map((id) => {
        const device = deviceMap.get(id)
        return device ? deviceLabel(device) : id
      })
      .join(', ')

  const add = async (event: React.FormEvent) => {
    event.preventDefault()
    if (!name.trim()) return
    setBusy(true)
    setError(null)
    try {
      const schedule =
        days.length && start && end
          ? { days, start, end }
          : {}
      await api.createParentalProfile({
        name: name.trim(),
        daily_limit_minutes: Number(limit) || 0,
        content_filter: filter,
        member_ids: members,
        schedule,
      })
      setName('')
      setMembers([])
      setDays([])
      setStart('')
      setEnd('')
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to create profile')
    } finally {
      setBusy(false)
    }
  }

  const toggle = async (profile: ParentalProfile) => {
    setBusy(true)
    setError(null)
    try {
      await api.updateParentalProfile(profile.id, { paused: !profile.paused })
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to update profile')
    } finally {
      setBusy(false)
    }
  }

  const remove = async (profile: ParentalProfile) => {
    setBusy(true)
    setError(null)
    try {
      await api.deleteParentalProfile(profile.id)
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to delete profile')
    } finally {
      setBusy(false)
    }
  }

  const beginMembers = (profile: ParentalProfile) => {
    setEditingMembers(profile.id)
    setMemberDraft([...profile.member_ids])
  }

  const saveMembers = async (profile: ParentalProfile) => {
    setBusy(true)
    setError(null)
    try {
      await api.updateParentalProfile(profile.id, { member_ids: memberDraft })
      setEditingMembers(null)
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to assign members')
    } finally {
      setBusy(false)
    }
  }

  const scheduleLabel = (profile: ParentalProfile) => {
    const schedule = profile.schedule
    if (!schedule?.days?.length || !schedule.start || !schedule.end) {
      return 'no schedule'
    }
    return `${schedule.start}–${schedule.end} · ${schedule.days.join(', ')}`
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Parental controls"
        subtitle="Profiles, member assignment, daily limits and block schedules"
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

      <Card title="New profile">
        <form onSubmit={(event) => void add(event)} className="grid gap-4 p-4">
          <div className="grid gap-3 sm:grid-cols-3">
            <Field label="Name">
              <Input
                value={name}
                placeholder="Kids"
                onChange={(event) => setName(event.target.value)}
              />
            </Field>
            <Field label="Daily limit (minutes)">
              <Input
                type="number"
                min={0}
                value={limit}
                onChange={(event) => setLimit(Number(event.target.value))}
              />
            </Field>
            <Field label="Content filter">
              <Select
                value={filter}
                onChange={(event) =>
                  setFilter(event.target.value as 'none' | 'safe' | 'adult')
                }
              >
                <option value="none">None</option>
                <option value="safe">Safe search</option>
                <option value="adult">Block adult</option>
              </Select>
            </Field>
          </div>

          <Field label="Members (Ctrl/Cmd-click to select multiple)">
            <select
              multiple
              value={members}
              onChange={(event) =>
                setMembers(
                  Array.from(event.target.selectedOptions, (option) => option.value),
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
          </Field>

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

          <Button type="submit" variant="primary" disabled={busy || loading}>
            {busy ? 'Applying…' : 'Create and apply profile'}
          </Button>
        </form>
      </Card>

      <Card title="Profiles">
        <div className="divide-y divide-[var(--border)]">
          {profiles.map((profile) => (
            <div key={profile.id} className="px-4 py-3">
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="text-sm font-medium text-[var(--text)]">
                      {profile.name}
                    </span>
                    <Badge tone={profile.paused ? 'amber' : 'emerald'}>
                      {profile.paused ? 'paused' : 'active'}
                    </Badge>
                    <Badge tone="slate">{profile.content_filter}</Badge>
                  </div>
                  <p className="mt-1 text-xs text-[var(--subtle)]">
                    {profile.daily_limit_minutes} min/day · used{' '}
                    {profile.used_minutes_today ?? 0} min ·{' '}
                    {profile.member_ids.length} member(s)
                  </p>
                  <p className="mt-1 text-xs text-[var(--subtle)]">
                    Schedule: {scheduleLabel(profile)}
                  </p>
                  {profile.member_ids.length > 0 && (
                    <p className="mt-1 text-xs text-[var(--muted)]">
                      {memberNames(profile)}
                    </p>
                  )}
                </div>
                <div className="flex flex-wrap gap-2">
                  <Button onClick={() => beginMembers(profile)} disabled={busy}>
                    Members
                  </Button>
                  <Button onClick={() => void toggle(profile)} disabled={busy}>
                    {profile.paused ? 'Resume' : 'Pause'}
                  </Button>
                  <Button
                    variant="danger"
                    onClick={() => void remove(profile)}
                    disabled={busy}
                  >
                    Delete
                  </Button>
                </div>
              </div>

              {editingMembers === profile.id && (
                <div className="mt-3 rounded-lg border border-[var(--border)] bg-[var(--surface-2)] p-3">
                  <p className="mb-2 text-xs text-[var(--subtle)]">
                    Assign devices to {profile.name}
                  </p>
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
                    className="min-h-32 w-full rounded-lg border border-[var(--border)] bg-[var(--input-bg)] px-3 py-2 text-sm text-[var(--text)] outline-none focus:border-[var(--accent)]"
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
                      onClick={() => void saveMembers(profile)}
                      disabled={busy}
                    >
                      Save members
                    </Button>
                    <Button
                      onClick={() => setEditingMembers(null)}
                      disabled={busy}
                    >
                      Cancel
                    </Button>
                  </div>
                </div>
              )}
            </div>
          ))}
          {profiles.length === 0 && <Empty>No parental profiles yet.</Empty>}
        </div>
      </Card>
    </div>
  )
}
