# Accounic 1.11.0 — Premium UX

The milestone brief was blunt about the problem: a product is not judged by its
best screen but by its weakest important one. Dashboard and People had been
refined; Person Detail, Settlement and the interaction system had not, and the
gap between them was visible the moment anyone actually used the thing.

This is the record of the pass. It is written after the work rather than before
it, because a review that predicts its own findings is not a review — every
defect below was found by running the two clients and looking at them, and each
one names how it was found.

**This shipped as v1.11.0.** The work was originally run under a rule of not
cutting a version until every screen reached the same bar; that rule was lifted
deliberately, so the Premium UX improvements reach installed clients through the
existing update checker rather than waiting on a later polish pass. The screens
listed as done below are done. The ones listed as outstanding are **planned
follow-up work for a subsequent milestone** — they have not been audited, and
nothing in the release notes claims otherwise.

---

## How this was verified

| Client | Method |
|---|---|
| Web | Real browser against the dev server and the live database. 1440 and 1024 desktop, 375 phone, both colour schemes, keyboard-driven for focus. |
| Flutter | The real Windows release binary, rebuilt from the working tree before each look, driven and screenshotted. Phone-width layout covered by widget tests at 390, which is the width the desktop binary cannot be resized to. |
| Both | `typecheck` / `analyze`, unit and widget suites, and — new this milestone — `npm run lint`, which had never run. |

Two rules held throughout: no automated click was allowed to write to the
ledger, and no screenshot was taken without first verifying the app was actually
the foreground window. The second rule exists because the first attempt at a
capture photographed the desktop instead of the app.

---

## Screen by screen

### Person Detail — the milestone's reason for existing

**Before.** The product's most important screen and its least designed one.
Everything the account knew was stacked into the first viewport: cash in hand,
the opening balance, the account position, a sparkline, nine controls at equal
weight, four figures, two per-currency tables and an opening-balance panel —
before the history it is all evidence for even began. A reader who wanted "where
do we stand?" had to scroll past the answer's working to reach the answer.

The action bar was five buttons, two icon buttons and two lines of destructive
plain text, all at one visual weight and all permanently on screen. "Retract all
history" sat one line under the primary call to action on every visit.

**Review.** This screen is a statement, and a statement has a shape: who, where
we stand, what to do about it, then the evidence. It was carrying all four at
once with no hierarchy between them.

**Change.**

- The position stands alone: one figure, its meaning in words, a direction badge
  beside the name, and the metadata line that answers "is this live, and when
  did anything last happen here". Nothing else competes for the first screen.
- Four tabs, because an account is four questions and a reader has one at a
  time: **Overview**, **Transactions**, **Settlements**, **Activity**. On the
  web they are links — switching ships no JavaScript, survives a refresh, and is
  a shareable URL. On Flutter they are local state, because a route per tab
  would put three entries in the back stack between the account and the list it
  came from.
- Secondary material — per-currency breakdowns, account details, notes — sits
  behind disclosures inside Overview, closed by default. Native `<details>` on
  the web; a `collapsible` mode on `SectionCard` in Flutter.
- Action hierarchy: Settle filled and first when there is something to settle;
  Add credit and Add debit as the two ordinary entries, still separate buttons
  because the type *is* the decision; transfer, edit, archive and both
  destructive routes behind the row menu.

**After.** Verified in both clients, in both schemes, at 1440 and 375, with each
tab opened and its contents checked against what the database says the rows are.

---

### Settlement — the product's other financial act

**Before.** A three-cell strip printed the arithmetic **above** the field it
depended on, so opening the sheet read "Settling 0.00, Remaining <the whole
balance>" — an answer to a question nobody had asked yet. The resulting figure
was never stated in the account's currency at all.

**Change.** The sheet states the chain end to end, in the order the questions
are actually asked:

> what is owed → what I am paying → in what, at what rate → and therefore what
> this settles

Balance due anchors the top, the amount and currency sit under it, the rate
panel under that, and a tinted block closes it with **You'll receive** /
**You'll pay** and the remainder beneath. An over-ceiling amount says so before
the submit rather than after.

