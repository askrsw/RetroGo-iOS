//
//  command_defines.h
//  RetroArch
//
//  Created by haharsw on 2025/8/26.
//


#ifndef __COMMAND_DEFINES__H
#define __COMMAND_DEFINES__H

#include <retro_common_api.h>

RETRO_BEGIN_DECLS

enum event_command
{
    CMD_SPECIAL = -1,
    CMD_EVENT_NONE = 0,
    /* Resets RetroArch. */
    CMD_EVENT_RESET,
    CMD_EVENT_SET_PER_GAME_RESOLUTION,
    CMD_EVENT_SET_FRAME_LIMIT,
    /* Loads core. */
    CMD_EVENT_LOAD_CORE,
    CMD_EVENT_LOAD_CORE_PERSIST,
#if defined(HAVE_RUNAHEAD) && (defined(HAVE_DYNAMIC) || defined(HAVE_DYLIB))
    CMD_EVENT_LOAD_SECOND_CORE,
#endif
    CMD_EVENT_UNLOAD_CORE,
    /* Closes content. */
    CMD_EVENT_CLOSE_CONTENT,
    /* Swaps the current state with what's on the undo load buffer. */
    CMD_EVENT_UNDO_LOAD_STATE,
    /* Rewrites a savestate on disk. */
    CMD_EVENT_UNDO_SAVE_STATE,
    /* Save state hotkeys. */
    CMD_EVENT_LOAD_STATE,
    CMD_EVENT_SAVE_STATE,
    CMD_EVENT_SAVE_STATE_DECREMENT,
    CMD_EVENT_SAVE_STATE_INCREMENT,
    /* Replay hotkeys. */
    CMD_EVENT_PLAY_REPLAY,
    CMD_EVENT_RECORD_REPLAY,
    CMD_EVENT_HALT_REPLAY,
    CMD_EVENT_REPLAY_DECREMENT,
    CMD_EVENT_REPLAY_INCREMENT,
    /* Save state actions. */
    CMD_EVENT_SAVE_STATE_TO_RAM,
    CMD_EVENT_LOAD_STATE_FROM_RAM,
    CMD_EVENT_RAM_STATE_TO_FILE,
    /* Takes screenshot. */
    CMD_EVENT_TAKE_SCREENSHOT,
    /* Quits RetroArch. */
    CMD_EVENT_QUIT,
    /* Reinitialize all drivers. */
    CMD_EVENT_REINIT_FROM_TOGGLE,
    /* Reinitialize all drivers. */
    CMD_EVENT_REINIT,
    /* Toggles cheevos hardcore mode. */
    CMD_EVENT_CHEEVOS_HARDCORE_MODE_TOGGLE,
    /* Deinitialize rewind. */
    CMD_EVENT_REWIND_DEINIT,
    /* Initializes rewind. */
    CMD_EVENT_REWIND_INIT,
    /* Reinitializes rewind (primarily if the state size changes). */
    CMD_EVENT_REWIND_REINIT,
    /* Toggles rewind. */
    CMD_EVENT_REWIND_TOGGLE,
    /* Initializes autosave. */
    CMD_EVENT_AUTOSAVE_INIT,
    /* Stops audio. */
    CMD_EVENT_AUDIO_STOP,
    /* Starts audio. */
    CMD_EVENT_AUDIO_START,
    /* Mutes audio. */
    CMD_EVENT_AUDIO_MUTE_TOGGLE,
    /* Volume adjustments. */
    CMD_EVENT_VOLUME_UP,
    CMD_EVENT_VOLUME_DOWN,
    CMD_EVENT_MIXER_VOLUME_UP,
    CMD_EVENT_MIXER_VOLUME_DOWN,
    /* Toggles FPS counter. */
    CMD_EVENT_FPS_TOGGLE,
    /* Toggles statistics display. */
    CMD_EVENT_STATISTICS_TOGGLE,
    /* Initializes overlay. */
    CMD_EVENT_OVERLAY_INIT,
    /* Frees or caches overlay. */
    CMD_EVENT_OVERLAY_UNLOAD,
    /* Sets current scale factor for overlay. */
    CMD_EVENT_OVERLAY_SET_SCALE_FACTOR,
    /* Sets current alpha modulation for overlay. */
    CMD_EVENT_OVERLAY_SET_ALPHA_MOD,
    /* Sets diagonal sensitivities of overlay eightway areas. */
    CMD_EVENT_OVERLAY_SET_EIGHTWAY_DIAGONAL_SENSITIVITY,
    /* Deinitializes overlay. */
    CMD_EVENT_DSP_FILTER_INIT,
    /* Initializes recording system. */
    CMD_EVENT_RECORD_INIT,
    /* Deinitializes recording system. */
    CMD_EVENT_RECORD_DEINIT,
    /* Deinitializes history playlist. */
    CMD_EVENT_HISTORY_DEINIT,
    /* Initializes history playlist. */
    CMD_EVENT_HISTORY_INIT,
    /* Deinitializes core information. */
    CMD_EVENT_CORE_INFO_DEINIT,
    /* Initializes core information. */
    CMD_EVENT_CORE_INFO_INIT,
    /* Deinitializes core. */
    CMD_EVENT_CORE_DEINIT,
    /* Initializes core. */
    CMD_EVENT_CORE_INIT,
    /* Apply video state changes. */
    CMD_EVENT_VIDEO_APPLY_STATE_CHANGES,
    /* Set video blocking state. */
    CMD_EVENT_VIDEO_SET_BLOCKING_STATE,
    /* Sets current aspect ratio index. */
    CMD_EVENT_VIDEO_SET_ASPECT_RATIO,
    /* Restarts RetroArch. */
    CMD_EVENT_RESTART_RETROARCH,
    /* Shutdown the OS */
    CMD_EVENT_SHUTDOWN,
    /* Reboot the OS */
    CMD_EVENT_REBOOT,
    /* Resume RetroArch when in menu. */
    CMD_EVENT_RESUME,
    /* Add a playlist entry to favorites. */
    CMD_EVENT_ADD_TO_FAVORITES,
    /* Reset playlist entry associated core to DETECT */
    CMD_EVENT_RESET_CORE_ASSOCIATION,
    /* Toggles pause. */
    CMD_EVENT_PAUSE_TOGGLE,
    /* Pauses RetroArch. */
    CMD_EVENT_MENU_PAUSE_LIBRETRO,
    CMD_EVENT_PAUSE,
    /* Unpauses RetroArch. */
    CMD_EVENT_UNPAUSE,
    /* Toggles menu on/off. */
    CMD_EVENT_MENU_TOGGLE,
    /* Configuration saving. */
    CMD_EVENT_MENU_RESET_TO_DEFAULT_CONFIG,
    CMD_EVENT_MENU_SAVE_CONFIG,
    CMD_EVENT_MENU_SAVE_AS_CONFIG,
    CMD_EVENT_MENU_SAVE_MAIN_CONFIG,
    CMD_EVENT_MENU_SAVE_CURRENT_CONFIG,
    CMD_EVENT_MENU_SAVE_CURRENT_CONFIG_OVERRIDE_CORE,
    CMD_EVENT_MENU_SAVE_CURRENT_CONFIG_OVERRIDE_CONTENT_DIR,
    CMD_EVENT_MENU_SAVE_CURRENT_CONFIG_OVERRIDE_GAME,
    CMD_EVENT_MENU_REMOVE_CURRENT_CONFIG_OVERRIDE_CORE,
    CMD_EVENT_MENU_REMOVE_CURRENT_CONFIG_OVERRIDE_CONTENT_DIR,
    CMD_EVENT_MENU_REMOVE_CURRENT_CONFIG_OVERRIDE_GAME,
    /* Applies shader changes. */
    CMD_EVENT_SHADERS_APPLY_CHANGES,
    /* A new shader preset has been loaded */
    CMD_EVENT_SHADER_PRESET_LOADED,
    /* Shader hotkeys. */
    CMD_EVENT_SHADER_NEXT,
    CMD_EVENT_SHADER_PREV,
    CMD_EVENT_SHADER_TOGGLE,
    /* Apply cheats. */
    CMD_EVENT_CHEATS_APPLY,
    /* Cheat hotkeys. */
    CMD_EVENT_CHEAT_TOGGLE,
    CMD_EVENT_CHEAT_INDEX_PLUS,
    CMD_EVENT_CHEAT_INDEX_MINUS,
    /* Initializes network system. */
    CMD_EVENT_NETWORK_INIT,
    /* Initializes netplay system with a string or no host specified. */
    CMD_EVENT_NETPLAY_INIT,
    /* Initializes netplay system with a direct host specified. */
    CMD_EVENT_NETPLAY_INIT_DIRECT,
    /* Initializes netplay system with a direct host specified after loading content. */
    CMD_EVENT_NETPLAY_INIT_DIRECT_DEFERRED,
    /* Deinitializes netplay system. */
    CMD_EVENT_NETPLAY_DEINIT,
    /* Switch between netplay gaming and watching. */
    CMD_EVENT_NETPLAY_GAME_WATCH,
    /* Open a netplay chat input menu. */
    CMD_EVENT_NETPLAY_PLAYER_CHAT,
    /* Toggle chat fading. */
    CMD_EVENT_NETPLAY_FADE_CHAT_TOGGLE,
    /* Start hosting netplay. */
    CMD_EVENT_NETPLAY_ENABLE_HOST,
    /* Disconnect from the netplay host. */
    CMD_EVENT_NETPLAY_DISCONNECT,
    /* Toggle ping counter. */
    CMD_EVENT_NETPLAY_PING_TOGGLE,
    /* Toggles netplay hosting. */
    CMD_EVENT_NETPLAY_HOST_TOGGLE,
    /* Reinitializes audio driver. */
    CMD_EVENT_AUDIO_REINIT,
    /* Resizes windowed scale. Will reinitialize video driver. */
    CMD_EVENT_RESIZE_WINDOWED_SCALE,
    /* Toggles disk eject. */
    CMD_EVENT_DISK_EJECT_TOGGLE,
    /* Cycle to next disk. */
    CMD_EVENT_DISK_NEXT,
    /* Cycle to previous disk. */
    CMD_EVENT_DISK_PREV,
    /* Switch to specified disk index */
    CMD_EVENT_DISK_INDEX,
    /* Appends disk image to disk image list. */
    CMD_EVENT_DISK_APPEND_IMAGE,
    /* Stops rumbling. */
    CMD_EVENT_RUMBLE_STOP,
    /* Toggles turbo fire. */
    CMD_EVENT_TURBO_FIRE_TOGGLE,
    /* Toggles mouse grab. */
    CMD_EVENT_GRAB_MOUSE_TOGGLE,
    /* Toggles game focus. */
    CMD_EVENT_GAME_FOCUS_TOGGLE,
    /* Toggles desktop menu. */
    CMD_EVENT_UI_COMPANION_TOGGLE,
    /* Toggles fullscreen mode. */
    CMD_EVENT_FULLSCREEN_TOGGLE,
    /* Toggle recording. */
    CMD_EVENT_RECORDING_TOGGLE,
    /* Toggle streaming. */
    CMD_EVENT_STREAMING_TOGGLE,
    /* Toggle Run-Ahead. */
    CMD_EVENT_RUNAHEAD_TOGGLE,
    /* Toggle Preemtive Frames. */
    CMD_EVENT_PREEMPT_TOGGLE,
    /* Deinitialize or Reinitialize Preemptive Frames. */
    CMD_EVENT_PREEMPT_UPDATE,
    /* Force Preemptive Frames to refill its state buffer. */
    CMD_EVENT_PREEMPT_RESET_BUFFER,
    /* Toggle VRR runloop. */
    CMD_EVENT_VRR_RUNLOOP_TOGGLE,
    /* AI service. */
    CMD_EVENT_AI_SERVICE_TOGGLE,
    CMD_EVENT_AI_SERVICE_CALL,
    /* Misc. */
    CMD_EVENT_SAVE_FILES,
    CMD_EVENT_LOAD_FILES,
    CMD_EVENT_CONTROLLER_INIT,
    CMD_EVENT_DISCORD_INIT,
    CMD_EVENT_PRESENCE_UPDATE,
    CMD_EVENT_OVERLAY_NEXT,
    CMD_EVENT_OSK_TOGGLE,
    CMD_EVENT_RELOAD_CONFIG,
#ifdef HAVE_MICROPHONE
    /* Stops all enabled microphones. */
    CMD_EVENT_MICROPHONE_STOP,
    /* Starts all enabled microphones */
    CMD_EVENT_MICROPHONE_START,
    /* Reinitializes microphone driver. */
    CMD_EVENT_MICROPHONE_REINIT,
#endif
    /* Add a playlist entry to another playlist. */
    CMD_EVENT_ADD_TO_PLAYLIST
};

RETRO_END_DECLS

#endif
