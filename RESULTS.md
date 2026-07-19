# Results

Measured 2026-07-19 on branch `spike/signal-animation-cost`, off `65a2deb`
(r12092). **Throwaway spike. Not a patch, not offered to anyone.**

## 1. Implementation cost — MEASURED

A complete end-to-end MVP: pakset-declared animation phases, read through the
descriptor, advanced per frame, and consumed when the signal picks its image.

```
src/simutrans/descriptor/roadsign_desc.h            13 +
src/simutrans/descriptor/reader/roadsign_reader.cc  22 +
src/simutrans/descriptor/writer/roadsign_writer.cc  10 +-
src/simutrans/obj/roadsign.h                         5 +
src/simutrans/obj/roadsign.cc                       35 +-
src/simutrans/obj/signal.cc                          7 +-
--------------------------------------------------------
6 files, 85 insertions, 7 deletions
```

For comparison, our merged upstream patches: the Android back-gesture fix was
one line; the shared-halt ownership fix was ~35 lines across three files. So
this is **roughly twice the size of our largest accepted patch** — not a large
feature by any absolute measure, and decomposable further.

Note the diff is *smaller* than the six-stage plan implied, because stages 3–5
collapse once the phase is a descriptor field: there is no separate "wire it up"
work.

## 2. Backwards compatibility — MEASURED

Upstream automated test suite, pak64 reference pakset, every roadsign in it a
**version-6 node** so the compatibility path is exercised throughout:

| Build | Result |
| --- | --- |
| control — unmodified r12092 | **201/201, "Tests completed successfully"** |
| spike — MVP applied | **201/201, "Tests completed successfully"** |

Identical. The version-7 reader defaults `phases = 1`, `animation_time = 0` for
every older node, and `is_animated()` is then false, so nothing changes.

### A trap found on the way, worth more than the result

The first two runs failed at test 91, `test_halt_make_public_single`, on **both**
the spike and the control. It was not the change: a stale copy of the test suite
at `simutrans/pak/scenario/automated-tests`, dated 2026-07-14 and therefore
predating r12091, still expects `null` where the current test expects
`"Das Feld gehoert\neinem anderen Spieler\n"`.

`pak/scenario/` takes precedence over `addons/pak/scenario/`, so a fresh copy
installed in `addons/` is **silently ignored**. Anyone running the suite on this
machine gets a false failure in a test unrelated to their work.

The stale directory has been left in place — it is not ours to delete — and the
runner script installs under a unique name instead.

**The control run is what caught this.** Without it the conclusion would have
been "the spike breaks the halt tests", which was false.

## 3. Runtime cost — NOT MEASURED

This is the claim the spike was built to settle, and it is **still unsettled**.

What was established:

- the instrumentation works: sync-list sizes and per-frame timings are reported;
- with the pak64 reference pakset, `sync_roadsigns` holds **0 objects** — but on
  a 64×64 intro map with **0 signals and 0 roadsigns**, so this proves nothing
  about a real network.

What blocked it:

- the only large savegame here (`save/aaaaa.sve`, 4 MB, ~18 MB uncompressed) is
  **pak128**, and pak128 is not installed on this machine;
- the reference pak64 intro map has no rail network to put signals on;
- `-until` runs in fast forward, which does not drive `karte_t::sync_step`, so
  the headless path yields no timing at all. A windowed, real-time run is
  required.

To settle it, one of: install pak128 and load that savegame; or build a rail
network of known size with a scenario script and sweep the signal count.

**Until then, "opt-in registration makes the runtime cost negligible" remains an
inference.** The structural half of it — that a pakset supplying one phase never
enters the sync list — is verifiable by reading the registration condition and
is not in doubt. The quantitative half is unmeasured.

## 4. What the MVP does not do

- no new signal states — `state:2` untouched;
- nothing added to `rdwr()`, so no savegame or network change;
- `sim_async_rand` for the starting phase, so signals do not blink in unison and
  the phase stays out of game state.

## 5. One design correction the spike forced

`simworld.cc` marks the boundary explicitly:

```cpp
/* animations do not require exact sync ... */
sync_buildings.sync_step(delta_t);
...
// the following sync_steps affect the game state
sync_roadsigns.sync_step(delta_t);
```

`sync_roadsigns` is on the **game-state** side. This MVP puts display-only
animation into it, which is expedient for a spike and wrong for a patch: a real
implementation wants its own list on the animation side, next to
`sync_buildings`. The staged plan said "animate inside the existing sync_step";
that was wrong and is corrected in the knowledge base.
