# Performance

What is measured, what was slow, and what was done about it.

The rule this project follows: the database computes every balance, so a client that
feels slow is almost never waiting on arithmetic. Every performance problem found so
far has been in how much work the client did *per row* on screen.

---

## 1. Database

Every read a screen needs is one round trip. The engine views do the arithmetic and
the RPCs return a screen's worth of data in a single shape, so no client fans out a
query per person or per transaction.

| Read | RPC | Returns |
|---|---|---|
| Dashboard | `dashboard()` | totals, 12 activity rows, 8 people — one call |
| Person page | `person_page()` | person, balance, timeline page, open transactions |
| People list | `person_balances` view | up to 500 rows, ordered by name or last activity |
| Activity | `activity_feed` view | 40 rows per page |
| Search | `search_all()` | 8 rows |

Indexes are in `db/migrations/0006_indexes.sql`. The accounting suite
(`node db/tools/run-sql.mjs test`) runs 82 assertions and rolls itself back.

**Pagination is per screen, not global.** The person timeline is 30 rows a page and
activity is 40. The people list is the one unbounded read, capped at 500 — see §4.

---

## 2. Web

`npm run build` is clean: 103 kB of shared first-load JS, largest route 190 kB.
Server components do the data fetching, so the client bundle carries the interactive
sheets and little else.

---

## 3. The Flutter client — what actually made it janky

The Android build was reported as laggy at v1.0.3. None of it was paint. There is no
blur anywhere in this app and barely a shadow, so there was nothing for the
rasterizer to struggle with. It was **tickers**.

Every row of every list carried three animations:

| Animation | Purpose | Cost |
|---|---|---|
| `Stagger` entrance | rows arrive in sequence | one `AnimationController` + `Ticker` |
| Hover fill | background tint under the pointer | one more, via `AnimatedContainer` |
| Hover chevron | the arrow nudges right | one more, via `AnimatedSlide` |

The people query returns up to 500 rows, so opening People built roughly **1,500
controllers**. Each running `Ticker` asks for a frame, and two of the three existed
to serve **hover** — an event a touch screen cannot produce at all.

On top of that, `AppPage` handed its `ListView` a single child holding a `Column` of
the whole page. A list with one item is not a list: that item is always in view, so
the viewport could never decline anything and every section on the page was built and
laid out whether or not it was near the screen.

### Measured, on a 300-row page

| | v1.0.3 | v1.0.4 |
|---|---|---|
| `Animate` widgets built | 300 | 9 |
| Total elements | 2,344 | 1,179 |

### The three changes

**`Stagger` animates only the rows within its cap.** Past `Motion.staggerCap` every
row already shared a single delay, so the choreography was over — those rows were
paying for a controller in order to arrive at the same instant as row eight, from
below the fold. The cost is now a function of the cap, not of how many people are on
the ledger.

**`Motion.pointerHovers` gates the hover work.** `Hoverable`, `HoverFill` and
`HoverSlide` build the plain widget on Android and iOS: no `MouseRegion`, no implicit
animation, no controller. On Windows nothing changes.

**`AppPage` hands its sections over individually**, so the viewport can decline the
ones off screen.

One deliberate exception: the person timeline row keeps its `AnimatedContainer`,
because its tint also tracks whether the row is expanded — a real state change that
touch *does* produce.

### Pinned

`app/test/motion_cost_test.dart` asserts all of it, plus the content-width constraint
the `AppPage` change could plausibly have broken. It asserts **widget counts, not
timings**, because a timing test measures the machine it runs on.

---

## 4. Known, and deliberately left

**The people list still builds every row it fetches.** The row animations are gone,
but the widgets are still constructed, because the list sits inside one card and is
therefore a single page section. Virtualizing it means restructuring that card around
slivers, which changes how the list looks. At the scale a personal ledger actually
reaches — tens of people, not hundreds — the remaining cost is not felt. Revisit it
if the 500-row cap is ever approached in practice.

**The launch sequence takes about 1.9s.** That is a designed feature, not a
regression; see `docs/decisions.md` §22–§26.

