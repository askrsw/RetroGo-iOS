/*  RetroArch - A frontend for libretro.
 *  Copyright (C) 2010-2014 - Hans-Kristian Arntzen
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

#include "menu_shader.h"

/**
 * menu_shader_manager_get_type:
 * @shader                   : shader handle
 *
 * Gets type of shader.
 *
 * Returns: type of shader.
 **/
enum rarch_shader_type menu_shader_manager_get_type(
      const struct video_shader *shader)
{
   enum rarch_shader_type type = RARCH_SHADER_NONE;
   /* All shader types must be the same, or we cannot use it. */

   if (shader)
   {
      type = video_shader_parse_type(shader->path);

      if (shader->passes)
      {
         size_t i                 = 0;
         if (type == RARCH_SHADER_NONE)
         {
            type = video_shader_parse_type(shader->pass[0].source.path);
            i    = 1;
         }

         for (; i < shader->passes; i++)
         {
            enum rarch_shader_type pass_type =
               video_shader_parse_type(shader->pass[i].source.path);

            switch (pass_type)
            {
               case RARCH_SHADER_CG:
               case RARCH_SHADER_GLSL:
               case RARCH_SHADER_SLANG:
                  if (type != pass_type)
                     return RARCH_SHADER_NONE;
                  break;
               default:
                  break;
            }
         }
      }
   }

   return type;
}

static bool menu_shader_manager_save_preset_internal(
      bool save_reference,
      const struct video_shader *shader,
      const char *basename,
      const char *dir_video_shader,
      bool apply,
      const char **target_dirs,
      size_t num_target_dirs)
{
   size_t _len;
   char fullname[NAME_MAX_LENGTH];
   bool ret                       = false;
   enum rarch_shader_type type    = RARCH_SHADER_NONE;
   char *preset_path              = NULL;
   size_t i                       = 0;
   if (!shader || !shader->passes)
      return false;
   if ((type = menu_shader_manager_get_type(shader)) == RARCH_SHADER_NONE)
      return false;

   if (!string_is_empty(basename))
      _len = strlcpy(fullname, basename, sizeof(fullname));
   else
      _len = strlcpy(fullname, "retroarch", sizeof(fullname));
   strlcpy(fullname + _len,
         video_shader_get_preset_extension(type),
         sizeof(fullname) - _len);

   if (path_is_absolute(fullname))
   {
      preset_path = fullname;
      if ((ret    = video_shader_write_preset(preset_path, shader, save_reference)))
         RARCH_LOG("[Shaders] Saved shader preset to \"%s\".\n", preset_path);
      else
         RARCH_ERR("[Shaders] Failed writing shader preset to \"%s\".\n", preset_path);
   }
   else
   {
      char basedir[DIR_MAX_LENGTH];
      char buffer[DIR_MAX_LENGTH];

      for (i = 0; i < num_target_dirs; i++)
      {
         if (string_is_empty(target_dirs[i]))
            continue;

         fill_pathname_join(buffer, target_dirs[i],
               fullname, sizeof(buffer));

         fill_pathname_basedir(basedir, buffer, sizeof(basedir));

         if (!path_is_directory(basedir) && !(ret = path_mkdir(basedir)))
         {
            RARCH_WARN("[Shaders] Failed to create preset directory \"%s\".\n", basedir);
            continue;
         }

         preset_path = buffer;

         if ((ret = video_shader_write_preset(preset_path,
               shader, save_reference)))
         {
            RARCH_LOG("[Shaders] Saved shader preset to \"%s\".\n", preset_path);
            break;
         }
         else
            RARCH_WARN("[Shaders] Failed writing shader preset to \"%s\".\n", preset_path);
      }

      if (!ret)
         RARCH_ERR("[Shaders] Failed to write shader preset. Make sure shader directory "
               "and/or config directory are writable.\n");
   }

   if (ret && apply)
      menu_shader_manager_set_preset(NULL, type, preset_path, true);

   return ret;
}

