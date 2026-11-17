import { useMemo, useState } from 'react'
import { clsx } from 'clsx'
import { Plus } from 'lucide-react'
import type { Address } from 'viem'
import { FUNDRAISE_STATUS, LAUNCHPAD_ADDRESS } from '@/contracts/launchpad'
import { useFundraises } from '@/hooks/useFundraises'
import { CreateFundraise } from './CreateFundraise'
import { FundraiseCard } from './FundraiseCard'
import { SearchInput, matchesQuery } from './SearchInput'
import { CardSkeleton, EmptyState, NotDeployedNotice } from './Notices'

type Filter = 'active' | 'launched' | 'cancelled' | 'all'
const FILTERS: { id: Filter; label: string; status?: number }[] = [
  { id: 'active', label: 'Raising', status: FUNDRAISE_STATUS.Active },
  { id: 'launched', label: 'Launched', status: FUNDRAISE_STATUS.Launched },
  { id: 'cancelled', label: 'Cancelled', status: FUNDRAISE_STATUS.Cancelled },
  { id: 'all', label: 'All' },
]

export function FundraisePage({ onTrade }: { onTrade: (token: Address) => void }) {
  const { fundraises, isLoading, enabled } = useFundraises()
  const [filter, setFilter] = useState<Filter>('active')
  const [query, setQuery] = useState('')
  const [creating, setCreating] = useState(false)

  const visible = useMemo(() => {
    const status = FILTERS.find((f) => f.id === filter)?.status
    return fundraises.filter(
      (f) => (status === undefined || f.status === status) && matchesQuery(query, [f.name, f.symbol, f.creator]),
    )
  }, [fundraises, filter, query])

  if (!LAUNCHPAD_ADDRESS || !enabled) return <NotDeployedNotice />

  return (
    <div className="space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="display text-3xl font-bold text-balance">Fundraise</h1>
          <p className="mt-1 max-w-xl text-sm text-muted">
            Back a token before it exists. When the target fills, it launches on the market and you claim your tokens.
          </p>
        </div>
        <button
          type="button"
          onClick={() => setCreating((v) => !v)}
          aria-expanded={creating}
          className="inline-flex min-h-11 items-center gap-2 rounded-xl bg-accent px-4 text-sm font-semibold text-bg hover:bg-accent-hover"
        >
          <Plus className="size-4" /> {creating ? 'Close form' : 'Create fundraise'}
        </button>
      </div>

      {creating && (
        <div className="mx-auto max-w-2xl">
          <CreateFundraise onCreated={() => setCreating(false)} />
        </div>
      )}

      <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
        <div className="sm:flex-1">
          <SearchInput value={query} onChange={setQuery} placeholder="Search by name, symbol or creator" label="Search fundraises" />
        </div>
        <div className="flex gap-1 overflow-x-auto" role="tablist" aria-label="Filter fundraises">
          {FILTERS.map((f) => (
            <button
              key={f.id}
              type="button"
              role="tab"
              aria-selected={filter === f.id}
              onClick={() => setFilter(f.id)}
              className={clsx(
                'min-h-11 shrink-0 rounded-xl px-3.5 text-sm font-semibold',
                filter === f.id ? 'bg-surface-strong text-ink' : 'text-subtle hover:text-ink',
              )}
            >
              {f.label}
            </button>
          ))}
        </div>
      </div>

      {isLoading ? (
        <CardSkeleton count={3} />
      ) : visible.length === 0 ? (
        <EmptyState
          title={fundraises.length === 0 ? 'No fundraises yet' : 'Nothing here'}
          body={
            fundraises.length === 0
              ? 'Create the first fundraise and let backers fill it before launch.'
              : 'No fundraise matches this filter or search.'
          }
        />
      ) : (
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {visible.map((f) => (
            <FundraiseCard key={f.id} fundraise={f} onTrade={onTrade} />
          ))}
        </div>
      )}
    </div>
  )
}
