import { Card, Skeleton } from '@/components/ui/primitives';

export default function ProfileLoading() {
  return (
    <div className="mx-auto w-full max-w-4xl px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
      <div className="mb-6 space-y-2">
        <Skeleton className="h-7 w-28" />
        <Skeleton className="h-4 w-64" />
      </div>

      <Card className="mb-4 flex items-center gap-4 px-5 py-4">
        <Skeleton className="size-14 rounded-2xl" />
        <div className="flex-1 space-y-2">
          <Skeleton className="h-5 w-40" />
          <Skeleton className="h-3.5 w-64" />
        </div>
      </Card>

      <div className="grid items-start gap-4 lg:grid-cols-[1.15fr_1fr]">
        <Card className="overflow-hidden">
          <div className="space-y-2 border-b border-line px-5 py-3.5">
            <Skeleton className="h-4 w-28" />
            <Skeleton className="h-3.5 w-56" />
          </div>
          <div className="space-y-4 px-5 py-4">
            <Skeleton className="h-3 w-20" />
            <div className="grid gap-4 sm:grid-cols-2">
              <Skeleton className="h-16 w-full" />
              <Skeleton className="h-16 w-full" />
            </div>
            <div className="grid gap-4 sm:grid-cols-2">
              <Skeleton className="h-16 w-full" />
              <Skeleton className="h-16 w-full" />
            </div>
            <Skeleton className="h-10 w-32" />
          </div>
        </Card>

        <div className="space-y-4">
          {[0, 1, 2].map((card) => (
            <Card key={card} className="space-y-3 px-5 py-4">
              <Skeleton className="h-4 w-28" />
              <Skeleton className="h-10 w-full" />
            </Card>
          ))}
        </div>
      </div>
    </div>
  );
}
