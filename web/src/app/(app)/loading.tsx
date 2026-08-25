import { Card, Skeleton } from '@/components/ui/primitives';

/**
 * Dashboard skeleton (context.md §27). Mirrors the real layout closely enough
 * that nothing moves when the data lands — the point of a skeleton is that the
 * page does not jump, not that something is spinning.
 */
export default function DashboardLoading() {
  return (
    <div className="mx-auto w-full max-w-6xl px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
      <div className="mb-6 space-y-2">
        <Skeleton className="h-4 w-32" />
        <Skeleton className="h-7 w-64" />
      </div>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {[0, 1, 2].map((i) => (
          <Card key={i} className="p-5">
            <Skeleton className="h-7 w-28" />
            <div className="mt-3 flex items-end justify-between gap-4">
              <div className="flex-1 space-y-2">
                <Skeleton className="h-7 w-32" />
                <Skeleton className="h-3.5 w-28" />
              </div>
              <Skeleton className="h-8 w-24" />
            </div>
            <div className="mt-4 border-t border-line pt-2.5">
              <Skeleton className="h-3 w-40" />
            </div>
          </Card>
        ))}
      </div>

      {/* The 30-day chart. Its own height is reserved so the two cards below
          do not jump up the page when the buckets land. */}
      <Card className="mt-4 overflow-hidden">
        <div className="border-b border-line px-5 py-3.5">
          <Skeleton className="h-4 w-32" />
        </div>
        <div className="px-5 py-5">
          <div className="mb-4 flex flex-wrap gap-x-5 gap-y-1.5">
            {[0, 1, 2].map((i) => (
              <Skeleton key={i} className="h-4 w-32" />
            ))}
          </div>
          <Skeleton className="h-28 w-full rounded-md" />
          <div className="mt-2 flex justify-between">
            <Skeleton className="h-3 w-12" />
            <Skeleton className="h-3 w-12" />
          </div>
        </div>
      </Card>

      <div className="mt-4 grid gap-4 lg:grid-cols-[1.05fr_1fr]">
        {[0, 1].map((card) => (
          <Card key={card} className="overflow-hidden">
            <div className="border-b border-line px-5 py-3.5">
              <Skeleton className="h-4 w-40" />
            </div>
            <ul className="divide-y divide-line">
              {[0, 1, 2, 3, 4].map((row) => (
                <li key={row} className="flex items-center gap-3 px-5 py-3">
                  <Skeleton className="size-10 rounded-xl" />
                  <div className="flex-1 space-y-1.5">
                    <Skeleton className="h-4 w-1/2" />
                    <Skeleton className="h-3 w-1/3" />
                  </div>
                  <Skeleton className="h-8 w-20" />
                </li>
              ))}
            </ul>
          </Card>
        ))}
      </div>
    </div>
  );
}
