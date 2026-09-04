'use client';

import { useState } from 'react';

import { buttonClass, segmentClass, SEGMENT_GROUP } from '@/components/ui/primitives';
import { DateRangeField } from '@/components/ui/date-picker';

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
  // "All time" is the default and has to be sayable, not merely the state you
  // are left in by clearing the dates: a period control with no way back to
  // "everything" reads as though a date range were required.
  const [period, setPeriod] = useState<'all' | 'range'>('all');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [includeVoid, setIncludeVoid] = useState(false);

  function href(format: 'pdf' | 'csv' | 'json'): string {
    const params = new URLSearchParams({ format, scope });
    if (period === 'range') {
      if (from) params.set('from', from);
      if (to) params.set('to', to);
    }
    if (includeVoid) params.set('void', '1');
    return `/api/export?${params.toString()}`;
  }

  return (
    <div className="space-y-4">
      <div>
        <span className="mb-1.5 block text-[0.75rem] font-medium text-ink-muted">Period</span>
        <div className={SEGMENT_GROUP} role="group" aria-label="Which dates to export">
          {(
            [
              ['all', 'All time'],
              ['range', 'Date range'],
            ] as const
          ).map(([value, label]) => (
            <button
              key={value}
              type="button"
              onClick={() => setPeriod(value)}
              aria-current={period === value ? 'true' : undefined}
              className={segmentClass(period === value)}
            >
              {label}
            </button>
          ))}
        </div>
        {period === 'range' ? (
          <div className="mt-2.5">
            <DateRangeField
              value={{ from, to }}
              onChange={(next) => {
                setFrom(next.from);
                setTo(next.to);
              }}
            />
          </div>
        ) : null}
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
            className={`tap press h-8 rounded-full border px-3 text-[0.8125rem] transition-[background-color,border-color,color,box-shadow] duration-[var(--dur-fast)] ease-[var(--ease)] ${
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
