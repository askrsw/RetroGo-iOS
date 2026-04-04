/**
 *  RetroArch - A frontend for libretro.
 *  Copyright (C) 2010-2014 - Hans-Kristian Arntzen
 *  Copyright (C) 2011-2017 - Daniel De Matteis
 *  Copyright (C) 2016-2019 - Andr s Su rez (input mapper code)
 *
 *  RetroArch is free software: you can redistribute it and/or modify it under
 *  the terms of the GNU General Public License as published by the Free
 *  Software Foundation, either version 3 of the License, or (at your option)
 *  any later version.
 *
 *  RetroArch is distributed in the hope that it will be useful, but WITHOUT
 *  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 *  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
 *  more details.
 *
 *  You should have received a copy of the GNU General Public License along
 *  with RetroArch. If not, see <http://www.gnu.org/licenses/>.
 **/

#define _USE_MATH_DEFINES
#include <math.h>
#include <string/stdstring.h>
#include <encodings/utf.h>
#include <clamping.h>
#include <retro_endianness.h>

#include <input/input_driver.h>
#include <input/input_keymaps.h>
#include <input/input_osk.h>
#include <input/input_types.h>

#ifdef HAVE_CHEEVOS
#include <cheevos/cheevos.h>
#endif

#ifdef HAVE_NETWORKING
#include <net/net_compat.h>
#include <net/net_socket.h>
#endif

#include <accessibility.h>
#include <emu/command.h>
#include <input/config.def.keybinds.h>
#include <utils/configuration.h>
#include <core/core_info.h>
#include <utils/driver_utils.h>
#include <utils/list_special.h>
#include <utils/retro_paths.h>
#include <utils/performance_counters.h>
#include <main/retroarch.h>
#ifdef HAVE_BSV_MOVIE
#include <tasks/task_content.h>
#endif
#include <tasks/tasks_internal.h>
#include <utils/verbosity.h>

#include <game_ai.h>

#define HOLD_BTN_DELAY_SEC 2

/* Depends on ASCII character values */
#define ISPRINT(c) (((int)(c) >= ' ' && (int)(c) <= '~') ? 1 : 0)

#define INPUT_REMOTE_KEY_PRESSED(input_st, key, port) (input_st->remote_st_ptr.buttons[(port)] & (UINT64_C(1) << (key)))

#define IS_COMPOSITION(c)       ( (c & 0x0F000000) ? 1 : 0)
#define IS_COMPOSITION_KR(c)    ( (c & 0x01000000) ? 1 : 0)
#define IS_END_COMPOSITION(c)   ( (c & 0xF0000000) ? 1 : 0)

/**
 * check_input_driver_block_hotkey:
 *
 * Checks if 'hotkey enable' key is pressed.
 *
 * If we haven't bound anything to this,
 * always allow hotkeys.

 * If we hold ENABLE_HOTKEY button, block all libretro input to allow
 * hotkeys to be bound to same keys as RetroPad.
 **/
#define CHECK_INPUT_DRIVER_BLOCK_HOTKEY(normal_bind, autoconf_bind) \
( \
         (((normal_bind)->key      != RETROK_UNKNOWN) \
      || ((normal_bind)->mbutton   != NO_BTN) \
      || ((normal_bind)->joykey    != NO_BTN) \
      || ((normal_bind)->joyaxis   != AXIS_NONE) \
      || ((autoconf_bind)->key     != RETROK_UNKNOWN) \
      || ((autoconf_bind)->joykey  != NO_BTN) \
      || ((autoconf_bind)->joyaxis != AXIS_NONE)) \
)

/* Human readable order of input binds */
const unsigned input_config_bind_order[24] = {
   RETRO_DEVICE_ID_JOYPAD_UP,
   RETRO_DEVICE_ID_JOYPAD_DOWN,
   RETRO_DEVICE_ID_JOYPAD_LEFT,
   RETRO_DEVICE_ID_JOYPAD_RIGHT,
   RETRO_DEVICE_ID_JOYPAD_B,
   RETRO_DEVICE_ID_JOYPAD_A,
   RETRO_DEVICE_ID_JOYPAD_Y,
   RETRO_DEVICE_ID_JOYPAD_X,
   RETRO_DEVICE_ID_JOYPAD_SELECT,
   RETRO_DEVICE_ID_JOYPAD_START,
   RETRO_DEVICE_ID_JOYPAD_L,
   RETRO_DEVICE_ID_JOYPAD_R,
   RETRO_DEVICE_ID_JOYPAD_L2,
   RETRO_DEVICE_ID_JOYPAD_R2,
   RETRO_DEVICE_ID_JOYPAD_L3,
   RETRO_DEVICE_ID_JOYPAD_R3,
   19, /* Left Analog Up */
   18, /* Left Analog Down */
   17, /* Left Analog Left */
   16, /* Left Analog Right */
   23, /* Right Analog Up */
   22, /* Right Analog Down */
   21, /* Right Analog Left */
   20, /* Right Analog Right */
};

/**************************************/
/* TODO/FIXME - turn these into static global variable */
retro_keybind_set input_config_binds[MAX_USERS];
retro_keybind_set input_autoconf_binds[MAX_USERS];
uint64_t lifecycle_state                                        = 0;

static void *input_null_init(const char *joypad_driver) { return (void*)-1; }
static void input_null_poll(void *data) { }
static int16_t input_null_input_state(
      void *data,
      const input_device_driver_t *joypad,
      const input_device_driver_t *sec_joypad,
      rarch_joypad_info_t *joypad_info,
      const retro_keybind_set *retro_keybinds,
      bool keyboard_mapping_blocked,
      unsigned port, unsigned device, unsigned index, unsigned id) { return 0; }
static void input_null_free(void *data) { }
static bool input_null_set_sensor_state(void *data, unsigned port,
         enum retro_sensor_action action, unsigned rate) { return false; }
static float input_null_get_sensor_input(void *data, unsigned port, unsigned id) { return 0.0; }
static uint64_t input_null_get_capabilities(void *data) { return 0; }
static void input_null_grab_mouse(void *data, bool state) { }
static bool input_null_grab_stdin(void *data) { return false; }
static void input_null_keypress_vibrate(void) { }

static input_driver_t input_null = {
   input_null_init,
   input_null_poll,
   input_null_input_state,
   input_null_free,
   input_null_set_sensor_state,
   input_null_get_sensor_input,
   input_null_get_capabilities,
   "null",
   input_null_grab_mouse,
   input_null_grab_stdin,
   input_null_keypress_vibrate
};

static input_device_driver_t null_joypad = {
   NULL, /* init */
   NULL, /* query_pad */
   NULL, /* destroy */
   NULL, /* button */
   NULL, /* state */
   NULL, /* get_buttons */
   NULL, /* axis */
   NULL, /* poll */
   NULL, /* rumble */
   NULL, /* rumble_gain */
   NULL, /* set_sensor_state */
   NULL, /* get_sensor_input */
   NULL, /* name */
   "null",
};


#ifdef HAVE_HID
static bool null_hid_joypad_query(void *data, unsigned pad) {
   return pad < MAX_USERS; }
static const char *null_hid_joypad_name(
      void *data, unsigned pad) { return NULL; }
static void null_hid_joypad_get_buttons(void *data,
      unsigned port, input_bits_t *state) { BIT256_CLEAR_ALL_PTR(state); }
static int16_t null_hid_joypad_button(
      void *data, unsigned port, uint16_t joykey) { return 0; }
static bool null_hid_joypad_rumble(void *data, unsigned pad,
      enum retro_rumble_effect effect, uint16_t strength) { return false; }
static int16_t null_hid_joypad_axis(
      void *data, unsigned port, uint32_t joyaxis) { return 0; }
static void *null_hid_init(void) { return (void*)-1; }
static void null_hid_free(const void *data) { }
static void null_hid_poll(void *data) { }
static int16_t null_hid_joypad_state(
      void *data,
      rarch_joypad_info_t *joypad_info,
      const void *binds_data,
      unsigned port) { return 0; }

static hid_driver_t null_hid = {
   null_hid_init,               /* init */
   null_hid_joypad_query,       /* joypad_query */
   null_hid_free,               /* free */
   null_hid_joypad_button,      /* button */
   null_hid_joypad_state,       /* state */
   null_hid_joypad_get_buttons, /* get_buttons */
   null_hid_joypad_axis,        /* axis */
   null_hid_poll,               /* poll */
   null_hid_joypad_rumble,      /* rumble */
   null_hid_joypad_name,        /* joypad_name */
   "null",
};
#endif

input_device_driver_t *joypad_drivers[] = {
#ifdef HAVE_XINPUT
   &xinput_joypad,
#endif
#ifdef GEKKO
   &gx_joypad,
#endif
#ifdef WIIU
   &wiiu_joypad,
#endif
#ifdef _XBOX1
   &xdk_joypad,
#endif
#if defined(ORBIS)
   &ps4_joypad,
#endif
#if defined(__PSL1GHT__) || defined(__PS3__)
   &ps3_joypad,
#endif
#if defined(PSP) || defined(VITA)
   &psp_joypad,
#endif
#if defined(PS2)
   &ps2_joypad,
#endif
#ifdef SWITCH
   &switch_joypad,
#endif
#ifdef HAVE_DINPUT
   &dinput_joypad,
#endif
#ifdef HAVE_UDEV
   &udev_joypad,
#endif
#if defined(__linux) && !defined(ANDROID)
   &linuxraw_joypad,
#endif
#ifdef HAVE_PARPORT
   &parport_joypad,
#endif
#ifdef ANDROID
   &android_joypad,
#endif
#if defined(HAVE_SDL) || defined(HAVE_SDL2)
   &sdl_joypad,
#endif
#if defined(DINGUX) && defined(HAVE_SDL_DINGUX)
   &sdl_dingux_joypad,
#endif
#ifdef __QNX__
   &qnx_joypad,
#endif
#ifdef HAVE_MFI
   &mfi_joypad,
#endif
#ifdef DJGPP
   &dos_joypad,
#endif
/* Selecting the HID gamepad driver disables the Wii U gamepad. So while
 * we want the HID code to be compiled & linked, we don't want the driver
 * to be selectable in the UI. */
#if defined(HAVE_HID) && !defined(WIIU)
   &hid_joypad,
#endif
#ifdef EMSCRIPTEN
   &rwebpad_joypad,
#endif
#ifdef HAVE_TEST_DRIVERS
   &test_joypad,
#endif
#ifdef HAVE_COCOATOUCH
   &virtual_joypad,
#endif
   &null_joypad,
   NULL,
};

input_driver_t *input_drivers[] = {
#ifdef ORBIS
   &input_ps4,
#endif
#if defined(__PSL1GHT__) || defined(__PS3__)
   &input_ps3,
#endif
#if defined(SN_TARGET_PSP2) || defined(PSP) || defined(VITA)
   &input_psp,
#endif
#if defined(PS2)
   &input_ps2,
#endif
#if defined(SWITCH)
   &input_switch,
#endif
#ifdef HAVE_X11
   &input_x,
#endif
#ifdef HAVE_WAYLAND
   &input_wayland,
#endif
#ifdef __WINRT__
   &input_uwp,
#endif
#ifdef XENON
   &input_xenon360,
#endif
#if defined(_WIN32) && !defined(_XBOX) && _WIN32_WINNT >= 0x0501 && !defined(__WINRT__)
#ifdef HAVE_WINRAWINPUT
   /* winraw only available since XP */
   &input_winraw,
#endif
#endif
#if defined(HAVE_XINPUT2) || defined(HAVE_XINPUT_XBOX1) || defined(__WINRT__)
   &input_xinput,
#endif
#ifdef HAVE_DINPUT
   &input_dinput,
#endif
#if (defined(HAVE_SDL) || defined(HAVE_SDL2)) && !(defined(HAVE_COCOA) || defined(HAVE_COCOA_METAL))
   &input_sdl,
#endif
#if defined(DINGUX) && defined(HAVE_SDL_DINGUX)
   &input_sdl_dingux,
#endif
#ifdef GEKKO
   &input_gx,
#endif
#ifdef WIIU
   &input_wiiu,
#endif
#ifdef ANDROID
   &input_android,
#endif
#ifdef HAVE_UDEV
   &input_udev,
#endif
#if defined(__linux__) && !defined(ANDROID)
   &input_linuxraw,
#endif
#if defined(HAVE_COCOA) || defined(HAVE_COCOATOUCH) || defined(HAVE_COCOA_METAL)
   &input_cocoa,
#endif
#ifdef __QNX__
   &input_qnx,
#endif
#ifdef EMSCRIPTEN
   &input_rwebinput,
#endif
#ifdef DJGPP
   &input_dos,
#endif
#ifdef HAVE_TEST_DRIVERS
   &input_test,
#endif
   &input_null,
   NULL,
};

#ifdef HAVE_HID
hid_driver_t *hid_drivers[] = {
#if defined(HAVE_BTSTACK)
   &btstack_hid,
#endif
#if defined(__APPLE__) && defined(HAVE_IOHIDMANAGER)
   &iohidmanager_hid,
#endif
#if defined(HAVE_LIBUSB) && defined(HAVE_THREADS)
   &libusb_hid,
#endif
#ifdef HW_RVL
   &wiiusb_hid,
#endif
#if defined(WIIU)
   &wiiu_hid,
#endif
   &null_hid,
   NULL,
};
#endif

static input_driver_state_t input_driver_st = {0}; /* double alignment */

/**************************************/

input_driver_state_t *input_state_get_ptr(void)
{
   return &input_driver_st;
}

/**
 * config_get_input_driver_options:
 *
 * Get an enumerated list of all input driver names, separated by '|'.
 *
 * Returns: string listing of all input driver names, separated by '|'.
 **/
const char* config_get_input_driver_options(void)
{
   return char_list_new_special(STRING_LIST_INPUT_DRIVERS, NULL);
}

/**
 * config_get_joypad_driver_options:
 *
 * Get an enumerated list of all joypad driver names, separated by '|'.
 *
 * Returns: string listing of all joypad driver names, separated by '|'.
 **/
const char* config_get_joypad_driver_options(void)
{
   return char_list_new_special(STRING_LIST_INPUT_JOYPAD_DRIVERS, NULL);
}

/**
 * Finds first suitable joypad driver and initializes. Used as a fallback by
 * input_joypad_init_driver when no matching driver is found.
 *
 * @param data  joypad state data pointer, which can be NULL and will be
 *              initialized by the new joypad driver, if one is found.
 *
 * @return joypad driver if found and initialized, otherwise NULL.
 **/
static const input_device_driver_t *input_joypad_init_first(void *data)
{
   int i;
   for (i = 0; joypad_drivers[i]; i++)
   {
      if (     joypad_drivers[i]
            && joypad_drivers[i]->init)
      {
         void *ptr = joypad_drivers[i]->init(data);
         if (ptr)
         {
            RARCH_LOG("[Input] Found joypad driver: \"%s\".\n",
                  joypad_drivers[i]->ident);
            return joypad_drivers[i];
         }
      }
   }

   return NULL;
}

bool input_driver_set_rumble(
         unsigned port, unsigned joy_idx,
         enum retro_rumble_effect effect, uint16_t strength)
{
   const input_device_driver_t  *primary_joypad;
   const input_device_driver_t      *sec_joypad;
   bool rumble_state   = false;

   if (joy_idx >= MAX_USERS)
      return false;

   primary_joypad = input_driver_st.primary_joypad;
   sec_joypad     = input_driver_st.secondary_joypad;

   if (primary_joypad && primary_joypad->set_rumble)
      rumble_state = primary_joypad->set_rumble(joy_idx, effect, strength);
   /* if sec_joypad exists, this set_rumble() return value will replace primary_joypad's return */
   if (sec_joypad     && sec_joypad->set_rumble)
      rumble_state = sec_joypad->set_rumble(joy_idx, effect, strength);

   return rumble_state;
}

bool input_driver_set_rumble_gain(
         unsigned gain,
         unsigned input_max_users)
{
   int i;

   if (  input_driver_st.primary_joypad
      && input_driver_st.primary_joypad->set_rumble_gain)
   {
      for (i = 0; i < (int)input_max_users; i++)
         input_driver_st.primary_joypad->set_rumble_gain(i, gain);
      return true;
   }
   return false;
}

bool input_driver_set_sensor(
         unsigned port, bool sensors_enable,
         enum retro_sensor_action action, unsigned rate)
{
   const input_driver_t *current_driver;

   if (!input_driver_st.current_data)
      return false;
   /* If sensors are disabled, inhibit any enable
    * actions (but always allow disable actions) */
   if (!sensors_enable &&
       (   (action == RETRO_SENSOR_ACCELEROMETER_ENABLE)
        || (action == RETRO_SENSOR_GYROSCOPE_ENABLE)
        || (action == RETRO_SENSOR_ILLUMINANCE_ENABLE)))
      return false;
   if (   (current_driver = input_driver_st.current_driver)
       &&  current_driver->set_sensor_state)
   {
      void *current_data = input_driver_st.current_data;
      return current_driver->set_sensor_state(current_data,
            port, action, rate);
   }
   else if (input_driver_st.primary_joypad && input_driver_st.primary_joypad->set_sensor_state)
      return input_driver_st.primary_joypad->set_sensor_state(NULL,
            port, action, rate);
   return false;
}

/**************************************/

float input_driver_get_sensor(
         unsigned port, bool sensors_enable, unsigned id)
{
   if (input_driver_st.current_data)
   {
      const input_driver_t *current_driver = input_driver_st.current_driver;
      if (sensors_enable && current_driver->get_sensor_input)
      {
         void *current_data = input_driver_st.current_data;
         return current_driver->get_sensor_input(current_data, port, id);
      }
      else if (sensors_enable && input_driver_st.primary_joypad &&
               input_driver_st.primary_joypad->get_sensor_input)
         return input_driver_st.primary_joypad->get_sensor_input(NULL,
               port, id);
   }

   return 0.0f;
}

const input_device_driver_t *input_joypad_init_driver(
      const char *ident, void *data)
{
   if (ident && *ident)
   {
      int i;
      for (i = 0; joypad_drivers[i]; i++)
      {
         if (string_is_equal(ident, joypad_drivers[i]->ident)
               && joypad_drivers[i]->init)
         {
            void *ptr = joypad_drivers[i]->init(data);
            if (ptr)
            {
               RARCH_LOG("[Input] Found joypad driver: \"%s\".\n",
                     joypad_drivers[i]->ident);
               return joypad_drivers[i];
            }
         }
      }
   }

   return input_joypad_init_first(data); /* fall back to first available driver */
}

static bool input_driver_button_combo_hold(
      unsigned mode,
      unsigned button,
      retro_time_t current_time,
      input_bits_t *p_input)
{
   rarch_timer_t *timer           = &input_driver_st.combo_timers[mode];
   runloop_state_t *runloop_st    = runloop_state_get_ptr();
   static bool enable_hotkey_dupe = false;

   /* Flag current press when button and 'enable_hotkey' are the same,
    * because 'input_hotkey_block_delay' clears the combo button bit. */
   if (     BIT256_GET_PTR(p_input, RARCH_ENABLE_HOTKEY)
         && BIT256_GET_PTR(p_input, button))
      enable_hotkey_dupe = true;

   /* Ignore press if 'enable_hotkey' is not the combo button. */
   if (      BIT256_GET_PTR(p_input, RARCH_ENABLE_HOTKEY)
         && !BIT256_GET_PTR(p_input, button)
         && !enable_hotkey_dupe)
      return false;

   /* Allow using the same button for 'enable_hotkey' if set,
    * and stop timer if holding fast-forward or slow-motion */
   if (     !BIT256_GET_PTR(p_input, button)
         && !( BIT256_GET_PTR(p_input, RARCH_ENABLE_HOTKEY)
            && !(input_driver_st.flags & INP_FLAG_BLOCK_HOTKEY)
            && !(runloop_st->flags & RUNLOOP_FLAG_SLOWMOTION)
            && !(runloop_st->flags & RUNLOOP_FLAG_FASTMOTION))
      )
   {
      /* Timer only runs while start is held down */
      enable_hotkey_dupe = false;
      timer->timer_begin = false;
      timer->timer_end   = true;
      timer->timeout_end = 0;
      return false;
   }

   /* User started holding down the start button, start the timer */
   if (!timer->timer_begin)
   {
      timer->timeout_us     = HOLD_BTN_DELAY_SEC * 1000000;
      timer->timeout_end    = current_time + timer->timeout_us;
      timer->timer_begin    = true;
      timer->timer_end      = false;
   }

   timer->current           = current_time;
   timer->timeout_us        = (timer->timeout_end - timer->current);

   if (!timer->timer_end && (timer->timeout_us <= 0))
   {
      /* Start has been held down long enough,
       * stop timer and enter menu */
      enable_hotkey_dupe = false;
      timer->timer_begin = false;
      timer->timer_end   = true;
      timer->timeout_end = 0;
      return true;
   }

   return false;
}

bool input_driver_pointer_is_offscreen(int16_t x, int16_t y)
{
   const int edge_detect = 32700;
   if (   (x >= -edge_detect)
       && (y >= -edge_detect)
       && (x <=  edge_detect)
       && (y <=  edge_detect))
      return false;
   return true;
}

unsigned input_driver_lightgun_id_convert(unsigned id)
{
   switch (id)
   {
      case RETRO_DEVICE_ID_LIGHTGUN_DPAD_RIGHT:
         return RARCH_LIGHTGUN_DPAD_RIGHT;
      case RETRO_DEVICE_ID_LIGHTGUN_DPAD_LEFT:
         return RARCH_LIGHTGUN_DPAD_LEFT;
      case RETRO_DEVICE_ID_LIGHTGUN_DPAD_UP:
         return RARCH_LIGHTGUN_DPAD_UP;
      case RETRO_DEVICE_ID_LIGHTGUN_DPAD_DOWN:
         return RARCH_LIGHTGUN_DPAD_DOWN;
      case RETRO_DEVICE_ID_LIGHTGUN_SELECT:
         return RARCH_LIGHTGUN_SELECT;
      case RETRO_DEVICE_ID_LIGHTGUN_PAUSE:
         return RARCH_LIGHTGUN_START;
      case RETRO_DEVICE_ID_LIGHTGUN_RELOAD:
         return RARCH_LIGHTGUN_RELOAD;
      case RETRO_DEVICE_ID_LIGHTGUN_TRIGGER:
         return RARCH_LIGHTGUN_TRIGGER;
      case RETRO_DEVICE_ID_LIGHTGUN_AUX_A:
         return RARCH_LIGHTGUN_AUX_A;
      case RETRO_DEVICE_ID_LIGHTGUN_AUX_B:
         return RARCH_LIGHTGUN_AUX_B;
      case RETRO_DEVICE_ID_LIGHTGUN_AUX_C:
         return RARCH_LIGHTGUN_AUX_C;
      case RETRO_DEVICE_ID_LIGHTGUN_START:
         return RARCH_LIGHTGUN_START;
      default:
         break;
   }

   return 0;
}


bool input_driver_button_combo(
      unsigned mode,
      retro_time_t current_time,
      input_bits_t *p_input)
{
   switch (mode)
   {
      case INPUT_COMBO_DOWN_Y_L_R:
         if (   BIT256_GET_PTR(p_input, RETRO_DEVICE_ID_JOYPAD_DOWN)
             && BIT256_GET_PTR(p_input, RETRO_DEVICE_ID_JOYPAD_Y)
             && BIT256_GET_PTR(p_input, RETRO_DEVICE_ID_JOYPAD_L)
             && BIT256_GET_PTR(p_input, RETRO_DEVICE_ID_JOYPAD_R))
            return true;
         break;
      case INPUT_COMBO_L3_R3:
         if (   BIT256_GET_PTR(p_input, RETRO_DEVICE_ID_JOYPAD_L3)
             && BIT256_GET_PTR(p_input, RETRO_DEVICE_ID_JOYPAD_R3))
            return true;
         break;
      case INPUT_COMBO_L1_R1_START_SELECT:
         if (   BIT256_GET_PTR(p_input, RETRO_DEVICE_ID_JOYPAD_L)
             && BIT256_GET_PTR(p_input, RETRO_DEVICE_ID_JOYPAD_R)
             && BIT256_GET_PTR(p_input, RETRO_DEVICE_ID_JOYPAD_START)
             && BIT256_GET_PTR(p_input, RETRO_DEVICE_ID_JOYPAD_SELECT))
            return true;
         break;
      case INPUT_COMBO_START_SELECT:
         if (   BIT256_GET_PTR(p_input, RETRO_DEVICE_ID_JOYPAD_START)
             && BIT256_GET_PTR(p_input, RETRO_DEVICE_ID_JOYPAD_SELECT))
            return true;
         break;
      case INPUT_COMBO_L3_R:
         if (   BIT256_GET_PTR(p_input, RETRO_DEVICE_ID_JOYPAD_L3)
             && BIT256_GET_PTR(p_input, RETRO_DEVICE_ID_JOYPAD_R))
            return true;
         break;
      case INPUT_COMBO_L_R:
         if (   BIT256_GET_PTR(p_input, RETRO_DEVICE_ID_JOYPAD_L)
             && BIT256_GET_PTR(p_input, RETRO_DEVICE_ID_JOYPAD_R))
            return true;
         break;
      case INPUT_COMBO_DOWN_SELECT:
         if (   BIT256_GET_PTR(p_input, RETRO_DEVICE_ID_JOYPAD_DOWN)
             && BIT256_GET_PTR(p_input, RETRO_DEVICE_ID_JOYPAD_SELECT))
            return true;
         break;
      case INPUT_COMBO_L2_R2:
         if (   BIT256_GET_PTR(p_input, RETRO_DEVICE_ID_JOYPAD_L2)
             && BIT256_GET_PTR(p_input, RETRO_DEVICE_ID_JOYPAD_R2))
            return true;
         break;
      case INPUT_COMBO_HOLD_START:
         return input_driver_button_combo_hold(
               INPUT_COMBO_HOLD_START, RETRO_DEVICE_ID_JOYPAD_START, current_time, p_input);
      case INPUT_COMBO_HOLD_SELECT:
         return input_driver_button_combo_hold(
               INPUT_COMBO_HOLD_SELECT, RETRO_DEVICE_ID_JOYPAD_SELECT, current_time, p_input);
      default:
      case INPUT_COMBO_NONE:
         break;
   }

   return false;
}

