/*  RetroArch - A frontend for libretro.
 *  Copyright (C) 2010-2017 - Hans-Kristian Arntzen
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

#include <stdio.h>
#include <string.h>
#include <string>
#include <algorithm>

#include <retro_miscellaneous.h>
#include <file/file_path.h>
#include <file/config_file.h>
#include <streams/file_stream.h>
#include <string/stdstring.h>

#include "glslang_util.h"
#include "glslang_util_cxx.h"
#include "retrogo_slang_cache.hpp"
#include <utils/retrogo_log.h>
#if defined(HAVE_GLSLANG)
#include "glslang.hpp"
#endif
#include <utils/verbosity.h>

static std::string build_stage_source(
      const struct string_list *lines, const char *stage)
{
   size_t i;
   std::string str;
   bool active = true;
   if (!lines || lines->size < 1)
      return "";
   str.reserve(lines->size);

   /* Version header. */
   str.append(lines->elems[0].data);
   str.append("\n");

   for (i = 1; i < lines->size; i++)
   {
      const char *line = lines->elems[i].data;

      if (string_starts_with_size(line, "#pragma", STRLEN_CONST("#pragma")))
      {
         /* Identify 'stage' (fragment/vertex) */
         if (!strncmp("#pragma stage ", line, STRLEN_CONST("#pragma stage ")))
         {
            if (!string_is_empty(stage))
            {
               char expected[128];
               size_t _len = strlcpy(expected, "#pragma stage ", sizeof(expected));
               strlcpy(expected + _len, stage, sizeof(expected) - _len);
               active = string_is_equal(expected, line);
            }
         }
         else if (
                  !strncmp("#pragma name ", line,
                  STRLEN_CONST("#pragma name "))
               || !strncmp("#pragma format ", line,
                  STRLEN_CONST("#pragma format ")))
         {
            /* Ignore */
         }
         else if (active)
            str.append(line);
      }
      else if (active)
         str.append(line);

      str.append("\n");
   }

   return str;
}

bool glslang_parse_meta(const struct string_list *lines, glslang_meta *meta)
{
   char id[64];
   char desc[64];
   size_t i;

   id[0]   = '\0';
   desc[0] = '\0';

   for (i = 0; i < lines->size; i++)
   {
      const char *line = lines->elems[i].data;

      if (string_starts_with_size(line, "#pragma", STRLEN_CONST("#pragma")))
      {
         /* Check for shader identifier */
         if (!strncmp("#pragma name ", line,
                  STRLEN_CONST("#pragma name ")))
         {
            const char *str = NULL;

            if (!meta->name.empty())
            {
               RARCH_ERR("[Slang] Trying to declare multiple names for file.\n");
               return false;
            }

            str = line + STRLEN_CONST("#pragma name ");
            while (*str == ' ')
               str++;

            meta->name = str;
         }
         /* Check for shader parameters */
         else if (!strncmp("#pragma parameter ", line,
                  STRLEN_CONST("#pragma parameter ")))
         {
            float initial, minimum, maximum, step;
            int ret = sscanf(
                  line, "#pragma parameter %63s \"%63[^\"]\" %f %f %f %f",
                  id, desc, &initial, &minimum, &maximum, &step);

            if (ret == 5)
            {
               step = 0.1f * (maximum - minimum);
               ret  = 6;
            }

            if (ret == 6)
            {
               bool parameter_found   = false;
               size_t parameter_index = 0;
               size_t j;

               for (j = 0; j < meta->parameters.size(); j++)
               {
                  /* Note: LHS is a std:string, RHS is a C string.
                   * (the glslang_meta stuff has to be C++) */
                  if (meta->parameters[j].id == id)
                  {
                     parameter_found = true;
                     parameter_index = j;
                     break;
                  }
               }

               /* Allow duplicate #pragma parameter, but only
                * if they are exactly the same. */
               if (parameter_found)
               {
                  const glslang_parameter *parameter =
                     &meta->parameters[parameter_index];

                  if (     (parameter->desc    != desc)
                        || (parameter->initial != initial)
                        || (parameter->minimum != minimum)
                        || (parameter->maximum != maximum)
                        || (parameter->step    != step)
                     )
                  {
                     RARCH_ERR("[Slang] Duplicate parameters found for \"%s\", but arguments do not match.\n", id);
                     return false;
                  }
               }
               else
                  meta->parameters.push_back({ id, desc, initial, minimum, maximum, step });
            }
            else
            {
               RARCH_ERR("[Slang] Invalid #pragma parameter line: \"%s\".\n",
                     line);
               return false;
            }
         }
         /* Check for framebuffer format */
         else if (!strncmp("#pragma format ", line,
                  STRLEN_CONST("#pragma format ")))
         {
            const char *str = NULL;

            if (meta->rt_format != SLANG_FORMAT_UNKNOWN)
            {
               RARCH_ERR("[Slang] Trying to declare format multiple times for file.\n");
               return false;
            }

            str = line + STRLEN_CONST("#pragma format ");
            while (*str == ' ')
               str++;

            meta->rt_format = glslang_find_format(str);

            if (meta->rt_format == SLANG_FORMAT_UNKNOWN)
            {
               RARCH_ERR("[Slang] Failed to find format \"%s\".\n", str);
               return false;
            }
         }
      }
   }

   return true;
}

