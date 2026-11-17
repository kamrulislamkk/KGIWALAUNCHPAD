import { useMemo, useState } from 'react'
import { clsx } from 'clsx'
import { ExternalLink } from 'lucide-react'
import type { Address } from 'viem'
import { giwaSepolia } from '@/config'
import { useTokens, type TokenView } from '@/hooks/useTokens'
import { useTrades } from '@/hooks/useTrades'
import { fmtEth, fmtPrice, fmtTokens, launchPrice, pctChange, shortAddress } from '@/lib/format'
import { SearchInput, matchesQuery } from './SearchInput'
import { Sparkline } from './Sparkline'
import { TokenLogo } from './TokenLogo'
import { TradeFeed } from './TradeFeed'
import { TradePanel } from './TradePanel'
import { EmptyState, NotDeployedNotice } from './Notices'

interface Props {
  selected?: Address
  onSelect: (token: Address) => void
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="glass-inner rounded-2xl px-3.5 py-3">
      <div className="text-[10px] font-semibold uppercase tracking-[0.1em] text-subtle">{label}</div>
      <div className="mt-0.5 truncate text-sm font-semibold tabular-nums">{value}</div>
    </div>
  )
}

function TokenDetail({ token }: { token: TokenView }) {
  const trades = useTrades(token.address)
  const change = pctChange(token.price, launchPrice())
  const series = useMemo(
    () => [...(trades.data ?? [])].reverse().map((t) => Number(t.newPrice)),
    [trades.data],
  )

  return (
    <div className="space-y-4">
      <section className="glass rounded-3xl p-4 sm:p-5">
        <div className="flex items-center gap-3">
          <TokenLogo logoURI={token.logoURI} symbol={token.symbol} size={52} />
          <div className="min-w-0 flex-1">
            <h2 className="display truncate text-2xl font-bold">{token.name}</h2>
            <div className="flex flex-wrap items-center gap-x-3 text-xs text-subtle">
              <span className="font-semibold uppercase tracking-wide">{token.symbol}</span>
              <a
                href={`${giwaSepolia.blockExplorers.default.url}/token/${token.address}`}
                target="_blank"
                rel="noopener noreferrer"
                className="mono inline-flex items-center gap-1 hover:text-ink"
              >
                {shortAddress(token.address)} <ExternalLink className="size-3" />
              </a>
            </div>
          </div>
          <div className="text-right">
            <div className="display text-2xl font-bold tabular-nums">{fmtEth(token.marketCap)}</div>
            <div className="text-xs text-subtle">ETH market cap</div>
          </div>
        </div>

        <div className="mt-4">
          <Sparkline values={series} height={96} />
        </div>

        <div className="mt-4 grid grid-cols-2 gap-2 sm:grid-cols-4">
          <Stat label="Price" value={`${fmtPrice(token.price)} ETH`} />
          <Stat label="Since launch" value={`${change >= 0 ? '+' : ''}${change.toFixed(1)}%`} />
          <Stat label="Volume" value={`${fmtEth(token.volume)} ETH`} />
          <Stat label="Liquidity" value={`${fmtEth(token.reserveETH)} ETH`} />
          <Stat label="Max supply" value={fmtTokens(token.supply)} />
          <Stat label="Left on curve" value={fmtTokens(token.curveInventory)} />
          <Stat label="Trade fee" value={`${Number(token.tradeFeeBps) / 100}%`} />
          <Stat label="Creator" value={shortAddress(token.creator)} />
        </div>
      </section>

      <TradeFeed trades={trades.data} symbol={token.symbol} isLoading={trades.isLoading} />
    </div>
  )
}

export function TradePage({ selected, onSelect }: Props) {
  const { tokens, isLoading, enabled } = useTokens()
  const [query, setQuery] = useState('')

  const launched = useMemo(() => tokens.filter((t) => t.launched), [tokens])
  const results = useMemo(
    () => launched.filter((t) => matchesQuery(query, [t.name, t.symbol, t.address])),
    [launched, query],
  )
  const token = launched.find((t) => t.address === selected) ?? undefined

  if (!enabled) return <NotDeployedNotice />

  return (
    <div className="space-y-5">
      <div>
        <h1 className="display text-3xl font-bold text-balance">Trade</h1>
        <p className="mt-1 text-sm text-muted">Search a token, then buy or sell against the curve.</p>
      </div>

      <div className="grid gap-5 lg:grid-cols-[280px_minmax(0,1fr)_380px]">
        <aside className="space-y-3 lg:sticky lg:top-24 lg:self-start">
          <SearchInput value={query} onChange={setQuery} />
          <div className="glass max-h-72 overflow-y-auto rounded-3xl p-2 lg:max-h-[60vh]">
            {isLoading ? (
              <div className="h-24 animate-pulse rounded-2xl" />
            ) : results.length === 0 ? (
              <p className="p-4 text-center text-sm text-subtle">
                {launched.length === 0 ? 'No tokens launched yet.' : 'No matches.'}
              </p>
            ) : (
              <ul>
                {results.map((t) => (
                  <li key={t.address}>
                    <button
                      type="button"
                      onClick={() => onSelect(t.address)}
                      aria-current={t.address === selected ? 'true' : undefined}
                      className={clsx(
                        'flex min-h-14 w-full items-center gap-3 rounded-2xl px-3 py-2 text-left transition-colors',
                        t.address === selected ? 'bg-surface-strong' : 'hover:bg-surface',
                      )}
                    >
                      <TokenLogo logoURI={t.logoURI} symbol={t.symbol} size={34} />
                      <div className="min-w-0 flex-1">
                        <div className="truncate text-sm font-semibold">{t.name}</div>
                        <div className="text-xs uppercase text-subtle">{t.symbol}</div>
                      </div>
                      <div className="text-right text-xs tabular-nums text-muted">{fmtEth(t.marketCap)} ETH</div>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </aside>

        {token ? (
          <>
            <div className="min-w-0 lg:order-none">
              <TokenDetail token={token} />
            </div>
            <div className="lg:sticky lg:top-24 lg:self-start">
              <TradePanel key={token.address} token={token} />
            </div>
          </>
        ) : (
          <div className="lg:col-span-2">
            <EmptyState
              title="Pick a token to trade"
              body="Search by name, symbol or address, or open one from the Market tab."
            />
          </div>
        )}
      </div>
    </div>
  )
}
