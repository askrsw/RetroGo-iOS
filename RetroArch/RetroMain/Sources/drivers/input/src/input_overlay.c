//
//  input_overlay.c
//  RetroArch
//
//  Created by haharsw on 2025/10/3.
//

#include <input/input_overlay.h>

void input_overlay_free_overlay(struct overlay *overlay)
{
   size_t i;

   if (!overlay)
      return;

   for (i = 0; i < overlay->size; i++)
   {
      image_texture_free(&overlay->descs[i].image);
      if (overlay->descs[i].eightway_config)
         free(overlay->descs[i].eightway_config);
      overlay->descs[i].eightway_config = NULL;
   }

   if (overlay->load_images)
      free(overlay->load_images);
   overlay->load_images = NULL;
   if (overlay->descs)
      free(overlay->descs);
   overlay->descs       = NULL;
   image_texture_free(&overlay->image);
}

void input_overlay_set_visibility(int overlay_idx,
      enum overlay_visibility vis)
{
   input_driver_state_t *input_st = input_state_get_ptr();
   input_overlay_t      *ol       = input_st->overlay_ptr;

   if (!input_st->overlay_visibility)
   {
      unsigned i;
      input_st->overlay_visibility = (enum overlay_visibility *)calloc(
            MAX_VISIBILITY, sizeof(enum overlay_visibility));

      for (i = 0; i < MAX_VISIBILITY; i++)
         input_st->overlay_visibility[i] = OVERLAY_VISIBILITY_DEFAULT;
   }

   input_st->overlay_visibility[overlay_idx] = vis;

   if (!ol)
      return;
   if (vis == OVERLAY_VISIBILITY_HIDDEN)
      ol->iface->set_alpha(ol->iface_data, overlay_idx, 0.0);
}

/* Attempts to automatically rotate the specified overlay.
 * Depends upon proper naming conventions in overlay
 * config file. */
void input_overlay_auto_rotate_(
      unsigned video_driver_width,
      unsigned video_driver_height,
      bool input_overlay_enable,
      input_overlay_t *ol)
{
   size_t i;
   enum overlay_orientation screen_orientation         = OVERLAY_ORIENTATION_PORTRAIT;
   enum overlay_orientation active_overlay_orientation = OVERLAY_ORIENTATION_NONE;
   bool tmp                                            = false;

   /* Sanity check */
   if (!ol || !(ol->flags & INPUT_OVERLAY_ALIVE) || !input_overlay_enable)
      return;

   /* Get current screen orientation */
   if (video_driver_width > video_driver_height)
      screen_orientation = OVERLAY_ORIENTATION_LANDSCAPE;

   /* Get orientation of active overlay */
   if (!string_is_empty(ol->active->name))
   {
      if (strstr(ol->active->name, "landscape"))
         active_overlay_orientation = OVERLAY_ORIENTATION_LANDSCAPE;
      else if (strstr(ol->active->name, "portrait"))
         active_overlay_orientation = OVERLAY_ORIENTATION_PORTRAIT;
      else /* Sanity check */
         return;
   }
   else /* Sanity check */
      return;

   /* If screen and overlay have the same orientation,
    * no action is required */
   if (screen_orientation == active_overlay_orientation)
      return;

   /* Attempt to find index of overlay corresponding
    * to opposite orientation */
   for (i = 0; i < ol->active->size; i++)
   {
      overlay_desc_t *desc = &ol->active->descs[i];

      if (!desc)
         continue;

      if (!string_is_empty(desc->next_index_name))
      {
         bool next_overlay_found = false;
         if (active_overlay_orientation == OVERLAY_ORIENTATION_LANDSCAPE)
            next_overlay_found = (strstr(desc->next_index_name, "portrait") != 0);
         else
            next_overlay_found = (strstr(desc->next_index_name, "landscape") != 0);

         if (next_overlay_found)
         {
            /* We have a valid target overlay
             * > Trigger 'overly next' command event
             * Note: tmp == false. This prevents CMD_EVENT_OVERLAY_NEXT
             * from calling input_overlay_auto_rotate_() again */
            ol->next_index     = desc->next_index;
            command_event(CMD_EVENT_OVERLAY_NEXT, &tmp);
            break;
         }
      }
   }
}

