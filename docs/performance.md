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
(`node db/tools/run-sql.mjs test`) runs 72 assertions and rolls itself back.

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
