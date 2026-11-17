import { ShieldCheck } from 'lucide-react'
import { useAccount } from 'wagmi'
import { useAdmin, useIsOwner } from '@/hooks/useAdmin'
import { useAdminEvents } from '@/hooks/useAdminEvents'
import { shortAddress } from '@/lib/format'
import { AdminFees } from './AdminFees'
import { AdminSettings } from './AdminSettings'
import { AdminTraders } from './AdminTraders'
import { NotDeployedNotice } from './Notices'
import { LAUNCHPAD_ADDRESS } from '@/contracts/launchpad'

function Restricted({ message }: { message: string }) {
  return (
    <div className="glass mx-auto flex max-w-lg flex-col items-center gap-3 rounded-3xl p-10 text-center">
      <div className="flex size-14 items-center justify-center rounded-2xl bg-surface-strong">
        <ShieldCheck className="size-6 text-accent" aria-hidden />
      </div>
      <h1 className="display text-2xl font-bold">Admin</h1>
      <p className="max-w-sm text-sm text-muted">{message}</p>
    </div>
  )
}

export function AdminPage() {
  const { isConnected } = useAccount()
  const { owner, isOwner, isLoading } = useIsOwner()
  const admin = useAdmin()
  const events = useAdminEvents(isOwner)

  if (!LAUNCHPAD_ADDRESS) return <NotDeployedNotice />
  if (!isConnected) return <Restricted message="Connect the owner wallet to open the admin panel." />
  if (isLoading) return <Restricted message="Checking your wallet..." />
  if (!isOwner) {
    return (
      <Restricted
        message={`The admin panel is only for the contract owner${owner ? ` (${shortAddress(owner)})` : ''}. Switch to that wallet to continue.`}
      />
    )
  }

  return (
    <div className="space-y-6">
      <header>
        <h1 className="display text-3xl font-bold">Admin</h1>
        <p className="mt-1 text-sm text-muted">Treasury, fees and trader activity for the launchpad.</p>
      </header>

      <AdminFees
        events={events.data}
        loading={events.isLoading}
        failed={events.isError}
        instantFee={admin.instantFee}
        totalVolume={admin.totalVolume}
      />
      <AdminSettings treasury={admin.treasury} treasuryBalance={admin.treasuryBalance} fundraiseFee={admin.fundraiseFee} />
      <AdminTraders events={events.data} eventsLoading={events.isLoading} traderCount={admin.traderCount} />
    </div>
  )
}
