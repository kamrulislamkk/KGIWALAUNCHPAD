import { useRef, useState } from 'react'
import { clsx } from 'clsx'
import { ImagePlus, Loader2, X } from 'lucide-react'
import { FEE_OPTIONS_BPS, TOTAL_SUPPLY } from '@/contracts/launchpad'
import { fileToLogoDataUri } from '@/lib/image'
import { TokenLogo } from './TokenLogo'

export interface TokenFormState {
  name: string
  symbol: string
  logoURI: string
  feeBps: number
}

export const INITIAL_TOKEN_FORM: TokenFormState = {
  name: '',
  symbol: '',
  logoURI: '',
  feeBps: 100,
}


/** Returns the first problem with the form, or undefined when it is valid. */
export function validateTokenForm(form: TokenFormState): string | undefined {
  if (!form.name.trim()) return 'Enter a token name'
  if (form.name.trim().length > 64) return 'Name is too long (max 64)'
  if (!form.symbol.trim()) return 'Enter a ticker'
  if (form.symbol.trim().length > 16) return 'Ticker is too long (max 16)'
  if (!FEE_OPTIONS_BPS.some((bps) => bps === form.feeBps)) return 'Choose a trade fee of 1%, 2% or 3%'
  return undefined
}

/** Supply is fixed by the contract at 1 billion tokens. */
export function fixedSupply(): bigint {
  return TOTAL_SUPPLY
}

function LogoPicker({ value, symbol, onChange }: { value: string; symbol: string; onChange: (uri: string) => void }) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string>()

  const pick = async (file: File | undefined) => {
    if (!file) return
    setBusy(true)
    setError(undefined)
    try {
      onChange(await fileToLogoDataUri(file))
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not use that image.')
    } finally {
      setBusy(false)
      if (inputRef.current) inputRef.current.value = ''
    }
  }

  return (
    <div>
      <div className="flex items-center gap-3">
        <TokenLogo logoURI={value} symbol={symbol || '??'} size={64} />
        <div className="flex flex-wrap gap-2">
          <input
            ref={inputRef}
            type="file"
            accept="image/*"
            className="sr-only"
            id="logo-upload"
            onChange={(e) => void pick(e.target.files?.[0])}
          />
          <label
            htmlFor="logo-upload"
            className="glass inline-flex min-h-11 cursor-pointer items-center gap-2 rounded-xl px-3.5 text-sm font-semibold hover:bg-surface-strong"
          >
            {busy ? <Loader2 className="size-4 animate-spin" /> : <ImagePlus className="size-4" />}
            {value ? 'Change logo' : 'Upload logo'}
          </label>
          {value && (
            <button
              type="button"
              onClick={() => onChange('')}
              className="inline-flex min-h-11 items-center gap-1.5 rounded-xl px-3 text-sm text-subtle hover:text-ink"
            >
              <X className="size-4" /> Remove
            </button>
          )}
        </div>
      </div>
      <p className="mt-2 text-xs text-subtle">
        Resized in your browser to a tiny image (about 4 KB) and stored onchain with the token.
      </p>
      {error && <p className="mt-1 text-xs text-danger">{error}</p>}
    </div>
  )
}

const inputClass =
  'glass-inner min-h-11 w-full rounded-xl px-3.5 py-2.5 text-sm outline-none focus:border-line-strong'

function Field({ label, htmlFor, children, hint }: { label: string; htmlFor?: string; children: React.ReactNode; hint?: string }) {
  return (
    <div>
      <label htmlFor={htmlFor} className="mb-1.5 block text-xs font-semibold uppercase tracking-[0.08em] text-subtle">
        {label}
      </label>
      {children}
      {hint && <p className="mt-1.5 text-xs text-subtle">{hint}</p>}
    </div>
  )
}

interface Props {
  form: TokenFormState
  onChange: (next: TokenFormState) => void
}

export function TokenFields({ form, onChange }: Props) {
  const set = <K extends keyof TokenFormState>(key: K, value: TokenFormState[K]) => onChange({ ...form, [key]: value })

  return (
    <div className="space-y-5">
      <Field label="Logo">
        <LogoPicker value={form.logoURI} symbol={form.symbol} onChange={(uri) => set('logoURI', uri)} />
      </Field>

      <div className="grid gap-4 sm:grid-cols-[1fr_160px]">
        <Field label="Token name" htmlFor="token-name">
          <input
            id="token-name"
            value={form.name}
            maxLength={64}
            onChange={(e) => set('name', e.target.value)}
            placeholder="Kgiwa Cat"
            className={inputClass}
          />
        </Field>
        <Field label="Ticker" htmlFor="token-symbol">
          <input
            id="token-symbol"
            value={form.symbol}
            maxLength={16}
            onChange={(e) => set('symbol', e.target.value.toUpperCase().replace(/\s/g, ''))}
            placeholder="KCAT"
            className={clsx(inputClass, 'uppercase')}
          />
        </Field>
      </div>

      <Field label="Trade fee" hint="Taken from every buy and sell of this token: 40% platform, 20% you as creator, 20% holders, 20% burned.">
        <div className="flex flex-wrap gap-1.5" role="group" aria-label="Trade fee">
          {FEE_OPTIONS_BPS.map((bps) => (
            <button
              key={bps}
              type="button"
              onClick={() => set('feeBps', bps)}
              aria-pressed={form.feeBps === bps}
              className={clsx(
                'min-h-10 rounded-xl px-3.5 text-sm font-semibold tabular-nums',
                form.feeBps === bps ? 'bg-surface-strong text-ink' : 'glass text-subtle hover:text-ink',
              )}
            >
              {bps / 100}%
            </button>
          ))}
        </div>
      </Field>
    </div>
  )
}