static void input_overlay_set_vertex_geom(input_overlay_t *ol)
{
   size_t i;

   if (!ol->iface->vertex_geom)
      return;

   if (ol->active->image.pixels)
      ol->iface->vertex_geom(ol->iface_data, 0,
            ol->active->mod_x, ol->active->mod_y,
            ol->active->mod_w, ol->active->mod_h);

   for (i = 0; i < ol->active->size; i++)
   {
      struct overlay_desc *desc = &ol->active->descs[i];
      if (desc->image.pixels)
         ol->iface->vertex_geom(ol->iface_data, desc->image_index,
               desc->mod_x, desc->mod_y, desc->mod_w, desc->mod_h);
   }
}

void input_overlay_load_active(
      enum overlay_visibility *visibility,
      input_overlay_t *ol, float opacity)
{
   if (ol->iface->load)
      ol->iface->load(ol->iface_data, ol->active->load_images,
            ol->active->load_images_size);

   input_overlay_set_alpha_mod(visibility, ol, opacity);
   input_overlay_set_vertex_geom(ol);

   if (ol->iface->full_screen)
      ol->iface->full_screen(ol->iface_data,
            (ol->active->flags & OVERLAY_FULL_SCREEN));
}

static void input_overlay_parse_layout(
      const struct overlay *ol,
      const overlay_layout_desc_t *layout_desc,
      float display_aspect_ratio,
      overlay_layout_t *overlay_layout)
{
   /* Set default values */
   overlay_layout->x_scale      = 1.0f;
   overlay_layout->y_scale      = 1.0f;
   overlay_layout->x_separation = 0.0f;
   overlay_layout->y_separation = 0.0f;
   overlay_layout->x_offset     = 0.0f;
   overlay_layout->y_offset     = 0.0f;

   /* Perform auto-scaling, if required */
   if (layout_desc->auto_scale)
   {
      /* Sanity check - if scaling is blocked,
       * or aspect ratios are invalid, then we
       * can do nothing */
      if (   (ol->flags & OVERLAY_BLOCK_SCALE)
          || (ol->aspect_ratio <= 0.0f)
          || (display_aspect_ratio <= 0.0f))
         return;

      /* If display is wider than overlay,
       * reduce width */
      if (display_aspect_ratio > ol->aspect_ratio)
      {
         overlay_layout->x_scale = ol->aspect_ratio /
               display_aspect_ratio;

         if (overlay_layout->x_scale <= 0.0f)
         {
            overlay_layout->x_scale = 1.0f;
            return;
         }

         /* If auto-scale X separation is enabled, move elements
          * horizontally towards the edges of the screen */
         if (ol->flags & OVERLAY_AUTO_X_SEPARATION)
            overlay_layout->x_separation = ((1.0f / overlay_layout->x_scale) - 1.0f) * 0.5f;
      }
      /* If display is taller than overlay,
       * reduce height */
      else
      {
         overlay_layout->y_scale = display_aspect_ratio /
               ol->aspect_ratio;

         if (overlay_layout->y_scale <= 0.0f)
         {
            overlay_layout->y_scale = 1.0f;
            return;
         }

         /* If auto-scale Y separation is enabled, move elements
          * vertically towards the edges of the screen */
         if (ol->flags & OVERLAY_AUTO_Y_SEPARATION)
            overlay_layout->y_separation = ((1.0f / overlay_layout->y_scale) - 1.0f) * 0.5f;
      }

      return;
   }

   /* Regular 'manual' scaling/position adjustment
    * > Landscape display orientations */
   if (display_aspect_ratio > 1.0f)
   {
      float scale              = layout_desc->scale_landscape;
      float aspect_adjust      = layout_desc->aspect_adjust_landscape;
      /* Note: Y offsets have their sign inverted,
       * since from a usability perspective positive
       * values should move the overlay upwards */
      overlay_layout->x_offset = layout_desc->x_offset_landscape;
      overlay_layout->y_offset = layout_desc->y_offset_landscape * -1.0f;

      if (!(ol->flags & OVERLAY_BLOCK_X_SEPARATION))
         overlay_layout->x_separation = layout_desc->x_separation_landscape;
      if (!(ol->flags & OVERLAY_BLOCK_Y_SEPARATION))
         overlay_layout->y_separation = layout_desc->y_separation_landscape;

      if (!(ol->flags & OVERLAY_BLOCK_SCALE))
      {
         /* In landscape orientations, aspect correction
          * adjusts the overlay width */
         overlay_layout->x_scale = (aspect_adjust >= 0.0f) ?
               (scale * (aspect_adjust + 1.0f)) :
               (scale / ((aspect_adjust * -1.0f) + 1.0f));
         overlay_layout->y_scale = scale;
      }
   }
   /* > Portrait display orientations */
   else
   {
      float scale              = layout_desc->scale_portrait;
      float aspect_adjust      = layout_desc->aspect_adjust_portrait;

      overlay_layout->x_offset = layout_desc->x_offset_portrait;
      overlay_layout->y_offset = layout_desc->y_offset_portrait * -1.0f;

      if (!(ol->flags & OVERLAY_BLOCK_X_SEPARATION))
         overlay_layout->x_separation = layout_desc->x_separation_portrait;
      if (!(ol->flags & OVERLAY_BLOCK_Y_SEPARATION))
         overlay_layout->y_separation = layout_desc->y_separation_portrait;

      if (!(ol->flags & OVERLAY_BLOCK_SCALE))
      {
         /* In portrait orientations, aspect correction
          * adjusts the overlay height */
         overlay_layout->x_scale = scale;
         overlay_layout->y_scale = (aspect_adjust >= 0.0f) ?
               (scale * (aspect_adjust + 1.0f)) :
               (scale / ((aspect_adjust * -1.0f) + 1.0f));
      }
   }
}

