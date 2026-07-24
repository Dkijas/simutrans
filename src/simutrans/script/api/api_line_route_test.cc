/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#include "api.h"

/** @file api_line_route_test.cc
 * Test/demo-only hooks for the "Show route on map" line-route overlay.
 *
 * These drive the overlay through its REAL code path: they create the actual line
 * management window (create_win), run the exact action the button runs
 * (line_management_gui_t::toggle_route_overlay), and close it (destroy_win -> WIN_CLOSE),
 * then expose the overlay's route-computation diagnostic counters so a headless scenario
 * can assert invariants. Tiles marked by the overlay are read back from Squirrel with the
 * existing tile_x.is_marked() / map_object_x.is_marked().
 *
 * This is NOT part of the product feature. It is only registered when a scenario is running
 * and lives in its own file so it can be excluded from any upstream patch.
 */

#include "../api_class.h"
#include "../api_function.h"

#include "../../simline.h"
#include "../../simconvoi.h"
#include "../../simversion.h"
#include "../../world/simworld.h"
#include "../../player/simplay.h"
#include "../../gui/line_management_gui.h"
#include "../../gui/simwin.h"
#include "../../tool/simtool.h" // tool_line_route_overlay_t diagnostic counters
#include "../../ground/grund.h"
#include "../../tpl/vector_tpl.h"
#include "../../dataobj/koord3d.h"

using namespace script_api;


// The line window uses (ptrdiff_t)line.get_rep() as its magic (see schedule_list.cc /
// depot_frame.cc), so we can find/close exactly the real window here.
static ptrdiff_t line_win_magic(linehandle_t line)
{
	return (ptrdiff_t)line.get_rep();
}


// Open the real line management window for this line (idempotent).
static SQInteger lrt_open(HSQUIRRELVM vm)
{
	linehandle_t line = param<linehandle_t>::get(vm, 1);
	bool ok = false;
	if(  line.is_bound()  &&  line->get_owner()  ) {
		const ptrdiff_t magic = line_win_magic(line);
		if(  win_get_magic(magic) == NULL  ) {
			// open on tab 1 (Chart), not the schedule tab: that keeps the separate schedule-stop
			// highlight (visualize_schedule) off, so the test observes only the route overlay.
			create_win( new line_management_gui_t( line, line->get_owner(), 1 ), w_info, magic );
		}
		ok = win_get_magic(magic) != NULL;
	}
	sq_pushbool(vm, ok);
	return 1;
}


// Run the exact button action (toggle) on the already-open window.
static SQInteger lrt_click(HSQUIRRELVM vm)
{
	linehandle_t line = param<linehandle_t>::get(vm, 1);
	if(  line.is_bound()  ) {
		gui_frame_t *w = win_get_magic( line_win_magic(line) );
		// identify the line window by its rdwr id (no dynamic_cast, matching engine style)
		if(  w  &&  w->get_rdwr_id() == magic_line_schedule_rdwr_dummy  ) {
			static_cast<line_management_gui_t*>(w)->toggle_route_overlay();
		}
	}
	return 0;
}


// Close the real window (fires WIN_CLOSE, which clears the overlay).
static SQInteger lrt_close(HSQUIRRELVM vm)
{
	linehandle_t line = param<linehandle_t>::get(vm, 1);
	if(  line.is_bound()  ) {
		destroy_win( line_win_magic(line) );
	}
	return 0;
}


// tile_x.is_route_marked(): is this tile part of the drawn line-route overlay path? The route is
// now drawn procedurally (not via the highlight bit), so the bench verifies it through this query.
static bool tile_in_route_overlay(grund_t *gr)
{
	if(  gr == NULL  ) {
		return false;
	}
	const koord3d pos = gr->get_pos();
	for(  koord3d const& p : world()->get_line_route_overlay()  ) {
		if(  p == pos  ) {
			return true;
		}
	}
	return false;
}


static SQInteger lrt_calc_count(HSQUIRRELVM vm)         { sq_pushinteger(vm, (SQInteger)tool_line_route_overlay_t::calc_route_call_count);     return 1; }
static SQInteger lrt_segments_attempted(HSQUIRRELVM vm) { sq_pushinteger(vm, (SQInteger)tool_line_route_overlay_t::last_segments_attempted);   return 1; }
static SQInteger lrt_segments_valid(HSQUIRRELVM vm)     { sq_pushinteger(vm, (SQInteger)tool_line_route_overlay_t::last_segments_valid);       return 1; }
static SQInteger lrt_segments_failed(HSQUIRRELVM vm)    { sq_pushinteger(vm, (SQInteger)tool_line_route_overlay_t::last_segments_failed);      return 1; }
static SQInteger lrt_tiles(HSQUIRRELVM vm)              { sq_pushinteger(vm, (SQInteger)tool_line_route_overlay_t::last_route_tiles);          return 1; }


// Save the current world to a .sve for the persistent demo game (Phase 7).
static SQInteger lrt_save(HSQUIRRELVM vm)
{
	const char *fn = param<const char*>::get(vm, 2);
	bool ok = false;
	if(  fn  &&  *fn  ) {
		world()->save( fn, false, SAVEGAME_VER_NR, true );
		ok = true;
	}
	sq_pushbool(vm, ok);
	return 1;
}


// Registered only in scenario mode. Adds test-only methods to the existing line_x class.
void export_line_route_test(HSQUIRRELVM vm, bool scenario)
{
	if(  !scenario  ) {
		return;
	}
	begin_class(vm, "line_x", 0);

	register_function(vm, &lrt_open,               "test_route_open",               1, param<linehandle_t>::typemask());
	register_function(vm, &lrt_click,              "test_route_click",              1, param<linehandle_t>::typemask());
	register_function(vm, &lrt_close,              "test_route_close",              1, param<linehandle_t>::typemask());
	register_function(vm, &lrt_calc_count,         "test_route_calc_count",         1, param<linehandle_t>::typemask());
	register_function(vm, &lrt_segments_attempted, "test_route_segments_attempted", 1, param<linehandle_t>::typemask());
	register_function(vm, &lrt_segments_valid,     "test_route_segments_valid",     1, param<linehandle_t>::typemask());
	register_function(vm, &lrt_segments_failed,    "test_route_segments_failed",    1, param<linehandle_t>::typemask());
	register_function(vm, &lrt_tiles,              "test_route_tiles",              1, param<linehandle_t>::typemask());
	register_function(vm, &lrt_save,               "test_route_save_game",          2, "x s");

	end_class(vm);

	// tile_x.is_route_marked(): read back the drawn route overlay (path now procedural, not flagged)
	begin_class(vm, "tile_x", 0);
	register_method(vm, &tile_in_route_overlay, "is_route_marked", true);
	end_class(vm);
}
