//
//  input_remapping.c
//  RetroArch
//
//  Created by haharsw on 2025/9/26.
//

#include <input/input_remapping.h>
#include <utils/configuration.h>

/**
 * input_remapping_load_file:
 * @data                     : Path to config file.
 *
 * Loads a remap file from disk to memory.
 *
 * Returns: true (1) if successful, otherwise false (0).
 **/
bool input_remapping_load_file(void *data, const char *path)
{
   unsigned i, j;
   config_file_t *conf                              = (config_file_t*)data;
   settings_t *settings                             = config_get_ptr();
   runloop_state_t *runloop_st                      = runloop_state_get_ptr();
   char key_strings[RARCH_FIRST_CUSTOM_BIND + 8][8] =
   {
      "b",      "y",      "select", "start",
      "up",     "down",   "left",   "right",
      "a",      "x",      "l",      "r",
      "l2",     "r2",     "l3",     "r3",
      "l_x+",   "l_x-",   "l_y+",   "l_y-",
      "r_x+",   "r_x-",   "r_y+",   "r_y-"
   };

   if (    !conf
         || string_is_empty(path))
      return false;

   if (!string_is_empty(runloop_st->name.remapfile))
      input_remapping_deinit(false);

   input_remapping_set_defaults(false);
   runloop_st->name.remapfile = strdup(path);

   for (i = 0; i < MAX_USERS; i++)
   {
      size_t _len;
      char prefix[16];
      char s1[32], s2[32], s3[32];
      char formatted_number[4];
      formatted_number[0] = '\0';
      snprintf(formatted_number, sizeof(formatted_number), "%u", i + 1);
      _len       = strlcpy(prefix, "input_player",   sizeof(prefix));
      strlcpy(prefix + _len, formatted_number, sizeof(prefix) - _len);
      _len       = strlcpy(s1, prefix, sizeof(s1));
      strlcpy(s1 + _len, "_btn", sizeof(s1) - _len);
      _len       = strlcpy(s2, prefix, sizeof(s2));
      strlcpy(s2 + _len, "_key", sizeof(s2) - _len);
      _len       = strlcpy(s3, prefix, sizeof(s3));
      strlcpy(s3 + _len, "_stk", sizeof(s3) - _len);

      for (j = 0; j < RARCH_FIRST_CUSTOM_BIND + 8; j++)
      {
         const char *key_string = key_strings[j];

         if (j < RARCH_FIRST_CUSTOM_BIND)
         {
            char ident[128];
            int _remap = -1;

            fill_pathname_join_delim(ident, s1,
                  key_string, '_', sizeof(ident));

            if (config_get_int(conf, ident, &_remap))
            {
               if (_remap == -1)
                  _remap = RARCH_UNMAPPED;

               configuration_set_uint(settings,
                     settings->uints.input_remap_ids[i][j], _remap);
            }

            fill_pathname_join_delim(ident, s2,
                  key_string, '_', sizeof(ident));

            _remap = -1;

            if (!config_get_int(conf, ident, &_remap))
               _remap = RETROK_UNKNOWN;

            configuration_set_uint(settings,
                  settings->uints.input_keymapper_ids[i][j], _remap);
         }
         else
         {
            char ident[256];
            int _remap = -1;

            fill_pathname_join_delim(ident, s3,
                  key_string, '_', sizeof(ident));

            if (config_get_int(conf, ident, &_remap))
            {
               if (_remap == -1)
                  _remap = RARCH_UNMAPPED;

               configuration_set_uint(settings,
                     settings->uints.input_remap_ids[i][j], _remap);
            }

            fill_pathname_join_delim(ident, s2,
                  key_string, '_', sizeof(ident));

            _remap = -1;

            if (!config_get_int(conf, ident, &_remap))
               _remap = RETROK_UNKNOWN;

            configuration_set_uint(settings,
                  settings->uints.input_keymapper_ids[i][j], _remap);
         }
      }

      _len = strlcpy(s1, "input_libretro_device_p", sizeof(s1));
      strlcpy(s1 + _len, formatted_number, sizeof(s1) - _len);
      CONFIG_GET_INT_BASE(conf, settings, uints.input_libretro_device[i], s1);

      _len = strlcpy(s1, prefix, sizeof(s1));
      strlcpy(s1 + _len, "_analog_dpad_mode", sizeof(s1) - _len);
      CONFIG_GET_INT_BASE(conf, settings, uints.input_analog_dpad_mode[i], s1);

      _len = strlcpy(s1, "input_remap_port_p", sizeof(s1));
      strlcpy(s1 + _len, formatted_number, sizeof(s1) - _len);
      CONFIG_GET_INT_BASE(conf, settings, uints.input_remap_ports[i], s1);
   }

   /* Turbo fire settings */
   CONFIG_GET_BOOL_BASE(conf, settings, bools.input_turbo_enable, "input_turbo_enable");
   CONFIG_GET_BOOL_BASE(conf, settings, bools.input_turbo_allow_dpad, "input_turbo_allow_dpad");
   CONFIG_GET_INT_BASE(conf, settings, uints.input_turbo_mode, "input_turbo_mode");
   CONFIG_GET_INT_BASE(conf, settings, ints.input_turbo_bind, "input_turbo_bind");
   CONFIG_GET_INT_BASE(conf, settings, uints.input_turbo_button, "input_turbo_button");
   CONFIG_GET_INT_BASE(conf, settings, uints.input_turbo_period, "input_turbo_period");
   CONFIG_GET_INT_BASE(conf, settings, uints.input_turbo_duty_cycle, "input_turbo_duty_cycle");

   input_remapping_update_port_map();

   /* Whenever a remap file is loaded, subsequent
    * changes to global remap-related parameters
    * must be reset at the next core deinitialisation */
   input_state_get_ptr()->flags   |=  INP_FLAG_REMAPPING_CACHE_ACTIVE;

   return true;
}

