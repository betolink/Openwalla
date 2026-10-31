import { useCallback, useEffect, useState } from 'react'
import { api, type Group, type Policy } from '../api'
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

export function Policies() {
  const [groups, setGroups] = useState<Group[]>([])
  const [policies, setPolicies] = useState<Policy[]>([])
  const [groupName, setGroupName] = useState('')
  const [name, setName] = useState('')
  const [scope, setScope] = useState<'device' | 'group' | 'all'>('group')
  const [groupId, setGroupId] = useState('')
  const [enabled, setEnabled] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const [groupList, policyList] = await Promise.all([
        api.listGroups(),
        api.listPolicies(),
      ])
      setGroups(groupList.items)
      setPolicies(policyList.items)
      if (!groupId && groupList.items[0]) {
        setGroupId(groupList.items[0].id)
      }
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to load')
    } finally {
      setLoading(false)
    }
  }, [groupId])

  useEffect(() => {
    void load()
  }, [load])

  const addGroup = async (event: React.FormEvent) => {
    event.preventDefault()
    if (!groupName.trim()) return
    setError(null)
    try {
      await api.createGroup({ name: groupName.trim(), member_ids: [] })
      setGroupName('')
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to create group')
    }
  }

  const addPolicy = async (event: React.FormEvent) => {
    event.preventDefault()
    if (!name.trim()) return
    setError(null)
    try {
      await api.createPolicy({
        name: name.trim(),
        scope,
        enabled,
        target_ids: scope === 'group' && groupId ? [groupId] : [],
        rules: [],
        schedule: {},
      })
      setName('')
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to create policy')
    }
  }

  const toggle = async (policy: Policy) => {
    try {
      await api.updatePolicy(policy.id, { enabled: !policy.enabled })
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to update policy')
    }
  }

  const removePolicy = async (policy: Policy) => {
    try {
      await api.deletePolicy(policy.id)
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to delete policy')
    }
  }

  const removeGroup = async (group: Group) => {
    try {
      await api.deleteGroup(group.id)
      await load()
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Unable to delete group')
    }
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Policies & groups"
        subtitle="Groups, device access rules and schedules"
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
            className="flex items-end gap-2 border-b border-[var(--border)] px-4 py-3"
          >
            <Field label="New group">
              <Input
                value={groupName}
                placeholder="Children"
                onChange={(event) => setGroupName(event.target.value)}
              />
            </Field>
            <Button type="submit">Add</Button>
          </form>
          <div className="divide-y divide-[var(--border)]">
            {groups.map((group) => (
              <div
                key={group.id}
                className="flex items-center justify-between px-4 py-2 text-sm"
              >
                <div>
                  <span className="text-[var(--text)]">{group.name}</span>
                  <span className="ml-2 text-xs text-[var(--subtle)]">
                    {group.member_ids.length} member(s)
                  </span>
                </div>
                <Button variant="danger" onClick={() => void removeGroup(group)}>
                  Delete
                </Button>
              </div>
            ))}
            {groups.length === 0 && <Empty>No groups yet.</Empty>}
          </div>
        </Card>

        <Card title="Policies">
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
                  <option value="all">All</option>
                </Select>
              </Field>
              <Field label="Target group">
                <Select
                  value={groupId}
                  disabled={scope !== 'group'}
                  onChange={(event) => setGroupId(event.target.value)}
                >
                  {groups.map((group) => (
                    <option key={group.id} value={group.id}>
                      {group.name}
                    </option>
                  ))}
                </Select>
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
            <Button type="submit" variant="primary">
              Add policy
            </Button>
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
                    {policy.scope} · {policy.rules.length} rule(s)
                  </p>
                </div>
                <div className="flex gap-2">
                  <Button onClick={() => void toggle(policy)}>
                    {policy.enabled ? 'Disable' : 'Enable'}
                  </Button>
                  <Button variant="danger" onClick={() => void removePolicy(policy)}>
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
