import {
  Area,
  AreaChart,
  CartesianGrid,
  Legend,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import type { DeviceDetails } from '../api'
import { formatBytes } from '../utils/format'

function formatClock(timestamp: number) {
  const date = new Date(timestamp * 1000)
  return Number.isNaN(date.getTime())
    ? String(timestamp)
    : date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
}

export function DeviceTrafficChart({
  data,
  height = 280,
}: {
  data: DeviceDetails['series']
  height?: number
}) {
  const chartData = data.map((point) => ({
    ...point,
    label: formatClock(point.timestamp),
  }))

  return (
    <div className="px-2 pb-3 pt-5" style={{ height }}>
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart
          data={chartData}
          margin={{ top: 8, right: 12, left: -10, bottom: 0 }}
        >
          <defs>
            <linearGradient id="device-down" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="var(--accent)" stopOpacity={0.4} />
              <stop offset="100%" stopColor="var(--accent)" stopOpacity={0} />
            </linearGradient>
            <linearGradient id="device-up" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="var(--success)" stopOpacity={0.35} />
              <stop offset="100%" stopColor="var(--success)" stopOpacity={0} />
            </linearGradient>
          </defs>
          <CartesianGrid
            stroke="var(--border)"
            strokeDasharray="3 3"
            vertical={false}
          />
          <XAxis
            dataKey="label"
            tick={{ fill: 'var(--subtle)', fontSize: 11 }}
            tickLine={false}
            axisLine={false}
            minTickGap={32}
          />
          <YAxis
            tick={{ fill: 'var(--subtle)', fontSize: 11 }}
            tickLine={false}
            axisLine={false}
            tickFormatter={(value) => formatBytes(Number(value))}
          />
          <Tooltip
            formatter={(value) => formatBytes(Number(value))}
            contentStyle={{
              background: 'var(--surface)',
              border: '1px solid var(--border)',
              borderRadius: 8,
              color: 'var(--text)',
            }}
          />
          <Legend wrapperStyle={{ fontSize: 12, color: 'var(--muted)' }} />
          <Area
            type="monotone"
            dataKey="download"
            name="Download"
            stroke="var(--accent)"
            strokeWidth={2}
            fill="url(#device-down)"
          />
          <Area
            type="monotone"
            dataKey="upload"
            name="Upload"
            stroke="var(--success)"
            strokeWidth={2}
            fill="url(#device-up)"
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  )
}