/**
 * input_remapping_save_file:
 * @path                     : Path to remapping file.
 *
 * Saves remapping values to file.
 *
 * Returns: true (1) if successful, otherwise false (0).
 **/
bool input_remapping_save_file(const char *path)
{
   bool ret;
   unsigned i, j;
   char remap_file_dir[DIR_MAX_LENGTH];
   char key_strings[RARCH_FIRST_CUSTOM_BIND + 8][8] =
   {
      "b",      "y",      "select", "start",
      "up",     "down",   "left",   "right",
      "a",      "x",      "l",      "r",
      "l2",     "r2",     "l3",     "r3",
      "l_x+",   "l_x-",   "l_y+",   "l_y-",
      "r_x+",   "r_x-",   "r_y+",   "r_y-"
   };
   config_file_t         *conf = NULL;
   runloop_state_t *runloop_st = runloop_state_get_ptr();
   settings_t        *settings = config_get_ptr();
   unsigned          max_users = settings->uints.input_max_users;

   if (string_is_empty(path))
      return false;

   /* Create output directory, if required */
   fill_pathname_parent_dir(remap_file_dir, path,
         sizeof(remap_file_dir));

   if (   !string_is_empty(remap_file_dir)
       && !path_is_directory(remap_file_dir)
       && !path_mkdir(remap_file_dir))
      return false;

   /* Attempt to load file */
   if (!(conf = config_file_new_alloc()))
      return false;

   for (i = 0; i < MAX_USERS; i++)
   {
      size_t _len;
      bool skip_port = true;
      char formatted_number[4];
      char prefix[16];
      char s1[32];
      char s2[32];
      char s3[32];

      formatted_number[0] = '\0';

      /* We must include all mapped ports + all those
       * with an index less than max_users */
      if (i < max_users)
         skip_port = false;
      else
      {
         /* Check whether current port is mapped
          * to an input device */
         for (j = 0; j < max_users; j++)
         {
            if (i == settings->uints.input_remap_ports[j])
            {
               skip_port = false;
               break;
            }
         }
      }

      if (skip_port)
         continue;

      _len = snprintf(formatted_number, sizeof(formatted_number), "%u", i + 1);
      if (_len >= sizeof(formatted_number)) {
         RARCH_ERR("[Config] Unexpectedly high number of users.");
         break;
      }
      _len       = strlcpy(prefix, "input_player",   sizeof(prefix));
      strlcpy(prefix + _len, formatted_number, sizeof(prefix) - _len);
      _len       = strlcpy(s1, prefix, sizeof(s1));
      strlcpy(s1 + _len, "_btn", sizeof(s1) - _len);
      _len       = strlcpy(s2, prefix, sizeof(s2));
      strlcpy(s2 + _len, "_key", sizeof(s2) - _len);
      _len       = strlcpy(s3, prefix, sizeof(s3));
      strlcpy(s3 + _len, "_stk", sizeof(s3) - _len);

      for (j = 0; j < RARCH_FIRST_CUSTOM_BIND; j++)
      {
         char _ident[128];
         const char *key_string = key_strings[j];
         unsigned remap_id      = settings->uints.input_remap_ids[i][j];
         unsigned keymap_id     = settings->uints.input_keymapper_ids[i][j];

         fill_pathname_join_delim(_ident, s1,
               key_string, '_', sizeof(_ident));

         /* Only save modified button values */
         if (remap_id == j)
            config_unset(conf, _ident);
         else
         {
            if (remap_id == RARCH_UNMAPPED)
            {
               if (string_is_empty(runloop_st->system.input_desc_btn[i][j]))
                  config_unset(conf, _ident);
               else
                  config_set_int(conf, _ident, -1);
            }
            else
               config_set_int(conf, _ident,
                     settings->uints.input_remap_ids[i][j]);
         }

         fill_pathname_join_delim(_ident, s2,
               key_string, '_', sizeof(_ident));

         /* Only save non-empty keymapper values */
         if (keymap_id == RETROK_UNKNOWN)
            config_unset(conf, _ident);
         else
            config_set_int(conf, _ident,
                  settings->uints.input_keymapper_ids[i][j]);
      }

      for (j = RARCH_FIRST_CUSTOM_BIND; j < (RARCH_FIRST_CUSTOM_BIND + 8); j++)
      {
         char _ident[128];
         const char *key_string = key_strings[j];
         unsigned remap_id      = settings->uints.input_remap_ids[i][j];
         unsigned keymap_id     = settings->uints.input_keymapper_ids[i][j];

         fill_pathname_join_delim(_ident, s3,
               key_string, '_', sizeof(_ident));

         /* Only save modified button values */
         if (remap_id == j)
            config_unset(conf, _ident);
         else
         {
            if (remap_id == RARCH_UNMAPPED)
            {
               if (string_is_empty(runloop_st->system.input_desc_btn[i][j]))
                  config_unset(conf, _ident);
               else
                  config_set_int(conf, _ident, -1);
            }
            else
               config_set_int(conf, _ident,
                     settings->uints.input_remap_ids[i][j]);
         }

         fill_pathname_join_delim(_ident, s2,
               key_string, '_', sizeof(_ident));

         /* Only save non-empty keymapper values */
         if (keymap_id == RETROK_UNKNOWN)
            config_unset(conf, _ident);
         else
            config_set_int(conf, _ident,
                  settings->uints.input_keymapper_ids[i][j]);
      }

      _len = strlcpy(s1, "input_libretro_device_p", sizeof(s1));
      strlcpy(s1 + _len, formatted_number, sizeof(s1) - _len);
      config_set_int(conf, s1, input_config_get_device(i));

      _len = strlcpy(s1, prefix, sizeof(s1));
      strlcpy(s1 + _len, "_analog_dpad_mode", sizeof(s1) - _len);
      config_set_int(conf, s1, settings->uints.input_analog_dpad_mode[i]);

      _len = strlcpy(s1, "input_remap_port_p", sizeof(s1));
      strlcpy(s1 + _len, formatted_number, sizeof(s1) - _len);
      config_set_int(conf, s1, settings->uints.input_remap_ports[i]);
   }

   /* Turbo fire settings */
   config_set_string(conf, "input_turbo_enable", settings->bools.input_turbo_enable ? "true" : "false");
   config_set_string(conf, "input_turbo_allow_dpad", settings->bools.input_turbo_allow_dpad ? "true" : "false");
   config_set_int(conf, "input_turbo_mode", settings->uints.input_turbo_mode);
   config_set_int(conf, "input_turbo_bind", settings->ints.input_turbo_bind);
   config_set_int(conf, "input_turbo_button", settings->uints.input_turbo_button);
   config_set_int(conf, "input_turbo_period", settings->uints.input_turbo_period);
   config_set_int(conf, "input_turbo_duty_cycle", settings->uints.input_turbo_duty_cycle);

   ret = config_file_write(conf, path, true);
   config_file_free(conf);

   /* Cache remap file path
    * > Must guard against the case where
    *   runloop_st->name.remapfile itself
    *   is passed to this function... */
   if (runloop_st->name.remapfile != path)
   {
      if (runloop_st->name.remapfile)
         free(runloop_st->name.remapfile);
      runloop_st->name.remapfile = strdup(path);
   }

   return ret;
}

