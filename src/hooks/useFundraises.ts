import { useMemo } from 'react'
import { useAccount, useReadContract, useReadContracts } from 'wagmi'
import { zeroAddress, type Address } from 'viem'
import { giwaSepolia } from '@/config'
import { LAUNCHPAD_ADDRESS, launchpadAbi } from '@/contracts/launchpad'

const chainId = giwaSepolia.id
const LP = LAUNCHPAD_ADDRESS ?? zeroAddress

export interface FundraiseView {
  id: number
  creator: Address
  name: string
  symbol: string
  logoURI: string
  supply: bigint
  targetETH: bigint
  raised: bigint
  price: bigint
  tradeFeeBps: bigint
  status: number
  token: Address
  /** Unix seconds after which an unfilled fundraise accepts no contributions and can be refunded. */
  deadline: number
  /** 0 means instant release; otherwise tokens unlock in hourly steps over this many hours. */
  vestingHours: number
  /** Unix seconds when the target filled and vesting started (0 until launched). */
  launchTime: number
  /** Vested but unclaimed tokens for the connected wallet. */
  claimable: bigint
  mine?: {
    ethContributed: bigint
    tokensAllocated: bigint
    claimed: boolean
    refunded: boolean
  }
}

export function useFundraises() {
  const { address: account } = useAccount()
  const enabled = Boolean(LAUNCHPAD_ADDRESS)

  const countQuery = useReadContract({
    address: LP,
    abi: launchpadAbi,
    functionName: 'fundraiseCount',
    chainId,
    query: { enabled, refetchInterval: 12_000 },
  })
  const count = countQuery.data === undefined ? 0 : Number(countQuery.data)

  const dataQuery = useReadContracts({
    allowFailure: false,
    contracts: Array.from({ length: count }, (_, i) => ({
      address: LP,
      abi: launchpadAbi,
      functionName: 'fundraises' as const,
      args: [BigInt(i)] as const,
      chainId,
    })),
    query: { enabled: enabled && count > 0, refetchInterval: 10_000 },
  })

  const deadlineQuery = useReadContracts({
    allowFailure: false,
    contracts: Array.from({ length: count }, (_, i) => ({
      address: LP,
      abi: launchpadAbi,
      functionName: 'fundraiseDeadline' as const,
      args: [BigInt(i)] as const,
      chainId,
    })),
    query: { enabled: enabled && count > 0, staleTime: Infinity },
  })

  // Older contract versions have no vesting views; those reads fail and the fundraise counts as instant.
  const vestingQuery = useReadContracts({
    allowFailure: true,
    contracts: Array.from({ length: count }, (_, i) => ({
      address: LP,
      abi: launchpadAbi,
      functionName: 'fundraiseVesting' as const,
      args: [BigInt(i)] as const,
      chainId,
    })),
    query: { enabled: enabled && count > 0, refetchInterval: 20_000 },
  })

  const claimableQuery = useReadContracts({
    allowFailure: true,
    contracts: Array.from({ length: count }, (_, i) => ({
      address: LP,
      abi: launchpadAbi,
      functionName: 'claimableOf' as const,
      args: [BigInt(i), account ?? zeroAddress] as const,
      chainId,
    })),
    query: { enabled: enabled && count > 0 && Boolean(account), refetchInterval: 15_000 },
  })

  const mineQuery = useReadContracts({
    allowFailure: false,
    contracts: Array.from({ length: count }, (_, i) => ({
      address: LP,
      abi: launchpadAbi,
      functionName: 'fundraiseContribution' as const,
      args: [BigInt(i), account ?? zeroAddress] as const,
      chainId,
    })),
    query: { enabled: enabled && count > 0 && Boolean(account), refetchInterval: 10_000 },
  })

  const fundraises = useMemo<FundraiseView[]>(() => {
    const rows = dataQuery.data
    if (!rows) return []
    const result: FundraiseView[] = []
    rows.forEach((row, i) => {
      const [creator, name, symbol, logoURI, supply, targetETH, raised, price, tradeFeeBps, status, token] = row
      const mine = mineQuery.data?.[i]
      const vesting = vestingQuery.data?.[i]
      const claimableRow = claimableQuery.data?.[i]
      const vestingHours = vesting && vesting.status === 'success' ? Number(vesting.result[0]) : 0
      const launchTime = vesting && vesting.status === 'success' ? Number(vesting.result[1]) : 0
      const claimable =
        claimableRow && claimableRow.status === 'success'
          ? claimableRow.result
          : mine && status === 1 && !mine[2]
            ? mine[1]
            : 0n
      result.push({
        id: i,
        creator,
        name,
        symbol,
        logoURI,
        supply,
        targetETH,
        raised,
        price,
        tradeFeeBps,
        status,
        token,
        deadline: Number(deadlineQuery.data?.[i] ?? 0n),
        vestingHours,
        launchTime,
        claimable,
        mine: mine
          ? { ethContributed: mine[0], tokensAllocated: mine[1], claimed: mine[2], refunded: mine[3] }
          : undefined,
      })
    })
    return result.reverse()
  }, [dataQuery.data, mineQuery.data, deadlineQuery.data, vestingQuery.data, claimableQuery.data])

  const isLoading = enabled && (countQuery.isLoading || (count > 0 && dataQuery.isLoading))
  return { fundraises, isLoading, enabled, count }
}
