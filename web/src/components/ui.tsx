import type {
  InputHTMLAttributes,
  MouseEvent,
  ReactNode,
  SelectHTMLAttributes,
} from 'react'

export function Badge({
  children,
  tone = 'slate',
}: {
  children: ReactNode
  tone?: 'slate' | 'emerald' | 'amber' | 'rose' | 'sky'
}) {
  const tones: Record<string, string> = {
    slate: 'bg-[var(--surface-2)] text-[var(--muted)]',
    emerald: 'bg-[var(--success-soft)] text-[var(--success)]',
    amber: 'bg-[var(--warning-soft)] text-[var(--warning)]',
    rose: 'bg-[var(--danger-soft)] text-[var(--danger)]',
    sky: 'bg-[var(--accent-soft)] text-[var(--accent-text)]',
  }
  return (
    <span className={`rounded-full px-2 py-0.5 text-xs ${tones[tone]}`}>
      {children}
    </span>
  )
}

export function Card({
  title,
  subtitle,
  actions,
  children,
  className = '',
}: {
  title?: string
  subtitle?: string
  actions?: ReactNode
  children: ReactNode
  className?: string
}) {
  return (
    <section
      className={`rounded-2xl border border-[var(--border)] bg-[var(--surface)] ${className}`}
    >
      {(title || actions) && (
        <div className="flex flex-wrap items-center justify-between gap-2 border-b border-[var(--border)] px-4 py-3">
          <div>
            {title && (
              <h2 className="text-sm font-semibold text-[var(--text-strong)]">{title}</h2>
            )}
            {subtitle && (
              <p className="mt-0.5 text-xs text-[var(--subtle)]">{subtitle}</p>
            )}
          </div>
          {actions}
        </div>
      )}
      {children}
    </section>
  )
}

export function Stat({
  label,
  value,
  hint,
}: {
  label: string
  value: string | number
  hint?: string
}) {
  return (
    <div className="rounded-2xl border border-[var(--border)] bg-gradient-to-br from-[var(--surface-3)] to-[var(--surface)] p-4">
      <p className="text-xs uppercase tracking-wide text-[var(--subtle)]">{label}</p>
      <p className="mt-1 text-2xl font-semibold text-[var(--text-strong)]">{value}</p>
      {hint && <p className="mt-1 text-xs text-[var(--subtle)]">{hint}</p>}
    </div>
  )
}

export function Button({
  children,
  onClick,
  type = 'button',
  variant = 'secondary',
  disabled = false,
}: {
  children: ReactNode
  onClick?: (event: MouseEvent<HTMLButtonElement>) => void
  type?: 'button' | 'submit'
  variant?: 'primary' | 'secondary' | 'danger'
  disabled?: boolean
}) {
  const variants = {
    primary:
      'bg-[var(--accent)] text-[var(--on-accent)] hover:bg-[var(--accent-strong)]',
    secondary:
      'bg-[var(--surface-2)] text-[var(--text)] hover:bg-[var(--surface-3)]',
    danger:
      'bg-[var(--danger-soft)] text-[var(--danger)] hover:opacity-90',
  }
  return (
    <button
      type={type}
      onClick={onClick}
      disabled={disabled}
      className={`rounded-md px-3 py-1.5 text-xs font-medium disabled:opacity-40 ${variants[variant]}`}
    >
      {children}
    </button>
  )
}

export function Field({
  label,
  children,
}: {
  label: string
  children: ReactNode
}) {
  return (
    <label className="grid gap-1 text-sm">
      <span className="text-[var(--muted)]">{label}</span>
      {children}
    </label>
  )
}

export function Input(props: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      {...props}
      className={`rounded-lg border border-[var(--border)] bg-[var(--input-bg)] px-3 py-2 text-[var(--text)] outline-none focus:border-[var(--accent)] ${props.className ?? ''}`}
    />
  )
}

export function Select(props: SelectHTMLAttributes<HTMLSelectElement>) {
  return (
    <select
      {...props}
      className={`rounded-lg border border-[var(--border)] bg-[var(--input-bg)] px-3 py-2 text-[var(--text)] outline-none focus:border-[var(--accent)] ${props.className ?? ''}`}
    />
  )
}

export function Empty({ children }: { children: ReactNode }) {
  return <p className="px-4 py-6 text-sm text-[var(--subtle)]">{children}</p>
}

export function PageHeader({
  title,
  subtitle,
  actions,
}: {
  title: string
  subtitle?: string
  actions?: ReactNode
}) {
  return (
    <div className="flex flex-wrap items-end justify-between gap-3">
      <div>
        <h1 className="text-2xl font-semibold text-[var(--text-strong)]">{title}</h1>
        {subtitle && <p className="mt-1 text-sm text-[var(--subtle)]">{subtitle}</p>}
      </div>
      {actions}
    </div>
  )
}