static int32_t input_state_wrap(
      input_driver_t *current_input,
      void *data,
      const input_device_driver_t *joypad,
      const input_device_driver_t *sec_joypad,
      rarch_joypad_info_t *joypad_info,
      const retro_keybind_set *binds,
      bool keyboard_mapping_blocked,
      unsigned _port,
      unsigned device,
      unsigned idx,
      unsigned id)
{
   int32_t ret = 0;

   if (!binds)
      return 0;

   /* Do a bitwise OR to combine input states together */

   if (device == RETRO_DEVICE_JOYPAD)
   {
      if (id == RETRO_DEVICE_ID_JOYPAD_MASK)
      {
         if (joypad)
            ret |= joypad->state(joypad_info, binds[_port], _port);
         if (sec_joypad)
            ret |= sec_joypad->state(joypad_info, binds[_port], _port);
      }
      else
      {
         /* Do a bitwise OR to combine both input
          * states together */
         if (binds[_port][id].valid)
         {
            /* Auto-binds are per joypad, not per user. */
            const uint64_t bind_joykey     = binds[_port][id].joykey;
            const uint64_t bind_joyaxis    = binds[_port][id].joyaxis;
            const uint64_t autobind_joykey = joypad_info->auto_binds[id].joykey;
            const uint64_t autobind_joyaxis= joypad_info->auto_binds[id].joyaxis;
            uint16_t port                  = joypad_info->joy_idx;
            float axis_threshold           = joypad_info->axis_threshold;
            const uint64_t joykey          = (bind_joykey != NO_BTN)
               ? bind_joykey  : autobind_joykey;
            const uint64_t joyaxis         = (bind_joyaxis != AXIS_NONE)
               ? bind_joyaxis : autobind_joyaxis;

            if (joypad)
            {
               if ((uint16_t)joykey != NO_BTN && joypad->button(
                        port, (uint16_t)joykey))
                  return 1;
               if (joyaxis != AXIS_NONE &&
                     ((float)abs(joypad->axis(port, (uint32_t)joyaxis))
                      / 0x8000) > axis_threshold)
                  return 1;
            }
            if (sec_joypad)
            {
               if ((uint16_t)joykey != NO_BTN && sec_joypad->button(
                        port, (uint16_t)joykey))
                  return 1;
               if (joyaxis != AXIS_NONE &&
                     ((float)abs(sec_joypad->axis(port, (uint32_t)joyaxis))
                      / 0x8000) > axis_threshold)
                  return 1;
            }
         }
      }
   }
   else if (device == RETRO_DEVICE_KEYBOARD)
   {
      /* Always ignore null key. */
      if (id == RETROK_UNKNOWN)
         return ret;
   }

   if (current_input && current_input->input_state)
      ret |= current_input->input_state(
            data,
            joypad,
            sec_joypad,
            joypad_info,
            binds,
            keyboard_mapping_blocked,
            _port,
            device,
            idx,
            id);

   return ret;
}

static int16_t input_joypad_axis(
      float input_analog_deadzone,
      float input_analog_sensitivity,
      const input_device_driver_t *drv,
      unsigned port, uint32_t joyaxis, float normal_mag)
{
   int16_t val = (joyaxis != AXIS_NONE) ? drv->axis(port, joyaxis) : 0;

   if (input_analog_deadzone)
   {
      /* if analog value is below the deadzone, ignore it
       * normal magnitude is calculated radially for analog sticks
       * and linearly for analog buttons */
      if (normal_mag <= input_analog_deadzone)
         return 0;

      /* due to the way normal_mag is calculated differently for buttons and
       * sticks, this results in either a radial scaled deadzone for sticks
       * or linear scaled deadzone for analog buttons */
      val = val * MAX(1.0f,(1.0f / normal_mag)) * MIN(1.0f,
            ((normal_mag - input_analog_deadzone)
          / (1.0f - input_analog_deadzone)));
   }

   if (input_analog_sensitivity != 1.0f)
   {
      float normalized = (1.0f / 0x7fff) * val;
      int      new_val = 0x7fff * normalized * input_analog_sensitivity;
      if (new_val > 0x7fff)
         return 0x7fff;
      else if (new_val < -0x7fff)
         return -0x7fff;
      return new_val;
   }

   return val;
}

/**
 * input_joypad_analog_button:
 * @drv                     : Input device driver handle.
 * @port                    : User number.
 * @idx                     : Analog key index.
 *                            E.g.:
 *                            - RETRO_DEVICE_INDEX_ANALOG_LEFT
 *                            - RETRO_DEVICE_INDEX_ANALOG_RIGHT
 * @ident                   : Analog key identifier.
 *                            E.g.:
 *                            - RETRO_DEVICE_ID_ANALOG_X
 *                            - RETRO_DEVICE_ID_ANALOG_Y
 * @binds                   : Binds of user.
 *
 * Gets analog value of analog key identifiers @idx and @ident
 * from user with number @port with provided keybinds (@binds).
 *
 * Returns: analog value on success, otherwise 0.
 **/
static int16_t input_joypad_analog_button(
      float input_analog_deadzone,
      float input_analog_sensitivity,
      const input_device_driver_t *drv,
      rarch_joypad_info_t *joypad_info,
      unsigned ident,
      const struct retro_keybind *bind)
{
   int16_t res      = 0;
   float normal_mag = 0.0f;
   uint32_t axis    = (bind->joyaxis == AXIS_NONE)
      ? joypad_info->auto_binds[ident].joyaxis
      : bind->joyaxis;

   /* Analog button. */
   if (input_analog_deadzone)
   {
      int16_t mult = 0;
      if (axis != AXIS_NONE)
         if ((mult = drv->axis(
                     joypad_info->joy_idx, axis)) != 0)
            normal_mag   = fabs((1.0f / 0x7fff) * mult);
   }

   /* If the result is zero, it's got a digital button
    * attached to it instead */
   if ((res = abs(input_joypad_axis(
            input_analog_deadzone,
            input_analog_sensitivity,
            drv,
            joypad_info->joy_idx, axis, normal_mag))) == 0)
   {
      uint16_t key = (bind->joykey == NO_BTN)
         ? joypad_info->auto_binds[ident].joykey
         : bind->joykey;

      if (drv->button(joypad_info->joy_idx, key))
         return 0x7fff;
      return 0;
   }

   return res;
}

static int16_t input_joypad_analog_axis(
      unsigned input_analog_dpad_mode,
      float input_analog_deadzone,
      float input_analog_sensitivity,
      const input_device_driver_t *drv,
      rarch_joypad_info_t *joypad_info,
      unsigned idx,
      unsigned ident,
      const struct retro_keybind *binds)
{
   int16_t res                              = 0;
   /* Analog sticks. Either RETRO_DEVICE_INDEX_ANALOG_LEFT
    * or RETRO_DEVICE_INDEX_ANALOG_RIGHT */
   unsigned ident_minus                     = 0;
   unsigned ident_plus                      = 0;
   unsigned ident_x_minus                   = 0;
   unsigned ident_x_plus                    = 0;
   unsigned ident_y_minus                   = 0;
   unsigned ident_y_plus                    = 0;
   const struct retro_keybind *bind_minus   = NULL;
   const struct retro_keybind *bind_plus    = NULL;
   const struct retro_keybind *bind_x_minus = NULL;
   const struct retro_keybind *bind_x_plus  = NULL;
   const struct retro_keybind *bind_y_minus = NULL;
   const struct retro_keybind *bind_y_plus  = NULL;

   /* Skip analog input with analog_dpad_mode */
   switch (input_analog_dpad_mode)
   {
      case ANALOG_DPAD_LSTICK:
         if (idx == RETRO_DEVICE_INDEX_ANALOG_LEFT)
            return 0;
         break;
      case ANALOG_DPAD_RSTICK:
         if (idx == RETRO_DEVICE_INDEX_ANALOG_RIGHT)
            return 0;
         break;
      default:
         break;
   }

   input_conv_analog_id_to_bind_id(idx, ident, ident_minus, ident_plus);

   bind_minus   = &binds[ident_minus];
   bind_plus    = &binds[ident_plus];

   if (!bind_minus->valid || !bind_plus->valid)
      return 0;

   input_conv_analog_id_to_bind_id(idx,
         RETRO_DEVICE_ID_ANALOG_X, ident_x_minus, ident_x_plus);

   bind_x_minus = &binds[ident_x_minus];
   bind_x_plus  = &binds[ident_x_plus];

   if (!bind_x_minus->valid || !bind_x_plus->valid)
      return 0;

   input_conv_analog_id_to_bind_id(idx,
         RETRO_DEVICE_ID_ANALOG_Y, ident_y_minus, ident_y_plus);

   bind_y_minus = &binds[ident_y_minus];
   bind_y_plus  = &binds[ident_y_plus];

   if (!bind_y_minus->valid || !bind_y_plus->valid)
      return 0;

   /* Keyboard bind priority */
   if (     bind_plus->key  != RETROK_UNKNOWN
         || bind_minus->key != RETROK_UNKNOWN)
   {
      input_driver_state_t *input_st = &input_driver_st;

      if (bind_plus->key && input_state_wrap(
            input_st->current_driver,
            input_st->current_data,
            input_st->primary_joypad,
            NULL,
            joypad_info,
            (*input_st->libretro_input_binds),
            (input_st->flags & INP_FLAG_KB_MAPPING_BLOCKED) ? true : false,
            0, RETRO_DEVICE_KEYBOARD, 0,
            bind_plus->key))
         res  = 0x7fff;
      if (bind_minus->key && input_state_wrap(
            input_st->current_driver,
            input_st->current_data,
            input_st->primary_joypad,
            NULL,
            joypad_info,
            (*input_st->libretro_input_binds),
            (input_st->flags & INP_FLAG_KB_MAPPING_BLOCKED) ? true : false,
            0, RETRO_DEVICE_KEYBOARD, 0,
            bind_minus->key))
         res += -0x7fff;

      if (res)
         return res;
   }

   {
      uint32_t axis_minus            = (bind_minus->joyaxis   == AXIS_NONE)
         ? joypad_info->auto_binds[ident_minus].joyaxis
         : bind_minus->joyaxis;
      uint32_t axis_plus             = (bind_plus->joyaxis    == AXIS_NONE)
         ? joypad_info->auto_binds[ident_plus].joyaxis
         : bind_plus->joyaxis;
      float normal_mag               = 0.0f;

      /* normalized magnitude of stick actuation, needed for scaled
       * radial deadzone */
      if (input_analog_deadzone)
      {
         float x                  = 0.0f;
         float y                  = 0.0f;
         uint32_t x_axis_minus    = (bind_x_minus->joyaxis == AXIS_NONE)
            ? joypad_info->auto_binds[ident_x_minus].joyaxis
            : bind_x_minus->joyaxis;
         uint32_t x_axis_plus     = (bind_x_plus->joyaxis  == AXIS_NONE)
            ? joypad_info->auto_binds[ident_x_plus].joyaxis
            : bind_x_plus->joyaxis;
         uint32_t y_axis_minus    = (bind_y_minus->joyaxis == AXIS_NONE)
            ? joypad_info->auto_binds[ident_y_minus].joyaxis
            : bind_y_minus->joyaxis;
         uint32_t y_axis_plus     = (bind_y_plus->joyaxis  == AXIS_NONE)
            ? joypad_info->auto_binds[ident_y_plus].joyaxis
            : bind_y_plus->joyaxis;
         /* normalized magnitude for radial scaled analog deadzone */
         if (x_axis_plus != AXIS_NONE && drv->axis)
            x                     = drv->axis(
                  joypad_info->joy_idx, x_axis_plus);
         if (x_axis_minus != AXIS_NONE && drv->axis)
            x                    += drv->axis(joypad_info->joy_idx,
                  x_axis_minus);
         if (y_axis_plus != AXIS_NONE && drv->axis)
            y                     = drv->axis(
                  joypad_info->joy_idx, y_axis_plus);
         if (y_axis_minus != AXIS_NONE && drv->axis)
            y                    += drv->axis(
                  joypad_info->joy_idx, y_axis_minus);
         normal_mag               = (1.0f / 0x7fff) * sqrt(x * x + y * y);
      }

      res           = abs(
            input_joypad_axis(
               input_analog_deadzone,
               input_analog_sensitivity,
               drv, joypad_info->joy_idx,
               axis_plus, normal_mag));
      res          -= abs(
            input_joypad_axis(
               input_analog_deadzone,
               input_analog_sensitivity,
               drv, joypad_info->joy_idx,
               axis_minus, normal_mag));
   }

   if (res == 0)
   {
      uint16_t key_minus    = (bind_minus->joykey == NO_BTN)
         ? joypad_info->auto_binds[ident_minus].joykey
         : bind_minus->joykey;
      uint16_t key_plus     = (bind_plus->joykey  == NO_BTN)
         ? joypad_info->auto_binds[ident_plus].joykey
         : bind_plus->joykey;
      if (drv->button && drv->button(joypad_info->joy_idx, key_plus))
         res  = 0x7fff;
      if (drv->button && drv->button(joypad_info->joy_idx, key_minus))
         res += -0x7fff;
   }

   return res;
}

void input_keyboard_line_append(
      struct input_keyboard_line *keyboard_line,
      const char *word, size_t len)
{
   size_t i;
   char *newbuf = (char*)realloc(keyboard_line->buffer,
         keyboard_line->size + len * 2);

   if (!newbuf)
      return;

   memmove(
         newbuf + keyboard_line->ptr + len,
         newbuf + keyboard_line->ptr,
         keyboard_line->size - keyboard_line->ptr + len);

   for (i = 0; i < len; i++)
   {
      newbuf[keyboard_line->ptr]= word[i];
      keyboard_line->ptr++;
      keyboard_line->size++;
   }

   newbuf[keyboard_line->size]  = '\0';

   keyboard_line->buffer        = newbuf;
}

void input_keyboard_line_clear(input_driver_state_t *input_st)
{
   if (input_st->keyboard_line.buffer)
      free(input_st->keyboard_line.buffer);
   input_st->keyboard_line.buffer       = NULL;
   input_st->keyboard_line.ptr          = 0;
   input_st->keyboard_line.size         = 0;
}

void input_keyboard_line_free(input_driver_state_t *input_st)
{
   if (input_st->keyboard_line.buffer)
      free(input_st->keyboard_line.buffer);
   input_st->keyboard_line.buffer       = NULL;
   input_st->keyboard_line.ptr          = 0;
   input_st->keyboard_line.size         = 0;
   input_st->keyboard_line.cb           = NULL;
   input_st->keyboard_line.userdata     = NULL;
   input_st->keyboard_line.enabled      = false;
}

const char **input_keyboard_start_line(
      void *userdata,
      struct input_keyboard_line *keyboard_line,
      input_keyboard_line_complete_t cb)
{
   keyboard_line->buffer    = NULL;
   keyboard_line->ptr       = 0;
   keyboard_line->size      = 0;
   keyboard_line->cb        = cb;
   keyboard_line->userdata  = userdata;
   keyboard_line->enabled   = true;

   return (const char**)&keyboard_line->buffer;
}

#ifdef HAVE_OVERLAY
static int16_t input_overlay_device_mouse_state(
      input_overlay_t *ol, unsigned id)
{
   int16_t res;
   input_overlay_pointer_state_t *ptr_st = &ol->pointer_state;

   switch(id)
   {
      case RETRO_DEVICE_ID_MOUSE_X:
         ptr_st->device_mask |= (1 << RETRO_DEVICE_MOUSE);
         res =   (ptr_st->mouse.scale_x)
               * (ptr_st->screen_x - ptr_st->mouse.prev_screen_x);
         return res;
      case RETRO_DEVICE_ID_MOUSE_Y:
         res =   (ptr_st->mouse.scale_y)
               * (ptr_st->screen_y - ptr_st->mouse.prev_screen_y);
         return res;
      case RETRO_DEVICE_ID_MOUSE_LEFT:
         return    (ptr_st->mouse.click & 0x1)
                || (ptr_st->mouse.hold  & 0x1);
      case RETRO_DEVICE_ID_MOUSE_RIGHT:
         return    (ptr_st->mouse.click & 0x2)
                || (ptr_st->mouse.hold  & 0x2);
      case RETRO_DEVICE_ID_MOUSE_MIDDLE:
         return    (ptr_st->mouse.click & 0x4)
                || (ptr_st->mouse.hold  & 0x4);
      default:
         break;
   }

   return 0;
}

static int16_t input_overlay_lightgun_state(
      bool input_overlay_lightgun_allow_offscreen,
      input_overlay_t *ol, unsigned id)
{
   unsigned rarch_id;
   input_overlay_pointer_state_t *ptr_st = &ol->pointer_state;

   switch(id)
   {
      /* Pointer positions have been clamped earlier in input drivers,   *
       * so if we want to pass true offscreen value, it must be detected */
      case RETRO_DEVICE_ID_LIGHTGUN_SCREEN_X:
         ptr_st->device_mask |= (1 << RETRO_DEVICE_LIGHTGUN);
         if (   ( ptr_st->ptr[0].x > -0x7fff && ptr_st->ptr[0].x != 0x7fff)
               || !input_overlay_lightgun_allow_offscreen)
            return ptr_st->ptr[0].x;
         return -0x8000;
      case RETRO_DEVICE_ID_LIGHTGUN_SCREEN_Y:
         if (   ( ptr_st->ptr[0].y > -0x7fff && ptr_st->ptr[0].y != 0x7fff)
               || !input_overlay_lightgun_allow_offscreen)
            return ptr_st->ptr[0].y;
         return -0x8000;
      case RETRO_DEVICE_ID_LIGHTGUN_IS_OFFSCREEN:
         ptr_st->device_mask |= (1 << RETRO_DEVICE_LIGHTGUN);
         return ( input_overlay_lightgun_allow_offscreen
               && input_driver_pointer_is_offscreen(ptr_st->ptr[0].x, ptr_st->ptr[0].y));
      case RETRO_DEVICE_ID_LIGHTGUN_AUX_A:
      case RETRO_DEVICE_ID_LIGHTGUN_AUX_B:
      case RETRO_DEVICE_ID_LIGHTGUN_AUX_C:
      case RETRO_DEVICE_ID_LIGHTGUN_TRIGGER:
      case RETRO_DEVICE_ID_LIGHTGUN_START:
      case RETRO_DEVICE_ID_LIGHTGUN_PAUSE:
      case RETRO_DEVICE_ID_LIGHTGUN_SELECT:
      case RETRO_DEVICE_ID_LIGHTGUN_RELOAD:
      case RETRO_DEVICE_ID_LIGHTGUN_DPAD_UP:
      case RETRO_DEVICE_ID_LIGHTGUN_DPAD_DOWN:
      case RETRO_DEVICE_ID_LIGHTGUN_DPAD_LEFT:
      case RETRO_DEVICE_ID_LIGHTGUN_DPAD_RIGHT:
         rarch_id = input_driver_lightgun_id_convert(id);
         break;
      default:
         rarch_id = RARCH_BIND_LIST_END;
         break;
   }

   return (   rarch_id < RARCH_BIND_LIST_END
           && (   ptr_st->lightgun.multitouch_id == rarch_id
               || BIT256_GET(ol->overlay_state.buttons, rarch_id)));
}

static int16_t input_overlay_pointer_state(input_overlay_t *ol,
      input_overlay_pointer_state_t *ptr_st,
      unsigned idx, unsigned id)
{
   ptr_st->device_mask |= (1 << RETRO_DEVICE_POINTER);

   switch (id)
   {
      case RETRO_DEVICE_ID_POINTER_X:
         return ptr_st->ptr[idx].x;
      case RETRO_DEVICE_ID_POINTER_Y:
         return ptr_st->ptr[idx].y;
      case RETRO_DEVICE_ID_POINTER_PRESSED:
         return (idx < ptr_st->count)
               && ptr_st->ptr[idx].x != -0x8000
               && ptr_st->ptr[idx].y != -0x8000;
      case RETRO_DEVICE_ID_POINTER_COUNT:
         return ptr_st->count;
      case RETRO_DEVICE_ID_POINTER_IS_OFFSCREEN:
         return input_driver_pointer_is_offscreen(ptr_st->ptr[idx].x, ptr_st->ptr[idx].y);
   }

   return 0;
}

static int16_t input_overlay_pointing_device_state(
      int input_overlay_lightgun_port,
      bool input_overlay_lightgun_allow_offscreen,
      input_overlay_t *ol, unsigned port, unsigned device,
      unsigned idx, unsigned id)
{
   switch (device)
   {
      case RETRO_DEVICE_MOUSE:
         return input_overlay_device_mouse_state(ol, id);
      case RETRO_DEVICE_LIGHTGUN:
         if (     input_overlay_lightgun_port == -1
               || input_overlay_lightgun_port == (int)port)
            return input_overlay_lightgun_state(
                  input_overlay_lightgun_allow_offscreen,
                  ol, id);
         break;
      case RETRO_DEVICE_POINTER:
         return input_overlay_pointer_state(ol,
               (input_overlay_pointer_state_t*)&ol->pointer_state,
               idx, id);
      default:
         break;
   }

   return 0;
}
#endif

#if defined(HAVE_NETWORKING) && defined(HAVE_NETWORKGAMEPAD)
static bool input_remote_init_network(input_remote_t *handle,
      uint16_t port, unsigned user)
{
   int fd;
   struct addrinfo *res  = NULL;
   port                  = port + user;

   if (!network_init())
      return false;

   RARCH_LOG("[Network] Bringing up remote interface on port %hu.\n",
         (unsigned short)port);

   if ((fd = socket_init((void**)&res, port, NULL, SOCKET_TYPE_DATAGRAM, AF_INET)) < 0)
      goto error;

   handle->net_fd[user] = fd;

   if (!socket_nonblock(handle->net_fd[user]))
      goto error;

   if (!socket_bind(handle->net_fd[user], res))
   {
      RARCH_ERR("Failed to bind socket.\n");
      goto error;
   }

   freeaddrinfo_retro(res);
   return true;

error:
   if (res)
      freeaddrinfo_retro(res);
   return false;
}

void input_remote_free(input_remote_t *handle, unsigned max_users)
{
   int user;
   for (user = 0; user < (int)max_users; user ++)
      socket_close(handle->net_fd[user]);
   free(handle);
}

static input_remote_t *input_remote_new(
      settings_t *settings,
      uint16_t port, unsigned max_users)
{
   int user;
   input_remote_t      *handle = (input_remote_t*)
      calloc(1, sizeof(*handle));

   if (!handle)
      return NULL;

   for (user = 0; user < (int)max_users; user++)
   {
      handle->net_fd[user] = -1;
      if (settings->bools.network_remote_enable_user[user])
         if (!input_remote_init_network(handle, port, user))
         {
            input_remote_free(handle, max_users);
            return NULL;
         }
   }

   return handle;
}

static void input_remote_parse_packet(
      input_remote_state_t *input_state,
      struct remote_message *msg, unsigned user)
{
   /* Parse message */
   switch (msg->device)
   {
      case RETRO_DEVICE_JOYPAD:
         if (msg->id < 16)
         {
            input_state->buttons[user] &= ~(1 << msg->id);
            if (msg->state)
               input_state->buttons[user] |= 1 << msg->id;
         }
         break;
      case RETRO_DEVICE_ANALOG:
         if (msg->id<2 && msg->index<2)
            input_state->analog[msg->index * 2 + msg->id][user] = msg->state;
         break;
   }
}

input_remote_t *input_driver_init_remote(
      settings_t *settings,
      unsigned num_active_users)
{
   return input_remote_new(settings,
         settings->uints.network_remote_base_port,
         num_active_users);
}
#endif