void input_remapping_cache_global_config(void)
{
   unsigned i;
   settings_t *settings           = config_get_ptr();
   input_driver_state_t *input_st = input_state_get_ptr();

   for (i = 0; i < MAX_USERS; i++)
   {
      /* Libretro device type is always set to
       * RETRO_DEVICE_JOYPAD globally *unless*
       * an override has been set via the command
       * line interface */
      unsigned device = RETRO_DEVICE_JOYPAD;

      if (retroarch_override_setting_is_set(
            RARCH_OVERRIDE_SETTING_LIBRETRO_DEVICE, &i))
         device = settings->uints.input_libretro_device[i];

      input_st->remapping_cache.analog_dpad_mode[i] = settings->uints.input_analog_dpad_mode[i];
      input_st->remapping_cache.libretro_device[i]  = device;
   }

   input_st->remapping_cache.turbo_enable     = settings->bools.input_turbo_enable;
   input_st->remapping_cache.turbo_allow_dpad = settings->bools.input_turbo_allow_dpad;
   input_st->remapping_cache.turbo_bind       = settings->ints.input_turbo_bind;
   input_st->remapping_cache.turbo_mode       = settings->uints.input_turbo_mode;
   input_st->remapping_cache.turbo_button     = settings->uints.input_turbo_button;
   input_st->remapping_cache.turbo_period     = settings->uints.input_turbo_period;
   input_st->remapping_cache.turbo_duty_cycle = settings->uints.input_turbo_duty_cycle;
}

