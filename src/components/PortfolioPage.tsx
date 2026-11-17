import { useMemo } from 'react'
import { clsx } from 'clsx'
import { useAccount, useBalance, useReadContracts } from 'wagmi'
import { erc20Abi, zeroAddress, type Address } from 'viem'
import { ConnectKitButton } from 'connectkit'
import { Wallet } from 'lucide-react'
import { giwaSepolia } from '@/config'
import { LAUNCHPAD_ADDRESS, launchpadAbi } from '@/contracts/launchpad'
import { useFundraises } from '@/hooks/useFundraises'
import { useTokens, type TokenView } from '@/hooks/useTokens'
import { fmtEth, fmtPrice, fmtTokens, launchPrice, pctChange } from '@/lib/format'
import { FundraiseCard } from './FundraiseCard'
import { RewardsSection } from './RewardsSection'
import { SocialLinks } from './SocialLinks'
import { TokenLogo } from './TokenLogo'
import { EmptyState, NotDeployedNotice } from './Notices'

const chainId = giwaSepolia.id
const LP = LAUNCHPAD_ADDRESS ?? zeroAddress

interface Holding {
  token: TokenView
  balance: bigint
  marketValue: bigint
  redeemable: bigint
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="space-y-3">
      <h2 className="display text-xl font-bold">{title}</h2>
      {children}
    </section>
  )
}

function useHoldings(tokens: TokenView[], account: Address | undefined) {
  const enabled = Boolean(account) && tokens.length > 0
  const balances = useReadContracts({
    allowFailure: false,
    contracts: tokens.map((t) => ({
      address: t.address,
      abi: erc20Abi,
      functionName: 'balanceOf' as const,
      args: [account ?? zeroAddress] as const,
      chainId,
    })),
    query: { enabled, refetchInterval: 12_000 },
  })

  const held = useMemo(() => {
    const data = balances.data
    if (!data) return []
    return tokens
      .map((token, i) => ({ token, balance: data[i] ?? 0n }))
      .filter((h) => h.balance > 0n)
  }, [tokens, balances.data])

  const quotes = useReadContracts({
    allowFailure: true,
    contracts: held.map((h) => ({
      address: LP,
      abi: launchpadAbi,
      functionName: 'quoteSell' as const,
      args: [h.token.address, h.balance] as const,
      chainId,
    })),
    query: { enabled: held.length > 0, refetchInterval: 12_000 },
  })

  const holdings = useMemo<Holding[]>(
    () =>
      held.map((h, i) => {
        const q = quotes.data?.[i]
        return {
          ...h,
          marketValue: (h.balance * h.token.price) / 10n ** 18n,
          redeemable: q && q.status === 'success' ? q.result : 0n,
        }
      }),
    [held, quotes.data],
  )
  return { holdings, isLoading: enabled && balances.isLoading }
}

function Summary({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="glass rounded-3xl p-5">
      <div className="text-[10px] font-semibold uppercase tracking-[0.1em] text-subtle">{label}</div>
      <div className="mt-1 flex items-baseline gap-1.5">
        <span className="display text-3xl font-bold tabular-nums">{value}</span>
        <span className="text-sm text-subtle">ETH</span>
      </div>
      {sub && <div className="mt-1 text-xs text-muted">{sub}</div>}
    </div>
  )
}

