import { useMemo } from 'react'
import { useReadContracts } from 'wagmi'
import { zeroAddress, type Address } from 'viem'
import { giwaSepolia } from '@/config'
import { LAUNCHPAD_ADDRESS, launchpadAbi } from '@/contracts/launchpad'
import type { TokenView } from '@/hooks/useTokens'
import { useTx } from '@/hooks/useTx'
import { fmtEth } from '@/lib/format'
import { ActionButton } from './ActionButton'
import { TokenLogo } from './TokenLogo'

const chainId = giwaSepolia.id
const LP = LAUNCHPAD_ADDRESS ?? zeroAddress

interface Row {
  token: TokenView
  kind: 'holder' | 'creator'
  amount: bigint
}

/** Holder rewards and creator fees the connected wallet can claim, read live from the contract. */
export function RewardsSection({ tokens, account }: { tokens: TokenView[]; account: Address }) {
  const { run, status } = useTx()

  const created = useMemo(
    () => tokens.filter((t) => t.creator.toLowerCase() === account.toLowerCase()),
    [tokens, account],
  )

  const holder = useReadContracts({
    allowFailure: false,
    contracts: tokens.map((t) => ({
      address: LP,
      abi: launchpadAbi,
      functionName: 'pendingHolderRewards' as const,
      args: [t.address, account] as const,
      chainId,
    })),
    query: { enabled: tokens.length > 0, refetchInterval: 15_000 },
  })
  const creator = useReadContracts({
    allowFailure: false,
    contracts: created.map((t) => ({
      address: LP,
      abi: launchpadAbi,
      functionName: 'creatorFees' as const,
      args: [t.address] as const,
      chainId,
    })),
    query: { enabled: created.length > 0, refetchInterval: 15_000 },
  })

  const rows = useMemo<Row[]>(() => {
    const out: Row[] = []
    tokens.forEach((token, i) => {
      const amount = holder.data?.[i]
      if (amount && amount > 0n) out.push({ token, kind: 'holder', amount })
    })
    created.forEach((token, i) => {
      const amount = creator.data?.[i]
      if (amount && amount > 0n) out.push({ token, kind: 'creator', amount })
    })
    return out
  }, [tokens, created, holder.data, creator.data])

  if (rows.length === 0) return null

  const claim = (row: Row) =>
    run(row.kind === 'holder' ? 'Claim holder rewards' : 'Claim creator fees', (write) =>
      write({
        address: LP,
        abi: launchpadAbi,
        functionName: row.kind === 'holder' ? 'claimHolderRewards' : 'claimCreatorFees',
        args: [row.token.address],
        chainId,
      }),
    )

  return (
    <section className="space-y-3" aria-label="Claimable rewards">
      <h2 className="display text-xl font-bold">Claimable fees</h2>
      <div className="glass divide-y divide-line overflow-hidden rounded-3xl">
        {rows.map((row) => (
          <div key={`${row.kind}-${row.token.address}`} className="flex flex-wrap items-center gap-3 px-4 py-3">
            <TokenLogo logoURI={row.token.logoURI} symbol={row.token.symbol} size={36} />
            <div className="min-w-0 flex-1">
              <div className="truncate text-sm font-semibold">{row.token.name}</div>
              <div className="text-xs text-subtle">
                {row.kind === 'holder' ? 'Holder rewards (20% of trade fees)' : 'Creator fees (20% of trade fees)'}
              </div>
            </div>
            <div className="text-sm font-semibold tabular-nums">{fmtEth(row.amount)} ETH</div>
            <div className="w-full sm:w-36">
              <ActionButton label="Claim" onClick={async () => {
                  await claim(row)
                }} status={status} />
            </div>
          </div>
        ))}
      </div>
    </section>
  )
}
