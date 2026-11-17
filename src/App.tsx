import { useCallback, useState } from 'react'
import type { Address } from 'viem'
import { Nav, type Tab } from '@/components/Nav'
import { MarketPage } from '@/components/MarketPage'
import { TradePage } from '@/components/TradePage'
import { LaunchPage } from '@/components/LaunchPage'
import { FundraisePage } from '@/components/FundraisePage'
import { PortfolioPage } from '@/components/PortfolioPage'
import { StakingPage } from '@/components/StakingPage'
import { AdminPage } from '@/components/AdminPage'
import { useIsOwner } from '@/hooks/useAdmin'
import { ContractLink, WrongNetworkBar } from '@/components/Notices'

export default function App() {
  const [tab, setTab] = useState<Tab>('market')
  const [selected, setSelected] = useState<Address | undefined>()
  const { isOwner } = useIsOwner()

  const changeTab = useCallback((next: Tab) => {
    setTab(next)
    window.scrollTo({ top: 0 })
  }, [])

  const openTrade = useCallback(
    (token: Address) => {
      setSelected(token)
      changeTab('trade')
    },
    [changeTab],
  )

  return (
    <div className="min-h-dvh">
      <Nav tab={tab} onChange={changeTab} showAdmin={isOwner} />
      <WrongNetworkBar />
      <main className="mx-auto max-w-6xl px-4 pb-24 pt-6">
        {tab === 'market' && <MarketPage onTrade={openTrade} onLaunch={() => changeTab('launch')} />}
        {tab === 'trade' && <TradePage selected={selected} onSelect={setSelected} />}
        {tab === 'launch' && <LaunchPage onLaunched={() => changeTab('market')} />}
        {tab === 'fundraise' && <FundraisePage onTrade={openTrade} />}
        {tab === 'portfolio' && <PortfolioPage onTrade={openTrade} />}
        {tab === 'staking' && <StakingPage />}
        {tab === 'admin' && <AdminPage />}
        <div className="mt-10 flex justify-center">
          <ContractLink label="View launchpad contract" />
        </div>
      </main>
    </div>
  )
}
