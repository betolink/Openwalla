import { render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import App from './App'

beforeEach(() => {
  vi.stubGlobal(
    'fetch',
    vi.fn((url: string) => {
      if (String(url).includes('/routers')) {
        return Promise.resolve({
          ok: true,
          status: 200,
          json: async () => ({
            items: [
              {
                id: 'r1',
                name: 'betowrt',
                address: '192.168.0.1',
                status: 'online',
                model: 'x86/64',
                has_credentials: true,
              },
            ],
            total: 1,
          }),
        })
      }
      if (String(url).includes('/devices')) {
        return Promise.resolve({
          ok: true,
          status: 200,
          json: async () => ({
            items: [
              {
                id: 'd1',
                router_id: 'r1',
                mac: 'aa:bb:cc:dd:ee:01',
                ipv4: '192.168.0.50',
                hostname: 'phone',
                vendor: 'Acme',
                device_type: 'phone',
                connection: 'wireless',
                online: true,
                blocked: false,
                paused: false,
              },
            ],
            total: 1,
          }),
        })
      }
      return Promise.resolve({
        ok: true,
        status: 200,
        json: async () => ({}),
      })
    }),
  )
})

afterEach(() => {
  vi.unstubAllGlobals()
})

describe('App', () => {
  it('renders routers and devices from the API', async () => {
    render(<App />)
    expect(await screen.findByText('betowrt')).toBeInTheDocument()
    expect((await screen.findAllByText('phone')).length).toBeGreaterThan(0)
  })
})