void input_remapping_restore_global_config(bool clear_cache, bool restore_analog_dpad_mode)
{
   unsigned i;
   settings_t *settings           = config_get_ptr();
   input_driver_state_t *input_st = input_state_get_ptr();

   if (!(input_st->flags & INP_FLAG_REMAPPING_CACHE_ACTIVE))
      goto end;

   for (i = 0; i < MAX_USERS; i++)
   {
      if (restore_analog_dpad_mode)
         configuration_set_uint(settings,
               settings->uints.input_analog_dpad_mode[i],
               input_st->remapping_cache.analog_dpad_mode[i]);

      configuration_set_uint(settings,
            settings->uints.input_libretro_device[i],
            input_st->remapping_cache.libretro_device[i]);
   }

   configuration_set_bool(settings,
         settings->bools.input_turbo_enable,
         input_st->remapping_cache.turbo_enable);

   configuration_set_bool(settings,
         settings->bools.input_turbo_allow_dpad,
         input_st->remapping_cache.turbo_allow_dpad);

   configuration_set_int(settings,
         settings->ints.input_turbo_bind,
         input_st->remapping_cache.turbo_bind);

   configuration_set_uint(settings,
         settings->uints.input_turbo_mode,
         input_st->remapping_cache.turbo_mode);

   configuration_set_uint(settings,
         settings->uints.input_turbo_button,
         input_st->remapping_cache.turbo_button);

   configuration_set_uint(settings,
         settings->uints.input_turbo_period,
         input_st->remapping_cache.turbo_period);

   configuration_set_uint(settings,
         settings->uints.input_turbo_duty_cycle,
         input_st->remapping_cache.turbo_duty_cycle);

end:
   if (clear_cache)
      input_st->flags &= ~INP_FLAG_REMAPPING_CACHE_ACTIVE;
}