static void input_overlay_desc_init_hitbox(struct overlay_desc *desc)
{
   desc->x_hitbox       =
         ((desc->x_shift + desc->range_x * desc->reach_right) +
          (desc->x_shift - desc->range_x * desc->reach_left)) / 2.0f;

   desc->y_hitbox       =
         ((desc->y_shift + desc->range_y * desc->reach_down) +
          (desc->y_shift - desc->range_y * desc->reach_up)) / 2.0f;

   desc->range_x_hitbox =
         (desc->range_x * desc->reach_right +
          desc->range_x * desc->reach_left) / 2.0f;

   desc->range_y_hitbox =
         (desc->range_y * desc->reach_down +
          desc->range_y * desc->reach_up) / 2.0f;

   desc->range_x_mod    = desc->range_x_hitbox * desc->range_mod;
   desc->range_y_mod    = desc->range_y_hitbox * desc->range_mod;
}


/**
 * input_overlay_scale:
 * @ol                    : Overlay handle.
 * @layout                : Scale + offset factors.
 *
 * Scales the overlay and all its associated descriptors
 * and applies any aspect ratio/offset factors.
 **/
static void input_overlay_scale(struct overlay *ol,
      const overlay_layout_t *layout)
{
   size_t i;

   ol->mod_w = ol->w * layout->x_scale;
   ol->mod_h = ol->h * layout->y_scale;
   ol->mod_x = (ol->center_x + (ol->x - ol->center_x) *
         layout->x_scale) + layout->x_offset;
   ol->mod_y = (ol->center_y + (ol->y - ol->center_y) *
         layout->y_scale) + layout->y_offset;

   for (i = 0; i < ol->size; i++)
   {
      struct overlay_desc *desc = &ol->descs[i];
      float x_shift_offset      = 0.0f;
      float y_shift_offset      = 0.0f;
      float scale_w;
      float scale_h;
      float adj_center_x;
      float adj_center_y;

      /* Apply 'x separation' factor */
      if (desc->x < (0.5f - 0.0001f))
         x_shift_offset = layout->x_separation * -1.0f;
      else if (desc->x > (0.5f + 0.0001f))
         x_shift_offset = layout->x_separation;

      desc->x_shift     = desc->x + x_shift_offset;

      /* Apply 'y separation' factor */
      if (desc->y < (0.5f - 0.0001f))
         y_shift_offset = layout->y_separation * -1.0f;
      else if (desc->y > (0.5f + 0.0001f))
         y_shift_offset = layout->y_separation;

      desc->y_shift     = desc->y + y_shift_offset;

      scale_w           = ol->mod_w * desc->range_x;
      scale_h           = ol->mod_h * desc->range_y;
      adj_center_x      = ol->mod_x + desc->x_shift * ol->mod_w;
      adj_center_y      = ol->mod_y + desc->y_shift * ol->mod_h;

      desc->mod_w       = 2.0f * scale_w;
      desc->mod_h       = 2.0f * scale_h;
      desc->mod_x       = adj_center_x - scale_w;
      desc->mod_y       = adj_center_y - scale_h;

      input_overlay_desc_init_hitbox(desc);
   }
}


