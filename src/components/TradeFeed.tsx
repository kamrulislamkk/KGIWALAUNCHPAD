import { clsx } from 'clsx'
import { ExternalLink } from 'lucide-react'
import { giwaSepolia } from '@/config'
import type { TradeView } from '@/hooks/useTrades'
import { fmtEth, fmtTokens, shortAddress, timeAgo } from '@/lib/format'

interface Props {
  trades: TradeView[] | undefined
  symbol: string
  isLoading: boolean
}

export function TradeFeed({ trades, symbol, isLoading }: Props) {
  return (
    <section className="glass rounded-3xl p-4 sm:p-5" aria-label="Recent trades">
      <h3 className="display mb-3 text-base font-bold">Recent trades</h3>
      {isLoading ? (
        <div className="h-24 animate-pulse rounded-2xl" style={{ background: 'rgba(255,255,255,0.05)' }} />
      ) : !trades || trades.length === 0 ? (
        <p className="py-6 text-center text-sm text-subtle">No trades yet.</p>
      ) : (
        <ul className="divide-y divide-line">
          {trades.slice(0, 20).map((t) => (
            <li key={`${t.txHash}-${t.logIndex}`} className="flex items-center gap-3 py-2.5 text-sm">
              <span
                className={clsx(
                  'w-10 shrink-0 text-xs font-bold uppercase',
                  t.isBuy ? 'text-success' : 'text-danger',
                )}
              >
                {t.isBuy ? 'Buy' : 'Sell'}
              </span>
              <span className="min-w-0 flex-1 truncate tabular-nums">
                {fmtTokens(t.tokenAmount)} {symbol}
                <span className="text-subtle"> for {fmtEth(t.ethAmount)} ETH</span>
              </span>
              <span className="mono hidden text-xs text-subtle sm:inline">{shortAddress(t.trader)}</span>
              <span className="w-14 shrink-0 text-right text-xs text-subtle">
                {t.timestamp ? timeAgo(t.timestamp) : `#${t.blockNumber}`}
              </span>
              <a
                href={`${giwaSepolia.blockExplorers.default.url}/tx/${t.txHash}`}
                target="_blank"
                rel="noopener noreferrer"
                aria-label="View transaction"
                className="text-subtle hover:text-ink"
              >
                <ExternalLink className="size-3.5" />
              </a>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}
