'use client';

import { useEffect, useState } from 'react';
import { MoonIcon, MonitorIcon, SunIcon } from '@/components/icons';
import { cn } from '@/components/ui/primitives';
import { THEME_EVENT, applyTheme, readTheme, type ThemeChoice } from '@/lib/theme';

const ORDER: ThemeChoice[] = ['system', 'light', 'dark'];
const LABEL: Record<ThemeChoice, string> = {
  system: 'Match system',
  light: 'Light',
  dark: 'Dark',
};

/** Header control. Cycles system → light → dark, and says which it is on. */
export function ThemeToggle({ className }: { className?: string }) {
  const [choice, setChoice] = useState<ThemeChoice>('system');

  useEffect(() => {
    setChoice(readTheme());
    const onChange = (event: Event) => setChoice((event as CustomEvent<ThemeChoice>).detail);
    window.addEventListener(THEME_EVENT, onChange);
    return () => window.removeEventListener(THEME_EVENT, onChange);
  }, []);

  function next() {
    const target = ORDER[(ORDER.indexOf(choice) + 1) % ORDER.length]!;
    applyTheme(target);
    setChoice(target);
  }

  const Icon = choice === 'light' ? SunIcon : choice === 'dark' ? MoonIcon : MonitorIcon;

  return (
    <button
      type="button"
      onClick={next}
      title={`Appearance: ${LABEL[choice]}`}
      aria-label={`Appearance: ${LABEL[choice]}. Change.`}
      className={cn(
        'grid size-9 place-items-center rounded-field border border-line bg-sunken text-ink-muted',
        'transition-[color,border-color] duration-[var(--dur)] ease-[var(--ease)]',
        'hover:border-line-strong hover:text-ink',
        className,
      )}
    >
      <Icon className="size-4" />
    </button>
  );
}

/** The same choice, as a labelled row for Profile → Preferences. */
export function ThemeChooser() {
  const [choice, setChoice] = useState<ThemeChoice>('system');

  useEffect(() => {
    setChoice(readTheme());
    const onChange = (event: Event) => setChoice((event as CustomEvent<ThemeChoice>).detail);
    window.addEventListener(THEME_EVENT, onChange);
    return () => window.removeEventListener(THEME_EVENT, onChange);
  }, []);

  return (
    <div
      className="inline-flex items-center gap-0.5 rounded-field border border-line bg-sunken p-0.5"
      role="group"
      aria-label="Appearance"
    >
      {ORDER.map((option) => {
        const Icon = option === 'light' ? SunIcon : option === 'dark' ? MoonIcon : MonitorIcon;
        const active = choice === option;
        return (
          <button
            key={option}
            type="button"
            onClick={() => {
              applyTheme(option);
              setChoice(option);
            }}
            aria-pressed={active}
            className={cn(
              'flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-[0.8125rem] font-medium',
              'transition-[background-color,color] duration-[var(--dur)] ease-[var(--ease)]',
              active ? 'bg-surface text-ink shadow-[var(--shadow-card)]' : 'text-ink-muted hover:text-ink',
            )}
          >
            <Icon className="size-4" />
            {LABEL[option]}
          </button>
        );
      })}
    </div>
  );
}
