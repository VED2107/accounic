import Link from 'next/link';
import { Card, EmptyState } from '@/components/ui/primitives';
import { PeopleIcon } from '@/components/icons';

export default function PersonNotFound() {
  return (
    <div className="mx-auto w-full max-w-2xl px-4 py-16 sm:px-6">
      <Card>
        <EmptyState
          icon={<PeopleIcon />}
          title="That account is not here"
          description="It may have been deleted, or it belongs to a different workspace."
          action={
            <Link
              href="/people"
              className="press inline-flex h-10 items-center rounded-lg bg-accent px-4 text-sm font-medium text-accent-ink transition-[background-color,border-color,color,box-shadow] duration-[var(--dur-fast)] ease-[var(--ease)] hover:bg-accent-hover"
            >
              Back to people
            </Link>
          }
        />
      </Card>
    </div>
  );
}
