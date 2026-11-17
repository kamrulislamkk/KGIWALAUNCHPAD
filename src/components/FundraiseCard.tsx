import { useState } from 'react'
import { useNow } from '@/hooks/useNow'
import { clsx } from 'clsx'
import { useAccount } from 'wagmi'
import { parseEther, type Address } from 'viem'
import { giwaSepolia } from '@/config'
import { FUNDRAISE_STATUS, LAUNCHPAD_ADDRESS, MIN_TRADE_ETH, launchpadAbi } from '@/contracts/launchpad'
import type { FundraiseView } from '@/hooks/useFundraises'
import { useTx } from '@/hooks/useTx'
import { fmtEth, fmtTokens, marketCap, parseEthInput, sanitizeDecimal, shortAddress } from '@/lib/format'
import { ActionButton } from './ActionButton'
import { TokenLogo } from './TokenLogo'

const STATUS_LABEL = ['Raising', 'Launched', 'Cancelled'] as const

function releaseLabel(hours: number): string {
  return hours === 0 ? 'Instant release' : `${hours}h hourly release`
}

function untilNext(secs: number): string {
  if (secs <= 0) return 'now'
  const m = Math.ceil(secs / 60)
  return m >= 60 ? `${Math.floor(m / 60)}h ${m % 60}m` : `${m}m`
}

function daysLeft(deadline: number, now: number): string {
  const secs = deadline - now
  if (secs <= 0) return 'Expired'
  const days = Math.floor(secs / 86_400)
  if (days >= 1) return `${days}d left`
  return `${Math.max(1, Math.floor(secs / 3600))}h left`
}

interface Props {
  fundraise: FundraiseView
  onTrade: (token: Address) => void
}

