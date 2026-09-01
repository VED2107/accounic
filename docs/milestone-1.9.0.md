# Milestone 1.9.0 — hardening, CI, Flutter-first, export

The plan this milestone is executed against, written after reading the repository
rather than before. Phase numbers follow the brief. What each phase turned out to
mean *here* — given what already exists — is the point of this document.

**Last updated:** 2026-09-01

---

## Phase 0 — audit findings

What the audit changed about the plan:

| Finding | Consequence |
|---|---|
| `shared/currencies.json` + `db/tools/sync-currencies.mjs --check` already exist and already generate the SQL seed, `currencies.ts` and `currencies.dart` | Phase 11 is largely **already done**. The work left is to run `--check` in CI and to extend the same pattern to the next-most-duplicated definition, not to build a generator |
| `web/src/lib/pdf/` already renders the person statement, with 19 tests | Phase 4 **extends** that renderer; it does not start a second one. Same for `app/lib/data/statement_pdf.dart` |
| SQL suites write directly to `auth.users` and `set local role authenticated` | A throwaway Postgres needs a shim (roles, `auth.users`, `auth.uid()`) — `db/ci/00_supabase_shim.sql`. With it, the real migrations and the real 12 suites run unchanged |
| `run-sql.mjs` forced TLS on every connection | Made conditional on the host, so one command serves Supabase and a local container |
| 81 of 82 Dart files disagree with `dart format` | No format gate in CI. That is a deliberate one-commit decision, not a CI failure to discover on a push |
| No Docker, no `psql`, no Android emulator on this machine | Local SQL verification runs against an embedded Postgres 16; CI uses a service container. Android verification stays widget-tests-at-phone-metrics plus the sideloaded APK |
| `errors.ts` logs only outside production | Telemetry is genuinely absent, not merely thin — Phase 2 stands as written |

### The line the whole milestone respects

**Accounting behaviour is one product; presentation is two.** These must stay
identical across web and Flutter: direction semantics, settlement pairing, opening
balance separation, currency of record, validation rules, authorization. These are
free to diverge: layout, navigation, spacing, sheets, gestures, motion.

**The currency and rates architecture is not being redesigned.** Entries keep the
currency they were entered in; conversion provenance stays on the row; the per-owner
`exchange_rates` cache stays. Phase 12 touches only what happens when the *provider*
fails — never how a rate is stored, chosen or applied.

---

## Execution order

Dependency-ordered, not brief-ordered. Each step lands as its own commit with its
own verification.

1. **Phase 1 — CI.** Everything after this is verified by it.
2. **Phase 12 — exchange-rate failure behaviour.** Small, additive, and it pins the
   currency path before any refactor moves code around it.
3. **Phase 6 → 5 → 4 — export.** RPC first (the data), then CSV/JSON (thin), then
   the PDF (presentation on top of an already-tested payload).
4. **Phase 9 — rate limiting.** A migration; wants CI and the export RPC settled.
5. **Phase 8 — 20k benchmark.** Needs a throwaway database, which Phase 1 supplies.
6. **Phase 7 — restore rehearsal.** Same infrastructure as Phase 8.
7. **Phase 10 — file splits.** Behaviour-preserving; done *before* the Flutter UX
   work so that work lands in the new structure instead of the old one.
8. **Phase 11 — shared definitions.** Extend the existing generator.
9. **Phase 2 — telemetry.** Web and Flutter.
10. **Phase 3 — Flutter-first product work.** The largest phase, and the one that
    benefits most from everything above.
11. **Phase 13 — full verification, then PROGRESS.**

---

## Status

Shipped as **v1.9.0** — PR #1 merged to `main`, tag `v1.9.0` pushed, migrations
0025–0028 applied to the live project (`snapshot.mjs diff`: every net balance
unchanged), and the release workflow building the installer and the APK.

| Phase | State |
|---|---|
| 0 — audit | **done** |
| 1 — CI | **done** — three workflows, all three green on GitHub. The SQL one builds a throwaway Postgres from `db/ci/00_supabase_shim.sql` + 28 migrations and runs all 15 suites |
| 2 — telemetry | **done** — `client_errors` in the owner's own project, three layers of redaction, wired to both Flutter error hooks, the web render boundary, `window.onerror` and `unhandledrejection` |
| 3 — Flutter-first | **partly** — the export sheet is built to these rules (chips, 44pt targets, live counts before generating, real page progress, cancel treated as not-an-error). Dashboard, person screen and transaction entry are **not** reworked |
| 4 — general PDF export | **done** — both clients, one document |
| 5 — CSV + JSON export | **done** — mirrored writers, 21 web + 26 Dart tests |
| 6 — export RPC | **done** — `export_workspace()` / `export_entries()`, 39 assertions including isolation |
| 7 — restore rehearsal | **not done** — no `pg_dump` in this environment |
| 8 — 20k benchmark | **done** — and the 98-second dashboard it found is fixed (0027) |
| 9 — rate limiting | **done** — trigger-based, 13 assertions, both clients show the refusal |
| 10 — file splits | **not done** |
| 11 — shared definitions | mostly pre-existing; `sync-currencies --check` runs in CI now |
| 12 — exchange-rate resilience | **done** — rate sanity guards + provider-payload rules, 14 web + 13 Dart tests |
| 13 — verification | **done for what shipped** — 15 SQL suites, 196 web tests, 315 Dart tests, analyze and build clean, CI green, and `docs/PROGRESS.md` updated. It is not a pass over phases 3, 7 and 10, which did not happen |

## What is left

Three phases of the brief, untouched and not claimed anywhere as done:

1. **Phase 3** — the Flutter dashboard, person screen and transaction-entry rework.
   The export sheet shows the shape it should take; the rest of the screens have not
   been through it.
2. **Phase 10** — `person_screen.dart` (1,686 lines), `dashboard_screen.dart` (1,359)
   and `actions.ts` (1,015) are still one file each. Worth doing **before** Phase 3,
   so that work lands in the new structure.
3. **Phase 7** — the restore rehearsal. There is no `pg_dump` in this environment, so
   the drill has to be a rebuild from migrations plus a data reload, reconciled
   against `person_balances`. The procedure is not written either.

Smaller things the milestone found and left:

* `dashboard()` is 1.2 s at 20,000 entries — the two `today` blocks sum the whole feed
  to answer a question about one day (`docs/performance.md` §6).
* `export_workspace()` inherits that cost, at ~2 s.
* The web PDF drops non-Latin glyphs when fontkit's shaper throws; it falls back
  rather than failing the export, but the name is lost from that cell.
