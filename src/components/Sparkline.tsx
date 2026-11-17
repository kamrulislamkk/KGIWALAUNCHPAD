interface Props {
  values: number[]
  width?: number
  height?: number
  className?: string
  label?: string
}

/** Minimal price line. Colour follows direction: green when up, red when down. */
export function Sparkline({ values, width = 320, height = 80, className, label = 'Price history' }: Props) {
  if (values.length < 2) {
    return (
      <div
        className={`flex items-center justify-center rounded-2xl text-xs text-subtle ${className ?? ''}`}
        style={{ height }}
      >
        Price history appears after the first trades
      </div>
    )
  }
  const min = Math.min(...values)
  const max = Math.max(...values)
  const range = max - min || 1
  const pad = 4
  const step = (width - pad * 2) / (values.length - 1)
  const points = values.map((v, i) => `${pad + i * step},${height - pad - ((v - min) / range) * (height - pad * 2)}`)
  const up = values[values.length - 1] >= values[0]
  const color = up ? 'var(--success)' : 'var(--danger)'
  const area = `${pad},${height - pad} ${points.join(' ')} ${pad + (values.length - 1) * step},${height - pad}`

  return (
    <svg
      viewBox={`0 0 ${width} ${height}`}
      className={className}
      role="img"
      aria-label={label}
      preserveAspectRatio="none"
      style={{ width: '100%', height }}
    >
      <polygon points={area} fill={color} opacity={0.12} />
      <polyline points={points.join(' ')} fill="none" stroke={color} strokeWidth={2} strokeLinejoin="round" />
    </svg>
  )
}
