import { useMemo, useState } from 'react'
import { clsx } from 'clsx'
import { ArrowUpRight, TrendingUp } from 'lucide-react'
import { useReadContracts } from 'wagmi'
import { zeroAddress, type Address } from 'viem'
import { giwaSepolia } from '@/config'
import { LAUNCHPAD_ADDRESS, launchpadAbi } from '@/contracts/launchpad'
import { useTokens, type TokenView } from '@/hooks/useTokens'
import { fmtEth, fmtPrice, launchPrice, pctChange } from '@/lib/format'
import { TokenLogo } from './TokenLogo'
import { SearchInput, matchesQuery } from './SearchInput'
import { CardSkeleton, EmptyState, NotDeployedNotice } from './Notices'

type Sort = 'new' | 'cap' | 'volume'
const SORTS: { id: Sort; label: string }[] = [
  { id: 'new', label: 'Newest' },
  { id: 'cap', label: 'Market cap' },
  { id: 'volume', label: 'Volume' },
]

interface Props {
  onTrade: (token: Address) => void
  onLaunch: () => void
}

function Stat({ label, value, unit }: { label: string; value: string; unit?: string }) {
  return (
    <div className="glass rounded-2xl px-4 py-3">
      <div className="text-[10px] font-semibold uppercase tracking-[0.1em] text-subtle">{label}</div>
      <div className="mt-1 flex items-baseline gap-1">
        <span className="display text-xl font-bold tabular-nums">{value}</span>
        {unit && <span className="text-xs text-subtle">{unit}</span>}
      </div>
    </div>
  )
}

function TokenCard({ token, onTrade }: { token: TokenView; onTrade: (a: Address) => void }) {
  const change = pctChange(token.price, launchPrice())
  const up = change >= 0
  return (
    <button
      type="button"
      onClick={() => onTrade(token.address)}
      className="glass group flex flex-col gap-4 rounded-3xl p-4 text-left transition-colors hover:bg-surface-strong"
    >
      <div className="flex items-center gap-3">
        <TokenLogo logoURI={token.logoURI} symbol={token.symbol} size={44} />
        <div className="min-w-0 flex-1">
          <div className="display truncate text-base font-bold">{token.name}</div>
          <div className="text-xs font-semibold uppercase tracking-wide text-subtle">{token.symbol}</div>
        </div>
        <ArrowUpRight className="size-4 text-subtle transition-colors group-hover:text-ink" aria-hidden />
      </div>
      <div className="grid grid-cols-2 gap-3">
        <div>
          <div className="text-[10px] font-semibold uppercase tracking-[0.1em] text-subtle">Market cap</div>
          <div className="display text-lg font-bold tabular-nums">{fmtEth(token.marketCap)} ETH</div>
        </div>
        <div className="text-right">
          <div className="text-[10px] font-semibold uppercase tracking-[0.1em] text-subtle">Since launch</div>
          <div
            className={clsx('display text-lg font-bold tabular-nums', up ? 'text-success' : 'text-danger')}
          >
            {up ? '+' : ''}
            {change.toFixed(1)}%
          </div>
        </div>
      </div>
      <div className="flex items-center justify-between text-xs text-subtle">
        <span className="tabular-nums">Price {fmtPrice(token.price)} ETH</span>
        <span className="tabular-nums">Vol {fmtEth(token.volume)} ETH</span>
      </div>
    </button>
  )
}

function useGlobalStats() {
  const query = useReadContracts({
    allowFailure: false,
    contracts: [
      { address: LAUNCHPAD_ADDRESS ?? zeroAddress, abi: launchpadAbi, functionName: 'totalVolume', chainId: giwaSepolia.id },
      { address: LAUNCHPAD_ADDRESS ?? zeroAddress, abi: launchpadAbi, functionName: 'traderCount', chainId: giwaSepolia.id },
    ],
    query: { enabled: Boolean(LAUNCHPAD_ADDRESS), refetchInterval: 15_000 },
  })
  return query.data
}

export function MarketPage({ onTrade, onLaunch }: Props) {
  const { tokens, isLoading, enabled } = useTokens()
  const stats = useGlobalStats()
  const [query, setQuery] = useState('')
  const [sort, setSort] = useState<Sort>('new')

  const visible = useMemo(() => {
    const filtered = tokens.filter(
      (t) => t.launched && matchesQuery(query, [t.name, t.symbol, t.address]),
    )
    if (sort === 'cap') return [...filtered].sort((a, b) => (b.marketCap > a.marketCap ? 1 : -1))
    if (sort === 'volume') return [...filtered].sort((a, b) => (b.volume > a.volume ? 1 : -1))
    return filtered
  }, [tokens, query, sort])

  if (!enabled) return <NotDeployedNotice />

  return (
    <div className="space-y-5">
      <div className="flex flex-col gap-1">
        <h1 className="display text-3xl font-bold text-balance">Market</h1>
        <p className="text-sm text-muted">Every token launched on Kgiwa, live from {giwaSepolia.name}.</p>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
        <Stat label="Tokens" value={String(tokens.length)} />
        <Stat label="Total volume" value={stats ? fmtEth(stats[0]) : '...'} unit="ETH" />
        <Stat label="Traders" value={stats ? String(stats[1]) : '...'} />
      </div>

      <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
        <div className="sm:flex-1">
          <SearchInput value={query} onChange={setQuery} />
        </div>
        <div className="flex gap-1 overflow-x-auto" role="tablist" aria-label="Sort tokens">
          {SORTS.map((s) => (
            <button
              key={s.id}
              type="button"
              role="tab"
              aria-selected={sort === s.id}
              onClick={() => setSort(s.id)}
              className={clsx(
                'min-h-11 shrink-0 rounded-xl px-3.5 text-sm font-semibold',
                sort === s.id ? 'bg-surface-strong text-ink' : 'text-subtle hover:text-ink',
              )}
            >
              {s.label}
            </button>
          ))}
        </div>
      </div>

      {isLoading ? (
        <CardSkeleton />
      ) : visible.length === 0 ? (
        tokens.length === 0 ? (
          <div className="glass flex flex-col items-center gap-3 rounded-3xl p-10 text-center">
            <TrendingUp className="size-7 text-accent" aria-hidden />
            <h3 className="display text-lg font-bold">No tokens yet</h3>
            <p className="max-w-sm text-sm text-muted">Be the first to launch a token on Kgiwa.</p>
            <button
              type="button"
              onClick={onLaunch}
              className="min-h-11 rounded-xl bg-accent px-5 text-sm font-semibold text-bg hover:bg-accent-hover"
            >
              Launch a token
            </button>
          </div>
        ) : (
          <EmptyState title="No matches" body="No token matches that search. Try a different name, symbol or address." />
        )
      ) : (
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {visible.map((t) => (
            <TokenCard key={t.address} token={t} onTrade={onTrade} />
          ))}
        </div>
      )}
    </div>
  )
}
