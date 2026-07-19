/*
 * This file is part of the Simutrans project under the Artistic License.
 * (see LICENSE.txt)
 */

#include <string>
#include <vector>
#include "../../dataobj/tabfile.h"
#include "../roadsign_desc.h"
#include "obj_node.h"
#include "text_writer.h"
#include "imagelist_writer.h"
#include "roadsign_writer.h"
#include "get_waytype.h"
#include "skin_writer.h"


static const char* private_sign_directions[] = {"ns", "ew"};
static const char* traffic_light_directions[] = {"n", "s", "w", "e", "nw", "se", "sw", "ne"};
static const char* general_sign_directions[] = {"n", "s", "w", "e"};

// MVP SPIKE: parse "image[direction][state][phase]".
//
// This did not exist. The first version of this spike added `phases` to the node
// and multiplied anim_frame by a stride in signal_t::calc_image, but there was no
// syntax to SUPPLY the extra images - the list still only ever held one phase, so
// the stride indexed off the end of it. That MVP was reported as "complete
// end-to-end" and was not: the data path was missing altogether, and nothing
// caught it because no pakset had ever asked for a second phase.
//
// PHASE IS THE SLOWEST INDEX. The engine computes
//     dir + state*dir_cnt + phase*get_phase_stride()
// with get_phase_stride() == get_count()/phases, so one phase must be a whole
// contiguous copy of the direction-by-state layout. Any other order shows a
// different ASPECT per frame, which is not a graphical glitch.
//
// Returns the number of states found, or 0 if this object has no 3d images.
static uint8 parse_images_3d(slist_tpl<std::string>& keys, tabfileobj_t& obj,
                             roadsign_desc_t::types flags, uint8 phases)
{
	// Same direction table as the 2d path, chosen the same way, so the two can
	// never disagree about what counts as a traffic light.
	const char** directions;
	uint8 dir_cnt;
	if(  flags&roadsign_desc_t::PRIVATE_ROAD  ) {
		directions = private_sign_directions;
		dir_cnt = lengthof(private_sign_directions);
	}
	else if(  *obj.get("image[ne][0]")  ||  *obj.get("image[ne][0][0]")  ) {
		directions = traffic_light_directions;
		dir_cnt = lengthof(traffic_light_directions);
	}
	else {
		directions = general_sign_directions;
		dir_cnt = lengthof(general_sign_directions);
	}

	char buf[64];
	sprintf(buf, "image[%s][0][0]", directions[0]);
	if(  !*obj.get(buf)  ) {
		return 0; // not a phased object; the 2d parser handles it
	}

	// How many states does phase 0 declare? Same discovery rule as the 2d path.
	uint8 states = 0;
	for(  uint8 state = 0;  state < 8;  state++  ) {
		sprintf(buf, "image[%s][%i][0]", directions[0], state);
		if(  !*obj.get(buf)  ) {
			break;
		}
		states++;
	}

	for(  uint8 phase = 0;  phase < phases;  phase++  ) {
		for(  uint8 state = 0;  state < states;  state++  ) {
			for(  uint8 idx = 0;  idx < dir_cnt;  idx++  ) {
				sprintf(buf, "image[%s][%i][%i]", directions[idx], state, phase);
				const char* img = obj.get(buf);
				if(  !*img  ) {
					// Unlike the 2d parser there is nothing to infer: the phase
					// count is declared, so a hole is always an error.
					dbg->fatal("roadsign_writer",
						"%s is missing (phases=%i declares %i images)",
						buf, phases, phases*states*dir_cnt);
				}
				keys.append(img);
			}
		}
	}
	return states;
}


// parse "image[direction][state]" syntax
void parse_images_2d(slist_tpl<std::string>& keys, tabfileobj_t& obj, roadsign_desc_t::types flags)
{
	const char** directions;
	uint8 dir_cnt; // how many directions are there?
	if(  flags&roadsign_desc_t::PRIVATE_ROAD  ) {
		directions = private_sign_directions;
		dir_cnt = lengthof(private_sign_directions);
	}
	else if(  *obj.get("image[ne][0]")  ) {
		// Assume this is a traffic light.
		directions = traffic_light_directions;
		dir_cnt = lengthof(traffic_light_directions);
	}
	else {
		// Normal road sign or railway signal
		directions = general_sign_directions;
		dir_cnt = lengthof(general_sign_directions);
	}

	for(  uint8 state=0;  state<8;  state++  ) {
		for(  uint8 idx = 0;  idx < dir_cnt;  idx++  ) {
			char buf[64];
			sprintf(buf, "image[%s][%i]", directions[idx], state);
			const char* img = obj.get(buf);
			if(  !*img  ){
				if(  state>(dir_cnt==2)  &&  idx==0  ) {
					// Assume all further state numbers are invalid.
					return;
				}
				// image in the middle is missing => fatal error
				dbg->fatal("roadsign_writer", "%s is missing!", buf);
			}
			// append image number
			keys.append(img);
		}
	}
}


