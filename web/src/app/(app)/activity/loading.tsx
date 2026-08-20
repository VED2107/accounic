import { Card, Skeleton } from '@/components/ui/primitives';

export default function ActivityLoading() {
  return (
    <div className="mx-auto w-full max-w-4xl px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
      <div className="mb-6 space-y-2">
        <Skeleton className="h-7 w-32" />
        <Skeleton className="h-4 w-48" />
      </div>

      <div className="grid gap-3 sm:grid-cols-3">
        {[0, 1, 2].map((i) => (
          <Card key={i} className="space-y-2 px-4 py-3.5">
            <Skeleton className="h-3 w-24" />
            <Skeleton className="h-6 w-28" />
          </Card>
        ))}
      </div>

      <Skeleton className="mt-4 h-10 w-72" />

      <div className="mt-4 space-y-5">
        {[0, 1].map((group) => (
          <div key={group}>
            <Skeleton className="mb-2 h-3 w-24" />
            <Card className="overflow-hidden">
              <ul className="divide-y divide-line">
                {[0, 1, 2, 3].map((row) => (
                  <li key={row} className="flex items-center gap-3 px-4 py-3 sm:px-5">
                    <Skeleton className="size-9 rounded-[0.625rem]" />
                    <div className="flex-1 space-y-1.5">
                      <Skeleton className="h-4 w-36" />
                      <Skeleton className="h-3 w-44" />
                    </div>
                    <Skeleton className="h-4 w-20" />
                  </li>
                ))}
              </ul>
            </Card>
          </div>
        ))}
      </div>
    </div>
  );
}
