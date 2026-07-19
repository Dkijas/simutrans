# Results

Measured 2026-07-19 on branch `spike/signal-animation-cost`, off `65a2deb`
(r12092). **Throwaway spike. Not a patch, not offered to anyone.**

Second session: pak128 2.10.1 installed, a measurement scenario written, and the
runtime cost finally measured. Three defects were found in the process, two of
them in the MVP this file previously reported as complete.

## 1. Runtime cost — MEASURED

Scenario `tests-signalload/`: a serpentine of rail across `empty-16x16.sve` with
a known number of signals, run **windowed and in real time** (`-until`
fast-forwards and never drives `karte_t::sync_step`, which is what defeated the
first attempt). Timings are `sync_roadsigns.sync_step()` only. Three consecutive
600-frame reports per arm, pak128 2.10.1, `Classic_Signals_right`.

| Signals on map | In sync list | ns/frame |
| --- | --- | --- |
| 0 | 0 | 35, 36, 40 |
| **42, opt-in registration** | **0** | **35, 36, 36** |
| 42, all animating (worst case) | 42 | 1098, 1121, 1241 |
| 84, all animating (worst case) | 84 | 1409, 1433, 1484 |

A frame at 25 fps is **40,000,000 ns**.

**The opt-in claim is now evidence, not inference.** 42 signals stand on the map
and the sync list holds zero, at a cost indistinguishable from an empty map. A
pakset that does not use the feature pays nothing — not "nearly nothing".

**The worst case is also cheap**: every signal animating costs 1.4 µs/frame at
84 signals, or **0.0036% of a frame**.

### What these numbers do not cover

- **Measured range is 0–84 signals.** 16x16 is the only empty map available
  here, and it sets the ceiling. Anything beyond 84 is arithmetic, not
  measurement. The two non-zero points are not cleanly linear (~6.9 ns per extra
  signal between them, over a fixed ~860 ns that appears as soon as the list is
  non-empty), so extrapolation should be quoted as a range, not a slope.
- **This times the sync-list walk, not the redraw.** Each phase change calls
  `mark_image_dirty()` and `set_flag(dirty)`. The extra *drawing* that causes is
  not in this number and is plausibly larger than what is. Unmeasured.
- Animation rate measured is one phase change per 600 ms of game time.

## 2. Three defects found while measuring

None of these were visible from reading the code, and the first two were in the
MVP that the previous session reported as finished.

### 2a. The instrumentation could not measure this at all

`dr_time()` is `timeGetTime()`/`SDL_GetTicks()` — **milliseconds**. The per-frame
cost here is tens to hundreds of nanoseconds, so every delta rounded to zero and
the total read `0 ms`. That is not "free", it is "below the clock", and it would
have been reported as the former. Now `std::chrono::steady_clock`, in ns.

### 2b. A dangling pointer in the MVP

Registration was `automatic || is_animated()`. The destructor removed only
`if (automatic)`. **An animated sign entered `sync_roadsigns` and was never
removed.**

It survived 201/201 because pak64's roadsigns are all version-6 nodes, so
`is_animated()` was false everywhere and the new branch never ran once. **The
suite passed because the feature was never switched on.** A green suite said
nothing about this code.

Fixed by recording the fact in `roadsign_t::in_sync_list` rather than
re-deriving it, so the two conditions cannot drift again.

### 2c. `sync_roadsigns` deletes rail signals

The bigger one. Past the `is_private_way()` branch, `roadsign_t::sync_step()`
asks the tile for ribi of waytype **road**:

```cpp
ribi_t::ribi r = gr->get_weg_ribi_unmasked(road_wt);
if (ribi_t::none == r || ...) return SYNC_DELETE;
```

A rail signal has no road, gets `ribi_t::none`, and returns `SYNC_DELETE` — which
is `delete ss` at `simworld.h:1078`. Putting rail signals in that list does not
merely cost ticks: **it destroys them on the first frame.**

Confirmed empirically before it was understood: the first worst-case run
registered 42 signals and reported a list of **0 objects** with a single 99 ns
spike. Had that been read at face value the conclusion would have been "animating
every signal is free", from a list that had emptied itself.

This turns the Stage 4 correction from a style preference into a hard
requirement. A real patch needs its own list **and its own sync_step**; the
existing one is road-only by construction.

### 2d. A one-phase sign with a moving counter indexes past its image list

Found by Victor, watching the window — signals blinking out and reappearing.

```cpp
uint16 get_phase_stride() const { return phases > 1 ? get_count() / phases : get_count(); }
```

With `phases == 1` the stride is the **entire image list**, so any non-zero
`anim_frame` sends `offset` past the end, every lookup returns `IMG_EMPTY`, and
the signal is drawn as nothing until the counter wraps.

It is only safe while `anim_frame` is always 0 for a one-phase sign — an
unwritten invariant, of exactly the kind this work is meant to remove. Now
guarded on `get_phases() > 1` in `signal_t::calc_image()`.

**This is invisible in the log.** The instrumentation reports timings and list
sizes; a missing image is silent. Four arms of coherent numbers were in hand and
the measurement would have been published with a contaminated worst case, because
`calc_image()` was failing early and doing less work than the real path.

Two rounds now where the check passed for the wrong reason: the suite passed
because the feature never ran, and the timings looked right because the work was
smaller than it should have been. Both failures sat in the part the check did not
look at.

## 3. Implementation cost — MEASURED, revised

| | insertions |
| --- | --- |
| the feature (descriptor, reader, writer, phase advance, image index) | ~92 |
| + spike-only instrumentation and worst-case switch | 207 total |

Still roughly twice our largest accepted upstream patch. The +7 over the original
85 is the `in_sync_list` fix and the phase guard — both of which a correct patch
needs.

## 4. Backwards compatibility — MEASURED, re-confirmed

| Build | Result |
| --- | --- |
| control — unmodified r12092 | 201/201 |
| spike — original MVP | 201/201 |
| spike — after all three fixes | **201/201** |

With the caveat established in 2b: pak64 exercises the *compatibility* path
thoroughly (every roadsign a version-6 node defaulting to one phase) and the
*feature* path not at all.

### The stale test suite, still there

`simutrans/pak/scenario/automated-tests`, dated 2026-07-14, predates r12091 and
takes precedence over `addons/`. It produces a false failure in test 91 for
anyone running the suite on this machine. Left in place — not ours to delete —
and the runner installs under a unique name.

## 5. What is still not answered

**prissi's objection is about design, and none of this touches it.** These
numbers remove invented figures from the discussion; they do not win it. Stage 0
stands.

Also unresolved: pakset size. An animated signal at 4 phases needs 32 images
instead of 8, and that — not ticks — is what the forum thread was actually
arguing about. Not measured.

## 6. An unrelated finding

`save/aaaaa.sve` (3.9 MB, pak128) **does not load with pak128 2.10.1**: 260,073
`position error` warnings with heights at half their expected value
(`-4 instead -8`), then `pure virtual function call`.

An unmodified control build crashes identically, so this is a pakset version
mismatch and not the spike. The savegame needs the pak128 it was made with. The
file was only read and is unchanged.
