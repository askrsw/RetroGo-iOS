/*  RetroArch - A frontend for libretro.
 *  Copyright (C) 2010-2014 - Hans-Kristian Arntzen
 *  Copyright (C) 2011-2016 - Daniel De Matteis
 *  Copyright (C) 2014-2016 - Jean-André Santoni
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

#ifndef __RARCH_CONFIGURATION_H__
#define __RARCH_CONFIGURATION_H__

#include <stdint.h>

#include <boolean.h>
#include <retro_common_api.h>
#include <retro_miscellaneous.h>
#include <file/config_file.h>

#include <defines/video_defines.h>
#include <defines/led_defines.h>

#include <defines/input_defines.h>

#define configuration_set_float(settings, var, newvar) \
{ \
   settings->flags |= SETTINGS_FLG_MODIFIED; \
   var              = newvar; \
}

#define configuration_set_bool(settings, var, newvar) \
{ \
   settings->flags |= SETTINGS_FLG_MODIFIED; \
   var              = newvar; \
}

#define configuration_set_uint(settings, var, newvar) \
{ \
   settings->flags |= SETTINGS_FLG_MODIFIED; \
   var              = newvar; \
}

#define configuration_set_int(settings, var, newvar) \
{ \
   settings->flags |= SETTINGS_FLG_MODIFIED; \
   var              = newvar; \
}

#define configuration_set_string(settings, var, newvar) \
{ \
   settings->flags |= SETTINGS_FLG_MODIFIED; \
   strlcpy(var, newvar, sizeof(var)); \
}

RETRO_BEGIN_DECLS

enum crt_switch_type
{
   CRT_SWITCH_NONE = 0,
   CRT_SWITCH_15KHZ,
   CRT_SWITCH_31KHZ,
   CRT_SWITCH_32_120,
   CRT_SWITCH_INI
};

enum override_type
{
   OVERRIDE_NONE = 0,
   OVERRIDE_AS,
   OVERRIDE_CORE,
   OVERRIDE_CONTENT_DIR,
   OVERRIDE_GAME
};

enum settings_glob_flags
{
   SETTINGS_FLG_MODIFIED              = (1 << 0),
   SETTINGS_FLG_SKIP_WINDOW_POSITIONS = (1 << 1)
};

typedef struct settings
{
   struct
   {
      size_t placeholder;
      size_t rewind_buffer_size;
   } sizes;

   video_viewport_t video_vp_custom; /* int alignment */

   struct
   {
      int placeholder;
      int netplay_check_frames;
      int location_update_interval_ms;
      int location_update_interval_distance;
      int state_slot;
      int replay_slot;
      int crt_switch_center_adjust;
      int crt_switch_porch_adjust;
      int crt_switch_vertical_adjust;
      int video_max_frame_latency;
#ifdef HAVE_VULKAN
      int vulkan_gpu_index;
#endif
#ifdef HAVE_D3D10
      int d3d10_gpu_index;
#endif
#ifdef HAVE_D3D11
      int d3d11_gpu_index;
#endif
#ifdef HAVE_D3D12
      int d3d12_gpu_index;
#endif
#ifdef HAVE_WINDOW_OFFSET
      int video_window_offset_x;
      int video_window_offset_y;
#endif
#ifdef HAVE_OVERLAY
      int input_overlay_lightgun_port;
#endif
      int input_turbo_bind;
   } ints;

   struct
   {
      unsigned placeholder;

      unsigned input_split_joycon[MAX_USERS];
      unsigned input_joypad_index[MAX_USERS];
      unsigned input_device[MAX_USERS];
      unsigned input_mouse_index[MAX_USERS];

      unsigned input_libretro_device[MAX_USERS];
      unsigned input_analog_dpad_mode[MAX_USERS];
      unsigned input_device_reservation_type[MAX_USERS];

      unsigned input_remap_ports[MAX_USERS];
      unsigned input_remap_ids[MAX_USERS][RARCH_CUSTOM_BIND_LIST_END];
      unsigned input_keymapper_ids[MAX_USERS][RARCH_CUSTOM_BIND_LIST_END];
      unsigned input_remap_port_map[MAX_USERS][MAX_USERS + 1];

      unsigned led_map[MAX_LEDS];

      unsigned audio_output_sample_rate;
      unsigned audio_block_frames;
      unsigned audio_latency;

#ifdef HAVE_WASAPI
      unsigned audio_wasapi_sh_buffer_length;
#endif

#ifdef HAVE_MICROPHONE
      unsigned microphone_sample_rate;
      unsigned microphone_block_frames;
      unsigned microphone_latency;
      unsigned microphone_resampler_quality;
#ifdef HAVE_WASAPI
      unsigned microphone_wasapi_sh_buffer_length;
#endif
#endif

      unsigned fps_update_interval;
      unsigned memory_update_interval;

      unsigned input_block_timeout;

      unsigned audio_resampler_quality;

      unsigned input_turbo_period;
      unsigned input_turbo_duty_cycle;
      unsigned input_turbo_mode;
      unsigned input_turbo_button;

      unsigned input_bind_timeout;
      unsigned input_bind_hold;
#ifdef GEKKO
      unsigned input_mouse_scale;
#endif
      unsigned input_touch_scale;
      unsigned input_hotkey_block_delay;
      unsigned input_quit_gamepad_combo;
      unsigned input_menu_toggle_gamepad_combo;
      unsigned input_keyboard_gamepad_mapping_type;
      unsigned input_poll_type_behavior;
      unsigned input_rumble_gain;
      unsigned input_auto_game_focus;
      unsigned input_max_users;

      unsigned netplay_port;
      unsigned netplay_max_connections;
      unsigned netplay_max_ping;
      unsigned netplay_chat_color_name;
      unsigned netplay_chat_color_msg;
      unsigned netplay_input_latency_frames_min;
      unsigned netplay_input_latency_frames_range;
      unsigned netplay_share_digital;
      unsigned netplay_share_analog;
      unsigned frontend_log_level;
      unsigned libretro_log_level;
      unsigned rewind_granularity;
      unsigned rewind_buffer_size_step;
      unsigned autosave_interval;
      unsigned replay_checkpoint_interval;
      unsigned replay_max_keep;
      unsigned savestate_max_keep;
      unsigned network_cmd_port;
      unsigned network_remote_base_port;
      unsigned keymapper_port;
      unsigned video_window_opacity;
      unsigned crt_switch_resolution;
      unsigned crt_switch_resolution_super;
      unsigned screen_brightness;
      unsigned video_monitor_index;
      unsigned video_fullscreen_x;
      unsigned video_fullscreen_y;
      unsigned video_scale;
      unsigned video_scale_integer_axis;
      unsigned video_scale_integer_scaling;
      unsigned video_max_swapchain_images;
      unsigned video_swap_interval;
      unsigned video_hard_sync_frames;
      unsigned video_frame_delay;
      unsigned video_viwidth;
      unsigned video_aspect_ratio_idx;
      unsigned video_rotation;
      unsigned screen_orientation;
      unsigned video_msg_bgcolor_red;
      unsigned video_msg_bgcolor_green;
      unsigned video_msg_bgcolor_blue;
      unsigned video_stream_port;
      unsigned video_record_quality;
      unsigned video_stream_quality;
      unsigned video_record_scale_factor;
      unsigned video_stream_scale_factor;
      unsigned video_3ds_display_mode;
      unsigned video_dingux_ipu_filter_type;
      unsigned video_dingux_refresh_rate;
      unsigned video_dingux_rs90_softfilter_type;
#ifdef GEKKO
      unsigned video_overscan_correction_top;
      unsigned video_overscan_correction_bottom;
#endif
      unsigned video_shader_delay;
#ifdef HAVE_SCREENSHOTS
      unsigned notification_show_screenshot_duration;
      unsigned notification_show_screenshot_flash;
#endif

      /* Accessibility */
      unsigned accessibility_narrator_speech_speed;

      unsigned camera_width;
      unsigned camera_height;

#ifdef HAVE_OVERLAY
      unsigned input_overlay_show_inputs;
      unsigned input_overlay_show_inputs_port;
      unsigned input_overlay_dpad_diagonal_sensitivity;
      unsigned input_overlay_abxy_diagonal_sensitivity;
      unsigned input_overlay_analog_recenter_zone;
      unsigned input_overlay_lightgun_trigger_delay;
      unsigned input_overlay_lightgun_two_touch_input;
      unsigned input_overlay_lightgun_three_touch_input;
      unsigned input_overlay_lightgun_four_touch_input;
      unsigned input_overlay_mouse_hold_msec;
      unsigned input_overlay_mouse_dtap_msec;
#endif // HAVE_OVERLAY

      unsigned run_ahead_frames;

      unsigned midi_volume;
      unsigned streaming_mode;

      unsigned window_position_x;
      unsigned window_position_y;
      unsigned window_position_width;
      unsigned window_position_height;
      unsigned window_auto_width_max;
      unsigned window_auto_height_max;

      unsigned video_record_threads;

      unsigned libnx_overclock;
      unsigned ai_service_mode;
      unsigned ai_service_target_lang;
      unsigned ai_service_source_lang;

      unsigned video_black_frame_insertion;
      unsigned video_bfi_dark_frames;
      unsigned video_shader_subframes;
      unsigned video_autoswitch_refresh_rate;
      unsigned quit_on_close_content;

#ifdef HAVE_LAKKA
      unsigned cpu_scaling_mode;
      unsigned cpu_min_freq;
      unsigned cpu_max_freq;
#endif

#ifdef HAVE_MIST
      unsigned steam_rich_presence_format;
#endif

      unsigned cheevos_appearance_anchor;
      unsigned cheevos_visibility_summary;
   } uints;

   struct
   {
      float placeholder;
      float video_aspect_ratio;
      float video_vp_bias_x;
      float video_vp_bias_y;
#if defined(RARCH_MOBILE)
      float video_vp_bias_portrait_x;
      float video_vp_bias_portrait_y;
#endif
      float video_refresh_rate;
      float video_autoswitch_pal_threshold;
      float crt_video_refresh_rate;
      float video_font_size;
      float video_msg_pos_x;
      float video_msg_pos_y;
      float video_msg_color_r;
      float video_msg_color_g;
      float video_msg_color_b;
      float video_msg_bgcolor_opacity;
      float video_hdr_max_nits;
      float video_hdr_paper_white_nits;
      float video_hdr_display_contrast;

      float cheevos_appearance_padding_h;
      float cheevos_appearance_padding_v;

      float audio_max_timing_skew;
      float audio_volume; /* dB scale. */
      float audio_mixer_volume; /* dB scale. */

      float input_overlay_opacity;
      float input_osk_overlay_opacity;

      float input_overlay_scale_landscape;
      float input_overlay_aspect_adjust_landscape;
      float input_overlay_x_separation_landscape;
      float input_overlay_y_separation_landscape;
      float input_overlay_x_offset_landscape;
      float input_overlay_y_offset_landscape;

      float input_overlay_scale_portrait;
      float input_overlay_aspect_adjust_portrait;
      float input_overlay_x_separation_portrait;
      float input_overlay_y_separation_portrait;
      float input_overlay_x_offset_portrait;
      float input_overlay_y_offset_portrait;

      float input_overlay_mouse_speed;
      float input_overlay_mouse_swipe_threshold;

      float slowmotion_ratio;
      float fastforward_ratio;
      float input_analog_deadzone;
      float input_axis_threshold;
      float input_analog_sensitivity;
   } floats;

   struct
   {
      char placeholder;

      char video_driver[32];
      char record_driver[32];
      char camera_driver[32];
      char bluetooth_driver[32];
      char wifi_driver[32];
      char led_driver[32];
      char location_driver[32];
      char cloud_sync_driver[32];
      char menu_driver[32];
      char cheevos_username[32];
      char cheevos_token[32];
      char cheevos_leaderboards_enable[32];
      char video_context_driver[32];
      char audio_driver[32];
      char audio_resampler[32];
      char input_driver[32];
      char input_joypad_driver[32];
      char midi_driver[32];
      char midi_input[32];
      char midi_output[32];
#ifdef HAVE_LAKKA
      char cpu_main_gov[32];
      char cpu_menu_gov[32];
#endif
#ifdef HAVE_MICROPHONE
      char microphone_driver[32];
      char microphone_resampler[32];
#endif
      char input_keyboard_layout[64];
      char cheevos_custom_host[64];

#ifdef HAVE_LAKKA
      char timezone[TIMEZONE_LENGTH];
#endif

      char cheevos_password[NAME_MAX_LENGTH];
#ifdef HAVE_MICROPHONE
      char microphone_device[NAME_MAX_LENGTH];
#endif
#ifdef ANDROID
      char input_android_physical_keyboard[NAME_MAX_LENGTH];
#endif
      char audio_device[NAME_MAX_LENGTH];
      char camera_device[NAME_MAX_LENGTH];
      char netplay_mitm_server[NAME_MAX_LENGTH];
      char webdav_url[NAME_MAX_LENGTH];
      char webdav_username[NAME_MAX_LENGTH];
      char webdav_password[NAME_MAX_LENGTH];

      char crt_switch_timings[NAME_MAX_LENGTH];
      char input_reserved_devices[MAX_USERS][NAME_MAX_LENGTH];

      char youtube_stream_key[PATH_MAX_LENGTH];
      char twitch_stream_key[PATH_MAX_LENGTH];
      char facebook_stream_key[PATH_MAX_LENGTH];
      char discord_app_id[PATH_MAX_LENGTH];
      char ai_service_url[PATH_MAX_LENGTH];

      char translation_service_url[2048]; /* TODO/FIXME - check size */
   } arrays;

   struct
   {
      char placeholder;

      char username[32];

      char netplay_password[128];
      char netplay_spectate_password[128];

      char streaming_title[512]; /* TODO/FIXME - check size */

      char netplay_server[NAME_MAX_LENGTH];
      char netplay_custom_mitm_server[NAME_MAX_LENGTH];
      char kiosk_mode_password[NAME_MAX_LENGTH];

      char directory_start[DIR_MAX_LENGTH];
      char directory_main_config[DIR_MAX_LENGTH];
      char directory_input_remapping[DIR_MAX_LENGTH];
      char directory_autoconfig[DIR_MAX_LENGTH];
      char directory_audio_filter[DIR_MAX_LENGTH];
      char directory_video_filter[DIR_MAX_LENGTH];
      char directory_assets[DIR_MAX_LENGTH];
      char directory_libretro[DIR_MAX_LENGTH];
      char path_libretro_info[PATH_MAX_LENGTH];
      char directory_overlay[DIR_MAX_LENGTH];
      char directory_osk_overlay[DIR_MAX_LENGTH];
      char path_overlay[PATH_MAX_LENGTH];
      char path_osk_overlay[PATH_MAX_LENGTH];
      char directory_video_shader[DIR_MAX_LENGTH];
      char directory_user_video_shader[DIR_MAX_LENGTH];
      char directory_screenshot[DIR_MAX_LENGTH];
      char directory_playlist[DIR_MAX_LENGTH];
      char directory_cache[DIR_MAX_LENGTH];
      char directory_thumbnails[DIR_MAX_LENGTH];
      char path_content_database[PATH_MAX_LENGTH];
      char path_cheat_database[PATH_MAX_LENGTH];
      char log_dir[DIR_MAX_LENGTH];

#ifdef HAVE_TEST_DRIVERS
      char test_input_file_joypad[PATH_MAX_LENGTH];
      char test_input_file_general[PATH_MAX_LENGTH];
#endif
      char path_record_config[PATH_MAX_LENGTH];
      char path_stream_config[PATH_MAX_LENGTH];
      char path_audio_dsp_plugin[PATH_MAX_LENGTH];
      char path_softfilter_plugin[PATH_MAX_LENGTH];
      char path_core_options[PATH_MAX_LENGTH];
      char path_cheat_settings[PATH_MAX_LENGTH];
      char path_font[PATH_MAX_LENGTH];

      char directory_menu_config[DIR_MAX_LENGTH];

      char browse_url[4096];      /* TODO/FIXME - check size */
      char path_stream_url[8192]; /* TODO/FIXME - check size */
   } paths;

   struct
   {
      bool placeholder;

      /* Video */
      bool video_fullscreen;
      bool video_windowed_fullscreen;
      bool video_vsync;
      bool video_adaptive_vsync;
      bool video_hard_sync;
      bool video_waitable_swapchains;
      bool video_vfilter;
      bool video_smooth;
      bool video_ctx_scaling;
      bool video_force_aspect;
      bool video_frame_delay_auto;
      bool video_crop_overscan;
      bool video_aspect_ratio_auto;
      bool video_dingux_ipu_keep_aspect;
      bool video_scale_integer;
      bool video_shader_enable;
      bool video_shader_watch_files;
      bool video_shader_remember_last_dir;
      bool video_shader_preset_save_reference_enable;
      bool video_scan_subframes;
      bool video_threaded;
      bool video_font_enable;
      bool video_disable_composition;
      bool video_post_filter_record;
      bool video_gpu_record;
      bool video_gpu_screenshot;
      bool video_allow_rotate;
      bool video_shared_context;
      bool video_force_srgb_disable;
      bool video_fps_show;
      bool video_statistics_show;
      bool video_framecount_show;
      bool video_memory_show;
      bool video_msg_bgcolor_enable;
      bool video_wiiu_prefer_drc;
      bool video_notch_write_over_enable;
      bool video_hdr_enable;
      bool video_hdr_expand_gamut;
      bool video_use_metal_arg_buffers;

      /* Accessibility */
      bool accessibility_enable;

      /* Audio */
      bool audio_enable;
      bool audio_enable_menu;
      bool audio_enable_menu_ok;
      bool audio_enable_menu_cancel;
      bool audio_enable_menu_notice;
      bool audio_enable_menu_bgm;
      bool audio_enable_menu_scroll;
      bool audio_sync;
      bool audio_rate_control;
      bool audio_fastforward_mute;
      bool audio_fastforward_speedup;
      bool audio_rewind_mute;
#ifdef IOS
      bool audio_respect_silent_mode;
#endif

#ifdef HAVE_WASAPI
      bool audio_wasapi_exclusive_mode;
      bool audio_wasapi_float_format;
#endif

#ifdef HAVE_MICROPHONE
      /* Microphone */
      bool microphone_enable;
#ifdef HAVE_WASAPI
      bool microphone_wasapi_exclusive_mode;
      bool microphone_wasapi_float_format;
#endif
#endif

      /* Input */
      bool input_remap_binds_enable;
      bool input_remap_sort_by_controller_enable;
      bool input_autodetect_enable;
      bool input_sensors_enable;
      bool input_overlay_enable;
      bool input_overlay_enable_autopreferred;
      bool input_overlay_behind_menu;
      bool input_overlay_hide_in_menu;
      bool input_overlay_hide_when_gamepad_connected;
      bool input_overlay_show_mouse_cursor;
      bool input_overlay_auto_rotate;
      bool input_overlay_auto_scale;
      bool input_osk_overlay_auto_scale;
      bool input_overlay_pointer_enable;
      bool input_overlay_lightgun_trigger_on_touch;
      bool input_overlay_lightgun_allow_offscreen;
      bool input_overlay_mouse_hold_to_drag;
      bool input_overlay_mouse_dtap_to_drag;
      bool input_descriptor_label_show;
      bool input_descriptor_hide_unbound;
      bool input_all_users_control_menu;
      bool input_menu_swap_ok_cancel_buttons;
      bool input_menu_swap_scroll_buttons;
      bool input_backtouch_enable;
      bool input_backtouch_toggle;
      bool input_small_keyboard_enable;
      bool input_keyboard_gamepad_enable;
      bool input_auto_mouse_grab;
      bool input_turbo_enable;
      bool input_turbo_allow_dpad;
      bool input_hotkey_device_merge;
#if defined(HAVE_DINPUT) || defined(HAVE_WINRAWINPUT)
      bool input_nowinkey_enable;
#endif
#ifdef UDEV_TOUCH_SUPPORT
      bool input_touch_vmouse_pointer;
      bool input_touch_vmouse_mouse;
      bool input_touch_vmouse_touchpad;
      bool input_touch_vmouse_trackball;
      bool input_touch_vmouse_gesture;
#endif

      /* Frame time counter */
      bool frame_time_counter_reset_after_fastforwarding;
      bool frame_time_counter_reset_after_load_state;
      bool frame_time_counter_reset_after_save_state;

      /* Menu */
      bool notification_show_autoconfig;
      bool notification_show_autoconfig_fails;
      bool notification_show_cheats_applied;
      bool notification_show_patch_applied;
      bool notification_show_remap_load;
      bool notification_show_config_override_load;
      bool notification_show_set_initial_disk;
      bool notification_show_disk_control;
      bool notification_show_save_state;
      bool notification_show_fast_forward;
#ifdef HAVE_SCREENSHOTS
      bool notification_show_screenshot;
#endif
      bool notification_show_refresh_rate;
      bool notification_show_netplay_extra;

      bool menu_pause_libretro;
      bool menu_mouse_enable;
      bool menu_linear_filter;

      bool crt_switch_hires_menu;

      /* Netplay */
      bool netplay_show_only_connectable;
      bool netplay_show_only_installed_cores;
      bool netplay_show_passworded;
      bool netplay_public_announce;
      bool netplay_start_as_spectator;
      bool netplay_fade_chat;
      bool netplay_allow_pausing;
      bool netplay_allow_slaves;
      bool netplay_require_slaves;
      bool netplay_nat_traversal;
      bool netplay_use_mitm_server;
      bool netplay_request_devices[MAX_USERS];
      bool netplay_ping_show;

      /* UI */
      bool ui_menubar_enable;
      bool ui_suspend_screensaver_enable;
      bool ui_companion_start_on_boot;
      bool ui_companion_enable;
      bool ui_companion_toggle;
      bool desktop_menu_enable;

      /* Cheevos */
      bool cheevos_enable;
      bool cheevos_test_unofficial;
      bool cheevos_hardcore_mode_enable;
      bool cheevos_richpresence_enable;
      bool cheevos_badges_enable;
      bool cheevos_verbose_enable;
      bool cheevos_auto_screenshot;
      bool cheevos_start_active;
      bool cheevos_unlock_sound_enable;
      bool cheevos_challenge_indicators;
      bool cheevos_appearance_padding_auto;
      bool cheevos_visibility_unlock;
      bool cheevos_visibility_mastery;
      bool cheevos_visibility_account;
      bool cheevos_visibility_lboard_start;
      bool cheevos_visibility_lboard_submit;
      bool cheevos_visibility_lboard_cancel;
      bool cheevos_visibility_lboard_trackers;
      bool cheevos_visibility_progress_tracker;

      /* Camera */
      bool camera_allow;

      /* Bluetooth */
      bool bluetooth_allow;

      /* WiFi */
      bool wifi_allow;
      bool wifi_enabled;

      /* Location */
      bool location_allow;

      /* Multimedia */
      bool multimedia_builtin_mediaplayer_enable;
      bool multimedia_builtin_imageviewer_enable;

      /* Driver */
      bool driver_switch_enable;

#ifdef HAVE_MIST
      /* Steam */
      bool steam_rich_presence_enable;
#endif

      /* Cloud Sync */
      bool cloud_sync_enable;
      bool cloud_sync_destructive;
      bool cloud_sync_sync_saves;
      bool cloud_sync_sync_configs;
      bool cloud_sync_sync_thumbs;
      bool cloud_sync_sync_system;

      /* Misc. */
      bool discord_enable;
      bool threaded_data_runloop_enable;
      bool set_supports_no_game_enable;
      bool auto_screenshot_filename;
      bool history_list_enable;
      bool rewind_enable;
      bool fastforward_frameskip;
      bool vrr_runloop_enable;
      bool apply_cheats_after_toggle;
      bool apply_cheats_after_load;
      bool run_ahead_enabled;
      bool run_ahead_secondary_instance;
      bool run_ahead_hide_warnings;
      bool preemptive_frames_enable;
      bool pause_nonactive;
      bool pause_on_disconnect;
      bool block_sram_overwrite;
      bool replay_auto_index;
      bool savestate_auto_index;
      bool savestate_auto_save;
      bool savestate_auto_load;
      bool savestate_thumbnail_enable;
      bool save_file_compression;
      bool savestate_file_compression;
      bool network_cmd_enable;
      bool stdin_cmd_enable;
      bool keymapper_enable;
      bool network_remote_enable;
      bool network_remote_enable_user[MAX_USERS];
      bool load_dummy_on_core_shutdown;
      bool check_firmware_before_loading;
      bool core_option_category_enable;
      bool core_info_cache_enable;
      bool core_info_savestate_bypass;
#ifndef HAVE_DYNAMIC
      bool always_reload_core_on_run_content;
#endif

      bool game_specific_options;
      bool auto_overrides_enable;
      bool auto_remaps_enable;
      bool initial_disk_change_enable;
      bool global_core_options;
      bool auto_shaders_enable;

      bool sort_savefiles_enable;
      bool sort_savestates_enable;
      bool sort_savefiles_by_content_enable;
      bool sort_savestates_by_content_enable;
      bool sort_screenshots_by_content_enable;
      bool config_save_on_exit;
      bool remap_save_on_exit;

      bool show_hidden_files;
      bool filter_by_current_core;
      bool use_last_start_directory;
      bool core_suggest_always;

      bool savefiles_in_content_dir;
      bool savestates_in_content_dir;
      bool screenshots_in_content_dir;
      bool systemfiles_in_content_dir;
      bool ssh_enable;
#ifdef HAVE_LAKKA_SWITCH
      bool switch_oc;
      bool switch_cec;
      bool bluetooth_ertm_disable;
#endif
      bool samba_enable;
      bool bluetooth_enable;
      bool localap_enable;

      bool video_window_show_decorations;
      bool video_window_save_positions;
      bool video_window_custom_size_enable;

      bool sustained_performance_mode;
      bool playlist_use_old_format;
      bool playlist_compression;

      bool playlist_fuzzy_archive_match;
      bool playlist_portable_paths;

      bool quit_press_twice;
      bool vibrate_on_keypress;
      bool enable_device_vibration;

      bool log_to_file;
      bool log_to_file_timestamp;

      bool scan_without_core_match;
      bool scan_serial_and_crc;

      bool ai_service_enable;
      bool ai_service_pause;

      bool gamemode_enable;

#ifdef ANDROID
      bool android_input_disconnect_workaround;
#endif

#if defined(HAVE_COCOATOUCH)
      bool gcdwebserver_alert;
#endif

#ifdef HAVE_GAME_AI
      bool quick_menu_show_game_ai;
      bool game_ai_override_p1;
      bool game_ai_override_p2;
      bool game_ai_show_debug;
#endif // HAVE_GAME_AI
   } bools;

   uint8_t flags;

} settings_t;

