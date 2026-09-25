# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

Flutter targets Android and Windows from one codebase (`app/`). There is no Flutter Web
build. The Next.js client in `web/` is a separate browser client and is out of scope for
visual redesign work unless named (confirmed 2026-09-25: the redesign is Flutter only).

## Users

All kinds, confirmed by the owner, with no single primary persona: small traders and
business owners who keep a running account with the people and firms they deal with,
often across currencies (the largest live workspace trades between India and the UAE,
INR workspace with AED accounts). They use it equally on an Android phone, for quick
entries on the move, and on the Windows app at a desk, to review and settle.

## Product Purpose

A small, fast, personal ledger. It answers four questions and little else:

1. Who do I have an account with?
2. How much do they owe me?
3. How much do I owe them?
4. What has been settled and what remains?

Success is the owner trusting every figure on sight and recording an entry in seconds.

## Positioning

A ledger of relationships, not a bookkeeping suite. Every amount keeps the currency and
rate it was entered at; the database, never a client, converts, and history is never
re-priced at today's rate. Cash in hand and opening balances are always two separate
figures.

## Operating Context

- Workflows: add a credit or debit, settle (in any currency), transfer between two
  people, set or adjust an opening balance, export a PDF statement / CSV / JSON backup,
  review activity, administer users (admin only).
- Direction vocabulary is fixed (`docs/accounting-direction.md`): credit = they owe me
  (receivable, green), debit = I owe them (payable, red). Colour never carries meaning
  alone.
- Live data: both clients write to the owner's real Supabase books. A demo build
  (`DEMO_MODE=on`) exists with sample books and a restricted surface.

## Capabilities and Constraints

- Screens that exist: Dashboard, People, Person detail (Overview / Transactions /
  Settlements / Activity), Activity, Profile/Settings, Administration, login, demo entry,
  plus the add-transaction, settle, transfer, person, opening-balance and export sheets.
- There are no Products, Billing, POS or Reports modules. Do not design them as if they
  exist (confirmed 2026-09-25).
- Redesigns preserve every figure, rule and flow: no accounting, currency, RLS or API
  changes as part of visual work.
- Performance floor: mid-range Android. Animate transform and opacity; no per-row
  controllers on long lists; respect reduced motion.

## Brand Commitments

- Name: Accounic. Mark: the ribbon "A" with ascending bars and a growth arrow
  (`brand/*.svg` are the only source; `node brand/build-assets.mjs` rasterises).
- The brand gradient is confined to the mark and a few accents; green and red are
  reserved for receivable and payable, so the accent is the brand's blue end.
- Currency display rule: base-currency amounts drop the ISO suffix, foreign amounts keep
  it, conversions read with ≈.

## Evidence on Hand

Real product, real data. Screens are verified by driving the Windows binary
(screenshots) — never by clicking writes into the live books. No testimonials, pricing or
customer claims exist and none should be invented.

## Product Principles

1. Every figure is trustworthy on sight: the currency it was entered in, never re-priced.
2. Recording is faster than remembering: an entry in seconds, from anywhere.
3. One question per surface; supporting detail is one step away, not beside it.
4. Parity is behavioural, not pixel-identical: respect each platform's interaction norms.

## Accessibility & Inclusion

WCAG AA contrast (enforced by `app/test/design_tokens_test.dart`), reduced motion
honoured, touch targets sized for phones, keyboard and focus usable on Windows.