**Defect found and fixed while here.** The sheet did its arithmetic on the typed
figure, so settling a rupee account with AED 40 read "Settling ₹40.00" and
computed the remainder from it — a number in the wrong currency wearing the
account's symbol, with every figure derived from it wrong in the same way.
`ConversionPanel` now reports what the entry resolves to in the account's
currency, in both clients; it owns the rate and both overrides, so it is what
may say. On Flutter it reports `null` when the rate is missing, so a sheet that
loses its rate stops showing a stale figure rather than keeping one.

---

### Dashboard

Refined already, so this was a targeted pass on the one open finding.

**The net-position sparkline was a decorative line.** No baseline, no scale, no
ending value. A line that rises is indistinguishable from one that rises
*through zero*, and on a ledger that crossing is the only event it is about.

Both clients now force zero into the domain, draw a hairline through it, fill
the area to that line rather than to the bottom of the box, and print the range
and the ending value beside the chart.

Three defects surfaced during that work, each one caught by looking at the
result rather than by reading the diff:

1. The scale described the data's own range while the chart was drawn against a
   zero-extended domain — a rail that looks authoritative and disagrees with the
   line beside it.
2. The scale dropped the sign. An account running from −₹4,500 to ₹15,500
   labelled its floor "₹4,500", a range containing neither the zero line through
   the middle of the chart nor the ₹2,537.50 the line ended on.
3. The caption said "Net position, daily". The series is cumulative
   credit-less-debit over the window; the net position beside it includes every
   account's whole history and every settlement. They read ₹32,599 and
   ₹2,537.50 under one name.

**Flutter money colour.** `MoneyText` overwrote the caller's colour
unconditionally, and its `tone` defaults to neutral — so every figure coloured
through `style` rendered in plain ink. The entire cash-in-hand breakdown passed
receivable and payable colours per figure and a balance tone per currency
headline, and all of it came out white while the web's identical block rendered
green and red. Colour is the only thing in this product that carries meaning
without words, and it was being discarded.

---

### Shell and navigation

**The sidebar's dead band.** The one filled button in the app was pinned to the
foot of the column, leaving roughly 450px on the web and 570px on Flutter
between the last destination and the primary action — the two things a reader
uses most, separated by half a screen, with the action closer to the taskbar
than to the product. It sits under the destinations in both clients now. The
space that remains falls above the profile card, where empty space in a column
is simply margin.

**The actions menu opened underneath the card.** Reported from the running app.
The list is `position: fixed` at viewport coordinates, which escapes overflow
only while no ancestor establishes a containing block for fixed descendants — and
an ancestor animating `transform` does exactly that. Every panel in this product
enters through `Reveal`, which animates transform and fills its final frame, so
the menu was laid out inside the Panel and cut off by its `overflow-hidden`.
Portalled to `<body>`, which is what a viewport-positioned popup should have
been doing from the start.

**People toolbar at narrow widths.** Four Show segments plus their label are
wider than a 375px viewport, and a segmented control cannot wrap without ceasing
to read as one control. Each named group scrolls inside its own track now, so
the control stays whole and the page never scrolls sideways.

---

## The interaction language

Motion was consistent by habit rather than by system. Three durations and one
curve existed as tokens, but nothing said which was for what; several controls
reached for the bare `transition` shorthand, which means
`transition-property: all` — the most reliable way to animate layout nobody
meant to animate and drop frames on a list; and press feedback existed only on
things that happened to be a `<Button>`.

The vocabulary is now named by job rather than by speed, and identical across
both clients:

| Token | For | Value |
|---|---|---|
| `--dur-tap` / `Motion.tap` | a press acknowledging itself | 110ms |
| `--dur-fast` / `Motion.micro` | hover, focus, a selected state changing hands | 120–140ms |
| `--dur` / `Motion.component` | a component appearing: menu, tooltip, tab panel | 170–240ms |
| `--dur-slow` / `Motion.major` | a surface: dialog, sheet, panel entrance | 220–380ms |
| `--ease` / `Motion.enter` | the app's curve — ease-out with authority | — |
| `--ease-move` / `Motion.move` | something on screen changing position or size | — |
| `--ease-emph` / `Motion.emphasis` | one restrained overshoot, money confirmed | — |

