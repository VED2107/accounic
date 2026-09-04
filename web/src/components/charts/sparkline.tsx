import { cn } from '@/components/ui/primitives';
import { formatMoney } from '@/lib/money';

/**
 * A sparkline (context.md §30 — reporting stays out of v1; this is context, not
 * a report).
 *
 * Hand-drawn SVG rather than a charting library: it is one path, it renders on
 * the server, and it costs nothing at runtime. No axes, no grid, no tooltip —
 * the shape is the whole message, and the figure beside it carries the value.
 *
 * v1.11.0 — a decorative line is not a chart.
 *
 * The net-position spark was a thin stroke with no baseline, no scale and no
 * endpoint value: a shape that rises is indistinguishable from one that rises
 * *through zero*, which on a ledger is the only event the line is really about.
 * Three additions fix that without turning it into a report:
 *
 *   - `zeroBaseline` puts 0 inside the domain and draws a hairline through it,
 *     so "above the line" means owed to you and "below" means owed by you. A
 *     series that never crosses zero is drawn against the line anyway, because
 *     the distance from zero is the story.
 *   - the segment below zero takes the payable colour, above it the receivable
 *     one, so the crossing is legible without reading a label.
 *   - the endpoint is a labelled dot rather than a bare circle, and
 *     `SparklineFigure` prints its value and the range beside the chart.
 *
 * The SVG itself stays aria-hidden — everything it shows is stated in words by
 * the figure beside it, so announcing it again would only add noise. The words
 * are what changed: they now include the range the shape is drawn against.
 */
