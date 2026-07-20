//
// SPIKE check 3: does the same clipping gate misbehave for BUILDINGS?
//
// The loop in simplan.cc treats obj_t::baum and gebaeude_t identically, so if
// the divisor is wrong it should silence both. wegbauer refuses to lay an
// elevated way OVER a tall building, so the only way to get one underneath is
// to lay the way first and build after - which is exactly what this does.
//
// Row 12 is kept free of trees, so any SPIKE-CLIP line for y=12 is a building.
//

map.file = "empty-16x16.sve"

scenario.short_description = "SPIKE building clip"
scenario.author = "spike"
scenario.version = "0.1"

const PUBLIC = 1

function start()
{
    local pl = player_x(PUBLIC)

    local ways = way_desc_x.get_available_ways(wt_road, st_elevated)
    if (ways.len() == 0) { print("SPIKE-BLD: no elevated road"); return }
    local e = command_x.build_way(pl, coord3d(2, 12, 0), coord3d(13, 12, 0), ways[0], true)
    print("SPIKE-BLD: elevated way at y=12 -> " + (e == null ? "built" : "refused '" + e + "'"))
    if (e != null) { return }

    // No default_param: simtool.cc:6036 takes the "random attraction" branch.
    local built = 0, refused = 0, first = null
    for (local x = 2; x <= 13; x++) {
        local r = command_x(tool_build_house).work(pl, coord3d(x, 12, 0), "00RES_06_10")
        if (r == null) { built++ } else { refused++; if (first == null) { first = r } }
    }
    print("SPIKE-BLD: under the deck: " + built + " built, " + refused + " refused"
          + (first == null ? "" : " (first: '" + first + "')"))

    // CONTROL: same tool, same tiles, NO elevated way overhead. If these are
    // refused too, "No suitable ground!" is about something else entirely and
    // the deck proves nothing.
    local cb = 0, cr = 0, cf = null
    for (local x = 2; x <= 13; x++) {
        local r = command_x(tool_build_house).work(pl, coord3d(x, 14, 0), "00RES_06_10")
        if (r == null) { cb++ } else { cr++; if (cf == null) { cf = r } }
    }
    print("SPIKE-BLD: CONTROL row y=14 (no way): " + cb + " built, " + cr + " refused"
          + (cf == null ? "" : " (first: '" + cf + "')"))

    local n = 0
    for (local x = 2; x <= 13; x++) {
        if (tile_x(x, 12, 0).find_object(mo_building) != null) { n++ }
    }
    print("SPIKE-BLD: buildings now under the elevated way: " + n)
}

function is_scenario_completed(pl) { return 0 }
function get_rule_text(pl)   { return ttext("SPIKE") }
function get_goal_text(pl)   { return ttext("None") }
function get_info_text(pl)   { return ttext("Buildings under an elevated way") }
function get_result_text(pl) { return ttext("See SPIKE-BLD / SPIKE-CLIP") }
