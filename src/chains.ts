import { defineChain } from 'viem'

// GIWA Sepolia testnet (OP Stack L2 on Ethereum Sepolia). Values from docs.giwa.io.
export const giwaSepolia = defineChain({
  id: 91342,
  name: 'GIWA Sepolia',
  nativeCurrency: { name: 'Ether', symbol: 'ETH', decimals: 18 },
  rpcUrls: { default: { http: ['https://sepolia-rpc.giwa.io'] } },
  blockExplorers: {
    default: { name: 'GIWA Explorer', url: 'https://sepolia-explorer.giwa.io' },
  },
  testnet: true,
})

export const GIWA_FAUCET_URL = 'https://faucet.giwa.io'