---

## 5. How to measure it again

There is no profiling harness. Widget tests are enough to catch the class of problem
found here, because the problem was *how many widgets*, not how fast they painted:

```bash
cd app && flutter test test/motion_cost_test.dart
```

For anything paint-related, run the real binary with
`flutter run --profile -d windows` and open DevTools — but check the widget count
first. Every jank bug this project has had was a build-phase cost, not a raster one.

---

## 6. The engine at 20,000 entries (milestone 1.9.0, Phase 8)

Section 1 measured a seeded workspace of a few dozen entries and said outright
what was missing: the numbers at realistic scale, where `person_balances`'
lateral joins and the FIFO loop in `transaction_settlement_status()` were the
two things most likely to bend first.

They bent. `db/bench/seed_bench.sql` builds a workspace of **50 accounts across
5 currencies, 20,230 transactions over three years, 4,925 settlements, 30
opening rows and 100 transfers**, and the dashboard took **98 seconds**.

| Query | Demo size | 20k, before | 20k, after |
|---|---|---|---|
| `dashboard()` | 9.8 ms | **98,235 ms** | **1,201 ms** |
| `person_page()` | 5.2 ms | 2,104 ms | 126 ms |
| `person_balances` (50 people) | 3.3 ms | 149 ms | 216 ms |
| `activity_page()` | 7.6 ms | 62 ms | 77 ms |
| `owner_summary` | 3.2 ms | 274 ms | 380 ms |
| `search_all()` | 1.6 ms | 12 ms | 14 ms |
| `transaction_settlement_status()` (one person) | — | 5 ms | 7 ms |
| `export_workspace()` | — | — | 2,019 ms |

(Median of five runs, server time — planning plus execution — under RLS, on an
embedded Postgres 18 on a laptop. Supabase's hardware is faster; the ratios are
the point, not the absolute numbers.)

### One cause, in two places

Migration 0024's per-currency breakdown joined the allocator laterally against
every row:

```sql
left join lateral public.transaction_settlement_status(a.person_id) st
       on st.transaction_id = a.id
```

So it ran **once per entry**, and each run walked that person's entire ledger to
allocate it FIFO. 20,000 entries × ~400 rows each is the 98 seconds. The same
join, per row, was in `person_currency_breakdown()`, which is what made
`person_page()` two seconds.

`db/migrations/0027_dashboard_scale.sql` moves the call: the allocator is asked
**once per person**, into a CTE the rows join against. 50 calls instead of
20,000. Nothing else in either function changed — the definitions in that
migration were taken from the live catalogue and edited in exactly those two
places — and `db/tests/12_dashboard_currency_breakdown.sql`, which asserts the
figures byte for byte, passes unchanged.

**82× on the dashboard, 17× on the person page, and no number moved.**

### What is still slow, and what it would take

* **`dashboard()` at 1.2 s** is now dominated by the two `today` blocks, which
  sum `amount_base_minor` over the whole feed to answer a question about one
  day. An index-friendly rewrite (filter by date before the union, rather than
  after) is the obvious next move, and it was left alone here because 1.2 s at
  20,000 entries is not what anyone will notice next.
* **`export_workspace()` at 2.0 s** includes `dashboard()`'s per-currency
  totals by construction; it will fall by roughly the same amount whenever the
  above is done.
* **`owner_summary` and `person_balances` grew slightly** (274→380 ms,
  149→216 ms) because the bench workspace is 50 people rather than 6. Both are
  linear in people, not in entries, which is the shape you want.

### Running it again

```bash
node db/tools/run-sql.mjs file db/ci/00_supabase_shim.sql   # throwaway DB only
node db/tools/run-sql.mjs migrate
node db/tools/run-sql.mjs file db/bench/seed_bench.sql
BENCH_EMAIL=bench@example.test node db/tools/bench.mjs 5
```

**Never against the live project.** The fixture writes 25,000 rows and signs its
workspace `bench@example.test`; `DATABASE_URL` decides where that lands.
