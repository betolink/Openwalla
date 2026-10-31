export type RouterStatus = 'online' | 'offline' | 'degraded' | 'unknown'

export interface Router {
  id: string
  name: string
  address: string
  port?: number
  scheme?: string
  model?: string
  openwrt_version?: string
  status: RouterStatus
  last_seen?: string
  capabilities?: string[]
  has_credentials?: boolean
  created_at?: string
  updated_at?: string
}

export interface Device {
  id: string
  router_id: string
  mac: string
  ipv4: string
  ipv6?: string[]
  hostname: string
  vendor: string
  device_type: string
  connection: 'wired' | 'wireless' | 'unknown'
  online: boolean
  blocked: boolean
  paused: boolean
  group_id?: string
  first_seen?: string
  last_seen?: string
  tags?: string[]
}

export interface ListResponse<T> {
  items: T[]
  total: number
}

export interface RouterInput {
  name: string
  address: string
  port?: number
  scheme?: string
  username?: string
  password?: string
  verify_tls?: boolean
}

export interface Group {
  id: string
  name: string
  description?: string
  member_ids: string[]
}

export interface PolicyRule {
  type: string
  value: string
  action: 'allow' | 'block'
}

export interface Schedule {
  timezone?: string
  days?: string[]
  start?: string
  end?: string
}

export interface Policy {
  id: string
  name: string
  description?: string
  enabled: boolean
  scope: 'device' | 'group' | 'all'
  target_ids: string[]
  rules: PolicyRule[]
  schedule: Schedule
}

export interface ParentalProfile {
  id: string
  name: string
  member_ids: string[]
  enabled: boolean
  paused: boolean
  pause_until?: string
  daily_limit_minutes: number
  content_filter: 'none' | 'safe' | 'adult'
  custom_dns?: string
  schedule?: Schedule
  bedtime?: Schedule
  used_minutes_today?: number
}

export interface AdblockStatus {
  enabled: boolean
  total_queries: number
  blocked_queries: number
  block_percent: number
  blocklists: string[]
  update_interval_hours: number
  last_updated?: string
}

export interface AdblockSettings {
  enabled: boolean
  blocklists: string[]
  update_interval_hours: number
}

export interface EventItem {
  id: string
  type: string
  severity: 'info' | 'warning' | 'critical'
  message: string
  router_id?: string
  device_id?: string
  created_at: string
  data?: Record<string, unknown>
}

export interface Flow {
  id?: string
  timestamp?: string
  local_ip?: string
  dest_ip?: string
  domain?: string
  application?: string
  protocol?: string
  risk_score?: number
  bytes_up?: number
  bytes_down?: number
  [key: string]: unknown
}

export interface TrafficPoint {
  timestamp: number
  flows: number
  devices: number
}

export interface DeviceRange {
  download: number
  upload: number
}

export interface DeviceWebsite {
  domain: string
  app: string
  protocol: string
  visits: number
  last_seen: number
}

export interface DeviceDetails {
  mac: string
  hours: number
  summary: Record<string, unknown>
  ranges: Record<'1h' | '12h' | '1d' | '7d', DeviceRange>
  series: Array<{ timestamp: number; download: number; upload: number }>
  websites: DeviceWebsite[]
}

export interface FlowDashboard {
  collector?: {
    connected?: boolean
    host?: string
    port?: number
    received?: number
    stored?: number
    discarded?: number
    last_event_at?: string | null
    last_error?: string | null
  }
  flows?: {
    hours?: number
    flow_count?: number
    device_count?: number
    latest_flow?: number | null
    database_bytes?: number
    top_applications?: Array<{ name: string; count: number }>
    recent_flows?: Array<Record<string, unknown>>
  }
  retention_hours?: number
}