/**
 * config_get_default_camera:
 *
 * Gets default camera driver.
 *
 * Returns: Default camera driver.
 **/
const char *config_get_default_camera(void);

/**
 * config_get_default_bluetooth:
 *
 * Gets default bluetooth driver.
 *
 * Returns: Default bluetooth driver.
 **/
const char *config_get_default_bluetooth(void);

/**
 * config_get_default_wifi:
 *
 * Gets default wifi driver.
 *
 * Returns: Default wifi driver.
 **/
const char *config_get_default_wifi(void);

/**
 * config_get_default_location:
 *
 * Gets default location driver.
 *
 * Returns: Default location driver.
 **/
const char *config_get_default_location(void);

/**
 * config_get_default_video:
 *
 * Gets default video driver.
 *
 * Returns: Default video driver.
 **/
const char *config_get_default_video(void);

/**
 * config_get_default_audio:
 *
 * Gets default audio driver.
 *
 * Returns: Default audio driver.
 **/
const char *config_get_default_audio(void);

#if defined(HAVE_MICROPHONE)
/**
 * config_get_default_microphone:
 *
 * Gets default microphone driver.
 *
 * Returns: Default microphone driver.
 **/
const char *config_get_default_microphone(void);
#endif

/**
 * config_get_default_audio_resampler:
 *
 * Gets default audio resampler driver.
 *
 * Returns: Default audio resampler driver.
 **/
