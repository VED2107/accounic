import Link from 'next/link';
import { DownloadIcon } from '@/components/icons';

/**
 * Export this account as a PDF (upgrade §47).
 *
 * A plain link, not a button with a fetch behind it. The route returns a file,
 * so the browser's own handling — open in a tab, save, print — is exactly the
 * behaviour wanted, and it works with JavaScript disabled and with a middle
 * click. Nothing here needs to be a client component.
 */
export function StatementButton({
  personId,
  personName,
}: {
  personId: string;
  personName: string;
}) {
  return (
    <Link
      href={`/people/${personId}/statement`}
      target="_blank"
      rel="noopener"
      prefetch={false}
      aria-label={`Export ${personName}'s statement as a PDF`}
      className="inline-flex items-center gap-1.5 rounded-field border border-line-strong bg-surface px-3 py-1.5 text-[0.75rem] font-medium text-ink-muted transition-[color,border-color,background-color] duration-[var(--dur)] hover:bg-sunken hover:text-ink"
    >
      <DownloadIcon className="size-3.5" />
      Export PDF
    </Link>
  );
}
