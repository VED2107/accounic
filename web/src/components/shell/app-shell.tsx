'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useCallback, useEffect, useState, type ReactNode } from 'react';
import {
  ActivityIcon,
  AdminIcon,
  ChevronRightIcon,
  HomeIcon,
  PeopleIcon,
  PlusIcon,
  ProfileIcon,
  SearchIcon,
} from '@/components/icons';
import { AccounicLogo, AccounicMark } from '@/components/brand';
import { Avatar, cn } from '@/components/ui/primitives';
import { ToastProvider } from '@/components/ui/toast';
import { ThemeToggle } from '@/components/shell/theme-toggle';
import { QuickSearch } from '@/components/shell/quick-search';
import { TransactionSheet } from '@/components/ledger/transaction-sheet';
import { initials } from '@/lib/names';
import type { Me } from '@/lib/types';

/**
 * Application shell (context.md §29).
 *
 * Desktop gets a persistent sidebar that can drop to an icon rail when the
 * screen is needed for the ledger. Mobile gets a bottom bar with the five
 * destinations the spec names, and the add button sits in the middle of it
 * where a thumb already is.
 *
 * The sidebar is deliberately quiet: one mark, five words, and a single filled
 * button. Navigation is not the product.
 */

interface NavItem {
  href: string;
  label: string;
  icon: (props: { className?: string }) => ReactNode;
  exact?: boolean;
}

const PRIMARY_NAV: NavItem[] = [
  { href: '/', label: 'Dashboard', icon: HomeIcon, exact: true },
  { href: '/people', label: 'People', icon: PeopleIcon },
  { href: '/activity', label: 'Activity', icon: ActivityIcon },
  { href: '/profile', label: 'Profile', icon: ProfileIcon },
];

const RAIL_KEY = 'accounic:rail';

