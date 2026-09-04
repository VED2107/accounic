import Link from 'next/link';

export default function NotFound() {
  return (
    <div className="grid min-h-dvh place-items-center px-6">
      <div className="w-full max-w-sm text-center">
        <h1 className="text-lg font-semibold tracking-tight">Page not found</h1>
        <p className="mt-1.5 text-sm text-ink-muted">
          That page does not exist in this workspace.
        </p>
        <Link
          href="/"
          className="press mt-6 inline-flex h-10 items-center rounded-lg bg-accent px-4 text-sm font-medium text-accent-ink transition-[background-color,border-color,color,box-shadow] duration-[var(--dur-fast)] ease-[var(--ease)] hover:bg-accent-hover"
        >
          Go to dashboard
        </Link>
      </div>
    </div>
  );
}