static bool menu_shader_manager_operate_auto_preset(
      enum auto_shader_operation op,
      const struct video_shader *shader,
      const char *dir_video_shader,
      const char *dir_menu_config,
      enum auto_shader_type type, bool apply)
{
   char file[PATH_MAX_LENGTH];
   char old_presets_directory[DIR_MAX_LENGTH];
   settings_t *settings                           = config_get_ptr();
   bool video_shader_preset_save_reference_enable = settings->
      bools.video_shader_preset_save_reference_enable;
   struct retro_system_info *sysinfo              = &runloop_state_get_ptr()->system.info;
   static enum rarch_shader_type shader_types[]   =
   {
      RARCH_SHADER_GLSL, RARCH_SHADER_SLANG, RARCH_SHADER_CG
   };
   static enum display_flags shader_types_flags[] =
   {
      GFX_CTX_FLAGS_SHADERS_GLSL, GFX_CTX_FLAGS_SHADERS_SLANG, GFX_CTX_FLAGS_SHADERS_CG
   };
   const char *core_name              = sysinfo ? sysinfo->library_name : NULL;
   const char *rarch_path_basename    = path_get(RARCH_PATH_BASENAME);
   const char *auto_preset_dirs[3]    = {0};
   bool has_content                   = !string_is_empty(rarch_path_basename);

   if (type != SHADER_PRESET_GLOBAL && string_is_empty(core_name))
      return false;

   if (    !has_content
       && ((type == SHADER_PRESET_GAME)
       ||  (type == SHADER_PRESET_PARENT)))
      return false;

   /* We are only including this directory for compatibility purposes with
    * versions 1.8.7 and older. */
   if (op != AUTO_SHADER_OP_SAVE && !string_is_empty(dir_video_shader))
      fill_pathname_join_special(
            old_presets_directory,
            dir_video_shader,
            "presets",
            sizeof(old_presets_directory));
   else
      old_presets_directory[0] = '\0';

   auto_preset_dirs[0] = settings->paths.directory_user_video_shader;
   auto_preset_dirs[1] = dir_menu_config;
   auto_preset_dirs[2] = old_presets_directory;

   switch (type)
   {
      case SHADER_PRESET_GLOBAL:
         strlcpy(file, "global", sizeof(file));
         break;
      case SHADER_PRESET_CORE:
         fill_pathname_join_special(file, core_name, core_name, sizeof(file));
         break;
      case SHADER_PRESET_PARENT:
         {
            char tmp_dir[DIR_MAX_LENGTH];
            fill_pathname_parent_dir_name(tmp_dir,
                  rarch_path_basename, sizeof(tmp_dir));
            fill_pathname_join_special(file, core_name, tmp_dir, sizeof(file));
         }
         break;
      case SHADER_PRESET_GAME:
         {
            const char *game_name = path_basename(rarch_path_basename);
            if (string_is_empty(game_name))
               return false;
            fill_pathname_join_special(file, core_name, game_name, sizeof(file));
            break;
         }
      default:
         return false;
   }