static int16_t input_state_device(
      input_driver_state_t *input_st,
      settings_t *settings,
      input_mapper_t *handle,
      unsigned input_analog_dpad_mode,
      int32_t ret,
      unsigned port, unsigned device,
      unsigned idx, unsigned id,
      bool button_mask)
{
   int16_t res  = 0;

   switch (device)
   {
      case RETRO_DEVICE_JOYPAD:

         if (id < RARCH_FIRST_META_KEY)
         {
#ifdef HAVE_NETWORKGAMEPAD
            /* Don't process binds if input is coming from Remote RetroPad */
            if (     input_st->remote
                  && INPUT_REMOTE_KEY_PRESSED(input_st, id, port))
               res |= 1;
            else
#endif
            {
               bool bind_valid       = input_st->libretro_input_binds[port]
                  && (*input_st->libretro_input_binds[port])[id].valid;
               unsigned remap_button = settings->uints.input_remap_ids[port][id];

               /* TODO/FIXME: What on earth is this code doing...? */
               if (!(bind_valid && (id != remap_button)))
               {
                  if (button_mask)
                  {
                     if (ret & (1 << id))
                        res |= (1 << id);
                  }
                  else
                     res = ret;
               }

               if (BIT256_GET(handle->buttons[port], id))
                  res = 1;

#ifdef HAVE_OVERLAY
               /* Check if overlay is active and button
                * corresponding to 'id' has been pressed */
               if (  (port == 0)
                   && input_st->overlay_ptr
                   && (input_st->overlay_ptr->flags & INPUT_OVERLAY_ALIVE)
                   && BIT256_GET(input_st->overlay_ptr->overlay_state.buttons, id))
               {
                  bool menu_driver_alive        = false;
                  bool input_remap_binds_enable = settings->bools.input_remap_binds_enable;

                  /* This button has already been processed
                   * inside input_driver_poll() if all the
                   * following are true:
                   * > Menu driver is not running
                   * > Input remaps are enabled
                   * > 'id' is not equal to remapped button index
                   * If these conditions are met, input here
                   * is ignored */
                  if (   (menu_driver_alive
                      || !input_remap_binds_enable)
                      || (id == remap_button))
                     res |= 1;
               }
#endif // HAVE_OVERLAY
            }

            if (id <= RETRO_DEVICE_ID_JOYPAD_R3)
            {
               /* Apply turbo button if activated. */
               uint8_t turbo_period     = settings->uints.input_turbo_period;
               uint8_t turbo_duty_cycle = settings->uints.input_turbo_duty_cycle;
               uint8_t turbo_mode       = settings->uints.input_turbo_mode;

               /* Don't allow classic mode turbo for D-pad unless explicitly allowed. */
               if (     turbo_mode <= INPUT_TURBO_MODE_CLASSIC_TOGGLE
                     && !settings->bools.input_turbo_allow_dpad
                     && id >= RETRO_DEVICE_ID_JOYPAD_UP
                     && id <= RETRO_DEVICE_ID_JOYPAD_RIGHT)
                  break;

               if (turbo_duty_cycle == 0)
                  turbo_duty_cycle = turbo_period / 2;

               /* Clear underlying button to prevent duplicates. */
               if (     input_st->turbo_btns.frame_enable[port]
                     && (int)id == settings->ints.input_turbo_bind)
                  res = 0;

               if (turbo_mode > INPUT_TURBO_MODE_CLASSIC_TOGGLE)
               {
                  unsigned turbo_button = settings->uints.input_turbo_button;
                  unsigned remap_button = settings->uints.input_remap_ids[port][turbo_button];

                  /* Single button modes only care about the defined button. */
                  if (id != remap_button)
                     break;

                  /* Pressing turbo bind toggles turbo button on or off.
                   * Holding the button will pass through, else
                   * the pressed state will be modulated by a
                   * periodic pulse defined by the configured duty cycle.
                   */

                  /* Avoid detecting the turbo button being held as multiple toggles */
                  if (!input_st->turbo_btns.frame_enable[port])
                     input_st->turbo_btns.turbo_pressed[port] &= ~(1 << 31);
                  else if (input_st->turbo_btns.turbo_pressed[port] >= 0)
                  {
                     input_st->turbo_btns.turbo_pressed[port] |= (1 << 31);
                     /* Toggle turbo for selected button. */
                     if (input_st->turbo_btns.enable[port] != (1 << id))
                        input_st->turbo_btns.enable[port] = (1 << id);
                     input_st->turbo_btns.mode1_enable[port] ^= 1;
                  }

                  if (input_st->turbo_btns.turbo_pressed[port] & (1 << 31))
                  {
                     /* Avoid detecting buttons being held as multiple toggles */
                     if (!res)
                        input_st->turbo_btns.turbo_pressed[port] &= ~(1 << id);
                     else if (!(input_st->turbo_btns.turbo_pressed[port] & (1 << id))
                           && turbo_mode == INPUT_TURBO_MODE_SINGLEBUTTON)
                     {
                        uint16_t enable_new;
                        input_st->turbo_btns.turbo_pressed[port] |= 1 << id;
                        enable_new = input_st->turbo_btns.enable[port] ^ (1 << id);
                        if (enable_new)
                           input_st->turbo_btns.enable[port] = enable_new;
                     }
                  }
                  /* Hold mode stops turbo on release */
                  else if ((turbo_mode == INPUT_TURBO_MODE_SINGLEBUTTON_HOLD)
                        && (input_st->turbo_btns.enable[port])
                        && (input_st->turbo_btns.mode1_enable[port]))
                     input_st->turbo_btns.mode1_enable[port] = 0;

                  if (     (!res)
                        && (input_st->turbo_btns.mode1_enable[port])
                        && (input_st->turbo_btns.enable[port] & (1 << id)))
                     res = ((input_st->turbo_btns.count % turbo_period) < turbo_duty_cycle);
               }
               else if (turbo_mode == INPUT_TURBO_MODE_CLASSIC)
               {
                  /* If turbo button is held, all buttons pressed
                   * will go into a turbo mode. Until the button is
                   * released again, the input state will be modulated by a
                   * periodic pulse defined by the configured duty cycle.
                   */
                  if (res)
                  {
                     if (input_st->turbo_btns.frame_enable[port])
                        input_st->turbo_btns.enable[port] |= (1 << id);

                     if (input_st->turbo_btns.enable[port] & (1 << id))
                        /* if turbo button is enabled for this key ID */
                        res = ((input_st->turbo_btns.count % turbo_period) < turbo_duty_cycle);
                  }
                  else
                     input_st->turbo_btns.enable[port] &= ~(1 << id);
               }
               else /* Classic toggle mode */
               {
                  /* Works pretty much the same as 
                   * classic mode above but with a 
                   * toggle mechanic */

                  /* Check if it's to enable the turbo func, 
                   * if we're still holding the button from 
                   * previous toggle then ignore */
                  if (   (res)
                      && (input_st->turbo_btns.frame_enable[port]))
                  {
                     if (!(input_st->turbo_btns.turbo_pressed[port] & (1 << id)))
                     {
                        input_st->turbo_btns.enable[port] ^= (1 << id);
                        /* Remember for the toggle check */
                        input_st->turbo_btns.turbo_pressed[port] |= (1 << id);
                     }
                  }
                  else
                     input_st->turbo_btns.turbo_pressed[port] &= ~(1 << id);

                  if (res)
                  {
                     /* If turbo button is enabled for this key ID */
                     if (input_st->turbo_btns.enable[port] & (1 << id))
                        res = ((input_st->turbo_btns.count % turbo_period) < turbo_duty_cycle);
                  }
               }
            }
         }

         break;


      case RETRO_DEVICE_KEYBOARD:

         res = ret;

         if (id < RETROK_LAST)
         {
#ifdef HAVE_OVERLAY
            if (port == 0)
            {
               if (input_st->overlay_ptr
                     && (input_st->overlay_ptr->flags & INPUT_OVERLAY_ALIVE))
               {
                  input_overlay_state_t
                     *ol_state          = &input_st->overlay_ptr->overlay_state;

                  if (OVERLAY_GET_KEY(ol_state, id))
                     res               |= 1;
               }
            }
#endif
            if (MAPPER_GET_KEY(handle, id))
               res |= 1;
         }

         break;


      case RETRO_DEVICE_ANALOG:
         {
#if defined(HAVE_NETWORKGAMEPAD) || defined(HAVE_OVERLAY)
#ifdef HAVE_NETWORKGAMEPAD
            input_remote_state_t
               *input_state         = &input_st->remote_st_ptr;

#endif
            unsigned base           = (idx == RETRO_DEVICE_INDEX_ANALOG_RIGHT)
               ? 2 : 0;
            if (id == RETRO_DEVICE_ID_ANALOG_Y)
               base += 1;
#ifdef HAVE_NETWORKGAMEPAD
            if (     input_st->remote && idx < RETRO_DEVICE_INDEX_ANALOG_BUTTON
                  && input_state && input_state->analog[base][port])
               res          = input_state->analog[base][port];
            else
#endif
#endif
            {
               if (id < RARCH_FIRST_META_KEY)
               {
                  bool bind_valid         = input_st->libretro_input_binds[port]
                     && (*input_st->libretro_input_binds[port])[id].valid;

                  if (bind_valid)
                  {
                     /* reset_state - used to reset input state of a button
                      * when the gamepad mapper is in action for that button*/
                     bool reset_state        = false;
                     if (idx < 2 && id < 2)
                     {
                        unsigned offset = RARCH_FIRST_CUSTOM_BIND +
                           (idx * 4) + (id * 2);

                        if (settings->uints.input_remap_ids[port][offset] != offset)
                           reset_state = true;
                        else if (settings->uints.input_remap_ids[port][offset + 1] != (offset+1))
                           reset_state = true;
                     }

                     if (reset_state)
                        res = 0;
                     else
                     {
                        res = ret;

#ifdef HAVE_OVERLAY
                        if (   (input_st->overlay_ptr)
                            && (input_st->overlay_ptr->flags & INPUT_OVERLAY_ALIVE)
                            && (port == 0)
                            && (idx != RETRO_DEVICE_INDEX_ANALOG_BUTTON)
                            && !(((input_analog_dpad_mode == ANALOG_DPAD_LSTICK)
                            &&   (idx == RETRO_DEVICE_INDEX_ANALOG_LEFT))
                            || ((input_analog_dpad_mode == ANALOG_DPAD_RSTICK)
                            &&   (idx == RETRO_DEVICE_INDEX_ANALOG_RIGHT))))
                        {
                           input_overlay_state_t *ol_state =
                              &input_st->overlay_ptr->overlay_state;
                           int16_t ol_analog               =
                                 ol_state->analog[base];

                           /* Analog values are an integer corresponding
                            * to the extent of the analog motion; these
                            * cannot be OR'd together, we must instead
                            * keep the value with the largest magnitude */
                           if (ol_analog)
                           {
                              if (res == 0)
                                 res = ol_analog;
                              else
                              {
                                 int16_t ol_analog_abs = (ol_analog >= 0) ?
                                       ol_analog : -ol_analog;
                                 int16_t res_abs       = (res >= 0) ?
                                       res : -res;

                                 res = (ol_analog_abs > res_abs) ?
                                       ol_analog : res;
                              }
                           }
                        }
#endif
                     }
                  }
               }
            }

            if (idx < 2 && id < 2)
            {
               unsigned offset = 0 + (idx * 4) + (id * 2);
               int        val1 = handle->analog_value[port][offset];
               int        val2 = handle->analog_value[port][offset+1];

               /* OR'ing these analog values is 100% incorrect,
                * but I have no idea what this code is supposed
                * to be doing (val1 and val2 always seem to be
                * zero), so I will leave it alone... */
               if (val1)
                  res          |= val1;
               else if (val2)
                  res          |= val2;
            }
         }
         break;

      case RETRO_DEVICE_MOUSE:
      case RETRO_DEVICE_LIGHTGUN:
      case RETRO_DEVICE_POINTER:

#ifdef HAVE_OVERLAY
         if (     (input_st->overlay_ptr)
               && (input_st->overlay_ptr->flags & INPUT_OVERLAY_ENABLE)
               && (settings->bools.input_overlay_pointer_enable))
            res = input_overlay_pointing_device_state(
                  settings->ints.input_overlay_lightgun_port,
                  settings->bools.input_overlay_lightgun_allow_offscreen,
                  input_st->overlay_ptr, port, device, idx, id);
#endif

         if (res || input_st->flags & INP_FLAG_BLOCK_POINTER_INPUT)
            break;

         if (id < RARCH_FIRST_META_KEY)
         {
            bool bind_valid = input_st->libretro_input_binds[port]
               && (*input_st->libretro_input_binds[port])[id].valid;

            if (bind_valid)
            {
               if (button_mask)
               {
                  if (ret & (1 << id))
                     res |= (1 << id);
               }
               else
                  res = ret;
            }
         }

         break;
   }

   return res;
}


static int16_t input_state_internal(
      input_driver_state_t *input_st,
      settings_t *settings,
      unsigned port, unsigned device,
      unsigned idx, unsigned id)
{
   rarch_joypad_info_t joypad_info;
   float input_analog_deadzone             = settings->floats.input_analog_deadzone;
   float input_analog_sensitivity          = settings->floats.input_analog_sensitivity;
   unsigned *input_remap_port_map          = settings->uints.input_remap_port_map[port];
   uint8_t max_users                       = settings->uints.input_max_users;
   const input_device_driver_t *joypad     = input_st->primary_joypad;
#ifdef HAVE_MFI
   const input_device_driver_t *sec_joypad = input_st->secondary_joypad;
#else
   const input_device_driver_t *sec_joypad = NULL;
#endif
   uint8_t mapped_port                     = 0;
   int16_t result                          = 0;
   bool input_blocked                      = (input_st->flags & INP_FLAG_BLOCK_LIBRETRO_INPUT) ? true : false;
   bool input_driver_analog_requested      = input_st->analog_requested[port];
   bool bitmask_enabled                    = false;

   device                                 &= RETRO_DEVICE_MASK;
   bitmask_enabled                         =    (device == RETRO_DEVICE_JOYPAD)
                                             && (id == RETRO_DEVICE_ID_JOYPAD_MASK);
   joypad_info.axis_threshold              = settings->floats.input_axis_threshold;

   /* Loop over all 'physical' ports mapped to specified
    * 'virtual' port index */
   while ((mapped_port = *(input_remap_port_map++)) < MAX_USERS)
   {
      int16_t ret                    = 0;
      int16_t port_result            = 0;
      uint8_t input_analog_dpad_mode = settings->uints.input_analog_dpad_mode[mapped_port];

      joypad_info.joy_idx            = settings->uints.input_joypad_index[mapped_port];
      joypad_info.auto_binds         = input_autoconf_binds[joypad_info.joy_idx];

      /* Skip disabled input devices */
      if (mapped_port >= max_users)
         continue;

      /* If core has requested analog input, disable
       * analog to dpad mapping (unless forced) */
      switch (input_analog_dpad_mode)
      {
         case ANALOG_DPAD_LSTICK:
         case ANALOG_DPAD_RSTICK:
            if (input_driver_analog_requested)
               input_analog_dpad_mode = ANALOG_DPAD_NONE;
            break;
         case ANALOG_DPAD_LSTICK_FORCED:
            input_analog_dpad_mode = ANALOG_DPAD_LSTICK;
            break;
         case ANALOG_DPAD_RSTICK_FORCED:
            input_analog_dpad_mode = ANALOG_DPAD_RSTICK;
            break;
         default:
            break;
      }

      /* TODO/FIXME: This code is gibberish - a mess of nested
       * refactors that make no sense whatsoever. The entire
       * thing needs to be rewritten from scratch... */

      ret = input_state_wrap(
            input_st->current_driver,
            input_st->current_data,
            joypad,
            sec_joypad,
            &joypad_info,
            (*input_st->libretro_input_binds),
            (input_st->flags & INP_FLAG_KB_MAPPING_BLOCKED) ? true : false,
            mapped_port, device, idx, id);

      /* Ignore analog sticks when using Analog to Digital */
      if (     (device == RETRO_DEVICE_ANALOG)
            && (input_analog_dpad_mode != ANALOG_DPAD_NONE))
         ret = 0;

      if (     (device == RETRO_DEVICE_ANALOG)
            && (ret == 0))
      {
         if (input_st->libretro_input_binds[mapped_port])
         {
            if (idx == RETRO_DEVICE_INDEX_ANALOG_BUTTON)
            {
               if (id < RARCH_FIRST_CUSTOM_BIND)
               {
                  /* TODO/FIXME: Analog buttons can only be read as analog
                   * when the default mapping is applied. If the user
                   * remaps any analog buttons, they will become 'digital'
                   * due to the way that mapping is handled elsewhere. We
                   * cannot fix this without rewriting the entire mess that
                   * is the input remapping system... */
                  bool valid_bind = (*input_st->libretro_input_binds[mapped_port])[id].valid &&
                        (id == settings->uints.input_remap_ids[mapped_port][id]);

                  if (valid_bind)
                  {
                     if (sec_joypad)
                        ret = input_joypad_analog_button(
                              input_analog_deadzone,
                              input_analog_sensitivity,
                              sec_joypad, &joypad_info,
                              id,
                              &(*input_st->libretro_input_binds[mapped_port])[id]);

                     if (joypad && (ret == 0))
                        ret = input_joypad_analog_button(
                              input_analog_deadzone,
                              input_analog_sensitivity,
                              joypad, &joypad_info,
                              id,
                              &(*input_st->libretro_input_binds[mapped_port])[id]);
                  }
               }
            }
            else
            {
               if (sec_joypad)
                  ret = input_joypad_analog_axis(
                        input_analog_dpad_mode,
                        input_analog_deadzone,
                        input_analog_sensitivity,
                        sec_joypad,
                        &joypad_info,
                        idx,
                        id,
                        (*input_st->libretro_input_binds[mapped_port]));

               if (joypad && (ret == 0))
                  ret = input_joypad_analog_axis(
                        input_analog_dpad_mode,
                        input_analog_deadzone,
                        input_analog_sensitivity,
                        joypad,
                        &joypad_info,
                        idx,
                        id,
                        (*input_st->libretro_input_binds[mapped_port]));
            }
         }
      }

      if (!input_blocked)
      {
         input_mapper_t *handle = &input_st->mapper;

         if (bitmask_enabled)
         {
            uint8_t i;
            for (i = 0; i < RARCH_FIRST_CUSTOM_BIND; i++)
               if (input_state_device(input_st,
                        settings, handle,
                        input_analog_dpad_mode, ret, mapped_port,
                        device, idx, i, true))
                  port_result |= (1 << i);
         }
         else
            port_result = input_state_device(input_st,
                  settings, handle,
                  input_analog_dpad_mode, ret, mapped_port,
                  device, idx, id, false);

         /* Handle Analog to Digital */
         if (     (device == RETRO_DEVICE_JOYPAD)
               && (input_analog_dpad_mode != ANALOG_DPAD_NONE)
               && (bitmask_enabled || (id >= RETRO_DEVICE_ID_JOYPAD_UP && id <= RETRO_DEVICE_ID_JOYPAD_RIGHT)))
         {
            int16_t ret_axis;
            uint8_t s;
            uint8_t a;

            for (s = RETRO_DEVICE_INDEX_ANALOG_LEFT; s <= RETRO_DEVICE_INDEX_ANALOG_RIGHT; s++)
            {
               if (     (s == RETRO_DEVICE_INDEX_ANALOG_LEFT  && input_analog_dpad_mode != ANALOG_DPAD_LSTICK)
                     || (s == RETRO_DEVICE_INDEX_ANALOG_RIGHT && input_analog_dpad_mode != ANALOG_DPAD_RSTICK))
                  continue;

               for (a = RETRO_DEVICE_ID_ANALOG_X; a <= RETRO_DEVICE_ID_ANALOG_Y; a++)
               {
                  ret_axis = input_joypad_analog_axis(
                        ANALOG_DPAD_NONE,
                        settings->floats.input_analog_deadzone,
                        settings->floats.input_analog_sensitivity,
                        joypad,
                        &joypad_info,
                        s,
                        a,
                        (*input_st->libretro_input_binds[mapped_port]));

                  if (ret_axis)
                  {
                     if (a == RETRO_DEVICE_ID_ANALOG_Y && (float)ret_axis / 0x7fff < -joypad_info.axis_threshold)
                     {
                        if (bitmask_enabled)
                           port_result |= (1 << RETRO_DEVICE_ID_JOYPAD_UP);
                        else if (id == RETRO_DEVICE_ID_JOYPAD_UP)
                           port_result = RETRO_DEVICE_ID_JOYPAD_UP;
                     }
                     else if (a == RETRO_DEVICE_ID_ANALOG_Y && (float)ret_axis / 0x7fff > joypad_info.axis_threshold)
                     {
                        if (bitmask_enabled)
                           port_result |= (1 << RETRO_DEVICE_ID_JOYPAD_DOWN);
                        else if (id == RETRO_DEVICE_ID_JOYPAD_DOWN)
                           port_result = RETRO_DEVICE_ID_JOYPAD_DOWN;
                     }

                     if (a == RETRO_DEVICE_ID_ANALOG_X && (float)ret_axis / 0x7fff < -joypad_info.axis_threshold)
                     {
                        if (bitmask_enabled)
                           port_result |= (1 << RETRO_DEVICE_ID_JOYPAD_LEFT);
                        else if (id == RETRO_DEVICE_ID_JOYPAD_LEFT)
                           port_result = RETRO_DEVICE_ID_JOYPAD_LEFT;
                     }
                     else if (a == RETRO_DEVICE_ID_ANALOG_X && (float)ret_axis / 0x7fff > joypad_info.axis_threshold)
                     {
                        if (bitmask_enabled)
                           port_result |= (1 << RETRO_DEVICE_ID_JOYPAD_RIGHT);
                        else if (id == RETRO_DEVICE_ID_JOYPAD_RIGHT)
                           port_result = RETRO_DEVICE_ID_JOYPAD_RIGHT;
                     }
                  }
               }
            }
         }
      }

      /* Digital values are represented by a bitmap;
       * we can just perform the logical OR of
       * successive samples.
       * Analog values are an integer corresponding
       * to the extent of the analog motion; these
       * cannot be OR'd together, we must instead
       * keep the value with the largest magnitude */
      if (device == RETRO_DEVICE_ANALOG)
      {
         if (result == 0)
            result = port_result;
         else
         {
            int16_t port_result_abs = (port_result >= 0)
               ? port_result : -port_result;
            int16_t result_abs      = (result >= 0)
               ? result      : -result;

            if (port_result_abs > result_abs)
               result = port_result;
         }
      }
      else
         result |= port_result;
   }

   return result;
}


#ifdef HAVE_OVERLAY
/**
 * input_overlay_add_inputs:
 * @desc : pointer to overlay description
 * @ol_state : pointer to overlay state. If valid, inputs
 *             that are actually 'touched' on the overlay
 *             itself will displayed. If NULL, inputs from
 *             the device connected to 'port' will be displayed.
 * @port : when ol_state is NULL, specifies the port of
 *         the input device from which input will be
 *         displayed.
 *
 * Adds inputs from current_input to the overlay, so it's displayed
 * @return true if an input that is pressed will change the overlay
 */
static bool input_overlay_add_inputs_inner(overlay_desc_t *desc,
      input_driver_state_t *input_st,
      settings_t *settings,
      input_overlay_state_t *ol_state, unsigned port)
{
   switch(desc->type)
   {
      case OVERLAY_TYPE_BUTTONS:
         {
            int i;

            /* Check custom binds in the mask */
            for (i = 0; i < CUSTOM_BINDS_U32_COUNT; ++i)
            {
               /* Get bank */
               uint32_t bank_mask = BITS_GET_ELEM(desc->button_mask,i);
               unsigned        id = i * 32;

               /* Worth pursuing? Have we got any bits left in here? */
               while (bank_mask)
               {
                  /* If this bit is set then we need to query the pad
                   * The button must be pressed.*/
                  if (bank_mask & 1)
                  {
                     if (id >= RARCH_CUSTOM_BIND_LIST_END)
                        break;

                     /* Light up the button if pressed */
                     if (     ol_state
                           ? !BIT256_GET(ol_state->buttons, id)
                           : !input_state_internal(input_st,
                              settings, port, RETRO_DEVICE_JOYPAD, 0, id))
                     {
                        /* We need ALL of the inputs to be active,
                         * abort. */
                        desc->touch_mask = 0;
                        return false;
                     }

                     desc->touch_mask   |= (1 << OVERLAY_MAX_TOUCH);
                  }

                  bank_mask >>= 1;
                  ++id;
               }
            }

            return (desc->touch_mask != 0);
         }

      case OVERLAY_TYPE_ANALOG_LEFT:
      case OVERLAY_TYPE_ANALOG_RIGHT:
         if (ol_state)
         {
            unsigned index_offset = (desc->type == OVERLAY_TYPE_ANALOG_RIGHT) ? 2 : 0;
            desc->touch_mask     |= (
                   ol_state->analog[index_offset]
                 | ol_state->analog[index_offset + 1]) << OVERLAY_MAX_TOUCH;
         }
         else
         {
            unsigned index        = (desc->type == OVERLAY_TYPE_ANALOG_RIGHT)
               ? RETRO_DEVICE_INDEX_ANALOG_RIGHT
               : RETRO_DEVICE_INDEX_ANALOG_LEFT;
            int16_t analog_x      = input_state_internal(input_st, settings, port, RETRO_DEVICE_ANALOG,
                  index, RETRO_DEVICE_ID_ANALOG_X);
            int16_t analog_y      = input_state_internal(input_st, settings, port, RETRO_DEVICE_ANALOG,
                  index, RETRO_DEVICE_ID_ANALOG_Y);

            /* Only modify overlay delta_x/delta_y values
             * if we are monitoring input from a physical
             * controller */
            desc->delta_x         = (analog_x / (float)0x8000) * (desc->range_x / 2.0f);
            desc->delta_y         = (analog_y / (float)0x8000) * (desc->range_y / 2.0f);
         }

         /* fall-through */

      case OVERLAY_TYPE_DPAD_AREA:
      case OVERLAY_TYPE_ABXY_AREA:
         return (desc->touch_mask != 0);

      case OVERLAY_TYPE_KEYBOARD:
         {
            bool tmp    = false;
            if (ol_state)
            {
               if (OVERLAY_GET_KEY(ol_state, desc->retro_key_idx))
                  tmp   = true;
            }
            else
               tmp      = input_state_internal(input_st, settings, port,
                     RETRO_DEVICE_KEYBOARD, 0, desc->retro_key_idx);

            if (tmp)
            {
               desc->touch_mask |= (1 << OVERLAY_MAX_TOUCH);
               return true;
            }
         }
         break;

      default:
         break;
   }

   return false;
}

static bool input_overlay_add_inputs(input_overlay_t *ol,
      input_overlay_state_t *ol_state,
      input_driver_state_t *input_st,
      settings_t *settings,
      bool show_touched, unsigned port)
{
   size_t i;
   bool button_pressed      = false;

   for (i = 0; i < ol->active->size; i++)
   {
      overlay_desc_t *desc  = &(ol->active->descs[i]);
      button_pressed       |= input_overlay_add_inputs_inner(
            desc, input_st,
            settings,
            show_touched
            ? ol_state
            : NULL,
            port);
   }

   return button_pressed;
}

