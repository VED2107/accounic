import { cn } from '@/components/ui/primitives';

/**
 * A sparkline (context.md §30 — reporting stays out of v1; this is context, not
 * a report).
 *
 * Hand-drawn SVG rather than a charting library: it is one path, it renders on
 * the server, and it costs nothing at runtime. No axes, no grid, no tooltip —
 * the shape is the whole message, and the figure beside it carries the value.
 *
 * Deliberately marked aria-hidden. Everything it shows is already stated in
 * words next to it, so announcing it again would only add noise.
 */
export function Sparkline({
  points,
  tone = 'accent',
  className,
  area = true,
  id,
}: {
  points: number[];
  tone?: 'receivable' | 'payable' | 'accent';
  className?: string;
  area?: boolean;
  /** Unique per instance — gradient ids are global. */
  id: string;
}) {
  if (points.length < 2) return null;

  const width = 100;
  const height = 32;
  const pad = 2;

  const min = Math.min(...points);
  const max = Math.max(...points);
  const span = max - min || 1;

  const coords = points.map((value, index) => {
    const x = (index / (points.length - 1)) * width;
    const y = height - pad - ((value - min) / span) * (height - pad * 2);
    return [x, y] as const;
  });

  // A light Catmull-Rom-ish smoothing: midpoints joined by quadratic curves.
  // Straight segments make a 30-point series look like a seismograph.
  let d = `M ${coords[0]![0]} ${coords[0]![1]}`;
  for (let i = 1; i < coords.length; i++) {
    const [px, py] = coords[i - 1]!;
    const [x, y] = coords[i]!;
    d += ` Q ${px} ${py} ${(px + x) / 2} ${(py + y) / 2}`;
  }
  d += ` L ${coords[coords.length - 1]![0]} ${coords[coords.length - 1]![1]}`;

  const stroke =
    tone === 'receivable'
      ? 'var(--receivable)'
      : tone === 'payable'
        ? 'var(--payable)'
        : 'var(--accent)';

  return (
    <svg
      viewBox={`0 0 ${width} ${height}`}
      preserveAspectRatio="none"
      aria-hidden
      className={cn('h-8 w-full', className)}
    >
      {area ? (
        <>
          <defs>
            <linearGradient id={`spark-${id}`} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0" stopColor={stroke} stopOpacity="0.22" />
              <stop offset="1" stopColor={stroke} stopOpacity="0" />
            </linearGradient>
          </defs>
          <path d={`${d} L ${width} ${height} L 0 ${height} Z`} fill={`url(#spark-${id})`} />
        </>
      ) : null}
      <path
        d={d}
        fill="none"
        stroke={stroke}
        strokeWidth="1.75"
        strokeLinecap="round"
        strokeLinejoin="round"
        vectorEffect="non-scaling-stroke"
      />
      <circle
        cx={coords[coords.length - 1]![0]}
        cy={coords[coords.length - 1]![1]}
        r="1.8"
        fill={stroke}
        vectorEffect="non-scaling-stroke"
      />
    </svg>
  );
}

/** "↑ 12.5%" with the direction coloured by whether it is good news. */
export function TrendChip({
  changePercent,
  goodWhenUp = true,
  suffix,
}: {
  changePercent: number | null;
  goodWhenUp?: boolean;
  suffix: string;
}) {
  if (changePercent === null) return null;
  const rounded = Math.round(Math.abs(changePercent) * 10) / 10;
  if (rounded === 0) {
    return <span className="text-[0.6875rem] text-ink-faint">No change {suffix}</span>;
  }

  const up = changePercent > 0;
  const good = up === goodWhenUp;

  return (
    <span className="flex items-center gap-1.5 text-[0.6875rem]">
      <span
        className={cn(
          'tnum font-medium',
          good ? 'text-receivable' : 'text-payable',
        )}
      >
        {up ? '↑' : '↓'} {rounded}%
      </span>
      <span className="text-ink-faint">{suffix}</span>
    </span>
  );
}