const char *config_get_default_audio_resampler(void);

/**
 * config_get_default_input:
 *
 * Gets default input driver.
 *
 * Returns: Default input driver.
 **/
const char *config_get_default_input(void);

/**
 * config_get_default_joypad:
 *
 * Gets default input joypad driver.
 *
 * Returns: Default input joypad driver.
 **/
const char *config_get_default_joypad(void);

const char *config_get_default_midi(void);
const char *config_get_midi_driver_options(void);

const char *config_get_default_record(void);

#ifdef HAVE_CONFIGFILE
/**
 * config_load_override:
 *
 * Tries to append game-specific and core-specific configuration.
 * These settings will always have precedence, thus this feature
 * can be used to enforce overrides.
 *
 * Returns: false if there was an error or no action was performed.
 *
 */
bool config_load_override(void *data);

/**
 * config_load_override_file:
 *
 * Tries to load specified configuration file.
 * These settings will always have precedence, thus this feature
 * can be used to enforce overrides.
 *
 * Returns: false if there was an error or no action was performed.
 *
 */
bool config_load_override_file(const char *path);

/**
 * config_unload_override:
 *
 * Unloads configuration overrides if overrides are active.
 *
 *
 * Returns: false if there was an error.
 */
bool config_unload_override(void);

/**
 * config_load_remap:
 *
 * Tries to append game-specific and core-specific remap files.
 *
 * Returns: false if there was an error or no action was performed.
 *
 */
