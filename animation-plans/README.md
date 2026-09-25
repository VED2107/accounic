# Animation plans — Flutter client

Audit by `improve-animations` (standard effort) at commit `dc83e6d`, 2026-09-25.
Motion tokens: `app/lib/ui/motion.dart` (`Motion.enter` = Cubic(0.23, 1, 0.32, 1),
`Motion.move` = Cubic(0.77, 0, 0.175, 1), `Motion.drawer` = Cubic(0.32, 0.72, 0, 1),
`Motion.exit` = easeInCubic for reverse curves only). Personality: a crisp ledger —
fast, no bounce except the one settlement moment.

| # | Severity | Plan | Status |
|---|---|---|---|
| 1 | HIGH | Keyboard navigation (Ctrl+1…N) cuts instantly; no page transition on a keyboard-initiated action | DONE |
| 2 | HIGH | Every implicit animation sets a curve: colour/hover → `Curves.ease`, switchers → `Motion.enter` (Flutter's default is linear) | DONE |
| 3 | MEDIUM | Button state crossfades (idle → busy → saved) masked with a 2px blur + 0.98 scale so two labels never double-expose | DONE |
| 4 | LOW | `Reveal` lightened to 6px / 200ms — screens are opened tens of times a day | DONE |
| M1 | Opportunity | When a settlement on screen brings cash in hand to zero, a SETTLED stamp strikes across the instrument (rare, earned) | DONE |
| M2 | Opportunity | Destructive confirmations are held, not tapped: 1.2s linear fill while pressed, 200ms ease-out snap back on release; keyboard and screen-reader activation confirm immediately | DONE |

Execution order: 2 → 4 → 3 → 1 → M1 → M2 (independent; 2 first because it touches the
most files). Feel-check each on the Windows build at 1× and with animations slowed
(Flutter DevTools "Slow animations"), and on an Android phone for M2's press.
