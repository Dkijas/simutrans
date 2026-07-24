/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#include "api.h"

/** @file api_line_route_test.cc
 * Test/demo-only hooks for the "Show route on map" line-route overlay.
 *
 * These drive the overlay through its REAL code path: they create the actual line management
 * window (create_win), issue the real product tool (TOOL_LINE_ROUTE_OVERLAY, the exact request
 * the button makes), and close the window (destroy_win -> WIN_CLOSE), then read the overlay's real
 * world-side state (route size, separators, stop count, shown-line id) so a headless scenario can
 * assert invariants. No product method is exposed just for the harness. Tiles on the drawn route
 * are read back with tile_x.is_route_marked().
 *
 * This is NOT part of the product feature. It is only registered when a scenario is running and
 * lives in its own file so it can be excluded from any upstream patch.
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
#include "../../tool/simmenu.h" // create_tool, TOOL_LINE_ROUTE_OVERLAY (issue the real product tool)
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


// Toggle the overlay for this line through the REAL product tool (exactly what the button issues):
// show this line's route if it is not the one currently shown, otherwise clear. No GUI internals.
static SQInteger lrt_click(HSQUIRRELVM vm)
{
	linehandle_t line = param<linehandle_t>::get(vm, 1);
	if(  line.is_bound()  ) {
		karte_t *welt = world();
		const bool already_shown = ( welt->get_line_route_overlay_line() == line );
		char param_buf[16];
		if(  !already_shown  ) {
			sprintf( param_buf, "s,%u", (unsigned)line.get_id() );
		}
		else {
			sprintf( param_buf, "c" );
		}
		tool_t *tool = create_tool( TOOL_LINE_ROUTE_OVERLAY | SIMPLE_TOOL );
		tool->set_default_param( param_buf );
		welt->set_tool( tool, line->get_owner() );
		delete tool;
	}
	return 0;
}


// Close the real window (fires WIN_CLOSE, which clears the overlay only if this line owns it).
static SQInteger lrt_close(HSQUIRRELVM vm)
{
	linehandle_t line = param<linehandle_t>::get(vm, 1);
	if(  line.is_bound()  ) {
		destroy_win( line_win_magic(line) );
	}
	return 0;
}


// tile_x.is_route_marked(): is this tile part of the drawn line-route overlay path? The route is
// drawn procedurally (not via the highlight bit), so the bench verifies it through this query.
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


// Real world-side overlay state (product, not harness telemetry): route tile count, whether the
// route contains an explicit break separator, the number of highlighted stop tiles, and the id of
// the line currently shown (0 = none).
static SQInteger lrt_overlay_size(HSQUIRRELVM vm)  { sq_pushinteger(vm, (SQInteger)world()->get_line_route_overlay().get_count());       return 1; }
static SQInteger lrt_stop_count(HSQUIRRELVM vm)    { sq_pushinteger(vm, (SQInteger)world()->get_line_route_overlay_stops().get_count()); return 1; }
static SQInteger lrt_active_line_id(HSQUIRRELVM vm)
{
	const linehandle_t l = world()->get_line_route_overlay_line();
	sq_pushinteger(vm, (SQInteger)( l.is_bound() ? l.get_id() : 0 ));
	return 1;
}
static SQInteger lrt_has_separator(HSQUIRRELVM vm)
{
	bool sep = false;
	for(  koord3d const& p : world()->get_line_route_overlay()  ) {
		if(  p == koord3d::invalid  ) {
			sep = true;
			break;
		}
	}
	sq_pushbool(vm, sep);
	return 1;
}
// Is THIS line the one currently shown? This is exactly the button's source of truth (karte_t), so
// the bench can assert per-window button state without reading the GUI.
static SQInteger lrt_is_active(HSQUIRRELVM vm)
{
	linehandle_t line = param<linehandle_t>::get(vm, 1);
	sq_pushbool(vm, line.is_bound()  &&  world()->get_line_route_overlay_line() == line);
	return 1;
}


// Save the current world to a .sve for the persistent demo game.
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

	register_function(vm, &lrt_open,            "test_route_open",         1, param<linehandle_t>::typemask());
	register_function(vm, &lrt_click,           "test_route_click",        1, param<linehandle_t>::typemask());
	register_function(vm, &lrt_close,           "test_route_close",        1, param<linehandle_t>::typemask());
	register_function(vm, &lrt_overlay_size,    "test_route_overlay_size", 1, param<linehandle_t>::typemask());
	register_function(vm, &lrt_stop_count,      "test_route_stop_count",   1, param<linehandle_t>::typemask());
	register_function(vm, &lrt_active_line_id,  "test_route_active_line",  1, param<linehandle_t>::typemask());
	register_function(vm, &lrt_is_active,       "test_route_is_active",    1, param<linehandle_t>::typemask());
	register_function(vm, &lrt_has_separator,   "test_route_has_separator",1, param<linehandle_t>::typemask());
	register_function(vm, &lrt_save,            "test_route_save_game",    2, "x s");

	end_class(vm);

	// tile_x.is_route_marked(): read back the drawn route overlay (path is procedural, not flagged)
	begin_class(vm, "tile_x", 0);
	register_method(vm, &tile_in_route_overlay, "is_route_marked", true);
	end_class(vm);
}
