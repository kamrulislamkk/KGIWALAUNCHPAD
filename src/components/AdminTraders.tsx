import { useMemo, useState } from 'react'
import { Copy, Download } from 'lucide-react'
import { toast } from 'sonner'
import { useReadContracts } from 'wagmi'
import { formatEther, zeroAddress, type Address } from 'viem'
import { giwaSepolia } from '@/config'
import { LAUNCHPAD_ADDRESS, launchpadAbi } from '@/contracts/launchpad'
import type { AdminEventData } from '@/hooks/useAdminEvents'
import { copyText } from '@/lib/clipboard'
import { fmtEth, shortAddress } from '@/lib/format'
import { SearchInput } from './SearchInput'

const chainId = giwaSepolia.id
const LP = LAUNCHPAD_ADDRESS ?? zeroAddress
const MAX_ADDRESSES = 2000
const PAGE = 50

type SortKey = 'volume' | 'trades' | 'address'

interface Row {
  address: Address
  trades: number
  buyVolume: bigint
  sellVolume: bigint
  volume: bigint
}

interface Props {
  events?: AdminEventData
  eventsLoading: boolean
  traderCount?: number
}

export function AdminTraders({ events, eventsLoading, traderCount }: Props) {
  const [query, setQuery] = useState('')
  const [sort, setSort] = useState<SortKey>('volume')
  const [shown, setShown] = useState(PAGE)

  const count = Math.min(traderCount ?? 0, MAX_ADDRESSES)
  const addresses = useReadContracts({
    allowFailure: false,
    contracts: Array.from({ length: count }, (_, i) => ({
      address: LP,
      abi: launchpadAbi,
      functionName: 'traderAt' as const,
      args: [BigInt(i)] as const,
      chainId,
    })),
    query: { enabled: Boolean(LAUNCHPAD_ADDRESS) && count > 0, refetchInterval: 60_000 },
  })

  const rows = useMemo<Row[]>(() => {
    const list = (addresses.data ?? []).map((address) => {
      const agg = events?.traders.get(address.toLowerCase())
      const buyVolume = agg?.buyVolume ?? 0n
      const sellVolume = agg?.sellVolume ?? 0n
      return { address, trades: agg?.trades ?? 0, buyVolume, sellVolume, volume: buyVolume + sellVolume }
    })
    list.sort((a, b) => {
      if (sort === 'address') return a.address.localeCompare(b.address)
      if (sort === 'trades') return b.trades - a.trades
      return a.volume === b.volume ? 0 : a.volume > b.volume ? -1 : 1
    })
    return list
  }, [addresses.data, events, sort])

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    return q ? rows.filter((r) => r.address.toLowerCase().includes(q)) : rows
  }, [rows, query])

  const copy = async (text: string, message: string) => {
    if (await copyText(text)) toast.success(message)
    else toast.error('Your browser blocked copying. Select the text and copy it manually.')
  }

  const csv = () =>
    ['wallet,trades,buy_eth,sell_eth,total_eth']
      .concat(
        rows.map((r) => `${r.address},${r.trades},${formatEther(r.buyVolume)},${formatEther(r.sellVolume)},${formatEther(r.volume)}`),
      )
      .join('\n')

  return (
    <section className="glass rounded-3xl p-5 sm:p-6" aria-labelledby="traders-title">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 id="traders-title" className="display text-lg font-bold">
            Traders
          </h2>
          <p className="mt-1 text-xs text-subtle">
            {traderCount === undefined ? 'Loading...' : `${traderCount} unique wallet${traderCount === 1 ? '' : 's'}`}
            {events && ` · volume counted from block ${events.fromBlock.toString()}`}
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            disabled={rows.length === 0}
            onClick={() => void copy(rows.map((r) => r.address).join('\n'), `Copied ${rows.length} addresses`)}
            className="flex min-h-11 items-center gap-1.5 rounded-xl bg-accent px-3.5 text-sm font-semibold text-bg hover:bg-accent-hover disabled:opacity-40"
          >
            <Copy className="size-4" /> Copy all addresses
          </button>
          <button
            type="button"
            disabled={rows.length === 0}
            onClick={() => void copy(csv(), 'Copied CSV with volumes')}
            className="glass flex min-h-11 items-center gap-1.5 rounded-xl px-3.5 text-sm font-semibold hover:bg-surface-strong disabled:opacity-40"
          >
            <Download className="size-4" /> Copy as CSV
          </button>
        </div>
      </div>

      <div className="mt-4 flex flex-wrap items-center gap-2">
        <div className="min-w-0 flex-1 basis-56">
          <SearchInput value={query} onChange={setQuery} placeholder="Search wallet address" label="Search wallets" />
        </div>
        <label className="glass flex min-h-11 items-center gap-2 rounded-2xl px-3 text-sm">
          <span className="text-subtle">Sort</span>
          <select
            value={sort}
            onChange={(e) => setSort(e.target.value as SortKey)}
            className="bg-transparent py-2 outline-none"
            aria-label="Sort traders"
          >
            <option value="volume" className="text-bg">Volume</option>
            <option value="trades" className="text-bg">Trades</option>
            <option value="address" className="text-bg">Address</option>
          </select>
        </label>
      </div>

      {(addresses.isLoading || eventsLoading) && <p className="mt-4 text-sm text-subtle">Loading traders...</p>}
      {traderCount === 0 && <p className="mt-4 text-sm text-subtle">No trades yet.</p>}
      {traderCount !== undefined && traderCount > MAX_ADDRESSES && (
        <p className="mt-3 text-xs text-subtle">Showing the first {MAX_ADDRESSES} wallets.</p>
      )}

      {filtered.length > 0 && (
        <div className="mt-4 overflow-x-auto">
          <table className="w-full min-w-[560px] text-left text-sm">
            <thead className="text-xs text-subtle">
              <tr>
                <th className="py-2 pr-3 font-medium">Wallet</th>
                <th className="py-2 pr-3 text-right font-medium">Trades</th>
                <th className="py-2 pr-3 text-right font-medium">Bought (ETH)</th>
                <th className="py-2 pr-3 text-right font-medium">Sold (ETH)</th>
                <th className="py-2 pr-3 text-right font-medium">Volume (ETH)</th>
                <th className="py-2 text-right font-medium">
                  <span className="sr-only">Copy</span>
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-line">
              {filtered.slice(0, shown).map((r) => (
                <tr key={r.address}>
                  <td className="py-2.5 pr-3">
                    <a
                      href={`${giwaSepolia.blockExplorers.default.url}/address/${r.address}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="mono text-xs hover:text-accent"
                      title={r.address}
                    >
                      {shortAddress(r.address)}
                    </a>
                  </td>
                  <td className="py-2.5 pr-3 text-right tabular-nums">{r.trades}</td>
                  <td className="py-2.5 pr-3 text-right tabular-nums">{fmtEth(r.buyVolume)}</td>
                  <td className="py-2.5 pr-3 text-right tabular-nums">{fmtEth(r.sellVolume)}</td>
                  <td className="py-2.5 pr-3 text-right font-semibold tabular-nums">{fmtEth(r.volume)}</td>
                  <td className="py-2.5 text-right">
                    <button
                      type="button"
                      onClick={() => void copy(r.address, 'Address copied')}
                      aria-label={`Copy ${r.address}`}
                      className="inline-flex size-9 items-center justify-center rounded-lg text-subtle hover:bg-surface-strong hover:text-ink"
                    >
                      <Copy className="size-4" />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {filtered.length > shown && (
            <button
              type="button"
              onClick={() => setShown((n) => n + PAGE)}
              className="glass mt-3 min-h-11 w-full rounded-xl text-sm font-semibold hover:bg-surface-strong"
            >
              Show more ({filtered.length - shown} left)
            </button>
          )}
        </div>
      )}
      {query && filtered.length === 0 && rows.length > 0 && <p className="mt-4 text-sm text-subtle">No wallet matches.</p>}
    </section>
  )
}