   switch (op)
   {
      case AUTO_SHADER_OP_SAVE:
         return menu_shader_manager_save_preset_internal(
               video_shader_preset_save_reference_enable,
               shader, file,
               dir_video_shader,
               apply,
               auto_preset_dirs,
               ARRAY_SIZE(auto_preset_dirs));
      case AUTO_SHADER_OP_REMOVE:
         {
            /* remove all supported auto-shaders of given type */
            char *end;
            size_t i, j, m;
            char preset_path[PATH_MAX_LENGTH];
            gfx_ctx_flags_t flags;
            /* n = amount of relevant shader presets found
             * m = amount of successfully deleted shader presets */
            size_t n = m    = 0;

            flags.flags     = 0;
            video_context_driver_get_flags(&flags);

            for (i = 0; i < ARRAY_SIZE(auto_preset_dirs); i++)
            {
               size_t _len2;
               if (string_is_empty(auto_preset_dirs[i]))
                  continue;

               _len2 = fill_pathname_join(preset_path,
                     auto_preset_dirs[i], file, sizeof(preset_path));
               end = preset_path + _len2;

               for (j = 0; j < ARRAY_SIZE(shader_types); j++)
               {
                  if (!(BIT32_GET(flags.flags, shader_types_flags[j])))
                     continue;

                  strlcpy(end, video_shader_get_preset_extension(shader_types[j]),
                        sizeof(preset_path) - (end - preset_path));

                  if (path_is_valid(preset_path))
                  {
                     n++;

                     if (!filestream_delete(preset_path))
                     {
                        m++;
                        RARCH_LOG("[Shaders] Deleted shader preset from \"%s\".\n", preset_path);
                     }
                     else
                        RARCH_WARN("[Shaders] Failed to remove shader preset at \"%s\".\n", preset_path);
                  }
               }
            }

            return n == m;
         }
      case AUTO_SHADER_OP_EXISTS:
         {
            /* test if any supported auto-shaders of given type exists */
            char *end;
            size_t i, j;
            gfx_ctx_flags_t flags;
            char preset_path[PATH_MAX_LENGTH];

            flags.flags     = 0;
            video_context_driver_get_flags(&flags);


            for (i = 0; i < ARRAY_SIZE(auto_preset_dirs); i++)
            {
               size_t _len2;
               if (string_is_empty(auto_preset_dirs[i]))
                  continue;

               _len2 = fill_pathname_join(preset_path,
                     auto_preset_dirs[i], file, sizeof(preset_path));
               end = preset_path + _len2;

               for (j = 0; j < ARRAY_SIZE(shader_types); j++)
               {
                  if (!(BIT32_GET(flags.flags, shader_types_flags[j])))
                     continue;

                  strlcpy(end, video_shader_get_preset_extension(shader_types[j]),
                        sizeof(preset_path) - (end - preset_path));

                  if (path_is_valid(preset_path))
                     return true;
               }
            }
         }
         break;
   }

   return false;
}

struct video_shader *menu_shader_get(void)
{
   gfx_ctx_flags_t flags;
   flags.flags     = 0;
   video_context_driver_get_flags(&flags);

  if (
         BIT32_GET(flags.flags, GFX_CTX_FLAGS_SHADERS_SLANG)
      || BIT32_GET(flags.flags, GFX_CTX_FLAGS_SHADERS_GLSL)
      || BIT32_GET(flags.flags, GFX_CTX_FLAGS_SHADERS_CG)
      || BIT32_GET(flags.flags, GFX_CTX_FLAGS_SHADERS_HLSL))
   {
      video_driver_state_t *video_st = video_state_get_ptr();
      if (video_st)
         return video_st->menu_driver_shader;
   }
   return NULL;
}

/**
 * menu_shader_manager_init:
 *
 * Initializes shader manager.
 **/
bool menu_shader_manager_init(void)
{
   gfx_ctx_flags_t flags;
   video_driver_state_t *video_st   = video_state_get_ptr();
   enum rarch_shader_type type      = RARCH_SHADER_NONE;
   bool ret                         = true;
   bool is_preset                   = false;
   const char *path_shader          = NULL;
   struct video_shader *menu_shader = NULL;
   /* We get the shader preset directly from the video driver, so that
    * we are in sync with it (it could fail loading an auto-shader)
    * If we can't (e.g. get_current_shader is not implemented),
    * we'll load video_shader_get_current_shader_preset() like always */
   video_shader_ctx_t shader_info   = {0};

   video_shader_driver_get_current_shader(&shader_info);

   if (shader_info.data)
      /* Use the path of the originally loaded preset because it could
       * have been a preset with a #reference in it to another preset */
      path_shader                 = shader_info.data->loaded_preset_path;
   else
      path_shader                 = video_shader_get_current_shader_preset();

   menu_shader_manager_free();

   if (!(menu_shader = (struct video_shader*)calloc(1, sizeof(*menu_shader))))
   {
      ret = false;
      goto end;
   }

   if (string_is_empty(path_shader))
      goto end;

   type            = video_shader_get_type_from_ext(
         path_get_extension(path_shader), &is_preset);
   flags.flags     = 0;
   video_context_driver_get_flags(&flags);

   if (!BIT32_GET(flags.flags, video_shader_type_to_flag(type)))
   {
      ret = false;
      goto end;
   }

   if (is_preset)
   {
      if (!video_shader_load_preset_into_shader(path_shader, menu_shader))
      {
         ret = false;
         goto end;
      }
      menu_shader->flags   &= ~SHDR_FLAG_MODIFIED;
   }
   else
   {
      strlcpy(menu_shader->pass[0].source.path, path_shader,
            sizeof(menu_shader->pass[0].source.path));
      menu_shader->passes = 1;
   }

end:
   video_st->menu_driver_shader = menu_shader;
   command_event(CMD_EVENT_SHADER_PRESET_LOADED, NULL);
   return ret;
}

