import { useState } from 'react'
import { ExternalLink } from 'lucide-react'
import { formatEther, isAddress, parseEther, zeroAddress, type Address } from 'viem'
import { giwaSepolia } from '@/config'
import { LAUNCHPAD_ADDRESS, launchpadAbi } from '@/contracts/launchpad'
import { useTx } from '@/hooks/useTx'
import { fmtEth, parseEthInput, sanitizeDecimal, shortAddress } from '@/lib/format'
import { ActionButton } from './ActionButton'

/** Typo guard for the fundraise creation fee (the contract itself has no upper bound). */
const MAX_FEE_ETH = '10'

interface Props {
  treasury?: Address
  treasuryBalance?: bigint
  fundraiseFee?: bigint
}

export function AdminSettings({ treasury, treasuryBalance, fundraiseFee }: Props) {
  const treasuryTx = useTx()
  const feeTx = useTx()
  const [wallet, setWallet] = useState('')
  const [fee, setFee] = useState('')
  const [confirmWallet, setConfirmWallet] = useState(false)
  const [confirmFee, setConfirmFee] = useState(false)

  const lp = LAUNCHPAD_ADDRESS
  if (!lp) return null

  const walletValid = isAddress(wallet)
  const walletProblem = !wallet
    ? 'Enter the new treasury address'
    : !walletValid
      ? 'Not a valid address'
      : wallet.toLowerCase() === zeroAddress
        ? 'The zero address is not allowed'
        : treasury && wallet.toLowerCase() === treasury.toLowerCase()
          ? 'That is already the treasury address'
          : undefined

  const feeWei = fee ? parseEthInput(fee) : undefined
  const feeProblem = !fee
    ? 'Enter the new fee in ETH'
    : feeWei === undefined
      ? 'Enter a valid number'
      : feeWei > parseEther(MAX_FEE_ETH)
        ? `Maximum is ${MAX_FEE_ETH} ETH`
        : fundraiseFee !== undefined && feeWei === fundraiseFee
          ? 'That is already the current fee'
          : undefined

  const saveWallet = async () => {
    if (walletProblem || !walletValid) return
    const ok = await treasuryTx.run('Treasury address update', (write) =>
      write({
        address: lp,
        abi: launchpadAbi,
        functionName: 'setPlatformWallet',
        args: [wallet],
        chainId: giwaSepolia.id,
      }),
    )
    if (ok) {
      setWallet('')
      setConfirmWallet(false)
    }
  }

  const saveFee = async () => {
    if (feeProblem || feeWei === undefined) return
    const ok = await feeTx.run('Fundraise fee update', (write) =>
      write({
        address: lp,
        abi: launchpadAbi,
        functionName: 'setFundraiseCreationFee',
        args: [feeWei],
        chainId: giwaSepolia.id,
      }),
    )
    if (ok) {
      setFee('')
      setConfirmFee(false)
    }
  }

  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <section className="glass rounded-3xl p-5 sm:p-6" aria-labelledby="treasury-title">
        <h2 id="treasury-title" className="display text-lg font-bold">
          Treasury wallet
        </h2>
        <p className="mt-1 text-xs text-subtle">All platform fees are paid to this address as they happen.</p>
        <div className="glass-inner mt-4 rounded-2xl p-4">
          <div className="text-xs text-subtle">Current address</div>
          {treasury ? (
            <a
              href={`${giwaSepolia.blockExplorers.default.url}/address/${treasury}`}
              target="_blank"
              rel="noopener noreferrer"
              className="mono mt-1 flex items-center gap-1.5 break-all text-xs hover:text-accent"
            >
              {treasury} <ExternalLink className="size-3 shrink-0" />
            </a>
          ) : (
            <div className="mt-1 text-sm">...</div>
          )}
          <div className="mt-3 text-xs text-subtle">Balance</div>
          <div className="mt-0.5 text-lg font-semibold tabular-nums">
            {treasuryBalance === undefined ? '...' : fmtEth(treasuryBalance)} <span className="text-sm text-subtle">ETH</span>
          </div>
        </div>

        <label className="mt-4 block text-sm font-medium" htmlFor="new-treasury">
          New treasury address
        </label>
        <input
          id="new-treasury"
          value={wallet}
          onChange={(e) => {
            setWallet(e.target.value.trim())
            setConfirmWallet(false)
          }}
          placeholder="0x..."
          spellCheck={false}
          autoComplete="off"
          className="glass-inner mono mt-1.5 min-h-11 w-full rounded-xl px-3 text-xs outline-none"
        />
        {confirmWallet && !walletProblem ? (
          <div className="mt-3 space-y-3">
            <p className="text-sm text-muted">
              From now on every platform fee is sent to <span className="mono text-xs">{shortAddress(wallet)}</span>. Make
              sure you control it.
            </p>
            <div className="flex gap-2">
              <ActionButton label="Confirm change" onClick={saveWallet} status={treasuryTx.status} />
              <ActionButton label="Cancel" variant="ghost" onClick={() => setConfirmWallet(false)} status="idle" />
            </div>
          </div>
        ) : (
          <div className="mt-3">
            <ActionButton
              label={walletProblem ?? 'Change treasury address'}
              onClick={() => setConfirmWallet(true)}
              status="idle"
              disabled={Boolean(walletProblem)}
            />
          </div>
        )}
        {treasuryTx.error && <p className="mt-2 text-center text-xs text-danger">{treasuryTx.error}</p>}
      </section>

      <section className="glass rounded-3xl p-5 sm:p-6" aria-labelledby="fee-title">
        <h2 id="fee-title" className="display text-lg font-bold">
          Fundraise creation fee
        </h2>
        <p className="mt-1 text-xs text-subtle">
          Charged once when someone publishes a fundraise. This is the only fee you can change here.
        </p>
        <div className="glass-inner mt-4 rounded-2xl p-4">
          <div className="text-xs text-subtle">Current fee</div>
          <div className="mt-0.5 text-lg font-semibold tabular-nums">
            {fundraiseFee === undefined ? '...' : formatEther(fundraiseFee)} <span className="text-sm text-subtle">ETH</span>
          </div>
        </div>

        <label className="mt-4 block text-sm font-medium" htmlFor="new-fee">
          New fee (ETH)
        </label>
        <input
          id="new-fee"
          inputMode="decimal"
          value={fee}
          onChange={(e) => {
            setFee(sanitizeDecimal(e.target.value))
            setConfirmFee(false)
          }}
          placeholder="0.05"
          className="glass-inner mt-1.5 min-h-11 w-full rounded-xl px-3 text-sm tabular-nums outline-none"
        />
        {confirmFee && !feeProblem ? (
          <div className="mt-3 space-y-3">
            <p className="text-sm text-muted">
              New fundraises will cost <span className="font-semibold">{fee} ETH</span> to create. Existing ones are not
              affected.
            </p>
            <div className="flex gap-2">
              <ActionButton label="Confirm change" onClick={saveFee} status={feeTx.status} />
              <ActionButton label="Cancel" variant="ghost" onClick={() => setConfirmFee(false)} status="idle" />
            </div>
          </div>
        ) : (
          <div className="mt-3">
            <ActionButton
              label={feeProblem ?? 'Update fundraise fee'}
              onClick={() => setConfirmFee(true)}
              status="idle"
              disabled={Boolean(feeProblem)}
            />
          </div>
        )}
        {feeTx.error && <p className="mt-2 text-center text-xs text-danger">{feeTx.error}</p>}
      </section>
    </div>
  )
}