export function PortfolioPage({ onTrade }: { onTrade: (token: Address) => void }) {
  const { address: account, isConnected } = useAccount()
  const { tokens, enabled } = useTokens()
  const { fundraises } = useFundraises()
  const ethBalance = useBalance({ address: account, chainId, query: { enabled: Boolean(account), refetchInterval: 12_000 } })
  const { holdings, isLoading } = useHoldings(tokens, account)

  const created = useMemo(
    () => (account ? tokens.filter((t) => t.creator.toLowerCase() === account.toLowerCase()) : []),
    [tokens, account],
  )
  const positions = useMemo(
    () => fundraises.filter((f) => f.mine && (f.mine.ethContributed > 0n || f.creator.toLowerCase() === account?.toLowerCase())),
    [fundraises, account],
  )

  const redeemableTotal = holdings.reduce((sum, h) => sum + h.redeemable, 0n)
  const marketTotal = holdings.reduce((sum, h) => sum + h.marketValue, 0n)

  if (!enabled) return <NotDeployedNotice />

  if (!isConnected) {
    return (
      <div className="mx-auto max-w-md space-y-4">
      <div className="glass flex flex-col items-center gap-3 rounded-3xl p-10 text-center">
        <Wallet className="size-7 text-accent" aria-hidden />
        <h1 className="display text-xl font-bold">Connect to see your portfolio</h1>
        <p className="text-sm text-muted">Your tokens, fundraise positions and created launches show up here.</p>
        <ConnectKitButton.Custom>
          {({ show }) => (
            <button
              type="button"
              onClick={show}
              className="min-h-11 rounded-xl bg-accent px-5 text-sm font-semibold text-bg hover:bg-accent-hover"
            >
              Connect wallet
            </button>
          )}
        </ConnectKitButton.Custom>
      </div>
      <SocialLinks />
      </div>
    )
  }

  return (
    <div className="space-y-8">
      <div>
        <h1 className="display text-3xl font-bold text-balance">Portfolio</h1>
        <p className="mt-1 text-sm text-muted">Live balances on {giwaSepolia.name}.</p>
      </div>

      <div className="grid gap-3 sm:grid-cols-3">
        <Summary
          label="Wallet balance"
          value={ethBalance.data ? fmtEth(ethBalance.data.value) : '...'}
        />
        <Summary
          label="Tokens (sell value)"
          value={fmtEth(redeemableTotal)}
          sub={`${fmtEth(marketTotal)} ETH at market price`}
        />
        <Summary
          label="Total"
          value={fmtEth((ethBalance.data?.value ?? 0n) + redeemableTotal)}
          sub="Wallet plus what your tokens would sell for"
        />
      </div>

      <Section title="Holdings">
        {isLoading ? (
          <div className="glass h-28 animate-pulse rounded-3xl" />
        ) : holdings.length === 0 ? (
          <EmptyState title="No tokens yet" body="Buy a token from the Market tab and it shows up here." />
        ) : (
          <div className="glass divide-y divide-line overflow-hidden rounded-3xl">
            {holdings.map((h) => {
              const change = pctChange(h.token.price, launchPrice())
              return (
                <button
                  key={h.token.address}
                  type="button"
                  onClick={() => onTrade(h.token.address)}
                  className="flex min-h-16 w-full items-center gap-3 px-4 py-3 text-left transition-colors hover:bg-surface"
                >
                  <TokenLogo logoURI={h.token.logoURI} symbol={h.token.symbol} size={40} />
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-sm font-semibold">{h.token.name}</div>
                    <div className="text-xs tabular-nums text-subtle">
                      {fmtTokens(h.balance)} {h.token.symbol} · {fmtPrice(h.token.price)} ETH
                    </div>
                  </div>
                  <div className="text-right">
                    <div className="text-sm font-semibold tabular-nums">{fmtEth(h.redeemable)} ETH</div>
                    <div className={clsx('text-xs tabular-nums', change >= 0 ? 'text-success' : 'text-danger')}>
                      {change >= 0 ? '+' : ''}
                      {change.toFixed(1)}% since launch
                    </div>
                  </div>
                </button>
              )
            })}
          </div>
        )}
      </Section>

      {account && <RewardsSection tokens={tokens} account={account} />}

      {positions.length > 0 && (
        <Section title="Fundraise positions">
          <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
            {positions.map((f) => (
              <FundraiseCard key={f.id} fundraise={f} onTrade={onTrade} />
            ))}
          </div>
        </Section>
      )}

      {created.length > 0 && (
        <Section title="Tokens you launched">
          <div className="glass divide-y divide-line overflow-hidden rounded-3xl">
            {created.map((t) => (
              <button
                key={t.address}
                type="button"
                onClick={() => onTrade(t.address)}
                className="flex min-h-16 w-full items-center gap-3 px-4 py-3 text-left transition-colors hover:bg-surface"
              >
                <TokenLogo logoURI={t.logoURI} symbol={t.symbol} size={40} />
                <div className="min-w-0 flex-1">
                  <div className="truncate text-sm font-semibold">{t.name}</div>
                  <div className="text-xs uppercase text-subtle">{t.symbol}</div>
                </div>
                <div className="text-right text-xs tabular-nums text-muted">
                  <div>{fmtEth(t.marketCap)} ETH cap</div>
                  <div>{fmtEth(t.volume)} ETH volume</div>
                </div>
              </button>
            ))}
          </div>
        </Section>
      )}

      <SocialLinks />
    </div>
  )
}