/**
 * input_overlay_get_eightway_state:
 * @desc : overlay descriptor handle for an eightway area
 * @out : current input state to be OR'd with eightway state
 * @x_dist : X offset from eightway area center
 * @y_dist : Y offset from eightway area center
 *
 * Gets the eightway area's current input state based on (@x_dist, @y_dist).
 **/
static INLINE void input_overlay_get_eightway_state(
      const struct overlay_desc *desc,
      overlay_eightway_config_t *eightway,
      input_bits_t *out,
      float x_dist, float y_dist)
{
   uint32_t *data;
   float abs_slope;

   x_dist /= desc->range_x;
   y_dist /= desc->range_y;

   if (x_dist == 0.0f)
      x_dist = 0.0001f;
   abs_slope = fabs(y_dist / x_dist);

   if (x_dist > 0.0f)
   {
      if (y_dist < 0.0f)
      {
         /* Q1 */
         if (abs_slope > *eightway->slope_high)
            data = eightway->up.data;
         else if (abs_slope < *eightway->slope_low)
            data = eightway->right.data;
         else
            data = eightway->up_right.data;
      }
      else
      {
         /* Q4 */
         if (abs_slope > *eightway->slope_high)
            data = eightway->down.data;
         else if (abs_slope < *eightway->slope_low)
            data = eightway->right.data;
         else
            data = eightway->down_right.data;
      }
   }
   else
   {
      if (y_dist < 0.0f)
      {
         /* Q2 */
         if (abs_slope > *eightway->slope_high)
            data = eightway->up.data;
         else if (abs_slope < *eightway->slope_low)
            data = eightway->left.data;
         else
            data = eightway->up_left.data;
      }
      else
      {
         /* Q3 */
         if (abs_slope > *eightway->slope_high)
            data = eightway->down.data;
         else if (abs_slope < *eightway->slope_low)
            data = eightway->left.data;
         else
            data = eightway->down_left.data;
      }
   }

   bits_or_bits(out->data, data, CUSTOM_BINDS_U32_COUNT);
}

/**
 * input_overlay_get_analog_state:
 * @out : Overlay input state to be modified
 * @desc : Overlay descriptor handle
 * @base : 0 or 2 for analog_left or analog_right
 * @x : X coordinate
 * @y : Y coordinate
 * @x_dist : X offset from analog center
 * @y_dist : Y offset from analog center
 * @first_touch : Set true if analog was not controlled in previous poll
 *
 * Gets the analog input state based on @x and @y, and applies to @out.
 */
static void input_overlay_get_analog_state(
      input_overlay_state_t *out, struct overlay_desc *desc,
      unsigned base, float x, float y, float *x_dist, float *y_dist,
      bool first_touch)
{
   float x_val, y_val;
   float x_val_sat, y_val_sat;
   const int b = base / 2;

   static float x_center[2];
   static float y_center[2];

   if (first_touch)
   {
      unsigned recenter_zone =  /* [0,100] */
            config_get_ptr()->uints.input_overlay_analog_recenter_zone;

      if (recenter_zone != 0)
      {
         float touch_dist, w;

         x_val      = (x - desc->x_shift) / desc->range_x;
         y_val      = (y - desc->y_shift) / desc->range_y;
         touch_dist = sqrt((x_val * x_val + y_val * y_val) * 1e4);

         /* Inside zone, recenter to first touch.
          * Outside zone, recenter to zone perimeter. */
         if (touch_dist <= recenter_zone || recenter_zone >= 100)
            w = 0.0f;
         else
            w = (touch_dist - recenter_zone) / touch_dist;

         x_center[b] = x * (1.0f - w) + desc->x_shift * w;
         y_center[b] = y * (1.0f - w) + desc->y_shift * w;
      }
      else
      {
         x_center[b] = desc->x_shift;
         y_center[b] = desc->y_shift;
      }
   }

   *x_dist   = x - x_center[b];
   *y_dist   = y - y_center[b];
   x_val     = *x_dist / desc->range_x;
   y_val     = *y_dist / desc->range_y;
   x_val_sat = x_val   / desc->analog_saturate_pct;
   y_val_sat = y_val   / desc->analog_saturate_pct;

   out->analog[base + 0] = clamp_float(x_val_sat, -1.0f, 1.0f) * 32767.0f;
   out->analog[base + 1] = clamp_float(y_val_sat, -1.0f, 1.0f) * 32767.0f;
}

/**
 * input_overlay_coords_inside_hitbox:
 * @desc                  : Overlay descriptor handle.
 * @x                     : X coordinate value.
 * @y                     : Y coordinate value.
 * @use_range_mod         : Set true to use range_mod hitbox
 *
 * Check whether the given @x and @y coordinates of the overlay
 * descriptor @desc is inside the overlay descriptor's hitbox.
 *
 * Returns: true (1) if X, Y coordinates are inside a hitbox,
 * otherwise false (0).
 **/
static bool input_overlay_coords_inside_hitbox(const struct overlay_desc *desc,
      float x, float y, bool use_range_mod)
{
   float range_x, range_y;

   if (use_range_mod)
   {
      range_x = desc->range_x_mod;
      range_y = desc->range_y_mod;
   }
   else
   {
      range_x = desc->range_x_hitbox;
      range_y = desc->range_y_hitbox;
   }

   switch (desc->hitbox)
   {
      case OVERLAY_HITBOX_RADIAL:
      {
         /* Ellipse. */
         float x_dist  = (x - desc->x_hitbox) / range_x;
         float y_dist  = (y - desc->y_hitbox) / range_y;
         float sq_dist = x_dist * x_dist + y_dist * y_dist;
         return (sq_dist <= 1.0f);
      }
      case OVERLAY_HITBOX_RECT:
         return
               (fabs(x - desc->x_hitbox) <= range_x)
            && (fabs(y - desc->y_hitbox) <= range_y);
      case OVERLAY_HITBOX_NONE:
         break;
   }
   return false;
}

/**
 * input_overlay_poll:
 * @out                   : Polled output data.
 * @touch_idx             : Touch pointer index.
 * @norm_x                : Normalized X coordinate.
 * @norm_y                : Normalized Y coordinate.
 * @touch_scale           : Overlay scale.
 *
 * Polls input overlay for a single touch pointer.
 *
 * @norm_x and @norm_y are the result of
 * video_driver_translate_coord_viewport().
 *
 * @return true if touch pointer is inside any hitbox
 **/
static bool input_overlay_poll(
      input_overlay_t *ol,
      input_overlay_state_t *out,
      int touch_idx, int16_t norm_x, int16_t norm_y, float touch_scale)
{
   size_t i, j;
   struct overlay_desc *descs = ol->active->descs;
   unsigned int highest_prio  = 0;
   int old_touch_idx          = input_driver_st.old_touch_index_lut[touch_idx];
   bool any_hitbox_pressed    = false;
   bool use_range_mod;

   /* norm_x and norm_y is in [-0x7fff, 0x7fff] range,
    * like RETRO_DEVICE_POINTER. */
   float x = (float)(norm_x + 0x7fff) / 0xffff;
   float y = (float)(norm_y + 0x7fff) / 0xffff;

   x -= ol->active->mod_x;
   y -= ol->active->mod_y;
   x /= ol->active->mod_w;
   y /= ol->active->mod_h;

   x *= touch_scale;
   y *= touch_scale;

   for (i = 0; i < ol->active->size; i++)
   {
      float x_dist, y_dist;
      unsigned int base         = 0;
      unsigned int desc_prio    = 0;
      struct overlay_desc *desc = &descs[i];

      /* Use range_mod if this touch pointer contributed
       * to desc's touch_mask in the previous poll */
      use_range_mod = (old_touch_idx != -1)
            && BIT32_GET(desc->old_touch_mask, old_touch_idx);

      if (!input_overlay_coords_inside_hitbox(desc, x, y, use_range_mod))
         continue;

      /* Check for exclusive hitbox, which blocks other input.
       * range_mod_exclusive has priority over exclusive. */
      if (use_range_mod && (desc->flags & OVERLAY_DESC_RANGE_MOD_EXCLUSIVE))
         desc_prio = 2;
      else if (desc->flags & OVERLAY_DESC_EXCLUSIVE)
         desc_prio = 1;

      if (highest_prio > desc_prio)
         continue;

      if (desc_prio > highest_prio)
      {
         highest_prio = desc_prio;
         memset(out, 0, sizeof(*out));
         for (j = 0; j < i; j++)
            BIT32_CLEAR(descs[j].touch_mask, touch_idx);
      }

      BIT32_SET(desc->touch_mask, touch_idx);
      x_dist = x - desc->x_shift;
      y_dist = y - desc->y_shift;

      switch (desc->type)
      {
         case OVERLAY_TYPE_BUTTONS:
            bits_or_bits(out->buttons.data,
                  desc->button_mask.data,
                  ARRAY_SIZE(desc->button_mask.data));

            if (BIT256_GET(desc->button_mask, RARCH_OVERLAY_NEXT))
               ol->next_index = desc->next_index;
            break;
         case OVERLAY_TYPE_KEYBOARD:
            if (desc->retro_key_idx < RETROK_LAST)
               OVERLAY_SET_KEY(out, desc->retro_key_idx);
            break;
         case OVERLAY_TYPE_DPAD_AREA:
         case OVERLAY_TYPE_ABXY_AREA:
            input_overlay_get_eightway_state(
                  desc, desc->eightway_config,
                  &out->buttons, x_dist, y_dist);
            break;
         case OVERLAY_TYPE_ANALOG_RIGHT:
            base = 2;
            /* fall-through */
         default:
            input_overlay_get_analog_state(
                  out, desc, base, x, y,
                  &x_dist, &y_dist, !use_range_mod);
            break;
      }

      if (desc->flags & OVERLAY_DESC_MOVABLE)
      {
         desc->delta_x = clamp_float(x_dist, -desc->range_x, desc->range_x)
            * ol->active->mod_w;
         desc->delta_y = clamp_float(y_dist, -desc->range_y, desc->range_y)
            * ol->active->mod_h;
      }

      any_hitbox_pressed = true;
   }

   if (ol->flags & INPUT_OVERLAY_BLOCKED)
      memset(out, 0, sizeof(*out));

   return any_hitbox_pressed;
}

/**
 * input_overlay_update_desc_geom:
 * @ol                    : overlay handle.
 * @desc                  : overlay descriptors handle.
 *
 * Update input overlay descriptors' vertex geometry.
 **/
static void input_overlay_update_desc_geom(input_overlay_t *ol,
      struct overlay_desc *desc)
{
   if (!desc->image.pixels || !(desc->flags & OVERLAY_DESC_MOVABLE))
      return;

   if (ol->iface->vertex_geom)
      ol->iface->vertex_geom(ol->iface_data, desc->image_index,
            desc->mod_x + desc->delta_x, desc->mod_y + desc->delta_y,
            desc->mod_w, desc->mod_h);

   desc->delta_x = 0.0f;
   desc->delta_y = 0.0f;
}

/**
 * input_overlay_post_poll:
 *
 * Called after all the input_overlay_poll() calls to
 * update alpha mods for pressed/unpressed controls
 **/
static void input_overlay_post_poll(
      enum overlay_visibility *visibility,
      input_overlay_t *ol,
      bool show_input, float opacity)
{
   size_t i;

   input_overlay_set_alpha_mod(visibility, ol, opacity);

   for (i = 0; i < ol->active->size; i++)
   {
      struct overlay_desc *desc = &ol->active->descs[i];

      if (     desc->touch_mask != 0
            && show_input && desc->image.pixels
            && ol->iface->set_alpha)
         ol->iface->set_alpha(ol->iface_data, desc->image_index,
               desc->alpha_mod * opacity);

      input_overlay_update_desc_geom(ol, desc);

      desc->old_touch_mask = desc->touch_mask;
      desc->touch_mask     = 0;
   }
}

/**
 * input_overlay_poll_clear:
 * @ol                    : overlay handle
 *
 * Call when there is nothing to poll. Allows overlay to
 * clear certain state.
 **/
static void input_overlay_poll_clear(
      enum overlay_visibility *visibility,
      input_overlay_t *ol, float opacity)
{
   size_t i;

   ol->flags &= ~INPUT_OVERLAY_BLOCKED;

   input_overlay_set_alpha_mod(visibility, ol, opacity);

   for (i = 0; i < ol->active->size; i++)
   {
      struct overlay_desc *desc = &ol->active->descs[i];

      desc->old_touch_mask      = desc->touch_mask;
      desc->touch_mask          = 0;

      input_overlay_update_desc_geom(ol, desc);
   }
}

/**
 * input_overlay_poll_lightgun
 * @settings: pointer to settings
 * @ol : overlay handle
 * @old_ptr_count : previous poll's non-hitbox pointer count
 *
 * Updates multi-touch button state of the overlay lightgun.
 */
static void input_overlay_poll_lightgun(settings_t *settings,
      input_overlay_t *ol, const int old_ptr_count)
{
   input_overlay_pointer_state_t *ptr_st = &ol->pointer_state;
   const int ptr_count                   = ptr_st->count;
   unsigned action                       = OVERLAY_LIGHTGUN_ACTION_NONE;
   int8_t trig_delay                     =
         settings->uints.input_overlay_lightgun_trigger_delay;
   int8_t delay_idx;

   static uint16_t trig_buf;
   static uint8_t now_idx;
   static uint8_t peak_ptr_count;
   static const unsigned action_to_id[OVERLAY_LIGHTGUN_ACTION_END] = {
      RARCH_BIND_LIST_END,
      RARCH_LIGHTGUN_TRIGGER,
      RARCH_LIGHTGUN_RELOAD,
      RARCH_LIGHTGUN_AUX_A,
      RARCH_LIGHTGUN_AUX_B,
      RARCH_LIGHTGUN_AUX_C,
      RARCH_LIGHTGUN_START,
      RARCH_LIGHTGUN_SELECT,
      RARCH_LIGHTGUN_DPAD_UP,
      RARCH_LIGHTGUN_DPAD_DOWN,
      RARCH_LIGHTGUN_DPAD_LEFT,
      RARCH_LIGHTGUN_DPAD_RIGHT
   };

   /* Update peak pointer count */
   if (!old_ptr_count && ptr_count)
      peak_ptr_count = ptr_count;
   else
      peak_ptr_count = MAX(ptr_count, peak_ptr_count);

   /* Apply trigger delay */
   now_idx   = (now_idx + 1) % (OVERLAY_LIGHTGUN_TRIG_MAX_DELAY + 1);
   delay_idx = (now_idx + trig_delay) % (OVERLAY_LIGHTGUN_TRIG_MAX_DELAY + 1);

   if (ptr_count > 0)
      BIT16_SET(trig_buf, delay_idx);
   else
      BIT16_CLEAR(trig_buf, delay_idx);

   /* Create button input if we're past the trigger delay */
   if (BIT16_GET(trig_buf, now_idx))
   {
      switch (peak_ptr_count)
      {
         case 1:
            if (settings->bools.input_overlay_lightgun_trigger_on_touch)
               action = OVERLAY_LIGHTGUN_ACTION_TRIGGER;
            break;
         case 2:
            action = settings->uints.input_overlay_lightgun_two_touch_input;
            break;
         case 3:
            action = settings->uints.input_overlay_lightgun_three_touch_input;
            break;
         case 4:
            action = settings->uints.input_overlay_lightgun_four_touch_input;
            break;
         default:
            break;
      }
   }

   ptr_st->lightgun.multitouch_id = action_to_id[action];
}

static void input_overlay_get_mouse_scale(settings_t *settings,
      float *scale_x, float *scale_y,
      int *swipe_thres_x, int *swipe_thres_y)
{
   video_driver_state_t *video_st   = video_state_get_ptr();
   struct retro_game_geometry *geom = &video_st->av_info.geometry;

   if (geom->base_height)
   {
      float adj_x, adj_y;
      float speed          = settings->floats.input_overlay_mouse_speed;
      float swipe_thres    =
            655.35f * settings->floats.input_overlay_mouse_swipe_threshold;
      float display_aspect = (float)video_st->width / video_st->height;
      float core_aspect    = (float)geom->base_width / geom->base_height;

      if (display_aspect > core_aspect)
      {
         adj_x = speed * (display_aspect / core_aspect);
         adj_y = speed;
      }
      else
      {
         adj_y = speed * (core_aspect / display_aspect);
         adj_x = speed;
      }

      *scale_x = (adj_x * geom->base_width) / (float)0x7fff;
      *scale_y = (adj_y * geom->base_height) / (float)0x7fff;

      if (display_aspect > 1.0f)
      {
         *swipe_thres_x = (int)(swipe_thres / display_aspect);
         *swipe_thres_y = (int)swipe_thres;
      }
      else
      {
         *swipe_thres_x = (int)swipe_thres;
         *swipe_thres_y = (int)(swipe_thres / display_aspect);
      }
   }
}

/**
 * input_overlay_poll_mouse
 * @settings: pointer to settings
 * @ol : overlay handle
 * @old_ptr_count : previous poll's non-hitbox pointer count
 *
 * Updates button state of the overlay mouse.
 */
static void input_overlay_poll_mouse(settings_t *settings,
      struct input_overlay_mouse_state *mouse_st,
      input_overlay_t *ol,
      const int ptr_count,
      const int old_ptr_count)
{
   input_overlay_pointer_state_t *ptr_st      = &ol->pointer_state;
   const retro_time_t now_usec                = cpu_features_get_time_usec();
   const retro_time_t hold_usec               = settings->uints.input_overlay_mouse_hold_msec * 1000;
   const retro_time_t dtap_usec               = settings->uints.input_overlay_mouse_dtap_msec * 1000;
   int swipe_thres_x                          = 0;
   int swipe_thres_y                          = 0;
   const bool hold_to_drag                    = settings->bools.input_overlay_mouse_hold_to_drag;
   const bool dtap_to_drag                    = settings->bools.input_overlay_mouse_dtap_to_drag;
   bool want_feedback                         = false;
   bool is_swipe, is_brief, is_long;

   static retro_time_t start_usec;
   static retro_time_t last_down_usec;
   static retro_time_t last_up_usec;
   static retro_time_t pending_click_usec;
   static retro_time_t click_dur_usec;
   static retro_time_t click_end_usec;
   static int x_start;
   static int y_start;
   static int peak_ptr_count;
   static int old_peak_ptr_count;
   static bool skip_buttons;
   static bool pending_click;

   input_overlay_get_mouse_scale(settings,
         &mouse_st->scale_x, &mouse_st->scale_y,
         &swipe_thres_x, &swipe_thres_y);

   /* Check for pointer count changes */
   if (ptr_count != old_ptr_count)
   {
      mouse_st->click = 0;
      pending_click   = false;

      /* Assume main pointer changed. Reset deltas */
      mouse_st->prev_screen_x = x_start = ptr_st->screen_x;
      mouse_st->prev_screen_y = y_start = ptr_st->screen_y;

      if (ptr_count > old_ptr_count)
      {
         /* Pointer added */
         peak_ptr_count = ptr_count;
         start_usec     = now_usec;
      }
      else
      {
         /* Pointer removed */
         mouse_st->hold = 0;
         if (!ptr_count)
            old_peak_ptr_count = peak_ptr_count;
      }
   }

   /* Action type */
   is_swipe = abs(ptr_st->screen_x - x_start) > swipe_thres_x ||
              abs(ptr_st->screen_y - y_start) > swipe_thres_y;
   is_brief = (now_usec - start_usec) < 200000;
   is_long  = (now_usec - start_usec) > (hold_to_drag ? hold_usec : 250000);

   /* Check if new button input should be created */
   if (!skip_buttons)
   {
      if (!is_swipe)
      {
         if (     hold_to_drag
               && is_long && ptr_count && !mouse_st->hold)
         {
            /* Long press */
            mouse_st->hold = (1 << (ptr_count - 1));
            want_feedback  = true;
         }
         else if (is_brief)
         {
            if (ptr_count && !old_ptr_count)
            {
               /* New input. Check for double tap */
               if (     dtap_to_drag
                     && now_usec - last_up_usec < dtap_usec)
                  mouse_st->hold = (1 << (old_peak_ptr_count - 1));

               last_down_usec = now_usec;
            }
            else if (!ptr_count && old_ptr_count)
            {
               /* Finished a tap. Send click */
               click_dur_usec = (now_usec - last_down_usec) + 5000;

               if (dtap_to_drag)
               {
                  pending_click      = true;
                  pending_click_usec = now_usec + dtap_usec;
               }
               else
               {
                  mouse_st->click    = (1 << (peak_ptr_count - 1));
                  click_end_usec     = now_usec + click_dur_usec;
               }

               last_up_usec = now_usec;
            }
         }
      }
      else
      {
         /* If dragging 2+ fingers, hold RMB or MMB */
         if (ptr_count > 1)
         {
            mouse_st->hold = (1 << (ptr_count - 1));
            if (hold_to_drag)
               want_feedback = true;
         }
         skip_buttons = true;
      }
   }

   /* Check for pending click */
   if (pending_click && now_usec >= pending_click_usec)
   {
      mouse_st->click = (1 << (old_peak_ptr_count - 1));
      click_end_usec  = now_usec + click_dur_usec;
      pending_click   = false;
   }

   if (!ptr_count)
      skip_buttons = false; /* Reset button checks  */
   else if (is_long)
      skip_buttons = true;  /* End of button checks */

   /* Remove stale clicks */
   if (mouse_st->click && now_usec > click_end_usec)
      mouse_st->click = 0;

   if (want_feedback && settings->bools.vibrate_on_keypress)
   {
      input_driver_t *current_input = input_driver_st.current_driver;

      if (current_input && current_input->keypress_vibrate)
         current_input->keypress_vibrate();
   }
}

/**
 * input_overlay_track_touch_inputs
 * @state : Overlay input state for this poll
 * @old_state : Overlay input state for previous poll
 *
 * Matches current touch inputs to previous poll's, based on distance.
 * Updates old_touch_index_lut and assigns -1 to any new inputs.
 */
static void input_overlay_track_touch_inputs(
      input_overlay_state_t *state, input_overlay_state_t *old_state)
{
   int *const old_index_lut = input_driver_st.old_touch_index_lut;
   int i, j, t, new_idx;
   float x_dist, y_dist, sq_dist, outlier;
   float min_sq_dist[OVERLAY_MAX_TOUCH];

   memset(old_index_lut, -1, sizeof(int) * OVERLAY_MAX_TOUCH);

   /* Compute (squared) distances and match new indexes to old */
   for (i = 0; i < state->touch_count; i++)
   {
      min_sq_dist[i] = 3e8f;

      for (j = 0; j < old_state->touch_count; j++)
      {
         x_dist  = state->touch[i].x - old_state->touch[j].x;
         y_dist  = state->touch[i].y - old_state->touch[j].y;

         sq_dist = x_dist * x_dist + y_dist * y_dist;

         if (sq_dist < min_sq_dist[i])
         {
            min_sq_dist[i]   = sq_dist;
            old_index_lut[i] = j;
         }
      }
   }

   /* If touch_count increased, find the outliers and assign -1 */
   for (t = old_state->touch_count; t < state->touch_count; t++)
   {
      new_idx = OVERLAY_MAX_TOUCH - 1;
      outlier = 0;

      for (i = 0; i < state->touch_count; i++)
         if (min_sq_dist[i] > outlier)
         {
            outlier        = min_sq_dist[i];
            new_idx        = i;
            min_sq_dist[i] = 0;
         }

      old_index_lut[new_idx] = -1;
   }
}

static void input_overlay_update_pointer_coords(
      input_overlay_pointer_state_t *ptr_st, int touch_idx)
{
   void *input_data              = input_driver_st.current_data;
   input_driver_t *current_input = input_driver_st.current_driver;

   /* Need multi-touch coordinates for pointer only */
   if (     ptr_st->count
         && !(ptr_st->device_mask & (1 << RETRO_DEVICE_POINTER)))
      goto finish;

   /* Need viewport pointers for pointer and lightgun */
   if (ptr_st->device_mask &
         ((1 << RETRO_DEVICE_LIGHTGUN) | (1 << RETRO_DEVICE_POINTER)))
   {
      ptr_st->ptr[ptr_st->count].x  = current_input->input_state(
            input_data, NULL, NULL, NULL, NULL, true, 0,
            RETRO_DEVICE_POINTER,
            touch_idx,
            RETRO_DEVICE_ID_POINTER_X);
      ptr_st->ptr[ptr_st->count].y  = current_input->input_state(
            input_data, NULL, NULL, NULL, NULL, true, 0,
            RETRO_DEVICE_POINTER,
            touch_idx,
            RETRO_DEVICE_ID_POINTER_Y);
   }

   /* Need fullscreen pointer for mouse only */
   if (     !ptr_st->count
         && (ptr_st->device_mask & (1 << RETRO_DEVICE_MOUSE)))
   {
      ptr_st->mouse.prev_screen_x = ptr_st->screen_x;
      ptr_st->screen_x = current_input->input_state(
            input_data, NULL, NULL, NULL, NULL, true, 0,
            RARCH_DEVICE_POINTER_SCREEN,
            touch_idx,
            RETRO_DEVICE_ID_POINTER_X);
      ptr_st->mouse.prev_screen_y = ptr_st->screen_y;
      ptr_st->screen_y = current_input->input_state(
            input_data, NULL, NULL, NULL, NULL, true, 0,
            RARCH_DEVICE_POINTER_SCREEN,
            touch_idx,
            RETRO_DEVICE_ID_POINTER_Y);
   }

finish:
   ptr_st->count++;
}

/*
 * input_poll_overlay:
 *
 * Poll pressed buttons/keys on currently active overlay.
 **/
