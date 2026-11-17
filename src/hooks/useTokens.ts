import { useMemo } from 'react'
import { useReadContract, useReadContracts } from 'wagmi'
import { erc20Abi, zeroAddress, type Address } from 'viem'
import { giwaSepolia } from '@/config'
import { LAUNCHPAD_ADDRESS, launchpadAbi } from '@/contracts/launchpad'
import { marketCap } from '@/lib/format'

const chainId = giwaSepolia.id
const LP = LAUNCHPAD_ADDRESS ?? zeroAddress

export interface TokenView {
  address: Address
  creator: Address
  supply: bigint
  price: bigint
  curveInventory: bigint
  reserveETH: bigint
  volume: bigint
  tradeFeeBps: bigint
  launched: boolean
  name: string
  symbol: string
  logoURI: string
  marketCap: bigint
}

export function useTokens() {
  const enabled = Boolean(LAUNCHPAD_ADDRESS)

  const countQuery = useReadContract({
    address: LP,
    abi: launchpadAbi,
    functionName: 'tokenCount',
    chainId,
    query: { enabled, refetchInterval: 12_000 },
  })
  const count = countQuery.data === undefined ? 0 : Number(countQuery.data)

  const addressQuery = useReadContracts({
    allowFailure: false,
    contracts: Array.from({ length: count }, (_, i) => ({
      address: LP,
      abi: launchpadAbi,
      functionName: 'tokenAt' as const,
      args: [BigInt(i)] as const,
      chainId,
    })),
    query: { enabled: enabled && count > 0 },
  })
  const addresses = useMemo(() => [...(addressQuery.data ?? [])] as Address[], [addressQuery.data])
  const hasTokens = addresses.length > 0

  const infoQuery = useReadContracts({
    allowFailure: false,
    contracts: addresses.map((a) => ({
      address: LP,
      abi: launchpadAbi,
      functionName: 'tokens' as const,
      args: [a] as const,
      chainId,
    })),
    query: { enabled: hasTokens, refetchInterval: 10_000 },
  })
  const nameQuery = useReadContracts({
    allowFailure: false,
    contracts: addresses.map((a) => ({ address: a, abi: erc20Abi, functionName: 'name' as const, chainId })),
    query: { enabled: hasTokens, staleTime: Infinity },
  })
  const symbolQuery = useReadContracts({
    allowFailure: false,
    contracts: addresses.map((a) => ({ address: a, abi: erc20Abi, functionName: 'symbol' as const, chainId })),
    query: { enabled: hasTokens, staleTime: Infinity },
  })
  const logoQuery = useReadContracts({
    allowFailure: false,
    contracts: addresses.map((a) => ({
      address: LP,
      abi: launchpadAbi,
      functionName: 'tokenLogoURI' as const,
      args: [a] as const,
      chainId,
    })),
    query: { enabled: hasTokens, staleTime: Infinity },
  })

  const tokens = useMemo<TokenView[]>(() => {
    const infos = infoQuery.data
    const names = nameQuery.data
    const symbols = symbolQuery.data
    const logos = logoQuery.data
    if (!infos || !names || !symbols || !logos) return []
    const result: TokenView[] = []
    addresses.forEach((address, i) => {
      const info = infos[i]
      if (!info) return
      const [creator, supply, price, curveInventory, reserveETH, volume, tradeFeeBps, launched] = info
      result.push({
        address,
        creator,
        supply,
        price,
        curveInventory,
        reserveETH,
        volume,
        tradeFeeBps,
        launched,
        name: names[i] ?? '',
        symbol: symbols[i] ?? '',
        logoURI: logos[i] ?? '',
        marketCap: marketCap(price, supply),
      })
    })
    // Newest first
    return result.reverse()
  }, [addresses, infoQuery.data, nameQuery.data, symbolQuery.data, logoQuery.data])

  const isLoading = enabled && (countQuery.isLoading || (hasTokens && tokens.length === 0))
  return { tokens, isLoading, enabled, count }
}
