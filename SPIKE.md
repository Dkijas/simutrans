# Spike: what would animated signals actually cost?

Not a patch. A measurement, to replace two inferences in
`../simutrans-contributor-workbench/knowledge/architecture/signal-animation-incremental-path.md`
with numbers:

1. "opt-in registration makes the runtime cost negligible" — unmeasured;
2. the implementation decomposes into cheap stages — asserted, never tried.

Branch `spike/signal-animation-cost`, off `65a2deb` (r12092). **Nothing here is
intended for upstream.** It exists to be measured and thrown away.

## Method

Instrumentation only, in three parts:

- count `signal_t` and `roadsign_t` instances actually present in a loaded game;
- time `sync_roadsigns.sync_step()` and `sync_buildings.sync_step()` per frame;
- then register every signal in a sync list — the **worst case**, the opposite of
  the opt-in design — and measure the same thing again.

Worst case first is deliberate. If the worst case is cheap, the design argument
is over and the opt-in machinery is not needed to make it affordable. If the
worst case is expensive, the measurement tells us how much the opt-in has to
save, which is the number the forum discussion is missing.

Measured on the largest savegame available here: `save/aaaaa.sve`, 4 MB, pak128.

## Result

See RESULTS.md, written after the run rather than before.
