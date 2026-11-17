import { useAccount, useBalance, useReadContract, useReadContracts } from 'wagmi'
import { zeroAddress } from 'viem'
import { giwaSepolia } from '@/config'
import { LAUNCHPAD_ADDRESS, launchpadAbi } from '@/contracts/launchpad'

const chainId = giwaSepolia.id
const LP = LAUNCHPAD_ADDRESS ?? zeroAddress

/** True when the connected wallet is the launchpad owner. Used to show the Admin tab. */
export function useIsOwner() {
  const { address } = useAccount()
  const owner = useReadContract({
    address: LP,
    abi: launchpadAbi,
    functionName: 'owner',
    chainId,
    query: { enabled: Boolean(LAUNCHPAD_ADDRESS), staleTime: 60_000 },
  })
  const isOwner = Boolean(address && owner.data && address.toLowerCase() === owner.data.toLowerCase())
  return { owner: owner.data, isOwner, isLoading: owner.isLoading }
}

/** Owner-facing settings and totals, all read live from the contract. */
export function useAdmin() {
  const enabled = Boolean(LAUNCHPAD_ADDRESS)
  const reads = useReadContracts({
    allowFailure: false,
    contracts: [
      { address: LP, abi: launchpadAbi, functionName: 'platformWallet', chainId },
      { address: LP, abi: launchpadAbi, functionName: 'fundraiseCreationFee', chainId },
      { address: LP, abi: launchpadAbi, functionName: 'instantCreationFee', chainId },
      { address: LP, abi: launchpadAbi, functionName: 'totalVolume', chainId },
      { address: LP, abi: launchpadAbi, functionName: 'traderCount', chainId },
      { address: LP, abi: launchpadAbi, functionName: 'paused', chainId },
    ],
    query: { enabled, refetchInterval: 20_000 },
  })

  const treasury = reads.data?.[0]
  const treasuryBalance = useBalance({
    address: treasury,
    chainId,
    query: { enabled: Boolean(treasury), refetchInterval: 20_000 },
  })

  return {
    treasury,
    treasuryBalance: treasuryBalance.data?.value,
    fundraiseFee: reads.data?.[1],
    instantFee: reads.data?.[2],
    totalVolume: reads.data?.[3],
    traderCount: reads.data ? Number(reads.data[4]) : undefined,
    paused: reads.data?.[5],
    isLoading: reads.isLoading,
  }
}