static void input_poll_overlay(
      bool keyboard_mapping_blocked,
      settings_t *settings,
      void *ol_data,
      enum overlay_visibility *overlay_visibility,
      float opacity,
      unsigned analog_dpad_mode,
      float axis_threshold)
{
   input_overlay_state_t old_ol_state;
   int i, j;
   input_overlay_t *ol                      = (input_overlay_t*)ol_data;
   uint16_t key_mod                         = 0;
   bool button_pressed                      = false;
   input_driver_state_t *input_st           = &input_driver_st;
   void *input_data                         = input_st->current_data;
   input_overlay_state_t *ol_state          = &ol->overlay_state;
   input_overlay_pointer_state_t *ptr_state = &ol->pointer_state;
   input_driver_t *current_input            = input_st->current_driver;
   enum overlay_show_input_type
         input_overlay_show_inputs          = (enum overlay_show_input_type)
               settings->uints.input_overlay_show_inputs;
   unsigned input_overlay_show_inputs_port  = settings->uints.input_overlay_show_inputs_port;
   float touch_scale                        = (float)settings->uints.input_touch_scale;
   bool ol_ptr_enable                       = settings->bools.input_overlay_pointer_enable;
   bool osk_state_changed                   = false;

   static int old_ptr_count;

   if (!ol_state)
      return;

   memcpy(&old_ol_state, ol_state,
         sizeof(old_ol_state));
   memset(ol_state, 0, sizeof(*ol_state));

   if (ol_ptr_enable)
   {
      old_ptr_count    = ptr_state->count;
      ptr_state->count = 0;
   }

   if (current_input->input_state)
   {
      rarch_joypad_info_t joypad_info;
      unsigned device                 = (ol->active->flags & OVERLAY_FULL_SCREEN)
         ? RARCH_DEVICE_POINTER_SCREEN
         : RETRO_DEVICE_POINTER;
      const input_device_driver_t
         *joypad                      = input_st->primary_joypad;
#ifdef HAVE_MFI
      const input_device_driver_t
         *sec_joypad                  = input_st->secondary_joypad;
#else
      const input_device_driver_t
         *sec_joypad                  = NULL;
#endif

      joypad_info.joy_idx             = 0;
      joypad_info.auto_binds          = NULL;
      joypad_info.axis_threshold      = 0.0f;

      /* Get driver input */
      for (i = 0;
            current_input->input_state(
               input_data,
               joypad,
               sec_joypad,
               &joypad_info,
               NULL,
               keyboard_mapping_blocked,
               0,
               device,
               i,
               RETRO_DEVICE_ID_POINTER_PRESSED)
                  && i < OVERLAY_MAX_TOUCH;
            i++)
      {
         ol_state->touch[i].x = current_input->input_state(
               input_data,
               joypad,
               sec_joypad,
               &joypad_info,
               NULL,
               keyboard_mapping_blocked,
               0,
               device,
               i,
               RETRO_DEVICE_ID_POINTER_X);
         ol_state->touch[i].y = current_input->input_state(
               input_data,
               joypad,
               sec_joypad,
               &joypad_info,
               NULL,
               keyboard_mapping_blocked,
               0,
               device,
               i,
               RETRO_DEVICE_ID_POINTER_Y);
      }
      ol_state->touch_count = i;

      /* Update lookup table of new to old touch indexes */
      input_overlay_track_touch_inputs(ol_state, &old_ol_state);

      /* Poll overlay */
      for (i = 0; i < ol_state->touch_count; i++)
      {
         input_overlay_state_t polled_data;
         bool hitbox_pressed = false;

         memset(&polled_data, 0, sizeof(struct input_overlay_state));

         if (ol->flags & INPUT_OVERLAY_ENABLE)
            hitbox_pressed = input_overlay_poll(ol, &polled_data, i,
                  ol_state->touch[i].x, ol_state->touch[i].y, touch_scale);
         else
            ol->flags &= ~INPUT_OVERLAY_BLOCKED;

         if (hitbox_pressed)
         {
            bits_or_bits(ol_state->buttons.data,
                  polled_data.buttons.data,
                  ARRAY_SIZE(polled_data.buttons.data));

            for (j = 0; j < (int)ARRAY_SIZE(ol_state->keys); j++)
               ol_state->keys[j] |= polled_data.keys[j];

            /* Fingers pressed later take priority and matched up
             * with overlay poll priorities. */
            for (j = 0; j < 4; j++)
               if (polled_data.analog[j])
                  ol_state->analog[j] = polled_data.analog[j];
         }
         else if (ol_ptr_enable
               && ptr_state->device_mask
               && !(ol->flags & INPUT_OVERLAY_BLOCKED))
            input_overlay_update_pointer_coords(ptr_state, i);
      }
   }

   if (ol_ptr_enable)
   {
      if (ptr_state->device_mask & (1 << RETRO_DEVICE_LIGHTGUN))
         input_overlay_poll_lightgun(settings, ol, old_ptr_count);
      if (ptr_state->device_mask & (1 << RETRO_DEVICE_MOUSE))
         input_overlay_poll_mouse(settings, &ptr_state->mouse, ol,
               ptr_state->count, old_ptr_count);
   }

   if (     OVERLAY_GET_KEY(ol_state, RETROK_LSHIFT)
         || OVERLAY_GET_KEY(ol_state, RETROK_RSHIFT))
      key_mod |= RETROKMOD_SHIFT;

   if (     OVERLAY_GET_KEY(ol_state, RETROK_LCTRL)
         || OVERLAY_GET_KEY(ol_state, RETROK_RCTRL))
      key_mod |= RETROKMOD_CTRL;

   if (     OVERLAY_GET_KEY(ol_state, RETROK_LALT)
         || OVERLAY_GET_KEY(ol_state, RETROK_RALT))
      key_mod |= RETROKMOD_ALT;

   if (     OVERLAY_GET_KEY(ol_state, RETROK_LMETA)
         || OVERLAY_GET_KEY(ol_state, RETROK_RMETA))
      key_mod |= RETROKMOD_META;

   /* CAPSLOCK SCROLLOCK NUMLOCK */
   for (i = (int)ARRAY_SIZE(ol_state->keys); i-- > 0;)
   {
      if (ol_state->keys[i] != old_ol_state.keys[i])
      {
         uint32_t orig_bits = old_ol_state.keys[i];
         uint32_t new_bits  = ol_state->keys[i];
         osk_state_changed  = true;

         for (j = 0; j < 32; j++)
            if ((orig_bits & (1 << j)) != (new_bits & (1 << j)))
            {
               unsigned rk = i * 32 + j;
               uint32_t c  = input_keymaps_translate_rk_to_ascii(rk, key_mod);
               input_keyboard_event(new_bits & (1 << j),
                     rk, c, key_mod, RETRO_DEVICE_POINTER);
            }
      }
   }

   /* Map "analog" buttons to analog axes like regular input drivers do. */
   for (j = 0; j < 4; j++)
   {
      unsigned bind_plus  = RARCH_ANALOG_LEFT_X_PLUS + 2 * j;
      unsigned bind_minus = bind_plus + 1;

      if (ol_state->analog[j])
         continue;

      if ((BIT256_GET(ol->overlay_state.buttons, bind_plus)))
         ol_state->analog[j] += 0x7fff;
      if ((BIT256_GET(ol->overlay_state.buttons, bind_minus)))
         ol_state->analog[j] -= 0x7fff;
   }

   /* Check for analog_dpad_mode.
    * Map analogs to d-pad buttons when configured. */
   switch (analog_dpad_mode)
   {
      case ANALOG_DPAD_LSTICK:
      case ANALOG_DPAD_RSTICK:
      {
         float analog_x, analog_y;
         unsigned analog_base = 2;

         if (analog_dpad_mode == ANALOG_DPAD_LSTICK)
            analog_base = 0;

         analog_x = (float)ol_state->analog[analog_base + 0] / 0x7fff;
         analog_y = (float)ol_state->analog[analog_base + 1] / 0x7fff;

         if (analog_x <= -axis_threshold)
            BIT256_SET(ol_state->buttons, RETRO_DEVICE_ID_JOYPAD_LEFT);
         if (analog_x >=  axis_threshold)
            BIT256_SET(ol_state->buttons, RETRO_DEVICE_ID_JOYPAD_RIGHT);
         if (analog_y <= -axis_threshold)
            BIT256_SET(ol_state->buttons, RETRO_DEVICE_ID_JOYPAD_UP);
         if (analog_y >=  axis_threshold)
            BIT256_SET(ol_state->buttons, RETRO_DEVICE_ID_JOYPAD_DOWN);
         break;
      }

      default:
         break;
   }

   button_pressed = input_overlay_add_inputs(ol, ol_state, input_st,
         settings,
         (input_overlay_show_inputs == OVERLAY_SHOW_INPUT_TOUCHED),
         input_overlay_show_inputs_port);

   /* Block other touchscreen input as needed. */
   if (     button_pressed
#ifdef IOS
         || (ptr_state->device_mask & (1 << RETRO_DEVICE_LIGHTGUN))
         || (ol->flags & INPUT_OVERLAY_BLOCKED))
#else
         || ol_ptr_enable)
#endif
      input_st->flags |=  INP_FLAG_BLOCK_POINTER_INPUT;
   else
      input_st->flags &= ~INP_FLAG_BLOCK_POINTER_INPUT;

   ptr_state->device_mask = 0;

   if (input_overlay_show_inputs == OVERLAY_SHOW_INPUT_NONE)
      button_pressed = false;

   if (button_pressed || ol_state->touch_count)
      input_overlay_post_poll(overlay_visibility, ol,
            button_pressed, opacity);
   else
      input_overlay_poll_clear(overlay_visibility, ol, opacity);

   /* Create haptic feedback for any change in button/key state,
    * unless touch_count decreased. */
   if (     current_input->keypress_vibrate
         && settings->bools.vibrate_on_keypress
         && ol_state->touch_count
         && ol_state->touch_count >= old_ol_state.touch_count
         && !(ol->flags & INPUT_OVERLAY_BLOCKED))
   {
      if (     osk_state_changed
            || bits_any_different(
                     ol_state->buttons.data,
                     old_ol_state.buttons.data,
                     ARRAY_SIZE(old_ol_state.buttons.data))
         )
         current_input->keypress_vibrate();
   }
}
#endif

size_t input_config_get_bind_string(
      void *settings_data,
      char *s,
      const struct retro_keybind *bind,
      const struct retro_keybind *auto_bind,
      size_t len)
{
   settings_t *settings                 = (settings_t*)settings_data;
   size_t _len                          = 0;
   int delim                            = 0;
   bool  input_descriptor_label_show    =
      settings->bools.input_descriptor_label_show;

   *s                                 = '\0';

   if      (bind      && bind->joykey  != NO_BTN)
      _len = input_config_get_bind_string_joykey(
            input_descriptor_label_show,
            s, "", bind, len);
   else if (bind      && bind->joyaxis != AXIS_NONE)
      _len = input_config_get_bind_string_joyaxis(
            input_descriptor_label_show,
            s, "", bind, len);
   else if (auto_bind && auto_bind->joykey != NO_BTN)
      _len = input_config_get_bind_string_joykey(
            input_descriptor_label_show,
            s, "(Auto)", auto_bind, len);
   else if (auto_bind && auto_bind->joyaxis != AXIS_NONE)
      _len = input_config_get_bind_string_joyaxis(
            input_descriptor_label_show,
            s, "(Auto)", auto_bind, len);

   if (*s)
      delim = 1;

#ifndef RARCH_CONSOLE
   {
      char key[64];
      key[0] = '\0';

      input_keymaps_translate_rk_to_str(bind->key, key, sizeof(key));
      if (     key[0] == 'n'
            && key[1] == 'u'
            && key[2] == 'l'
            && key[3] == '\0'
         )
         *key = '\0';
      /*empty?*/
      else if (*key != '\0')
      {
         if (delim)
            _len += strlcpy(s + _len, ", ", len - _len);
         _len += snprintf(s + _len, len - _len,
               msg_hash_to_str(MENU_ENUM_LABEL_VALUE_INPUT_KEY), key);
         delim = 1;
      }
   }
#endif

   if (bind->mbutton != NO_BTN)
   {
      int tag = 0;
      switch (bind->mbutton)
      {
         case RETRO_DEVICE_ID_MOUSE_LEFT:
            tag = MENU_ENUM_LABEL_VALUE_INPUT_MOUSE_LEFT;
            break;
         case RETRO_DEVICE_ID_MOUSE_RIGHT:
            tag = MENU_ENUM_LABEL_VALUE_INPUT_MOUSE_RIGHT;
            break;
         case RETRO_DEVICE_ID_MOUSE_MIDDLE:
            tag = MENU_ENUM_LABEL_VALUE_INPUT_MOUSE_MIDDLE;
            break;
         case RETRO_DEVICE_ID_MOUSE_BUTTON_4:
            tag = MENU_ENUM_LABEL_VALUE_INPUT_MOUSE_BUTTON4;
            break;
         case RETRO_DEVICE_ID_MOUSE_BUTTON_5:
            tag = MENU_ENUM_LABEL_VALUE_INPUT_MOUSE_BUTTON5;
            break;
         case RETRO_DEVICE_ID_MOUSE_WHEELUP:
            tag = MENU_ENUM_LABEL_VALUE_INPUT_MOUSE_WHEEL_UP;
            break;
         case RETRO_DEVICE_ID_MOUSE_WHEELDOWN:
            tag = MENU_ENUM_LABEL_VALUE_INPUT_MOUSE_WHEEL_DOWN;
            break;
         case RETRO_DEVICE_ID_MOUSE_HORIZ_WHEELUP:
            tag = MENU_ENUM_LABEL_VALUE_INPUT_MOUSE_HORIZ_WHEEL_UP;
            break;
         case RETRO_DEVICE_ID_MOUSE_HORIZ_WHEELDOWN:
            tag = MENU_ENUM_LABEL_VALUE_INPUT_MOUSE_HORIZ_WHEEL_DOWN;
            break;
      }

      if (tag != 0)
      {
         if (delim)
            _len += strlcpy(s + _len, ", ", len - _len);
         _len += strlcpy(s + _len, msg_hash_to_str((enum msg_hash_enums)tag), len - _len);
      }
   }

   /*completely empty?*/
   if (*s == '\0')
      _len += strlcpy(s + _len, "---", len - _len);
   return _len;
}

size_t input_config_get_bind_string_joykey(
      bool input_descriptor_label_show,
      char *s, const char *suffix,
      const struct retro_keybind *bind, size_t len)
{
   size_t _len = 0;
   if (GET_HAT_DIR(bind->joykey))
   {
      if (      bind->joykey_label
            && !string_is_empty(bind->joykey_label)
            && input_descriptor_label_show)
         return fill_pathname_join_delim(s,
               bind->joykey_label, suffix, ' ', len);
      /* TODO/FIXME - localize */
      _len  = snprintf(s, len,
            "Hat #%u ", (unsigned)GET_HAT(bind->joykey));
      switch (GET_HAT_DIR(bind->joykey))
      {
         case HAT_UP_MASK:
            _len += strlcpy(s + _len, "Up",    len - _len);
            break;
         case HAT_DOWN_MASK:
            _len += strlcpy(s + _len, "Down",  len - _len);
            break;
         case HAT_LEFT_MASK:
            _len += strlcpy(s + _len, "Left",  len - _len);
            break;
         case HAT_RIGHT_MASK:
            _len += strlcpy(s + _len, "Right", len - _len);
            break;
         default:
            _len += strlcpy(s + _len, "?",     len - _len);
            break;
      }
   }
   else
   {
      if (      bind->joykey_label
            && !string_is_empty(bind->joykey_label)
            && input_descriptor_label_show)
         return fill_pathname_join_delim(s,
               bind->joykey_label, suffix, ' ', len);
      /* TODO/FIXME - localize */
      _len  = strlcpy(s, "Button ", len);
      _len += snprintf(s + _len, len - _len, "%u",
            (unsigned)bind->joykey);
   }
   return _len;
}

size_t input_config_get_bind_string_joyaxis(
      bool input_descriptor_label_show,
      char *s, const char *suffix,
      const struct retro_keybind *bind, size_t len)
{
   size_t _len = 0;
   if (      bind->joyaxis_label
         && !string_is_empty(bind->joyaxis_label)
         && input_descriptor_label_show)
      return fill_pathname_join_delim(s,
            bind->joyaxis_label, suffix, ' ', len);
   /* TODO/FIXME - localize */
   _len = strlcpy(s, "Axis ", len);
   if (AXIS_NEG_GET(bind->joyaxis) != AXIS_DIR_NONE)
      _len += snprintf(s + _len, len - _len, "-%u",
            (unsigned)AXIS_NEG_GET(bind->joyaxis));
   else if (AXIS_POS_GET(bind->joyaxis) != AXIS_DIR_NONE)
      _len += snprintf(s + _len, len - _len, "+%u",
            (unsigned)AXIS_POS_GET(bind->joyaxis));
   return _len;
}

#ifdef HAVE_LANGEXTRA
/* combine 3 korean elements. make utf8 character */
static unsigned get_kr_utf8(int c1, int c2, int c3)
{
   int  uv = c1 * (28 * 21) + c2 * 28 + c3 + 0xac00;
   int  tv = (uv >> 12) | ((uv & 0x0f00) << 2) | ((uv & 0xc0) << 2) | ((uv & 0x3f) << 16);
   return  (tv | 0x8080e0);
}

/* utf8 korean composition */
static unsigned get_kr_composition(char* pcur, char* padd)
{
   size_t _len;
   static char cc1[] = {"ㄱㄱㄲ ㄷㄷㄸ ㅂㅂㅃ ㅅㅅㅆ ㅈㅈㅉ"};
   static char cc2[] = {"ㅗㅏㅘ ㅗㅐㅙ ㅗㅣㅚ ㅜㅓㅝ ㅜㅔㅞ ㅜㅣㅟ ㅡㅣㅢ"};
   static char cc3[] = {"ㄱㄱㄲ ㄱㅅㄳ ㄴㅈㄵ ㄴㅎㄶ ㄹㄱㄺ ㄹㅁㄻ ㄹㅂㄼ ㄹㅅㄽ ㄹㅌㄾ ㄹㅍㄿ ㄹㅎㅀ ㅂㅅㅄ ㅅㅅㅆ"};
   static char s1[]  = {"ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣㆍㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ"};
   char *tmp1        = NULL;
   char *tmp2        = NULL;
   int c1            = -1;
   int c2            = -1;
   int c3            =  0;
   int nv            = -1;
   char utf8[8]      = {0, 0, 0, 0, 0, 0, 0, 0};
   unsigned ret      =  *((unsigned*)pcur);

   /* check korean */
   if (!pcur[0] || !pcur[1] || !pcur[2] || pcur[3])
      return ret;
   if (!padd[0] || !padd[1] || !padd[2] || padd[3])
      return ret;
   if ((tmp1 = strstr(s1, pcur)))
      c1 = (int)((tmp1 - s1) / 3);
   if ((tmp1 = strstr(s1, padd)))
      nv = (int)((tmp1 - s1) / 3);
   if (nv == -1 || nv >= 19 + 21)
      return ret;

   /* single element composition  */
   _len = strlcpy(utf8, pcur, sizeof(utf8));
   strlcpy(utf8 + _len, padd, sizeof(utf8) - _len);

   if ((tmp2 = strstr(cc1, utf8)))
   {
      *((unsigned*)padd) = *((unsigned*)(tmp2 + 6)) & 0xffffff;
      return 0;
   }
   else if ((tmp2 = strstr(cc2, utf8)))
   {
      *((unsigned*)padd) = *((unsigned*)(tmp2 + 6)) & 0xffffff;
      return 0;
   }
   if (tmp2 && tmp2 < cc2 + sizeof(cc2) - 10)
   {
      *((unsigned*)padd) = *((unsigned*)(tmp2 + 6)) & 0xffffff;
      return 0;
   }

   if (c1 >= 19)
      return ret;

   if (c1 == -1)
   {
      int tv = ((pcur[0] & 0x0f) << 12) | ((pcur[1] & 0x3f) << 6) | (pcur[2] & 0x03f);
      tv     = tv  - 0xac00;
      c1     = tv  / (28 * 21);
      c2     = (tv % (28 * 21)) / 28;
      c3     = (tv % (28));
      if (c1 < 0 || c1 >= 19 || c2 < 0 || c2 > 21 || c3 < 0 || c3 > 28)
         return ret;
   }

   if (c1 == -1 && c2 == -1 && c3 == 0)
      return ret;

   if (c2 == -1 && c3 == 0)
   {
      /* 2nd element attach */
      if (nv < 19)
         return ret;
      c2  = nv - 19;
   }
   else
      if (c2 >= 0 && c3 == 0)
      {
         if (nv < 19)
         {
            /* 3rd element attach */
            if (!(tmp1 = strstr(s1 + (19 + 21) * 3, padd)))
               return ret;
            c3 = (int)((tmp1 - s1) / 3 - 19 - 21);
         }
         else
         {
            /* 2nd element transform */
            strlcpy(utf8, s1 + (19 + c2) * 3, 4);
            utf8[3] = 0;
            strlcat(utf8, padd, sizeof(utf8));
            if (    !(tmp2 = strstr(cc2, utf8))
                  || (tmp2 >= cc2 + sizeof(cc2) - 10))
               return ret;
            strlcpy(utf8, tmp2 + 6, 4);
            utf8[3] = 0;
            if (!(tmp1 = strstr(s1 + (19) * 3, utf8)))
               return ret;
            c2 = (int)((tmp1 - s1) / 3 - 19);
         }
      }
      else
         if (c3 > 0)
         {
            strlcpy(utf8, s1 + (19 + 21 + c3) * 3, 4);
            utf8[3] = 0;
            if (nv < 19)
            {
               /* 3rd element transform */
               strlcat(utf8, padd, sizeof(utf8));
               if (    !(tmp2 = strstr(cc3, utf8))
                     || (tmp2 >= cc3 + sizeof(cc3) - 10))
                     return ret;
               strlcpy(utf8, tmp2 + 6, 4);
               utf8[3] = 0;
               if (!(tmp1 = strstr(s1 + (19 + 21) * 3, utf8)))
                  return ret;
               c3 = (int)((tmp1 - s1) / 3 - 19 - 21);
            }
            else
            {
               int tv = 0;
               if ((tmp2 = strstr(cc3, utf8)))
                  tv = (tmp2 - cc3) % 10;
               if (tv == 6)
               {
                  /*  complex 3rd element -> disassemble */
                  strlcpy(utf8, tmp2 - 3, 4);
                  if (!(tmp1 = strstr(s1, utf8)))
                     return ret;
                  tv = (int)((tmp1 - s1) / 3);
                  strlcpy(utf8, tmp2 - 6, 4);
                  if (!(tmp1 = strstr(s1 + (19 + 21) * 3, utf8)))
                     return ret;
                  c3 = (int)((tmp1 - s1) / 3 - 19 - 21);
               }
               else
               {
                  if (!(tmp1 = strstr(s1, utf8)) || (tmp1 - s1) >= 19 * 3)
                     return ret;
                  tv = (int)((tmp1 - s1) / 3);
                  c3 = 0;
               }
               *((unsigned*)padd) = get_kr_utf8(tv, nv - 19, 0);
               return get_kr_utf8(c1, c2, c3);
            }
         }
         else
            return ret;
   *((unsigned*)padd) = get_kr_utf8(c1, c2, c3);
   return 0;
}
#endif

/**
 * input_keyboard_line_event:
 * @state                    : Input keyboard line handle.
 * @character                : Inputted character.
 *
 * Called on every keyboard character event.
 *
 * Returns: true (1) on success, otherwise false (0).
 **/
bool input_keyboard_line_event(
      input_driver_state_t *input_st,
      input_keyboard_line_t *state, uint32_t character)
{
   char array[2];
   bool            ret         = false;
   const char            *word = NULL;
   char            c           = (character >= 128) ? '?' : character;
#ifdef HAVE_LANGEXTRA
   static uint32_t composition = 0;
   /* reset composition, when edit box is opened. */
   if (state->size == 0)
      composition = 0;
   /* reset composition, when 1 byte(=english) input */
   if (character && character < 0xff)
      composition = 0;
   if (IS_COMPOSITION(character) || IS_END_COMPOSITION(character))
   {
      size_t _len = strlen((char*)&composition);
      if (composition && state->buffer && state->size >= _len && state->ptr >= _len)
      {
         memmove(state->buffer + state->ptr - _len, state->buffer + state->ptr, _len + 1);
         state->ptr  -= _len;
         state->size -= _len;
      }
      if (IS_COMPOSITION_KR(character) && composition)
      {
         unsigned new_comp;
         character   = character & 0xffffff;
         new_comp    = get_kr_composition((char*)&composition, (char*)&character);
         if (new_comp)
            input_keyboard_line_append(state, (char*)&new_comp, 3);
         composition = character;
      }
      else
      {
         if (IS_END_COMPOSITION(character))
            composition = 0;
         else
            composition = character & 0xffffff;
         character     &= 0xffffff;
      }
      if (_len && composition == 0)
         word = state->buffer;
      if (character)
         input_keyboard_line_append(state, (char*)&character, strlen((char*)&character));
      word = state->buffer;
   }
   else
#endif

   /* Treat extended chars as ? as we cannot support
    * printable characters for unicode stuff. */
   if (c == '\r' || c == '\n')
   {
      state->cb(state->userdata, state->buffer);

      array[0] = c;
      array[1] = 0;

      ret      = true;
      word     = array;
   }
   else if (c == '\b' || c == '\x7f') /* 0x7f is ASCII for del */
   {
      if (state->ptr)
      {
         unsigned i;

         for (i = 0; i < input_st->osk_last_codepoint_len; i++)
         {
            memmove(state->buffer + state->ptr - 1,
                  state->buffer + state->ptr,
                  state->size - state->ptr + 1);
            state->ptr--;
            state->size--;
         }

         word     = state->buffer;
      }
   }
   else if (ISPRINT(c))
   {
      /* Handle left/right here when suitable */
      char *newbuf = (char*)
         realloc(state->buffer, state->size + 2);
      if (!newbuf)
         return false;

      memmove(newbuf + state->ptr + 1,
            newbuf + state->ptr,
            state->size - state->ptr + 1);
      newbuf[state->ptr] = c;
      state->ptr++;
      state->size++;
      newbuf[state->size] = '\0';

      state->buffer = newbuf;

      array[0] = c;
      array[1] = 0;

      word     = array;
   }

   /* OSK - update last character */
   if (word)
      osk_update_last_codepoint(
            &input_st->osk_last_codepoint,
            &input_st->osk_last_codepoint_len,
            word);

   return ret;
}

