import { formatEther, formatUnits, parseEther } from 'viem'

/** Plain decimal string for a wei amount (never scientific), keeping `sig` significant digits for tiny values. */
function plainDecimal(wei: bigint, sig: number): string {
  if (wei === 0n) return '0'
  const [int, frac = ''] = formatEther(wei).split('.')
  if (int !== '0') {
    const kept = frac.slice(0, 4).replace(/0+$/, '')
    return kept ? `${int}.${kept}` : int
  }
  const leadingZeros = /^0*/.exec(frac)?.[0].length ?? 0
  const kept = frac.slice(0, leadingZeros + sig).replace(/0+$/, '')
  return kept ? `0.${kept}` : '0'
}

export function shortAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`
}

/** Format a wei amount as ETH with sensible precision (more decimals for small values). */
export function fmtEth(wei: bigint, maxDecimals = 6): string {
  const value = Number(formatEther(wei))
  if (value === 0) return '0'
  if (value >= 1000) return value.toLocaleString('en-US', { maximumFractionDigits: 2 })
  if (value >= 1) return value.toLocaleString('en-US', { maximumFractionDigits: 4 })
  if (value >= 0.0001) return value.toLocaleString('en-US', { maximumFractionDigits: maxDecimals })
  return plainDecimal(wei, 3)
}

/** Format a per-token price in wei (wei per whole token) as a compact ETH string. */
export function fmtPrice(priceWei: bigint): string {
  const value = Number(formatEther(priceWei))
  if (value === 0) return '0'
  if (value >= 0.01) return value.toLocaleString('en-US', { maximumFractionDigits: 4 })
  return plainDecimal(priceWei, 4)
}

/** Compact token amount (18 decimals): 1.2M, 340K, 12.5 */
export function fmtTokens(raw: bigint, decimals = 18): string {
  const value = Number(formatUnits(raw, decimals))
  if (value === 0) return '0'
  return new Intl.NumberFormat('en-US', {
    notation: value >= 10_000 ? 'compact' : 'standard',
    maximumFractionDigits: value >= 100 ? 1 : 4,
  }).format(value)
}

/** Launch price: 5 ETH virtual liquidity over 20M virtual tokens = 0.00000025 ETH (wei per whole token). */
export function launchPrice(): bigint {
  return 250_000_000_000n
}

export function marketCap(priceWei: bigint, supply: bigint): bigint {
  return (priceWei * supply) / 10n ** 18n
}

/** Percent change of a price against the launch price, as a number (e.g. 15.2). */
export function pctChange(current: bigint, base: bigint): number {
  if (base === 0n) return 0
  return (Number(current - base) / Number(base)) * 100
}

/** Parse a decimal ETH input safely; returns undefined for empty or invalid input. */
export function parseEthInput(input: string): bigint | undefined {
  const trimmed = input.trim()
  if (!/^\d*\.?\d+$|^\d+\.$/.test(trimmed)) return undefined
  try {
    return parseEther(trimmed.endsWith('.') ? trimmed.slice(0, -1) : trimmed)
  } catch {
    return undefined
  }
}

/** Parse a whole-token decimal input into 18-decimal raw units. */
export function parseTokenInput(input: string): bigint | undefined {
  return parseEthInput(input)
}

export function sanitizeDecimal(value: string): string {
  const cleaned = value.replace(/[^0-9.]/g, '')
  const [head, ...rest] = cleaned.split('.')
  return rest.length > 0 ? `${head}.${rest.join('')}` : head
}

export function timeAgo(ms: number): string {
  const seconds = Math.max(0, Math.floor((Date.now() - ms) / 1000))
  if (seconds < 60) return `${seconds}s ago`
  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}m ago`
  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}h ago`
  return `${Math.floor(hours / 24)}d ago`
}