bool glslang_compile_shader(const char *shader_path, glslang_output *output, bool require_cache,
      std::string *artifact, bool *compiled)
{
   if (compiled) *compiled = false;
   if (artifact) artifact->clear();
#if defined(HAVE_GLSLANG)
   struct string_list lines;
   std::string vertex, fragment, cache_path, source;

   if (!string_list_initialize(&lines))
      return false;

   if (!glslang_read_shader_file(shader_path, &lines, true, false))
      goto error;
   vertex = build_stage_source(&lines, "vertex");
   fragment = build_stage_source(&lines, "fragment");
   for (size_t i = 0; i < lines.size; i++) { source.append(lines.elems[i].data); source.append("\n"); }
   cache_path = retrogo_slang_cache::path(retrogo_slang_cache::identity(vertex, fragment, source));
   if (artifact) *artifact = cache_path;
   if (retrogo_slang_cache::load(cache_path, *output))
   {
      string_list_deinitialize(&lines);
      RETROGO_LOGD(GAME, "Shader SPIR-V cache hit for %s", shader_path);
      return true;
   }
   if (require_cache && cache_path.empty()) goto error;
   RARCH_LOG("[Slang] Compiling shader: \"%s\".\n", shader_path);
   if (compiled) *compiled = true;
   output->meta = glslang_meta{};
   if (!glslang_parse_meta(&lines, &output->meta))
      goto error;

   if (!glslang::compile_spirv(vertex,
            glslang::StageVertex, &output->vertex))
   {
      RARCH_ERR("[Slang] Failed to compile vertex shader stage.\n");
      goto error;
   }

   if (!glslang::compile_spirv(fragment,
            glslang::StageFragment, &output->fragment))
   {
      RARCH_ERR("[Slang] Failed to compile fragment shader stage.\n");
      goto error;
   }

   string_list_deinitialize(&lines);
   if (!retrogo_slang_cache::store(cache_path, *output))
   {
      RETROGO_LOGD(GAME, "Shader SPIR-V cache write unavailable for %s", shader_path);
      return !require_cache;
   }
   RETROGO_LOGD(GAME, "Shader SPIR-V cache stored for %s", shader_path);
   return true;

error:
   string_list_deinitialize(&lines);
#endif

   return false;
}

extern "C" void retrogo_shader_cache_set_directory(const char *path)
{
   std::lock_guard<std::mutex> lock(retrogo_slang_cache::directory_mutex);
   retrogo_slang_cache::directory = path ? path : "";
}

extern "C" bool retrogo_shader_cache_prepare_info(const char *path, char *artifact, size_t size, bool *compiled)
{
   glslang_output output;
   std::string file;
   if (!path || !artifact || !size || !glslang_compile_shader(path, &output, true, &file, compiled)) return false;
   return strlcpy(artifact, file.c_str(), size) < size;
}
