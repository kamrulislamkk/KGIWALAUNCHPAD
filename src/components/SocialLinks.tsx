const LINKS = [
  {
    id: 'telegram',
    label: 'Telegram',
    handle: 't.me/kgiwalaunchpad',
    href: 'https://t.me/kgiwalaunchpad',
    icon: (
      <svg viewBox="0 0 24 24" className="size-5" fill="currentColor" aria-hidden>
        <path d="M21.9 4.4 18.7 19.6c-.2 1.1-.9 1.4-1.8.9l-4.9-3.6-2.4 2.3c-.3.3-.5.5-1 .5l.4-5 9-8.1c.4-.3-.1-.5-.6-.2L6.3 13.4l-4.8-1.5c-1-.3-1-1 .2-1.5L20.5 3.1c.9-.3 1.6.2 1.4 1.3Z" />
      </svg>
    ),
  },
  {
    id: 'x',
    label: 'X',
    handle: '@ITSMEkkdot',
    href: 'https://x.com/ITSMEkkdot',
    icon: (
      <svg viewBox="0 0 24 24" className="size-4" fill="currentColor" aria-hidden>
        <path d="M18.2 2.3h3.3l-7.2 8.3 8.5 11.2h-6.7l-5.2-6.8-6 6.8H1.6l7.7-8.8L1.2 2.3H8l4.7 6.2 5.5-6.2Zm-1.2 17.5h1.8L7.1 4.1H5.1L17 19.8Z" />
      </svg>
    ),
  },
] as const

/** Follow-us links, opened in a new tab. */
export function SocialLinks() {
  return (
    <section className="glass rounded-3xl p-5 sm:p-6" aria-label="Follow us">
      <h2 className="display text-base font-bold">Follow Kgiwa</h2>
      <p className="mt-0.5 text-sm text-muted">Join the community for launches, updates and support.</p>
      <div className="mt-4 flex flex-wrap gap-3">
        {LINKS.map((link) => (
          <a
            key={link.id}
            href={link.href}
            target="_blank"
            rel="noopener noreferrer"
            aria-label={`${link.label} ${link.handle}`}
            className="glass flex min-h-12 items-center gap-3 rounded-2xl px-4 text-sm font-semibold transition-colors hover:bg-surface-strong"
          >
            <span className="flex size-9 items-center justify-center rounded-xl bg-accent text-bg">{link.icon}</span>
            <span className="leading-tight">
              <span className="block">{link.label}</span>
              <span className="block text-xs font-normal text-subtle">{link.handle}</span>
            </span>
          </a>
        ))}
      </div>
    </section>
  )
}
