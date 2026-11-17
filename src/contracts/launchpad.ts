import { erc20Abi, isAddress, type Address } from 'viem'
import { launchpadAbi } from './launchpadAbi'

/**
 * Deployed launchpad address and the block it was deployed at.
 * Both come from .env (VITE_LAUNCHPAD_ADDRESS, VITE_LAUNCHPAD_DEPLOY_BLOCK) after deployment.
 */
const rawAddress = String(import.meta.env.VITE_LAUNCHPAD_ADDRESS ?? '')
const rawBlock = String(import.meta.env.VITE_LAUNCHPAD_DEPLOY_BLOCK ?? '')

export const LAUNCHPAD_ADDRESS: Address | undefined = isAddress(rawAddress) ? rawAddress : undefined
export const LAUNCHPAD_DEPLOY_BLOCK: bigint | undefined = /^\d+$/.test(rawBlock) ? BigInt(rawBlock) : undefined

/** Default fees shown in the UI. The contract's own getters are the source of truth. */
export const CREATION_FEE_LABEL = '0.0001'
export const FUNDRAISE_FEE_LABEL = '0.05'

/** Fundraise targets must stay within this range (enforced by the contract). */
export const MIN_FUNDRAISE_TARGET = '0.01'
export const MAX_FUNDRAISE_TARGET = '50'
export const FUNDRAISE_DAYS = 30

/** Smallest buy or contribution accepted by the contract. */
export const MIN_TRADE_ETH = '0.00001'

/** Fixed token economics (match the contract). */
export const TOTAL_SUPPLY = 1_000_000_000n * 10n ** 18n
export const CURVE_SUPPLY = 800_000_000n * 10n ** 18n
export const LOCKED_SUPPLY = 200_000_000n * 10n ** 18n
export const START_PRICE_ETH = '0.00000025'

/** Creator-selectable trade fee options in basis points (contract allows 100 to 300). */
export const FEE_OPTIONS_BPS = [100, 200, 300] as const

/** Token release choices for a fundraise: 0 = instant, otherwise hourly steps over N hours. */
export const VESTING_OPTIONS = [
  { hours: 0, label: 'Instant', hint: 'Claim everything as soon as it launches' },
  { hours: 24, label: '24 hours', hint: '1/24 unlocks every hour' },
  { hours: 48, label: '48 hours', hint: '1/48 unlocks every hour' },
] as const

export const FUNDRAISE_STATUS = { Active: 0, Launched: 1, Cancelled: 2 } as const

export { launchpadAbi, erc20Abi }
