import { useQuery } from '@tanstack/react-query'
import { usePublicClient } from 'wagmi'
import { getAbiItem } from 'viem'
import { giwaSepolia } from '@/config'
import { LAUNCHPAD_ADDRESS, LAUNCHPAD_DEPLOY_BLOCK, launchpadAbi } from '@/contracts/launchpad'

/** The public RPC is rate-limited, so scans look back a bounded number of blocks in windows. */
const MAX_LOOKBACK = 400_000n
const WINDOW = 50_000n

const events = [
  getAbiItem({ abi: launchpadAbi, name: 'Trade' }),
  getAbiItem({ abi: launchpadAbi, name: 'FeesDistributed' }),
  getAbiItem({ abi: launchpadAbi, name: 'TokenCreated' }),
  getAbiItem({ abi: launchpadAbi, name: 'FundraiseCreated' }),
  getAbiItem({ abi: launchpadAbi, name: 'FundraiseCompleted' }),
] as const

export interface TraderAggregate {
  trades: number
  buyVolume: bigint
  sellVolume: bigint
}

export interface AdminEventData {
  fromBlock: bigint
  head: bigint
  /** True when the scan could not reach the deploy block, so older activity is not counted. */
  truncated: boolean
  platformTradeFees: bigint
  instantLaunches: number
  fundraiseCreationFees: bigint
  fundraisesCreated: number
  /** Keyed by lowercase trader address. */
  traders: Map<string, TraderAggregate>
}

/** One bounded scan of launchpad events, shared by the fee totals and the trader table. */
export function useAdminEvents(enabled: boolean) {
  const client = usePublicClient({ chainId: giwaSepolia.id })

  return useQuery({
    queryKey: ['admin-events', LAUNCHPAD_ADDRESS],
    enabled: enabled && Boolean(client && LAUNCHPAD_ADDRESS),
    refetchInterval: 60_000,
    staleTime: 30_000,
    queryFn: async (): Promise<AdminEventData> => {
      if (!client || !LAUNCHPAD_ADDRESS) throw new Error('Launchpad not configured')
      const head = await client.getBlockNumber()
      const floor = head > MAX_LOOKBACK ? head - MAX_LOOKBACK : 0n
      const deploy = LAUNCHPAD_DEPLOY_BLOCK ?? floor
      const fromBlock = deploy > floor ? deploy : floor
      const truncated = fromBlock > deploy

      let platformTradeFees = 0n
      let tokenCreated = 0
      let fundraiseCompleted = 0
      let fundraisesCreated = 0
      const fundraiseTxs: `0x${string}`[] = []
      const traders = new Map<string, TraderAggregate>()

      for (let from = fromBlock; from <= head; from += WINDOW) {
        const to = from + WINDOW - 1n > head ? head : from + WINDOW - 1n
        const logs = await client.getLogs({ address: LAUNCHPAD_ADDRESS, events, strict: true, fromBlock: from, toBlock: to })
        for (const log of logs) {
          switch (log.eventName) {
            case 'Trade': {
              const key = log.args.trader.toLowerCase()
              const row = traders.get(key) ?? { trades: 0, buyVolume: 0n, sellVolume: 0n }
              row.trades += 1
              if (log.args.isBuy) row.buyVolume += log.args.ethAmount
              else row.sellVolume += log.args.ethAmount
              traders.set(key, row)
              break
            }
            case 'FeesDistributed':
              platformTradeFees += log.args.platform
              break
            case 'TokenCreated':
              tokenCreated += 1
              break
            case 'FundraiseCompleted':
              fundraiseCompleted += 1
              break
            case 'FundraiseCreated':
              fundraisesCreated += 1
              fundraiseTxs.push(log.transactionHash)
              break
          }
        }
      }

      // The fundraise creation fee is paid as the exact ETH value of the creating transaction.
      let fundraiseCreationFees = 0n
      for (const hash of fundraiseTxs) {
        const tx = await client.getTransaction({ hash })
        fundraiseCreationFees += tx.value
      }

      // TokenCreated is emitted for instant launches and for completed fundraises; subtract the latter.
      return {
        fromBlock,
        head,
        truncated,
        platformTradeFees,
        instantLaunches: Math.max(0, tokenCreated - fundraiseCompleted),
        fundraiseCreationFees,
        fundraisesCreated,
        traders,
      }
    },
  })
}
