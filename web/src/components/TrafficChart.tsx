import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import type { TrafficPoint } from '../api'

function formatClock(timestamp: number) {
  const date = new Date(timestamp * 1000)
  return Number.isNaN(date.getTime())
    ? String(timestamp)
    : date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
}

export function TrafficChart({
  data,
  height = 260,
}: {
  data: TrafficPoint[]
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
          margin={{ top: 8, right: 12, left: -18, bottom: 0 }}
        >
          <defs>
            <linearGradient id="flows" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="var(--accent)" stopOpacity={0.45} />
              <stop offset="100%" stopColor="var(--accent)" stopOpacity={0} />
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
            allowDecimals={false}
          />
          <Tooltip
            contentStyle={{
              background: 'var(--surface)',
              border: '1px solid var(--border)',
              borderRadius: 8,
              color: 'var(--text)',
            }}
          />
          <Area
            type="monotone"
            dataKey="flows"
            stroke="var(--accent)"
            strokeWidth={2}
            fill="url(#flows)"
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  )
}