/**
 * input_overlay_set_scale_factor:
 * @ol                    : Overlay handle.
 * @layout_desc           : Scale + offset factors.
 *
 * Scales the overlay and applies any aspect ratio/
 * offset factors.
 **/
void input_overlay_set_scale_factor(
      input_overlay_t *ol, const overlay_layout_desc_t *layout_desc,
      unsigned video_driver_width,
      unsigned video_driver_height
)
{
   size_t i;
   float display_aspect_ratio = 0.0f;

   if (!ol || !layout_desc)
      return;

   if (video_driver_height > 0)
      display_aspect_ratio = (float)video_driver_width /
         (float)video_driver_height;

   for (i = 0; i < ol->size; i++)
   {
      struct overlay *current_overlay = &ol->overlays[i];
      overlay_layout_t overlay_layout;

      input_overlay_parse_layout(current_overlay,
            layout_desc, display_aspect_ratio, &overlay_layout);
      input_overlay_scale(current_overlay, &overlay_layout);
   }

   input_overlay_set_vertex_geom(ol);
}

static enum overlay_visibility input_overlay_get_visibility(
      enum overlay_visibility *visibility,
      int overlay_idx)
{
    if (!visibility)
       return OVERLAY_VISIBILITY_DEFAULT;
    if ((overlay_idx < 0) || (overlay_idx >= MAX_VISIBILITY))
       return OVERLAY_VISIBILITY_DEFAULT;
    return visibility[overlay_idx];
}

void input_overlay_set_alpha_mod(
      enum overlay_visibility *visibility,
      input_overlay_t *ol, float mod)
{
   unsigned i;

   if (!ol)
      return;

   for (i = 0; i < ol->active->load_images_size; i++)
   {
      if (input_overlay_get_visibility(visibility, i)
            == OVERLAY_VISIBILITY_HIDDEN)
          ol->iface->set_alpha(ol->iface_data, i, 0.0);
      else
          ol->iface->set_alpha(ol->iface_data, i, mod);
   }
}

static void input_overlay_get_eightway_slope_limits(
      const unsigned diagonal_sensitivity,
      float* low_slope, float* high_slope)
{
   /* Sensitivity setting is the relative size of diagonal zones to
    * cardinal zones. Convert to fraction of 45 deg span (max diagonal).
    */
   float f     =  2.0f * diagonal_sensitivity
             / (100.0f + diagonal_sensitivity);

   float high_angle  /* 67.5 deg max */
               = (f * (0.375 * M_PI) + (1.0f - f) * (0.25 * M_PI));
   float low_angle   /* 22.5 deg min */
               = (f * (0.125 * M_PI) + (1.0f - f) * (0.25 * M_PI));

   *high_slope = tan(high_angle);
   *low_slope  = tan(low_angle);
}

/**
 * input_overlay_set_eightway_diagonal_sensitivity:
 *
 * Gets the slope limits defining each eightway type's diagonal zones.
 */
void input_overlay_set_eightway_diagonal_sensitivity(void)
{
   settings_t           *settings = config_get_ptr();
   input_driver_state_t *input_st = input_state_get_ptr();

   input_overlay_get_eightway_slope_limits(
         settings->uints.input_overlay_dpad_diagonal_sensitivity,
         &input_st->overlay_eightway_dpad_slopes[0],
         &input_st->overlay_eightway_dpad_slopes[1]);

   input_overlay_get_eightway_slope_limits(
         settings->uints.input_overlay_abxy_diagonal_sensitivity,
         &input_st->overlay_eightway_abxy_slopes[0],
         &input_st->overlay_eightway_abxy_slopes[1]);
}

static void input_overlay_free_overlays(input_overlay_t *ol)
{
   size_t i;

   if (!ol || !ol->overlays)
      return;

   for (i = 0; i < ol->size; i++)
      input_overlay_free_overlay(&ol->overlays[i]);

   free(ol->overlays);
   ol->overlays = NULL;
}

/**
 * input_overlay_free:
 * @ol                    : Overlay handle.
 *
 * Frees overlay handle.
 **/
