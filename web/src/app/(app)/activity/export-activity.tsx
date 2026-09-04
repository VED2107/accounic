'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import { Modal } from '@/components/ui/modal';
import { Button, Spinner, cn, segmentClass, SEGMENT_GROUP } from '@/components/ui/primitives';
import { useToast } from '@/components/ui/toast';
import { ChevronRightIcon, DownloadIcon, ReportIcon, TableIcon } from '@/components/icons';
import { DateRangeField } from '@/components/ui/date-picker';
import {
  activityScopeLabel,
  ALL_ACTIVITY,
  dayRange,
  rangeIsBackwards,
  VIEW_LABEL,
  type ActivityRange,
  type ActivityView,
} from '@/lib/export/activity';
import { countActivityForExport } from './export-actions';

/**
 * Exporting the Activity feed.
 *
 * The document this produces is the screen it was opened from: the same days in
 * the same order, holding the same entries. So the dialog asks the two
 * questions that decide which part of the feed goes in the file, and keeps them
 * separate, because they are separate:
 *
 *     DATE      this day · a range · all activity
 *     CATEGORY  Everything · Transactions · Settlements
 *
 * They compose freely — a range of settlements, one day of transactions — and
 * the count under them is re-asked of the database every time either moves, so
 * the number above the button is always the number of rows in the file.
 *
 * Opened from a day heading, the date starts on that day. Opened from the page
 * header it starts on the whole feed, and the category starts on whichever tab
 * is showing. Neither is a guess: both are what the user was already looking at.
 *
 * It fetches rather than linking, unlike the Profile panel's plain download
 * links: a dialog has to be able to say "preparing", "that failed, try again"
 * and "saved", and a link can say none of the three. The route is still the
 * only thing that builds a file.
 */

type Format = 'pdf' | 'csv';
type DateScope = 'day' | 'range' | 'all';

const FORMATS: Array<{
  format: Format;
  label: string;
  description: string;
  Icon: typeof ReportIcon;
}> = [
  { format: 'pdf', label: 'PDF', description: 'Activity report, day by day', Icon: ReportIcon },
  { format: 'csv', label: 'CSV', description: 'Spreadsheet, one row per entry', Icon: TableIcon },
];

function href(format: Format, view: ActivityView, range: ActivityRange): string {
  const params = new URLSearchParams({ format, view });
  if (range.from) params.set('from', range.from);
  if (range.to) params.set('to', range.to);
  return `/api/export/activity?${params.toString()}`;
}

/** The filename the route chose, or a sane fallback if the header is missing. */
function filenameFrom(disposition: string | null, format: Format): string {
  const match = disposition?.match(/filename="?([^";]+)"?/i);
  return match?.[1] ?? `accounic-activity.${format}`;
}

/* -------------------------------------------------------------------------- */
/* Triggers                                                                    */
/* -------------------------------------------------------------------------- */

/** The page header's action: the whole feed, in the tab that is showing. */
export function ExportActivityButton({
  view,
  hasEntries,
}: {
  view: ActivityView;
  hasEntries: boolean;
}) {
  const [open, setOpen] = useState(false);

  return (
    <>
      <Button
        type="button"
        variant="secondary"
        size="sm"
        onClick={() => setOpen(true)}
        aria-haspopup="dialog"
      >
        <DownloadIcon className="size-4" />
        Export
      </Button>
      {open ? (
        <ExportDialog
          initialView={view}
          day={null}
          dayLabel={null}
          hasEntries={hasEntries}
          onClose={() => setOpen(false)}
        />
      ) : null}
    </>
  );
}

/**
 * A day heading's action: that day, already chosen.
 *
 * Deliberately small and quiet. The day headings are structure, not chrome, and
 * a control loud enough to compete with them would turn a readable feed into a
 * column of buttons.
 */
export function ExportDayButton({
  view,
  day,
  dayLabel,
}: {
  view: ActivityView;
  day: string;
  dayLabel: string;
}) {
  const [open, setOpen] = useState(false);

  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        aria-haspopup="dialog"
        aria-label={`Export ${dayLabel}`}
        className={cn(
          'tap press grid size-7 shrink-0 place-items-center rounded-lg text-ink-faint',
          'transition-[background-color,color,opacity] duration-[var(--dur-fast)] ease-[var(--ease)]',
          'hover:bg-sunken hover:text-ink',
          // Visible on touch, and on hover or focus at a pointer: the day it
          // sits beside is the subject, not this.
          'opacity-100 sm:opacity-0 sm:group-hover/day:opacity-100 sm:focus-visible:opacity-100',
        )}
      >
        <DownloadIcon className="size-3.5" />
      </button>
      {open ? (
        <ExportDialog
          initialView={view}
          day={day}
          dayLabel={dayLabel}
          hasEntries
          onClose={() => setOpen(false)}
        />
      ) : null}
    </>
  );
}

