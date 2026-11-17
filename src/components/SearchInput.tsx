import { Search, X } from 'lucide-react'

interface Props {
  value: string
  onChange: (value: string) => void
  placeholder?: string
  label?: string
}

export function SearchInput({ value, onChange, placeholder = 'Search by name, symbol or address', label = 'Search tokens' }: Props) {
  return (
    <label className="glass flex min-h-11 items-center gap-2 rounded-2xl px-3.5">
      <Search className="size-4 shrink-0 text-subtle" aria-hidden />
      <input
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        aria-label={label}
        className="min-w-0 flex-1 bg-transparent py-2.5 text-sm outline-none"
        autoComplete="off"
        spellCheck={false}
      />
      {value && (
        <button
          type="button"
          onClick={() => onChange('')}
          aria-label="Clear search"
          className="flex size-6 items-center justify-center rounded-full text-subtle hover:text-ink"
        >
          <X className="size-4" />
        </button>
      )}
    </label>
  )
}

export function matchesQuery(query: string, fields: string[]): boolean {
  const q = query.trim().toLowerCase()
  if (!q) return true
  return fields.some((f) => f.toLowerCase().includes(q))
}