static void input_overlay_free(input_overlay_t *ol)
{
   if (!ol)
      return;

   input_overlay_free_overlays(ol);

   if (ol->iface && ol->iface->enable)
      ol->iface->enable(ol->iface_data, false);

   if (ol->path)
   {
      free(ol->path);
      ol->path = NULL;
   }

   free(ol);
}

static void input_overlay_deinit(void)
{
   input_driver_state_t *input_st = input_state_get_ptr();
   input_overlay_free(input_st->overlay_ptr);
   input_st->overlay_ptr = NULL;

   input_overlay_free(input_st->overlay_cache_ptr);
   input_st->overlay_cache_ptr = NULL;

   input_st->flags &= ~INP_FLAG_BLOCK_POINTER_INPUT;
}

static bool video_driver_overlay_interface(
      const video_overlay_interface_t **iface)
{
   video_driver_state_t *video_st = video_state_get_ptr();
   if (!video_st->current_video || !video_st->current_video->overlay_interface)
      return false;
   video_st->current_video->overlay_interface(video_st->data, iface);
   return true;
}

static void input_overlay_enable_(bool enable)
{
   settings_t *settings           = config_get_ptr();
   video_driver_state_t *video_st = video_state_get_ptr();
   input_driver_state_t *input_st = input_state_get_ptr();
   input_overlay_t *ol            = input_st->overlay_ptr;
   float opacity                  = (ol && (ol->flags & INPUT_OVERLAY_IS_OSK))
      ? settings->floats.input_osk_overlay_opacity
      : settings->floats.input_overlay_opacity;
   bool auto_rotate               = settings->bools.input_overlay_auto_rotate;
   bool hide_mouse_cursor         = !settings->bools.input_overlay_show_mouse_cursor
         && settings->bools.video_fullscreen;

   if (!ol)
      return;

   if (enable)
   {
      /* Set video interface */
      ol->iface_data = video_st->data;
      if (!video_driver_overlay_interface(&ol->iface) || !ol->iface)
      {
         RARCH_ERR("[Input] Overlay interface is not present in video driver.\n");
         ol->flags &= ~INPUT_OVERLAY_ALIVE;
         return;
      }

      /* Load last-active overlay */
      input_overlay_load_active(input_st->overlay_visibility, ol, opacity);

      /* Adjust to current settings */
      command_event(CMD_EVENT_OVERLAY_SET_SCALE_FACTOR, NULL);

      if (auto_rotate)
         input_overlay_auto_rotate_(
               video_st->width, video_st->height, true, ol);

      /* Enable */
      if (ol->iface->enable)
         ol->iface->enable(ol->iface_data, true);

      ol->flags |= (INPUT_OVERLAY_ENABLE | INPUT_OVERLAY_BLOCKED);

      if (     hide_mouse_cursor
            && video_st->poke
            && video_st->poke->show_mouse)
         video_st->poke->show_mouse(video_st->data, false);
   }
   else
   {
      /* Disable and clear input state */
      ol->flags       &= ~INPUT_OVERLAY_ENABLE;
      input_st->flags &= ~INP_FLAG_BLOCK_POINTER_INPUT;

      if (ol->iface && ol->iface->enable)
         ol->iface->enable(ol->iface_data, false);
      ol->iface = NULL;

      memset(&ol->overlay_state, 0, sizeof(input_overlay_state_t));
      memset(&ol->pointer_state, 0, sizeof(input_overlay_pointer_state_t));
   }
}


static void input_overlay_move_to_cache(void)
{
   input_driver_state_t *input_st = input_state_get_ptr();
   input_overlay_t      *ol       = input_st->overlay_ptr;

   if (!ol)
      return;

   /* Free existing cache */
   input_overlay_free(input_st->overlay_cache_ptr);

   /* Disable current overlay */
   input_overlay_enable_(false);

   /* Move to cache */
   input_st->overlay_cache_ptr = ol;
   input_st->overlay_ptr       = NULL;
}

void input_overlay_unload(void)
{
   bool input_overlay_enable   = config_get_ptr()->bools.input_overlay_enable;
   runloop_state_t *runloop_st = runloop_state_get_ptr();

   /* Free if overlays disabled or initing/deiniting core */
   if (     !input_overlay_enable
         || !(runloop_st->flags & RUNLOOP_FLAG_IS_INITED)
         ||  (runloop_st->flags & RUNLOOP_FLAG_SHUTDOWN_INITIATED))
      input_overlay_deinit();
   else
      input_overlay_move_to_cache();
}