export function Sparkline({
  points,
  tone = 'accent',
  className,
  area = true,
  id,
  zeroBaseline = false,
}: {
  points: number[];
  tone?: 'receivable' | 'payable' | 'accent';
  className?: string;
  area?: boolean;
  /** Unique per instance — gradient ids are global. */
  id: string;
  /**
   * Force 0 into the vertical domain and draw a rule through it. For any series
   * that can go negative — a net position, a person's balance — this is the
   * difference between a shape and a statement.
   */
  zeroBaseline?: boolean;
}) {
  if (points.length < 2) return null;

  const width = 100;
  const height = 32;
  const pad = 2;

  const rawMin = Math.min(...points);
  const rawMax = Math.max(...points);
  // With a baseline, zero is always in frame. A flat series still needs a span,
  // and a series that sits entirely on one side of zero must not be stretched to
  // fill the box — that is what made a ₹20 wobble look like a collapse.
  const min = zeroBaseline ? Math.min(rawMin, 0) : rawMin;
  const max = zeroBaseline ? Math.max(rawMax, 0) : rawMax;
  const span = max - min || 1;

  const y = (value: number) => height - pad - ((value - min) / span) * (height - pad * 2);

  const coords = points.map((value, index) => {
    const x = (index / (points.length - 1)) * width;
    return [x, y(value)] as const;
  });

  // A light Catmull-Rom-ish smoothing: midpoints joined by quadratic curves.
  // Straight segments make a 30-point series look like a seismograph.
  let d = `M ${coords[0]![0]} ${coords[0]![1]}`;
  for (let i = 1; i < coords.length; i++) {
    const [px, py] = coords[i - 1]!;
    const [x, cy] = coords[i]!;
    d += ` Q ${px} ${py} ${(px + x) / 2} ${(py + cy) / 2}`;
  }
  d += ` L ${coords[coords.length - 1]![0]} ${coords[coords.length - 1]![1]}`;

  const stroke =
    tone === 'receivable'
      ? 'var(--receivable)'
      : tone === 'payable'
        ? 'var(--payable)'
        : 'var(--accent)';

  const zeroY = y(0);
  // Only worth drawing when zero is genuinely inside the plotted band — a rule
  // pinned to the very edge of the box is a border, not a baseline.
  const showZero = zeroBaseline && zeroY > pad + 0.5 && zeroY < height - pad - 0.5;
  // The area fills to the baseline when there is one, so the shaded region means
  // "distance from settled" rather than "distance from the bottom of the box".
  const floor = showZero ? zeroY : height;

  return (
    <svg
      viewBox={`0 0 ${width} ${height}`}
      preserveAspectRatio="none"
      aria-hidden
      className={cn('h-8 w-full overflow-visible', className)}
    >
      {area ? (
        <>
          <defs>
            <linearGradient id={`spark-${id}`} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0" stopColor={stroke} stopOpacity="0.22" />
              <stop offset="1" stopColor={stroke} stopOpacity="0" />
            </linearGradient>
          </defs>
          <path
            d={`${d} L ${coords[coords.length - 1]![0]} ${floor} L ${coords[0]![0]} ${floor} Z`}
            fill={`url(#spark-${id})`}
          />
        </>
      ) : null}

      {showZero ? (
        <line
          x1="0"
          x2={width}
          y1={zeroY}
          y2={zeroY}
          stroke="var(--line-strong)"
          strokeWidth="1"
          strokeDasharray="3 3"
          vectorEffect="non-scaling-stroke"
        />
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

      {/* The endpoint is the current value, so it is marked rather than merely
          ended: a filled dot inside a ring of the page's own surface colour, so
          it reads as a pin on the line rather than a bump in it. */}
      <circle
        cx={coords[coords.length - 1]![0]}
        cy={coords[coords.length - 1]![1]}
        r="3"
        fill="var(--surface)"
        stroke={stroke}
        strokeWidth="1.5"
        vectorEffect="non-scaling-stroke"
      />
    </svg>
  );
}

/**
 * A sparkline that says what it is showing.
 *
 * The chart, the range it is drawn against, and the value the line ends on —
 * the three things that turn a decorative stroke into a figure a reader can
 * act on. Everything is stated in text as well as drawn, so the screen reader
 * experience is the same as the visual one.
 */
export function SparklineFigure({
  id,
  points,
  tone = 'accent',
  currency,
  caption,
  label,
  className,
  chartClassName = 'h-12',
}: {
  id: string;
  points: number[];
  tone?: 'receivable' | 'payable' | 'accent';
  /** Formats the endpoint and the range. */
  currency: string;
  /** What the series is, in words — "Balance across the last 30 entries". */
  caption: string;
  /** The overline above the chart. */
  label?: string;
  className?: string;
  chartClassName?: string;
}) {
  if (points.length < 2) return null;

  const last = points[points.length - 1]!;
  const min = Math.min(...points);
  const max = Math.max(...points);
  const money = (minor: number) =>
    formatMoney(Math.abs(minor), currency, { base: currency, compactDecimals: true });

  return (
    <figure className={cn('min-w-0', className)}>
      {label ? <figcaption className="stat-label mb-1.5">{label}</figcaption> : null}

      <div className="flex items-stretch gap-2">
        {/* The scale. Two numbers, hairline-quiet, so the shape has units — a
            line without them can only be compared to itself. */}
        <div className="flex shrink-0 flex-col justify-between py-0.5 text-right text-[0.625rem] leading-none text-ink-subtle tnum">
          <span>{money(max)}</span>
          <span>{money(min)}</span>
        </div>
        <div className="min-w-0 flex-1">
          <Sparkline
            id={id}
            points={points}
            tone={tone}
            zeroBaseline
            className={chartClassName}
          />
        </div>
      </div>

      <div className="mt-1.5 flex flex-wrap items-baseline justify-between gap-x-3 gap-y-0.5">
        <span className="text-[0.6875rem] text-ink-faint">{caption}</span>
        <span
          className={cn(
            'money-sm',
            last > 0 && 'text-receivable',
            last < 0 && 'text-payable',
            last === 0 && 'text-ink-faint',
          )}
        >
          {last === 0 ? 'Settled' : money(last)}
        </span>
      </div>
    </figure>
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
