/*  RetroArch - A frontend for libretro.
 *  Copyright (C) 2010-2014 - Hans-Kristian Arntzen
 *  Copyright (C) 2011-2017 - Daniel De Matteis
 *  Copyright (C) 2016-2019 - Brad Parker
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

#ifndef _PLAYLIST_H__
#define _PLAYLIST_H__

#include <stddef.h>

#include <retro_common_api.h>
#include <boolean.h>
#include <lists/string_list.h>

#include <core/core_info.h>

/* Default maximum playlist size */
#define COLLECTION_SIZE 0x7FFFFFFF

RETRO_BEGIN_DECLS

enum playlist_runtime_status
{
   PLAYLIST_RUNTIME_UNKNOWN = 0,
   PLAYLIST_RUNTIME_MISSING,
   PLAYLIST_RUNTIME_VALID
};

enum playlist_file_mode
{
   PLAYLIST_LOAD = 0,
   PLAYLIST_SAVE
};

enum playlist_label_display_mode
{
   LABEL_DISPLAY_MODE_DEFAULT = 0,
   LABEL_DISPLAY_MODE_REMOVE_PARENTHESES,
   LABEL_DISPLAY_MODE_REMOVE_BRACKETS,
   LABEL_DISPLAY_MODE_REMOVE_PARENTHESES_AND_BRACKETS,
   LABEL_DISPLAY_MODE_KEEP_REGION,
   LABEL_DISPLAY_MODE_KEEP_DISC_INDEX,
   LABEL_DISPLAY_MODE_KEEP_REGION_AND_DISC_INDEX
};

enum playlist_thumbnail_mode
{
   PLAYLIST_THUMBNAIL_MODE_DEFAULT = 0,
   PLAYLIST_THUMBNAIL_MODE_OFF,
   PLAYLIST_THUMBNAIL_MODE_SCREENSHOTS,
   PLAYLIST_THUMBNAIL_MODE_TITLE_SCREENS,
   PLAYLIST_THUMBNAIL_MODE_BOXARTS,
   PLAYLIST_THUMBNAIL_MODE_LOGOS,

   PLAYLIST_THUMBNAIL_MODE_LAST
};

enum playlist_thumbnail_match_mode
{
   PLAYLIST_THUMBNAIL_MATCH_MODE_DEFAULT = 0,
   PLAYLIST_THUMBNAIL_MATCH_MODE_WITH_LABEL = PLAYLIST_THUMBNAIL_MATCH_MODE_DEFAULT,
   PLAYLIST_THUMBNAIL_MATCH_MODE_WITH_FILENAME
};

enum playlist_sort_mode
{
   PLAYLIST_SORT_MODE_DEFAULT = 0,
   PLAYLIST_SORT_MODE_ALPHABETICAL,
   PLAYLIST_SORT_MODE_OFF
};

/* Note: We already have a left/right enum defined
 * in gfx_thumbnail_path.h - but we can't include
 * menu code here, so have to make a 'duplicate'... */
enum playlist_thumbnail_id
{
   PLAYLIST_THUMBNAIL_RIGHT = 0,
   PLAYLIST_THUMBNAIL_LEFT,
   PLAYLIST_THUMBNAIL_ICON
};

enum playlist_thumbnail_name_flags
{
   PLAYLIST_THUMBNAIL_FLAG_INVALID          = 0,
   PLAYLIST_THUMBNAIL_FLAG_FULL_NAME        = (1 << 0),
   PLAYLIST_THUMBNAIL_FLAG_STD_NAME         = (1 << 1),
   PLAYLIST_THUMBNAIL_FLAG_SHORT_NAME       = (1 << 2),
   PLAYLIST_THUMBNAIL_FLAG_NONE             = (1 << 3)
};

typedef struct content_playlist playlist_t;

/* Holds all parameters required to uniquely
 * identify a playlist content path */
typedef struct
{
   char *real_path;
   char *archive_path;
   uint32_t real_path_hash;
   uint32_t archive_path_hash;
   bool is_archive;
   bool is_in_archive;
} playlist_path_id_t;

struct playlist_entry
{
   char *path;
   char *label;
   char *core_path;
   char *core_name;
   char *db_name;
   char *crc32;
   char *subsystem_ident;
   char *subsystem_name;
   char *runtime_str;
   char *last_played_str;
   struct string_list *subsystem_roms;
   playlist_path_id_t *path_id;
   unsigned entry_slot;
   unsigned runtime_hours;
   unsigned runtime_minutes;
   unsigned runtime_seconds;
   /* Note: due to platform dependence, have to record
    * timestamp as either a string or independent integer
    * values. The latter is more verbose, but more efficient. */
   unsigned last_played_year;
   unsigned last_played_month;
   unsigned last_played_day;
   unsigned last_played_hour;
   unsigned last_played_minute;
   unsigned last_played_second;
   enum playlist_runtime_status runtime_status;
   enum playlist_thumbnail_name_flags thumbnail_flags;
};

/* Holds all configuration parameters required
 * when initialising/saving playlists */
typedef struct
{
   size_t capacity;
   bool old_format;
   bool compress;
   bool fuzzy_archive_match;
   bool autofix_paths;
   char path[PATH_MAX_LENGTH];
   char base_content_directory[DIR_MAX_LENGTH];
} playlist_config_t;

size_t playlist_config_set_path(playlist_config_t *config, const char *path);

size_t playlist_config_set_base_content_directory(playlist_config_t* config, const char* path);

playlist_t *playlist_init(const playlist_config_t *config);

void playlist_free(playlist_t *playlist);

void playlist_get_index(playlist_t *playlist, size_t idx, const struct playlist_entry **entry);

bool playlist_push(playlist_t *playlist, const struct playlist_entry *entry);

bool playlist_entry_exists(playlist_t *playlist, const char *path);

uint32_t playlist_get_size(playlist_t *playlist);

void playlist_write_file(playlist_t *playlist);

void command_playlist_push_write(playlist_t *playlist, const struct playlist_entry *entry);

RETRO_END_DECLS

#endif
