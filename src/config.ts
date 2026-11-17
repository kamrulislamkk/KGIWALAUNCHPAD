/**
 * wagmi configuration
 * Built with Arc Studio — https://studio.arc.io
 */

import { http, createConfig } from 'wagmi'
import { injected } from 'wagmi/connectors'
import { giwaSepolia, GIWA_FAUCET_URL } from './chains'
import { registerChain } from './tracing'

export { giwaSepolia, GIWA_FAUCET_URL }

// Pre-register chain RPC URLs so trace events show correct chain names immediately
registerChain(giwaSepolia.id, giwaSepolia.rpcUrls.default.http[0])

export const config = createConfig({
  chains: [giwaSepolia],
  connectors: [injected()],
  transports: {
    [giwaSepolia.id]: http(),
  },
})
