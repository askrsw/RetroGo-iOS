/*  RetroArch - A frontend for libretro.
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

/* Assume W-functions do not work below Win2K and Xbox platforms */
#if defined(_WIN32_WINNT) && _WIN32_WINNT < 0x0500 || defined(_XBOX)

#ifndef LEGACY_WIN32
#define LEGACY_WIN32
#endif

#endif

#ifdef _WIN32
#include <direct.h>
#else
#include <unistd.h>
#endif

#ifdef OSX
#include <CoreFoundation/CoreFoundation.h>
#endif

#ifdef __QNX__
#include <libgen.h>
#endif

#ifdef __HAIKU__
#include <kernel/image.h>
#endif

#if defined(DINGUX)
#include "dingux/dingux_utils.h"
#endif

#include <stdlib.h>
#include <boolean.h>
#include <string.h>
#include <time.h>

#include <file/file_path.h>
#include <string/stdstring.h>

#include <compat/strl.h>

#include <utils/defaults.h>
#include <compat/posix_string.h>
#include <retro_assert.h>
#include <retro_miscellaneous.h>
#include <encodings/utf.h>

#include <utils/configuration.h>
#include <utils/file_path_special.h>

#include <utils/retro_paths.h>
#include <utils/verbosity.h>
#include <intl/msg_hash.h>

bool fill_pathname_application_data(char *s, size_t len)
{
#if defined(_WIN32) && !defined(_XBOX) && !defined(__WINRT__)
#ifdef LEGACY_WIN32
   const char *appdata = getenv("APPDATA");

   if (appdata)
   {
      strlcpy(s, appdata, len);
      return true;
   }
#else
   const wchar_t *appdataW = _wgetenv(L"APPDATA");

   if (appdataW)
   {
      char *appdata = utf16_to_utf8_string_alloc(appdataW);

      if (appdata)
      {
         strlcpy(s, appdata, len);
         free(appdata);
         return true;
      }
   }
#endif

#elif defined(OSX)
   CFBundleRef bundle = CFBundleGetMainBundle();
   if (!bundle)
      return false;

   /* get the directory containing the app */
   CFStringRef parent_path;
   CFURLRef bundle_url, parent_url;
   bundle_url  = CFBundleCopyBundleURL(bundle);
   parent_url  = CFURLCreateCopyDeletingLastPathComponent(NULL, bundle_url);
   parent_path = CFURLCopyFileSystemPath(parent_url, kCFURLPOSIXPathStyle);
   CFStringGetCString(parent_path, s, len, kCFStringEncodingUTF8);
   CFRelease(parent_path);
   CFRelease(parent_url);
   CFRelease(bundle_url);

#if HAVE_STEAM
   return true;
#else
   /* if portable.txt exists next to the app then we use that directory */
   char portable_buf[PATH_MAX_LENGTH] = {0};
   fill_pathname_join(portable_buf, s, "portable.txt", sizeof(portable_buf));
   if (path_is_valid(portable_buf))
      return true;

   /* if the app itself says it's portable we obey that as well */
   CFStringRef key = CFStringCreateWithCString(NULL, "RAPortableInstall", kCFStringEncodingUTF8);
   if (key)
   {
      CFBooleanRef val = CFBundleGetValueForInfoDictionaryKey(bundle, key);
      CFRelease(key);
      if (val)
      {
         bool portable = CFBooleanGetValue(val);
         CFRelease(val);
         if (portable)
            return true;
      }
   }

   /* otherwise we use ~/Library/Application Support/RetroArch */
   const char *appdata = getenv("HOME");
   if (appdata)
   {
      fill_pathname_join(s, appdata,
            "Library/Application Support/RetroArch", len);
      return true;
   }
#endif
#elif defined(RARCH_UNIX_CWD_ENV)
   getcwd(s, len);
   return true;
#elif defined(DINGUX)
   dingux_get_base_path(s, len);
   return true;
#elif !defined(RARCH_CONSOLE)
   const char *xdg     = getenv("XDG_CONFIG_HOME");
   const char *appdata = getenv("HOME");

   /* XDG_CONFIG_HOME falls back to $HOME/.config with most Unix systems */
   /* On Haiku, it is set by default to /home/user/config/settings */
   if (xdg)
   {
      fill_pathname_join(s, xdg, "Data/", len);
      return true;
   }

   if (appdata)
   {
#ifdef __HAIKU__
      /* in theory never used as Haiku has XDG_CONFIG_HOME set by default */
      fill_pathname_join(s, appdata,
            "config/settings/Data/", len);
#else
      fill_pathname_join(s, appdata,
            ".config/Data/", len);
#endif
      return true;
   }
#endif

   return false;
}