void *input_driver_init_wrap(input_driver_t *input, const char *name)
{
   void *ret                   = NULL;
   if (!input)
      return NULL;
   if ((ret = input->init(name)))
   {
      input_driver_init_joypads();
      return ret;
   }
   return NULL;
}

bool input_driver_find_driver(
      settings_t *settings,
      const char *prefix,
      bool verbosity_enabled)
{
   int i                = (int)driver_find_index(
         "input_driver",
         settings->arrays.input_driver);

   if (i >= 0)
   {
      input_driver_st.current_driver = (input_driver_t*)input_drivers[i];
      RARCH_LOG("[Input] Found %s: \"%s\".\n", prefix,
            input_driver_st.current_driver->ident);
   }
   else
   {
      input_driver_t *tmp = NULL;
      if (verbosity_enabled)
      {
         unsigned d;
         RARCH_ERR("Couldn't find any %s named \"%s\"\n", prefix,
               settings->arrays.input_driver);
         RARCH_LOG_OUTPUT("Available %ss are:\n", prefix);
         for (d = 0; input_drivers[d]; d++)
            RARCH_LOG_OUTPUT("\t%s\n", input_drivers[d]->ident);
         RARCH_WARN("Going to default to first %s...\n", prefix);
      }

      tmp = (input_driver_t*)input_drivers[0];
      if (!tmp)
         return false;
      input_driver_st.current_driver = tmp;
   }

   return true;
}

/**
 * Sets the sensor state. Used by RETRO_ENVIRONMENT_GET_SENSOR_INTERFACE.
 *
 * @param port
 * @param action
 * @param rate
 *
 * @return true if the sensor state has been successfully set
 **/
bool input_set_sensor_state(unsigned port,
      enum retro_sensor_action action, unsigned rate)
{
   bool input_sensors_enable   = config_get_ptr()->bools.input_sensors_enable;
   return input_driver_set_sensor(
      port, input_sensors_enable, action, rate);
}

const char *joypad_driver_name(unsigned i)
{
   if (!input_driver_st.primary_joypad || !input_driver_st.primary_joypad->name)
      return NULL;
   return input_driver_st.primary_joypad->name(i);
}

void joypad_driver_reinit(void *data, const char *joypad_driver_name)
{
   if (input_driver_st.primary_joypad)
   {
      const input_device_driver_t *tmp  = input_driver_st.primary_joypad;
      input_driver_st.primary_joypad    = NULL;
      /* Run poll one last time in order to detect disconnections */
      tmp->poll();
      tmp->destroy();
   }
#ifdef HAVE_MFI
   if (input_driver_st.secondary_joypad)
   {
      const input_device_driver_t *tmp  = input_driver_st.secondary_joypad;
      input_driver_st.secondary_joypad  = NULL;
      tmp->poll();
      tmp->destroy();
   }
#endif
   if (!input_driver_st.primary_joypad)
      input_driver_st.primary_joypad    = input_joypad_init_driver(joypad_driver_name, data);
#if 0
   if (!input_driver_st.secondary_joypad)
      input_driver_st.secondary_joypad  = input_joypad_init_driver("mfi", data);
#endif
}

/**
 * Retrieves the sensor state associated with the provided port and ID.
 *
 * @param port
 * @param id    Sensor ID
 *
 * @return The current state associated with the port and ID as a float
 **/
float input_get_sensor_state(unsigned port, unsigned id)
{
   bool input_sensors_enable              = config_get_ptr()->bools.input_sensors_enable;
   return input_driver_get_sensor(port, input_sensors_enable, id);
}

/**
 * Sets the rumble state. Used by RETRO_ENVIRONMENT_GET_RUMBLE_INTERFACE.
 *
 * @param port      User number.
 * @param effect    Rumble effect.
 * @param strength  Strength of rumble effect.
 *
 * @return true if the rumble state has been successfully set
 **/
bool input_set_rumble_state(unsigned port,
      enum retro_rumble_effect effect, uint16_t strength)
{
   settings_t *settings                   = config_get_ptr();
   unsigned joy_idx                       = settings->uints.input_joypad_index[port];
   uint16_t scaled_strength               = strength;

   /* If gain setting is not supported, do software gain control */
   if (input_driver_st.primary_joypad)
   {
      if (!input_driver_st.primary_joypad->set_rumble_gain)
      {
         unsigned rumble_gain = settings->uints.input_rumble_gain;
         scaled_strength      = (rumble_gain * strength) / 100.0;
      }
   }

   return input_driver_set_rumble(
      port, joy_idx, effect, scaled_strength);
}

/**
 * Sets the rumble gain. Used by MENU_ENUM_LABEL_INPUT_RUMBLE_GAIN.
 *
 * @param gain  Rumble gain, 0-100 [%]
 *
 * @return true if the rumble gain has been successfully set
 **/
bool input_set_rumble_gain(unsigned gain)
{
   return (input_driver_set_rumble_gain(
            gain, config_get_ptr()->uints.input_max_users));
}

uint64_t input_driver_get_capabilities(void)
{
   if (     !input_driver_st.current_driver
         || !input_driver_st.current_driver->get_capabilities)
      return 0;
   return input_driver_st.current_driver->get_capabilities(input_driver_st.current_data);
}

void input_driver_init_joypads(void)
{
   settings_t                   *settings    = config_get_ptr();
   if (!input_driver_st.primary_joypad)
      input_driver_st.primary_joypad        = input_joypad_init_driver(
         settings->arrays.input_joypad_driver,
         input_driver_st.current_data);
#if 0
   if (!input_driver_st.secondary_joypad)
      input_driver_st.secondary_joypad      = input_joypad_init_driver(
            "mfi",
            input_driver_st.current_data);
#endif
}

bool input_key_pressed(int key, bool keyboard_pressed)
{
   /* If a keyboard key is pressed then immediately return
    * true, otherwise call button_is_pressed to determine
    * if the input comes from another input device */
   if (!(
            (key < RARCH_BIND_LIST_END)
            && keyboard_pressed
        )
      )
   {
      const input_device_driver_t
         *joypad                     = (const input_device_driver_t*)
         input_driver_st.primary_joypad;
      const uint64_t bind_joykey     = input_config_binds[0][key].joykey;
      const uint64_t bind_joyaxis    = input_config_binds[0][key].joyaxis;
      const uint64_t autobind_joykey = input_autoconf_binds[0][key].joykey;
      const uint64_t autobind_joyaxis= input_autoconf_binds[0][key].joyaxis;
      uint16_t port                  = 0;
      float axis_threshold           = config_get_ptr()->floats.input_axis_threshold;
      const uint64_t joykey          = (bind_joykey != NO_BTN)
         ? bind_joykey  : autobind_joykey;
      const uint64_t joyaxis         = (bind_joyaxis != AXIS_NONE)
         ? bind_joyaxis : autobind_joyaxis;

      if ((uint16_t)joykey != NO_BTN && joypad->button(
               port, (uint16_t)joykey))
         return true;
      if (joyaxis != AXIS_NONE &&
            ((float)abs(joypad->axis(port, (uint32_t)joyaxis))
             / 0x8000) > axis_threshold)
         return true;
      return false;
   }
   return true;
}

bool video_driver_init_input(
      input_driver_t *tmp,
      settings_t *settings,
      bool verbosity_enabled)
{
   void              *new_data    = NULL;
   input_driver_t         **input = &input_driver_st.current_driver;
   if (*input)
#if HAVE_TEST_DRIVERS
      if (strcmp(settings->arrays.input_driver, "test") != 0)
         /* Test driver not in use, keep selected driver */
         return true;
      else if (string_is_empty(settings->paths.test_input_file_general))
      {
         RARCH_LOG("[Input] Test input driver selected, but no input file provided - falling back.\n");
         return true;
      }
      else
         RARCH_LOG("[Video] Graphics driver initialized an input driver, but ignoring it as test input driver is in use.\n");
#else
      return true;
#endif
   else
      /* Video driver didn't provide an input driver,
       * so we use configured one. */
      RARCH_LOG("[Video] Graphics driver did not initialize an input driver."
         " Attempting to pick a suitable driver.\n");

   if (tmp)
      *input = tmp;
   else
   {
      if (!(input_driver_find_driver(
            settings, "input driver",
            verbosity_enabled)))
      {
         RARCH_ERR("[Video] Cannot find input driver. Exiting...\n");
         return false;
      }
   }

   /* This should never really happen as tmp (driver.input) is always
    * found before this in find_driver_input(), or we have aborted
    * in a similar fashion anyways. */
   if (     !input_driver_st.current_driver
         || !(new_data = input_driver_init_wrap(
               input_driver_st.current_driver,
               settings->arrays.input_joypad_driver)))
   {
      RARCH_ERR("[Video] Cannot initialize input driver. Exiting...\n");
      return false;
   }

   input_driver_st.current_data = new_data;

   return true;
}

bool input_driver_grab_mouse(void)
{
   if (!input_driver_st.current_driver || !input_driver_st.current_driver->grab_mouse)
      return false;
   input_driver_st.current_driver->grab_mouse(
         input_driver_st.current_data, true);
   return true;
}

bool input_driver_ungrab_mouse(void)
{
   if (!input_driver_st.current_driver || !input_driver_st.current_driver->grab_mouse)
      return false;
   input_driver_st.current_driver->grab_mouse(input_driver_st.current_data, false);
   return true;
}

void input_config_reset(void)
{
   unsigned i;
   input_driver_state_t *input_st = &input_driver_st;

   memcpy(input_config_binds[0], retro_keybinds_1, sizeof(retro_keybinds_1));

   for (i = 1; i < MAX_USERS; i++)
      memcpy(input_config_binds[i], retro_keybinds_rest,
            sizeof(retro_keybinds_rest));

   for (i = 0; i < MAX_USERS; i++)
   {
      /* Note: Don't use input_config_clear_device_name()
       * here, since this will re-index devices each time
       * (not required - we are setting all 'name indices'
       * to zero manually) */
      input_st->input_device_info[i].name[0]          = '\0';
      input_st->input_device_info[i].display_name[0]  = '\0';
      input_st->input_device_info[i].config_name[0]   = '\0';
      input_st->input_device_info[i].joypad_driver[0] = '\0';
      input_st->input_device_info[i].vid              = 0;
      input_st->input_device_info[i].pid              = 0;
      input_st->input_device_info[i].autoconfigured   = false;
      input_st->input_device_info[i].name_index       = 0;

      input_config_reset_autoconfig_binds(i);

      input_st->libretro_input_binds[i] = (const retro_keybind_set *)&input_config_binds[i];
   }
}

void input_config_set_device(unsigned port, unsigned id)
{
   settings_t        *settings = config_get_ptr();
   if (settings && (port < MAX_USERS))
      configuration_set_uint(settings,
            settings->uints.input_libretro_device[port], id);
}

unsigned input_config_get_device(unsigned port)
{
   settings_t             *settings = config_get_ptr();
   if (settings && (port < MAX_USERS))
      return settings->uints.input_libretro_device[port];
   return RETRO_DEVICE_NONE;
}

const struct retro_keybind *input_config_get_bind_auto(
      unsigned port, unsigned id)
{
   settings_t        *settings = config_get_ptr();
   unsigned        joy_idx     = settings->uints.input_joypad_index[port];

   if (joy_idx < MAX_USERS)
      return &input_autoconf_binds[joy_idx][id];
   return NULL;
}

unsigned *input_config_get_device_ptr(unsigned port)
{
   settings_t             *settings = config_get_ptr();
   if (settings && (port < MAX_USERS))
      return &settings->uints.input_libretro_device[port];
   return NULL;
}

/* Adds an index to devices with the same name,
 * so they can be uniquely identified in the
 * frontend */
static void input_config_reindex_device_names(input_driver_state_t *input_st)
{
   unsigned i;
   unsigned j;
   unsigned name_index;

   /* Reset device name indices */
   for (i = 0; i < MAX_INPUT_DEVICES; i++)
      input_st->input_device_info[i].name_index       = 0;

   /* Scan device names */
   for (i = 0; i < MAX_INPUT_DEVICES; i++)
   {
      const char *device_name = input_config_get_device_name(i);

      /* If current device name is empty, or a non-zero
       * name index has already been assigned, continue
       * to the next device */
      if (
               string_is_empty(device_name)
            || input_st->input_device_info[i].name_index != 0)
         continue;

      /* > Uniquely named devices have a name index
       *   of 0
       * > Devices with the same name have a name
       *   index starting from 1 */
      name_index = 1;

      /* Loop over all devices following the current
       * selection */
      for (j = i + 1; j < MAX_INPUT_DEVICES; j++)
      {
         const char *next_device_name = input_config_get_device_name(j);

         if (string_is_empty(next_device_name))
            continue;

         /* Check if names match */
         if (string_is_equal(device_name, next_device_name))
         {
            /* If this is the first match, set a starting
             * index for the current device selection */
            if (input_st->input_device_info[i].name_index == 0)
               input_st->input_device_info[i].name_index       = name_index++;

            /* Set name index for the next device
             * (will keep incrementing as more matches
             *  are found) */
            input_st->input_device_info[j].name_index          = name_index++;
         }
      }
   }
}

const char *input_config_get_device_name(unsigned port)
{
   input_driver_state_t *input_st = &input_driver_st;
   if (string_is_empty(input_st->input_device_info[port].name))
      return NULL;
   return input_st->input_device_info[port].name;
}

const char *input_config_get_device_display_name(unsigned port)
{
   input_driver_state_t *input_st = &input_driver_st;
   if (string_is_empty(input_st->input_device_info[port].display_name))
      return NULL;
   return input_st->input_device_info[port].display_name;
}

const char *input_config_get_device_config_name(unsigned port)
{
   input_driver_state_t *input_st = &input_driver_st;
   if (string_is_empty(input_st->input_device_info[port].config_name))
      return NULL;
   return input_st->input_device_info[port].config_name;
}

const char *input_config_get_device_joypad_driver(unsigned port)
{
   input_driver_state_t *input_st = &input_driver_st;
   if (string_is_empty(input_st->input_device_info[port].joypad_driver))
      return NULL;
   return input_st->input_device_info[port].joypad_driver;
}

uint16_t input_config_get_device_vid(unsigned port)
{
   input_driver_state_t *input_st = &input_driver_st;
   return input_st->input_device_info[port].vid;
}

uint16_t input_config_get_device_pid(unsigned port)
{
   input_driver_state_t *input_st = &input_driver_st;
   return input_st->input_device_info[port].pid;
}

bool input_config_get_device_autoconfigured(unsigned port)
{
   input_driver_state_t *input_st = &input_driver_st;
   return input_st->input_device_info[port].autoconfigured;
}

unsigned input_config_get_device_name_index(unsigned port)
{
   input_driver_state_t *input_st = &input_driver_st;
   return input_st->input_device_info[port].name_index;
}

/* TODO/FIXME: This is required by linuxraw_joypad.c
 * and parport_joypad.c. These input drivers should
 * be refactored such that this dubious low-level
 * access is not required */
char *input_config_get_device_name_ptr(unsigned port)
{
   input_driver_state_t *input_st = &input_driver_st;
   return input_st->input_device_info[port].name;
}

size_t input_config_get_device_name_size(unsigned port)
{
   input_driver_state_t *input_st = &input_driver_st;
   return sizeof(input_st->input_device_info[port].name);
}

void input_config_set_device_name(unsigned port, const char *name)
{
   input_driver_state_t *input_st = &input_driver_st;
   if (string_is_empty(name))
      return;

   strlcpy(input_st->input_device_info[port].name, name,
         sizeof(input_st->input_device_info[port].name));

   input_config_reindex_device_names(input_st);
}

void input_config_set_device_display_name(unsigned port, const char *name)
{
   input_driver_state_t *input_st = &input_driver_st;
   if (!string_is_empty(name))
      strlcpy(input_st->input_device_info[port].display_name, name,
            sizeof(input_st->input_device_info[port].display_name));
}

void input_config_set_device_config_name(unsigned port, const char *name)
{
   input_driver_state_t *input_st = &input_driver_st;
   if (!string_is_empty(name))
      strlcpy(input_st->input_device_info[port].config_name, name,
            sizeof(input_st->input_device_info[port].config_name));
}

void input_config_set_device_joypad_driver(unsigned port, const char *driver)
{
   input_driver_state_t *input_st = &input_driver_st;
   if (!string_is_empty(driver))
      strlcpy(input_st->input_device_info[port].joypad_driver, driver,
            sizeof(input_st->input_device_info[port].joypad_driver));
}

void input_config_set_device_vid(unsigned port, uint16_t vid)
{
   input_driver_state_t *input_st        = &input_driver_st;
   input_st->input_device_info[port].vid = vid;
}

void input_config_set_device_pid(unsigned port, uint16_t pid)
{
   input_driver_state_t *input_st        = &input_driver_st;
   input_st->input_device_info[port].pid = pid;
}

void input_config_set_device_autoconfigured(unsigned port, bool autoconfigured)
{
   input_driver_state_t *input_st = &input_driver_st;
   input_st->input_device_info[port].autoconfigured = autoconfigured;
}

void input_config_set_device_name_index(unsigned port, unsigned name_index)
{
   input_driver_state_t *input_st = &input_driver_st;
   input_st->input_device_info[port].name_index = name_index;
}

void input_config_clear_device_name(unsigned port)
{
   input_driver_state_t *input_st = &input_driver_st;
   input_st->input_device_info[port].name[0] = '\0';
   input_config_reindex_device_names(input_st);
}

void input_config_clear_device_display_name(unsigned port)
{
   input_driver_state_t *input_st = &input_driver_st;
   input_st->input_device_info[port].display_name[0] = '\0';
}

void input_config_clear_device_config_name(unsigned port)
{
   input_driver_state_t *input_st = &input_driver_st;
   input_st->input_device_info[port].config_name[0] = '\0';
}

void input_config_clear_device_joypad_driver(unsigned port)
{
   input_driver_state_t *input_st = &input_driver_st;
   input_st->input_device_info[port].joypad_driver[0] = '\0';
}

const char *input_config_get_mouse_display_name(unsigned port)
{
   input_driver_state_t *input_st = &input_driver_st;
   if (string_is_empty(input_st->input_mouse_info[port].display_name))
      return NULL;
   return input_st->input_mouse_info[port].display_name;
}

void input_config_set_mouse_display_name(unsigned port, const char *name)
{
   char name_ascii[NAME_MAX_LENGTH];
   input_driver_state_t *input_st = &input_driver_st;

   name_ascii[0] = '\0';

   /* Strip non-ASCII characters */
   if (!string_is_empty(name))
      string_copy_only_ascii(name_ascii, name);

   if (!string_is_empty(name_ascii))
      strlcpy(input_st->input_mouse_info[port].display_name, name_ascii,
            sizeof(input_st->input_mouse_info[port].display_name));
}

#ifdef HAVE_COMMAND
void input_driver_init_command(input_driver_state_t *input_st,
      settings_t *settings)
{
#ifdef HAVE_STDIN_CMD
   bool input_stdin_cmd_enable       = settings->bools.stdin_cmd_enable;

   if (input_stdin_cmd_enable)
   {
      input_driver_state_t *input_st = &input_driver_st;
      bool grab_stdin                =
         input_st->current_driver->grab_stdin &&
         input_st->current_driver->grab_stdin(input_st->current_data);
      if (grab_stdin)
      {
         RARCH_WARN("stdin command interface is desired, "
               "but input driver has already claimed stdin.\n"
               "Cannot use this command interface.\n");
      }
      else
      {
         input_st->command[0] = command_stdin_new();
         if (!input_st->command[0])
            RARCH_ERR("Failed to initialize the stdin command interface.\n");
      }
   }
#endif

   /* Initialize the network command interface */
#ifdef HAVE_NETWORK_CMD
   {
      bool input_network_cmd_enable = settings->bools.network_cmd_enable;
      if (input_network_cmd_enable)
      {
         unsigned network_cmd_port  = settings->uints.network_cmd_port;
         if (!(input_st->command[1] = command_network_new(network_cmd_port)))
            RARCH_ERR("Failed to initialize the network command interface.\n");
      }
   }
#endif

#if defined(HAVE_LAKKA)
   if (!(input_st->command[2] = command_uds_new()))
      RARCH_ERR("Failed to initialize the UDS command interface.\n");
#elif defined(EMSCRIPTEN)
   if (!(input_st->command[2] = command_emscripten_new()))
      RARCH_ERR("Failed to initialize the emscripten command interface.\n");
#endif
}

void input_driver_deinit_command(input_driver_state_t *input_st)
{
   int i;
   for (i = 0; i < (int)ARRAY_SIZE(input_st->command); i++)
   {
      if (input_st->command[i])
         input_st->command[i]->destroy(
            input_st->command[i]);

      input_st->command[i] = NULL;
    }
}
#endif

void input_game_focus_free(void)
{
   input_game_focus_state_t *game_focus_st = &input_driver_st.game_focus_state;

   /* Ensure that game focus mode is disabled */
   if (game_focus_st->enabled)
   {
      enum input_game_focus_cmd_type game_focus_cmd = GAME_FOCUS_CMD_OFF;
      command_event(CMD_EVENT_GAME_FOCUS_TOGGLE, &game_focus_cmd);
   }

   game_focus_st->enabled        = false;
   game_focus_st->core_requested = false;
}

void input_pad_connect(unsigned port, input_device_driver_t *driver)
{
   if (port >= MAX_USERS || !driver)
   {
      RARCH_ERR("[Input] input_pad_connect: Bad parameters.\n");
      return;
   }

   input_autoconfigure_connect(driver->name(port), NULL, driver->ident,
          port, 0, 0);
}

static bool input_keys_pressed_other_sources(
      input_driver_state_t *input_st,
      unsigned i,
      input_bits_t* p_new_state)
{
#ifdef HAVE_COMMAND
   int j;
   for (j = 0; j < (int)ARRAY_SIZE(input_st->command); j++)
      if ((i < RARCH_BIND_LIST_END) && input_st->command[j]
         && input_st->command[j]->state[i])
         return true;
#endif

#ifdef HAVE_OVERLAY
   if (               input_st->overlay_ptr &&
         ((BIT256_GET(input_st->overlay_ptr->overlay_state.buttons, i))))
      return true;
#endif

#ifdef HAVE_NETWORKGAMEPAD
   /* Only process key presses related to game input if using Remote RetroPad */
   if (i < RARCH_CUSTOM_BIND_LIST_END
         && input_st->remote
         && INPUT_REMOTE_KEY_PRESSED(input_st, i, 0))
      return true;
#endif

   return false;
}

/**
 * input_keys_pressed:
 *
 * Grab an input sample for this frame.
 */