void input_remapping_update_port_map(void)
{
   unsigned i, j;
   settings_t *settings               = config_get_ptr();
   unsigned port_map_index[MAX_USERS] = {0};

   /* First pass: 'reset' port map */
   for (i = 0; i < MAX_USERS; i++)
      for (j = 0; j < (MAX_USERS + 1); j++)
         settings->uints.input_remap_port_map[i][j] = MAX_USERS;

   /* Second pass: assign port indices from
    * 'input_remap_ports' */
   for (i = 0; i < MAX_USERS; i++)
   {
      unsigned remap_port = settings->uints.input_remap_ports[i];

      if (remap_port < MAX_USERS)
      {
         /* 'input_remap_port_map' provides a list of
          * 'physical' ports for each 'virtual' port
          * sampled in input_state().
          * (Note: in the following explanation, port
          * index starts from 0, rather than the frontend
          * display convention of 1)
          * For example - the following remap configuration
          * will map input devices 0+1 to port 0, and input
          * device 2 to port 1
          * > input_remap_ports[0] = 0;
          *   input_remap_ports[1] = 0;
          *   input_remap_ports[2] = 1;
          * This gives a port map of:
          * > input_remap_port_map[0] = { 0, 1, MAX_USERS, ... };
          *   input_remap_port_map[1] = { 2, MAX_USERS, ... }
          *   input_remap_port_map[2] = { MAX_USERS, ... }
          *   ...
          * A port map value of MAX_USERS indicates the end
          * of the 'physical' port list */
         settings->uints.input_remap_port_map[remap_port]
               [port_map_index[remap_port]] = i;
         port_map_index[remap_port]++;
      }
   }
}

void input_remapping_deinit(bool save_remap)
{
   runloop_state_t *runloop_st  = runloop_state_get_ptr();
   if (runloop_st->name.remapfile)
   {
      if (save_remap)
         input_remapping_save_file(runloop_st->name.remapfile);

      free(runloop_st->name.remapfile);
   }
   runloop_st->name.remapfile   = NULL;
   runloop_st->flags           &= ~(RUNLOOP_FLAG_REMAPS_CORE_ACTIVE
                               |    RUNLOOP_FLAG_REMAPS_CONTENT_DIR_ACTIVE
                               |    RUNLOOP_FLAG_REMAPS_GAME_ACTIVE);
}

void input_remapping_set_defaults(bool clear_cache)
{
   unsigned i, j;
   settings_t *settings        = config_get_ptr();

   for (i = 0; i < MAX_USERS; i++)
   {
      /* Button/keyboard remaps */
      for (j = 0; j < RARCH_FIRST_CUSTOM_BIND; j++)
      {
         const struct retro_keybind *keybind = &input_config_binds[i][j];

         configuration_set_uint(settings,
               settings->uints.input_remap_ids[i][j],
                     keybind ? keybind->id : RARCH_UNMAPPED);

         configuration_set_uint(settings,
               settings->uints.input_keymapper_ids[i][j], RETROK_UNKNOWN);
      }

      /* Analog stick remaps */
      for (j = RARCH_FIRST_CUSTOM_BIND; j < (RARCH_FIRST_CUSTOM_BIND + 8); j++)
         configuration_set_uint(settings,
               settings->uints.input_remap_ids[i][j], j);

      /* Controller port remaps */
      configuration_set_uint(settings,
            settings->uints.input_remap_ports[i], i);
   }

   /* Need to call 'input_remapping_update_port_map()'
    * whenever 'settings->uints.input_remap_ports'
    * is modified */
   input_remapping_update_port_map();

   /* Restore 'global' settings that were cached on
    * the last core init
    * > Prevents remap changes from 'bleeding through'
    *   into the main config file */
   input_remapping_restore_global_config(clear_cache, true);
}

const char *input_config_bind_map_get_base(unsigned bind_index)
{
   const struct input_bind_map *keybind =
      (const struct input_bind_map*)INPUT_CONFIG_BIND_MAP_GET(bind_index);
   if (!keybind)
      return NULL;
   return keybind->base;
}