size_t fill_pathname_application_special(char *s,
      size_t len, enum application_special_type type)
{
   size_t _len = 0;
   switch (type)
   {
      case APPLICATION_SPECIAL_DIRECTORY_CONFIG:
         {
            settings_t *settings        = config_get_ptr();
            const char *dir_menu_config = settings->paths.directory_main_config;

            /* Try config directory setting first,
             * fallback to the location of the current configuration file. */
            if (!string_is_empty(dir_menu_config))
               _len = strlcpy(s, dir_menu_config, len);
            else if (!path_is_empty(RARCH_PATH_CONFIG))
               _len = fill_pathname_basedir(s, path_get(RARCH_PATH_CONFIG), len);
         }
         break;
      case APPLICATION_SPECIAL_DIRECTORY_ASSETS_XMB_ICONS:
         break;
      case APPLICATION_SPECIAL_DIRECTORY_ASSETS_XMB_BG:
         break;
      case APPLICATION_SPECIAL_DIRECTORY_ASSETS_SOUNDS:
         break;
      case APPLICATION_SPECIAL_DIRECTORY_ASSETS_SYSICONS:
         break;
      case APPLICATION_SPECIAL_DIRECTORY_ASSETS_OZONE_ICONS:
         break;
      case APPLICATION_SPECIAL_DIRECTORY_ASSETS_RGUI_FONT:
         break;
      case APPLICATION_SPECIAL_DIRECTORY_ASSETS_XMB:
         break;
      case APPLICATION_SPECIAL_DIRECTORY_ASSETS_XMB_FONT:
         break;
      case APPLICATION_SPECIAL_DIRECTORY_THUMBNAILS_DISCORD_AVATARS:
      {
        char tmp_dir[DIR_MAX_LENGTH];
        settings_t *settings       = config_get_ptr();
        const char *dir_thumbnails = settings->paths.directory_thumbnails;
        fill_pathname_join_special(tmp_dir, dir_thumbnails, "discord", sizeof(tmp_dir));
        _len = fill_pathname_join_special(s, tmp_dir, "avatars", len);
      }
      break;

      case APPLICATION_SPECIAL_DIRECTORY_THUMBNAILS_CHEEVOS_BADGES:
      {
        char tmp_dir[DIR_MAX_LENGTH];
        settings_t *settings       = config_get_ptr();
        const char *dir_thumbnails = settings->paths.directory_thumbnails;
        fill_pathname_join_special(tmp_dir, dir_thumbnails, "cheevos", sizeof(tmp_dir));
        _len = fill_pathname_join_special(s, tmp_dir, "badges", len);
      }
      break;

      case APPLICATION_SPECIAL_NONE:
      default:
         break;
   }
   return _len;
}

static const char *strip_private_prefix(const char *path)
{
   const char *prefix = "/private";
   size_t prefix_len = strlen(prefix);

   if (path && string_starts_with(path, prefix))
   {
      const char *next = path + prefix_len;
      if (*next == '/')
         return next;
   }

   return path;
}

const char *shorten_path_for_log(const char *path, char *buffer, size_t buffer_size)
{
   const char *home_path = g_defaults.dirs[DEFAULT_DIR_USER_DOCUMENT];
   const char *bundle_root = g_defaults.dirs[DEFAULT_DIR_BUNDLE_ROOT];
   const char *path_norm = strip_private_prefix(path);
   const char *home_norm = strip_private_prefix(home_path);
   const char *bundle_norm = strip_private_prefix(bundle_root);
   bool has_home_path = strlen(home_path) > 0;
   bool has_bundle_root = strlen(bundle_root) > 0;

   if (string_is_empty(path) || !buffer || buffer_size == 0)
      return path;

   if (has_bundle_root && string_starts_with(path_norm, bundle_norm))
   {
      size_t bundle_len = strlen(bundle_norm);
      const char *suffix = path_norm + bundle_len;

      if (*suffix == '\0')
         strlcpy(buffer, "@", buffer_size);
      else
         snprintf(buffer, buffer_size, "@%s", suffix);

      return buffer;
   }

   if (has_home_path && string_starts_with(path_norm, home_norm))
   {
      size_t home_len = strlen(home_norm);
      const char *suffix = path_norm + home_len;

      if (*suffix == '\0')
         strlcpy(buffer, "~", buffer_size);
      else
         snprintf(buffer, buffer_size, "~%s", suffix);

      return buffer;
   }

   return path;
}