void menu_shader_manager_free(void)
{
   video_driver_state_t *video_st = video_state_get_ptr();
   if (video_st->menu_driver_shader)
      free(video_st->menu_driver_shader);
   video_st->menu_driver_shader = NULL;
}

/**
 * menu_shader_manager_set_preset:
 * @menu_shader              : Shader handle to the menu shader.
 * @type                     : Type of shader.
 * @preset_path              : Preset path to load from.
 * @apply                    : Whether to apply the shader or just update shader information
 *
 * Sets shader preset.
 **/
bool menu_shader_manager_set_preset(struct video_shader *menu_shader,
      enum rarch_shader_type type, const char *preset_path, bool apply)
{
   bool ret                      = false;
   settings_t *settings          = config_get_ptr();

   if (apply && !video_shader_apply_shader(settings, type, preset_path, true))
      goto clear;

   if (string_is_empty(preset_path))
   {
      ret = true;
      goto clear;
   }

   /* Load stored Preset into menu on success.
    * Used when a preset is directly loaded.
    * No point in updating when the Preset was
    * created from the menu itself. */
   if (     !menu_shader
         || !(video_shader_load_preset_into_shader(preset_path, menu_shader)))
      goto end;

   ret = true;

end:
   command_event(CMD_EVENT_SHADER_PRESET_LOADED, NULL);
   return ret;

clear:
   /* We don't want to disable shaders entirely here,
    * just reset number of passes
    * > Note: Disabling shaders at this point would in
    *   fact be dangerous, since it changes the number of
    *   entries in the shader options menu which can in
    *   turn lead to the menu selection pointer going out
    *   of bounds. This causes undefined behaviour/segfaults */
   menu_shader_manager_clear_num_passes(menu_shader);
   command_event(CMD_EVENT_SHADER_PRESET_LOADED, NULL);
   return ret;
}

/**
 * menu_shader_manager_append_preset:
 * @shader                   : current shader
 * @preset_path              : path to the preset to append
 * @dir_video_shader         : temporary directory
 *
 * combine current shader with a shader preset on disk
 **/
bool menu_shader_manager_append_preset(struct video_shader *shader,
      const char* preset_path, const bool prepend)
{
   bool ret                      = false;
   const char *dir_video_shader  = config_get_ptr()->paths.directory_video_shader;
   enum rarch_shader_type type   = menu_shader_manager_get_type(shader);

   if (string_is_empty(preset_path))
   {
      ret = true;
      goto clear;
   }

   if (!video_shader_combine_preset_and_apply(
            type, shader, preset_path, dir_video_shader, prepend, true))
      goto clear;

   ret = true;

   command_event(CMD_EVENT_SHADER_PRESET_LOADED, NULL);
   return ret;

clear:
   /* We don't want to disable shaders entirely here,
    * just reset number of passes
    * > Note: Disabling shaders at this point would in
    *   fact be dangerous, since it changes the number of
    *   entries in the shader options menu which can in
    *   turn lead to the menu selection pointer going out
    *   of bounds. This causes undefined behaviour/segfaults */
   menu_shader_manager_clear_num_passes(shader);
   command_event(CMD_EVENT_SHADER_PRESET_LOADED, NULL);
   return ret;
}

/**
 * menu_shader_manager_save_auto_preset:
 * @shader                   : shader to save
 * @type                     : type of shader preset which determines save path
 * @apply                    : immediately set preset after saving
 *
 * Save a shader as an auto-shader to it's appropriate path:
 *    SHADER_PRESET_GLOBAL: <target dir>/global
 *    SHADER_PRESET_CORE:   <target dir>/<core name>/<core name>
 *    SHADER_PRESET_PARENT: <target dir>/<core name>/<parent>
 *    SHADER_PRESET_GAME:   <target dir>/<core name>/<game name>
 * Needs to be consistent with video_shader_load_auto_shader_preset()
 * Auto-shaders will be saved as a reference if possible
 **/
