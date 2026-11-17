import { useState } from 'react'
import { useAccount, useBalance, useReadContract } from 'wagmi'
import { parseEther, zeroAddress } from 'viem'
import { giwaSepolia } from '@/config'
import {
  FUNDRAISE_DAYS,
  FUNDRAISE_FEE_LABEL,
  LAUNCHPAD_ADDRESS,
  MAX_FUNDRAISE_TARGET,
  MIN_FUNDRAISE_TARGET,
  VESTING_OPTIONS,
  launchpadAbi,
} from '@/contracts/launchpad'
import { useTx } from '@/hooks/useTx'
import { useVestingSupport } from '@/hooks/useVestingSupport'
import { fmtEth, parseEthInput, sanitizeDecimal } from '@/lib/format'
import { ActionButton } from './ActionButton'
import {
  INITIAL_TOKEN_FORM,
  TokenFields,
  fixedSupply,
  validateTokenForm,
  type TokenFormState,
} from './TokenFields'

const TARGET_PRESETS = ['0.1', '1', '5', '10', '50']

export function CreateFundraise({ onCreated }: { onCreated: () => void }) {
  const { address: account } = useAccount()
  const { run, status, error } = useTx()
  const [form, setForm] = useState<TokenFormState>(INITIAL_TOKEN_FORM)
  const [target, setTarget] = useState('')
  const [vestingHours, setVestingHours] = useState<number>(0)
  const { supported: vestingSupported } = useVestingSupport()

  const feeQuery = useReadContract({
    address: LAUNCHPAD_ADDRESS ?? zeroAddress,
    abi: launchpadAbi,
    functionName: 'fundraiseCreationFee',
    chainId: giwaSepolia.id,
    query: { enabled: Boolean(LAUNCHPAD_ADDRESS) },
  })
  const balance = useBalance({ address: account, chainId: giwaSepolia.id, query: { enabled: Boolean(account) } })

  const fee = feeQuery.data ?? parseEther(FUNDRAISE_FEE_LABEL)
  const targetWei = parseEthInput(target)
  const min = parseEther(MIN_FUNDRAISE_TARGET)
  const max = parseEther(MAX_FUNDRAISE_TARGET)

  const problem =
    validateTokenForm(form) ??
    (targetWei === undefined
      ? 'Enter a target amount'
      : targetWei < min || targetWei > max
        ? `Target must be ${MIN_FUNDRAISE_TARGET} to ${MAX_FUNDRAISE_TARGET} ETH`
        : balance.data && fee > balance.data.value
          ? 'Not enough ETH for the creation fee'
          : undefined)

  const submit = async () => {
    const lp = LAUNCHPAD_ADDRESS
    if (problem || targetWei === undefined || !lp) return
    const base = [
      form.name.trim(),
      form.symbol.trim(),
      form.logoURI,
      fixedSupply(),
      targetWei,
      BigInt(form.feeBps),
    ] as const
    const ok = await run(`Publish ${form.symbol} fundraise`, (write) =>
      vestingHours === 0
        ? write({
            address: lp,
            abi: launchpadAbi,
            functionName: 'createFundraise',
            args: base,
            value: fee,
            chainId: giwaSepolia.id,
          })
        : write({
            address: lp,
            abi: launchpadAbi,
            functionName: 'createFundraiseVested',
            args: [...base, BigInt(vestingHours)] as const,
            value: fee,
            chainId: giwaSepolia.id,
          }),
    )
    if (ok) {
      setForm(INITIAL_TOKEN_FORM)
      setTarget('')
      setVestingHours(0)
      onCreated()
    }
  }

  return (
    <section className="glass rounded-3xl p-5 sm:p-6" aria-label="Create a fundraise">
      <h2 className="display text-xl font-bold">Create a fundraise</h2>
      <p className="mt-1 text-sm text-muted">
        Publish the token details and a target. The token launches only when the target is filled, using the raised ETH
        as the first buy. You can cancel any time before it is filled, and the creation fee is not refunded.
      </p>

      <div className="mt-5 space-y-5">
        <TokenFields form={form} onChange={setForm} />

        <div>
          <label htmlFor="fund-target" className="mb-1.5 block text-xs font-semibold uppercase tracking-[0.08em] text-subtle">
            Fundraise target
          </label>
          <div className="glass-inner flex items-center gap-2 rounded-xl px-3.5">
            <input
              id="fund-target"
              inputMode="decimal"
              value={target}
              onChange={(e) => setTarget(sanitizeDecimal(e.target.value))}
              placeholder="1.0"
              className="min-h-11 w-full bg-transparent text-sm tabular-nums outline-none"
            />
            <span className="text-xs font-semibold text-subtle">ETH</span>
          </div>
          <div className="mt-2 flex flex-wrap gap-1.5">
            {TARGET_PRESETS.map((p) => (
              <button
                key={p}
                type="button"
                onClick={() => setTarget(p)}
                aria-pressed={target === p}
                className={`min-h-9 rounded-lg px-3 text-xs font-semibold tabular-nums ${target === p ? 'bg-surface-strong text-ink' : 'text-subtle hover:text-ink'}`}
              >
                {p} ETH
              </button>
            ))}
          </div>
          <p className="mt-1.5 text-xs text-subtle">
            Contributions buy along the same curve from 0.00000025 ETH. Target {MIN_FUNDRAISE_TARGET} to {MAX_FUNDRAISE_TARGET} ETH. If it is not filled within {FUNDRAISE_DAYS} days, contributors can refund.
          </p>
        </div>

        <fieldset>
          <legend className="mb-1.5 block text-xs font-semibold uppercase tracking-[0.08em] text-subtle">
            Token release for contributors
          </legend>
          <div className="grid gap-2 sm:grid-cols-3" role="radiogroup" aria-label="Token release">
            {VESTING_OPTIONS.map((opt) => {
              const disabled = opt.hours !== 0 && !vestingSupported
              const active = vestingHours === opt.hours
              return (
                <button
                  key={opt.hours}
                  type="button"
                  role="radio"
                  aria-checked={active}
                  disabled={disabled}
                  onClick={() => setVestingHours(opt.hours)}
                  className={`min-h-16 rounded-2xl px-3.5 py-2.5 text-left transition-colors disabled:cursor-not-allowed disabled:opacity-40 ${active ? 'bg-surface-strong ring-1 ring-accent' : 'glass-inner hover:bg-surface'}`}
                >
                  <span className="block text-sm font-semibold">{opt.label}</span>
                  <span className="block text-xs text-subtle">{opt.hint}</span>
                </button>
              )
            })}
          </div>
          <p className="mt-1.5 text-xs text-subtle">
            {vestingSupported
              ? 'Release starts when the fundraise fills. With 24 or 48 hours, the first part unlocks 1 hour after launch.'
              : 'Hourly release needs the latest launchpad contract. Instant release is used until it is deployed.'}
          </p>
        </fieldset>

        <div className="flex items-center justify-between border-t border-line pt-4 text-sm">
          <span className="text-subtle">Creation fee</span>
          <span className="font-semibold tabular-nums">{fmtEth(fee, 4)} ETH</span>
        </div>
        <ActionButton label={problem ?? 'Publish fundraise'} onClick={submit} status={status} disabled={Boolean(problem)} />
        {error && <p className="text-center text-xs text-danger">{error}</p>}
      </div>
    </section>
  )
}
