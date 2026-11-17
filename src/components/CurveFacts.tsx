import { START_PRICE_ETH } from '@/contracts/launchpad'

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-baseline justify-between gap-4 py-1.5">
      <dt className="text-subtle">{label}</dt>
      <dd className="text-right font-medium tabular-nums">{value}</dd>
    </div>
  )
}

/** Fixed token economics shared by every launch. Values mirror the contract constants. */
export function CurveFacts() {
  return (
    <section className="glass rounded-3xl p-5 sm:p-6" aria-label="How the curve works">
      <h2 className="display text-base font-bold">How every launch works</h2>
      <dl className="mt-2 divide-y divide-line text-sm">
        <Row label="Total supply" value="1,000,000,000" />
        <Row label="Sold on the curve" value="800,000,000 (80%)" />
        <Row label="Locked forever" value="200,000,000 (20%)" />
        <Row label="Start price" value={`${START_PRICE_ETH} ETH`} />
        <Row label="Selling out the curve" value="about 782 ETH" />
      </dl>
      <p className="mt-3 text-xs text-subtle">
        Buys and sells follow the same curve. Sales are paid from real ETH held by the contract, never from virtual
        liquidity. Fees never come out of that backing.
      </p>
    </section>
  )
}