bool config_load_remap(const char *directory_input_remapping,
      void *data);

/**
 * config_get_autoconf_profile_filename:
 * @device_name       : Input device name
 * @user              : Controller number to save
 * Fills buf with the autoconf profile file name (including driver dir if needed).
 **/

void config_get_autoconf_profile_filename(
      const char *device_name, unsigned user, char *s, size_t len);
/**
 * config_save_autoconf_profile:
 * @device_name       : Input device name
 * @user              : Controller number to save
 * Writes a controller autoconf file to disk.
 **/
bool config_save_autoconf_profile(const char *device_name, unsigned user);

/**
 * config_save_file:
 * @path            : Path that shall be written to.
 *
 * Writes a config file to disk.
 *
 * Returns: true (1) on success, otherwise returns false (0).
 **/
bool config_save_file(const char *path);

/**
 * config_save_overrides:
 * @path            : Path that shall be written to.
 *
 * Writes a config file override to disk.
 *
 * Returns: true (1) on success, (-1) if nothing to write, otherwise returns false (0).
 **/
int8_t config_save_overrides(enum override_type type,
      void *data, bool remove, const char *path);

/* Replaces currently loaded configuration file with
 * another one. Will load a dummy core to flush state
 * properly. */
bool config_replace(bool config_save_on_exit, char *path);

config_file_t *open_default_config_file(void);
#endif

bool config_overlay_enable_default(void);

void config_set_defaults(void *data);

void config_load(void *data);

#if !defined(HAVE_DYNAMIC)
/* Salamander config file contains a single
 * entry (libretro_path), which is linked to
 * RARCH_PATH_CORE
 * > Used to select which core to load
 *   when launching a salamander build */
void config_load_file_salamander(void);
void config_save_file_salamander(void);
#endif

void retroarch_config_init(void);

void retroarch_config_deinit(void);

settings_t *config_get_ptr(void);

#ifdef HAVE_LAKKA
const char *config_get_all_timezones(void);
void config_set_timezone(char *timezone);
#endif

bool input_config_bind_map_get_valid(unsigned bind_index);

const char *input_config_get_prefix(unsigned user, bool meta);

RETRO_END_DECLS

#endif