static void input_keys_pressed(
      unsigned port,
      bool is_menu,
      unsigned input_hotkey_block_delay,
      input_bits_t *p_new_state,
      const retro_keybind_set *binds,
      const struct retro_keybind *binds_norm,
      const struct retro_keybind *binds_auto,
      const input_device_driver_t *joypad,
      const input_device_driver_t *sec_joypad,
      rarch_joypad_info_t *joypad_info,
      bool input_hotkey_device_merge)
{
   unsigned i;
   input_driver_state_t *input_st = &input_driver_st;
   bool block_hotkey[RARCH_BIND_LIST_END];
   bool libretro_hotkey_set       =
            binds[port][RARCH_ENABLE_HOTKEY].joykey                 != NO_BTN
         || binds[port][RARCH_ENABLE_HOTKEY].joyaxis                != AXIS_NONE
         || input_autoconf_binds[port][RARCH_ENABLE_HOTKEY].joykey  != NO_BTN
         || input_autoconf_binds[port][RARCH_ENABLE_HOTKEY].joyaxis != AXIS_NONE;
   bool keyboard_hotkey_set       =
         binds[port][RARCH_ENABLE_HOTKEY].key != RETROK_UNKNOWN;

   if (!binds)
      return;

   if (     input_hotkey_device_merge
         && (libretro_hotkey_set || keyboard_hotkey_set))
      libretro_hotkey_set = keyboard_hotkey_set = true;

   if (     binds[port][RARCH_ENABLE_HOTKEY].valid
         && CHECK_INPUT_DRIVER_BLOCK_HOTKEY(binds_norm, binds_auto))
   {
      if (input_state_wrap(
            input_st->current_driver,
            input_st->current_data,
            input_st->primary_joypad,
            sec_joypad,
            joypad_info,
            binds,
            (input_st->flags & INP_FLAG_KB_MAPPING_BLOCKED) ? true : false,
            port, RETRO_DEVICE_JOYPAD, 0,
            RARCH_ENABLE_HOTKEY))
      {
         if (input_st->input_hotkey_block_counter < input_hotkey_block_delay)
            input_st->input_hotkey_block_counter++;
         else
            input_st->flags |= INP_FLAG_BLOCK_LIBRETRO_INPUT;
      }
      else
      {
         input_st->input_hotkey_block_counter = 0;
         input_st->flags |= INP_FLAG_BLOCK_HOTKEY;
      }
   }

   if (!is_menu && binds[port][RARCH_GAME_FOCUS_TOGGLE].valid)
   {
      const struct retro_keybind *focus_binds_auto =
            &input_autoconf_binds[port][RARCH_GAME_FOCUS_TOGGLE];
      const struct retro_keybind *focus_normal     =
            &binds[port][RARCH_GAME_FOCUS_TOGGLE];

      /* Allows Game Focus toggle hotkey to still work
       * even though every hotkey is blocked */
      if (CHECK_INPUT_DRIVER_BLOCK_HOTKEY(focus_normal, focus_binds_auto))
      {
         if (input_state_wrap(
               input_st->current_driver,
               input_st->current_data,
               input_st->primary_joypad,
               sec_joypad,
               joypad_info,
               binds,
               (input_st->flags & INP_FLAG_KB_MAPPING_BLOCKED) ? true : false,
               port, RETRO_DEVICE_JOYPAD, 0,
               RARCH_GAME_FOCUS_TOGGLE))
            input_st->flags &= ~INP_FLAG_BLOCK_HOTKEY;
      }
   }

   {
      int32_t ret                 = 0;
      bool libretro_input_pressed = false;

      /* Check libretro input if emulated device type is active,
       * except device type must be always active in menu. */
      if (     !(input_st->flags & INP_FLAG_BLOCK_LIBRETRO_INPUT)
            && !(!is_menu && !input_config_get_device(port)))
         ret = input_state_wrap(
               input_st->current_driver,
               input_st->current_data,
               input_st->primary_joypad,
               sec_joypad,
               joypad_info,
               binds,
               (input_st->flags & INP_FLAG_KB_MAPPING_BLOCKED) ? true : false,
               port, RETRO_DEVICE_JOYPAD, 0,
               RETRO_DEVICE_ID_JOYPAD_MASK);

      for (i = 0; i < RARCH_FIRST_CUSTOM_BIND; i++)
      {
         if (     (ret & (UINT64_C(1) << i))
               || input_keys_pressed_other_sources(input_st, i, p_new_state))
         {
            BIT256_SET_PTR(p_new_state, i);
            libretro_input_pressed = true;
         }
      }

      if (!libretro_input_pressed)
      {
         /* Ignore keyboard menu toggle button and check
          * joypad menu toggle button for pressing
          * it without 'enable_hotkey', because Guide button
          * is not part of the usual buttons. */
         i = RARCH_MENU_TOGGLE;

         if (!(binds[port][i].valid
               && input_state_wrap(
                     input_st->current_driver,
                     input_st->current_data,
                     input_st->primary_joypad,
                     sec_joypad,
                     joypad_info,
                     binds,
                     (input_st->flags & INP_FLAG_KB_MAPPING_BLOCKED) ? true : false,
                     port, RETRO_DEVICE_KEYBOARD, 0,
                     input_config_binds[port][i].key)))
         {
            bool bit_pressed = binds[port][i].valid
                  && input_state_wrap(
                        input_st->current_driver,
                        input_st->current_data,
                        input_st->primary_joypad,
                        sec_joypad,
                        joypad_info,
                        binds,
                        (input_st->flags & INP_FLAG_KB_MAPPING_BLOCKED) ? true : false,
                        port, RETRO_DEVICE_JOYPAD, 0, i);

            if (
                     bit_pressed
                  || BIT64_GET(lifecycle_state, i)
                  || input_keys_pressed_other_sources(input_st, i, p_new_state))
            {
               BIT256_SET_PTR(p_new_state, i);
            }
         }
      }
   }

   /* Hotkeys are only relevant for first port */
   if (port > 0)
      return;

   /* Check hotkeys to block keyboard and joypad hotkeys separately.
    * This looks complicated because hotkeys must be unblocked based
    * on the device type depending if 'enable_hotkey' is set or not.. */
   if (     input_st->flags & INP_FLAG_BLOCK_HOTKEY
         && (libretro_hotkey_set && keyboard_hotkey_set))
   {
      /* Block everything when hotkey bind exists for both device types */
      for (i = RARCH_FIRST_META_KEY; i < RARCH_BIND_LIST_END; i++)
         block_hotkey[i] = true;
   }
   else if (input_st->flags & INP_FLAG_BLOCK_HOTKEY
         && (!libretro_hotkey_set || !keyboard_hotkey_set))
   {
      /* Block selectively when hotkey bind exists for either device type */
      for (i = RARCH_FIRST_META_KEY; i < RARCH_BIND_LIST_END; i++)
      {
         bool keyboard_hotkey_pressed = false;
         bool libretro_hotkey_pressed = false;

         /* Default */
         block_hotkey[i]              = true;

         /* No 'enable_hotkey' in joypad */
         if (!libretro_hotkey_set)
         {
            if (     binds[port][i].joykey  != NO_BTN
                  || binds[port][i].joyaxis != AXIS_NONE)
            {
               /* Allow blocking if keyboard hotkey is pressed */
               if (input_state_wrap(
                     input_st->current_driver,
                     input_st->current_data,
                     input_st->primary_joypad,
                     sec_joypad,
                     joypad_info,
                     binds,
                     (input_st->flags & INP_FLAG_KB_MAPPING_BLOCKED) ? true : false,
                     port, RETRO_DEVICE_KEYBOARD, 0,
                     input_config_binds[port][i].key))
               {
                  keyboard_hotkey_pressed = true;

                  /* Always block */
                  block_hotkey[i] = true;
               }

               /* Deny blocking if joypad hotkey is pressed */
               if (input_state_wrap(
                     input_st->current_driver,
                     input_st->current_data,
                     input_st->primary_joypad,
                     sec_joypad,
                     joypad_info,
                     binds,
                     (input_st->flags & INP_FLAG_KB_MAPPING_BLOCKED) ? true : false,
                     port, RETRO_DEVICE_JOYPAD, 0,
                     i))
               {
                  libretro_hotkey_pressed = true;

                  /* Only deny block if keyboard is not pressed */
                  if (!keyboard_hotkey_pressed)
                     block_hotkey[i] = false;
               }
            }
         }

         /* No 'enable_hotkey' in keyboard */
         if (!keyboard_hotkey_set)
         {
            if (binds[port][i].key != RETROK_UNKNOWN)
            {
               /* Deny blocking if keyboard hotkey is pressed */
               if (input_state_wrap(
                     input_st->current_driver,
                     input_st->current_data,
                     input_st->primary_joypad,
                     sec_joypad,
                     joypad_info,
                     binds,
                     (input_st->flags & INP_FLAG_KB_MAPPING_BLOCKED) ? true : false,
                     port, RETRO_DEVICE_KEYBOARD, 0,
                     input_config_binds[port][i].key))
               {
                  keyboard_hotkey_pressed = true;

                  /* Only deny block if joypad is not pressed */
                  if (!libretro_hotkey_pressed)
                     block_hotkey[i] = false;
               }

               /* Allow blocking if joypad hotkey is pressed */
               if (input_state_wrap(
                     input_st->current_driver,
                     input_st->current_data,
                     input_st->primary_joypad,
                     sec_joypad,
                     joypad_info,
                     binds,
                     (input_st->flags & INP_FLAG_KB_MAPPING_BLOCKED) ? true : false,
                     port, RETRO_DEVICE_JOYPAD, 0,
                     i))
               {

                  /* Only block if keyboard is not pressed */
                  if (!keyboard_hotkey_pressed)
                     block_hotkey[i] = true;
               }
            }
         }
      }
   }
   else
   {
      /* Clear everything */
      for (i = RARCH_FIRST_META_KEY; i < RARCH_BIND_LIST_END; i++)
         block_hotkey[i] = false;
   }

   {
      for (i = RARCH_FIRST_META_KEY; i < RARCH_BIND_LIST_END; i++)
      {
         bool other_pressed = input_keys_pressed_other_sources(input_st, i, p_new_state);
         bool bit_pressed   = binds[port][i].valid
               && input_state_wrap(
                     input_st->current_driver,
                     input_st->current_data,
                     input_st->primary_joypad,
                     sec_joypad,
                     joypad_info,
                     binds,
                     (input_st->flags & INP_FLAG_KB_MAPPING_BLOCKED) ? true : false,
                     port, RETRO_DEVICE_JOYPAD, 0,
                     i);

         if (     bit_pressed
               || other_pressed
               || BIT64_GET(lifecycle_state, i))
         {
            if (libretro_hotkey_set || keyboard_hotkey_set)
            {
               /* Do not block "other source" (input overlay) presses */
               if (block_hotkey[i] && !other_pressed)
                  continue;
            }

            BIT256_SET_PTR(p_new_state, i);

            /* Ignore all other hotkeys if menu toggle is pressed */
            if (i == RARCH_MENU_TOGGLE)
               break;
         }
      }
   }
}

#ifdef HAVE_BSV_MOVIE
/* Forward declaration */
void bsv_movie_free(bsv_movie_t*);

void bsv_movie_enqueue(input_driver_state_t *input_st,
      bsv_movie_t * state, enum bsv_flags flags)
{
   if (input_st->bsv_movie_state_next_handle)
      bsv_movie_free(input_st->bsv_movie_state_next_handle);
   input_st->bsv_movie_state_next_handle    = state;
   input_st->bsv_movie_state.flags          = flags;
}

void bsv_movie_deinit(input_driver_state_t *input_st)
{
   if (input_st->bsv_movie_state_handle)
      bsv_movie_free(input_st->bsv_movie_state_handle);
   input_st->bsv_movie_state_handle = NULL;
}

void bsv_movie_deinit_full(input_driver_state_t *input_st)
{
   bsv_movie_deinit(input_st);
   if (input_st->bsv_movie_state_next_handle)
      bsv_movie_free(input_st->bsv_movie_state_next_handle);
   input_st->bsv_movie_state_next_handle = NULL;
}

void bsv_movie_frame_rewind(void)
{
   input_driver_state_t *input_st = &input_driver_st;
   bsv_movie_t         *handle    = input_st->bsv_movie_state_handle;
   bool recording = (input_st->bsv_movie_state.flags
         & BSV_FLAG_MOVIE_RECORDING) ? true : false;

   if (!handle)
      return;

   handle->did_rewind = true;

   if (     ( (handle->frame_counter & handle->frame_mask) <= 1)
         && (handle->frame_pos[0] == handle->min_file_pos))
   {
      /* If we're at the beginning... */
      handle->frame_counter = 0;
      intfstream_seek(handle->file, (int)handle->min_file_pos, SEEK_SET);
      if (recording)
         intfstream_truncate(handle->file, (int)handle->min_file_pos);
      else
         bsv_movie_read_next_events(handle);
   }
   else
   {
      /* First time rewind is performed, the old frame is simply replayed.
       * However, playing back that frame caused us to read data, and push
       * data to the ring buffer.
       *
       * Successively rewinding frames, we need to rewind past the read data,
       * plus another. */
      uint8_t delta = handle->first_rewind ? 1 : 2;
      if (handle->frame_counter >= delta)
         handle->frame_counter -= delta;
      else
         handle->frame_counter = 0;
      intfstream_seek(handle->file, (int)handle->frame_pos[handle->frame_counter & handle->frame_mask], SEEK_SET);
      if (recording)
         intfstream_truncate(handle->file, (int)handle->frame_pos[handle->frame_counter & handle->frame_mask]);
      else
         bsv_movie_read_next_events(handle);
   }

   if (intfstream_tell(handle->file) <= (long)handle->min_file_pos)
   {
      /* We rewound past the beginning. */

      if (handle->playback)
      {
         intfstream_seek(handle->file, (int)handle->min_file_pos, SEEK_SET);
         bsv_movie_read_next_events(handle);
      }
      else
      {
         retro_ctx_serialize_info_t serial_info;

         /* If recording, we simply reset
          * the starting point. Nice and easy. */

         intfstream_seek(handle->file, 4 * sizeof(uint32_t), SEEK_SET);
         intfstream_truncate(handle->file, 4 * sizeof(uint32_t));

         serial_info.data = handle->state;
         serial_info.size = handle->state_size;

         core_serialize(&serial_info);

         intfstream_write(handle->file, handle->state, handle->state_size);
      }
   }
}

void bsv_movie_handle_push_key_event(bsv_movie_t *movie,
      uint8_t down, uint16_t mod, uint32_t code, uint32_t character)
{
   bsv_key_data_t data;
   data.down                                 = down;
   data._padding                             = 0;
   data.mod                                  = swap_if_big16(mod);
   data.code                                 = swap_if_big32(code);
   data.character                            = swap_if_big32(character);
   movie->key_events[movie->key_event_count] = data;
   movie->key_event_count++;
}

void bsv_movie_handle_push_input_event(bsv_movie_t *movie,
     uint8_t port, uint8_t dev, uint8_t idx, uint16_t id, int16_t val)
{
   bsv_input_data_t data;
   data.port                          = port;
   data.device                        = dev;
   data.idx                           = idx;
   data._padding                      = 0;
   data.id                            = swap_if_big16(id);
   data.value                         = swap_if_big16(val);
   movie->input_events[movie->input_event_count] = data;
   movie->input_event_count++;
}

bool bsv_movie_handle_read_input_event(bsv_movie_t *movie,
     uint8_t port, uint8_t dev, uint8_t idx, uint16_t id, int16_t* val)
{
   int i;
   /* if movie is old, just read two bytes and hope for the best */
   if (movie->version == 0)
   {
      int64_t read = intfstream_read(movie->file, val, 2);
      *val         = swap_if_big16(*val);
      return (read == 2);
   }
   for (i = 0; i < movie->input_event_count; i++)
   {
      bsv_input_data_t evt = movie->input_events[i];
      if (   (evt.port   == port)
          && (evt.device == dev)
          && (evt.idx    == idx)
          && (evt.id     == id))
      {
         *val = swap_if_big16(evt.value);
         return true;
      }
   }
   return false;
}

void bsv_movie_finish_rewind(input_driver_state_t *input_st)
{
   bsv_movie_t *handle    = input_st->bsv_movie_state_handle;
   if (!handle)
      return;
   handle->frame_counter += 1;
   handle->first_rewind   = !handle->did_rewind;
   handle->did_rewind     = false;
}

void bsv_movie_read_next_events(bsv_movie_t *handle)
{
   input_driver_state_t *input_st = input_state_get_ptr();
   if (intfstream_read(handle->file, &(handle->key_event_count), 1) == 1)
   {
      int i;
      for (i = 0; i < handle->key_event_count; i++)
      {
         if (intfstream_read(handle->file, &(handle->key_events[i]),
                  sizeof(bsv_key_data_t)) != sizeof(bsv_key_data_t))
         {
            /* Unnatural EOF */
            RARCH_ERR("[Replay] Keyboard replay ran out of keyboard inputs too early.\n");
            input_st->bsv_movie_state.flags |= BSV_FLAG_MOVIE_END;
            return;
         }
      }
   }
   else
   {
      RARCH_LOG("[Replay] EOF after buttons.\n");
      /* Natural(?) EOF */
      input_st->bsv_movie_state.flags |= BSV_FLAG_MOVIE_END;
      return;
   }
   if (handle->version > 0)
   {
      if (intfstream_read(handle->file, &(handle->input_event_count), 2) == 2)
      {
         int i;
         handle->input_event_count = swap_if_big16(handle->input_event_count);
         for (i = 0; i < handle->input_event_count; i++)
         {
            if (intfstream_read(handle->file, &(handle->input_events[i]),
                     sizeof(bsv_input_data_t)) != sizeof(bsv_input_data_t))
            {
               /* Unnatural EOF */
               RARCH_ERR("[Replay] Input replay ran out of inputs too early.\n");
               input_st->bsv_movie_state.flags |= BSV_FLAG_MOVIE_END;
               return;
            }
         }
      }
      else
      {
         RARCH_LOG("[Replay] EOF after inputs.\n");
         /* Natural(?) EOF */
         input_st->bsv_movie_state.flags |= BSV_FLAG_MOVIE_END;
         return;
      }
   }

   {
      uint8_t next_frame_type=REPLAY_TOKEN_INVALID;
      if (intfstream_read(handle->file, (uint8_t *)(&next_frame_type),
               sizeof(uint8_t)) != sizeof(uint8_t))
      {
         /* Unnatural EOF */
         RARCH_ERR("[Replay] Replay ran out of frames.\n");
         input_st->bsv_movie_state.flags |= BSV_FLAG_MOVIE_END;
         return;
      }
      else if (next_frame_type == REPLAY_TOKEN_CHECKPOINT_FRAME)
      {
         uint64_t size;
         uint8_t *st;
         retro_ctx_serialize_info_t serial_info;

         if (intfstream_read(handle->file, &(size),
             sizeof(uint64_t)) != sizeof(uint64_t))
         {
            RARCH_ERR("[Replay] Replay ran out of frames.\n");
            input_st->bsv_movie_state.flags |= BSV_FLAG_MOVIE_END;
            return;
         }

         size = swap_if_big64(size);
         st   = (uint8_t*)malloc(size);
         if (intfstream_read(handle->file, st, size) != (int64_t)size)
         {
            RARCH_ERR("[Replay] Replay checkpoint truncated.\n");
            input_st->bsv_movie_state.flags |= BSV_FLAG_MOVIE_END;
            free(st);
            return;
         }

         serial_info.data_const = st;
         serial_info.size       = size;
         core_unserialize(&serial_info);
         free(st);
      }
   }
}

void bsv_movie_next_frame(input_driver_state_t *input_st)
{
   unsigned checkpoint_interval   = config_get_ptr()->uints.replay_checkpoint_interval;
   /* if bsv_movie_state_next_handle is not null, deinit and set
      bsv_movie_state_handle to bsv_movie_state_next_handle and clear
      next_handle */
   bsv_movie_t         *handle    = input_st->bsv_movie_state_handle;
   if (input_st->bsv_movie_state_next_handle)
   {
      if (handle)
         bsv_movie_deinit(input_st);
      handle = input_st->bsv_movie_state_next_handle;
      input_st->bsv_movie_state_handle = handle;
      input_st->bsv_movie_state_next_handle = NULL;
   }

   if (!handle)
      return;
#ifdef HAVE_REWIND
   if (state_manager_frame_is_reversed())
      return;
#endif

   if (input_st->bsv_movie_state.flags & BSV_FLAG_MOVIE_RECORDING)
   {
      int i;
      uint16_t evt_count = swap_if_big16(handle->input_event_count);
      /* write key events, frame is over */
      intfstream_write(handle->file, &(handle->key_event_count), 1);
      for (i = 0; i < handle->key_event_count; i++)
         intfstream_write(handle->file, &(handle->key_events[i]),
               sizeof(bsv_key_data_t));
      /* Zero out key events when playing back or recording */
      handle->key_event_count = 0;
      /* write input events, frame is over */
      intfstream_write(handle->file, &evt_count, 2);
      for (i = 0; i < handle->input_event_count; i++)
         intfstream_write(handle->file, &(handle->input_events[i]),
               sizeof(bsv_input_data_t));
      /* Zero out input events when playing back or recording */
      handle->input_event_count = 0;

      /* Maybe record checkpoint */
      if (     (checkpoint_interval != 0)
            && (handle->frame_counter > 0)
            && (handle->frame_counter % (checkpoint_interval*60) == 0))
      {
         retro_ctx_serialize_info_t serial_info;
         uint8_t frame_tok = REPLAY_TOKEN_CHECKPOINT_FRAME;
         size_t _len       = core_serialize_size();
         uint64_t size     = swap_if_big64(_len);
         uint8_t *st       = (uint8_t*)malloc(_len);
         serial_info.data  = st;
         serial_info.size  = _len;
         core_serialize(&serial_info);
         /* "next frame is a checkpoint" */
         intfstream_write(handle->file, (uint8_t *)(&frame_tok), sizeof(uint8_t));
         intfstream_write(handle->file, &size, sizeof(uint64_t));
         intfstream_write(handle->file, st, _len);
         free(st);
      }
      else
      {
         uint8_t frame_tok = REPLAY_TOKEN_REGULAR_FRAME;
         /* write "next frame is not a checkpoint" */
         intfstream_write(handle->file, (uint8_t *)(&frame_tok), sizeof(uint8_t));
      }
   }

   if (input_st->bsv_movie_state.flags & BSV_FLAG_MOVIE_PLAYBACK)
      bsv_movie_read_next_events(handle);
   handle->frame_pos[handle->frame_counter & handle->frame_mask] = intfstream_tell(handle->file);
}

size_t replay_get_serialize_size(void)
{
   input_driver_state_t *input_st = &input_driver_st;
   if (input_st->bsv_movie_state.flags & (BSV_FLAG_MOVIE_RECORDING | BSV_FLAG_MOVIE_PLAYBACK))
      return sizeof(int32_t)+intfstream_tell(input_st->bsv_movie_state_handle->file);
   return 0;
}

bool replay_get_serialized_data(void* buffer)
{
   input_driver_state_t *input_st = &input_driver_st;
   bsv_movie_t *handle            = input_st->bsv_movie_state_handle;

   if (input_st->bsv_movie_state.flags & (BSV_FLAG_MOVIE_RECORDING | BSV_FLAG_MOVIE_PLAYBACK))
   {
      int64_t file_end        = intfstream_tell(handle->file);
      int64_t read_amt        = 0;
      long file_end_lil       = swap_if_big32(file_end);
      uint8_t *file_end_bytes = (uint8_t *)(&file_end_lil);
      uint8_t *buf            = buffer;
      buf[0]                  = file_end_bytes[0];
      buf[1]                  = file_end_bytes[1];
      buf[2]                  = file_end_bytes[2];
      buf[3]                  = file_end_bytes[3];
      buf                    += 4;
      intfstream_rewind(handle->file);
      read_amt                = intfstream_read(handle->file, (void *)buf, file_end);
      if (read_amt != file_end)
         RARCH_ERR("[Replay] Failed to write correct number of replay bytes into state file: %d / %d.\n",
               read_amt, file_end);
   }
   return true;
}

bool replay_set_serialized_data(void* buf)
{
   uint8_t *buffer                = buf;
   input_driver_state_t *input_st = &input_driver_st;
   bool playback                  = (input_st->bsv_movie_state.flags & BSV_FLAG_MOVIE_PLAYBACK)  ? true : false;
   bool recording                 = (input_st->bsv_movie_state.flags & BSV_FLAG_MOVIE_RECORDING) ? true : false;

   /* If there is no current replay, ignore this entirely.
      TODO/FIXME: Later, consider loading up the replay
      and allow the user to continue it?
      Or would that be better done from the replay hotkeys?
    */
   if (!(playback || recording))
      return true;

   if (!buffer)
   {
      if (recording)
      {
         const char *_msg = msg_hash_to_str(MSG_REPLAY_LOAD_STATE_FAILED_INCOMPAT);
         runloop_msg_queue_push(_msg, strlen(_msg), 1, 180, true, NULL,
               MESSAGE_QUEUE_ICON_DEFAULT, MESSAGE_QUEUE_CATEGORY_ERROR);
         RARCH_ERR("[Replay] Not from current recording.\n");
         return false;
      }

      if (playback)
      {
         const char *_msg = msg_hash_to_str(MSG_REPLAY_LOAD_STATE_HALT_INCOMPAT);
         runloop_msg_queue_push(_msg, sizeof(_msg), 1, 180, true, NULL,
               MESSAGE_QUEUE_ICON_DEFAULT, MESSAGE_QUEUE_CATEGORY_WARNING);
         RARCH_WARN("[Replay] Not compatible with replay.\n");
         movie_stop(input_st);
      }
   }
   else
   {
      /* TODO: should factor the next few lines away, magic numbers ahoy */
      uint32_t *header         = (uint32_t *)(buffer + sizeof(int32_t));
      int64_t *ident_spot      = (int64_t *)(header + 4);
      int64_t ident            = swap_if_big64(*ident_spot);

      if (ident == input_st->bsv_movie_state_handle->identifier) /* is compatible? */
      {
         int32_t loaded_len    = swap_if_big32(((int32_t *)buffer)[0]);
         int64_t handle_idx    = intfstream_tell(
               input_st->bsv_movie_state_handle->file);
         /* If the state is part of this replay, go back to that state
            and rewind/fast forward the replay.

            If the savestate movie is after the current replay
            length we can replace the current replay data with it,
            but if it's earlier we can rewind the replay to the
            savestate movie time point.

            This can truncate the current replay if we're in recording mode.
         */
         if (loaded_len > handle_idx)
         {
            /* TODO: Really, to be very careful, we should be
               checking that the events in the loaded state are the
               same up to handle_idx. Right? */
            intfstream_rewind(input_st->bsv_movie_state_handle->file);
            intfstream_write(input_st->bsv_movie_state_handle->file, buffer+sizeof(int32_t), loaded_len);
         }
         else
         {
            intfstream_seek(input_st->bsv_movie_state_handle->file, loaded_len, SEEK_SET);
            if (recording)
               intfstream_truncate(input_st->bsv_movie_state_handle->file, loaded_len);
         }
      }
      else
      {
         /* otherwise, if recording do not allow the load */
         if (recording)
         {
            const char *_msg = msg_hash_to_str(MSG_REPLAY_LOAD_STATE_FAILED_INCOMPAT);
            runloop_msg_queue_push(_msg, strlen(_msg), 1, 180, true, NULL,
                  MESSAGE_QUEUE_ICON_DEFAULT, MESSAGE_QUEUE_CATEGORY_ERROR);
            RARCH_ERR("[Replay] Not from current recording.\n");
            return false;
         }
         /* if in playback, halt playback and go to that state normally */
         if (playback)
         {
            const char *_msg = msg_hash_to_str(MSG_REPLAY_LOAD_STATE_HALT_INCOMPAT);
            runloop_msg_queue_push(_msg, strlen(_msg), 1, 180, true, NULL,
                  MESSAGE_QUEUE_ICON_DEFAULT, MESSAGE_QUEUE_CATEGORY_WARNING);
            RARCH_WARN("[Replay] Not compatible with replay.\n");
            movie_stop(input_st);
         }
      }
   }
   return true;
}
#endif

