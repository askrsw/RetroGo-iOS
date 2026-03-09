//
//  language_manager.h
//  RetroArch
//
//  Created by haharsw on 2025/10/5.
//

#ifndef __LANGUAGE_MANAGER_H
#define __LANGUAGE_MANAGER_H

#include <boolean.h>
#include <retro_inline.h>
#include <retro_common_api.h>

#include <libretro.h>

RETRO_BEGIN_DECLS

enum retro_language retroarch_get_language_from_iso(const char *lang);

unsigned *msg_hash_get_uint(enum msg_hash_action type);

void msg_hash_set_uint(enum msg_hash_action type, unsigned val);

RETRO_END_DECLS

#endif