const API_BASE = import.meta.env.VITE_API_BASE ?? ''

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API_BASE}${path}`, {
    headers: { 'Content-Type': 'application/json', ...(init?.headers ?? {}) },
    ...init,
  })
  if (!response.ok) {
    let message = `HTTP ${response.status}`
    try {
      const text = await response.text()
      if (text) message = text
    } catch {
      // keep the status message
    }
    throw new Error(message)
  }
  if (response.status === 204) {
    return undefined as T
  }
  return (await response.json()) as T
}

function query(
  params: Record<string, string | number | boolean | undefined>,
): string {
  const search = new URLSearchParams()
  for (const [key, value] of Object.entries(params)) {
    if (value === undefined || value === '') continue
    search.set(key, String(value))
  }
  const result = search.toString()
  return result ? `?${result}` : ''
}

export const api = {
  listRouters: () => request<ListResponse<Router>>('/api/v1/routers'),

  createRouter: (input: RouterInput) =>
    request<Router>('/api/v1/routers', {
      method: 'POST',
      body: JSON.stringify(input),
    }),

  deleteRouter: (id: string) =>
    request<void>(`/api/v1/routers/${id}`, { method: 'DELETE' }),

  syncRouter: (id: string) =>
    request<{ router: Router; devices: number; interfaces: number }>(
      `/api/v1/routers/${id}/sync`,
      { method: 'POST' },
    ),

  listDevices: (
    params: {
      router_id?: string
      online?: boolean
      group_id?: string
      q?: string
      limit?: number
      offset?: number
    } = {},
  ) => request<ListResponse<Device>>(`/api/v1/devices${query(params)}`),

  blockDevice: (id: string) =>
    request<Device>(`/api/v1/devices/${id}/block`, { method: 'POST' }),

  unblockDevice: (id: string) =>
    request<Device>(`/api/v1/devices/${id}/unblock`, { method: 'POST' }),

  pauseDevice: (id: string) =>
    request<Device>(`/api/v1/devices/${id}/pause`, { method: 'POST' }),

  resumeDevice: (id: string) =>
    request<Device>(`/api/v1/devices/${id}/resume`, { method: 'POST' }),

  listGroups: () => request<ListResponse<Group>>('/api/v1/groups'),

  createGroup: (input: { name: string; description?: string; member_ids?: string[] }) =>
    request<Group>('/api/v1/groups', {
      method: 'POST',
      body: JSON.stringify(input),
    }),

  deleteGroup: (id: string) =>
    request<void>(`/api/v1/groups/${id}`, { method: 'DELETE' }),

  listPolicies: () => request<ListResponse<Policy>>('/api/v1/policies'),

  createPolicy: (input: Partial<Policy> & { name: string }) =>
    request<Policy>('/api/v1/policies', {
      method: 'POST',
      body: JSON.stringify(input),
    }),

  updatePolicy: (id: string, input: Partial<Policy>) =>
    request<Policy>(`/api/v1/policies/${id}`, {
      method: 'PUT',
      body: JSON.stringify(input),
    }),

  deletePolicy: (id: string) =>
    request<void>(`/api/v1/policies/${id}`, { method: 'DELETE' }),

  listParentalProfiles: () =>
    request<ListResponse<ParentalProfile>>('/api/v1/parental/profiles'),

  createParentalProfile: (
    input: Partial<ParentalProfile> & { name: string },
  ) =>
    request<ParentalProfile>('/api/v1/parental/profiles', {
      method: 'POST',
      body: JSON.stringify(input),
    }),

  updateParentalProfile: (id: string, input: Partial<ParentalProfile>) =>
    request<ParentalProfile>(`/api/v1/parental/profiles/${id}`, {
      method: 'PUT',
      body: JSON.stringify(input),
    }),

  deleteParentalProfile: (id: string) =>
    request<void>(`/api/v1/parental/profiles/${id}`, { method: 'DELETE' }),

  getAdblockStatus: () => request<AdblockStatus>('/api/v1/adblock/status'),

  getAdblockSettings: () =>
    request<AdblockSettings>('/api/v1/adblock/settings'),

  updateAdblockSettings: (input: Partial<AdblockSettings>) =>
    request<AdblockSettings>('/api/v1/adblock/settings', {
      method: 'PUT',
      body: JSON.stringify(input),
    }),

  listEvents: (params: { severity?: string; limit?: number } = {}) =>
    request<ListResponse<EventItem>>(`/api/v1/events${query(params)}`),

  getFlowDashboard: (hours = 24) =>
    request<FlowDashboard>(`/api/v1/dashboard?hours=${hours}`),

  listFlows: (params: { limit?: number; hours?: number; search?: string } = {}) =>
    request<{ items: Flow[] }>(`/api/v1/flows${query(params)}`),

  getTrafficSeries: (hours = 24, bucket = 300) =>
    request<{ items: TrafficPoint[] }>(
      `/api/v1/traffic/series${query({ hours, bucket })}`,
    ),

  getDeviceDetails: (id: string, hours = 24) =>
    request<DeviceDetails>(`/api/v1/devices/${id}/details${query({ hours })}`),
}
