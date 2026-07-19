//
// SPIKE: a rail network of KNOWN signal count, to measure what animating
// signals costs per frame. Not a test, not for upstream.
//
// The measurement it feeds lives in ../RESULTS.md. The engine side is the
// SPIKE instrumentation in world/simworld.cc, which reports the size and the
// nanosecond cost of sync_roadsigns every 600 frames.
//
// How many signals get built is read from the environment, so one scenario
// serves the whole sweep and the runs cannot differ by an edit:
//
//     SPIKE_SIGNAL_STRIDE=0   no signals at all (the baseline)
//     SPIKE_SIGNAL_STRIDE=2   a signal every 2 tiles of track
//     SPIKE_SIGNAL_STRIDE=1   a signal on every tile it will take
//

map.file = "empty-16x16.sve"

scenario.short_description = "SPIKE signal load"
scenario.author = "spike"
scenario.version = "0.1"


// empty-16x16.sve is the only empty map available here, so the ceiling on this
// experiment is set by 16x16 tiles, not by choice. Leave a margin at the edges:
// build_way needs somewhere to put the curve.
const MAP_MIN = 1
const MAP_MAX = 14


function stride_from_env()
{
	// script.cc:144 registers only the string, math and system libraries -- there
	// is no iolib, so no file(). systemlib does provide getenv, which is how the
	// sweep parameter gets in.
	try {
		local s = getenv("SPIKE_SIGNAL_STRIDE")
		if (s == null || s == "") { return 0 }
		return s.tointeger()
	}
	catch (e) {
		print("SPIKE-SCEN: getenv failed (" + e + "), defaulting to 0")
		return 0
	}
}


// Lay a serpentine so the whole map is one connected run of track: east along a
// row, one tile south, west along the next. Straight segments only -- signals go
// on straight track, and a serpentine maximises how much straight track fits.
function build_network()
{
	local pl = player_x(0)
	local rail = way_desc_x.get_available_ways(wt_rail, st_flat)[0]
	if (rail == null) {
		print("SPIKE-SCEN: no rail way available, aborting")
		return []
	}
	print("SPIKE-SCEN: rail = " + rail.get_name())

	local rows = []
	local built = 0
	local failed = 0

	for (local y = MAP_MIN; y <= MAP_MAX; y += 2) {
		local err = command_x.build_way(pl, coord3d(MAP_MIN, y, 0),
		                                    coord3d(MAP_MAX, y, 0), rail, true)
		if (err == null) {
			rows.append(y)
			built++
		}
		else {
			failed++
			if (failed <= 3) { print("SPIKE-SCEN: row " + y + " failed: " + err) }
		}
	}

	print("SPIKE-SCEN: " + built + " rows of track built, " + failed + " failed")
	return rows
}


function place_signals(rows, stride)
{
	if (stride <= 0) {
		print("SPIKE-SCEN: stride 0 -- baseline, no signals placed")
		return 0
	}

	local pl = player_x(0)
	local signals = sign_desc_x.get_available_signs(wt_rail).filter(
		@(idx, s) s.is_signal())
	if (signals.len() == 0) {
		print("SPIKE-SCEN: no rail signal available in this pakset, aborting")
		return 0
	}
	local sig = signals[0]
	print("SPIKE-SCEN: signal = " + sig.get_name()
	      + " (of " + signals.len() + " available)")

	local placed = 0
	local refused = 0
	local first_error = null

	foreach (y in rows) {
		// Skip the very ends of the row: a signal wants track on both sides.
		for (local x = MAP_MIN + 1; x < MAP_MAX; x += stride) {
			local err = command_x.build_sign_at(pl, coord3d(x, y, 0), sig)
			if (err == null) {
				placed++
			}
			else {
				refused++
				if (first_error == null) { first_error = err }
			}
		}
	}

	print("SPIKE-SCEN: " + placed + " signals placed, " + refused + " refused"
	      + (first_error == null ? "" : " (first refusal: " + first_error + ")"))
	return placed
}


function start()
{
	local stride = stride_from_env()
	print("SPIKE-SCEN: ==== stride " + stride + " ====")

	local rows = build_network()
	local n = place_signals(rows, stride)

	// This is the number the RESULTS table is keyed on. The engine reports the
	// sync-list size independently; the two must agree, and if they do not, the
	// opt-in registration condition is not doing what it claims.
	print("SPIKE-SCEN: ==== signals placed: " + n + " ====")
}


function is_scenario_completed(pl)
{
	// Never completes: the run has to keep stepping so the instrumentation can
	// report. The shell script kills it on a timeout.
	return 0
}


function get_rule_text(pl)   { return ttext("SPIKE: measurement scenario.") }
function get_goal_text(pl)   { return ttext("None. This scenario is a stopwatch.") }
function get_info_text(pl)   { return ttext("Builds track and a known number of signals.") }
function get_result_text(pl) { return ttext("See the SPIKE lines in the log.") }
