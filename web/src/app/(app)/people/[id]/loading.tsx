import { Card, Panel, Skeleton } from '@/components/ui/primitives';

export default function PersonLoading() {
  return (
    <div className="mx-auto w-full max-w-4xl px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
      <Skeleton className="mb-4 h-3.5 w-16" />

      <div className="mb-4 flex items-start gap-4">
        <Skeleton className="size-14 rounded-2xl" />
        <div className="flex-1 space-y-2">
          <Skeleton className="h-7 w-56" />
          <Skeleton className="h-4 w-40" />
        </div>
      </div>

      <Panel>
        <div className="flex flex-wrap items-end justify-between gap-5 px-5 py-6 sm:px-6">
          <div className="space-y-3">
            <Skeleton className="h-4 w-32" />
            <Skeleton className="h-10 w-52" />
            <Skeleton className="h-4 w-28" />
          </div>
          <Skeleton className="h-12 w-56" />
        </div>
        <div className="border-t border-line px-5 py-4 sm:px-6">
          <Skeleton className="h-10 w-72" />
        </div>
        <div className="grid grid-cols-2 border-t border-line sm:grid-cols-4">
          {[0, 1, 2, 3].map((i) => (
            <div key={i} className="space-y-2 px-4 py-3.5 sm:px-5">
              <Skeleton className="h-3 w-24" />
              <Skeleton className="h-5 w-20" />
            </div>
          ))}
        </div>
      </Panel>

      <div className="mt-6 space-y-3">
        <Skeleton className="h-10 w-56" />
        <Card className="overflow-hidden">
          <ul className="divide-y divide-line">
            {[0, 1, 2, 3].map((row) => (
              <li key={row} className="flex items-center gap-3 px-4 py-3 sm:px-5">
                <Skeleton className="size-9 rounded-field" />
                <div className="flex-1 space-y-1.5">
                  <Skeleton className="h-4 w-32" />
                  <Skeleton className="h-3 w-44" />
                </div>
                <Skeleton className="h-4 w-20" />
              </li>
            ))}
          </ul>
        </Card>
      </div>
    </div>
  );
}
