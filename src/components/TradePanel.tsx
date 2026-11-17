import { useMemo, useState } from 'react'
import { clsx } from 'clsx'
import { useAccount, useBalance, useReadContract } from 'wagmi'
import { erc20Abi, formatEther, formatUnits, zeroAddress } from 'viem'
import { giwaSepolia } from '@/config'
import { LAUNCHPAD_ADDRESS, MIN_TRADE_ETH, launchpadAbi } from '@/contracts/launchpad'
import type { TokenView } from '@/hooks/useTokens'
import { useTx } from '@/hooks/useTx'
import { fmtEth, fmtTokens, parseEthInput, sanitizeDecimal } from '@/lib/format'
import { ActionButton } from './ActionButton'

const LP = LAUNCHPAD_ADDRESS ?? zeroAddress
const chainId = giwaSepolia.id
const SLIPPAGE_OPTIONS = [1, 5, 10, 25]
const GAS_RESERVE = 200_000_000_000_000n // keep 0.0002 ETH for gas when using Max

type Side = 'buy' | 'sell'

export function TradePanel({ token }: { token: TokenView }) {
  const { address: account } = useAccount()
  const { run, status, error } = useTx()
  const [side, setSide] = useState<Side>('buy')
  const [amount, setAmount] = useState('')
  const [slippage, setSlippage] = useState(5)

  const parsed = parseEthInput(amount)

  const pausedQuery = useReadContract({
    address: LP,
    abi: launchpadAbi,
    functionName: 'paused',
    chainId,
    query: { enabled: Boolean(LAUNCHPAD_ADDRESS), refetchInterval: 20_000 },
  })
  const paused = pausedQuery.data === true

  const ethBalance = useBalance({ address: account, chainId, query: { enabled: Boolean(account), refetchInterval: 10_000 } })
  const tokenBalance = useReadContract({
    address: token.address,
    abi: erc20Abi,
    functionName: 'balanceOf',
    args: [account ?? zeroAddress],
    chainId,
    query: { enabled: Boolean(account), refetchInterval: 10_000 },
  })
  const allowance = useReadContract({
    address: token.address,
    abi: erc20Abi,
    functionName: 'allowance',
    args: [account ?? zeroAddress, LP],
    chainId,
    query: { enabled: Boolean(account) && side === 'sell', refetchInterval: 10_000 },
  })

  const buyQuote = useReadContract({
    address: LP,
    abi: launchpadAbi,
    functionName: 'quoteBuyDetail',
    args: [token.address, parsed ?? 0n],
    chainId,
    query: { enabled: side === 'buy' && parsed !== undefined && parsed > 0n },
  })
  const sellQuote = useReadContract({
    address: LP,
    abi: launchpadAbi,
    functionName: 'quoteSellDetail',
    args: [token.address, parsed ?? 0n],
    chainId,
    query: { enabled: side === 'sell' && parsed !== undefined && parsed > 0n },
  })

  const minTrade = parseEthInput(MIN_TRADE_ETH) ?? 0n
  const activeQuote = side === 'buy' ? buyQuote : sellQuote
  const quote = activeQuote.data?.[0]
  const newPrice = activeQuote.data?.[2]
  const quoteFailed = parsed !== undefined && parsed > 0n && activeQuote.isError
  const impactPct =
    newPrice !== undefined && token.price > 0n ? (Number(newPrice - token.price) / Number(token.price)) * 100 : undefined
  const minOut = quote !== undefined ? (quote * BigInt(100 - slippage)) / 100n : 0n

  const validation = useMemo(() => {
    if (!parsed || parsed === 0n) return 'Enter an amount'
    if (quoteFailed) {
      return side === 'buy' ? 'Over what the curve has left' : 'Reserve cannot cover that sale'
    }
    if (side === 'buy') {
      if (parsed < minTrade) return `Minimum buy is ${MIN_TRADE_ETH} ETH`
      if (ethBalance.data && parsed > ethBalance.data.value) return 'Not enough ETH'
      if (quote !== undefined && quote === 0n) return 'Amount too small'
    } else {
      if (tokenBalance.data !== undefined && parsed > tokenBalance.data) return `Not enough ${token.symbol}`
      if (quote !== undefined && quote === 0n) return 'Not enough liquidity for that amount'
    }
    return undefined
  }, [parsed, side, minTrade, ethBalance.data, quote, quoteFailed, token.symbol, tokenBalance.data])

  const needsApproval =
    side === 'sell' && parsed !== undefined && parsed > 0n && allowance.data !== undefined && allowance.data < parsed

  const setMax = () => {
    if (side === 'buy') {
      const bal = ethBalance.data?.value ?? 0n
      const max = bal > GAS_RESERVE ? bal - GAS_RESERVE : 0n
      setAmount(max > 0n ? formatEther(max) : '')
    } else if (tokenBalance.data !== undefined) {
      setAmount(formatUnits(tokenBalance.data, 18))
    }
  }

  const submit = async () => {
    if (!parsed || validation || paused) return
    if (side === 'buy') {
      const ok = await run('Buy', (write) =>
        write({ address: LP, abi: launchpadAbi, functionName: 'buy', args: [token.address, minOut], value: parsed, chainId }),
      )
      if (ok) setAmount('')
    } else if (needsApproval) {
      await run(`Approve ${token.symbol}`, (write) =>
        write({ address: token.address, abi: erc20Abi, functionName: 'approve', args: [LP, parsed], chainId }),
      )
    } else {
      const ok = await run('Sell', (write) =>
        write({ address: LP, abi: launchpadAbi, functionName: 'sell', args: [token.address, parsed, minOut], chainId }),
      )
      if (ok) setAmount('')
    }
  }

  const balanceLabel =
    side === 'buy'
      ? ethBalance.data
        ? `Balance: ${fmtEth(ethBalance.data.value)} ETH`
        : undefined
      : tokenBalance.data !== undefined
        ? `Balance: ${fmtTokens(tokenBalance.data)} ${token.symbol}`
        : undefined

  const ctaLabel = validation ?? (paused ? 'Launchpad paused' : needsApproval ? `Approve ${token.symbol}` : side === 'buy' ? `Buy ${token.symbol}` : `Sell ${token.symbol}`)
  const ctaDisabled = Boolean(validation) || paused
  const feePct = Number(token.tradeFeeBps) / 100

  return (
    <section className="glass rounded-3xl p-4 sm:p-5" aria-label="Trade">
      <div className="mb-4 grid grid-cols-2 gap-1 rounded-2xl p-1" style={{ background: 'rgba(255,255,255,0.05)' }} role="tablist">
        {(['buy', 'sell'] as const).map((s) => (
          <button
            key={s}
            type="button"
            role="tab"
            aria-selected={side === s}
            onClick={() => {
              setSide(s)
              setAmount('')
            }}
            className={clsx(
              'min-h-11 rounded-xl text-sm font-semibold capitalize transition-colors',
              side === s ? 'bg-surface-strong text-ink' : 'text-subtle hover:text-ink',
            )}
          >
            {s}
          </button>
        ))}
      </div>

      <div className="glass-inner rounded-2xl p-4">
        <div className="flex items-center justify-between text-xs text-subtle">
          <span>{side === 'buy' ? 'You pay' : 'You sell'}</span>
          {balanceLabel && (
            <button type="button" onClick={setMax} className="font-semibold text-accent hover:text-accent-hover">
              {balanceLabel} · Max
            </button>
          )}
        </div>
        <div className="mt-2 flex items-baseline gap-2">
          <input
            inputMode="decimal"
            value={amount}
            onChange={(e) => setAmount(sanitizeDecimal(e.target.value))}
            placeholder="0.0"
            aria-label={side === 'buy' ? 'ETH amount to spend' : `${token.symbol} amount to sell`}
            className="display w-full min-w-0 bg-transparent text-4xl font-bold tabular-nums outline-none"
          />
          <span className="text-sm font-semibold text-subtle">{side === 'buy' ? 'ETH' : token.symbol}</span>
        </div>
      </div>

      <dl className="mt-4 space-y-2 text-sm">
        <div className="flex justify-between">
          <dt className="text-subtle">{side === 'buy' ? 'You receive (est.)' : 'You receive (est.)'}</dt>
          <dd className="tabular-nums">
            {quote === undefined
              ? '--'
              : side === 'buy'
                ? `${fmtTokens(quote)} ${token.symbol}`
                : `${fmtEth(quote)} ETH`}
          </dd>
        </div>
        <div className="flex justify-between">
          <dt className="text-subtle">Minimum received</dt>
          <dd className="tabular-nums">
            {quote === undefined ? '--' : side === 'buy' ? `${fmtTokens(minOut)} ${token.symbol}` : `${fmtEth(minOut)} ETH`}
          </dd>
        </div>
        <div className="flex justify-between">
          <dt className="text-subtle">Trade fee</dt>
          <dd className="tabular-nums">{feePct}%</dd>
        </div>
        <p className="text-xs text-subtle">
          Fee split: 40% platform, 20% creator, 20% holders, 20% burned. It never reduces the ETH backing the curve.
        </p>
        {side === 'sell' && (
          <div className="flex justify-between">
            <dt className="text-subtle">Available liquidity</dt>
            <dd className="tabular-nums">{fmtEth(token.reserveETH)} ETH</dd>
          </div>
        )}
        <div className="flex justify-between">
          <dt className="text-subtle">Price impact</dt>
          <dd className="tabular-nums">
            {impactPct === undefined ? '--' : `${impactPct >= 0 ? '+' : ''}${impactPct.toFixed(2)}%`}
          </dd>
        </div>
      </dl>

      <div className="mt-4 flex items-center gap-1.5" role="group" aria-label="Slippage tolerance">
        <span className="mr-1 text-xs text-subtle">Slippage</span>
        {SLIPPAGE_OPTIONS.map((s) => (
          <button
            key={s}
            type="button"
            onClick={() => setSlippage(s)}
            aria-pressed={slippage === s}
            className={clsx(
              'min-h-9 rounded-lg px-2.5 text-xs font-semibold tabular-nums',
              slippage === s ? 'bg-surface-strong text-ink' : 'text-subtle hover:text-ink',
            )}
          >
            {s}%
          </button>
        ))}
      </div>

      <div className="mt-4">
        <ActionButton label={ctaLabel} onClick={submit} status={status} disabled={ctaDisabled} />
      </div>
      {error && <p className="mt-3 text-center text-xs text-danger">{error}</p>}
      {paused && <p className="mt-3 text-center text-xs text-subtle">Trading is paused by the platform owner.</p>}
    </section>
  )
}
