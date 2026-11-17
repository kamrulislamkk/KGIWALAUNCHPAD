import { useQuery } from '@tanstack/react-query'
import { toFunctionSelector, type Hex } from 'viem'
import { usePublicClient } from 'wagmi'
import { giwaSepolia } from '@/config'
import { LAUNCHPAD_ADDRESS } from '@/contracts/launchpad'

const SELECTOR = toFunctionSelector(
  'createFundraiseVested(string,string,string,uint256,uint256,uint256,uint256)',
).slice(2)

/**
 * True when the deployed launchpad includes fundraise vesting (v2.2 or newer).
 * Checks the deployed bytecode for the function selector, so older deployments degrade to instant release.
 */
export function useVestingSupport() {
  const client = usePublicClient({ chainId: giwaSepolia.id })
  const query = useQuery({
    queryKey: ['vestingSupport', LAUNCHPAD_ADDRESS],
    enabled: Boolean(client && LAUNCHPAD_ADDRESS),
    staleTime: Infinity,
    queryFn: async () => {
      const code: Hex | undefined = await client?.getCode({ address: LAUNCHPAD_ADDRESS! })
      return Boolean(code?.toLowerCase().includes(SELECTOR.toLowerCase()))
    },
  })
  return { supported: query.data === true, isLoading: query.isLoading }
}
