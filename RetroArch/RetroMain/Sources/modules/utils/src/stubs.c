//
//  stubs.c
//  RetroGo
//
//  Created by haharsw on 2026/2/27.
//  Copyright © 2026 haharsw. All rights reserved.
//
//  ---------------------------------------------------------------------------------
//  This file is part of RetroGo.
//  ---------------------------------------------------------------------------------
//
//  RetroGo is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  RetroGo is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

#include <utils/playlist.h>

typedef struct
{
   char *content_dir;
   char *file_exts;
   char *dat_file_path;
   bool search_recursively;
   bool search_archives;
   bool filter_dat_content;
   bool overwrite_playlist;
} playlist_manual_scan_record_t;

struct content_playlist
{
   char *default_core_path;
   char *default_core_name;
   char *base_content_directory;

   struct playlist_entry *entries;

   playlist_manual_scan_record_t scan_record; /* ptr alignment */
   playlist_config_t config;                  /* size_t alignment */

   enum playlist_label_display_mode label_display_mode;
   enum playlist_thumbnail_mode right_thumbnail_mode;
   enum playlist_thumbnail_mode left_thumbnail_mode;
   enum playlist_thumbnail_match_mode thumbnail_match_mode;
   enum playlist_sort_mode sort_mode;

   uint8_t flags;
};

void command_playlist_push_write(playlist_t *playlist, const struct playlist_entry *entry)
{ }

void playlist_write_file(playlist_t *playlist)
{ }

bool playlist_entry_exists(playlist_t *playlist, const char *path)
{
    return false;
}

uint32_t playlist_get_size(playlist_t *playlist)
{
    return 0;
}

bool playlist_push(playlist_t *playlist, const struct playlist_entry *entry)
{
    return true;
}

void playlist_get_index(playlist_t *playlist, size_t idx, const struct playlist_entry **entry)
{ }

playlist_t *playlist_init(const playlist_config_t *config)
{
    return NULL;
}

void playlist_free(playlist_t *playlist)
{ }

size_t playlist_config_set_base_content_directory(playlist_config_t* config, const char* path)
{ }

size_t playlist_config_set_path(playlist_config_t *config, const char *path)
{
    return 0;
}
