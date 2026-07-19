//
// SPIKE: reproduce forum 23991 - an elevated road does not stop the buildings
// underneath it from being renovated into taller ones.
//
// Not a test, not for upstream. The detection is in the engine: a SPIKE-RENOVATE
// message in world/simcity.cc fires whenever renovate_city_building picks a
// replacement for a tile that has an elevated way above it, and says whether
// that replacement draws anything at height 1 - which is exactly the predicate
// wegbauer.cc:609 uses to REFUSE building the elevated way over it in the first
// place.
//
// This scenario only has to build the situation. Renovation lives in step(),
// not sync_step(), so -until fast-forward drives it and the run can be headless.
//

map.file = "empty-16x16.sve"

scenario.short_description = "SPIKE elevated renovate"
scenario.author = "spike"
scenario.version = "0.1"

// player 1 is the public player: it has the rights and the money for tools like
// tool_add_city (see tests/tests/test_city.nut).
const PUBLIC = 1


function find_city_buildings()
{
    local found = []
    for (local y = 0; y < 16; y++) {
        for (local x = 0; x < 16; x++) {
            local t = tile_x(x, y, 0)
            if (t.find_object(mo_building) != null) {
                found.append(coord(x, y))
            }
        }
    }
    return found
}


function pick_elevated_way()
{
    local ways = way_desc_x.get_available_ways(wt_road, st_elevated)
    print("SPIKE-SCEN: " + ways.len() + " elevated road type(s) available")
    foreach (w in ways) {
        print("SPIKE-SCEN:   " + w.get_name())
    }
    return ways.len() > 0 ? ways[0] : null
}


// Find the longest straight east-west run of city buildings, so the elevated
// road actually passes OVER houses rather than beside them. That is the whole
// point: a road that misses the buildings reproduces nothing.
function best_row(cells)
{
    local rows = {}
    foreach (c in cells) {
        if (!(c.y in rows)) { rows[c.y] <- [] }
        rows[c.y].append(c.x)
    }
    local best_y = -1, best_n = 0
    foreach (y, xs in rows) {
        if (xs.len() > best_n) { best_n = xs.len(); best_y = y }
    }
    return [best_y, best_n]
}


function start()
{
    local pl = player_x(PUBLIC)

    print("SPIKE-SCEN: ==== building a city ====")
    local err = command_x(tool_add_city).work(pl, coord3d(8, 8, 0))
    print("SPIKE-SCEN: add_city -> " + (err == null ? "ok" : err))

    // ORDER MATTERS, and getting it wrong is what the first attempt did.
    //
    // makie's case is: the elevated road goes up over SHORT buildings, which the
    // engine permits, and the problem appears later when those buildings
    // renovate. Growing the city first and then trying to build the road
    // reproduces nothing - wegbauer correctly refuses, because by then the
    // buildings are tall. The run before this one returned an empty error
    // string from build_way for exactly that reason.
    //
    // So: a SMALL city first, road over it while it is still low-rise, then
    // grow and let time run.
    //
    // tool_change_city_size_t reads atoi(default_param) (simtool.h:217), and
    // work() takes the param as its third argument (api_command.cc:155).
    local g = command_x(tool_change_city_size).work(pl, coord3d(8, 8, 0), "400")
    print("SPIKE-SCEN: initial small growth -> " + (g == null ? "ok" : "'" + g + "'"))

    local cells = find_city_buildings()
    print("SPIKE-SCEN: " + cells.len() + " city building tiles")
    if (cells.len() == 0) {
        print("SPIKE-SCEN: no city, nothing to reproduce")
        return
    }

    local way = pick_elevated_way()
    if (way == null) {
        print("SPIKE-SCEN: no elevated road available in this year, aborting")
        return
    }

    // Try every row, densest first. wegbauer refuses a row that already holds a
    // building drawing at height 1, and that refusal is the CORRECT half of the
    // behaviour under investigation - so a failure here is information, not an
    // error. Note build_way signals refusal with an EMPTY STRING, not null and
    // not a message, which is easy to print as success by accident.
    local rows = {}
    foreach (c in cells) {
        if (!(c.y in rows)) { rows[c.y] <- 0 }
        rows[c.y] += 1
    }
    local order = []
    foreach (y, n in rows) { order.append([y, n]) }
    order.sort(@(a, b) b[1] <=> a[1])

    local built_y = -1
    foreach (row in order) {
        local y = row[0]
        local e = command_x.build_way(pl, coord3d(0, y, 0), coord3d(15, y, 0), way, true)
        print("SPIKE-SCEN: elevated road along y=" + y + " (" + row[1]
              + " buildings) -> " + (e == null ? "ok" : "refused '" + e + "'"))
        if (e == null) { built_y = y; break }
    }
    if (built_y < 0) {
        print("SPIKE-SCEN: no row would take an elevated road, nothing to reproduce")
        return
    }

    local under = 0
    foreach (c in cells) {
        if (c.y == built_y) { under++ }
    }
    print("SPIKE-SCEN: ==== " + under + " city buildings under the elevated road at y="
          + built_y + " ====")

    // NOW grow the city hard, so those buildings get renovated with the road
    // already overhead. This is makie's sequence, in order.
    for (local i = 0; i < 6; i++) {
        command_x(tool_change_city_size).work(pl, coord3d(8, 8, 0), "2000")
    }
    print("SPIKE-SCEN: grown; watch for SPIKE-RENOVATE lines from the engine")
}


function is_scenario_completed(pl) { return 0 }

function get_rule_text(pl)   { return ttext("SPIKE: reproduction scenario.") }
function get_goal_text(pl)   { return ttext("None.") }
function get_info_text(pl)   { return ttext("Builds a city and an elevated road over it.") }
function get_result_text(pl) { return ttext("See SPIKE-RENOVATE in the log.") }