export function FundraiseCard({ fundraise: f, onTrade }: Props) {
  const { address: account } = useAccount()
  const { run, status, error } = useTx()
  const [amount, setAmount] = useState('')

  const now = useNow()
  const expired = f.status === FUNDRAISE_STATUS.Active && f.deadline > 0 && now > f.deadline
  const isCreator = account !== undefined && account.toLowerCase() === f.creator.toLowerCase()
  const pct = f.targetETH > 0n ? Number((f.raised * 10_000n) / f.targetETH) / 100 : 0
  const remaining = f.targetETH - f.raised
  const parsed = amount ? parseEthInput(amount) : undefined
  const minBuy = parseEther(MIN_TRADE_ETH)
  const accepted = parsed !== undefined && parsed > remaining ? remaining : parsed
  const estTokens = accepted !== undefined && f.price > 0n ? (accepted * 10n ** 18n) / f.price : undefined
  const problem =
    parsed === undefined || parsed === 0n
      ? 'Enter an amount'
      : parsed < minBuy
        ? `Minimum is ${MIN_TRADE_ETH} ETH`
        : undefined

  const lp = LAUNCHPAD_ADDRESS as Address

  const write = (label: string, fn: 'cancelFundraise' | 'claim' | 'refund') =>
    run(label, (w) =>
      w({ address: lp, abi: launchpadAbi, functionName: fn, args: [BigInt(f.id)], chainId: giwaSepolia.id }),
    )

  const contribute = async () => {
    if (problem || parsed === undefined) return
    const ok = await run('Contribution', (w) =>
      w({
        address: lp,
        abi: launchpadAbi,
        functionName: 'contribute',
        args: [BigInt(f.id)],
        value: parsed,
        chainId: giwaSepolia.id,
      }),
    )
    if (ok) setAmount('')
  }

  const mine = f.mine
  const launched = f.status === FUNDRAISE_STATUS.Launched
  const hasPosition = launched && mine !== undefined && mine.tokensAllocated > 0n
  const canClaim = hasPosition && !mine.claimed && f.claimable > 0n
  const vested = f.vestingHours > 0 && f.launchTime > 0
  const unlockedHours = vested ? Math.min(f.vestingHours, Math.max(0, Math.floor((now - f.launchTime) / 3600))) : 0
  const nextUnlock = vested && unlockedHours < f.vestingHours ? f.launchTime + (unlockedHours + 1) * 3600 - now : 0
  const canRefund = (f.status === FUNDRAISE_STATUS.Cancelled || expired) && mine && !mine.refunded && mine.ethContributed > 0n

  return (
    <article className="glass flex flex-col gap-4 rounded-3xl p-4 sm:p-5">
      <div className="flex items-center gap-3">
        <TokenLogo logoURI={f.logoURI} symbol={f.symbol} size={48} />
        <div className="min-w-0 flex-1">
          <h3 className="display truncate text-lg font-bold">{f.name}</h3>
          <div className="flex items-center gap-2 text-xs text-subtle">
            <span className="font-semibold uppercase tracking-wide">{f.symbol}</span>
            <span aria-hidden>·</span>
            <span className="mono">by {shortAddress(f.creator)}</span>
          </div>
        </div>
        <span
          className={clsx(
            'rounded-full px-2.5 py-1 text-[10px] font-bold uppercase tracking-wider',
            f.status === FUNDRAISE_STATUS.Active && !expired && 'bg-surface-strong text-accent',
            f.status === FUNDRAISE_STATUS.Launched && 'text-success',
            (f.status === FUNDRAISE_STATUS.Cancelled || expired) && 'text-danger',
          )}
          style={f.status !== FUNDRAISE_STATUS.Active || expired ? { background: 'rgba(255,255,255,0.07)' } : undefined}
        >
          {expired ? 'Expired' : (STATUS_LABEL[f.status] ?? 'Unknown')}
        </span>
      </div>

      <div>
        <div className="mb-1.5 flex items-baseline justify-between text-sm">
          <span className="display text-xl font-bold tabular-nums">
            {fmtEth(f.raised)} <span className="text-sm font-medium text-subtle">/ {fmtEth(f.targetETH)} ETH</span>
          </span>
          <span className="tabular-nums text-subtle">{pct.toFixed(1)}%</span>
        </div>
        <div
          className="h-2 overflow-hidden rounded-full"
          style={{ background: 'rgba(255,255,255,0.08)' }}
          role="progressbar"
          aria-valuenow={Math.round(pct)}
          aria-valuemin={0}
          aria-valuemax={100}
          aria-label="Fundraise progress"
        >
          <div className="h-full rounded-full bg-accent" style={{ width: `${Math.min(100, pct)}%` }} />
        </div>
        <div className="mt-2 flex justify-between text-xs text-subtle">
          <span>Market cap now {fmtEth(marketCap(f.price, f.supply))} ETH</span>
          <span>{f.status === FUNDRAISE_STATUS.Active ? daysLeft(f.deadline, now) : `Supply ${fmtTokens(f.supply)}`}</span>
        </div>
        <div className="mt-1 text-xs text-subtle">Tokens: {releaseLabel(f.vestingHours)}</div>
      </div>

      {mine && mine.ethContributed > 0n && (
        <div className="glass-inner rounded-2xl px-3.5 py-2.5 text-sm">
          You contributed <span className="font-semibold tabular-nums">{fmtEth(mine.ethContributed)} ETH</span> for{' '}
          <span className="font-semibold tabular-nums">{fmtTokens(mine.tokensAllocated)} {f.symbol}</span>
          {mine.claimed && <span className="text-success"> (claimed)</span>}
          {mine.refunded && <span className="text-subtle"> (refunded)</span>}
        </div>
      )}

      {f.status === FUNDRAISE_STATUS.Active && !expired && (
        <div className="space-y-3">
          <div className="glass-inner flex items-center gap-2 rounded-xl px-3.5">
            <input
              inputMode="decimal"
              value={amount}
              onChange={(e) => setAmount(sanitizeDecimal(e.target.value))}
              placeholder="0.0"
              aria-label={`ETH to contribute to ${f.name}`}
              className="min-h-11 w-full bg-transparent text-sm tabular-nums outline-none"
            />
            <span className="text-xs font-semibold text-subtle">ETH</span>
          </div>
          {estTokens !== undefined && estTokens > 0n && (
            <p className="text-xs text-subtle">
              You receive about {fmtTokens(estTokens)} {f.symbol} when it launches
              {parsed !== undefined && parsed > remaining && ' (extra above the target is returned)'}.
            </p>
          )}
          <ActionButton label={problem ?? 'Contribute'} onClick={contribute} status={status} disabled={Boolean(problem)} />
          {isCreator && (
            <ActionButton
              label="Cancel fundraise"
              variant="ghost"
              onClick={() => void write('Cancel', 'cancelFundraise')}
              status={status}
            />
          )}
        </div>
      )}

      {launched && (
        <div className="space-y-2">
          {hasPosition && f.vestingHours > 0 && (
            <div className="glass-inner space-y-2 rounded-2xl px-3.5 py-3 text-sm">
              <div className="flex justify-between text-xs text-subtle">
                <span>
                  Unlocked {unlockedHours}/{f.vestingHours} hours
                </span>
                <span>{unlockedHours >= f.vestingHours ? 'Fully unlocked' : `Next unlock in ${untilNext(nextUnlock)}`}</span>
              </div>
              <div
                className="h-1.5 overflow-hidden rounded-full"
                style={{ background: 'rgba(255,255,255,0.08)' }}
                role="progressbar"
                aria-valuenow={unlockedHours}
                aria-valuemin={0}
                aria-valuemax={f.vestingHours}
                aria-label="Vesting progress"
              >
                <div
                  className="h-full rounded-full bg-accent"
                  style={{ width: `${(unlockedHours / f.vestingHours) * 100}%` }}
                />
              </div>
              <div className="flex justify-between">
                <span className="text-subtle">Claimable now</span>
                <span className="font-semibold tabular-nums">
                  {fmtTokens(f.claimable)} {f.symbol}
                </span>
              </div>
            </div>
          )}
          {hasPosition && !mine.claimed && (
            <ActionButton
              label={canClaim ? `Claim ${fmtTokens(f.claimable)} ${f.symbol}` : 'Nothing to claim yet'}
              onClick={() => void write('Claim', 'claim')}
              status={status}
              disabled={!canClaim}
            />
          )}
          <ActionButton label="Trade token" variant={canClaim ? 'ghost' : 'primary'} onClick={() => onTrade(f.token)} status="idle" />
        </div>
      )}

      {(f.status === FUNDRAISE_STATUS.Cancelled || expired) && (
        <div>
          {canRefund ? (
            <ActionButton label={`Refund ${fmtEth(mine.ethContributed)} ETH`} onClick={() => void write('Refund', 'refund')} status={status} />
          ) : (
            <p className="text-center text-xs text-subtle">{expired ? 'This fundraise expired before reaching its target.' : 'This fundraise was cancelled by its creator.'}</p>
          )}
        </div>
      )}

      {error && <p className="text-center text-xs text-danger">{error}</p>}
    </article>
  )
}
