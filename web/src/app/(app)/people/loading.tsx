import { Card, Skeleton } from '@/components/ui/primitives';

export default function PeopleLoading() {
  return (
    <div className="mx-auto w-full max-w-5xl px-4 py-6 sm:px-6 lg:px-8 lg:py-9">
      <div className="mb-6 flex items-end justify-between gap-4">
        <div className="space-y-2">
          <Skeleton className="h-7 w-32" />
          <Skeleton className="h-4 w-52" />
        </div>
        <Skeleton className="h-10 w-32" />
      </div>

      <Card className="mb-4 flex flex-wrap items-center gap-8 px-5 py-4">
        <div className="space-y-2">
          <Skeleton className="h-3 w-20" />
          <Skeleton className="h-5 w-24" />
        </div>
        <div className="space-y-2">
          <Skeleton className="h-3 w-16" />
          <Skeleton className="h-5 w-24" />
        </div>
        <Skeleton className="h-1 min-w-32 flex-1 rounded-full" />
      </Card>

      <Skeleton className="h-10 w-full" />

      <Card className="mt-3 overflow-hidden">
        <ul className="divide-y divide-line">
          {[0, 1, 2, 3, 4, 5].map((row) => (
            <li key={row} className="flex items-center gap-3 px-4 py-3 sm:px-5">
              <Skeleton className="size-10 rounded-xl" />
              <div className="flex-1 space-y-1.5">
                <Skeleton className="h-4 w-40" />
                <Skeleton className="h-3 w-28" />
              </div>
              <Skeleton className="h-8 w-24" />
            </li>
          ))}
        </ul>
      </Card>
    </div>
  );
}
