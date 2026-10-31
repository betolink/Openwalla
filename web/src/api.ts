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
}