export function AppShell({ me, children }: { me: Me; children: ReactNode }) {
  const pathname = usePathname();
  const [searchOpen, setSearchOpen] = useState(false);
  const [addOpen, setAddOpen] = useState(false);
  const [rail, setRail] = useState(false);

  // Read after mount so the server and first client render agree.
  useEffect(() => {
    setRail(window.localStorage.getItem(RAIL_KEY) === '1');
  }, []);

  const toggleRail = useCallback(() => {
    setRail((current) => {
      window.localStorage.setItem(RAIL_KEY, current ? '0' : '1');
      return !current;
    });
  }, []);

  const nav = me.is_admin
    ? [...PRIMARY_NAV, { href: '/admin', label: 'Admin', icon: AdminIcon }]
    : PRIMARY_NAV;

  const isActive = useCallback(
    (item: NavItem) => (item.exact ? pathname === item.href : pathname.startsWith(item.href)),
    [pathname],
  );

  // Keyboard first on desktop (context.md §18): ⌘K / Ctrl-K search, N for new.
  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      const target = event.target as HTMLElement | null;
      const typing =
        target?.tagName === 'INPUT' ||
        target?.tagName === 'TEXTAREA' ||
        target?.isContentEditable === true;

      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault();
        setSearchOpen(true);
        return;
      }
      if (!typing && !event.metaKey && !event.ctrlKey && event.key.toLowerCase() === 'n') {
        event.preventDefault();
        setAddOpen(true);
      }
    }
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, []);

  return (
    <ToastProvider>
      <div
        className={cn(
          'min-h-dvh lg:grid',
          rail ? 'lg:grid-cols-[4.75rem_1fr]' : 'lg:grid-cols-[16.5rem_1fr]',
        )}
      >
        {/* ---------------------------------------------------------------- */}
        {/* Desktop sidebar                                                   */}
        {/* ---------------------------------------------------------------- */}
        <aside
          className={cn(
            'sticky top-0 hidden h-dvh flex-col border-r border-line bg-surface lg:flex',
            'transition-[width] duration-[var(--dur-slow)] ease-[var(--ease)]',
          )}
        >
          <div
            className={cn(
              'flex h-16 shrink-0 items-center',
              rail ? 'justify-center px-2' : 'justify-between pl-5 pr-3',
            )}
          >
            {rail ? (
              <Link href="/" aria-label="Accounic — dashboard">
                <AccounicMark id="rail" className="size-7" />
              </Link>
            ) : (
              <Link href="/" aria-label="Accounic — dashboard">
                <AccounicLogo id="side" />
              </Link>
            )}
            {!rail ? (
              <button
                type="button"
                onClick={toggleRail}
                aria-label="Collapse sidebar"
                className="press grid size-8 place-items-center rounded-lg text-ink-faint transition-[background-color,color,transform] duration-[var(--dur-fast)] ease-[var(--ease)] hover:bg-sunken hover:text-ink"
              >
                <ChevronRightIcon className="size-4 rotate-180" />
              </button>
            ) : null}
          </div>

          {/* The primary action sits with the navigation, not at the far end of
              the column.

              It used to be pinned to the bottom, which on a 1080p screen left
              roughly 450px of nothing between the last nav row and the one
              filled button on the page — the two things a reader uses most,
              separated by half a screen of void, with the action closer to the
              taskbar than to the app. Directly under the destinations it is
              where the eye already is, and the remaining space falls above the
              profile footer, where empty space in a column is simply margin. */}
          <div className="px-3 pt-2">
            <button
              type="button"
              onClick={() => setAddOpen(true)}
              aria-label="Add transaction"
              title={rail ? 'Add transaction' : undefined}
              className={cn(
                // Prominent, but sized like a control rather than a banner:
                // 44px is the touch minimum and the same height as a nav row
                // plus its padding, so the sidebar reads as one system (§4).
                'flex w-full items-center justify-center gap-2 rounded-field bg-accent-solid',
                '[background-image:var(--grad-action)] text-[0.875rem] font-semibold text-accent-ink',
                'shadow-[0_1px_0_0_rgb(255_255_255/0.14)_inset,0_6px_16px_-10px_rgb(37_99_235/0.65)]',
                'transition-[filter,transform,box-shadow] duration-[var(--dur)] ease-[var(--ease)]',
                'hover:brightness-110 hover:shadow-[0_1px_0_0_rgb(255_255_255/0.18)_inset,0_10px_22px_-10px_rgb(37_99_235/0.8)]',
                'active:scale-[0.985] motion-reduce:active:scale-100',
                rail ? 'h-11' : 'h-11 px-4',
              )}
            >
              <PlusIcon className="size-4 shrink-0" />
              {!rail ? 'Add transaction' : null}
            </button>
          </div>

          <nav className="flex-1 space-y-0.5 px-3 pt-3">
            {nav.map((item) => {
              const active = isActive(item);
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  aria-current={active ? 'page' : undefined}
                  title={rail ? item.label : undefined}
                  className={cn(
                    'press group relative flex items-center rounded-field text-[0.875rem] font-medium',
                    'transition-[background-color,color,box-shadow,transform] duration-[var(--dur-fast)] ease-[var(--ease)]',
                    rail ? 'h-10 justify-center' : 'gap-3 px-3 py-2.5',
                    // Selected reads as "you are here", not as a button: a tinted
                    // field, a hairline border and the brand rule at the left
                    // edge, rather than a filled block competing with the primary
                    // action below it (§4).
                    active
                      ? 'bg-accent-soft text-accent shadow-[inset_0_0_0_1px_var(--accent-line)]'
                      : 'text-ink-muted hover:bg-sunken hover:text-ink',
                  )}
                >
                  {/* The one place the brand ramp touches navigation. */}
                  <span
                    aria-hidden
                    className={cn(
                      'absolute left-0 top-1/2 h-4 w-[3px] -translate-y-1/2 rounded-r-full brand-fill',
                      'transition-opacity duration-[var(--dur)] ease-[var(--ease)]',
                      active ? 'opacity-100' : 'opacity-0',
                    )}
                  />
                  <item.icon
                    className={cn(
                      'size-[1.125rem] shrink-0 transition-colors duration-[var(--dur)]',
                      active ? 'text-accent' : 'text-ink-faint group-hover:text-ink-muted',
                    )}
                  />
                  {!rail ? item.label : null}
                </Link>
              );
            })}
          </nav>

          <div className="space-y-3 border-t border-line p-3">
            {rail ? (
              <div className="flex flex-col items-center gap-2">
                <button
                  type="button"
                  onClick={toggleRail}
                  aria-label="Expand sidebar"
                  className="press grid size-8 place-items-center rounded-lg text-ink-faint transition-[background-color,color,transform] duration-[var(--dur-fast)] ease-[var(--ease)] hover:bg-sunken hover:text-ink"
                >
                  <ChevronRightIcon className="size-4" />
                </button>
                <Link href="/profile" aria-label={me.name}>
                  <Avatar tone="accent" size="sm">
                    {initials(me.name || me.email)}
                  </Avatar>
                </Link>
              </div>
            ) : (
              <Link
                href="/profile"
                className={cn(
                  'flex items-center gap-2.5 rounded-field border border-line bg-sunken px-2.5 py-2',
                  'transition-[border-color,background-color] duration-[var(--dur)] ease-[var(--ease)]',
                  'hover:border-line-strong',
                )}
              >
                <Avatar tone="accent" size="sm">
                  {initials(me.name || me.email)}
                </Avatar>
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-[0.8125rem] font-medium text-ink">
                    {me.name}
                  </span>
                  <span className="block truncate text-[0.6875rem] text-ink-faint">
                    {me.business_name ?? me.email}
                  </span>
                </span>
              </Link>
            )}
          </div>
        </aside>

        {/* ---------------------------------------------------------------- */}
        {/* Mobile top bar                                                    */}
        {/* ---------------------------------------------------------------- */}
        <div className="flex min-w-0 flex-col">
          <header className="sticky top-0 z-30 flex items-center gap-3 border-b border-line bg-paper/85 px-4 py-3 backdrop-blur-xl lg:hidden">
            <Link href="/" aria-label="Accounic — dashboard">
              <AccounicLogo id="mobile" markClassName="size-6" />
            </Link>
            <button
              type="button"
              onClick={() => setSearchOpen(true)}
              aria-label="Search"
              className="press ml-auto grid size-9 place-items-center rounded-field text-ink-muted transition-[background-color,border-color,color,box-shadow] duration-[var(--dur-fast)] ease-[var(--ease)] hover:bg-sunken hover:text-ink"
            >
              <SearchIcon />
            </button>
            <ThemeToggle />
          </header>

          {/* Desktop top bar. Search is here rather than in the sidebar so the
              navigation column stays purely navigational. */}
          <header className="sticky top-0 z-30 hidden border-b border-line bg-paper/80 px-8 py-3 backdrop-blur-xl lg:block">
            <div className="mx-auto flex w-full max-w-6xl items-center gap-3">
            <button
              type="button"
              onClick={() => setSearchOpen(true)}
              className={cn(
                'flex h-9 w-full max-w-sm items-center gap-2.5 rounded-field border border-line bg-sunken px-3',
                'text-[0.8125rem] text-ink-faint',
                'transition-[border-color,color] duration-[var(--dur)] ease-[var(--ease)]',
                'hover:border-line-strong hover:text-ink-muted',
              )}
            >
              <SearchIcon className="size-4 shrink-0" />
              <span className="flex-1 text-left">Search people, notes, amounts…</span>
              <kbd className="rounded border border-line-strong px-1.5 py-0.5 text-[0.625rem] font-medium">
                ⌘K
              </kbd>
            </button>
            <div className="ml-auto flex items-center gap-2">
              <ThemeToggle />
            </div>
            </div>
          </header>

          <main className="min-w-0 flex-1 pb-24 lg:pb-0">{children}</main>

          {/* -------------------------------------------------------------- */}
          {/* Mobile bottom bar                                               */}
          {/* -------------------------------------------------------------- */}
          <nav className="fixed inset-x-0 bottom-0 z-30 border-t border-line bg-paper/90 pb-[env(safe-area-inset-bottom)] backdrop-blur-xl lg:hidden">
            <div className="mx-auto grid max-w-md grid-cols-5 items-center px-2 py-1.5">
              <BottomLink item={PRIMARY_NAV[0]!} active={isActive(PRIMARY_NAV[0]!)} />
              <BottomLink item={PRIMARY_NAV[1]!} active={isActive(PRIMARY_NAV[1]!)} />

              <div className="flex justify-center">
                <button
                  type="button"
                  onClick={() => setAddOpen(true)}
                  aria-label="Add transaction"
                  className="-mt-5 grid size-12 place-items-center rounded-2xl bg-accent-solid [background-image:var(--grad-action)] text-accent-ink shadow-[var(--shadow-pop)] transition-[filter,transform,box-shadow] duration-[var(--dur-tap)] ease-[var(--ease)] hover:brightness-110 active:scale-95 motion-reduce:active:scale-100"
                >
                  <PlusIcon className="size-5" />
                </button>
              </div>

              <BottomLink item={PRIMARY_NAV[2]!} active={isActive(PRIMARY_NAV[2]!)} />
              <BottomLink item={PRIMARY_NAV[3]!} active={isActive(PRIMARY_NAV[3]!)} />
            </div>
          </nav>
        </div>

        <QuickSearch open={searchOpen} onClose={() => setSearchOpen(false)} currency={me.currency} />
        <TransactionSheet
          open={addOpen}
          onClose={() => setAddOpen(false)}
          currency={me.currency}
          mode="create"
        />
      </div>
    </ToastProvider>
  );
}

function BottomLink({ item, active }: { item: NavItem; active: boolean }) {
  return (
    <Link
      href={item.href}
      aria-current={active ? 'page' : undefined}
      className={cn(
        'press flex flex-col items-center gap-0.5 rounded-field py-1.5 text-[0.625rem] font-medium',
        'transition-[color,transform] duration-[var(--dur-fast)] ease-[var(--ease)]',
        active ? 'text-accent' : 'text-ink-faint',
      )}
    >
      <item.icon className="size-5" />
      {item.label}
    </Link>
  );
}