// parse "image[number]" syntax
void parse_images_numbered(slist_tpl<std::string>& keys, tabfileobj_t& obj)
{
	for (int i = 0; i < 32; i++) {
		char buf[40];
		sprintf(buf, "image[%i]", i);
		const char *str = obj.get(buf);
		// make sure, there are always 4, 8, 12, ... images (for all directions)
		if(  !*str  ) {
			if(  i % 4  ) {
				dbg->fatal("roadsign_writer", "image count is %d but must be multiple of 4!", i);
			}
			break;
		}
		keys.append(str);
	}
}


void roadsign_writer_t::write_obj(FILE* fp, obj_node_t& parent, tabfileobj_t& obj)
{
	const sint64           price       = obj.get_int64("cost",      500) * 100;
	const sint64           maintenance = obj.get_int64("maintenance", 0);
	const uint16           min_speed   = obj.get_int("min_speed",     0);
	const sint8            offset_left = obj.get_int("offset_left",  14);
	const uint8            wtyp        = get_waytype(obj.get("waytype"));
	roadsign_desc_t::types flags       = roadsign_desc_t::NONE;

	if(  obj.get_int("is_signal",0)   ) {
		flags = roadsign_desc_t::SIGN_SIGNAL;
		if(  obj.get_int("free_route",0)  ) {
			flags |= roadsign_desc_t::CHOOSE_SIGN;
		}
	}
	else if(  obj.get_int("is_presignal",0)   ) {
		flags = roadsign_desc_t::SIGN_PRE_SIGNAL;
	}
	else if(  obj.get_int("is_prioritysignal",0)   ) {
		flags = roadsign_desc_t::SIGN_PRIORITY_SIGNAL;
	}
	else if(  obj.get_int("is_longblocksignal",0)   ) {
		flags = roadsign_desc_t::SIGN_LONGBLOCK_SIGNAL;
	}
	else {
		// road or airsigns ...
		flags =
			(obj.get_int("single_way",         0) > 0 ? roadsign_desc_t::ONE_WAY               : roadsign_desc_t::NONE) |
			(obj.get_int("free_route",         0) > 0 ? roadsign_desc_t::CHOOSE_SIGN           : roadsign_desc_t::NONE) |
			(obj.get_int("is_private",         0) > 0 ? roadsign_desc_t::PRIVATE_ROAD          : roadsign_desc_t::NONE) |
			(obj.get_int("no_foreground",      0) > 0 ? roadsign_desc_t::ONLY_BACKIMAGE        : roadsign_desc_t::NONE) |
			(obj.get_int("end_of_choose",      0) > 0 ? roadsign_desc_t::END_OF_CHOOSE_AREA    : roadsign_desc_t::NONE);
	}
	// this causes unused entries to give a warning that they are ignored

	const uint8  phases         = obj.get_int("phases",         1);
	const uint16 animation_time = obj.get_int("animation_time", 0);

	obj_node_t node(this, 31, &parent);

	node.write_version(fp, 7);
	node.write_uint16(fp, min_speed);
	node.write_sint64(fp, price);
	node.write_sint64(fp, maintenance);
	node.write_uint16(fp, flags);
	node.write_uint8 (fp, offset_left);
	node.write_uint8 (fp, wtyp);

	uint16 intro_date = obj.get_int("intro_year", DEFAULT_INTRO_YEAR) * 12;
	intro_date += obj.get_int("intro_month", 1) - 1;
	node.write_uint16(fp, intro_date);

	uint16 retire_date = obj.get_int("retire_year", DEFAULT_RETIRE_YEAR) * 12;
	retire_date += obj.get_int("retire_month", 1) - 1;
	node.write_uint16(fp, retire_date);

	node.write_uint8 (fp, phases);
	node.write_uint16(fp, animation_time);

	write_name_and_copyright(fp, node, obj);

	// add the images
	slist_tpl<std::string> keys;

	if(  *obj.get("image[0]")  ) {
		// image[0] is defined.
		// assume that images are defined in image[number] syntax.
		parse_images_numbered(keys, obj);
	}
	else if(  parse_images_3d(keys, obj, flags, phases)  ) {
		// MVP SPIKE: image[direction][state][phase]. Returns 0 and consumes
		// nothing when the object has no phased images, so the 2d path below
		// stays the default and every existing pakset takes it.
	}
	else {
		// image[0] is not defined.
		// assume that images are defined in image[direction][state] syntax.
		parse_images_2d(keys, obj, flags);
	}
	imagelist_writer_t::instance()->write_obj(fp, node, keys);

	// probably add some icons, if defined
	slist_tpl<std::string> cursorkeys;

	const char *c = obj.get("cursor"), *i=obj.get("icon");
	cursorkeys.append(c);
	cursorkeys.append(i);
	if (*c || *i) {
		cursorskin_writer_t::instance()->write_obj(fp, node, obj, cursorkeys);
	}

	node.check_and_write_header(fp);
}
