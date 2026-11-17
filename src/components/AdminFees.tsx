import { useMemo } from 'react'
import { useReadContracts } from 'wagmi'
import { zeroAddress } from 'viem'
import { giwaSepolia } from '@/config'
import { LAUNCHPAD_ADDRESS, launchpadAbi } from '@/contracts/launchpad'
import type { AdminEventData } from '@/hooks/useAdminEvents'
import { useTokens } from '@/hooks/useTokens'
import { fmtEth } from '@/lib/format'

const chainId = giwaSepolia.id
const LP = LAUNCHPAD_ADDRESS ?? zeroAddress

function Stat({ label, value, hint, strong }: { label: string; value: string; hint?: string; strong?: boolean }) {
  return (
    <div className="glass-inner rounded-2xl p-4">
      <div className="text-xs text-subtle">{label}</div>
      <div className={strong ? 'display mt-1 text-2xl font-bold tabular-nums' : 'mt-1 text-lg font-semibold tabular-nums'}>
        {value} <span className="text-sm font-medium text-subtle">ETH</span>
      </div>
      {hint && <div className="mt-1 text-xs text-subtle">{hint}</div>}
    </div>
  )
}

interface Props {
  events?: AdminEventData
  loading: boolean
  failed: boolean
  instantFee?: bigint
  totalVolume?: bigint
}

export function AdminFees({ events, loading, failed, instantFee, totalVolume }: Props) {
  const { tokens } = useTokens()
  const enabled = Boolean(LAUNCHPAD_ADDRESS) && tokens.length > 0

  const creatorFees = useReadContracts({
    allowFailure: false,
    contracts: tokens.map((t) => ({
      address: LP,
      abi: launchpadAbi,
      functionName: 'creatorFees' as const,
      args: [t.address] as const,
      chainId,
    })),
    query: { enabled, refetchInterval: 30_000 },
  })
  const holderPools = useReadContracts({
    allowFailure: false,
    contracts: tokens.map((t) => ({
      address: LP,
      abi: launchpadAbi,
      functionName: 'holderPool' as const,
      args: [t.address] as const,
      chainId,
    })),
    query: { enabled, refetchInterval: 30_000 },
  })

  const held = useMemo(() => {
    const sum = (list?: readonly bigint[]) => (list ?? []).reduce((a, b) => a + b, 0n)
    return {
      creator: sum(creatorFees.data),
      holders: sum(holderPools.data),
      reserves: tokens.reduce((a, t) => a + t.reserveETH, 0n),
    }
  }, [creatorFees.data, holderPools.data, tokens])

  const instantFees = events && instantFee !== undefined ? BigInt(events.instantLaunches) * instantFee : undefined
  const total =
    events && instantFees !== undefined
      ? events.platformTradeFees + events.fundraiseCreationFees + instantFees
      : undefined

  return (
    <section className="glass rounded-3xl p-5 sm:p-6" aria-labelledby="fees-title">
      <h2 id="fees-title" className="display text-lg font-bold">
        Fees collected
      </h2>
      <p className="mt-1 text-xs text-subtle">
        The platform share of trading fees and all creation fees are paid straight to the treasury wallet, so there is
        nothing to claim. These are running totals.
      </p>

      {failed && (
        <p className="mt-3 text-sm text-danger">Could not read fee history from the network. Try again in a moment.</p>
      )}

      <div className="mt-4 grid gap-3 sm:grid-cols-2">
        <Stat
          label="Total collected by treasury"
          value={loading || total === undefined ? '...' : fmtEth(total)}
          strong
        />
        <Stat
          label="Trading fees (platform 40%)"
          value={loading || !events ? '...' : fmtEth(events.platformTradeFees)}
        />
        <Stat
          label="Fundraise creation fees"
          value={loading || !events ? '...' : fmtEth(events.fundraiseCreationFees)}
          hint={events ? `${events.fundraisesCreated} fundraise${events.fundraisesCreated === 1 ? '' : 's'} created` : undefined}
        />
        <Stat
          label="Instant launch fees"
          value={loading || instantFees === undefined ? '...' : fmtEth(instantFees)}
          hint={events ? `${events.instantLaunches} instant launch${events.instantLaunches === 1 ? '' : 'es'}` : undefined}
        />
      </div>

      {events?.truncated && (
        <p className="mt-3 text-xs text-subtle">
          Totals cover blocks {events.fromBlock.toString()} to {events.head.toString()}. Older activity is not counted.
        </p>
      )}

      <h3 className="mt-6 text-sm font-semibold">Held by the contract for others</h3>
      <p className="mt-1 text-xs text-subtle">The owner cannot claim these. They belong to creators, holders and sellers.</p>
      <div className="mt-3 grid gap-3 sm:grid-cols-3">
        <Stat label="Creator fees unclaimed" value={fmtEth(held.creator)} />
        <Stat label="Holder reward pools" value={fmtEth(held.holders)} />
        <Stat label="Curve reserves" value={fmtEth(held.reserves)} />
      </div>
      {totalVolume !== undefined && (
        <p className="mt-4 text-xs text-subtle">All-time trading volume: {fmtEth(totalVolume)} ETH</p>
      )}
    </section>
  )
}
