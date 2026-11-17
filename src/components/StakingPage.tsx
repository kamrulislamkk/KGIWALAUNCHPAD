import { Lock } from 'lucide-react'

export function StakingPage() {
  return (
    <div className="glass mx-auto flex max-w-lg flex-col items-center gap-3 rounded-3xl p-12 text-center">
      <div className="flex size-14 items-center justify-center rounded-2xl bg-surface-strong">
        <Lock className="size-6 text-accent" aria-hidden />
      </div>
      <h1 className="display text-2xl font-bold">Staking is coming soon</h1>
      <p className="max-w-sm text-sm text-muted">
        Stake the tokens you hold to earn rewards. We will announce it here when it goes live.
      </p>
    </div>
  )
}