unsigned input_config_bind_map_get_meta(unsigned bind_index)
{
   const struct input_bind_map *keybind =
      (const struct input_bind_map*)INPUT_CONFIG_BIND_MAP_GET(bind_index);
   if (!keybind)
      return 0;
   return keybind->meta;
}

const char *input_config_bind_map_get_desc(unsigned bind_index)
{
   const struct input_bind_map *keybind =
      (const struct input_bind_map*)INPUT_CONFIG_BIND_MAP_GET(bind_index);
   if (!keybind)
      return NULL;
   return msg_hash_to_str(keybind->desc);
}

uint8_t input_config_bind_map_get_retro_key(unsigned bind_index)
{
   const struct input_bind_map *keybind =
      (const struct input_bind_map*)INPUT_CONFIG_BIND_MAP_GET(bind_index);
   if (!keybind)
      return 0;
   return keybind->retro_key;
}

/**
 * input_config_translate_str_to_rk:
 * @str                            : String to translate to key ID.
 *
 * Translates string representation to key identifier.
 *
 * Returns: key identifier.
 **/
enum retro_key input_config_translate_str_to_rk(const char *str, size_t len)
{
   size_t i;
   if (len == 1 && ISALPHA((int)*str))
      return (enum retro_key)(RETROK_a + (TOLOWER((int)*str) - (int)'a'));
   for (i = 0; input_config_key_map[i].str; i++)
   {
      if (string_is_equal_noncase(input_config_key_map[i].str, str))
         return input_config_key_map[i].key;
   }
   return RETROK_UNKNOWN;
}

/**
 * input_config_translate_str_to_bind_id:
 * @str                            : String to translate to bind ID.
 *
 * Translate string representation to bind ID.
 *
 * Returns: Bind ID value on success, otherwise
 * RARCH_BIND_LIST_END on not found.
 **/
unsigned input_config_translate_str_to_bind_id(const char *str)
{
   unsigned i;

   for (i = 0; input_config_bind_map[i].valid; i++)
      if (string_is_equal(str, input_config_bind_map[i].base))
         return i;

   return RARCH_BIND_LIST_END;
}

static uint16_t input_config_parse_hat(const char *dir)
{
   if (     dir[0] == 'u'
         && dir[1] == 'p'
         && dir[2] == '\0'
      )
      return HAT_UP_MASK;
   else if (
            dir[0] == 'd'
         && dir[1] == 'o'
         && dir[2] == 'w'
         && dir[3] == 'n'
         && dir[4] == '\0'
         )
      return HAT_DOWN_MASK;
   else if (
            dir[0] == 'l'
         && dir[1] == 'e'
         && dir[2] == 'f'
         && dir[3] == 't'
         && dir[4] == '\0'
         )
      return HAT_LEFT_MASK;
   else if (
            dir[0] == 'r'
         && dir[1] == 'i'
         && dir[2] == 'g'
         && dir[3] == 'h'
         && dir[4] == 't'
         && dir[5] == '\0'
         )
      return HAT_RIGHT_MASK;

   return 0;
}

static void input_config_parse_joy_button(
      char *s,
      void *data, const char *prefix,
      const char *btn, void *bind_data)
{
   char tmp[64];
   char key[64];
   config_file_t *conf                     = (config_file_t*)data;
   struct retro_keybind *bind              = (struct retro_keybind*)bind_data;
   struct config_entry_list *tmp_a         = NULL;

   tmp[0]                                  = '\0';

   fill_pathname_join_delim(key, s,
         "btn", '_', sizeof(key));

   if (config_get_array(conf, key, tmp, sizeof(tmp)))
   {
      btn = tmp;
      if (     btn[0] == 'n'
            && btn[1] == 'u'
            && btn[2] == 'l'
            && btn[3] == '\0'
         )
         bind->joykey = NO_BTN;
      else
      {
         if (*btn == 'h')
         {
            const char *str = btn + 1;
            /* Parse hat? */
            if (str && ISDIGIT((int)*str))
            {
               char        *dir = NULL;
               uint16_t     hat = strtoul(str, &dir, 0);
               uint16_t hat_dir = dir ? input_config_parse_hat(dir) : 0;
               if (hat_dir)
                  bind->joykey = HAT_MAP(hat, hat_dir);
            }
         }
         else
            bind->joykey = strtoull(tmp, NULL, 0);
      }
   }

   fill_pathname_join_delim(key, s,
         "btn_label", '_', sizeof(key));

   tmp_a = config_get_entry(conf, key);

   if (tmp_a && !string_is_empty(tmp_a->value))
   {
      if (!string_is_empty(bind->joykey_label))
         free(bind->joykey_label);

      bind->joykey_label = strdup(tmp_a->value);
   }
}