void input_driver_poll(void)
{
   size_t i, j;
   rarch_joypad_info_t joypad_info[MAX_USERS];
   input_driver_state_t *input_st = &input_driver_st;
   settings_t *settings           = config_get_ptr();
   const input_device_driver_t
      *joypad                     = input_st->primary_joypad;
#ifdef HAVE_MFI
   const input_device_driver_t
      *sec_joypad                 = input_st->secondary_joypad;
#else
   const input_device_driver_t
      *sec_joypad                 = NULL;
#endif
   bool input_remap_binds_enable  = settings->bools.input_remap_binds_enable;
   float input_axis_threshold     = settings->floats.input_axis_threshold;
   uint8_t max_users              = (uint8_t)settings->uints.input_max_users;

   if (joypad && joypad->poll)
      joypad->poll();
   if (sec_joypad && sec_joypad->poll)
      sec_joypad->poll();
   if (     input_st->current_driver
         && input_st->current_driver->poll)
      input_st->current_driver->poll(input_st->current_data);

   input_st->turbo_btns.count++;

   if (input_st->flags & INP_FLAG_BLOCK_LIBRETRO_INPUT)
   {
      for (i = 0; i < max_users; i++)
         input_st->turbo_btns.frame_enable[i] = 0;
      return;
   }

   /* This rarch_joypad_info_t struct contains the device index + autoconfig binds for the
    * controller to be queried, and also (for unknown reasons) the analog axis threshold
    * when mapping analog stick to dpad input. */
   for (i = 0; i < max_users; i++)
   {
      uint16_t button_id = RARCH_TURBO_ENABLE;

      if (settings->ints.input_turbo_bind != -1)
         button_id = settings->ints.input_turbo_bind;

      joypad_info[i].axis_threshold        = input_axis_threshold;
      joypad_info[i].joy_idx               = settings->uints.input_joypad_index[i];
      joypad_info[i].auto_binds            = input_autoconf_binds[joypad_info[i].joy_idx];

      input_st->turbo_btns.frame_enable[i] =
               (*input_st->libretro_input_binds[i])[button_id].valid
            && settings->bools.input_turbo_enable ?
         input_state_wrap(input_st->current_driver, input_st->current_data,
               joypad, sec_joypad, &joypad_info[i],
               (*input_st->libretro_input_binds),
               (input_st->flags & INP_FLAG_KB_MAPPING_BLOCKED) ? true : false,
               (unsigned)i,
               RETRO_DEVICE_JOYPAD, 0, button_id) : 0;
   }

#ifdef HAVE_OVERLAY
   if (      input_st->overlay_ptr
         && (input_st->overlay_ptr->flags & INPUT_OVERLAY_ALIVE))
   {
      unsigned input_analog_dpad_mode = settings->uints.input_analog_dpad_mode[0];
      float input_overlay_opacity     = (input_st->overlay_ptr->flags & INPUT_OVERLAY_IS_OSK)
         ? settings->floats.input_osk_overlay_opacity
         : settings->floats.input_overlay_opacity;

      switch (input_analog_dpad_mode)
      {
         case ANALOG_DPAD_LSTICK:
         case ANALOG_DPAD_RSTICK:
            {
               unsigned mapped_port      = settings->uints.input_remap_ports[0];
               if (input_st->analog_requested[mapped_port])
                  input_analog_dpad_mode = ANALOG_DPAD_NONE;
            }
            break;
         case ANALOG_DPAD_LSTICK_FORCED:
            input_analog_dpad_mode       = ANALOG_DPAD_LSTICK;
            break;
         case ANALOG_DPAD_RSTICK_FORCED:
            input_analog_dpad_mode       = ANALOG_DPAD_RSTICK;
            break;
         default:
            break;
      }

      input_poll_overlay(
            (input_st->flags & INP_FLAG_KB_MAPPING_BLOCKED) ? true : false,
            settings,
            input_st->overlay_ptr,
            input_st->overlay_visibility,
            input_overlay_opacity,
            input_analog_dpad_mode,
            settings->floats.input_axis_threshold);
   }
#endif // HAVE_OVERLAY

   if (input_remap_binds_enable)
   {
#ifdef HAVE_OVERLAY
      input_overlay_t *overlay_pointer   = (input_overlay_t*)input_st->overlay_ptr;
      bool poll_overlay                  = (overlay_pointer &&
            (overlay_pointer->flags & INPUT_OVERLAY_ALIVE));
#endif
      input_mapper_t *handle             = &input_st->mapper;
      float input_analog_deadzone        = settings->floats.input_analog_deadzone;
      float input_analog_sensitivity     = settings->floats.input_analog_sensitivity;

      for (i = 0; i < max_users; i++)
      {
         input_bits_t current_inputs;
         unsigned mapped_port            = settings->uints.input_remap_ports[i];
         unsigned device                 = settings->uints.input_libretro_device[mapped_port]
                                           & RETRO_DEVICE_MASK;
         input_bits_t *p_new_state       = (input_bits_t*)&current_inputs;
         unsigned input_analog_dpad_mode = settings->uints.input_analog_dpad_mode[i];

         switch (input_analog_dpad_mode)
         {
            case ANALOG_DPAD_LSTICK:
            case ANALOG_DPAD_RSTICK:
               if (input_st->analog_requested[mapped_port])
                  input_analog_dpad_mode = ANALOG_DPAD_NONE;
               break;
            case ANALOG_DPAD_LSTICK_FORCED:
               input_analog_dpad_mode    = ANALOG_DPAD_LSTICK;
               break;
            case ANALOG_DPAD_RSTICK_FORCED:
               input_analog_dpad_mode    = ANALOG_DPAD_RSTICK;
               break;
            default:
               break;
         }

         switch (device)
         {
            case RETRO_DEVICE_KEYBOARD:
            case RETRO_DEVICE_JOYPAD:
            case RETRO_DEVICE_ANALOG:
               BIT256_CLEAR_ALL_PTR(&current_inputs);
               if (joypad)
               {
                  unsigned k, j;
                  int32_t ret = input_state_wrap(
                        input_st->current_driver,
                        input_st->current_data,
                        input_st->primary_joypad,
                        sec_joypad,
                        &joypad_info[i],
                        (*input_st->libretro_input_binds),
                        (input_st->flags & INP_FLAG_KB_MAPPING_BLOCKED) ? true : false,
                        (unsigned)i, RETRO_DEVICE_JOYPAD,
                        0, RETRO_DEVICE_ID_JOYPAD_MASK);

                  for (k = 0; k < RARCH_FIRST_CUSTOM_BIND; k++)
                  {
                     if (ret & (1 << k))
                     {
                        bool valid_bind  =
                           (*input_st->libretro_input_binds[i])[k].valid;

                        if (valid_bind)
                        {
                           int16_t   val =
                              input_joypad_analog_button(
                                    input_analog_deadzone,
                                    input_analog_sensitivity,
                                    joypad,
                                    &joypad_info[i],
                                    k,
                                    &(*input_st->libretro_input_binds[i])[k]
                                    );
                           if (val)
                              p_new_state->analog_buttons[k] = val;
                        }

                        BIT256_SET_PTR(p_new_state, k);
                     }
                  }

                  /* This is the analog joypad index -
                   * handles only the two analog axes */
                  for (k = 0; k < 2; k++)
                  {
                     /* This is the analog joypad ident */
                     for (j = 0; j < 2; j++)
                     {
                        unsigned offset = 0 + (k * 4) + (j * 2);
                        int16_t     val = input_joypad_analog_axis(
                              input_analog_dpad_mode,
                              input_analog_deadzone,
                              input_analog_sensitivity,
                              joypad, &joypad_info[i],
                              k, j, (*input_st->libretro_input_binds[i]));

                        if (val >= 0)
                           p_new_state->analogs[offset]   = val;
                        else
                           p_new_state->analogs[offset+1] = val;
                     }
                  }
               }
               break;
            default:
               break;
         }

         /* mapper */
         switch (device)
         {
            /* keyboard to gamepad remapping */
            case RETRO_DEVICE_KEYBOARD:
               for (j = 0; j < RARCH_CUSTOM_BIND_LIST_END; j++)
               {
                  unsigned current_button_value;
                  unsigned remap_key =
                        settings->uints.input_keymapper_ids[i][j];

                  if (remap_key == RETROK_UNKNOWN)
                     continue;

                  if (j >= RARCH_FIRST_CUSTOM_BIND && j < RARCH_ANALOG_BIND_LIST_END)
                  {
                     int16_t current_axis_value = p_new_state->analogs[j - RARCH_FIRST_CUSTOM_BIND];
                     current_button_value = abs(current_axis_value) >
                           settings->floats.input_axis_threshold
                            * 32767;
                  }
                  else
                     current_button_value = BIT256_GET_PTR(p_new_state, j);

#ifdef HAVE_OVERLAY
                  if (poll_overlay && i == 0)
                  {
                     input_overlay_state_t *ol_state  = overlay_pointer
                        ? &overlay_pointer->overlay_state : NULL;
                     if (ol_state)
                        current_button_value |= BIT256_GET(ol_state->buttons, j);
                  }
#endif
                  /* Press */
                  if ((current_button_value == 1)
                        && !MAPPER_GET_KEY(handle, remap_key))
                  {
                     handle->key_button[remap_key] = (unsigned)j;

                     MAPPER_SET_KEY(handle, remap_key);
                     input_keyboard_event(true,
                           remap_key,
                           0, 0, RETRO_DEVICE_KEYBOARD);
                  }
                  /* Release */
                  else if ((current_button_value == 0)
                        && MAPPER_GET_KEY(handle, remap_key))
                  {
                     if (handle->key_button[remap_key] != j)
                        continue;

                     input_keyboard_event(false,
                           remap_key,
                           0, 0, RETRO_DEVICE_KEYBOARD);
                     MAPPER_UNSET_KEY(handle, remap_key);
                  }
               }
               break;

               /* gamepad remapping */
            case RETRO_DEVICE_JOYPAD:
            case RETRO_DEVICE_ANALOG:
               /* this loop iterates on all users and all buttons,
                * and checks if a pressed button is assigned to any
                * other button than the default one, then it sets
                * the bit on the mapper input bitmap, later on the
                * original input is cleared in input_state */
               BIT256_CLEAR_ALL(handle->buttons[i]);

               for (j = 0; j < 8; j++)
                  handle->analog_value[i][j] = 0;

               for (j = 0; j < RARCH_FIRST_CUSTOM_BIND; j++)
               {
                  bool remap_valid;
                  unsigned remap_button         =
                        settings->uints.input_remap_ids[i][j];
                  unsigned current_button_value =
                        BIT256_GET_PTR(p_new_state, j);

#ifdef HAVE_OVERLAY
                  if (poll_overlay && i == 0)
                  {
                     input_overlay_state_t *ol_state  =
                          overlay_pointer
                        ? &overlay_pointer->overlay_state
                        : NULL;
                     if (ol_state)
                        current_button_value |= BIT256_GET(ol_state->buttons, j);
                  }
#endif
                  remap_valid                   =
                        (current_button_value == 1)
                     && (j != remap_button)
                     && (remap_button != RARCH_UNMAPPED);

#ifdef HAVE_ACCESSIBILITY
                  /* gamepad override */
                  if (     (i == 0)
                        && input_st->gamepad_input_override & (1 << j))
                  {
                     BIT256_SET(handle->buttons[i], j);
                  }
#endif

                  if (remap_valid)
                  {
                     if (remap_button < RARCH_FIRST_CUSTOM_BIND)
                     {
                        BIT256_SET(handle->buttons[i], remap_button);
                     }
                     else
                     {
                        int invert = 1;

                        if (remap_button % 2 != 0)
                           invert = -1;

                        handle->analog_value[i][
                           remap_button - RARCH_FIRST_CUSTOM_BIND] =
                              (p_new_state->analog_buttons[j]
                               ? p_new_state->analog_buttons[j]
                               : 32767) * invert;
                     }
                  }
               }

               for (j = 0; j < 8; j++)
               {
                  unsigned k                 = (unsigned)j + RARCH_FIRST_CUSTOM_BIND;
                  int16_t current_axis_value = p_new_state->analogs[j];
                  unsigned remap_axis        = settings->uints.input_remap_ids[i][k];

                  if (
                        (
                            abs(current_axis_value) > 0
                        && (k != remap_axis)
                        && (remap_axis != RARCH_UNMAPPED)
                        )
                     )
                  {
                     if (remap_axis < RARCH_FIRST_CUSTOM_BIND &&
                           abs(current_axis_value) >
                           settings->floats.input_axis_threshold
                            * 32767)
                     {
                        BIT256_SET(handle->buttons[i], remap_axis);
                     }
                     else
                     {
                        unsigned remap_axis_bind =
                           remap_axis - RARCH_FIRST_CUSTOM_BIND;

                        if (remap_axis_bind < sizeof(handle->analog_value[i]))
                        {
                           int invert = 1;
                           if (     (k % 2 == 0 && remap_axis % 2 != 0)
                                 || (k % 2 != 0 && remap_axis % 2 == 0)
                              )
                              invert = -1;

                           handle->analog_value[i][
                              remap_axis_bind] =
                                 current_axis_value * invert;
                        }
                     }
                  }

               }
               break;
            default:
               break;
         }
      }
   }

#ifdef HAVE_COMMAND
   for (i = 0; i < ARRAY_SIZE(input_st->command); i++)
   {
      if (input_st->command[i])
      {
         memset(input_st->command[i]->state,
                0, sizeof(input_st->command[i]->state));

         input_st->command[i]->poll(
            input_st->command[i]);
      }
   }
#endif

#ifdef HAVE_NETWORKGAMEPAD
   /* Poll remote */
   if (input_st->remote)
   {
      unsigned user;

      for (user = 0; user < max_users; user++)
      {
         if (settings->bools.network_remote_enable_user[user])
         {
#if defined(HAVE_NETWORKING) && defined(HAVE_NETWORKGAMEPAD)
            fd_set fds;
            ssize_t ret;
            struct remote_message msg;


#if defined(_WIN32)
            if (input_st->remote->net_fd[user] == INVALID_SOCKET)
#else
            if (input_st->remote->net_fd[user] < 0)
#endif
               return;

            FD_ZERO(&fds);
            FD_SET(input_st->remote->net_fd[user], &fds);

            ret = recvfrom(input_st->remote->net_fd[user],
                  (char*)&msg,
                  sizeof(msg), 0, NULL, NULL);

            if (ret == sizeof(msg))
               input_remote_parse_packet(&input_st->remote_st_ptr, &msg, user);
            else if ((ret != -1) || ((errno != EAGAIN) && (errno != ENOENT)))
#endif
            {
               input_remote_state_t *input_state  = &input_st->remote_st_ptr;
               input_state->buttons[user]         = 0;
               input_state->analog[0][user]       = 0;
               input_state->analog[1][user]       = 0;
               input_state->analog[2][user]       = 0;
               input_state->analog[3][user]       = 0;
            }
         }
      }
   }
#endif
#ifdef HAVE_BSV_MOVIE
   if (BSV_MOVIE_IS_PLAYBACK_ON())
   {
      runloop_state_t *runloop_st   = runloop_state_get_ptr();
      retro_keyboard_event_t *key_event                 = &runloop_st->key_event;

      if (*key_event && *key_event == runloop_st->frontend_key_event)
      {
         int i;
         bsv_key_data_t k;
         for (i = 0; i < input_st->bsv_movie_state_handle->key_event_count; i++)
         {
#ifdef HAVE_CHEEVOS
            rcheevos_pause_hardcore();
#endif
            k = input_st->bsv_movie_state_handle->key_events[i];
            input_keyboard_event(k.down, swap_if_big32(k.code),
                  swap_if_big32(k.character), swap_if_big16(k.mod),
                  RETRO_DEVICE_KEYBOARD);
         }
         /* Have to clear here so we don't double-apply key events */
         /* Zero out key events when playing back or recording */
         input_st->bsv_movie_state_handle->key_event_count = 0;
      }
   }
#endif
}

int16_t input_driver_state_wrapper(unsigned port, unsigned device,
      unsigned idx, unsigned id)
{
   input_driver_state_t
      *input_st                = &input_driver_st;
   settings_t *settings        = config_get_ptr();
   int16_t result              = 0;
#ifdef HAVE_BSV_MOVIE
   /* Load input from BSV record, if enabled */
   if (BSV_MOVIE_IS_PLAYBACK_ON())
   {
      int16_t bsv_result = 0;
      bsv_movie_t *movie = input_st->bsv_movie_state_handle;
      if (bsv_movie_handle_read_input_event(
          movie, port, device, idx, id, &bsv_result))
      {
#ifdef HAVE_CHEEVOS
         rcheevos_pause_hardcore();
#endif
         return bsv_result;
      }

      input_st->bsv_movie_state.flags |= BSV_FLAG_MOVIE_END;
   }
#endif

   /* Read input state */
   result = input_state_internal(input_st, settings, port, device, idx, id);

   /* Register any analog stick input requests for
    * this 'virtual' (core) port */
   if (     (device == RETRO_DEVICE_ANALOG)
       && ( (idx    == RETRO_DEVICE_INDEX_ANALOG_LEFT)
       ||   (idx    == RETRO_DEVICE_INDEX_ANALOG_RIGHT)))
      input_st->analog_requested[port] = true;

#ifdef HAVE_BSV_MOVIE
   /* Save input to BSV record, if enabled */
   if (BSV_MOVIE_IS_RECORDING())
      bsv_movie_handle_push_input_event(
            input_st->bsv_movie_state_handle,
            port,
            device,
            idx,
            id,
            result);
#endif

#ifdef HAVE_GAME_AI
   if (settings->bools.game_ai_override_p1 && port == 0)
      result |= game_ai_input(port, device, idx, id, result);
   if (settings->bools.game_ai_override_p2 && port == 1)
      result |= game_ai_input(port, device, idx, id, result);
#endif

   return result;
}

#ifdef HAVE_HID
void *hid_driver_get_data(void)
{
   return (void *)input_driver_st.hid_data;
}

/* This is only to be called after we've invoked free() on the
 * HID driver; the memory will have already been freed, so we need to
 * reset the pointer.
 */
void hid_driver_reset_data(void) { input_driver_st.hid_data = NULL; }

/**
 * config_get_hid_driver_options:
 *
 * Get an enumerated list of all HID driver names, separated by '|'.
 *
 * Returns: string listing of all HID driver names, separated by '|'.
 **/
const char* config_get_hid_driver_options(void)
{
   return char_list_new_special(STRING_LIST_INPUT_HID_DRIVERS, NULL);
}

/**
 * input_hid_init_first:
 *
 * Finds first suitable HID driver and initializes.
 *
 * Returns: HID driver if found, otherwise NULL.
 **/
const hid_driver_t *input_hid_init_first(void)
{
   unsigned i;
   input_driver_state_t *input_st = &input_driver_st;

   for (i = 0; hid_drivers[i]; i++)
   {
      input_st->hid_data = hid_drivers[i]->init();

      if (input_st->hid_data)
      {
         RARCH_LOG("[Input] Found HID driver: \"%s\".\n",
               hid_drivers[i]->ident);
         return hid_drivers[i];
      }
   }

   return NULL;
}
#endif

void input_driver_collect_system_input(input_driver_state_t *input_st,
      settings_t *settings, input_bits_t *current_bits)
{
   rarch_joypad_info_t joypad_info;
   input_driver_t *current_input       = input_st->current_driver;
   const input_device_driver_t *joypad = input_st->primary_joypad;
#ifdef HAVE_MFI
   const input_device_driver_t
      *sec_joypad                      = input_st->secondary_joypad;
#else
   const input_device_driver_t
      *sec_joypad                      = NULL;
#endif
   unsigned block_delay                = settings->uints.input_hotkey_block_delay;
   uint8_t max_users                   = settings->uints.input_max_users;
   uint8_t port                        = 0;
   joypad_info.axis_threshold          = settings->floats.input_axis_threshold;

   /* Gather input from each (enabled) joypad */
   for (port = 0; port < (int)max_users; port++)
   {
      const struct retro_keybind *binds_norm = &input_config_binds[port][RARCH_ENABLE_HOTKEY];
      const struct retro_keybind *binds_auto = &input_autoconf_binds[port][RARCH_ENABLE_HOTKEY];

      joypad_info.joy_idx                    = settings->uints.input_joypad_index[port];
      joypad_info.auto_binds                 = input_autoconf_binds[joypad_info.joy_idx];

      input_keys_pressed(port,
            false,
            block_delay,
            current_bits,
            (const retro_keybind_set *)input_config_binds,
            binds_norm,
            binds_auto,
            joypad,
            sec_joypad,
            &joypad_info,
            settings->bools.input_hotkey_device_merge);
   }

   {
#if defined(HAVE_ACCESSIBILITY) && defined(HAVE_TRANSLATE)
      if (settings->bools.ai_service_enable)
      {
         int i;
         input_st->gamepad_input_override = 0;
         for (i = 0; i < MAX_USERS; i++)
         {
            /* Set gamepad input override */
            if (input_st->ai_gamepad_state[i] == 2)
               input_st->gamepad_input_override |= (1 << i);
            input_st->ai_gamepad_state[i] = 0;
         }
      }
#endif /* defined(HAVE_ACCESSIBILITY) && defined(HAVE_TRANSLATE) */
   }
}

void input_keyboard_event(bool down, unsigned code,
      uint32_t character, uint16_t mod, unsigned device)
{
   runloop_state_t *runloop_st = runloop_state_get_ptr();
   retro_keyboard_event_t
      *key_event               = &runloop_st->key_event;
   input_driver_state_t
      *input_st                = &input_driver_st;
#ifdef HAVE_ACCESSIBILITY
   access_state_t *access_st   = access_state_get_ptr();
   settings_t *settings        = config_get_ptr();
   bool accessibility_enable   = settings->bools.accessibility_enable;
   unsigned accessibility_narrator_speech_speed
                               = settings->uints.accessibility_narrator_speech_speed;
#endif // HAVE_ACCESSIBILITY

   if (input_st->flags & INP_FLAG_DEFERRED_WAIT_KEYS)
   {
      if (down)
         return;
      input_st->keyboard_press_cb    = NULL;
      input_st->keyboard_press_data  = NULL;
      input_st->flags               &= ~(INP_FLAG_KB_MAPPING_BLOCKED
                                     |   INP_FLAG_DEFERRED_WAIT_KEYS
                                       );
   }
   else if (input_st->keyboard_press_cb)
   {
      if (!down || code == RETROK_UNKNOWN)
         return;
      if (input_st->keyboard_press_cb(input_st->keyboard_press_data, code))
         return;
      input_st->flags               |= INP_FLAG_DEFERRED_WAIT_KEYS;
   }
   else if (input_st->keyboard_line.enabled)
   {
      if (!down)
         return;

      if (!input_keyboard_line_event(input_st,
            &input_st->keyboard_line, character))
         return;

      /* Line is complete, can free it now. */
      input_keyboard_line_free(input_st);

      /* Unblock all hotkeys. */
      input_st->flags &= ~INP_FLAG_KB_MAPPING_BLOCKED;
   }
   else
   {
      if (code == RETROK_UNKNOWN)
         return;

      /* Check if keyboard events should be blocked when
       * pressing hotkeys and RetroPad binds, but
       * - not with Game Focus
       * - not from keyboard device type mappings
       * - not from overlay keyboard input
       * - with 'enable_hotkey' modifier set and unpressed.
       *
       * Also do not block key up events, because keys will
       * get stuck if Game Focus key is also pressing a key. */
      if (     down
            && !input_st->game_focus_state.enabled
            && BIT512_GET(input_st->keyboard_mapping_bits, code)
            && device != RETRO_DEVICE_POINTER)
      {
         unsigned j;
         settings_t *settings        = config_get_ptr();
         unsigned max_users          = settings->uints.input_max_users;
         bool hotkey_pressed         = (input_st->input_hotkey_block_counter > 0);
         bool block_key_event        = false;

         /* Loop enabled ports for keycode dupes. */
         for (j = 0; j < max_users; j++)
         {
            unsigned k;
            unsigned hotkey_code = input_config_binds[0][RARCH_ENABLE_HOTKEY].key;

            /* Block hotkey key events based on 'enable_hotkey' modifier,
             * and only when modifier is a keyboard key. */
            if (     j == 0
                  && !block_key_event
                  && !( !hotkey_pressed
                  &&     hotkey_code != RETROK_UNKNOWN
                  &&     hotkey_code != code))
            {
               for (k = RARCH_FIRST_META_KEY; k < RARCH_BIND_LIST_END; k++)
               {
                  if (input_config_binds[j][k].key == code)
                  {
                     block_key_event = true;
                     break;
                  }
               }
            }

            /* RetroPad blocking needed only when emulated
             * device type is active. */
            if (     input_config_get_device(j)
                  && !block_key_event)
            {
               for (k = 0; k < RARCH_FIRST_META_KEY; k++)
               {
                  if (input_config_binds[j][k].key == code)
                  {
                     block_key_event = true;
                     break;
                  }
               }
            }
         }

         /* No blocking when event comes from emulated keyboard device type */
         if (MAPPER_GET_KEY(&input_st->mapper, code))
            block_key_event = false;

         if (block_key_event)
            return;
      }

      if (*key_event)
      {
         if (*key_event == runloop_st->frontend_key_event)
         {
#ifdef HAVE_BSV_MOVIE
            /* Save input to BSV record, if recording */
            if (BSV_MOVIE_IS_RECORDING())
               bsv_movie_handle_push_key_event(
                     input_st->bsv_movie_state_handle, down, mod,
                     code, character);
#endif
         }
         (*key_event)(down, code, character, mod);
      }
   }
}