static const char *input_overlay_path(bool want_osk)
{
   static char   system_overlay_path[PATH_MAX_LENGTH] = {0};
   char          overlay_directory[PATH_MAX_LENGTH];
   settings_t   *settings                             = config_get_ptr();
   core_info_t  *core_info                            = NULL;
   const char   *content_path                         = path_get(RARCH_PATH_CONTENT);

   if (want_osk)
      return settings->paths.path_osk_overlay;
   /* if the option is set to turn this off, just return default */
   if (!settings->bools.input_overlay_enable_autopreferred)
       return settings->paths.path_overlay;
   /* if there's an override, use it */
   if (retroarch_override_setting_is_set(RARCH_OVERRIDE_SETTING_OVERLAY_PRESET, NULL))
       return settings->paths.path_overlay;
   /* if there's no core, just return the default */
   if (string_is_empty(path_get(RARCH_PATH_CORE)))
      return settings->paths.path_overlay;

   /* let's go hunting */
   fill_pathname_expand_special(overlay_directory,
         settings->paths.directory_overlay,
         sizeof(overlay_directory));

#define SYSTEM_OVERLAY_DIR "gamepads/Named_Overlays"

   /* maybe the core info will have some clues */
   core_info_get_current_core(&core_info);
   if (core_info)
   {
      if(!string_is_empty(core_info->overlay_path))
      {
         fill_pathname_join_special(system_overlay_path, settings->paths.directory_overlay, core_info->overlay_path, sizeof(system_overlay_path));
         if (path_is_valid(system_overlay_path))
            return system_overlay_path;
      }

      if (core_info->databases_list && core_info->databases_list->size == 1)
      {
         fill_pathname_join_special_ext(system_overlay_path,
               overlay_directory, SYSTEM_OVERLAY_DIR, core_info->databases_list->elems[0].data, ".cfg",
               sizeof(system_overlay_path));
         if (path_is_valid(system_overlay_path))
            return system_overlay_path;
      }

      if (core_info->display_name)
      {
         fill_pathname_join_special_ext(system_overlay_path,
               overlay_directory, SYSTEM_OVERLAY_DIR, core_info->display_name, ".cfg",
               sizeof(system_overlay_path));
         if (path_is_valid(system_overlay_path))
            return system_overlay_path;
      }
   }

   /* maybe based on the content's directory name */
   if (!string_is_empty(content_path))
   {
      char dirname[DIR_MAX_LENGTH];
      fill_pathname_parent_dir_name(dirname, content_path, sizeof(dirname));
      fill_pathname_join_special_ext(system_overlay_path,
            overlay_directory, SYSTEM_OVERLAY_DIR, dirname, ".cfg",
            sizeof(system_overlay_path));
      if (path_is_valid(system_overlay_path))
         return system_overlay_path;
   }

   /* I give up */
   return settings->paths.path_overlay;
}

static bool input_overlay_want_hidden(void)
{
   settings_t *settings = config_get_ptr();
   bool hide            = false;
   if (settings->bools.input_overlay_hide_when_gamepad_connected)
      hide = hide || (input_config_get_device_name(0) != NULL);

   return hide;
}

static void input_overlay_swap_with_cached(void)
{
   input_driver_state_t *input_st = input_state_get_ptr();
   input_overlay_t      *ol;

   /* Disable current overlay */
   input_overlay_enable_(false);

   /* Swap with cached */
   ol                          = input_st->overlay_cache_ptr;
   input_st->overlay_cache_ptr = input_st->overlay_ptr;
   input_st->overlay_ptr       = ol;

   /* Enable and update to current settings */
   input_overlay_enable_(true);
}