static void input_config_parse_joy_axis(
      char *s,
      void *conf_data, const char *prefix,
      const char *axis, void *bind_data)
{
   char       tmp[64];
   char       key[64];
   config_file_t *conf                     = (config_file_t*)conf_data;
   struct retro_keybind *bind              = (struct retro_keybind*)bind_data;
   struct config_entry_list *tmp_a         = NULL;

   tmp[0] = '\0';

   fill_pathname_join_delim(key, s,
         "axis", '_', sizeof(key));

   if (config_get_array(conf, key, tmp, sizeof(tmp)))
   {
      if (     tmp[0] == 'n'
            && tmp[1] == 'u'
            && tmp[2] == 'l'
            && tmp[3] == '\0'
         )
         bind->joyaxis = AXIS_NONE;
      else if
         (     tmp[0] != '\0'
          &&   tmp[1] != '\0'
          && (*tmp    == '+'
          ||  *tmp    == '-'))
      {
         int i_axis = (int)strtol(tmp + 1, NULL, 0);
         if (*tmp == '+')
            bind->joyaxis = AXIS_POS(i_axis);
         else
            bind->joyaxis = AXIS_NEG(i_axis);
      }
   }

   fill_pathname_join_delim(key, s,
         "axis_label", '_', sizeof(key));

   tmp_a = config_get_entry(conf, key);

   if (tmp_a && (!string_is_empty(tmp_a->value)))
   {
      if (bind->joyaxis_label &&
            !string_is_empty(bind->joyaxis_label))
         free(bind->joyaxis_label);
      bind->joyaxis_label = strdup(tmp_a->value);
   }
}

static void input_config_parse_mouse_button(
      char *s,
      void *conf_data, const char *prefix,
      const char *btn, void *bind_data)
{
   int val;
   char tmp[64];
   char key[64];
   config_file_t *conf        = (config_file_t*)conf_data;
   struct retro_keybind *bind = (struct retro_keybind*)bind_data;

   tmp[0] = '\0';

   fill_pathname_join_delim(key, s, "mbtn", '_', sizeof(key));

   if (config_get_array(conf, key, tmp, sizeof(tmp)))
   {
      bind->mbutton = NO_BTN;

      if (tmp[0]=='w')
      {
         switch (tmp[1])
         {
            case 'u':
               bind->mbutton = RETRO_DEVICE_ID_MOUSE_WHEELUP;
               break;
            case 'd':
               bind->mbutton = RETRO_DEVICE_ID_MOUSE_WHEELDOWN;
               break;
            case 'h':
               switch (tmp[2])
               {
                  case 'u':
                     bind->mbutton = RETRO_DEVICE_ID_MOUSE_HORIZ_WHEELUP;
                     break;
                  case 'd':
                     bind->mbutton = RETRO_DEVICE_ID_MOUSE_HORIZ_WHEELDOWN;
                     break;
               }
               break;
         }
      }
      else
      {
         val = atoi(tmp);
         switch (val)
         {
            case 1:
               bind->mbutton = RETRO_DEVICE_ID_MOUSE_LEFT;
               break;
            case 2:
               bind->mbutton = RETRO_DEVICE_ID_MOUSE_RIGHT;
               break;
            case 3:
               bind->mbutton = RETRO_DEVICE_ID_MOUSE_MIDDLE;
               break;
            case 4:
               bind->mbutton = RETRO_DEVICE_ID_MOUSE_BUTTON_4;
               break;
            case 5:
               bind->mbutton = RETRO_DEVICE_ID_MOUSE_BUTTON_5;
               break;
         }
      }
   }
}

