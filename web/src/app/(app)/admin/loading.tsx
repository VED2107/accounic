import { Card, Skeleton } from '@/components/ui/primitives';

export default function AdminLoading() {
  return (
    <div className="mx-auto w-full max-w-5xl px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
      <div className="mb-6 space-y-2">
        <Skeleton className="h-3.5 w-28" />
        <Skeleton className="h-7 w-56" />
        <Skeleton className="h-4 w-96 max-w-full" />
      </div>

      <Card className="mb-4 grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6">
        {[0, 1, 2, 3, 4, 5].map((i) => (
          <div key={i} className="space-y-2 px-4 py-3">
            <Skeleton className="h-3 w-16" />
            <Skeleton className="h-4 w-20" />
          </div>
        ))}
      </Card>

      <Skeleton className="mb-3 h-10 w-full" />

      <Card className="overflow-hidden">
        <ul className="divide-y divide-line">
          {[0, 1, 2].map((row) => (
            <li key={row} className="flex items-center gap-3 px-4 py-3 sm:px-5">
              <Skeleton className="size-10 rounded-xl" />
              <div className="flex-1 space-y-1.5">
                <Skeleton className="h-4 w-40" />
                <Skeleton className="h-3 w-56" />
              </div>
              <Skeleton className="h-8 w-44" />
            </li>
          ))}
        </ul>
      </Card>
    </div>
  );
}
