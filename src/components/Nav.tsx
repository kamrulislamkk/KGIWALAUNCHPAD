import { ConnectKitButton } from 'connectkit'
import { clsx } from 'clsx'
import { Droplets, Wallet } from 'lucide-react'
import { GIWA_FAUCET_URL } from '@/config'
import { shortAddress } from '@/lib/format'

export type Tab = 'market' | 'trade' | 'launch' | 'fundraise' | 'portfolio' | 'staking' | 'admin'

const TABS: { id: Tab; label: string }[] = [
  { id: 'market', label: 'Market' },
  { id: 'trade', label: 'Trade' },
  { id: 'launch', label: 'Launch' },
  { id: 'fundraise', label: 'Fundraise' },
  { id: 'portfolio', label: 'Portfolio' },
  { id: 'staking', label: 'Staking' },
]

interface Props {
  tab: Tab
  onChange: (tab: Tab) => void
  /** Show the Admin tab (only for the contract owner wallet). */
  showAdmin?: boolean
}

export function Nav({ tab, onChange, showAdmin = false }: Props) {
  const tabs = showAdmin ? [...TABS, { id: 'admin' as const, label: 'Admin' }] : TABS
  return (
    <header
      className="sticky top-0 z-30 border-b border-line backdrop-blur-xl"
      style={{ background: 'rgba(13, 27, 47, 0.8)' }}
    >
      <div className="mx-auto flex max-w-6xl flex-wrap items-center gap-x-6 gap-y-2 px-4 py-3">
        <div className="flex items-center gap-2.5">
          <img
            src="/logo.png"
            alt="Kgiwa logo"
            width={40}
            height={40}
            className="size-10 rounded-full object-cover"
          />
          <div className="leading-tight">
            <div className="display text-lg font-bold">Kgiwa</div>
            <div className="text-[10px] font-semibold uppercase tracking-[0.1em] text-subtle">Launchpad terminal</div>
          </div>
        </div>

        <div className="ml-auto flex items-center gap-2 sm:order-3">
          <a
            href={GIWA_FAUCET_URL}
            target="_blank"
            rel="noopener noreferrer"
            className="glass hidden min-h-11 items-center gap-1.5 rounded-xl px-3 text-xs font-semibold text-muted hover:text-ink sm:flex"
          >
            <Droplets className="size-3.5" /> Faucet
          </a>
          <ConnectKitButton.Custom>
            {({ isConnected, show, address }) => (
              <button
                type="button"
                onClick={show}
                className="flex min-h-11 items-center gap-2 rounded-xl bg-accent px-4 text-sm font-semibold text-bg hover:bg-accent-hover"
              >
                <Wallet className="size-4" />
                {isConnected && address ? <span className="mono text-xs">{shortAddress(address)}</span> : 'Connect'}
              </button>
            )}
          </ConnectKitButton.Custom>
        </div>

        <nav
          aria-label="Sections"
          className="-mx-4 flex w-[calc(100%+2rem)] gap-1 overflow-x-auto px-4 sm:order-2 sm:mx-0 sm:w-auto sm:px-0"
        >
          {tabs.map((t) => (
            <button
              key={t.id}
              type="button"
              onClick={() => onChange(t.id)}
              aria-current={tab === t.id ? 'page' : undefined}
              className={clsx(
                'min-h-11 shrink-0 rounded-xl px-3.5 text-sm font-semibold transition-colors',
                tab === t.id ? 'bg-surface-strong text-ink' : 'text-subtle hover:text-ink',
              )}
            >
              {t.label}
              {t.id === 'staking' && (
                <span className="ml-1.5 rounded-full bg-surface-strong px-1.5 py-0.5 text-[9px] uppercase tracking-wider text-subtle">
                  Soon
                </span>
              )}
            </button>
          ))}
        </nav>
      </div>
    </header>
  )
}
