import { ConnectKitButton } from 'connectkit'
import { Loader2 } from 'lucide-react'
import { clsx } from 'clsx'
import { useAccount } from 'wagmi'
import { giwaSepolia } from '@/config'
import type { TxStatus } from '@/hooks/useTx'

interface Props {
  label: string
  onClick: () => void | Promise<void>
  status: TxStatus
  disabled?: boolean
  variant?: 'primary' | 'danger' | 'ghost'
  className?: string
}

const BUSY_LABEL: Record<Exclude<TxStatus, 'idle'>, string> = {
  switching: `Switching to ${giwaSepolia.name}...`,
  signing: 'Confirm in wallet...',
  confirming: 'Confirming...',
}

/** One primary CTA that covers connect, busy, and ready states from real wallet and chain status. */
export function ActionButton({ label, onClick, status, disabled, variant = 'primary', className }: Props) {
  const { isConnected } = useAccount()
  const base =
    'flex min-h-12 w-full items-center justify-center gap-2 rounded-2xl px-4 text-sm font-semibold transition-all active:scale-[0.99] disabled:cursor-not-allowed disabled:opacity-40'
  const tone =
    variant === 'primary'
      ? 'bg-accent text-bg hover:bg-accent-hover'
      : variant === 'danger'
        ? 'bg-danger text-bg hover:opacity-90'
        : 'glass text-ink hover:bg-surface-strong'

  if (!isConnected) {
    return (
      <ConnectKitButton.Custom>
        {({ show, isConnecting }) => (
          <button type="button" onClick={show} className={clsx(base, tone, className)}>
            {isConnecting ? <Loader2 className="size-4 animate-spin" /> : null}
            Connect wallet
          </button>
        )}
      </ConnectKitButton.Custom>
    )
  }

  const busy = status !== 'idle'
  return (
    <button type="button" onClick={() => void onClick()} disabled={disabled || busy} className={clsx(base, tone, className)}>
      {busy ? (
        <>
          <Loader2 className="size-4 animate-spin" />
          {BUSY_LABEL[status]}
        </>
      ) : (
        label
      )}
    </button>
  )
}
