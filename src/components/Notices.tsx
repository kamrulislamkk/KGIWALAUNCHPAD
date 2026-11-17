import { AlertTriangle, ExternalLink } from 'lucide-react'
import { useAccount } from 'wagmi'
import { LAUNCHPAD_ADDRESS } from '@/contracts/launchpad'
import { giwaSepolia } from '@/config'

export function NotDeployedNotice() {
  return (
    <div className="glass mx-auto max-w-xl rounded-3xl p-6 text-center">
      <AlertTriangle className="mx-auto mb-3 size-7 text-accent" aria-hidden />
      <h2 className="display text-xl font-bold">Launchpad contract not deployed yet</h2>
      <p className="mt-2 text-sm text-muted">
        Tokens, trades and fundraises appear here once the contract is deployed to {giwaSepolia.name} and its address
        is set in <span className="mono text-xs">VITE_LAUNCHPAD_ADDRESS</span>.
      </p>
    </div>
  )
}

export function EmptyState({ title, body }: { title: string; body: string }) {
  return (
    <div className="glass rounded-3xl p-8 text-center">
      <h3 className="display text-lg font-bold">{title}</h3>
      <p className="mx-auto mt-1.5 max-w-sm text-sm text-muted">{body}</p>
    </div>
  )
}

export function CardSkeleton({ count = 6 }: { count?: number }) {
  return (
    <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3" aria-busy="true" aria-label="Loading">
      {Array.from({ length: count }, (_, i) => (
        <div key={i} className="glass h-36 animate-pulse rounded-3xl" />
      ))}
    </div>
  )
}

export function WrongNetworkBar() {
  const { isConnected, chainId } = useAccount()
  if (!isConnected || chainId === giwaSepolia.id) return null
  return (
    <div
      className="px-4 py-2 text-center text-xs font-medium text-danger"
      style={{ background: 'rgba(232, 109, 122, 0.15)' }}
    >
      Your wallet is on another network. Transactions will ask you to switch to {giwaSepolia.name}.
    </div>
  )
}

export function ContractLink({ label = 'Contract' }: { label?: string }) {
  if (!LAUNCHPAD_ADDRESS) return null
  return (
    <a
      href={`${giwaSepolia.blockExplorers.default.url}/address/${LAUNCHPAD_ADDRESS}`}
      target="_blank"
      rel="noopener noreferrer"
      className="inline-flex items-center gap-1 text-xs font-medium text-subtle hover:text-ink"
    >
      {label} <ExternalLink className="size-3" />
    </a>
  )
}
