/*  RetroArch - A frontend for libretro.
 *  Copyright (C) 2011-2017 - Daniel De Matteis
 *
 *  RetroArch is free software: you can redistribute it and/or modify it under the terms
 *  of the GNU General Public License as published by the Free Software Found-
 *  ation, either version 3 of the License, or (at your option) any later version.
 *
 *  RetroArch is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
 *  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
 *  PURPOSE.  See the GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License along with RetroArch.
 *  If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef __RARCH_DEFAULTS_H
#define __RARCH_DEFAULTS_H

#include <stdint.h>

#include <boolean.h>

#include <retro_miscellaneous.h>

#ifndef IS_SALAMANDER
#include <utils/playlist.h>
#endif

enum default_dirs
{
   DEFAULT_DIR_START = 0,
   DEFAULT_DIR_MAIN_CONFIG,
   DEFAULT_DIR_REMAP,
   DEFAULT_DIR_AUTOCONFIG,
   DEFAULT_DIR_AUDIO_FILTER,
   DEFAULT_DIR_VIDEO_FILTER,
   DEFAULT_DIR_ASSETS,
   DEFAULT_DIR_CORE,
   DEFAULT_DIR_CORE_INFO,
   DEFAULT_DIR_OVERLAY,
   DEFAULT_DIR_OSK_OVERLAY,
   DEFAULT_DIR_SHADER,
   DEFAULT_DIR_USER_SHADER,
   DEFAULT_DIR_SAVESTATE,
   DEFAULT_DIR_SRAM,
   DEFAULT_DIR_SCREENSHOT,
   DEFAULT_DIR_PLAYLIST,
   DEFAULT_DIR_CACHE,
   DEFAULT_DIR_THUMBNAILS,
   DEFAULT_DIR_DATABASE,
   DEFAULT_DIR_CHEATS,
   DEFAULT_DIR_RECORD_CONFIG,
   DEFAULT_DIR_RECORD_OUTPUT,
   DEFAULT_DIR_LOGS,
   DEFAULT_DIR_BUNDLE_ROOT,
   DEFAULT_DIR_USER_DOCUMENT,
   DEFAULT_DIR_LAST
};

struct defaults
{
#ifndef IS_SALAMANDER
   playlist_t *content_history;
   playlist_t *content_favorites;
#ifdef HAVE_IMAGEVIEWER
   playlist_t *image_history;
#endif
   playlist_t *music_history;
#if defined(HAVE_FFMPEG) || defined(HAVE_MPV)
   playlist_t *video_history;
#endif
#endif // !IS_SALAMANDER
   int settings_out_latency;
   int settings_in_latency;

   float settings_video_refresh_rate;

   char dirs [DEFAULT_DIR_LAST + 1][DIR_MAX_LENGTH];
   char path_config[PATH_MAX_LENGTH];
   char settings_menu[32];

   bool overlay_set;
   bool overlay_enable;
};

bool dir_set_defaults(enum default_dirs dir_type, const char *dirpath);

/* Public data structures. */
extern struct defaults g_defaults;

#endif // !__RARCH_DEFAULTS_H
