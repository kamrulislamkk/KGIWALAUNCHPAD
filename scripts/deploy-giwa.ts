/**
 * Deploy KgiwaLaunchpad to GIWA Sepolia testnet with a throwaway testnet key.
 *
 * Usage:
 *   bun run deploy:giwa                 # deploy
 *   bun run deploy:giwa --dry-run       # show deployer, balance and gas estimate only
 *   bun run deploy:giwa --platform-wallet 0x...   # fee recipient (defaults to the deployer)
 *
 * The key is read from GIWA_DEPLOYER_PRIVATE_KEY in .env. Use a fresh wallet that only holds
 * testnet ETH. The key is never printed.
 */
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { createPublicClient, createWalletClient, formatEther, http, isAddress, type Hex } from 'viem'
import { privateKeyToAccount } from 'viem/accounts'
import { GIWA_FAUCET_URL, giwaSepolia } from '../src/chains'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const artifactPath = resolve(root, 'contracts/out/KgiwaLaunchpad.sol/KgiwaLaunchpad.json')
const metadataPath = resolve(root, 'contracts/contract-metadata/KgiwaLaunchpad.json')
const envPath = resolve(root, '.env')

const args = process.argv.slice(2)
const dryRun = args.includes('--dry-run')
const walletFlag = args.indexOf('--platform-wallet')
const platformWalletArg = walletFlag >= 0 ? args[walletFlag + 1] : undefined

function fail(message: string): never {
  console.error(`\nError: ${message}\n`)
  process.exit(1)
}

const rawKey = process.env.GIWA_DEPLOYER_PRIVATE_KEY?.trim()
if (!rawKey) fail('GIWA_DEPLOYER_PRIVATE_KEY is not set. Add a throwaway testnet key to .env (never paste it in chat).')
const privateKey = (rawKey.startsWith('0x') ? rawKey : `0x${rawKey}`) as Hex
if (!/^0x[0-9a-fA-F]{64}$/.test(privateKey)) fail('GIWA_DEPLOYER_PRIVATE_KEY is not a valid 32-byte hex key.')

if (!existsSync(artifactPath)) fail('Artifact missing. Run `bun run contracts:build` first.')
const artifact = JSON.parse(readFileSync(artifactPath, 'utf8')) as { abi: unknown[]; bytecode: { object: Hex } }
if (!artifact.bytecode?.object || artifact.bytecode.object === '0x') fail('Artifact has no bytecode. Rebuild the contracts.')

const account = privateKeyToAccount(privateKey)
const platformWallet = platformWalletArg ?? account.address
if (!isAddress(platformWallet)) fail('--platform-wallet must be a valid address.')

const publicClient = createPublicClient({ chain: giwaSepolia, transport: http() })
const walletClient = createWalletClient({ account, chain: giwaSepolia, transport: http() })

const chainId = await publicClient.getChainId()
if (chainId !== giwaSepolia.id) fail(`RPC reports chain ${chainId}, expected ${giwaSepolia.id}. Refusing to deploy.`)

const balance = await publicClient.getBalance({ address: account.address })
console.log(`Network:        ${giwaSepolia.name} (${chainId})`)
console.log(`Deployer:       ${account.address}`)
console.log(`Balance:        ${formatEther(balance)} ETH`)
console.log(`Owner:          ${account.address}`)
console.log(`Platform wallet: ${platformWallet}`)

if (balance === 0n) fail(`Deployer has no test ETH. Fund it from ${GIWA_FAUCET_URL} and retry.`)

const constructorArgs = [account.address, platformWallet] as const

const gas = await publicClient.estimateContractGas({
  abi: artifact.abi as never,
  bytecode: artifact.bytecode.object,
  account,
  args: constructorArgs,
} as never).catch(() => undefined)
console.log(gas ? `Gas estimate:   ${gas}` : 'Gas estimate:   unavailable (continuing)')

if (dryRun) {
  console.log('\nDry run only. Nothing was broadcast.')
  process.exit(0)
}

console.log('\nDeploying...')
const hash = await walletClient.deployContract({
  abi: artifact.abi as never,
  bytecode: artifact.bytecode.object,
  args: constructorArgs,
})
console.log(`Tx:             ${hash}`)

const receipt = await publicClient.waitForTransactionReceipt({ hash })
if (receipt.status !== 'success' || !receipt.contractAddress) fail(`Deployment failed (status ${receipt.status}).`)

const address = receipt.contractAddress
const explorer = giwaSepolia.blockExplorers.default.url
console.log(`\nDeployed:       ${address}`)
console.log(`Block:          ${receipt.blockNumber}`)
console.log(`Explorer:       ${explorer}/address/${address}`)

mkdirSync(dirname(metadataPath), { recursive: true })
writeFileSync(
  metadataPath,
  JSON.stringify(
    {
      name: 'KgiwaLaunchpad',
      contractAddress: address,
      network: 'GIWA-SEPOLIA',
      chainId,
      deployerAddress: account.address,
      platformWallet,
      txHash: hash,
      blockNumber: Number(receipt.blockNumber),
      constructorArgs: [...constructorArgs],
      contract_code_path: 'contracts/KgiwaLaunchpad.sol',
      contract_compiled_code_path: 'contracts/out/KgiwaLaunchpad.sol/KgiwaLaunchpad.json',
      contract_network_and_links: { 'GIWA-SEPOLIA': `${explorer}/address/${address}` },
    },
    null,
    2,
  ),
)

// Public values only (never the key). The frontend reads these at dev-server start.
const envText = existsSync(envPath) ? readFileSync(envPath, 'utf8') : ''
const lines = envText.split('\n').filter((l) => !l.startsWith('VITE_LAUNCHPAD_ADDRESS=') && !l.startsWith('VITE_LAUNCHPAD_DEPLOY_BLOCK='))
writeFileSync(envPath, lines.join('\n').replace(/\n*$/, '\n'))
appendFileSync(envPath, `VITE_LAUNCHPAD_ADDRESS=${address}\nVITE_LAUNCHPAD_DEPLOY_BLOCK=${receipt.blockNumber}\n`)
console.log('\nWrote VITE_LAUNCHPAD_ADDRESS and VITE_LAUNCHPAD_DEPLOY_BLOCK to .env. Restart the dev server to pick them up.')