/* -------------------------------------------------------------------------- */
/* Dialog                                                                      */
/* -------------------------------------------------------------------------- */

function Label({ children }: { children: React.ReactNode }) {
  return (
    <p className="mb-1.5 text-[0.6875rem] font-semibold uppercase tracking-wider text-ink-faint">
      {children}
    </p>
  );
}

function ExportDialog({
  initialView,
  day,
  dayLabel,
  hasEntries,
  onClose,
}: {
  initialView: ActivityView;
  day: string | null;
  dayLabel: string | null;
  hasEntries: boolean;
  onClose: () => void;
}) {
  const toast = useToast();

  const [view, setView] = useState<ActivityView>(initialView);
  const [dateScope, setDateScope] = useState<DateScope>(day ? 'day' : 'all');
  // The range starts on the day it was opened from, so switching to "Date
  // range" begins somewhere meaningful rather than on two empty fields.
  const [from, setFrom] = useState(day ?? '');
  const [to, setTo] = useState(day ?? '');

  const [count, setCount] = useState<number | null>(null);
  const [countError, setCountError] = useState<string | null>(null);
  const [busy, setBusy] = useState<Format | null>(null);
  const [error, setError] = useState<string | null>(null);
  const alive = useRef(true);

  const range: ActivityRange = useMemo(() => {
    if (dateScope === 'all') return ALL_ACTIVITY;
    if (dateScope === 'day') return day ? dayRange(day) : ALL_ACTIVITY;
    return { from: from || null, to: to || null };
  }, [dateScope, day, from, to]);

  const backwards = rangeIsBackwards(range);
  // A half-filled range is not an error, it is an unfinished thought: nothing
  // is counted or exported until both ends are there.
  const incomplete = dateScope === 'range' && (!range.from || !range.to);
  const blocked = backwards || incomplete;

  useEffect(() => {
    alive.current = true;
    return () => {
      alive.current = false;
    };
  }, []);

  // The count is re-asked whenever either choice moves: a number that described
  // the previous choice would be a lie, and a stale one is worse than none.
  useEffect(() => {
    let current = true;
    setCount(null);
    setCountError(null);

    if (blocked) return;

    // A feed with nothing in it needs no round trip to be counted.
    if (!hasEntries && range.from === null && range.to === null) {
      setCount(0);
      return;
    }

    void countActivityForExport(view, range).then((result) => {
      if (!current || !alive.current) return;
      if (result.ok) setCount(result.count);
      else setCountError(result.error);
    });

    return () => {
      current = false;
    };
  }, [view, range, blocked, hasEntries]);

  const empty = count === 0;

  const run = useCallback(
    async (format: Format) => {
      // One export at a time. A second click while the first is in flight would
      // build the same file twice on the server and save whichever finished
      // last: a race and a bill, for no benefit.
      if (busy || blocked) return;
      setBusy(format);
      setError(null);

      try {
        const response = await fetch(href(format, view, range), { cache: 'no-store' });

        if (!response.ok) {
          // The route answers a failure as JSON, and its message never carries
          // ledger data or anything about the database.
          const body = (await response.json().catch(() => null)) as { error?: string } | null;
          throw new Error(
            typeof body?.error === 'string' && body.error.trim() !== ''
              ? body.error
              : 'The export could not be built. Nothing has been saved.',
          );
        }

        const blob = await response.blob();
        const filename = filenameFrom(response.headers.get('Content-Disposition'), format);

        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = url;
        link.download = filename;
        document.body.appendChild(link);
        link.click();
        link.remove();
        // Revoked later, not now: Safari has not finished reading the blob when
        // click() returns, and revoking synchronously cancels the save.
        window.setTimeout(() => URL.revokeObjectURL(url), 4000);

        if (!alive.current) return;
        setBusy(null);
        toast.show({ title: 'Export ready', body: filename, tone: 'success' });
        onClose();
      } catch (cause) {
        if (!alive.current) return;
        setBusy(null);
        setError(
          cause instanceof Error && cause.message
            ? cause.message
            : 'The export could not be built. Nothing has been saved.',
        );
      }
    },
    [blocked, busy, onClose, range, toast, view],
  );

  const summary = busy
    ? 'Preparing your file…'
    : backwards
      ? 'The start of the range is after its end'
      : incomplete
        ? 'Pick both ends of the range'
        : empty
          ? 'No activity to export'
          : count === null
            ? countError
              ? 'The number of entries could not be checked'
              : 'Counting…'
            : `${count.toLocaleString()} ${count === 1 ? 'entry' : 'entries'}`;

  const dateOptions: Array<[DateScope, string]> = [
    ...(day ? ([['day', dayLabel ?? 'This day']] as Array<[DateScope, string]>) : []),
    ['range', 'Date range'],
    ['all', 'All activity'],
  ];

  return (
    <Modal
      open
      onClose={() => {
        if (busy) return;
        onClose();
      }}
      title="Export activity"
      description="Your activity as it reads on screen: day by day, newest first."
    >
      <div className="space-y-4">
        <div>
          <Label>Date</Label>
          <div className={SEGMENT_GROUP} role="group" aria-label="Which dates to export">
            {dateOptions.map(([value, label]) => (
              <button
                key={value}
                type="button"
                onClick={() => setDateScope(value)}
                disabled={busy !== null}
                aria-current={dateScope === value ? 'true' : undefined}
                className={segmentClass(dateScope === value)}
              >
                {label}
              </button>
            ))}
          </div>

          {dateScope === 'range' ? (
            <div className="mt-2.5">
              <DateRangeField
                value={{ from, to }}
                onChange={(next) => {
                  setFrom(next.from);
                  setTo(next.to);
                }}
                disabled={busy !== null}
              />
            </div>
          ) : null}
        </div>

        <div>
          <Label>Category</Label>
          <div className={SEGMENT_GROUP} role="group" aria-label="Which entries to export">
            {(['all', 'transaction', 'settlement'] as const).map((value) => (
              <button
                key={value}
                type="button"
                onClick={() => setView(value)}
                disabled={busy !== null}
                aria-current={view === value ? 'true' : undefined}
                className={segmentClass(view === value)}
              >
                {VIEW_LABEL[value]}
              </button>
            ))}
          </div>
        </div>

        <div
          className="overflow-hidden rounded-card border border-line"
          role="group"
          aria-label="Export format"
        >
          {FORMATS.map(({ format, label, description, Icon }, index) => {
            const pending = busy === format;
            const disabled = empty || blocked || (busy !== null && !pending);

            return (
              <button
                key={format}
                type="button"
                data-autofocus={index === 0 ? 'true' : undefined}
                disabled={disabled || pending}
                aria-busy={pending}
                onClick={() => void run(format)}
                className={cn(
                  'tap flex w-full items-center gap-3 px-4 py-3.5 text-left',
                  'transition-[background-color,color] duration-[var(--dur-fast)] ease-[var(--ease)]',
                  index > 0 && 'border-t border-line',
                  disabled || pending ? 'cursor-not-allowed opacity-55' : 'press hover:bg-sunken',
                )}
              >
                <span
                  aria-hidden
                  className="grid size-9 shrink-0 place-items-center rounded-field border border-line bg-sunken text-ink-muted"
                >
                  <Icon className="size-[1.125rem]" />
                </span>
                <span className="min-w-0 flex-1">
                  <span className="block text-sm font-semibold text-ink">{label}</span>
                  <span className="block truncate text-[0.75rem] text-ink-muted">
                    {description}
                  </span>
                </span>
                {pending ? (
                  <Spinner className="text-ink-muted" />
                ) : (
                  <ChevronRightIcon aria-hidden className="size-4 shrink-0 text-ink-faint" />
                )}
              </button>
            );
          })}
        </div>

        {error ? (
          <p role="alert" className="text-[0.8125rem] leading-relaxed text-payable">
            {error} You can try again.
          </p>
        ) : null}

        <div className="space-y-0.5 text-[0.8125rem]">
          <p
            className={cn('font-medium', blocked ? 'text-payable' : 'text-ink')}
            role={blocked ? 'alert' : undefined}
            aria-live="polite"
          >
            {summary}
          </p>
          <p className="text-ink-faint">
            {empty
              ? 'There is nothing in this view to put in a file.'
              : `${VIEW_LABEL[view]} · ${activityScopeLabel(range).toLowerCase()}`}
          </p>
        </div>

        <div className="flex justify-end">
          <Button type="button" variant="secondary" onClick={onClose} disabled={busy !== null}>
            Cancel
          </Button>
        </div>
      </div>
    </Modal>
  );
}
