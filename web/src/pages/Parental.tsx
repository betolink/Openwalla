import { useCallback, useEffect, useState } from 'react'
import { api, type ParentalProfile } from '../api'
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

export function Parental() {
  const [profiles, setProfiles] = useState<ParentalProfile[]>([])
  const [name, setName] = useState('')
  const [limit, setLimit] = useState(120)
  const [filter, setFilter] = useState<'none' | 'safe' | 'adult'>('safe')
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const result = await api.listParentalProfiles()
      setProfiles(result.items)
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to load')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    void load()
  }, [load])

  const add = async (event: React.FormEvent) => {
    event.preventDefault()
    if (!name.trim()) return
    setError(null)
    try {
      await api.createParentalProfile({
        name: name.trim(),
        daily_limit_minutes: Number(limit) || 0,
        content_filter: filter,
        member_ids: [],
      })
      setName('')
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to create profile')
    }
  }

  const toggle = async (profile: ParentalProfile) => {
    try {
      await api.updateParentalProfile(profile.id, { paused: !profile.paused })
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to update profile')
    }
  }

  const remove = async (profile: ParentalProfile) => {
    try {
      await api.deleteParentalProfile(profile.id)
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to delete profile')
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Parental controls"
        subtitle="Profiles, schedules, quotas and content filters"
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
        <form onSubmit={(event) => void add(event)} className="grid gap-3 p-4">
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
          <Button type="submit" variant="primary">
            Create profile
          </Button>
        </form>
      </Card>

      <Card title="Profiles">
        <div className="divide-y divide-[var(--border)]">
          {profiles.map((profile) => (
            <div
              key={profile.id}
              className="flex flex-wrap items-center justify-between gap-3 px-4 py-3"
            >
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
              </div>
              <div className="flex gap-2">
                <Button onClick={() => void toggle(profile)}>
                  {profile.paused ? 'Resume' : 'Pause'}
                </Button>
                <Button variant="danger" onClick={() => void remove(profile)}>
                  Delete
                </Button>
              </div>
            </div>
          ))}
          {profiles.length === 0 && <Empty>No parental profiles yet.</Empty>}
        </div>
      </Card>
    </div>
  )
}
