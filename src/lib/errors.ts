import { BaseError, ContractFunctionRevertedError } from 'viem'

const REVERT_MESSAGES: Record<string, string> = {
  LaunchpadPaused: 'The launchpad is paused right now.',
  InvalidMetadata: 'Name, symbol or logo is invalid.',
  InvalidSupply: 'Supply is fixed at 1 billion tokens.',
  InvalidFee: 'Trade fee must be between 1% and 3%.',
  InvalidPayment: 'The payment does not match the required fee.',
  InvalidTarget: 'Target must be between 0.01 and 50 ETH.',
  InvalidFundraise: 'That fundraise does not exist.',
  InvalidStatus: 'This fundraise is not in the right state for that action.',
  UnknownToken: 'That token is not on the launchpad.',
  TradeTooSmall: 'That amount is too small to trade.',
  InsufficientInventory: 'Not enough tokens left on the curve for that.',
  InsufficientReserve: 'The ETH reserve cannot pay for that sale right now.',
  InvalidVesting: 'Choose instant, 24 hour or 48 hour release.',
  FundraiseExpired: 'This fundraise has expired. Contributors can refund.',
  CurveMathError: 'The curve could not price that amount. Try a different size.',
  SlippageExceeded: 'Price moved. Raise your slippage and try again.',
  NothingToReceive: 'There is nothing to receive for that amount.',
  AlreadyProcessed: 'You already did that.',
  NotCreator: 'Only the creator can do that.',
  ETHTransferFailed: 'An ETH transfer failed.',
  TokenTransferFailed: 'A token transfer failed.',
  ERC20InsufficientAllowance: 'Approve the token first.',
  ERC20InsufficientBalance: 'You do not hold enough of that token.',
}

export function isUserRejection(error: unknown): boolean {
  const message = error instanceof Error ? error.message.toLowerCase() : ''
  const code = (error as { code?: number } | null)?.code
  return code === 4001 || message.includes('user rejected') || message.includes('user denied')
}

export function parseOnchainError(error: unknown): string {
  if (isUserRejection(error)) return 'Transaction cancelled.'
  if (error instanceof BaseError) {
    const reverted = error.walk((e) => e instanceof ContractFunctionRevertedError)
    if (reverted instanceof ContractFunctionRevertedError) {
      const name = reverted.data?.errorName
      if (name && REVERT_MESSAGES[name]) return REVERT_MESSAGES[name]
      if (name) return `Transaction failed: ${name}`
    }
    const text = error.shortMessage.toLowerCase()
    if (text.includes('insufficient funds')) {
      return 'Not enough test ETH for this amount plus gas. Use the faucet.'
    }
    if (text.includes('network') || text.includes('timeout') || text.includes('http request failed')) {
      return 'Network issue. Check your connection and retry.'
    }
    return error.shortMessage
  }
  return 'Something went wrong. Please try again.'
}
