import { useState } from 'react'
import { clsx } from 'clsx'

const HUES = [210, 160, 28, 280, 340, 190, 50, 250]

function hueFor(seed: string): number {
  let h = 0
  for (let i = 0; i < seed.length; i++) h = (h * 31 + seed.charCodeAt(i)) >>> 0
  return HUES[h % HUES.length]
}

interface Props {
  logoURI?: string
  symbol: string
  size?: number
  className?: string
}

/** Token image from its onchain logoURI, with an initials fallback. */
export function TokenLogo({ logoURI, symbol, size = 40, className }: Props) {
  const [failed, setFailed] = useState(false)
  const showImage = Boolean(logoURI) && !failed
  const hue = hueFor(symbol)

  return (
    <div
      className={clsx('shrink-0 overflow-hidden rounded-full', className)}
      style={{
        width: size,
        height: size,
        background: showImage ? 'var(--surface-muted)' : `hsl(${hue} 35% 28%)`,
      }}
    >
      {showImage ? (
        <img
          src={logoURI}
          alt={`${symbol} logo`}
          width={size}
          height={size}
          className="size-full object-cover"
          onError={() => setFailed(true)}
        />
      ) : (
        <div
          className="display flex size-full items-center justify-center font-bold"
          style={{ fontSize: size * 0.38, color: `hsl(${hue} 60% 85%)` }}
        >
          {symbol.slice(0, 2).toUpperCase()}
        </div>
      )}
    </div>
  )
}
