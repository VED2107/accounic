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

| Phase | State |
|---|---|
| 0 — audit | done |
| 1 — CI | in progress |
| 2 — telemetry | not started |
| 3 — Flutter-first | not started |
| 4 — general PDF export | not started |
| 5 — CSV + JSON export | not started |
| 6 — export RPC | not started |
| 7 — restore rehearsal | not started |
| 8 — 20k benchmark | not started |
| 9 — rate limiting | not started |
| 10 — file splits | not started |
| 11 — shared definitions | mostly pre-existing; CI check added in Phase 1 |
| 12 — exchange-rate resilience | not started |
| 13 — verification | not started |