Never `ease-in` anywhere in the UI: a slow start is a slow interface at exactly
the moment the user is watching hardest. The emphasis curve has exactly one
caller in each client — the settlement tick — and earns its place by being rare.

Press feedback now covers every pressable thing: segments, menu items, nav rows,
timeline rows, bottom-bar destinations, toast and modal controls. A tap on a row
that then takes 200ms to navigate used to read as a tap that did nothing.

The existing restraint was preserved deliberately. The Flutter client had an
animation-controller problem on touch devices once; `Motion.pointerHovers` and
the stagger cap that fixed it are untouched, and nothing added here builds a
controller per row.

---

## Accessibility and keyboard

**The focus ring had never been the colour it was documented as.** The rule was
written with `:where()`, which zeroes specificity, while Tailwind's preflight
sets `outline-color: currentColor` on the universal selector — and at equal
specificity the later rule wins. So the product's one brand-blue focus treatment
had been rendering in whatever colour the focused element's *text* was, for the
life of the project: black on a button, and 2px of #646e7e on #f6f7f9 on the
quiet links and metadata rows where a keyboard user needs it most. Measured with
`getComputedStyle` under real keyboard focus, fixed by writing the selector out.

`summary` was missing from that selector entirely — disclosures are focusable by
the platform rather than by anything this app does, and the new Overview
disclosures are the first the product has had.

Verified by keyboard on the web: tab order follows the reading order, Escape
closes a dialog and returns focus to its trigger, the menu traps focus and moves
on arrows with Home/End at the ends, and every focusable element in the account
screen takes a visible ring.

---

## What is done, and what is not

| Area | State |
|---|---|
| Design tokens and primitives | Strong; extended, not rebuilt |
| Person Detail | Rebuilt in both clients, verified live |
| Settlement | Rebuilt in both clients, plus a real currency defect fixed |
| Motion system | Tokenised and applied across both clients |
| Dashboard | Chart honesty fixed; Flutter money colour fixed |
| People | Narrow-width toolbar fixed |
| Shell / sidebar | Dead band closed in both clients |
| Lint | `npm run lint` runs for the first time; seven findings fixed |
| Web responsive | Verified 1440 / 1024 / 375, no horizontal overflow |
| Web themes | Verified light and dark on Dashboard, People, Person Detail |
| Web keyboard | Verified: tab order, Escape, focus return, menu arrows, ring visibility |
| Flutter phone layout | Two overflows fixed; covered by widget tests at 390 |
| **Profile** | **Not reviewed this milestone** |
| **Administration** | **Not reviewed this milestone** |
| **Activity** | **Route checked, not visually reviewed** |
| **Flutter light theme** | **Not verified — the binary was driven in dark only** |
| **Flutter keyboard/focus** | **Not audited** |

The five rows in bold are the honest remainder. They are not "mostly fine"; they
are unlooked-at, and this document would be worth less if it implied otherwise.

### Planned follow-up work

Carried into the next milestone, unstarted:

1. **Profile** — full visual review.
2. **Administration** — full visual review.
3. **Activity** — final visual review. The route was checked for correctness and
   for horizontal overflow; its composition was not reviewed.
4. **Flutter light theme** — the binary was driven in dark only, at desktop
   width, so the light scheme is unverified on that client.
5. **Flutter keyboard and focus** — not audited. The web client's audit does not
   transfer: focus order, traversal and visible focus are separate
   implementations there.

None of the five is a regression introduced by v1.11.0. They are areas this pass
did not reach.

---

## Why this shipped before the polish pass finished

The milestone opened under a rule of not cutting a version until every screen
reached the bar of the refined ones. That rule was lifted on purpose.

Person Detail, Settlement and the interaction system — the three things the
milestone existed for — are done, and with them six defects that were live in
v1.10.0, including a focus ring that had never rendered in the documented
colour and a foreign settlement that did its arithmetic in the wrong currency.
Holding all of that behind a review of Profile and Administration would keep
fixes out of installed clients to buy consistency in screens that are not
broken.

So v1.11.0 ships what is finished, the release notes say plainly what it
contains, and the five areas above are the opening scope of the next
milestone.