bool menu_shader_manager_save_auto_preset(
      const struct video_shader *shader,
      enum auto_shader_type type,
      const char *dir_video_shader,
      const char *dir_menu_config,
      bool apply)
{
   return menu_shader_manager_operate_auto_preset(
         AUTO_SHADER_OP_SAVE, shader,
         dir_video_shader,
         dir_menu_config,
         type, apply);
}

/**
 * menu_shader_manager_save_preset:
 * @shader                   : shader to save
 * @type                     : type of shader preset which determines save path
 * @basename                 : basename of preset
 * @apply                    : immediately set preset after saving
 *
 * Save a shader preset to disk.
 **/
bool menu_shader_manager_save_preset(const struct video_shader *shader,
      const char *basename,
      const char *dir_video_shader,
      const char *dir_menu_config,
      bool apply)
{
   const char *preset_dirs[3]  = {0};
   settings_t *settings        = config_get_ptr();
   bool preset_save_ref_enable = settings->
      bools.video_shader_preset_save_reference_enable;

   preset_dirs[0] = settings->paths.directory_user_video_shader;
   preset_dirs[1] = dir_menu_config;
   preset_dirs[2] = dir_video_shader;

   return menu_shader_manager_save_preset_internal(
         preset_save_ref_enable,
         shader, basename,
         dir_video_shader,
         apply,
         preset_dirs,
         ARRAY_SIZE(preset_dirs));
}

/**
 * menu_shader_manager_apply_changes:
 *
 * Apply shader state changes.
 **/
void menu_shader_manager_apply_changes(
      struct video_shader *shader,
      const char *dir_video_shader,
      const char *dir_menu_config)
{
   enum rarch_shader_type type = RARCH_SHADER_NONE;
   settings_t *settings        = config_get_ptr();

   if (!shader)
      return;

   type = menu_shader_manager_get_type(shader);

   /* Allow cold start from hotkey */
   if (     type == RARCH_SHADER_NONE
         && settings->bools.video_shader_enable
         && !(shader->flags & SHDR_FLAG_DISABLED))
   {
      const char *preset          = video_shader_get_current_shader_preset();
      enum rarch_shader_type type = video_shader_parse_type(preset);
      video_shader_apply_shader(settings, type, preset, false);
      return;
   }

   /* Temporary state does not save anything */
   if (shader->flags & SHDR_FLAG_TEMPORARY)
      return;

   if (     shader->passes
         && type != RARCH_SHADER_NONE
         && !(shader->flags & SHDR_FLAG_DISABLED))
   {
      menu_shader_manager_save_preset(shader, NULL,
            dir_video_shader, dir_menu_config, true);
      return;
   }

   menu_shader_manager_set_preset(NULL, type, NULL, true);

   /* Reinforce disabled state on failure */
   configuration_set_bool(settings, settings->bools.video_shader_enable, false);
}

int menu_shader_manager_clear_num_passes(struct video_shader *shader)
{
   if (shader)
   {
      shader->passes              = 0;
      video_shader_resolve_parameters(shader);
      shader->flags              |= SHDR_FLAG_MODIFIED;
   }

   return 0;
}

int menu_shader_manager_clear_parameter(struct video_shader *shader,
      unsigned i)
{
   struct video_shader_parameter *param = shader ?
      &shader->parameters[i] : NULL;

   if (param)
   {
      param->current = param->initial;
      param->current = MIN(MAX(param->minimum,
               param->current), param->maximum);

      shader->flags |= SHDR_FLAG_MODIFIED;
   }

   return 0;
}

int menu_shader_manager_clear_pass_filter(struct video_shader *shader,
      unsigned i)
{
   struct video_shader_pass *shader_pass = shader ?
      &shader->pass[i] : NULL;

   if (!shader_pass)
      return -1;

   shader_pass->filter = RARCH_FILTER_UNSPEC;
   shader->flags      |= SHDR_FLAG_MODIFIED;

   return 0;
}