/* task_data = overlay_task_data_t* */
static void input_overlay_loaded(retro_task_t *task,
      void *task_data, void *user_data, const char *err)
{

   uint16_t overlay_types;
   overlay_task_data_t  *data     = (overlay_task_data_t*)task_data;
   input_overlay_t      *ol       = NULL;
   input_driver_state_t *input_st = input_state_get_ptr();
   bool enable_overlay            = !input_overlay_want_hidden()
         && config_get_ptr()->bools.input_overlay_enable;

   if (err)
      return;

   ol              = (input_overlay_t*)calloc(1, sizeof(*ol));
   ol->overlays    = data->overlays;
   ol->size        = data->size;
   ol->active      = data->active;
   ol->path        = data->overlay_path;
   ol->next_index  = (unsigned)((ol->index + 1) % ol->size);
   ol->flags      |= INPUT_OVERLAY_ALIVE;
   if (data->flags & OVERLAY_LOADER_IS_OSK)
      ol->flags   |= INPUT_OVERLAY_IS_OSK;

   overlay_types   = data->overlay_types;

   free(data);

   /* Due to the asynchronous nature of overlay loading
    * it is possible for overlay_ptr to be non-NULL here
    * > Ensure it is free()'d before assigning new pointer */
   if (input_st->overlay_ptr)
      input_overlay_free(input_st->overlay_ptr);
   input_st->overlay_ptr = ol;

   /* Enable or disable the overlay */
   input_overlay_enable_(enable_overlay);

   /* Abort if enable failed */
   if (!(ol->flags & INPUT_OVERLAY_ALIVE))
   {
      input_st->overlay_ptr = NULL;
      input_overlay_free(ol);
      return;
   }

   /* Cache or free if hidden */
   if (!enable_overlay)
      input_overlay_unload();

   input_overlay_set_eightway_diagonal_sensitivity();

#ifdef HAVE_MENU
   /* Update menu entries if this is the main overlay */
   if (!(ol->flags & INPUT_OVERLAY_IS_OSK))
   {
      struct menu_state *menu_st = menu_state_get_ptr();

      if (menu_st->overlay_types != overlay_types)
      {
         menu_st->overlay_types = overlay_types;
         menu_st->flags        |=  MENU_ST_FLAG_ENTRIES_NEED_REFRESH;
      }
   }
#else
   input_st->overlay_types = overlay_types;
#endif // HAVE_MENU
}

void input_overlay_init(void)
{
   settings_t *settings           = config_get_ptr();
   input_driver_state_t *input_st = input_state_get_ptr();
   input_overlay_t *ol            = input_st->overlay_ptr;
   input_overlay_t *ol_cache      = input_st->overlay_cache_ptr;
   bool want_osk                  =
            (input_st->flags & INP_FLAG_KB_LINEFEED_ENABLE)
         && !string_is_empty(settings->paths.path_osk_overlay);
   const char *path_overlay       = input_overlay_path(want_osk);
   bool want_hidden               = input_overlay_want_hidden();
   bool overlay_shown             = ol
         && (ol->flags & INPUT_OVERLAY_ENABLE)
         && string_is_equal(path_overlay, ol->path);
   bool overlay_cached            = ol_cache
         && (ol_cache->flags & INPUT_OVERLAY_ALIVE)
         && string_is_equal(path_overlay, ol_cache->path);
   bool overlay_hidden            = !ol && overlay_cached;

#if defined(GEKKO)
   /* Avoid a crash at startup or even when toggling overlay in rgui */
   if (frontend_driver_get_free_memory() < (3 * 1024 * 1024))
      return;
#endif

   /* Cancel if overlays disabled or task already done */
   if (     !settings->bools.input_overlay_enable
         || ( want_hidden && overlay_hidden)
         || (!want_hidden && overlay_shown))
      return;

   /* Restore if cached */
   if (!want_hidden && overlay_cached)
   {
      input_overlay_swap_with_cached();
      return;
   }

   /* Cache current overlay when loading a different type */
   if (want_osk != (ol && (ol->flags & INPUT_OVERLAY_IS_OSK)))
      input_overlay_unload();
   else
      input_overlay_deinit();

   /* Start task */
   task_push_overlay_load_default(
         input_overlay_loaded, path_overlay, want_osk, NULL);
}

void input_overlay_check_mouse_cursor(void)
{
   input_driver_state_t *input_st = input_state_get_ptr();
   video_driver_state_t *video_st = video_state_get_ptr();
   input_overlay_t *ol            = input_st->overlay_ptr;

   if (     ol && (ol->flags & INPUT_OVERLAY_ENABLE)
         && video_st->poke
         && video_st->poke->show_mouse)
   {
      if (config_get_ptr()->bools.input_overlay_show_mouse_cursor)
         video_st->poke->show_mouse(video_st->data, true);
      else if (input_st->flags & INP_FLAG_GRAB_MOUSE_STATE)
         video_st->poke->show_mouse(video_st->data, false);
   }
}