void input_keyboard_mapping_bits(unsigned mode, unsigned key)
{
   input_driver_state_t *input_st = input_state_get_ptr();
   switch (mode)
   {
      case 0:
         BIT512_CLEAR_PTR(&input_st->keyboard_mapping_bits, key);
         break;
      case 1:
         BIT512_SET_PTR(&input_st->keyboard_mapping_bits, key);
         break;
      default:
         break;
   }
}

void config_read_keybinds_conf(void *data)
{
   unsigned i;
   config_file_t            *conf = (config_file_t*)data;
   bool key_store[RETROK_LAST]    = {0};

   if (!conf)
      return;

   for (i = 0; i < MAX_USERS; i++)
   {
      unsigned j;

      for (j = 0; input_config_bind_map_get_valid(j); j++)
      {
         char str[NAME_MAX_LENGTH];
         const struct input_bind_map *keybind =
            (const struct input_bind_map*)INPUT_CONFIG_BIND_MAP_GET(j);
         struct retro_keybind *bind = &input_config_binds[i][j];
         bool meta                  = false;
         const char *prefix         = NULL;
         const char *btn            = NULL;
         struct config_entry_list
            *entry                  = NULL;


         if (!bind || !bind->valid || !keybind)
            continue;
         if (!keybind->valid)
            continue;
         meta                       = keybind->meta;
         btn                        = keybind->base;
         prefix                     = input_config_get_prefix(i, meta);
         if (!btn || !prefix)
            continue;

         fill_pathname_join_delim(str, prefix, btn,  '_', sizeof(str));

         /* Clear old mapping bit unless just recently set */
         if (!key_store[bind->key])
            input_keyboard_mapping_bits(0, bind->key);

         entry                      = config_get_entry(conf, str);
         if (entry && !string_is_empty(entry->value))
            bind->key               = input_config_translate_str_to_rk(
                  entry->value, strlen(entry->value));

         /* Store new mapping bit and remember it for a while
          * so that next clear leaves the new key alone */
         input_keyboard_mapping_bits(1, bind->key);
         key_store[bind->key]       = true;

         input_config_parse_joy_button  (str, conf, prefix, btn, bind);
         input_config_parse_joy_axis    (str, conf, prefix, btn, bind);
         input_config_parse_mouse_button(str, conf, prefix, btn, bind);
      }
   }
}

void input_config_set_autoconfig_binds(unsigned port, void *data)
{
   unsigned i;
   config_file_t *config       = (config_file_t*)data;
   struct retro_keybind *binds = NULL;

   if (    (port >= MAX_USERS)
         || !config)
      return;

   binds = input_autoconf_binds[port];

   for (i = 0; i < RARCH_BIND_LIST_END; i++)
   {
      const struct input_bind_map *keybind =
         (const struct input_bind_map*)INPUT_CONFIG_BIND_MAP_GET(i);
      if (keybind)
      {
         char str[256];
         const char *base = keybind->base;
         fill_pathname_join_delim(str, "input", base,  '_', sizeof(str));

         input_config_parse_joy_button(str, config, "input", base, &binds[i]);
         input_config_parse_joy_axis  (str, config, "input", base, &binds[i]);
      }
   }
}

void input_mapper_reset(void *data)
{
   unsigned i;
   input_mapper_t *handle = (input_mapper_t*)data;

   for (i = 0; i < MAX_USERS; i++)
   {
      unsigned j;
      for (j = 0; j < 8; j++)
      {
         handle->analog_value[i][j]           = 0;
         handle->buttons[i].data[j]           = 0;
         handle->buttons[i].analogs[j]        = 0;
         handle->buttons[i].analog_buttons[j] = 0;
      }
   }
   for (i = 0; i < RETROK_LAST; i++)
      handle->key_button[i]         = 0;
   for (i = 0; i < (RETROK_LAST / 32 + 1); i++)
      handle->keys[i]               = 0;
}
