import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { api } from './api'

const fetchMock = vi.fn()

beforeEach(() => {
  fetchMock.mockReset()
  vi.stubGlobal('fetch', fetchMock)
})

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('api', () => {
  it('lists devices with query parameters', async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ items: [], total: 0 }),
    })
    await api.listDevices({ router_id: 'r1', online: true })
    expect(fetchMock).toHaveBeenCalledWith(
      '/api/v1/devices?router_id=r1&online=true',
      expect.anything(),
    )
  })

  it('creates a router with JSON', async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      status: 201,
      json: async () => ({ id: 'r1', name: 'betowrt', address: '192.168.0.1' }),
    })
    await api.createRouter({
      name: 'betowrt',
      address: '192.168.0.1',
      username: 'root',
      password: 'secret',
    })
    const [url, init] = fetchMock.mock.calls[0]
    expect(url).toBe('/api/v1/routers')
    expect(init.method).toBe('POST')
    expect(JSON.parse(init.body)).toMatchObject({ name: 'betowrt' })
  })

  it('blocks a device', async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ id: 'd1', blocked: true }),
    })
    await api.blockDevice('d1')
    expect(fetchMock.mock.calls[0][0]).toBe('/api/v1/devices/d1/block')
    expect(fetchMock.mock.calls[0][1].method).toBe('POST')
  })

  it('throws on an error response', async () => {
    fetchMock.mockResolvedValue({
      ok: false,
      status: 500,
      text: async () => 'boom',
    })
    await expect(api.listRouters()).rejects.toThrow('boom')
  })

  it('lists policies', async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ items: [] }),
    })
    await api.listPolicies()
    expect(fetchMock.mock.calls[0][0]).toBe('/api/v1/policies')
  })

  it('creates a parental profile', async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      status: 201,
      json: async () => ({ id: 'p1', name: 'Kids' }),
    })
    await api.createParentalProfile({ name: 'Kids', daily_limit_minutes: 120 })
    const [url, init] = fetchMock.mock.calls[0]
    expect(url).toBe('/api/v1/parental/profiles')
    expect(init.method).toBe('POST')
    expect(JSON.parse(init.body).daily_limit_minutes).toBe(120)
  })

  it('updates adblock settings', async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ enabled: true, blocklists: [] }),
    })
    await api.updateAdblockSettings({ enabled: true, blocklists: ['stevenblack'] })
    const [url, init] = fetchMock.mock.calls[0]
    expect(url).toBe('/api/v1/adblock/settings')
    expect(init.method).toBe('PUT')
  })

  it('lists events', async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ items: [], total: 0 }),
    })
    await api.listEvents()
    expect(fetchMock.mock.calls[0][0]).toBe('/api/v1/events')
  })

  it('lists traffic series', async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ items: [] }),
    })
    await api.getTrafficSeries(24, 300)
    expect(fetchMock.mock.calls[0][0]).toBe(
      '/api/v1/traffic/series?hours=24&bucket=300',
    )
  })

  it('gets device details', async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ mac: 'aa:bb', hours: 12 }),
    })
    await api.getDeviceDetails('d1', 12)
    expect(fetchMock.mock.calls[0][0]).toBe(
      '/api/v1/devices/d1/details?hours=12',
    )
  })

  it('loads network status and runs a speed test', async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({}),
    })
    await api.getNetworkStatus()
    expect(fetchMock.mock.calls[0][0]).toBe('/api/v1/network/status')

    await api.runSpeedtest()
    expect(fetchMock.mock.calls[1][0]).toBe('/api/v1/network/speedtest')
    expect(fetchMock.mock.calls[1][1]?.method).toBe('POST')

    await api.setGeoIP(['va'])
    expect(fetchMock.mock.calls[2][0]).toBe('/api/v1/network/geoip')
    expect(fetchMock.mock.calls[2][1]?.method).toBe('PUT')

    await api.lookupGeoIP('1.1.1.1')
    expect(fetchMock.mock.calls[3][0]).toBe(
      '/api/v1/network/geoip/lookup?ip=1.1.1.1',
    )
  })

  it('renames a device', async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      status: 200,
      json: async () => ({ id: 'd1', display_name: 'Kitchen' }),
    })
    await api.updateDevice('d1', { display_name: 'Kitchen' })
    expect(fetchMock.mock.calls[0][0]).toBe('/api/v1/devices/d1')
    expect(fetchMock.mock.calls[0][1]?.method).toBe('PATCH')
    expect(fetchMock.mock.calls[0][1]?.body).toBe(
      JSON.stringify({ display_name: 'Kitchen' }),
    )
  })
})
