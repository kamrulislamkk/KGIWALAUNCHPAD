import { useCallback, useState } from 'react'
import { useAccount, usePublicClient, useSwitchChain, useWriteContract } from 'wagmi'
import { useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import type { Hash } from 'viem'
import { giwaSepolia } from '@/config'
import { isUserRejection, parseOnchainError } from '@/lib/errors'

export type TxStatus = 'idle' | 'switching' | 'signing' | 'confirming'
export type Writer = ReturnType<typeof useWriteContract>['writeContractAsync']

export function txUrl(hash: Hash): string {
  return `${giwaSepolia.blockExplorers.default.url}/tx/${hash}`
}

/**
 * Runs one contract write end to end: switch chain if needed, sign, wait for the receipt,
 * then refresh all reads. Status reflects real wallet and chain state only.
 */
export function useTx() {
  const { chainId, isConnected } = useAccount()
  const { switchChainAsync } = useSwitchChain()
  const { writeContractAsync } = useWriteContract()
  const publicClient = usePublicClient({ chainId: giwaSepolia.id })
  const queryClient = useQueryClient()
  const [status, setStatus] = useState<TxStatus>('idle')
  const [lastHash, setLastHash] = useState<Hash | undefined>()
  const [error, setError] = useState<string | undefined>()

  const run = useCallback(
    async (label: string, send: (write: Writer) => Promise<Hash>): Promise<boolean> => {
      if (!isConnected || !publicClient) return false
      setError(undefined)
      setLastHash(undefined)
      try {
        if (chainId !== giwaSepolia.id) {
          setStatus('switching')
          await switchChainAsync({ chainId: giwaSepolia.id })
        }
        setStatus('signing')
        const hash = await send(writeContractAsync)
        setLastHash(hash)
        setStatus('confirming')
        const receipt = await publicClient.waitForTransactionReceipt({ hash })
        if (receipt.status !== 'success') throw new Error('Transaction reverted onchain.')
        toast.success(`${label} confirmed`, {
          action: { label: 'View', onClick: () => window.open(txUrl(hash), '_blank', 'noopener,noreferrer') },
        })
        await queryClient.invalidateQueries()
        return true
      } catch (err) {
        if (!isUserRejection(err)) {
          const message = parseOnchainError(err)
          setError(message)
          toast.error(message)
        }
        return false
      } finally {
        setStatus('idle')
      }
    },
    [chainId, isConnected, publicClient, queryClient, switchChainAsync, writeContractAsync],
  )

  return { run, status, busy: status !== 'idle', lastHash, error, clearError: () => setError(undefined) }
}
