# Design — Counterfoil & Seal

The Flutter client's visual system (Android + Windows), recorded from the built
app in v1.16.0. The web client keeps its own look; parity between the two is
behavioural, not visual (PRODUCT.md).

## Thesis

Every account is an instrument of value — engraved, serialised, and stamped
when settled. The app refuses the white-card KPI dashboard: the one figure a
screen is about is *certified* on an instrument, and everything that explains
it hangs below.

## Colour — ink only

Zero-chroma neutrals, so nothing reads gold or blue. Colour means money and
nothing else.

| Role | Light (paper) | Dark (carbon) |
|---|---|---|
| Ground (scaffold) | `#ECECEA` | `#111111` |
| Surface / instrument paper | `#F7F7F5` | `#181818` |
| Raised | `#FFFFFF` | `#202020` |
| Sunken | `#E3E3E0` | `#0B0B0B` |
| Ink (text, action plate) | `#161616` | `#F2F2F0` |
| Ink muted / faint | `#3E3E3C` / `#565654` | `#C6C6C3` / `#A2A29F` |
| Line / line strong | `#D7D7D3` / `#BEBEBA` | `#262626` / `#383837` |
| **Receivable** (owed to you) | `#1B6A45` bottle-green ink | `#6CD3A0` |
| **Payable** (you owe) | `#B0301C` cinnabar seal red | `#F2795E` |

- The primary action is a **solid ink plate** that inverts with the scheme
  (`context.actionFill` / `context.onAction`). No accent hue exists.
- Green and red never change meaning; shades may vary, contrast may not drop.
  `app/test/design_tokens_test.dart` fails under WCAG AA on either ground.
- The brand gradient lives only in the logo mark.

## Type

Poppins for display, figures and stamps; the platform face for body. Figures
are always tabular. Section headings are set heavy with a hairline rule running
out to the edge of the form, in the text's own case (never uppercased in code).

## The instrument vocabulary (`app/lib/ui/widgets/instrument.dart`)

| Piece | Means | Rule |
|---|---|---|
| `InstrumentPanel` + `GuillocheField` | the one certified figure on a surface | one per screen; the field sits only behind that figure |
| `Perforation` | two figures that are never added together | cash in hand ↔ opening counterfoil; net ↔ its sides; a sheet's heading ↔ its form |
| `SerialText` | the record's own id (`A/C 4462·63`, `No. BFCF·C9`) | accounts and entries |
| `Microprint` | real account data at the instrument's edge | decorative to screen readers |
| `CancellationStamp` | an outcome: SETTLED, RECEIVED, PAID, VOID, ALL SETTLED | firm name arched top, LEDGER along the bottom, word on a knockout bar; worn-rubber texture and tilt seeded by the record id; inked in the direction's colour; placed **beside** a figure, never over it |
| `DirectionNode` | an entry's direction | round ink node; the same mark on the spine, the dashboard and Activity |

The person screen's entries hang on a **ledger spine**: one engraved rule down
the list, each entry a stub.

## Shape

Instrument corners, not pillows: field 8, card 12, panel 16.

## Motion (`app/lib/ui/motion.dart`)

| Token | Value | Use |
|---|---|---|
| `Motion.enter` | `Cubic(0.23, 1, 0.32, 1)` | anything entering; all implicit animations' default |
| `Motion.move` | `Cubic(0.77, 0, 0.175, 1)` | on-screen travel (segment thumb) |
| `Motion.drawer` | `Cubic(0.32, 0.72, 0, 1)` | panels, drill-in routes |
| `Motion.exit` | ease-in, **reverse curves only** | a closing route or dialog leaves at once |
| `sheetIn` / `sheetOut` | 360 / 200 ms | every modal leaves faster than it arrived |
| press | 0.97, 100 ms down / 180 ms release | every pressable |

- Colour and hover transitions use `Curves.ease`; nothing is left on Flutter's
  linear default.
- Keyboard-initiated navigation (Ctrl+1…N on Windows) cuts instantly.
- Tab bodies cross over in the direction the segmented thumb travelled, with a
  3 px blur on desktop only.
- Label swaps (Save → spinner → Saved) use `Motion.blurSwap`: 2 px blur + 0.98
  scale.
- Figures count to new values and nudge 4 px in the direction the money went.
- **The signature moment:** a settlement's success sheet strikes a stamp (out of
  a 6 px blur at 1.3×, squash to 0.96, pressure ring, settle — 460 ms, once);
  the account's instrument strikes SETTLED across itself when a settlement on
  screen brings cash in hand to zero.
- Destructive confirmations are **held**: 1.2 s linear fill, 200 ms snap back;
  keyboard and screen readers confirm at once.
- Reduced motion (`Motion.of`) turns all of it into cuts and fades.