void menu_shader_manager_clear_pass_scale(struct video_shader *shader,
      unsigned i)
{
   struct video_shader_pass *shader_pass = shader ?
      &shader->pass[i] : NULL;

   if (!shader_pass)
      return;

   shader_pass->fbo.scale_x = 0;
   shader_pass->fbo.scale_y = 0;
   shader_pass->fbo.flags  &= ~FBO_SCALE_FLAG_VALID;

   shader->flags           |=  SHDR_FLAG_MODIFIED;
}

void menu_shader_manager_clear_pass_path(struct video_shader *shader,
      unsigned i)
{
   struct video_shader_pass
      *shader_pass              = shader
      ? &shader->pass[i]
      : NULL;

   if (shader_pass)
      *shader_pass->source.path = '\0';

   if (shader)
      shader->flags            |= SHDR_FLAG_MODIFIED;
}

/**
 * menu_shader_manager_remove_auto_preset:
 * @type                     : type of shader preset to delete
 *
 * Deletes an auto-shader.
 **/
bool menu_shader_manager_remove_auto_preset(
      enum auto_shader_type type,
      const char *dir_video_shader,
      const char *dir_menu_config)
{
   return menu_shader_manager_operate_auto_preset(
         AUTO_SHADER_OP_REMOVE, NULL,
         dir_video_shader,
         dir_menu_config,
         type, false);
}

/**
 * menu_shader_manager_auto_preset_exists:
 * @type                     : type of shader preset
 *
 * Tests if an auto-shader of the given type exists.
 **/
bool menu_shader_manager_auto_preset_exists(
      enum auto_shader_type type,
      const char *dir_video_shader,
      const char *dir_menu_config)
{
   return menu_shader_manager_operate_auto_preset(
         AUTO_SHADER_OP_EXISTS, NULL,
         dir_video_shader,
         dir_menu_config,
         type, false);
}

int generic_action_ok_shader_preset_save(enum auto_shader_type preset_type) {
    
   settings_t      *settings     = config_get_ptr();
   const char *dir_video_shader  = settings->paths.directory_video_shader;
   const char *dir_menu_config   = settings->paths.directory_menu_config;

   /* Save Auto Preset and have it immediately reapply the preset
    * TODO: This seems necessary so that the loaded shader gains a link to the file saved
    * But this is slow and seems like a redundant way to do this
    * It seems like it would be better to just set the path and shader_preset_loaded
    * on the current shader */
   if (menu_shader_manager_save_auto_preset(menu_shader_get(), preset_type,
            dir_video_shader, dir_menu_config,
            true))
   {
      const char *_msg = msg_hash_to_str(MSG_SHADER_PRESET_SAVED_SUCCESSFULLY);
      runloop_msg_queue_push(_msg, strlen(_msg), 1, 100, true, NULL,
            MESSAGE_QUEUE_ICON_DEFAULT, MESSAGE_QUEUE_CATEGORY_INFO);
   }
   else
   {
      const char *_msg = msg_hash_to_str(MSG_ERROR_SAVING_SHADER_PRESET);
      runloop_msg_queue_push(_msg, strlen(_msg), 1, 100, true, NULL,
            MESSAGE_QUEUE_ICON_DEFAULT, MESSAGE_QUEUE_CATEGORY_INFO);
   }

   return 0;
}

int generic_action_ok_shader_preset_remove(enum auto_shader_type preset_type) {
   settings_t         *settings = config_get_ptr();
   const char *dir_video_shader = settings->paths.directory_video_shader;
   const char *dir_menu_config  = settings->paths.directory_menu_config;
   if (menu_shader_manager_remove_auto_preset(preset_type,
         dir_video_shader, dir_menu_config))
   {
      const char *_msg = msg_hash_to_str(MSG_SHADER_PRESET_REMOVED_SUCCESSFULLY);
      runloop_msg_queue_push(_msg, strlen(_msg), 1, 100, true, NULL,
            MESSAGE_QUEUE_ICON_DEFAULT, MESSAGE_QUEUE_CATEGORY_INFO);
   }
   else
   {
      const char *_msg = msg_hash_to_str(MSG_ERROR_REMOVING_SHADER_PRESET);
      runloop_msg_queue_push(_msg, strlen(_msg), 1, 100, true, NULL,
            MESSAGE_QUEUE_ICON_DEFAULT, MESSAGE_QUEUE_CATEGORY_INFO);
   }

   return 0;
}
