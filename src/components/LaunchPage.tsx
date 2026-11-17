import { useState } from 'react'
import { useAccount, useBalance, useReadContract } from 'wagmi'
import { parseEther, zeroAddress } from 'viem'
import { giwaSepolia } from '@/config'
import { CREATION_FEE_LABEL, LAUNCHPAD_ADDRESS, MIN_TRADE_ETH, launchpadAbi } from '@/contracts/launchpad'
import { useTx } from '@/hooks/useTx'
import { fmtEth, parseEthInput, sanitizeDecimal } from '@/lib/format'
import { ActionButton } from './ActionButton'
import { CurveFacts } from './CurveFacts'
import { NotDeployedNotice } from './Notices'
import {
  INITIAL_TOKEN_FORM,
  TokenFields,
  fixedSupply,
  validateTokenForm,
  type TokenFormState,
} from './TokenFields'

export function LaunchPage({ onLaunched }: { onLaunched: () => void }) {
  const { address: account } = useAccount()
  const { run, status, error } = useTx()
  const [form, setForm] = useState<TokenFormState>(INITIAL_TOKEN_FORM)
  const [firstBuy, setFirstBuy] = useState('')

  const feeQuery = useReadContract({
    address: LAUNCHPAD_ADDRESS ?? zeroAddress,
    abi: launchpadAbi,
    functionName: 'instantCreationFee',
    chainId: giwaSepolia.id,
    query: { enabled: Boolean(LAUNCHPAD_ADDRESS) },
  })
  const balance = useBalance({ address: account, chainId: giwaSepolia.id, query: { enabled: Boolean(account) } })

  const lp = LAUNCHPAD_ADDRESS
  if (!lp) return <NotDeployedNotice />

  const creationFee = feeQuery.data ?? parseEther(CREATION_FEE_LABEL)
  const firstBuyWei = firstBuy ? parseEthInput(firstBuy) : 0n
  const minBuy = parseEther(MIN_TRADE_ETH)
  const total = creationFee + (firstBuyWei ?? 0n)

  const problem =
    validateTokenForm(form) ??
    (firstBuyWei === undefined
      ? 'Enter a valid first buy amount'
      : firstBuyWei > 0n && firstBuyWei < minBuy
        ? `First buy must be at least ${MIN_TRADE_ETH} ETH (or leave it empty)`
        : balance.data && total > balance.data.value
          ? 'Not enough ETH for the fee plus first buy'
          : undefined)

  const submit = async () => {
    if (problem) return
    const ok = await run(`Launch ${form.symbol}`, (write) =>
      write({
        address: lp,
        abi: launchpadAbi,
        functionName: 'createInstant',
        args: [form.name.trim(), form.symbol.trim(), form.logoURI, fixedSupply(), BigInt(form.feeBps)],
        value: total,
        chainId: giwaSepolia.id,
      }),
    )
    if (ok) {
      setForm(INITIAL_TOKEN_FORM)
      setFirstBuy('')
      onLaunched()
    }
  }

  return (
    <div className="mx-auto max-w-2xl space-y-5">
      <div>
        <h1 className="display text-3xl font-bold text-balance">Launch a token</h1>
        <p className="mt-1 text-sm text-muted">
          Your token goes live on the curve instantly at 0.00000025 ETH. The price rises smoothly as people buy and falls as they sell, up to 10x at sell-out.
        </p>
      </div>

      <section className="glass rounded-3xl p-5 sm:p-6">
        <TokenFields form={form} onChange={setForm} />

        <div className="mt-5">
          <label htmlFor="first-buy" className="mb-1.5 block text-xs font-semibold uppercase tracking-[0.08em] text-subtle">
            Your first buy (optional)
          </label>
          <div className="glass-inner flex items-center gap-2 rounded-xl px-3.5">
            <input
              id="first-buy"
              inputMode="decimal"
              value={firstBuy}
              onChange={(e) => setFirstBuy(sanitizeDecimal(e.target.value))}
              placeholder="0.0"
              className="min-h-11 w-full bg-transparent text-sm tabular-nums outline-none"
            />
            <span className="text-xs font-semibold text-subtle">ETH</span>
          </div>
          <p className="mt-1.5 text-xs text-subtle">Buy your own token at the starting price in the same transaction.</p>
        </div>
      </section>

      <CurveFacts />

      <section className="glass rounded-3xl p-5 sm:p-6">
        <dl className="space-y-2 text-sm">
          <div className="flex justify-between">
            <dt className="text-subtle">Creation fee</dt>
            <dd className="tabular-nums">{fmtEth(creationFee, 4)} ETH</dd>
          </div>
          <div className="flex justify-between">
            <dt className="text-subtle">First buy</dt>
            <dd className="tabular-nums">{fmtEth(firstBuyWei ?? 0n)} ETH</dd>
          </div>
          <div className="flex justify-between border-t border-line pt-2 font-semibold">
            <dt>Total</dt>
            <dd className="tabular-nums">{fmtEth(total, 4)} ETH</dd>
          </div>
        </dl>
        <div className="mt-4">
          <ActionButton
            label={problem ?? `Launch ${form.symbol || 'token'}`}
            onClick={submit}
            status={status}
            disabled={Boolean(problem)}
          />
        </div>
        {error && <p className="mt-3 text-center text-xs text-danger">{error}</p>}
      </section>
    </div>
  )
}
