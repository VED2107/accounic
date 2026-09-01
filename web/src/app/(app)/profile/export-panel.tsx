'use client';

import { useState } from 'react';

import { buttonClass } from '@/components/ui/primitives';

/**
 * Exporting the workspace from the browser (Phases 4 and 5).
 *
 * Deliberately not the phone's sheet rebuilt in HTML. A browser already has a
 * download manager, a file picker and a back button, so this is three links and
 * a couple of filters — the work happens at `/api/export`, which streams the
 * file with a Content-Disposition and never renders anything.
 *
 * The three formats say what they are for rather than what they are, because
 * "CSV" answers a question nobody asked and "for a spreadsheet" answers the one
 * they did.
 */
export function ExportPanel() {
  const [scope, setScope] = useState<'all' | 'regular' | 'opening'>('all');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [includeVoid, setIncludeVoid] = useState(false);

  function href(format: 'pdf' | 'csv' | 'json'): string {
    const params = new URLSearchParams({ format, scope });
    if (from) params.set('from', from);
    if (to) params.set('to', to);
    if (includeVoid) params.set('void', '1');
    return `/api/export?${params.toString()}`;
  }

  return (
    <div className="space-y-4">
      <div className="grid gap-3 sm:grid-cols-2">
        <label className="block">
          <span className="mb-1 block text-[0.75rem] font-medium text-ink-muted">From</span>
          <input
            type="date"
            value={from}
            onChange={(event) => setFrom(event.target.value)}
            className="h-9 w-full rounded-lg border border-line bg-surface px-2.5 text-[0.8125rem] text-ink"
          />
        </label>
        <label className="block">
          <span className="mb-1 block text-[0.75rem] font-medium text-ink-muted">To</span>
          <input
            type="date"
            value={to}
            onChange={(event) => setTo(event.target.value)}
            className="h-9 w-full rounded-lg border border-line bg-surface px-2.5 text-[0.8125rem] text-ink"
          />
        </label>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        {(
          [
            ['all', 'Everything'],
            ['regular', 'Transactions'],
            ['opening', 'Opening balances'],
          ] as const
        ).map(([value, label]) => (
          <button
            key={value}
            type="button"
            onClick={() => setScope(value)}
            aria-pressed={scope === value}
            className={`h-8 rounded-full border px-3 text-[0.8125rem] transition ${
              scope === value
                ? 'border-line-strong bg-surface-raised text-ink'
                : 'border-line text-ink-muted hover:text-ink'
            }`}
          >
            {label}
          </button>
        ))}
      </div>

      <label className="flex items-center gap-2 text-[0.8125rem] text-ink-muted">
        <input
          type="checkbox"
          checked={includeVoid}
          onChange={(event) => setIncludeVoid(event.target.checked)}
          className="size-4 rounded border-line"
        />
        Include voided history
      </label>

      <div className="grid gap-2 sm:grid-cols-3">
        {(
          [
            ['pdf', 'PDF report'],
            ['csv', 'Spreadsheet'],
            ['json', 'Backup'],
          ] as const
        ).map(([format, label]) => (
          <a
            key={format}
            href={href(format)}
            download
            className={buttonClass('secondary', 'md', 'justify-center')}
          >
            {label}
          </a>
        ))}
      </div>

      <p className="text-[0.75rem] text-ink-faint">
        The PDF is a printable report; the spreadsheet is one row per entry; the backup keeps
        every field, so it can be read back later. Amounts stay in the currency they were
        entered in.
      </p>
    </div>
  );
}
