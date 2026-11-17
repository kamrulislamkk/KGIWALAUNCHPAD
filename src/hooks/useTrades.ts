import { useQuery } from '@tanstack/react-query'
import { usePublicClient } from 'wagmi'
import { getAbiItem, type Address, type Hash } from 'viem'
import { giwaSepolia } from '@/config'
import { LAUNCHPAD_ADDRESS, LAUNCHPAD_DEPLOY_BLOCK, launchpadAbi } from '@/contracts/launchpad'

const tradeEvent = getAbiItem({ abi: launchpadAbi, name: 'Trade' })

/** How far back we scan, and how many blocks per request (the public RPC is rate-limited). */
const MAX_LOOKBACK = 300_000n
const WINDOW = 50_000n
const TIMESTAMPED_TRADES = 30

export interface TradeView {
  token: Address
  trader: Address
  isBuy: boolean
  ethAmount: bigint
  tokenAmount: bigint
  fee: bigint
  newPrice: bigint
  blockNumber: bigint
  logIndex: number
  txHash: Hash
  timestamp?: number
}

/** Recent Trade events, newest first. Pass a token to filter to that token. */
export function useTrades(token?: Address, limit = 50) {
  const client = usePublicClient({ chainId: giwaSepolia.id })

  return useQuery({
    queryKey: ['trades', LAUNCHPAD_ADDRESS, token, limit],
    enabled: Boolean(client && LAUNCHPAD_ADDRESS),
    refetchInterval: 30_000,
    queryFn: async (): Promise<TradeView[]> => {
      if (!client || !LAUNCHPAD_ADDRESS) return []
      const head = await client.getBlockNumber()
      let start = head > MAX_LOOKBACK ? head - MAX_LOOKBACK : 0n
      if (LAUNCHPAD_DEPLOY_BLOCK !== undefined && LAUNCHPAD_DEPLOY_BLOCK > start) start = LAUNCHPAD_DEPLOY_BLOCK

      const trades: TradeView[] = []
      for (let from = start; from <= head; from += WINDOW) {
        const to = from + WINDOW - 1n > head ? head : from + WINDOW - 1n
        const logs = await client.getLogs({
          address: LAUNCHPAD_ADDRESS,
          event: tradeEvent,
          strict: true,
          args: token ? { token } : undefined,
          fromBlock: from,
          toBlock: to,
        })
        for (const log of logs) {
          trades.push({
            token: log.args.token,
            trader: log.args.trader,
            isBuy: log.args.isBuy,
            ethAmount: log.args.ethAmount,
            tokenAmount: log.args.tokenAmount,
            fee: log.args.fee,
            newPrice: log.args.newPrice,
            blockNumber: log.blockNumber,
            logIndex: log.logIndex,
            txHash: log.transactionHash,
          })
        }
      }

      trades.sort((a, b) =>
        a.blockNumber === b.blockNumber ? b.logIndex - a.logIndex : Number(b.blockNumber - a.blockNumber),
      )
      const recent = trades.slice(0, limit)

      // Attach timestamps to the newest trades only, one request per unique block.
      const blocks = [...new Set(recent.slice(0, TIMESTAMPED_TRADES).map((t) => t.blockNumber))]
      const stamps = new Map<bigint, number>()
      await Promise.all(
        blocks.map(async (blockNumber) => {
          const block = await client.getBlock({ blockNumber })
          stamps.set(blockNumber, Number(block.timestamp) * 1000)
        }),
      )
      return recent.map((t) => ({ ...t, timestamp: stamps.get(t.blockNumber) }))
    },
  })
}
