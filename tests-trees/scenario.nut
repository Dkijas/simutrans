//
// SPIKE: do trees survive under an elevated way, and does anything stop them?
// Forum 23991, Vaclav's follow-up.
//
// Not a test, not for upstream. NO ENGINE INSTRUMENTATION IS NEEDED: the script
// API exposes mo_tree and tool_plant_tree, so the whole thing is observable from
// here and no patched binary can colour the result.
//
// Three rows, three questions:
//
//   y=3   plant trees, then build a GROUND road over them.
//         CONTROL. The claim being tested is that a ground way replaces the
//         tile and takes the tree with it. If this row keeps its trees, the
//         explanation for the whole issue is wrong.
//
//   y=6   plant trees, then build an ELEVATED way over them.
//         Route 1, the common one: the trees were there first.
//
//   y=9   build an ELEVATED way first, then try to plant underneath.
//         Route 2: does tool_plant_tree refuse when something is overhead?
//

map.file = "empty-16x16.sve"

scenario.short_description = "SPIKE trees under elevated ways"
scenario.author = "spike"
scenario.version = "0.1"

const PUBLIC = 1
const XMIN = 2
const XMAX = 13


function count_trees(y)
{
    local n = 0
    for (local x = XMIN; x <= XMAX; x++) {
        if (tile_x(x, y, 0).find_object(mo_tree) != null) { n++ }
    }
    return n
}


function plant_row(pl, y)
{
    // No default_param at all: simtool.cc:2406 takes that branch and plants a
    // random tree up to max_no_of_trees_on_square.
    local planted = 0, refused = 0, first_err = null
    for (local x = XMIN; x <= XMAX; x++) {
        local e = command_x(tool_plant_tree).work(pl, coord3d(x, y, 0))
        if (e == null) { planted++ }
        else {
            refused++
            if (first_err == null) { first_err = e }
        }
    }
    print("SPIKE-TREE: y=" + y + " planting: " + planted + " ok, " + refused
          + " refused" + (first_err == null ? "" : " (first: '" + first_err + "')"))
    return planted
}


function build_road(pl, y, elevated)
{
    local ways = way_desc_x.get_available_ways(wt_road, elevated ? st_elevated : st_flat)
    if (ways.len() == 0) {
        print("SPIKE-TREE: no " + (elevated ? "elevated" : "flat") + " road available")
        return false
    }
    local w = ways[0]
    local e = command_x.build_way(pl, coord3d(XMIN, y, 0), coord3d(XMAX, y, 0), w, true)
    // build_way signals refusal with an EMPTY STRING, not null and not a message.
    print("SPIKE-TREE: y=" + y + " " + (elevated ? "ELEVATED" : "ground") + " road '"
          + w.get_name() + "' -> " + (e == null ? "built" : "refused '" + e + "'"))
    return e == null
}


function start()
{
    local pl = player_x(PUBLIC)

    print("SPIKE-TREE: ================ CONTROL: ground road ================")
    local before3 = plant_row(pl, 3)
    print("SPIKE-TREE: y=3 trees before: " + count_trees(3))
    build_road(pl, 3, false)
    print("SPIKE-TREE: y=3 trees AFTER ground road: " + count_trees(3))

    print("SPIKE-TREE: ============ ROUTE 1: trees first, then elevated ============")
    local before6 = plant_row(pl, 6)
    print("SPIKE-TREE: y=6 trees before: " + count_trees(6))
    build_road(pl, 6, true)
    print("SPIKE-TREE: y=6 trees AFTER elevated way: " + count_trees(6))

    print("SPIKE-TREE: ============ ROUTE 2: elevated first, then plant ============")
    local ok = build_road(pl, 9, true)
    print("SPIKE-TREE: y=9 trees before planting: " + count_trees(9))
    plant_row(pl, 9)
    print("SPIKE-TREE: y=9 trees AFTER planting under the deck: " + count_trees(9))

    print("SPIKE-TREE: ================ done ================")
}


function is_scenario_completed(pl) { return 0 }

function get_rule_text(pl)   { return ttext("SPIKE: tree reproduction.") }
function get_goal_text(pl)   { return ttext("None.") }
function get_info_text(pl)   { return ttext("Trees under elevated ways.") }
function get_result_text(pl) { return ttext("See SPIKE-TREE in the log.") }
