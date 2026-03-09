/*  RetroArch - A frontend for libretro.
 *  Copyright (C) 2010-2014 - Hans-Kristian Arntzen
 *  Copyright (C) 2011-2017 - Daniel De Matteis
 *  Copyright (C) 2014-2017 - Jean-André Santoni
 *  Copyright (C) 2015-2019 - Andrés Suárez (input remapping + other things)
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

#include <ctype.h>

#include <libretro.h>
#include <file/config_file.h>
#include <file/file_path.h>
#include <compat/strl.h>
#include <compat/posix_string.h>
#include <string/stdstring.h>
#include <streams/file_stream.h>
#include <array/rhmap.h>

#include <utils/file_path_special.h>
#include <emu/command.h>
#include <utils/configuration.h>
#include <emu/content.h>
#include <utils/config.def.h>
#include <utils/config.features.h>
#include <defines/led_defines.h>
#include <utils/defaults.h>
#include <core/core.h>
#include <utils/retro_paths.h>
#include <main/retroarch.h>
#include <utils/verbosity.h>

#include <audio/audio_driver.h>
#include <record/record_driver.h>

#include <tasks/task_content.h>
#include <tasks/tasks_internal.h>

#include <utils/list_special.h>

#if __APPLE__
extern bool RAIsVoiceOverRunning(void);
extern bool ios_running_on_ipad(void);
#endif

#ifdef HAVE_NETWORKING
#include <defines/netplay_defines.h>
#endif

enum video_driver_enum
{
   VIDEO_GL                 = 0,
   VIDEO_GL1,
   VIDEO_GL_CORE,
   VIDEO_VULKAN,
   VIDEO_METAL,
   VIDEO_DRM,
   VIDEO_XVIDEO,
   VIDEO_SDL,
   VIDEO_SDL2,
   VIDEO_SDL_DINGUX,
   VIDEO_SDL_RS90,
   VIDEO_EXT,
   VIDEO_WII,
   VIDEO_WIIU,
   VIDEO_XENON360,
   VIDEO_PSP1,
   VIDEO_VITA2D,
   VIDEO_PS2,
   VIDEO_CTR,
   VIDEO_SWITCH,
   VIDEO_D3D8,
   VIDEO_D3D9_CG,
   VIDEO_D3D9_HLSL,
   VIDEO_D3D10,
   VIDEO_D3D11,
   VIDEO_D3D12,
   VIDEO_VG,
   VIDEO_OMAP,
   VIDEO_EXYNOS,
   VIDEO_SUNXI,
   VIDEO_DISPMANX,
   VIDEO_CACA,
   VIDEO_GDI,
   VIDEO_VGA,
   VIDEO_FPGA,
   VIDEO_RSX,
   VIDEO_NULL
};

enum audio_driver_enum
{
   AUDIO_RSOUND             = VIDEO_NULL + 1,
   AUDIO_AUDIOIO,
   AUDIO_OSS,
   AUDIO_ALSA,
   AUDIO_ALSATHREAD,
   AUDIO_TINYALSA,
   AUDIO_ROAR,
   AUDIO_AL,
   AUDIO_SL,
   AUDIO_JACK,
   AUDIO_SDL,
   AUDIO_SDL2,
   AUDIO_XAUDIO,
   AUDIO_PULSE,
   AUDIO_EXT,
   AUDIO_DSOUND,
   AUDIO_WASAPI,
   AUDIO_COREAUDIO,
   AUDIO_COREAUDIO3,
   AUDIO_PS3,
   AUDIO_XENON360,
   AUDIO_WII,
   AUDIO_WIIU,
   AUDIO_RWEBAUDIO,
   AUDIO_AUDIOWORKLET,
   AUDIO_PSP,
   AUDIO_PS2,
   AUDIO_CTR,
   AUDIO_SWITCH,
   AUDIO_PIPEWIRE,
   AUDIO_NULL
};

enum microphone_driver_enum
{
   MICROPHONE_ALSA = AUDIO_NULL + 1,
   MICROPHONE_ALSATHREAD,
   MICROPHONE_SDL2,
   MICROPHONE_WASAPI,
   MICROPHONE_PIPEWIRE,
   MICROPHONE_COREAUDIO,
   MICROPHONE_NULL
};

enum audio_resampler_driver_enum
{
   AUDIO_RESAMPLER_CC       = MICROPHONE_NULL + 1,
   AUDIO_RESAMPLER_SINC,
   AUDIO_RESAMPLER_NEAREST,
   AUDIO_RESAMPLER_NULL
};

enum input_driver_enum
{
   INPUT_ANDROID            = AUDIO_RESAMPLER_NULL + 1,
   INPUT_SDL,
   INPUT_SDL2,
   INPUT_SDL_DINGUX,
   INPUT_X,
   INPUT_WAYLAND,
   INPUT_DINPUT,
   INPUT_PS4,
   INPUT_PS3,
   INPUT_PSP,
   INPUT_PS2,
   INPUT_CTR,
   INPUT_SWITCH,
   INPUT_XENON360,
   INPUT_WII,
   INPUT_WIIU,
   INPUT_XINPUT,
   INPUT_UWP,
   INPUT_UDEV,
   INPUT_LINUXRAW,
   INPUT_COCOA,
   INPUT_QNX,
   INPUT_RWEBINPUT,
   INPUT_DOS,
   INPUT_WINRAW,
   INPUT_NULL
};

enum joypad_driver_enum
{
   JOYPAD_PS3               = INPUT_NULL + 1,
   JOYPAD_XINPUT,
   JOYPAD_GX,
   JOYPAD_WIIU,
   JOYPAD_XDK,
   JOYPAD_PS4,
   JOYPAD_PSP,
   JOYPAD_PS2,
   JOYPAD_CTR,
   JOYPAD_SWITCH,
   JOYPAD_DINPUT,
   JOYPAD_UDEV,
   JOYPAD_LINUXRAW,
   JOYPAD_ANDROID,
   JOYPAD_SDL,
   JOYPAD_SDL_DINGUX,
   JOYPAD_DOS,
   JOYPAD_HID,
   JOYPAD_QNX,
   JOYPAD_RWEBPAD,
   JOYPAD_MFI,
   JOYPAD_NULL
};

enum camera_driver_enum
{
   CAMERA_V4L2              = JOYPAD_NULL + 1,
   CAMERA_RWEBCAM,
   CAMERA_ANDROID,
   CAMERA_AVFOUNDATION,
   CAMERA_PIPEWIRE,
   CAMERA_FFMPEG,
   CAMERA_NULL
};

enum bluetooth_driver_enum
{
   BLUETOOTH_BLUETOOTHCTL   = CAMERA_NULL + 1,
   BLUETOOTH_BLUEZ,
   BLUETOOTH_NULL
};

enum wifi_driver_enum
{
   WIFI_CONNMANCTL          = BLUETOOTH_NULL + 1,
   WIFI_NMCLI,
   WIFI_NULL
};

enum location_driver_enum
{
   LOCATION_ANDROID         = WIFI_NULL + 1,
   LOCATION_CORELOCATION,
   LOCATION_NULL
};

enum osk_driver_enum
{
   OSK_PS3                  = LOCATION_NULL + 1,
   OSK_NULL
};

enum menu_driver_enum
{
   MENU_RGUI                = OSK_NULL + 1,
   MENU_MATERIALUI,
   MENU_XMB,
   MENU_STRIPES,
   MENU_OZONE,
   MENU_NULL
};

enum record_driver_enum
{
   RECORD_FFMPEG            = MENU_NULL + 1,
   RECORD_WAV,
   RECORD_NULL
};

enum midi_driver_enum
{
   MIDI_WINMM               = RECORD_NULL + 1,
   MIDI_ALSA,
   MIDI_COREMIDI,
   MIDI_NULL
};

#if defined(HAVE_METAL)
#if defined(HAVE_VULKAN)
/* Default to Vulkan/MoltenVK when available */
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_VULKAN;
#else
/* iOS supports both the OpenGL and Metal video drivers; default to OpenGL since Metal support is preliminary */
#if defined(HAVE_COCOATOUCH) && defined(HAVE_OPENGL)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_GL;
#else
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_METAL;
#endif
#endif
#elif defined(HAVE_D3D11) || defined(__WINRT__) || (defined(WINAPI_FAMILY) && WINAPI_FAMILY == WINAPI_FAMILY_PHONE_APP)
/* Default to D3D11 in UWP, even when its compiled with ANGLE, since ANGLE is just calling D3D anyway.*/
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_D3D11;
#elif defined(HAVE_OPENGL1) && defined(_MSC_VER) && (_MSC_VER <= 1600)
/* On Windows XP and earlier, use gl1 by default
 * (regular opengl has compatibility issues with
 * obsolete hardware drivers...) */
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_GL1;
#elif defined(HAVE_VITA2D)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_VITA2D;
#elif defined(HAVE_OPENGL) || defined(HAVE_OPENGLES) || defined(HAVE_PSGL)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_GL;
#elif defined(HAVE_OPENGL_CORE) && !defined(__HAIKU__)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_GL_CORE;
#elif defined(HAVE_OPENGL1)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_GL1;
#elif defined(HAVE_VULKAN)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_VULKAN;
#elif defined(GEKKO)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_WII;
#elif defined(WIIU)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_WIIU;
#elif defined(XENON)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_XENON360;
#elif defined(HAVE_D3D12)
/* FIXME/WARNING: DX12 performance on Xbox is horrible for
 * some reason. For now, we will default to D3D11 when possible. */
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_D3D12;
#elif defined(HAVE_D3D10)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_D3D10;
#elif defined(HAVE_D3D9)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_D3D9;
#elif defined(HAVE_D3D8)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_D3D8;
#elif defined(HAVE_VG)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_VG;
#elif defined(PSP)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_PSP1;
#elif defined(PS2)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_PS2;
#elif defined(SWITCH)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_SWITCH;
#elif defined(HAVE_XVIDEO)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_XVIDEO;
#elif defined(HAVE_SDL) && !defined(HAVE_SDL_DINGUX)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_SDL;
#elif defined(HAVE_SDL2)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_SDL2;
#elif defined(HAVE_SDL_DINGUX)
#if defined(RS90) || defined(MIYOO)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_SDL_RS90;
#else
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_SDL_DINGUX;
#endif
#elif defined(_WIN32) && !defined(_XBOX)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_GDI;
#elif defined(DJGPP)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_VGA;
#elif defined(HAVE_FPGA)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_FPGA;
#elif defined(HAVE_DYLIB) && !defined(ANDROID)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_EXT;
#elif defined(__PSL1GHT__)
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_RSX;
#else
static const enum video_driver_enum VIDEO_DEFAULT_DRIVER = VIDEO_NULL;
#endif

#if defined(XENON)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_XENON360;
#elif defined(GEKKO)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_WII;
#elif defined(WIIU)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_WIIU;
#elif defined(PSP) || defined(VITA) || defined(ORBIS)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_PSP;
#elif defined(PS2)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_PS2;
#elif defined(__PS3__)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_PS3;
#elif defined(SWITCH)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_SWITCH;
#elif (defined(DINGUX_BETA) || defined(MIYOO)) && defined(HAVE_ALSA)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_ALSA;
#elif defined(DINGUX) && defined(HAVE_AL)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_AL;
#elif defined(HAVE_PULSE)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_PULSE;
#elif defined(HAVE_PIPEWIRE)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_PIPEWIRE;
#elif defined(HAVE_ALSA) && defined(HAVE_THREADS)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_ALSATHREAD;
#elif defined(HAVE_ALSA)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_ALSA;
#elif defined(HAVE_TINYALSA)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_TINYALSA;
#elif defined(HAVE_AUDIOIO)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_AUDIOIO;
#elif defined(HAVE_OSS)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_OSS;
#elif defined(HAVE_JACK)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_JACK;
#elif defined(HAVE_COREAUDIO3) || defined(HAVE_COREAUDIO)
/* SDL microphone does not play well with coreaudio audio driver */
#if defined(HAVE_SDL2) && defined(HAVE_MICROPHONE)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_SDL2;
#elif defined(HAVE_COREAUDIO3)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_COREAUDIO3;
#elif defined(HAVE_COREAUDIO)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_COREAUDIO;
#endif
#elif defined(HAVE_WASAPI)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_WASAPI;
#elif defined(HAVE_XAUDIO)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_XAUDIO;
#elif defined(HAVE_DSOUND)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_DSOUND;
#elif defined(HAVE_AL)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_AL;
#elif defined(HAVE_SL)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_SL;
#elif defined(HAVE_AUDIOWORKLET)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_AUDIOWORKLET;
#elif defined(HAVE_RWEBAUDIO)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_RWEBAUDIO;
#elif defined(HAVE_SDL)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_SDL;
#elif defined(HAVE_SDL2)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_SDL2;
#elif defined(HAVE_RSOUND)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_RSOUND;
#elif defined(HAVE_ROAR)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_ROAR;
#elif defined(HAVE_DYLIB) && !defined(ANDROID)
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_EXT;
#else
static const enum audio_driver_enum AUDIO_DEFAULT_DRIVER = AUDIO_NULL;
#endif

#if defined(HAVE_MICROPHONE)
#if defined(HAVE_WASAPI)
/* The default mic driver on Windows is WASAPI if it's available. */
static const enum microphone_driver_enum MICROPHONE_DEFAULT_DRIVER = MICROPHONE_WASAPI;
#elif defined(HAVE_ALSA) && defined(HAVE_THREADS)
/* The default mic driver on Linux is the threaded ALSA driver, if available. */
static const enum microphone_driver_enum MICROPHONE_DEFAULT_DRIVER = MICROPHONE_ALSATHREAD;
#elif defined(HAVE_ALSA)
static const enum microphone_driver_enum MICROPHONE_DEFAULT_DRIVER = MICROPHONE_ALSA;
#elif defined(HAVE_PIPEWIRE)
static const enum microphone_driver_enum MICROPHONE_DEFAULT_DRIVER = MICROPHONE_PIPEWIRE;
#elif defined(HAVE_SDL2)
/* The default fallback driver is SDL2, if available. */
static const enum microphone_driver_enum MICROPHONE_DEFAULT_DRIVER = MICROPHONE_SDL2;
#elif defined(HAVE_COREAUDIO)
static const enum microphone_driver_enum MICROPHONE_DEFAULT_DRIVER = MICROPHONE_COREAUDIO;
#else
static const enum microphone_driver_enum MICROPHONE_DEFAULT_DRIVER = MICROPHONE_NULL;
#endif
#endif

#if defined(RS90) || defined(MIYOO)
static const enum audio_resampler_driver_enum AUDIO_DEFAULT_RESAMPLER_DRIVER = AUDIO_RESAMPLER_NEAREST;
#elif defined(PSP) || (defined(EMSCRIPTEN) && defined(HAVE_CC_RESAMPLER))
static const enum audio_resampler_driver_enum AUDIO_DEFAULT_RESAMPLER_DRIVER = AUDIO_RESAMPLER_CC;
#else
static const enum audio_resampler_driver_enum AUDIO_DEFAULT_RESAMPLER_DRIVER = AUDIO_RESAMPLER_SINC;
#endif

#if defined(HAVE_FFMPEG)
static const enum record_driver_enum RECORD_DEFAULT_DRIVER = RECORD_FFMPEG;
#else
static const enum record_driver_enum RECORD_DEFAULT_DRIVER = RECORD_WAV;
#endif

#ifdef HAVE_WINMM
static const enum midi_driver_enum MIDI_DEFAULT_DRIVER = MIDI_WINMM;
#elif defined(HAVE_COREMIDI)
static const enum midi_driver_enum MIDI_DEFAULT_DRIVER = MIDI_COREMIDI;
#elif defined(HAVE_ALSA) && !defined(HAVE_HAKCHI) && !defined(HAVE_SEGAM) && !defined(DINGUX)
static const enum midi_driver_enum MIDI_DEFAULT_DRIVER = MIDI_ALSA;
#else
static const enum midi_driver_enum MIDI_DEFAULT_DRIVER = MIDI_NULL;
#endif

#if defined(HAVE_STEAM) && defined(__linux__) && defined(HAVE_SDL2)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_SDL2;
#elif defined(__WINRT__) || defined(WINAPI_FAMILY) && WINAPI_FAMILY == WINAPI_FAMILY_PHONE_APP
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_UWP;
#elif defined(XENON)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_XENON360;
#elif defined(_XBOX360) || defined(_XBOX) || defined(HAVE_XINPUT2) || defined(HAVE_XINPUT_XBOX1)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_XINPUT;
#elif defined(ANDROID)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_ANDROID;
#elif defined(EMSCRIPTEN) && defined(HAVE_SDL2)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_SDL2;
#elif defined(WEBOS) && defined(HAVE_SDL2)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_SDL2;
#elif defined(EMSCRIPTEN)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_RWEBINPUT;
#elif defined(_WIN32) && defined(HAVE_DINPUT)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_DINPUT;
#elif defined(_WIN32) && !defined(HAVE_DINPUT) && _WIN32_WINNT >= 0x0501
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_WINRAW;
#elif defined(PS2)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_PS2;
#elif defined(__PS3__)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_PS3;
#elif defined(ORBIS)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_PS4;
#elif defined(PSP) || defined(VITA)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_PSP;
#elif defined(SWITCH)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_SWITCH;
#elif defined(GEKKO)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_WII;
#elif defined(WIIU)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_WIIU;
#elif defined(DINGUX) && defined(HAVE_SDL_DINGUX)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_SDL_DINGUX;
#elif defined(HAVE_X11)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_X;
#elif defined(HAVE_UDEV)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_UDEV;
#elif defined(__linux__) && !defined(ANDROID)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_LINUXRAW;
#elif defined(HAVE_WAYLAND)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_WAYLAND;
#elif defined(HAVE_COCOA) || defined(HAVE_COCOATOUCH) || defined(HAVE_COCOA_METAL)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_COCOA;
#elif defined(__QNX__)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_QNX;
#elif defined(HAVE_SDL)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_SDL;
#elif defined(HAVE_SDL2)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_SDL2;
#elif defined(DJGPP)
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_DOS;
#else
static const enum input_driver_enum INPUT_DEFAULT_DRIVER = INPUT_NULL;
#endif

#if defined(HAVE_STEAM) && defined(__linux__) && defined(HAVE_SDL2)
static const enum joypad_driver_enum JOYPAD_DEFAULT_DRIVER = JOYPAD_SDL;
#elif defined(HAVE_XINPUT)
static const enum joypad_driver_enum JOYPAD_DEFAULT_DRIVER = JOYPAD_XINPUT;
#elif defined(GEKKO)
static const enum joypad_driver_enum JOYPAD_DEFAULT_DRIVER = JOYPAD_GX;
#elif defined(WIIU)
static const enum joypad_driver_enum JOYPAD_DEFAULT_DRIVER = JOYPAD_WIIU;
#elif defined(WEBOS)
static const enum joypad_driver_enum JOYPAD_DEFAULT_DRIVER = JOYPAD_SDL;
#elif defined(_XBOX)
static const enum joypad_driver_enum JOYPAD_DEFAULT_DRIVER = JOYPAD_XDK;
#elif defined(PS2)
static const enum joypad_driver_enum JOYPAD_DEFAULT_DRIVER = JOYPAD_PS2;
#elif defined(__PS3__) || defined(__PSL1GHT__)
static const enum joypad_driver_enum JOYPAD_DEFAULT_DRIVER = JOYPAD_PS3;
#elif defined(ORBIS)
static const enum joypad_driver_enum JOYPAD_DEFAULT_DRIVER = JOYPAD_PS4;
#elif defined(PSP) || defined(VITA)
static const enum joypad_driver_enum JOYPAD_DEFAULT_DRIVER = JOYPAD_PSP;
#elif defined(SWITCH)
static const enum joypad_driver_enum JOYPAD_DEFAULT_DRIVER = JOYPAD_SWITCH;
#elif defined(DINGUX) && defined(HAVE_SDL_DINGUX)
static const enum joypad_driver_enum JOYPAD_DEFAULT_DRIVER = JOYPAD_SDL_DINGUX;
#elif defined(HAVE_DINPUT)
static const enum joypad_driver_enum JOYPAD_DEFAULT_DRIVER = JOYPAD_DINPUT;
#elif defined(HAVE_UDEV)
static const enum joypad_driver_enum JOYPAD_DEFAULT_DRIVER = JOYPAD_UDEV;
#elif defined(__linux) && !defined(ANDROID)
static const enum joypad_driver_enum JOYPAD_DEFAULT_DRIVER = JOYPAD_LINUXRAW;
#elif defined(ANDROID)
static const enum joypad_driver_enum JOYPAD_DEFAULT_DRIVER = JOYPAD_ANDROID;
#elif defined(HAVE_MFI)
static const enum joypad_driver_enum JOYPAD_DEFAULT_DRIVER = JOYPAD_MFI;
#elif defined(HAVE_SDL) || defined(HAVE_SDL2)
static const enum joypad_driver_enum JOYPAD_DEFAULT_DRIVER = JOYPAD_SDL;
#elif defined(DJGPP)
static const enum joypad_driver_enum JOYPAD_DEFAULT_DRIVER = JOYPAD_DOS;
#elif defined(HAVE_HID)
static const enum joypad_driver_enum JOYPAD_DEFAULT_DRIVER = JOYPAD_HID;
#elif defined(__QNX__)
static const enum joypad_driver_enum JOYPAD_DEFAULT_DRIVER = JOYPAD_QNX;
#elif defined(EMSCRIPTEN)
static const enum joypad_driver_enum JOYPAD_DEFAULT_DRIVER = JOYPAD_RWEBPAD;
#else
static const enum joypad_driver_enum JOYPAD_DEFAULT_DRIVER = JOYPAD_NULL;
#endif

#if defined(HAVE_V4L2)
static const enum camera_driver_enum CAMERA_DEFAULT_DRIVER = CAMERA_V4L2;
#elif defined(EMSCRIPTEN)
static const enum camera_driver_enum CAMERA_DEFAULT_DRIVER = CAMERA_RWEBCAM;
#elif defined(ANDROID)
static const enum camera_driver_enum CAMERA_DEFAULT_DRIVER = CAMERA_ANDROID;
#elif defined(HAVE_PIPEWIRE)
static const enum camera_driver_enum CAMERA_DEFAULT_DRIVER = CAMERA_PIPEWIRE;
#elif defined(HAVE_FFMPEG)
static const enum camera_driver_enum CAMERA_DEFAULT_DRIVER = CAMERA_FFMPEG;
#elif defined(HAVE_AVF)
static const enum camera_driver_enum CAMERA_DEFAULT_DRIVER = CAMERA_AVFOUNDATION;
#else
static const enum camera_driver_enum CAMERA_DEFAULT_DRIVER = CAMERA_NULL;
#endif

#if defined(HAVE_BLUETOOTH)
# if defined(HAVE_DBUS)
static const enum bluetooth_driver_enum BLUETOOTH_DEFAULT_DRIVER = BLUETOOTH_BLUEZ;
# else
static const enum bluetooth_driver_enum BLUETOOTH_DEFAULT_DRIVER = BLUETOOTH_BLUETOOTHCTL;
# endif
#else
static const enum bluetooth_driver_enum BLUETOOTH_DEFAULT_DRIVER = BLUETOOTH_NULL;
#endif

#if defined(HAVE_LAKKA)
static const enum wifi_driver_enum WIFI_DEFAULT_DRIVER = WIFI_CONNMANCTL;
#else
static const enum wifi_driver_enum WIFI_DEFAULT_DRIVER = WIFI_NULL;
#endif

#if defined(ANDROID)
static const enum location_driver_enum LOCATION_DEFAULT_DRIVER = LOCATION_ANDROID;
#elif defined(HAVE_CORELOCATION)
static const enum location_driver_enum LOCATION_DEFAULT_DRIVER = LOCATION_CORELOCATION;
#else
static const enum location_driver_enum LOCATION_DEFAULT_DRIVER = LOCATION_NULL;
#endif

/* All config related settings go here. */
enum config_bool_flags
{
   CFG_BOOL_FLG_DEF_ENABLE = (1 << 0),
   CFG_BOOL_FLG_HANDLE     = (1 << 1)
};

struct config_bool_setting
{
   const char *ident;
   bool *ptr;
   enum rarch_override_setting override;
   uint8_t flags;
   bool def;
};

struct config_int_setting
{
   const char *ident;
   int *ptr;
   int def;
   enum rarch_override_setting override;
   uint8_t flags;
};

struct config_uint_setting
{
   const char *ident;
   unsigned *ptr;
   unsigned def;
   enum rarch_override_setting override;
   uint8_t flags;
};

struct config_size_setting
{
   const char *ident;
   size_t *ptr;
   size_t def;
   enum rarch_override_setting override;
   uint8_t flags;
};

struct config_float_setting
{
   const char *ident;
   float *ptr;
   float def;
   enum rarch_override_setting override;
   uint8_t flags;
};

struct config_array_setting
{
   const char *ident;
   const char *def;
   char *ptr;
   enum rarch_override_setting override;
   uint8_t flags;
};

struct config_path_setting
{
   const char *ident;
   char *ptr;
   char *def;
   uint8_t flags;
};

#define GENERAL_SETTING(key, configval, default_enable, default_setting, type, handle_setting) \
{ \
   tmp[count].ident      = key; \
   tmp[count].ptr        = configval; \
   if (default_enable) \
   { \
      tmp[count].flags |= CFG_BOOL_FLG_DEF_ENABLE; \
      tmp[count].def    = default_setting; \
   } \
   if (handle_setting) \
      tmp[count].flags |= CFG_BOOL_FLG_HANDLE; \
   count++; \
}

#define SETTING_BOOL(key, configval, default_enable, default_setting, handle_setting) \
   GENERAL_SETTING(key, configval, default_enable, default_setting, struct config_bool_setting, handle_setting)

#define SETTING_FLOAT(key, configval, default_enable, default_setting, handle_setting) \
   GENERAL_SETTING(key, configval, default_enable, default_setting, struct config_float_setting, handle_setting)

#define SETTING_INT(key, configval, default_enable, default_setting, handle_setting) \
   GENERAL_SETTING(key, configval, default_enable, default_setting, struct config_int_setting, handle_setting)

#define SETTING_UINT(key, configval, default_enable, default_setting, handle_setting) \
   GENERAL_SETTING(key, configval, default_enable, default_setting, struct config_uint_setting, handle_setting)

#define SETTING_SIZE(key, configval, default_enable, default_setting, handle_setting) \
   GENERAL_SETTING(key, configval, default_enable, default_setting, struct config_size_setting, handle_setting)

#define SETTING_PATH(key, configval, default_enable, default_setting, handle_setting) \
   GENERAL_SETTING(key, configval, default_enable, default_setting, struct config_path_setting, handle_setting)

#define SETTING_ARRAY(key, configval, default_enable, default_setting, handle_setting) \
   GENERAL_SETTING(key, configval, default_enable, default_setting, struct config_array_setting, handle_setting)

#define SETTING_OVERRIDE(override_setting) \
   tmp[count-1].override = override_setting

/* Forward declarations */
#ifdef HAVE_CONFIGFILE
static void config_parse_file(global_t *global);
#endif

struct defaults g_defaults;

static settings_t *config_st = NULL;

settings_t *config_get_ptr(void)
{
   return config_st;
}

/**
 * config_get_default_audio:
 *
 * Gets default audio driver.
 *
 * Returns: Default audio driver.
 **/
const char *config_get_default_audio(void)
{
   enum audio_driver_enum default_driver = AUDIO_DEFAULT_DRIVER;

   switch (default_driver)
   {
      case AUDIO_RSOUND:
         return "rsound";
      case AUDIO_AUDIOIO:
         return "audioio";
      case AUDIO_OSS:
         return "oss";
      case AUDIO_ALSA:
         return "alsa";
      case AUDIO_ALSATHREAD:
         return "alsathread";
      case AUDIO_TINYALSA:
         return "tinyalsa";
      case AUDIO_ROAR:
         return "roar";
      case AUDIO_COREAUDIO:
         return "coreaudio";
      case AUDIO_COREAUDIO3:
         return "coreaudio3";
      case AUDIO_AL:
         return "openal";
      case AUDIO_SL:
         return "opensl";
      case AUDIO_SDL:
         return "sdl";
      case AUDIO_SDL2:
         return "sdl2";
      case AUDIO_DSOUND:
         return "dsound";
      case AUDIO_WASAPI:
         return "wasapi";
      case AUDIO_XAUDIO:
         return "xaudio";
      case AUDIO_PULSE:
         return "pulse";
      case AUDIO_PIPEWIRE:
         return "pipewire";
      case AUDIO_EXT:
         return "ext";
      case AUDIO_XENON360:
         return "xenon360";
      case AUDIO_PS3:
         return "ps3";
      case AUDIO_WII:
         return "gx";
      case AUDIO_WIIU:
         return "AX";
      case AUDIO_PSP:
#if defined(VITA)
         return "vita";
#elif defined(ORBIS)
         return "orbis";
#else
         return "psp";
#endif
      case AUDIO_PS2:
         return "ps2";
      case AUDIO_CTR:
         return "dsp";
      case AUDIO_SWITCH:
#if defined(HAVE_LIBNX)
         return "switch_audren_thread";
#else
         return "switch";
#endif
      case AUDIO_RWEBAUDIO:
         return "rwebaudio";
      case AUDIO_AUDIOWORKLET:
         return "audioworklet";
      case AUDIO_JACK:
         return "jack";
      case AUDIO_NULL:
         break;
   }

   return "null";
}

#if defined(HAVE_MICROPHONE)
/**
 * config_get_default_microphone:
 *
 * Gets default microphone driver.
 *
 * Returns: Default microphone driver.
 **/
const char *config_get_default_microphone(void)
{
   enum microphone_driver_enum default_driver = MICROPHONE_DEFAULT_DRIVER;

   switch (default_driver)
   {
      case MICROPHONE_ALSA:
         return "alsa";
      case MICROPHONE_ALSATHREAD:
         return "alsathread";
      case MICROPHONE_PIPEWIRE:
         return "pipewire";
      case MICROPHONE_WASAPI:
         return "wasapi";
      case MICROPHONE_SDL2:
         return "sdl2";
      case MICROPHONE_COREAUDIO:
         return "coreaudio";
      case MICROPHONE_NULL:
         break;
   }

   return "null";
}
#endif


const char *config_get_default_record(void)
{
   enum record_driver_enum default_driver = RECORD_DEFAULT_DRIVER;

   switch (default_driver)
   {
      case RECORD_FFMPEG:
         return "ffmpeg";
      case RECORD_WAV:
         return "wav";
      case RECORD_NULL:
         break;
   }

   return "null";
}

/**
 * config_get_default_audio_resampler:
 *
 * Gets default audio resampler driver.
 *
 * Returns: Default audio resampler driver.
 **/
const char *config_get_default_audio_resampler(void)
{
   enum audio_resampler_driver_enum default_driver = AUDIO_DEFAULT_RESAMPLER_DRIVER;

   switch (default_driver)
   {
      case AUDIO_RESAMPLER_CC:
         return "cc";
      case AUDIO_RESAMPLER_SINC:
         return "sinc";
      case AUDIO_RESAMPLER_NEAREST:
         return "nearest";
      case AUDIO_RESAMPLER_NULL:
         break;
   }

   return "null";
}

/**
 * config_get_default_video:
 *
 * Gets default video driver.
 *
 * Returns: Default video driver.
 **/
const char *config_get_default_video(void)
{
   enum video_driver_enum default_driver = VIDEO_DEFAULT_DRIVER;

   switch (default_driver)
   {
      case VIDEO_GL:
         return "gl";
      case VIDEO_GL1:
         return "gl1";
      case VIDEO_GL_CORE:
         return "glcore";
      case VIDEO_VULKAN:
         return "vulkan";
      case VIDEO_METAL:
         return "metal";
      case VIDEO_DRM:
         return "drm";
      case VIDEO_WII:
         return "gx";
      case VIDEO_WIIU:
         return "gx2";
      case VIDEO_XENON360:
         return "xenon360";
      case VIDEO_D3D8:
         return "d3d8";
      case VIDEO_D3D9_CG:
         return "d3d9_cg";
      case VIDEO_D3D9_HLSL:
         return "d3d9_hlsl";
      case VIDEO_D3D10:
         return "d3d10";
      case VIDEO_D3D11:
         return "d3d11";
      case VIDEO_D3D12:
         return "d3d12";
      case VIDEO_PSP1:
         return "psp1";
      case VIDEO_PS2:
         return "ps2";
      case VIDEO_VITA2D:
         return "vita2d";
      case VIDEO_CTR:
         return "ctr";
      case VIDEO_SWITCH:
         return "switch";
      case VIDEO_XVIDEO:
         return "xvideo";
      case VIDEO_SDL_DINGUX:
         return "sdl_dingux";
      case VIDEO_SDL_RS90:
         return "sdl_rs90";
      case VIDEO_SDL:
         return "sdl";
      case VIDEO_SDL2:
         return "sdl2";
      case VIDEO_EXT:
         return "ext";
      case VIDEO_VG:
         return "vg";
      case VIDEO_OMAP:
         return "omap";
      case VIDEO_EXYNOS:
         return "exynos";
      case VIDEO_DISPMANX:
         return "dispmanx";
      case VIDEO_SUNXI:
         return "sunxi";
      case VIDEO_CACA:
         return "caca";
      case VIDEO_GDI:
         return "gdi";
      case VIDEO_VGA:
         return "vga";
      case VIDEO_FPGA:
         return "fpga";
      case VIDEO_RSX:
         return "rsx";
      case VIDEO_NULL:
         break;
   }

   return "null";
}

/**
 * config_get_default_input:
 *
 * Gets default input driver.
 *
 * Returns: Default input driver.
 **/
const char *config_get_default_input(void)
{
   enum input_driver_enum default_driver = INPUT_DEFAULT_DRIVER;

   switch (default_driver)
   {
      case INPUT_ANDROID:
         return "android";
      case INPUT_PS4:
         return "ps4";
      case INPUT_PS3:
         return "ps3";
      case INPUT_PSP:
#ifdef VITA
         return "vita";
#else
         return "psp";
#endif
      case INPUT_PS2:
         return "ps2";
      case INPUT_CTR:
         return "ctr";
      case INPUT_SWITCH:
         return "switch";
      case INPUT_SDL:
         return "sdl";
      case INPUT_SDL2:
         return "sdl2";
      case INPUT_SDL_DINGUX:
         return "sdl_dingux";
      case INPUT_DINPUT:
         return "dinput";
      case INPUT_WINRAW:
         return "raw";
      case INPUT_X:
         return "x";
      case INPUT_WAYLAND:
         return "wayland";
      case INPUT_XENON360:
         return "xenon360";
      case INPUT_XINPUT:
         return "xinput";
      case INPUT_UWP:
         return "uwp";
      case INPUT_WII:
         return "gx";
      case INPUT_WIIU:
         return "wiiu";
      case INPUT_LINUXRAW:
         return "linuxraw";
      case INPUT_UDEV:
         return "udev";
      case INPUT_COCOA:
         return "cocoa";
      case INPUT_QNX:
          return "qnx_input";
      case INPUT_RWEBINPUT:
          return "rwebinput";
      case INPUT_DOS:
         return "dos";
      case INPUT_NULL:
          break;
   }

   return "null";
}

/**
 * config_get_default_joypad:
 *
 * Gets default input joypad driver.
 *
 * Returns: Default input joypad driver.
 **/
const char *config_get_default_joypad(void)
{
   enum joypad_driver_enum default_driver = JOYPAD_DEFAULT_DRIVER;

   switch (default_driver)
   {
      case JOYPAD_PS4:
         return "ps4";
      case JOYPAD_PS3:
         return "ps3";
      case JOYPAD_XINPUT:
         return "xinput";
      case JOYPAD_GX:
         return "gx";
      case JOYPAD_WIIU:
         return "wiiu";
      case JOYPAD_XDK:
         return "xdk";
      case JOYPAD_PSP:
#ifdef VITA
         return "vita";
#else
         return "psp";
#endif
      case JOYPAD_PS2:
         return "ps2";
      case JOYPAD_CTR:
         return "ctr";
      case JOYPAD_SWITCH:
         return "switch";
      case JOYPAD_DINPUT:
         return "dinput";
      case JOYPAD_UDEV:
         return "udev";
      case JOYPAD_LINUXRAW:
         return "linuxraw";
      case JOYPAD_ANDROID:
         return "android";
      case JOYPAD_SDL:
#ifdef HAVE_SDL2
         return "sdl2";
#else
         return "sdl";
#endif
      case JOYPAD_SDL_DINGUX:
         return "sdl_dingux";
      case JOYPAD_HID:
         return "hid";
      case JOYPAD_QNX:
         return "qnx";
      case JOYPAD_RWEBPAD:
         return "rwebpad";
      case JOYPAD_DOS:
         return "dos";
      case JOYPAD_MFI:
         return "mfi";
      case JOYPAD_NULL:
         break;
   }

   return "null";
}

/**
 * config_get_default_camera:
 *
 * Gets default camera driver.
 *
 * Returns: Default camera driver.
 **/
const char *config_get_default_camera(void)
{
   enum camera_driver_enum default_driver = CAMERA_DEFAULT_DRIVER;

   switch (default_driver)
   {
      case CAMERA_V4L2:
         return "video4linux2";
      case CAMERA_RWEBCAM:
         return "rwebcam";
      case CAMERA_ANDROID:
         return "android";
      case CAMERA_AVFOUNDATION:
         return "avfoundation";
      case CAMERA_PIPEWIRE:
         return "pipewire";
      case CAMERA_FFMPEG:
         return "ffmpeg";
      case CAMERA_NULL:
         break;
   }

   return "null";
}

/**
 * config_get_default_bluetooth:
 *
 * Gets default bluetooth driver.
 *
 * Returns: Default bluetooth driver.
 **/
const char *config_get_default_bluetooth(void)
{
   enum bluetooth_driver_enum default_driver = BLUETOOTH_DEFAULT_DRIVER;

   switch (default_driver)
   {
      case BLUETOOTH_BLUETOOTHCTL:
         return "bluetoothctl";
      case BLUETOOTH_BLUEZ:
         return "bluez";
      case BLUETOOTH_NULL:
         break;
   }

   return "null";
}

/**
 * config_get_default_wifi:
 *
 * Gets default wifi driver.
 *
 * Returns: Default wifi driver.
 **/
const char *config_get_default_wifi(void)
{
   enum wifi_driver_enum default_driver = WIFI_DEFAULT_DRIVER;

   switch (default_driver)
   {
      case WIFI_CONNMANCTL:
         return "connmanctl";
      case WIFI_NMCLI:
         return "nmcli";
      case WIFI_NULL:
         break;
   }

   return "null";
}

/**
 * config_get_default_led:
 *
 * Gets default led driver.
 *
 * Returns: Default led driver.
 **/
const char *config_get_default_led(void)
{
   return "null";
}

/**
 * config_get_default_cloudsync:
 *
 * Gets default cloud sync driver.
 *
 * Returns: Default cloud sync driver.
 **/
const char *config_get_default_cloudsync(void)
{
   return "null";
}

/**
 * config_get_default_location:
 *
 * Gets default location driver.
 *
 * Returns: Default location driver.
 **/
const char *config_get_default_location(void)
{
   enum location_driver_enum default_driver = LOCATION_DEFAULT_DRIVER;

   switch (default_driver)
   {
      case LOCATION_ANDROID:
         return "android";
      case LOCATION_CORELOCATION:
         return "corelocation";
      case LOCATION_NULL:
         break;
   }

   return "null";
}

const char *config_get_default_midi(void)
{
   enum midi_driver_enum default_driver = MIDI_DEFAULT_DRIVER;

   switch (default_driver)
   {
      case MIDI_WINMM:
         return "winmm";
      case MIDI_ALSA:
         return "alsa";
      case MIDI_COREMIDI:
         return "coremidi";
      case MIDI_NULL:
         break;
   }

   return "null";
}

const char *config_get_midi_driver_options(void)
{
   return char_list_new_special(STRING_LIST_MIDI_DRIVERS, NULL);
}

#ifdef HAVE_LAKKA
void config_set_timezone(char *timezone)
{
   setenv("TZ", timezone, 1);
   tzset();
}

const char *config_get_all_timezones(void)
{
   return char_list_new_special(STRING_LIST_TIMEZONES, NULL);
}

static void load_timezone(char *s, size_t len)
{
   char haystack[TIMEZONE_LENGTH+32];
   RFILE *tzfp             = filestream_open(LAKKA_TIMEZONE_PATH,
                       RETRO_VFS_FILE_ACCESS_READ,
                       RETRO_VFS_FILE_ACCESS_HINT_NONE);
   if (tzfp)
   {
      static char *needle = "TIMEZONE=";
      char *start = NULL;

      filestream_gets(tzfp, haystack, sizeof(haystack)-1);
      filestream_close(tzfp);

      if ((start = strstr(haystack, needle)))
         strlcpy(s, start + STRLEN_CONST("TIMEZONE="), len);
      else
         strlcpy(s, DEFAULT_TIMEZONE, len);
   }
   else
      strlcpy(s, DEFAULT_TIMEZONE, len);
   config_set_timezone(s);
}
#endif

bool config_overlay_enable_default(void)
{
   if (g_defaults.overlay_set)
      return g_defaults.overlay_enable;
#if defined(RARCH_MOBILE) && !TARGET_OS_TV
   return true;
#else
   return false;
#endif
}

static struct config_array_setting *populate_settings_array(
      settings_t *settings, int *size)
{
   unsigned i                           = 0;
   unsigned count                       = 0;
   struct config_array_setting  *tmp    = (struct config_array_setting*)calloc(1, (*size + 1) * sizeof(struct config_array_setting));

   if (!tmp)
      return NULL;

   /* Arrays */
   SETTING_ARRAY("audio_driver",                 settings->arrays.audio_driver, false, NULL, true);
   SETTING_ARRAY("audio_device",                 settings->arrays.audio_device, false, NULL, true);
   SETTING_ARRAY("audio_resampler",              settings->arrays.audio_resampler, false, NULL, true);
#ifdef HAVE_MICROPHONE
   SETTING_ARRAY("microphone_device",            settings->arrays.microphone_device, false, NULL, true);
   SETTING_ARRAY("microphone_driver",            settings->arrays.microphone_driver, false, NULL, true);
   SETTING_ARRAY("microphone_resampler",         settings->arrays.microphone_resampler, false, NULL, true);
#endif
   SETTING_ARRAY("midi_driver",                  settings->arrays.midi_driver, false, NULL, true);
   SETTING_ARRAY("midi_input",                   settings->arrays.midi_input, true, DEFAULT_MIDI_INPUT, true);
   SETTING_ARRAY("midi_output",                  settings->arrays.midi_output, true, DEFAULT_MIDI_OUTPUT, true);

   SETTING_ARRAY("video_driver",                 settings->arrays.video_driver, false, NULL, true);
   SETTING_ARRAY("video_context_driver",         settings->arrays.video_context_driver, false, NULL, true);
   SETTING_ARRAY("crt_switch_timings",           settings->arrays.crt_switch_timings, false, NULL, true);

   SETTING_ARRAY("input_driver",                 settings->arrays.input_driver, false, NULL, true);
   SETTING_ARRAY("input_joypad_driver",          settings->arrays.input_joypad_driver, false, NULL, true);
   SETTING_ARRAY("input_keyboard_layout",        settings->arrays.input_keyboard_layout, false, NULL, true);
#ifdef ANDROID
   SETTING_ARRAY("input_android_physical_keyboard", settings->arrays.input_android_physical_keyboard, false, NULL, true);
#endif

   for (i = 0; i < MAX_USERS; i++)
   {
      char key[32];
      size_t _len  = strlcpy(key, "input_player", sizeof(key));
      _len += snprintf(key + _len, sizeof(key) - _len, "%u", i + 1);
      strlcpy(key + _len, "_reserved_device", sizeof(key) - _len);
      SETTING_ARRAY(strdup(key), settings->arrays.input_reserved_devices[i], false, NULL, true);
   }

   SETTING_ARRAY("record_driver",                settings->arrays.record_driver, false, NULL, true);
   SETTING_ARRAY("camera_driver",                settings->arrays.camera_driver, false, NULL, true);
   SETTING_ARRAY("camera_device",                settings->arrays.camera_device, false, NULL, true);
   SETTING_ARRAY("bluetooth_driver",             settings->arrays.bluetooth_driver, false, NULL, true);
   SETTING_ARRAY("wifi_driver",                  settings->arrays.wifi_driver, false, NULL, true);
   SETTING_ARRAY("led_driver",                   settings->arrays.led_driver, false, NULL, true);
   SETTING_ARRAY("location_driver",              settings->arrays.location_driver, false, NULL, true);
   SETTING_ARRAY("cloud_sync_driver",            settings->arrays.cloud_sync_driver, false, NULL, true);

#ifdef HAVE_CHEEVOS
   SETTING_ARRAY("cheevos_custom_host",          settings->arrays.cheevos_custom_host, false, NULL, true);
   SETTING_ARRAY("cheevos_username",             settings->arrays.cheevos_username, false, NULL, true);
   SETTING_ARRAY("cheevos_password",             settings->arrays.cheevos_password, false, NULL, true);
   SETTING_ARRAY("cheevos_token",                settings->arrays.cheevos_token, false, NULL, true);
   SETTING_ARRAY("cheevos_leaderboards_enable",  settings->arrays.cheevos_leaderboards_enable, true, "", true); /* deprecated */
#endif

#ifdef HAVE_NETWORKING
   SETTING_ARRAY("netplay_mitm_server",          settings->arrays.netplay_mitm_server, false, NULL, true);
   SETTING_ARRAY("webdav_url",                   settings->arrays.webdav_url, false, NULL, true);
   SETTING_ARRAY("webdav_username",              settings->arrays.webdav_username, false, NULL, true);
   SETTING_ARRAY("webdav_password",              settings->arrays.webdav_password, false, NULL, true);
   SETTING_ARRAY("youtube_stream_key",           settings->arrays.youtube_stream_key, true, NULL, true);
   SETTING_ARRAY("twitch_stream_key",            settings->arrays.twitch_stream_key, true, NULL, true);
   SETTING_ARRAY("facebook_stream_key",          settings->arrays.facebook_stream_key, true, NULL, true);
   SETTING_ARRAY("discord_app_id",               settings->arrays.discord_app_id, true, DEFAULT_DISCORD_APP_ID, true);
   SETTING_ARRAY("ai_service_url",               settings->arrays.ai_service_url, true, DEFAULT_AI_SERVICE_URL, true);
#endif

#ifdef HAVE_LAKKA
   SETTING_ARRAY("cpu_main_gov",                 settings->arrays.cpu_main_gov, false, NULL, true);
   SETTING_ARRAY("cpu_menu_gov",                 settings->arrays.cpu_menu_gov, false, NULL, true);
#endif

   *size = count;

   return tmp;
}

static struct config_path_setting *populate_settings_path(
      settings_t *settings, int *size)
{
   unsigned count = 0;
   recording_state_t *recording_st     = recording_state_get_ptr();
   struct config_path_setting  *tmp    = (struct config_path_setting*)calloc(1, (*size + 1) * sizeof(struct config_path_setting));

   if (!tmp)
      return NULL;

   /* Paths */
   SETTING_PATH("core_options_path",             settings->paths.path_core_options, false, NULL, true);
   SETTING_PATH("video_filter",                  settings->paths.path_softfilter_plugin, false, NULL, true);
   SETTING_PATH("video_font_path",               settings->paths.path_font, false, NULL, true);
   SETTING_PATH("video_record_config",           settings->paths.path_record_config, false, NULL, true);
   SETTING_PATH("video_stream_config",           settings->paths.path_stream_config, false, NULL, true);
   SETTING_PATH("recording_output_directory",    recording_st->output_dir, false, NULL, true);
   SETTING_PATH("recording_config_directory",    recording_st->config_dir, false, NULL, true);

#ifdef HAVE_NETWORKING
   SETTING_PATH("netplay_ip_address",            settings->paths.netplay_server, false, NULL, true);
   SETTING_PATH("netplay_custom_mitm_server",    settings->paths.netplay_custom_mitm_server, false, NULL, true);
   SETTING_PATH("netplay_nickname",              settings->paths.username, false, NULL, true);
   SETTING_PATH("netplay_password",              settings->paths.netplay_password, false, NULL, true);
   SETTING_PATH("netplay_spectate_password",     settings->paths.netplay_spectate_password, false, NULL, true);
#endif // HAVE_NETWORKING

#ifdef HAVE_TEST_DRIVERS
   SETTING_PATH("test_input_file_joypad",        settings->paths.test_input_file_joypad,  false, NULL, true);
   SETTING_PATH("test_input_file_general",       settings->paths.test_input_file_general, false, NULL, true);
#endif

   *size = count;

   return tmp;
}

static struct config_bool_setting *populate_settings_bool(
      settings_t *settings, int *size)
{
   struct config_bool_setting  *tmp    = (struct config_bool_setting*)calloc(1, (*size + 1) * sizeof(struct config_bool_setting));
   unsigned count                      = 0;

   SETTING_BOOL("accessibility_enable",          &settings->bools.accessibility_enable, true, DEFAULT_ACCESSIBILITY_ENABLE, false);
   SETTING_BOOL("driver_switch_enable",          &settings->bools.driver_switch_enable, true, DEFAULT_DRIVER_SWITCH_ENABLE, false);
   SETTING_BOOL("ui_companion_start_on_boot",    &settings->bools.ui_companion_start_on_boot, true, DEFAULT_UI_COMPANION_START_ON_BOOT, false);
   SETTING_BOOL("ui_companion_enable",           &settings->bools.ui_companion_enable, true, DEFAULT_UI_COMPANION_ENABLE, false);
   SETTING_BOOL("ui_companion_toggle",           &settings->bools.ui_companion_toggle, false, DEFAULT_UI_COMPANION_TOGGLE, false);
   SETTING_BOOL("desktop_menu_enable",           &settings->bools.desktop_menu_enable, true, DEFAULT_DESKTOP_MENU_ENABLE, false);
   SETTING_BOOL("video_gpu_record",              &settings->bools.video_gpu_record, true, DEFAULT_GPU_RECORD, false);
   SETTING_BOOL("input_descriptor_label_show",   &settings->bools.input_descriptor_label_show, true, DEFAULT_INPUT_DESCRIPTOR_LABEL_SHOW, false);
   SETTING_BOOL("input_descriptor_hide_unbound", &settings->bools.input_descriptor_hide_unbound, true, DEFAULT_INPUT_DESCRIPTOR_HIDE_UNBOUND, false);
   SETTING_BOOL("load_dummy_on_core_shutdown",   &settings->bools.load_dummy_on_core_shutdown, true, DEFAULT_LOAD_DUMMY_ON_CORE_SHUTDOWN, false);
   SETTING_BOOL("check_firmware_before_loading", &settings->bools.check_firmware_before_loading, true, DEFAULT_CHECK_FIRMWARE_BEFORE_LOADING, false);
   SETTING_BOOL("core_option_category_enable",   &settings->bools.core_option_category_enable, true, DEFAULT_CORE_OPTION_CATEGORY_ENABLE, false);
   SETTING_BOOL("core_info_savestate_bypass",    &settings->bools.core_info_savestate_bypass, true, DEFAULT_CORE_INFO_SAVESTATE_BYPASS, false);
#if defined(__WINRT__) || defined(WINAPI_FAMILY) && WINAPI_FAMILY == WINAPI_FAMILY_PHONE_APP
   SETTING_BOOL("core_info_cache_enable",        &settings->bools.core_info_cache_enable, false, DEFAULT_CORE_INFO_CACHE_ENABLE, false);
#else
   SETTING_BOOL("core_info_cache_enable",        &settings->bools.core_info_cache_enable, true, DEFAULT_CORE_INFO_CACHE_ENABLE, false);
#endif
   SETTING_BOOL("core_set_supports_no_game_enable", &settings->bools.set_supports_no_game_enable, true, true, false);
#ifndef HAVE_DYNAMIC
   SETTING_BOOL("always_reload_core_on_run_content", &settings->bools.always_reload_core_on_run_content, true, DEFAULT_ALWAYS_RELOAD_CORE_ON_RUN_CONTENT, false);
#endif
   SETTING_BOOL("builtin_mediaplayer_enable",    &settings->bools.multimedia_builtin_mediaplayer_enable, true, DEFAULT_BUILTIN_MEDIAPLAYER_ENABLE, false);
   SETTING_BOOL("builtin_imageviewer_enable",    &settings->bools.multimedia_builtin_imageviewer_enable, true, DEFAULT_BUILTIN_IMAGEVIEWER_ENABLE, false);
   SETTING_BOOL("fps_show",                      &settings->bools.video_fps_show, true, DEFAULT_FPS_SHOW, false);
   SETTING_BOOL("statistics_show",               &settings->bools.video_statistics_show, true, DEFAULT_STATISTICS_SHOW, false);
   SETTING_BOOL("framecount_show",               &settings->bools.video_framecount_show, true, DEFAULT_FRAMECOUNT_SHOW, false);
   SETTING_BOOL("memory_show",                   &settings->bools.video_memory_show, true, DEFAULT_MEMORY_SHOW, false);
   SETTING_BOOL("ui_menubar_enable",             &settings->bools.ui_menubar_enable, true, DEFAULT_UI_MENUBAR_ENABLE, false);
   SETTING_BOOL("pause_nonactive",               &settings->bools.pause_nonactive, true, DEFAULT_PAUSE_NONACTIVE, false);
   SETTING_BOOL("pause_on_disconnect",           &settings->bools.pause_on_disconnect, true, DEFAULT_PAUSE_ON_DISCONNECT, false);
   SETTING_BOOL("auto_screenshot_filename",      &settings->bools.auto_screenshot_filename, true, DEFAULT_AUTO_SCREENSHOT_FILENAME, false);
   SETTING_BOOL("suspend_screensaver_enable",    &settings->bools.ui_suspend_screensaver_enable, true, true, false);
   SETTING_BOOL("apply_cheats_after_toggle",     &settings->bools.apply_cheats_after_toggle, true, DEFAULT_APPLY_CHEATS_AFTER_TOGGLE, false);
   SETTING_BOOL("apply_cheats_after_load",       &settings->bools.apply_cheats_after_load, true, DEFAULT_APPLY_CHEATS_AFTER_LOAD, false);
   SETTING_BOOL("rewind_enable",                 &settings->bools.rewind_enable, true, DEFAULT_REWIND_ENABLE, false);
   SETTING_BOOL("fastforward_frameskip",         &settings->bools.fastforward_frameskip, true, DEFAULT_FASTFORWARD_FRAMESKIP, false);
   SETTING_BOOL("vrr_runloop_enable",            &settings->bools.vrr_runloop_enable, true, DEFAULT_VRR_RUNLOOP_ENABLE, false);
   SETTING_BOOL("run_ahead_enabled",             &settings->bools.run_ahead_enabled, true, false, false);
   SETTING_BOOL("run_ahead_secondary_instance",  &settings->bools.run_ahead_secondary_instance, true, DEFAULT_RUN_AHEAD_SECONDARY_INSTANCE, false);
   SETTING_BOOL("run_ahead_hide_warnings",       &settings->bools.run_ahead_hide_warnings, true, DEFAULT_RUN_AHEAD_HIDE_WARNINGS, false);
   SETTING_BOOL("preemptive_frames_enable",      &settings->bools.preemptive_frames_enable, true, false, false);
   SETTING_BOOL("block_sram_overwrite",          &settings->bools.block_sram_overwrite, true, DEFAULT_BLOCK_SRAM_OVERWRITE, false);
   SETTING_BOOL("replay_auto_index",             &settings->bools.replay_auto_index, true, DEFAULT_REPLAY_AUTO_INDEX, false);
   SETTING_BOOL("savestate_auto_index",          &settings->bools.savestate_auto_index, true, DEFAULT_SAVESTATE_AUTO_INDEX, false);
   SETTING_BOOL("savestate_auto_save",           &settings->bools.savestate_auto_save, true, DEFAULT_SAVESTATE_AUTO_SAVE, false);
   SETTING_BOOL("savestate_auto_load",           &settings->bools.savestate_auto_load, true, DEFAULT_SAVESTATE_AUTO_LOAD, false);
   SETTING_BOOL("savestate_thumbnail_enable",    &settings->bools.savestate_thumbnail_enable, true, DEFAULT_SAVESTATE_THUMBNAIL_ENABLE, false);
   SETTING_BOOL("save_file_compression",         &settings->bools.save_file_compression, true, DEFAULT_SAVE_FILE_COMPRESSION, false);
   SETTING_BOOL("savestate_file_compression",    &settings->bools.savestate_file_compression, true, DEFAULT_SAVESTATE_FILE_COMPRESSION, false);
   SETTING_BOOL("game_specific_options",         &settings->bools.game_specific_options, true, DEFAULT_GAME_SPECIFIC_OPTIONS, false);
   SETTING_BOOL("auto_overrides_enable",         &settings->bools.auto_overrides_enable, true, DEFAULT_AUTO_OVERRIDES_ENABLE, false);
   SETTING_BOOL("auto_remaps_enable",            &settings->bools.auto_remaps_enable, true, DEFAULT_AUTO_REMAPS_ENABLE, false);
   SETTING_BOOL("initial_disk_change_enable",    &settings->bools.initial_disk_change_enable, true, DEFAULT_INITIAL_DISK_CHANGE_ENABLE, false);
   SETTING_BOOL("global_core_options",           &settings->bools.global_core_options, true, DEFAULT_GLOBAL_CORE_OPTIONS, false);
   SETTING_BOOL("auto_shaders_enable",           &settings->bools.auto_shaders_enable, true, DEFAULT_AUTO_SHADERS_ENABLE, false);
   SETTING_BOOL("scan_without_core_match",       &settings->bools.scan_without_core_match, true, DEFAULT_SCAN_WITHOUT_CORE_MATCH, false);
   SETTING_BOOL("scan_serial_and_crc",           &settings->bools.scan_serial_and_crc, true, DEFAULT_SCAN_SERIAL_AND_CRC, false);
   SETTING_BOOL("sort_savefiles_enable",              &settings->bools.sort_savefiles_enable, true, DEFAULT_SORT_SAVEFILES_ENABLE, false);
   SETTING_BOOL("sort_savestates_enable",             &settings->bools.sort_savestates_enable, true, DEFAULT_SORT_SAVESTATES_ENABLE, false);
   SETTING_BOOL("sort_savefiles_by_content_enable",   &settings->bools.sort_savefiles_by_content_enable, true, DEFAULT_SORT_SAVEFILES_BY_CONTENT_ENABLE, false);
   SETTING_BOOL("sort_savestates_by_content_enable",  &settings->bools.sort_savestates_by_content_enable, true, DEFAULT_SORT_SAVESTATES_BY_CONTENT_ENABLE, false);
   SETTING_BOOL("sort_screenshots_by_content_enable", &settings->bools.sort_screenshots_by_content_enable, true, DEFAULT_SORT_SCREENSHOTS_BY_CONTENT_ENABLE, false);
   SETTING_BOOL("savestates_in_content_dir",     &settings->bools.savestates_in_content_dir, true, DEFAULT_SAVESTATES_IN_CONTENT_DIR, false);
   SETTING_BOOL("savefiles_in_content_dir",      &settings->bools.savefiles_in_content_dir, true, DEFAULT_SAVEFILES_IN_CONTENT_DIR, false);
   SETTING_BOOL("systemfiles_in_content_dir",    &settings->bools.systemfiles_in_content_dir, true, DEFAULT_SYSTEMFILES_IN_CONTENT_DIR, false);
   SETTING_BOOL("screenshots_in_content_dir",    &settings->bools.screenshots_in_content_dir, true, DEFAULT_SCREENSHOTS_IN_CONTENT_DIR, false);
   SETTING_BOOL("quit_press_twice",              &settings->bools.quit_press_twice, true, DEFAULT_QUIT_PRESS_TWICE, false);
   SETTING_BOOL("config_save_on_exit",           &settings->bools.config_save_on_exit, true, DEFAULT_CONFIG_SAVE_ON_EXIT, false);
   SETTING_BOOL("remap_save_on_exit",            &settings->bools.remap_save_on_exit, true, DEFAULT_REMAP_SAVE_ON_EXIT, false);
   SETTING_BOOL("show_hidden_files",             &settings->bools.show_hidden_files, true, DEFAULT_SHOW_HIDDEN_FILES, false);
   SETTING_BOOL("use_last_start_directory",      &settings->bools.use_last_start_directory, true, DEFAULT_USE_LAST_START_DIRECTORY, false);
   SETTING_BOOL("core_suggest_always",           &settings->bools.core_suggest_always, true, DEFAULT_CORE_SUGGEST_ALWAYS, false);
   SETTING_BOOL("camera_allow",                  &settings->bools.camera_allow, true, false, false);
   SETTING_BOOL("location_allow",                &settings->bools.location_allow, true, false, false);
   SETTING_BOOL("cloud_sync_enable",             &settings->bools.cloud_sync_enable, true, false, false);
   SETTING_BOOL("cloud_sync_destructive",        &settings->bools.cloud_sync_destructive, true, false, false);
   SETTING_BOOL("cloud_sync_sync_saves",         &settings->bools.cloud_sync_sync_saves, true, true, false);
   SETTING_BOOL("cloud_sync_sync_configs",       &settings->bools.cloud_sync_sync_configs, true, true, false);
   SETTING_BOOL("cloud_sync_sync_thumbs",        &settings->bools.cloud_sync_sync_thumbs, true, false, false);
   SETTING_BOOL("cloud_sync_sync_system",        &settings->bools.cloud_sync_sync_system, true, false, false);
   SETTING_BOOL("discord_allow",                 &settings->bools.discord_enable, true, false, false);
#ifdef HAVE_MIST
   SETTING_BOOL("steam_rich_presence_enable",    &settings->bools.steam_rich_presence_enable, true, false, false);
#endif
#ifdef HAVE_THREADS
   SETTING_BOOL("threaded_data_runloop_enable",  &settings->bools.threaded_data_runloop_enable, true, DEFAULT_THREADED_DATA_RUNLOOP_ENABLE, false);
#endif
   SETTING_BOOL("log_to_file",                   &settings->bools.log_to_file, true, DEFAULT_LOG_TO_FILE, false);
   SETTING_OVERRIDE(RARCH_OVERRIDE_SETTING_LOG_TO_FILE);
   SETTING_BOOL("log_to_file_timestamp",         &settings->bools.log_to_file_timestamp, true, DEFAULT_LOG_TO_FILE_TIMESTAMP, false);
   SETTING_BOOL("ai_service_enable",             &settings->bools.ai_service_enable, true, DEFAULT_AI_SERVICE_ENABLE, false);
   SETTING_BOOL("ai_service_pause",              &settings->bools.ai_service_pause, true, DEFAULT_AI_SERVICE_PAUSE, false);
   SETTING_BOOL("wifi_enabled",                  &settings->bools.wifi_enabled, true, DEFAULT_WIFI_ENABLE, false);
#ifndef HAVE_LAKKA
   SETTING_BOOL("gamemode_enable",               &settings->bools.gamemode_enable, true, DEFAULT_GAMEMODE_ENABLE, false);
#endif
#ifdef HAVE_LAKKA_SWITCH
   SETTING_BOOL("switch_oc",                     &settings->bools.switch_oc, true, DEFAULT_SWITCH_OC, false);
   SETTING_BOOL("switch_cec",                    &settings->bools.switch_cec, true, DEFAULT_SWITCH_CEC, false);
   SETTING_BOOL("bluetooth_ertm_disable",        &settings->bools.bluetooth_ertm_disable, true, DEFAULT_BLUETOOTH_ERTM, false);
#endif
   SETTING_BOOL("audio_enable",                  &settings->bools.audio_enable, true, DEFAULT_AUDIO_ENABLE, false);
   SETTING_BOOL("audio_sync",                    &settings->bools.audio_sync, true, DEFAULT_AUDIO_SYNC, false);
   SETTING_BOOL("audio_rate_control",            &settings->bools.audio_rate_control, true, DEFAULT_RATE_CONTROL, false);
   SETTING_BOOL("audio_enable_menu",             &settings->bools.audio_enable_menu, true, DEFAULT_AUDIO_ENABLE_MENU, false);
   SETTING_BOOL("audio_enable_menu_ok",          &settings->bools.audio_enable_menu_ok, true, DEFAULT_AUDIO_ENABLE_MENU_OK, false);
   SETTING_BOOL("audio_enable_menu_cancel",      &settings->bools.audio_enable_menu_cancel, true, DEFAULT_AUDIO_ENABLE_MENU_CANCEL, false);
   SETTING_BOOL("audio_enable_menu_notice",      &settings->bools.audio_enable_menu_notice, true, DEFAULT_AUDIO_ENABLE_MENU_NOTICE, false);
   SETTING_BOOL("audio_enable_menu_bgm",         &settings->bools.audio_enable_menu_bgm, true, DEFAULT_AUDIO_ENABLE_MENU_BGM, false);
   SETTING_BOOL("audio_enable_menu_scroll",      &settings->bools.audio_enable_menu_scroll, true, DEFAULT_AUDIO_ENABLE_MENU_SCROLL, false);
   SETTING_BOOL("audio_mute_enable",             audio_get_bool_ptr(AUDIO_ACTION_MUTE_ENABLE), true, false, false);
#ifdef HAVE_AUDIOMIXER
   SETTING_BOOL("audio_mixer_mute_enable",       audio_get_bool_ptr(AUDIO_ACTION_MIXER_MUTE_ENABLE), true, false, false);
#endif
#if TARGET_OS_IOS
   SETTING_BOOL("audio_respect_silent_mode",     &settings->bools.audio_respect_silent_mode, true, DEFAULT_AUDIO_RESPECT_SILENT_MODE, false);
#endif
   SETTING_BOOL("audio_fastforward_mute",        &settings->bools.audio_fastforward_mute, true, DEFAULT_AUDIO_FASTFORWARD_MUTE, false);
   SETTING_BOOL("audio_fastforward_speedup",     &settings->bools.audio_fastforward_speedup, true, DEFAULT_AUDIO_FASTFORWARD_SPEEDUP, false);
   SETTING_BOOL("audio_rewind_mute",             &settings->bools.audio_rewind_mute, true, DEFAULT_AUDIO_REWIND_MUTE, false);

#ifdef HAVE_WASAPI
   SETTING_BOOL("audio_wasapi_exclusive_mode",   &settings->bools.audio_wasapi_exclusive_mode, true, DEFAULT_WASAPI_EXCLUSIVE_MODE, false);
   SETTING_BOOL("audio_wasapi_float_format",     &settings->bools.audio_wasapi_float_format, true, DEFAULT_WASAPI_FLOAT_FORMAT, false);
#endif

#ifdef HAVE_MICROPHONE
   SETTING_BOOL("microphone_enable",             &settings->bools.microphone_enable, true, DEFAULT_MICROPHONE_ENABLE, false);
#ifdef HAVE_WASAPI
   SETTING_BOOL("microphone_wasapi_exclusive_mode", &settings->bools.microphone_wasapi_exclusive_mode, true, DEFAULT_WASAPI_EXCLUSIVE_MODE, false);
   SETTING_BOOL("microphone_wasapi_float_format",   &settings->bools.microphone_wasapi_float_format, true, DEFAULT_WASAPI_FLOAT_FORMAT, false);
#endif
#endif

   SETTING_BOOL("crt_switch_hires_menu",         &settings->bools.crt_switch_hires_menu, true, false, true);
   SETTING_BOOL("video_shader_enable",           &settings->bools.video_shader_enable, true, DEFAULT_SHADER_ENABLE, false);
   SETTING_BOOL("video_shader_watch_files",      &settings->bools.video_shader_watch_files, true, DEFAULT_VIDEO_SHADER_WATCH_FILES, false);
   SETTING_BOOL("video_shader_remember_last_dir", &settings->bools.video_shader_remember_last_dir, true, DEFAULT_VIDEO_SHADER_REMEMBER_LAST_DIR, false);
   SETTING_BOOL("video_shader_preset_save_reference_enable", &settings->bools.video_shader_preset_save_reference_enable, true, DEFAULT_VIDEO_SHADER_PRESET_SAVE_REFERENCE_ENABLE, false);

   /* Let implementation decide if automatic, or 1:1 PAR. */
   SETTING_BOOL("video_aspect_ratio_auto",       &settings->bools.video_aspect_ratio_auto, true, DEFAULT_ASPECT_RATIO_AUTO, false);

   SETTING_BOOL("video_scan_subframes",          &settings->bools.video_scan_subframes, true, DEFAULT_SCAN_SUBFRAMES, false);

   SETTING_BOOL("video_allow_rotate",            &settings->bools.video_allow_rotate, true, DEFAULT_ALLOW_ROTATE, false);
   SETTING_BOOL("video_windowed_fullscreen",     &settings->bools.video_windowed_fullscreen, true, DEFAULT_WINDOWED_FULLSCREEN, false);
   SETTING_BOOL("video_crop_overscan",           &settings->bools.video_crop_overscan, true, DEFAULT_CROP_OVERSCAN, false);
   SETTING_BOOL("video_scale_integer",           &settings->bools.video_scale_integer, true, DEFAULT_SCALE_INTEGER, false);
   SETTING_BOOL("video_smooth",                  &settings->bools.video_smooth, true, DEFAULT_VIDEO_SMOOTH, false);
   SETTING_BOOL("video_ctx_scaling",             &settings->bools.video_ctx_scaling, true, DEFAULT_VIDEO_CTX_SCALING, false);
   SETTING_BOOL("video_force_aspect",            &settings->bools.video_force_aspect, true, DEFAULT_FORCE_ASPECT, false);
   SETTING_BOOL("video_frame_delay_auto",        &settings->bools.video_frame_delay_auto, true, DEFAULT_FRAME_DELAY_AUTO, false);
#if defined(DINGUX)
   SETTING_BOOL("video_dingux_ipu_keep_aspect",  &settings->bools.video_dingux_ipu_keep_aspect, true, DEFAULT_DINGUX_IPU_KEEP_ASPECT, false);
#endif
   SETTING_BOOL("video_threaded",                video_driver_get_threaded(), true, DEFAULT_VIDEO_THREADED, false);
   SETTING_BOOL("video_shared_context",          &settings->bools.video_shared_context, true, DEFAULT_VIDEO_SHARED_CONTEXT, false);
#ifdef GEKKO
   SETTING_BOOL("video_vfilter",                 &settings->bools.video_vfilter, true, DEFAULT_VIDEO_VFILTER, false);
#endif
   SETTING_BOOL("video_font_enable",             &settings->bools.video_font_enable, true, DEFAULT_FONT_ENABLE, false);
   SETTING_BOOL("video_force_srgb_disable",      &settings->bools.video_force_srgb_disable, true, false, false);
   SETTING_BOOL("video_fullscreen",              &settings->bools.video_fullscreen, true, DEFAULT_FULLSCREEN, false);
   SETTING_BOOL("video_hdr_enable",              &settings->bools.video_hdr_enable, true, DEFAULT_VIDEO_HDR_ENABLE, false);
   SETTING_BOOL("video_hdr_expand_gamut",        &settings->bools.video_hdr_expand_gamut, true, DEFAULT_VIDEO_HDR_EXPAND_GAMUT, false);
   SETTING_BOOL("video_vsync",                   &settings->bools.video_vsync, true, DEFAULT_VSYNC, false);
   SETTING_BOOL("video_adaptive_vsync",          &settings->bools.video_adaptive_vsync, true, DEFAULT_ADAPTIVE_VSYNC, false);
   SETTING_BOOL("video_hard_sync",               &settings->bools.video_hard_sync, true, DEFAULT_HARD_SYNC, false);
   SETTING_BOOL("video_waitable_swapchains",     &settings->bools.video_waitable_swapchains, true, DEFAULT_WAITABLE_SWAPCHAINS, false);
   SETTING_BOOL("video_disable_composition",     &settings->bools.video_disable_composition, true, DEFAULT_DISABLE_COMPOSITION, false);
   SETTING_BOOL("video_gpu_screenshot",          &settings->bools.video_gpu_screenshot, true, DEFAULT_GPU_SCREENSHOT, false);
   SETTING_BOOL("video_post_filter_record",      &settings->bools.video_post_filter_record, true, DEFAULT_POST_FILTER_RECORD, false);
   SETTING_BOOL("video_notch_write_over_enable", &settings->bools.video_notch_write_over_enable, true, DEFAULT_NOTCH_WRITE_OVER_ENABLE, false);
#if defined(__APPLE__) && defined(HAVE_VULKAN)
   SETTING_BOOL("video_use_metal_arg_buffers",   &settings->bools.video_use_metal_arg_buffers, true, DEFAULT_USE_METAL_ARG_BUFFERS, false);
#endif
   SETTING_BOOL("video_msg_bgcolor_enable",      &settings->bools.video_msg_bgcolor_enable, true, DEFAULT_MESSAGE_BGCOLOR_ENABLE, false);
   SETTING_BOOL("video_window_show_decorations", &settings->bools.video_window_show_decorations, true, DEFAULT_WINDOW_DECORATIONS, false);
   SETTING_BOOL("video_window_save_positions",   &settings->bools.video_window_save_positions, true, DEFAULT_WINDOW_SAVE_POSITIONS, false);
   SETTING_BOOL("video_window_custom_size_enable", &settings->bools.video_window_custom_size_enable, true, DEFAULT_WINDOW_CUSTOM_SIZE_ENABLE, false);

   SETTING_BOOL("notification_show_autoconfig",  &settings->bools.notification_show_autoconfig, true, DEFAULT_NOTIFICATION_SHOW_AUTOCONFIG, false);
   SETTING_BOOL("notification_show_autoconfig_fails", &settings->bools.notification_show_autoconfig_fails, true, DEFAULT_NOTIFICATION_SHOW_AUTOCONFIG_FAILS, false);
   SETTING_BOOL("notification_show_cheats_applied", &settings->bools.notification_show_cheats_applied, true, DEFAULT_NOTIFICATION_SHOW_CHEATS_APPLIED, false);
   SETTING_BOOL("notification_show_patch_applied", &settings->bools.notification_show_patch_applied, true, DEFAULT_NOTIFICATION_SHOW_PATCH_APPLIED, false);
   SETTING_BOOL("notification_show_remap_load",  &settings->bools.notification_show_remap_load, true, DEFAULT_NOTIFICATION_SHOW_REMAP_LOAD, false);
   SETTING_BOOL("notification_show_config_override_load", &settings->bools.notification_show_config_override_load, true, DEFAULT_NOTIFICATION_SHOW_CONFIG_OVERRIDE_LOAD, false);
   SETTING_BOOL("notification_show_set_initial_disk", &settings->bools.notification_show_set_initial_disk, true, DEFAULT_NOTIFICATION_SHOW_SET_INITIAL_DISK, false);
   SETTING_BOOL("notification_show_disk_control", &settings->bools.notification_show_disk_control, true, DEFAULT_NOTIFICATION_SHOW_DISK_CONTROL, false);
   SETTING_BOOL("notification_show_save_state",  &settings->bools.notification_show_save_state, true, DEFAULT_NOTIFICATION_SHOW_SAVE_STATE, false);
   SETTING_BOOL("notification_show_fast_forward", &settings->bools.notification_show_fast_forward, true, DEFAULT_NOTIFICATION_SHOW_FAST_FORWARD, false);
#ifdef HAVE_SCREENSHOTS
   SETTING_BOOL("notification_show_screenshot",  &settings->bools.notification_show_screenshot, true, DEFAULT_NOTIFICATION_SHOW_SCREENSHOT, false);
#endif
   SETTING_BOOL("notification_show_refresh_rate", &settings->bools.notification_show_refresh_rate, true, DEFAULT_NOTIFICATION_SHOW_REFRESH_RATE, false);
#ifdef HAVE_NETWORKING
   SETTING_BOOL("notification_show_netplay_extra", &settings->bools.notification_show_netplay_extra, true, DEFAULT_NOTIFICATION_SHOW_NETPLAY_EXTRA, false);
#endif

#ifdef HAVE_CHEEVOS
   SETTING_BOOL("cheevos_enable",                &settings->bools.cheevos_enable, true, DEFAULT_CHEEVOS_ENABLE, false);
   SETTING_BOOL("cheevos_test_unofficial",       &settings->bools.cheevos_test_unofficial, true, false, false);
   SETTING_BOOL("cheevos_hardcore_mode_enable",  &settings->bools.cheevos_hardcore_mode_enable, true, true, false);
   SETTING_BOOL("cheevos_challenge_indicators",  &settings->bools.cheevos_challenge_indicators, true, true, false);
   SETTING_BOOL("cheevos_richpresence_enable",   &settings->bools.cheevos_richpresence_enable, true, true, false);
   SETTING_BOOL("cheevos_unlock_sound_enable",   &settings->bools.cheevos_unlock_sound_enable, true, false, false);
   SETTING_BOOL("cheevos_verbose_enable",        &settings->bools.cheevos_verbose_enable, true, true, false);
   SETTING_BOOL("cheevos_auto_screenshot",       &settings->bools.cheevos_auto_screenshot, true, false, false);
   SETTING_BOOL("cheevos_badges_enable",         &settings->bools.cheevos_badges_enable, true, false, false);
   SETTING_BOOL("cheevos_start_active",          &settings->bools.cheevos_start_active, true, false, false);
   SETTING_BOOL("cheevos_appearance_padding_auto", &settings->bools.cheevos_appearance_padding_auto, true, DEFAULT_CHEEVOS_APPEARANCE_PADDING_AUTO, false);
   SETTING_BOOL("cheevos_visibility_unlock",     &settings->bools.cheevos_visibility_unlock, true, DEFAULT_CHEEVOS_VISIBILITY_UNLOCK, false);
   SETTING_BOOL("cheevos_visibility_mastery",    &settings->bools.cheevos_visibility_mastery, true, DEFAULT_CHEEVOS_VISIBILITY_MASTERY, false);
   SETTING_BOOL("cheevos_visibility_account",    &settings->bools.cheevos_visibility_account, true, DEFAULT_CHEEVOS_VISIBILITY_ACCOUNT, false);
   SETTING_BOOL("cheevos_visibility_lboard_start", &settings->bools.cheevos_visibility_lboard_start, true, DEFAULT_CHEEVOS_VISIBILITY_LBOARD_START, false);
   SETTING_BOOL("cheevos_visibility_lboard_submit", &settings->bools.cheevos_visibility_lboard_submit, true, DEFAULT_CHEEVOS_VISIBILITY_LBOARD_SUBMIT, false);
   SETTING_BOOL("cheevos_visibility_lboard_cancel", &settings->bools.cheevos_visibility_lboard_cancel, true, DEFAULT_CHEEVOS_VISIBILITY_LBOARD_CANCEL, false);
   SETTING_BOOL("cheevos_visibility_lboard_trackers", &settings->bools.cheevos_visibility_lboard_trackers, true, DEFAULT_CHEEVOS_VISIBILITY_LBOARD_TRACKERS, false);
   SETTING_BOOL("cheevos_visibility_progress_tracker", &settings->bools.cheevos_visibility_progress_tracker, true, DEFAULT_CHEEVOS_VISIBILITY_PROGRESS_TRACKER, false);
#endif // HAVE_CHEEVOS
#ifdef HAVE_OVERLAY
   SETTING_BOOL("input_overlay_enable",          &settings->bools.input_overlay_enable, true, config_overlay_enable_default(), false);
   SETTING_BOOL("input_overlay_enable_autopreferred", &settings->bools.input_overlay_enable_autopreferred, true, DEFAULT_OVERLAY_ENABLE_AUTOPREFERRED, false);
   SETTING_BOOL("input_overlay_behind_menu",     &settings->bools.input_overlay_behind_menu, true, DEFAULT_OVERLAY_BEHIND_MENU, false);
   SETTING_BOOL("input_overlay_hide_in_menu",    &settings->bools.input_overlay_hide_in_menu, true, DEFAULT_OVERLAY_HIDE_IN_MENU, false);
   SETTING_BOOL("input_overlay_hide_when_gamepad_connected", &settings->bools.input_overlay_hide_when_gamepad_connected, true, DEFAULT_OVERLAY_HIDE_WHEN_GAMEPAD_CONNECTED, false);
   SETTING_BOOL("input_overlay_show_mouse_cursor", &settings->bools.input_overlay_show_mouse_cursor, true, DEFAULT_OVERLAY_SHOW_MOUSE_CURSOR, false);
   SETTING_BOOL("input_overlay_auto_rotate",     &settings->bools.input_overlay_auto_rotate, true, DEFAULT_OVERLAY_AUTO_ROTATE, false);
   SETTING_BOOL("input_overlay_auto_scale",      &settings->bools.input_overlay_auto_scale, true, DEFAULT_INPUT_OVERLAY_AUTO_SCALE, false);
   SETTING_BOOL("input_osk_overlay_auto_scale",  &settings->bools.input_osk_overlay_auto_scale, true, DEFAULT_INPUT_OVERLAY_AUTO_SCALE, false);
   SETTING_BOOL("input_overlay_pointer_enable",  &settings->bools.input_overlay_pointer_enable, true, DEFAULT_INPUT_OVERLAY_POINTER_ENABLE, false);
   SETTING_BOOL("input_overlay_lightgun_trigger_on_touch", &settings->bools.input_overlay_lightgun_trigger_on_touch, true, DEFAULT_INPUT_OVERLAY_LIGHTGUN_TRIGGER_ON_TOUCH, false);
   SETTING_BOOL("input_overlay_lightgun_allow_offscreen",  &settings->bools.input_overlay_lightgun_allow_offscreen, true, DEFAULT_INPUT_OVERLAY_LIGHTGUN_ALLOW_OFFSCREEN, false);
   SETTING_BOOL("input_overlay_mouse_hold_to_drag", &settings->bools.input_overlay_mouse_hold_to_drag, true, DEFAULT_INPUT_OVERLAY_MOUSE_HOLD_TO_DRAG, false);
   SETTING_BOOL("input_overlay_mouse_dtap_to_drag", &settings->bools.input_overlay_mouse_dtap_to_drag, true, DEFAULT_INPUT_OVERLAY_MOUSE_DTAP_TO_DRAG, false);
#endif // HAVE_OVERLAY
#ifdef UDEV_TOUCH_SUPPORT
   SETTING_BOOL("input_touch_vmouse_pointer",    &settings->bools.input_touch_vmouse_pointer, true, DEFAULT_INPUT_TOUCH_VMOUSE_POINTER, false);
   SETTING_BOOL("input_touch_vmouse_mouse",      &settings->bools.input_touch_vmouse_mouse, true, DEFAULT_INPUT_TOUCH_VMOUSE_MOUSE, false);
   SETTING_BOOL("input_touch_vmouse_touchpad",   &settings->bools.input_touch_vmouse_touchpad, true, DEFAULT_INPUT_TOUCH_VMOUSE_TOUCHPAD, false);
   SETTING_BOOL("input_touch_vmouse_trackball",  &settings->bools.input_touch_vmouse_trackball, true, DEFAULT_INPUT_TOUCH_VMOUSE_TRACKBALL, false);
   SETTING_BOOL("input_touch_vmouse_gesture",    &settings->bools.input_touch_vmouse_gesture, true, DEFAULT_INPUT_TOUCH_VMOUSE_GESTURE, false);
#endif // UDEV_TOUCH_SUPPORT
#if defined(VITA)
   SETTING_BOOL("input_backtouch_enable",        &settings->bools.input_backtouch_enable, false, DEFAULT_INPUT_BACKTOUCH_ENABLE, false);
   SETTING_BOOL("input_backtouch_toggle",        &settings->bools.input_backtouch_toggle, false, DEFAULT_INPUT_BACKTOUCH_TOGGLE, false);
#endif
#if TARGET_OS_IPHONE
   SETTING_BOOL("small_keyboard_enable",         &settings->bools.input_small_keyboard_enable, true, false, false);
#endif
   SETTING_BOOL("keyboard_gamepad_enable",       &settings->bools.input_keyboard_gamepad_enable, true, DEFAULT_INPUT_KEYBOARD_GAMEPAD_ENABLE, false);
   SETTING_BOOL("input_autodetect_enable",       &settings->bools.input_autodetect_enable, true, DEFAULT_INPUT_AUTODETECT_ENABLE, false);
   SETTING_BOOL("input_turbo_enable",            &settings->bools.input_turbo_enable, true, DEFAULT_TURBO_ENABLE, false);
   SETTING_BOOL("input_turbo_allow_dpad",        &settings->bools.input_turbo_allow_dpad, true, DEFAULT_TURBO_ALLOW_DPAD, false);
   SETTING_BOOL("input_auto_mouse_grab",         &settings->bools.input_auto_mouse_grab, true, DEFAULT_INPUT_AUTO_MOUSE_GRAB, false);
   SETTING_BOOL("input_remap_binds_enable",      &settings->bools.input_remap_binds_enable, true, true, false);
   SETTING_BOOL("input_remap_sort_by_controller_enable",      &settings->bools.input_remap_sort_by_controller_enable, true, false, false);
   SETTING_BOOL("input_hotkey_device_merge",     &settings->bools.input_hotkey_device_merge, true, DEFAULT_INPUT_HOTKEY_DEVICE_MERGE, false);
   SETTING_BOOL("all_users_control_menu",        &settings->bools.input_all_users_control_menu, true, DEFAULT_ALL_USERS_CONTROL_MENU, false);
#if defined(HAVE_DINPUT) || defined(HAVE_WINRAWINPUT)
   SETTING_BOOL("input_nowinkey_enable",         &settings->bools.input_nowinkey_enable, true, false, false);
#endif
   SETTING_BOOL("input_sensors_enable",          &settings->bools.input_sensors_enable, true, DEFAULT_INPUT_SENSORS_ENABLE, false);
   SETTING_BOOL("vibrate_on_keypress",           &settings->bools.vibrate_on_keypress, true, DEFAULT_VIBRATE_ON_KEYPRESS, false);
   SETTING_BOOL("enable_device_vibration",       &settings->bools.enable_device_vibration, true, DEFAULT_ENABLE_DEVICE_VIBRATION, false);
   SETTING_BOOL("sustained_performance_mode",    &settings->bools.sustained_performance_mode, true, DEFAULT_SUSTAINED_PERFORMANCE_MODE, false);

   SETTING_BOOL("history_list_enable",           &settings->bools.history_list_enable, false, DEFAULT_HISTORY_LIST_ENABLE, false);
   SETTING_BOOL("playlist_use_old_format",       &settings->bools.playlist_use_old_format, true, DEFAULT_PLAYLIST_USE_OLD_FORMAT, false);
   SETTING_BOOL("playlist_compression",          &settings->bools.playlist_compression, true, DEFAULT_PLAYLIST_COMPRESSION, false);
   SETTING_BOOL("playlist_fuzzy_archive_match",  &settings->bools.playlist_fuzzy_archive_match, true, DEFAULT_PLAYLIST_FUZZY_ARCHIVE_MATCH, false);
   SETTING_BOOL("playlist_portable_paths",       &settings->bools.playlist_portable_paths, true, DEFAULT_PLAYLIST_PORTABLE_PATHS, false);

   SETTING_BOOL("frame_time_counter_reset_after_fastforwarding", &settings->bools.frame_time_counter_reset_after_fastforwarding, true, false, false);
   SETTING_BOOL("frame_time_counter_reset_after_load_state",     &settings->bools.frame_time_counter_reset_after_load_state, true, false, false);
   SETTING_BOOL("frame_time_counter_reset_after_save_state",     &settings->bools.frame_time_counter_reset_after_save_state, true, false, false);

#ifdef HAVE_COMMAND
   SETTING_BOOL("network_cmd_enable",            &settings->bools.network_cmd_enable, true, DEFAULT_NETWORK_CMD_ENABLE, false);
   SETTING_BOOL("stdin_cmd_enable",              &settings->bools.stdin_cmd_enable, true, DEFAULT_STDIN_CMD_ENABLE, false);
#endif

#ifdef HAVE_NETWORKING
   SETTING_BOOL("netplay_show_only_connectable", &settings->bools.netplay_show_only_connectable, true, DEFAULT_NETPLAY_SHOW_ONLY_CONNECTABLE, false);
   SETTING_BOOL("netplay_show_only_installed_cores", &settings->bools.netplay_show_only_installed_cores, true, DEFAULT_NETPLAY_SHOW_ONLY_INSTALLED_CORES, false);
   SETTING_BOOL("netplay_show_passworded",       &settings->bools.netplay_show_passworded, true, DEFAULT_NETPLAY_SHOW_PASSWORDED, false);
   SETTING_BOOL("netplay_public_announce",       &settings->bools.netplay_public_announce, true, DEFAULT_NETPLAY_PUBLIC_ANNOUNCE, false);
   SETTING_BOOL("netplay_start_as_spectator",    &settings->bools.netplay_start_as_spectator, false, DEFAULT_NETPLAY_START_AS_SPECTATOR, false);
   SETTING_BOOL("netplay_nat_traversal",         &settings->bools.netplay_nat_traversal, true, true, false);
   SETTING_BOOL("netplay_fade_chat",             &settings->bools.netplay_fade_chat, true, DEFAULT_NETPLAY_FADE_CHAT, false);
   SETTING_BOOL("netplay_allow_pausing",         &settings->bools.netplay_allow_pausing, true, DEFAULT_NETPLAY_ALLOW_PAUSING, false);
   SETTING_BOOL("netplay_allow_slaves",          &settings->bools.netplay_allow_slaves, true, DEFAULT_NETPLAY_ALLOW_SLAVES, false);
   SETTING_BOOL("netplay_require_slaves",        &settings->bools.netplay_require_slaves, true, DEFAULT_NETPLAY_REQUIRE_SLAVES, false);
   SETTING_BOOL("netplay_use_mitm_server",       &settings->bools.netplay_use_mitm_server, true, DEFAULT_NETPLAY_USE_MITM_SERVER, false);
   SETTING_BOOL("netplay_request_device_p1",     &settings->bools.netplay_request_devices[0], true, false, false);
   SETTING_BOOL("netplay_request_device_p2",     &settings->bools.netplay_request_devices[1], true, false, false);
   SETTING_BOOL("netplay_request_device_p3",     &settings->bools.netplay_request_devices[2], true, false, false);
   SETTING_BOOL("netplay_request_device_p4",     &settings->bools.netplay_request_devices[3], true, false, false);
   SETTING_BOOL("netplay_request_device_p5",     &settings->bools.netplay_request_devices[4], true, false, false);
   SETTING_BOOL("netplay_request_device_p6",     &settings->bools.netplay_request_devices[5], true, false, false);
   SETTING_BOOL("netplay_request_device_p7",     &settings->bools.netplay_request_devices[6], true, false, false);
   SETTING_BOOL("netplay_request_device_p8",     &settings->bools.netplay_request_devices[7], true, false, false);
   SETTING_BOOL("netplay_request_device_p9",     &settings->bools.netplay_request_devices[8], true, false, false);
   SETTING_BOOL("netplay_request_device_p10",    &settings->bools.netplay_request_devices[9], true, false, false);
   SETTING_BOOL("netplay_request_device_p11",    &settings->bools.netplay_request_devices[10], true, false, false);
   SETTING_BOOL("netplay_request_device_p12",    &settings->bools.netplay_request_devices[11], true, false, false);
   SETTING_BOOL("netplay_request_device_p13",    &settings->bools.netplay_request_devices[12], true, false, false);
   SETTING_BOOL("netplay_request_device_p14",    &settings->bools.netplay_request_devices[13], true, false, false);
   SETTING_BOOL("netplay_request_device_p15",    &settings->bools.netplay_request_devices[14], true, false, false);
   SETTING_BOOL("netplay_request_device_p16",    &settings->bools.netplay_request_devices[15], true, false, false);
   SETTING_BOOL("netplay_ping_show",             &settings->bools.netplay_ping_show, true, DEFAULT_NETPLAY_PING_SHOW, false);
#ifdef HAVE_NETWORKGAMEPAD
   SETTING_BOOL("network_remote_enable",         &settings->bools.network_remote_enable, false, false /* TODO */, false);
#endif
#endif // HAVE_NETWORKING

#ifdef ANDROID
   SETTING_BOOL("android_input_disconnect_workaround", &settings->bools.android_input_disconnect_workaround, true, false, false);
#endif

#ifdef WIIU
   SETTING_BOOL("video_wiiu_prefer_drc",         &settings->bools.video_wiiu_prefer_drc, true, DEFAULT_WIIU_PREFER_DRC, false);
#endif

#if defined(HAVE_COCOATOUCH) && defined(TARGET_OS_TV)
   SETTING_BOOL("gcdwebserver_alert",            &settings->bools.gcdwebserver_alert, true, true, false);
#endif

#ifdef HAVE_GAME_AI
   SETTING_BOOL("quick_menu_show_game_ai",  &settings->bools.quick_menu_show_game_ai, true, 1, false);
#endif

   *size = count;

   return tmp;
}

static struct config_float_setting *populate_settings_float(
      settings_t *settings, int *size)
{
   unsigned count = 0;
   struct config_float_setting  *tmp      = (struct config_float_setting*)calloc(1, (*size + 1) * sizeof(struct config_float_setting));

   if (!tmp)
      return NULL;

#ifdef HAVE_CHEEVOS
   SETTING_FLOAT("cheevos_appearance_padding_h", &settings->floats.cheevos_appearance_padding_h, true, DEFAULT_CHEEVOS_APPEARANCE_PADDING_H, false);
   SETTING_FLOAT("cheevos_appearance_padding_v", &settings->floats.cheevos_appearance_padding_v, true, DEFAULT_CHEEVOS_APPEARANCE_PADDING_V, false);
#endif

   SETTING_FLOAT("fastforward_ratio",            &settings->floats.fastforward_ratio, true, DEFAULT_FASTFORWARD_RATIO, false);
   SETTING_FLOAT("slowmotion_ratio",             &settings->floats.slowmotion_ratio,  true, DEFAULT_SLOWMOTION_RATIO, false);

   SETTING_FLOAT("audio_rate_control_delta",     audio_get_float_ptr(AUDIO_ACTION_RATE_CONTROL_DELTA), true, DEFAULT_RATE_CONTROL_DELTA, false);
   SETTING_FLOAT("audio_max_timing_skew",        &settings->floats.audio_max_timing_skew, true, DEFAULT_MAX_TIMING_SKEW, false);
   SETTING_FLOAT("audio_volume",                 &settings->floats.audio_volume, true, DEFAULT_AUDIO_VOLUME, false);
#ifdef HAVE_AUDIOMIXER
   SETTING_FLOAT("audio_mixer_volume",           &settings->floats.audio_mixer_volume, true, DEFAULT_AUDIO_MIXER_VOLUME, false);
#endif

   SETTING_FLOAT("video_aspect_ratio",           &settings->floats.video_aspect_ratio, true, DEFAULT_ASPECT_RATIO, false);
   SETTING_FLOAT("video_viewport_bias_x",        &settings->floats.video_vp_bias_x, true, DEFAULT_VIEWPORT_BIAS_X, false);
   SETTING_FLOAT("video_viewport_bias_y",        &settings->floats.video_vp_bias_y, true, DEFAULT_VIEWPORT_BIAS_Y, false);
#if defined(RARCH_MOBILE)
   SETTING_FLOAT("video_viewport_bias_portrait_x", &settings->floats.video_vp_bias_portrait_x, true, DEFAULT_VIEWPORT_BIAS_PORTRAIT_X, false);
   SETTING_FLOAT("video_viewport_bias_portrait_y", &settings->floats.video_vp_bias_portrait_y, true, DEFAULT_VIEWPORT_BIAS_PORTRAIT_Y, false);
#endif
   SETTING_FLOAT("video_refresh_rate",           &settings->floats.video_refresh_rate, true, DEFAULT_REFRESH_RATE, false);
   SETTING_FLOAT("video_autoswitch_pal_threshold", &settings->floats.video_autoswitch_pal_threshold, true, DEFAULT_AUTOSWITCH_PAL_THRESHOLD, false);
   SETTING_FLOAT("crt_video_refresh_rate",       &settings->floats.crt_video_refresh_rate, true, DEFAULT_CRT_REFRESH_RATE, false);
   SETTING_FLOAT("video_message_pos_x",          &settings->floats.video_msg_pos_x, true, DEFAULT_MESSAGE_POS_OFFSET_X, false);
   SETTING_FLOAT("video_message_pos_y",          &settings->floats.video_msg_pos_y, true, DEFAULT_MESSAGE_POS_OFFSET_Y, false);
   SETTING_FLOAT("video_font_size",              &settings->floats.video_font_size, true, DEFAULT_FONT_SIZE, false);
   SETTING_FLOAT("video_msg_bgcolor_opacity",    &settings->floats.video_msg_bgcolor_opacity, true, DEFAULT_MESSAGE_BGCOLOR_OPACITY, false);
   SETTING_FLOAT("video_hdr_max_nits",           &settings->floats.video_hdr_max_nits, true, DEFAULT_VIDEO_HDR_MAX_NITS, false);
   SETTING_FLOAT("video_hdr_paper_white_nits",   &settings->floats.video_hdr_paper_white_nits, true, DEFAULT_VIDEO_HDR_PAPER_WHITE_NITS, false);
   SETTING_FLOAT("video_hdr_display_contrast",   &settings->floats.video_hdr_display_contrast, true, DEFAULT_VIDEO_HDR_CONTRAST, false);

   SETTING_FLOAT("input_axis_threshold",         &settings->floats.input_axis_threshold,     true, DEFAULT_AXIS_THRESHOLD, false);
   SETTING_FLOAT("input_analog_deadzone",        &settings->floats.input_analog_deadzone,    true, DEFAULT_ANALOG_DEADZONE, false);
   SETTING_FLOAT("input_analog_sensitivity",     &settings->floats.input_analog_sensitivity, true, DEFAULT_ANALOG_SENSITIVITY, false);
#ifdef HAVE_OVERLAY
   SETTING_FLOAT("input_overlay_opacity",                 &settings->floats.input_overlay_opacity, true, DEFAULT_INPUT_OVERLAY_OPACITY, false);
   SETTING_FLOAT("input_osk_overlay_opacity",             &settings->floats.input_osk_overlay_opacity, true, DEFAULT_INPUT_OVERLAY_OPACITY, false);
   SETTING_FLOAT("input_overlay_scale_landscape",         &settings->floats.input_overlay_scale_landscape, true, DEFAULT_INPUT_OVERLAY_SCALE_LANDSCAPE, false);
   SETTING_FLOAT("input_overlay_aspect_adjust_landscape", &settings->floats.input_overlay_aspect_adjust_landscape, true, DEFAULT_INPUT_OVERLAY_ASPECT_ADJUST_LANDSCAPE, false);
   SETTING_FLOAT("input_overlay_x_separation_landscape",  &settings->floats.input_overlay_x_separation_landscape, true, DEFAULT_INPUT_OVERLAY_X_SEPARATION_LANDSCAPE, false);
   SETTING_FLOAT("input_overlay_y_separation_landscape",  &settings->floats.input_overlay_y_separation_landscape, true, DEFAULT_INPUT_OVERLAY_Y_SEPARATION_LANDSCAPE, false);
   SETTING_FLOAT("input_overlay_x_offset_landscape",      &settings->floats.input_overlay_x_offset_landscape, true, DEFAULT_INPUT_OVERLAY_X_OFFSET_LANDSCAPE, false);
   SETTING_FLOAT("input_overlay_y_offset_landscape",      &settings->floats.input_overlay_y_offset_landscape, true, DEFAULT_INPUT_OVERLAY_Y_OFFSET_LANDSCAPE, false);
   SETTING_FLOAT("input_overlay_scale_portrait",          &settings->floats.input_overlay_scale_portrait, true, DEFAULT_INPUT_OVERLAY_SCALE_PORTRAIT, false);
   SETTING_FLOAT("input_overlay_aspect_adjust_portrait",  &settings->floats.input_overlay_aspect_adjust_portrait, true, DEFAULT_INPUT_OVERLAY_ASPECT_ADJUST_PORTRAIT, false);
   SETTING_FLOAT("input_overlay_x_separation_portrait",   &settings->floats.input_overlay_x_separation_portrait, true, DEFAULT_INPUT_OVERLAY_X_SEPARATION_PORTRAIT, false);
   SETTING_FLOAT("input_overlay_y_separation_portrait",   &settings->floats.input_overlay_y_separation_portrait, true, DEFAULT_INPUT_OVERLAY_Y_SEPARATION_PORTRAIT, false);
   SETTING_FLOAT("input_overlay_x_offset_portrait",       &settings->floats.input_overlay_x_offset_portrait, true, DEFAULT_INPUT_OVERLAY_X_OFFSET_PORTRAIT, false);
   SETTING_FLOAT("input_overlay_y_offset_portrait",       &settings->floats.input_overlay_y_offset_portrait, true, DEFAULT_INPUT_OVERLAY_Y_OFFSET_PORTRAIT, false);
   SETTING_FLOAT("input_overlay_mouse_speed",             &settings->floats.input_overlay_mouse_speed, true, DEFAULT_INPUT_OVERLAY_MOUSE_SPEED, false);
   SETTING_FLOAT("input_overlay_mouse_swipe_threshold",   &settings->floats.input_overlay_mouse_swipe_threshold, true, DEFAULT_INPUT_OVERLAY_MOUSE_SWIPE_THRESHOLD, false);
#endif // HAVE_OVERLAY

   *size = count;

   return tmp;
}

static struct config_uint_setting *populate_settings_uint(
      settings_t *settings, int *size)
{
   unsigned count                     = 0;
   struct config_uint_setting  *tmp   = (struct config_uint_setting*)calloc(1, (*size + 1) * sizeof(struct config_uint_setting));

   if (!tmp)
      return NULL;

   SETTING_UINT("frontend_log_level",            &settings->uints.frontend_log_level, true, DEFAULT_FRONTEND_LOG_LEVEL, false);
   SETTING_UINT("libretro_log_level",            &settings->uints.libretro_log_level, true, DEFAULT_LIBRETRO_LOG_LEVEL, false);
   SETTING_UINT("fps_update_interval",           &settings->uints.fps_update_interval, true, DEFAULT_FPS_UPDATE_INTERVAL, false);
   SETTING_UINT("memory_update_interval",        &settings->uints.memory_update_interval, true, DEFAULT_MEMORY_UPDATE_INTERVAL, false);
   SETTING_UINT("autosave_interval",             &settings->uints.autosave_interval,  true, DEFAULT_AUTOSAVE_INTERVAL, false);
   SETTING_UINT("rewind_granularity",            &settings->uints.rewind_granularity, true, DEFAULT_REWIND_GRANULARITY, false);
   SETTING_UINT("rewind_buffer_size_step",       &settings->uints.rewind_buffer_size_step, true, DEFAULT_REWIND_BUFFER_SIZE_STEP, false);
   SETTING_UINT("run_ahead_frames",              &settings->uints.run_ahead_frames, true, 1,  false);
   SETTING_UINT("replay_max_keep",               &settings->uints.replay_max_keep, true, DEFAULT_REPLAY_MAX_KEEP, false);
   SETTING_UINT("replay_checkpoint_interval",    &settings->uints.replay_checkpoint_interval,  true, DEFAULT_REPLAY_CHECKPOINT_INTERVAL, false);
   SETTING_UINT("savestate_max_keep",            &settings->uints.savestate_max_keep, true, DEFAULT_SAVESTATE_MAX_KEEP, false);
   SETTING_UINT("audio_out_rate",                &settings->uints.audio_output_sample_rate, true, DEFAULT_OUTPUT_RATE, false);
   SETTING_UINT("audio_latency",                 &settings->uints.audio_latency, false, 0 /* TODO */, false);
   SETTING_UINT("audio_resampler_quality",       &settings->uints.audio_resampler_quality, true, DEFAULT_AUDIO_RESAMPLER_QUALITY_LEVEL, false);
   SETTING_UINT("audio_block_frames",            &settings->uints.audio_block_frames, true, 0, false);
   SETTING_UINT("midi_volume",                   &settings->uints.midi_volume, true, DEFAULT_MIDI_VOLUME, false);

#ifdef HAVE_WASAPI
   SETTING_UINT("audio_wasapi_sh_buffer_length",  &settings->uints.audio_wasapi_sh_buffer_length, true, DEFAULT_WASAPI_SH_BUFFER_LENGTH, false);
#endif

#ifdef HAVE_MICROPHONE
   SETTING_UINT("microphone_latency",            &settings->uints.microphone_latency, false, 0 /* TODO */, false);
   SETTING_UINT("microphone_resampler_quality",  &settings->uints.microphone_resampler_quality, true, DEFAULT_AUDIO_RESAMPLER_QUALITY_LEVEL, false);
   SETTING_UINT("microphone_block_frames",       &settings->uints.microphone_block_frames, true, 0, false);
   SETTING_UINT("microphone_rate",               &settings->uints.microphone_sample_rate, true, DEFAULT_INPUT_RATE, false);
#ifdef HAVE_WASAPI
   SETTING_UINT("microphone_wasapi_sh_buffer_length", &settings->uints.microphone_wasapi_sh_buffer_length, true, DEFAULT_WASAPI_MICROPHONE_SH_BUFFER_LENGTH, false);
#endif
#endif

   SETTING_UINT("crt_switch_resolution",         &settings->uints.crt_switch_resolution, true, DEFAULT_CRT_SWITCH_RESOLUTION, false);
   SETTING_UINT("crt_switch_resolution_super",   &settings->uints.crt_switch_resolution_super, true, DEFAULT_CRT_SWITCH_RESOLUTION_SUPER, false);
   SETTING_UINT("custom_viewport_width",         &settings->video_vp_custom.width, false, 0 /* TODO */, false);
   SETTING_UINT("custom_viewport_height",        &settings->video_vp_custom.height, false, 0 /* TODO */, false);
   SETTING_UINT("custom_viewport_x",             (unsigned*)&settings->video_vp_custom.x, false, 0 /* TODO */, false);
   SETTING_UINT("custom_viewport_y",             (unsigned*)&settings->video_vp_custom.y, false, 0 /* TODO */, false);
   SETTING_UINT("aspect_ratio_index",            &settings->uints.video_aspect_ratio_idx, true, DEFAULT_ASPECT_RATIO_IDX, false);
   SETTING_UINT("video_autoswitch_refresh_rate", &settings->uints.video_autoswitch_refresh_rate, true, DEFAULT_AUTOSWITCH_REFRESH_RATE, false);
   SETTING_UINT("video_monitor_index",           &settings->uints.video_monitor_index, true, DEFAULT_MONITOR_INDEX, false);
   SETTING_UINT("video_windowed_position_x",     &settings->uints.window_position_x,    true, 0, false);
   SETTING_UINT("video_windowed_position_y",     &settings->uints.window_position_y,    true, 0, false);
   SETTING_UINT("video_windowed_position_width", &settings->uints.window_position_width,    true, DEFAULT_WINDOW_WIDTH, false);
   SETTING_UINT("video_windowed_position_height",&settings->uints.window_position_height,    true, DEFAULT_WINDOW_HEIGHT, false);
   SETTING_UINT("video_window_auto_width_max",   &settings->uints.window_auto_width_max,    true, DEFAULT_WINDOW_AUTO_WIDTH_MAX, false);
   SETTING_UINT("video_window_auto_height_max",  &settings->uints.window_auto_height_max,    true, DEFAULT_WINDOW_AUTO_HEIGHT_MAX, false);
#ifdef __WINRT__
   SETTING_UINT("video_fullscreen_x",            &settings->uints.video_fullscreen_x, true, uwp_get_width(), false);
   SETTING_UINT("video_fullscreen_y",            &settings->uints.video_fullscreen_y, true, uwp_get_height(), false);
#else
   SETTING_UINT("video_fullscreen_x",            &settings->uints.video_fullscreen_x, true, DEFAULT_FULLSCREEN_X, false);
   SETTING_UINT("video_fullscreen_y",            &settings->uints.video_fullscreen_y, true, DEFAULT_FULLSCREEN_Y, false);
#endif
   SETTING_UINT("video_scale",                   &settings->uints.video_scale, true, DEFAULT_SCALE, false);
   SETTING_UINT("video_scale_integer_axis",      &settings->uints.video_scale_integer_axis, true, DEFAULT_SCALE_INTEGER_AXIS, false);
   SETTING_UINT("video_scale_integer_scaling",   &settings->uints.video_scale_integer_scaling, true, DEFAULT_SCALE_INTEGER_SCALING, false);
   SETTING_UINT("video_window_opacity",          &settings->uints.video_window_opacity, true, DEFAULT_WINDOW_OPACITY, false);
   SETTING_UINT("video_shader_delay",            &settings->uints.video_shader_delay, true, DEFAULT_SHADER_DELAY, false);
#ifdef GEKKO
   SETTING_UINT("video_viwidth",                    &settings->uints.video_viwidth, true, DEFAULT_VIDEO_VI_WIDTH, false);
   SETTING_UINT("video_overscan_correction_top",    &settings->uints.video_overscan_correction_top, true, DEFAULT_VIDEO_OVERSCAN_CORRECTION_TOP, false);
   SETTING_UINT("video_overscan_correction_bottom", &settings->uints.video_overscan_correction_bottom, true, DEFAULT_VIDEO_OVERSCAN_CORRECTION_BOTTOM, false);
#endif
   SETTING_UINT("video_hard_sync_frames",        &settings->uints.video_hard_sync_frames, true, DEFAULT_HARD_SYNC_FRAMES, false);
   SETTING_UINT("video_frame_delay",             &settings->uints.video_frame_delay,      true, DEFAULT_FRAME_DELAY, false);
   SETTING_UINT("video_max_swapchain_images",    &settings->uints.video_max_swapchain_images, true, DEFAULT_MAX_SWAPCHAIN_IMAGES, false);
   SETTING_UINT("video_black_frame_insertion",   &settings->uints.video_black_frame_insertion, true, DEFAULT_BLACK_FRAME_INSERTION, false);
   SETTING_UINT("video_bfi_dark_frames",         &settings->uints.video_bfi_dark_frames, true, DEFAULT_BFI_DARK_FRAMES, false);
   SETTING_UINT("video_shader_subframes",        &settings->uints.video_shader_subframes, true, DEFAULT_SHADER_SUBFRAMES, false);
   SETTING_UINT("video_swap_interval",           &settings->uints.video_swap_interval, true, DEFAULT_SWAP_INTERVAL, false);
   SETTING_UINT("video_rotation",                &settings->uints.video_rotation, true, ORIENTATION_NORMAL, false);
   SETTING_UINT("screen_orientation",            &settings->uints.screen_orientation, true, ORIENTATION_NORMAL, false);
   SETTING_UINT("video_msg_bgcolor_red",         &settings->uints.video_msg_bgcolor_red, true, DEFAULT_MESSAGE_BGCOLOR_RED, false);
   SETTING_UINT("video_msg_bgcolor_green",       &settings->uints.video_msg_bgcolor_green, true, DEFAULT_MESSAGE_BGCOLOR_GREEN, false);
   SETTING_UINT("video_msg_bgcolor_blue",        &settings->uints.video_msg_bgcolor_blue, true, DEFAULT_MESSAGE_BGCOLOR_BLUE, false);

   SETTING_UINT("video_stream_port",             &settings->uints.video_stream_port, true, RARCH_STREAM_DEFAULT_PORT, false);
   SETTING_UINT("video_record_threads",          &settings->uints.video_record_threads, true, DEFAULT_VIDEO_RECORD_THREADS, false);
   SETTING_UINT("video_record_quality",          &settings->uints.video_record_quality, true, RECORD_CONFIG_TYPE_RECORDING_MED_QUALITY, false);
   SETTING_UINT("video_stream_quality",          &settings->uints.video_stream_quality, true, RECORD_CONFIG_TYPE_STREAMING_MED_QUALITY, false);
   SETTING_UINT("video_record_scale_factor",     &settings->uints.video_record_scale_factor, true, 1, false);
   SETTING_UINT("video_stream_scale_factor",     &settings->uints.video_stream_scale_factor, true, 1, false);

#ifdef HAVE_NETWORKING
   SETTING_UINT("streaming_mode",                &settings->uints.streaming_mode, true, STREAMING_MODE_TWITCH, false);
#endif
   SETTING_UINT("screen_brightness",             &settings->uints.screen_brightness, true, DEFAULT_SCREEN_BRIGHTNESS, false);

   SETTING_UINT("input_bind_timeout",            &settings->uints.input_bind_timeout,     true, DEFAULT_INPUT_BIND_TIMEOUT, false);
   SETTING_UINT("input_bind_hold",               &settings->uints.input_bind_hold,        true, DEFAULT_INPUT_BIND_HOLD, false);
   SETTING_UINT("input_turbo_period",            &settings->uints.input_turbo_period,     true, DEFAULT_TURBO_PERIOD, false);
   SETTING_UINT("input_turbo_duty_cycle",        &settings->uints.input_turbo_duty_cycle, true, DEFAULT_TURBO_DUTY_CYCLE, false);
   SETTING_UINT("input_turbo_mode",              &settings->uints.input_turbo_mode,       true, DEFAULT_TURBO_MODE, false);
   SETTING_UINT("input_turbo_button",            &settings->uints.input_turbo_button,     true, DEFAULT_TURBO_BUTTON, false);
   SETTING_UINT("input_max_users",               &settings->uints.input_max_users,          true, DEFAULT_INPUT_MAX_USERS, false);
   SETTING_UINT("input_menu_toggle_gamepad_combo", &settings->uints.input_menu_toggle_gamepad_combo, true, DEFAULT_MENU_TOGGLE_GAMEPAD_COMBO, false);
   SETTING_UINT("input_poll_type_behavior",      &settings->uints.input_poll_type_behavior, true, DEFAULT_INPUT_POLL_TYPE_BEHAVIOR, false);
   SETTING_UINT("input_quit_gamepad_combo",      &settings->uints.input_quit_gamepad_combo, true, DEFAULT_QUIT_GAMEPAD_COMBO, false);
   SETTING_UINT("input_hotkey_block_delay",      &settings->uints.input_hotkey_block_delay, true, DEFAULT_INPUT_HOTKEY_BLOCK_DELAY, false);
#ifdef GEKKO
   SETTING_UINT("input_mouse_scale",             &settings->uints.input_mouse_scale, true, DEFAULT_MOUSE_SCALE, false);
#endif
   SETTING_UINT("input_touch_scale",             &settings->uints.input_touch_scale, true, DEFAULT_TOUCH_SCALE, false);
   SETTING_UINT("input_rumble_gain",             &settings->uints.input_rumble_gain, true, DEFAULT_RUMBLE_GAIN, false);
   SETTING_UINT("input_auto_game_focus",         &settings->uints.input_auto_game_focus, true, DEFAULT_INPUT_AUTO_GAME_FOCUS, false);
#ifdef ANDROID
   SETTING_UINT("input_block_timeout",           &settings->uints.input_block_timeout, true, 0, false);
#endif
   SETTING_UINT("keyboard_gamepad_mapping_type", &settings->uints.input_keyboard_gamepad_mapping_type, true, 1, false);

#if defined(HAVE_OVERLAY)
   SETTING_UINT("input_overlay_show_inputs",               &settings->uints.input_overlay_show_inputs, true, DEFAULT_OVERLAY_SHOW_INPUTS, false);
   SETTING_UINT("input_overlay_show_inputs_port",          &settings->uints.input_overlay_show_inputs_port, true, DEFAULT_OVERLAY_SHOW_INPUTS_PORT, false);
   SETTING_UINT("input_overlay_dpad_diagonal_sensitivity", &settings->uints.input_overlay_dpad_diagonal_sensitivity, true, DEFAULT_OVERLAY_DPAD_DIAGONAL_SENSITIVITY, false);
   SETTING_UINT("input_overlay_abxy_diagonal_sensitivity", &settings->uints.input_overlay_abxy_diagonal_sensitivity, true, DEFAULT_OVERLAY_ABXY_DIAGONAL_SENSITIVITY, false);
   SETTING_UINT("input_overlay_analog_recenter_zone",      &settings->uints.input_overlay_analog_recenter_zone, true, DEFAULT_INPUT_OVERLAY_ANALOG_RECENTER_ZONE, false);
#endif

#ifdef HAVE_LIBNX
   SETTING_UINT("split_joycon_p1",               &settings->uints.input_split_joycon[0], true, 0, false);
   SETTING_UINT("split_joycon_p2",               &settings->uints.input_split_joycon[1], true, 0, false);
   SETTING_UINT("split_joycon_p3",               &settings->uints.input_split_joycon[2], true, 0, false);
   SETTING_UINT("split_joycon_p4",               &settings->uints.input_split_joycon[3], true, 0, false);
   SETTING_UINT("split_joycon_p5",               &settings->uints.input_split_joycon[4], true, 0, false);
   SETTING_UINT("split_joycon_p6",               &settings->uints.input_split_joycon[5], true, 0, false);
   SETTING_UINT("split_joycon_p7",               &settings->uints.input_split_joycon[6], true, 0, false);
   SETTING_UINT("split_joycon_p8",               &settings->uints.input_split_joycon[7], true, 0, false);
#endif

#ifdef HAVE_SCREENSHOTS
   SETTING_UINT("notification_show_screenshot_duration", &settings->uints.notification_show_screenshot_duration, true, DEFAULT_NOTIFICATION_SHOW_SCREENSHOT_DURATION, false);
   SETTING_UINT("notification_show_screenshot_flash",    &settings->uints.notification_show_screenshot_flash, true, DEFAULT_NOTIFICATION_SHOW_SCREENSHOT_FLASH, false);
#endif

#ifdef HAVE_NETWORKING
   SETTING_UINT("netplay_ip_port",                    &settings->uints.netplay_port, true, RARCH_DEFAULT_PORT, false);
   SETTING_OVERRIDE(RARCH_OVERRIDE_SETTING_NETPLAY_IP_PORT);
   SETTING_UINT("netplay_max_connections",            &settings->uints.netplay_max_connections, true, DEFAULT_NETPLAY_MAX_CONNECTIONS, false);
   SETTING_UINT("netplay_max_ping",                   &settings->uints.netplay_max_ping, true, DEFAULT_NETPLAY_MAX_PING, false);
   SETTING_UINT("netplay_chat_color_name",            &settings->uints.netplay_chat_color_name, true, DEFAULT_NETPLAY_CHAT_COLOR_NAME, false);
   SETTING_UINT("netplay_chat_color_msg",             &settings->uints.netplay_chat_color_msg, true, DEFAULT_NETPLAY_CHAT_COLOR_MSG, false);
   SETTING_UINT("netplay_input_latency_frames_min",   &settings->uints.netplay_input_latency_frames_min, true, 0, false);
   SETTING_UINT("netplay_input_latency_frames_range", &settings->uints.netplay_input_latency_frames_range, true, 0, false);
   SETTING_UINT("netplay_share_digital",              &settings->uints.netplay_share_digital, true, DEFAULT_NETPLAY_SHARE_DIGITAL, false);
   SETTING_UINT("netplay_share_analog",               &settings->uints.netplay_share_analog,  true, DEFAULT_NETPLAY_SHARE_ANALOG, false);
#endif
#ifdef HAVE_COMMAND
   SETTING_UINT("network_cmd_port",              &settings->uints.network_cmd_port,    true, DEFAULT_NETWORK_CMD_PORT, false);
#endif
#ifdef HAVE_NETWORKGAMEPAD
   SETTING_UINT("network_remote_base_port",      &settings->uints.network_remote_base_port, true, DEFAULT_NETWORK_REMOTE_BASE_PORT, false);
#endif

#ifdef HAVE_LANGEXTRA
   SETTING_UINT("user_language",                 msg_hash_get_uint(MSG_HASH_USER_LANGUAGE), true, frontend_driver_get_user_language(), false);
#endif
#ifndef __APPLE__
   SETTING_UINT("bundle_assets_extract_version_current", &settings->uints.bundle_assets_extract_version_current, true, 0, false);
#endif

#ifdef HAVE_CHEEVOS
   SETTING_UINT("cheevos_appearance_anchor",     &settings->uints.cheevos_appearance_anchor, true, DEFAULT_CHEEVOS_APPEARANCE_ANCHOR, false);
   SETTING_UINT("cheevos_visibility_summary",    &settings->uints.cheevos_visibility_summary, true, DEFAULT_CHEEVOS_VISIBILITY_SUMMARY, false);
#endif
   SETTING_UINT("accessibility_narrator_speech_speed", &settings->uints.accessibility_narrator_speech_speed, true, DEFAULT_ACCESSIBILITY_NARRATOR_SPEECH_SPEED, false);
   SETTING_UINT("ai_service_mode",              &settings->uints.ai_service_mode,            true, DEFAULT_AI_SERVICE_MODE, false);
   SETTING_UINT("ai_service_target_lang",       &settings->uints.ai_service_target_lang,     true, 0, false);
   SETTING_UINT("ai_service_source_lang",       &settings->uints.ai_service_source_lang,     true, 0, false);

#ifdef HAVE_LIBNX
   SETTING_UINT("libnx_overclock",               &settings->uints.libnx_overclock, true, SWITCH_DEFAULT_CPU_PROFILE, false);
#endif
#if defined(DINGUX)
   SETTING_UINT("video_dingux_ipu_filter_type",  &settings->uints.video_dingux_ipu_filter_type, true, DEFAULT_DINGUX_IPU_FILTER_TYPE, false);
#if defined(DINGUX_BETA)
   SETTING_UINT("video_dingux_refresh_rate",     &settings->uints.video_dingux_refresh_rate, true, DEFAULT_DINGUX_REFRESH_RATE, false);
#endif
#if defined(RS90) || defined(MIYOO)
   SETTING_UINT("video_dingux_rs90_softfilter_type", &settings->uints.video_dingux_rs90_softfilter_type, true, DEFAULT_DINGUX_RS90_SOFTFILTER_TYPE, false);
#endif
#endif

#ifdef HAVE_LAKKA
   SETTING_UINT("cpu_scaling_mode",              &settings->uints.cpu_scaling_mode,    true,   0, false);
   SETTING_UINT("cpu_min_freq",                  &settings->uints.cpu_min_freq,        true,   1, false);
   SETTING_UINT("cpu_max_freq",                  &settings->uints.cpu_max_freq,        true, ~0U, false);
#endif

#ifdef HAVE_MIST
   SETTING_UINT("steam_rich_presence_format",    &settings->uints.steam_rich_presence_format, true, DEFAULT_STEAM_RICH_PRESENCE_FORMAT, false);
#endif

#ifdef HAVE_OVERLAY
   SETTING_UINT("input_overlay_lightgun_trigger_delay",     &settings->uints.input_overlay_lightgun_trigger_delay, true, DEFAULT_INPUT_OVERLAY_LIGHTGUN_TRIGGER_DELAY, false);
   SETTING_UINT("input_overlay_lightgun_two_touch_input",   &settings->uints.input_overlay_lightgun_two_touch_input, true, DEFAULT_INPUT_OVERLAY_LIGHTGUN_MULTI_TOUCH_INPUT, false);
   SETTING_UINT("input_overlay_lightgun_three_touch_input", &settings->uints.input_overlay_lightgun_three_touch_input, true, DEFAULT_INPUT_OVERLAY_LIGHTGUN_MULTI_TOUCH_INPUT, false);
   SETTING_UINT("input_overlay_lightgun_four_touch_input",  &settings->uints.input_overlay_lightgun_four_touch_input, true, DEFAULT_INPUT_OVERLAY_LIGHTGUN_MULTI_TOUCH_INPUT, false);
   SETTING_UINT("input_overlay_mouse_hold_msec",            &settings->uints.input_overlay_mouse_hold_msec, true, DEFAULT_INPUT_OVERLAY_MOUSE_HOLD_MSEC, false);
   SETTING_UINT("input_overlay_mouse_dtap_msec",            &settings->uints.input_overlay_mouse_dtap_msec, true, DEFAULT_INPUT_OVERLAY_MOUSE_DTAP_MSEC, false);
#endif

   *size = count;

   return tmp;
}

static struct config_size_setting *populate_settings_size(
      settings_t *settings, int *size)
{
   unsigned count                     = 0;
   struct config_size_setting  *tmp   = (struct config_size_setting*)calloc((*size + 1), sizeof(struct config_size_setting));

   if (!tmp)
      return NULL;

   SETTING_SIZE("rewind_buffer_size",            &settings->sizes.rewind_buffer_size, true, DEFAULT_REWIND_BUFFER_SIZE, false);

   *size = count;

   return tmp;
}

static struct config_int_setting *populate_settings_int(
      settings_t *settings, int *size)
{
   unsigned count                     = 0;
   struct config_int_setting  *tmp    = (struct config_int_setting*)calloc((*size + 1), sizeof(struct config_int_setting));

   if (!tmp)
      return NULL;
    
   SETTING_INT("state_slot",                     &settings->ints.state_slot, false, 0, false);
   SETTING_INT("replay_slot",                    &settings->ints.replay_slot, false, 0, false);

   SETTING_INT("crt_switch_center_adjust",       &settings->ints.crt_switch_center_adjust, false, DEFAULT_CRT_SWITCH_CENTER_ADJUST, false);
   SETTING_INT("crt_switch_porch_adjust",        &settings->ints.crt_switch_porch_adjust, false, DEFAULT_CRT_SWITCH_PORCH_ADJUST, false);
   SETTING_INT("crt_switch_vertical_adjust",     &settings->ints.crt_switch_vertical_adjust, false, DEFAULT_CRT_SWITCH_VERTICAL_ADJUST, false);
#ifdef HAVE_WINDOW_OFFSET
   SETTING_INT("video_window_offset_x",          &settings->ints.video_window_offset_x, true, DEFAULT_WINDOW_OFFSET_X, false);
   SETTING_INT("video_window_offset_y",          &settings->ints.video_window_offset_y, true, DEFAULT_WINDOW_OFFSET_Y, false);
#endif
   SETTING_INT("video_max_frame_latency",        &settings->ints.video_max_frame_latency, true, DEFAULT_MAX_FRAME_LATENCY, false);

#ifdef HAVE_D3D10
   SETTING_INT("d3d10_gpu_index",                &settings->ints.d3d10_gpu_index, true, DEFAULT_D3D10_GPU_INDEX, false);
#endif
#ifdef HAVE_D3D11
   SETTING_INT("d3d11_gpu_index",                &settings->ints.d3d11_gpu_index, true, DEFAULT_D3D11_GPU_INDEX, false);
#endif
#ifdef HAVE_D3D12
   SETTING_INT("d3d12_gpu_index",                &settings->ints.d3d12_gpu_index, true, DEFAULT_D3D12_GPU_INDEX, false);
#endif
#ifdef HAVE_VULKAN
   SETTING_INT("vulkan_gpu_index",               &settings->ints.vulkan_gpu_index, true, DEFAULT_VULKAN_GPU_INDEX, false);
#endif

#ifdef HAVE_NETWORKING
   SETTING_INT("netplay_check_frames",           &settings->ints.netplay_check_frames, true, DEFAULT_NETPLAY_CHECK_FRAMES, false);
   SETTING_OVERRIDE(RARCH_OVERRIDE_SETTING_NETPLAY_CHECK_FRAMES);
#endif

#ifdef HAVE_OVERLAY
   SETTING_INT("input_overlay_lightgun_port",    &settings->ints.input_overlay_lightgun_port, true, DEFAULT_INPUT_OVERLAY_LIGHTGUN_PORT, false);
#endif
   SETTING_INT("input_turbo_bind",               &settings->ints.input_turbo_bind, true, DEFAULT_TURBO_BIND, false);

   *size = count;

   return tmp;
}

static void video_driver_default_settings(global_t *global)
{
   if (!global)
      return;

   global->console.screen.gamma_correction       = DEFAULT_GAMMA;
   global->console.flickerfilter_enable          = false;
   global->console.softfilter_enable             = false;

   global->console.screen.resolutions.current.id = 0;
}

/* Moves built-in playlists from legacy location to 'playlists/builtin' */
#define CONFIG_PLAYLIST_MIGRATION(playlist_path, playlist_tag) \
{ \
   char new_file[PATH_MAX_LENGTH]; \
   fill_pathname_resolve_relative( \
         playlist_path, \
         path_config, \
         playlist_tag, \
         sizeof(playlist_path)); \
   fill_pathname_join_special( \
         new_file, \
         new_path, \
         playlist_tag, \
         sizeof(tmp_str)); \
   if (path_is_valid(playlist_path)) \
   { \
      if (!filestream_copy(playlist_path, new_file)) \
         RARCH_LOG("[Config] Copied file \"%s\" to \"%s\".\n", playlist_path, new_file); \
      if (path_is_valid(new_file) && !filestream_cmp(playlist_path, new_file)) \
      { \
         if (!filestream_delete(playlist_path)) \
            RARCH_LOG("[Config] Deleted file \"%s\".\n", playlist_path); \
      } \
      else \
         new_file[0] = '\0'; \
   } \
   if (!string_is_empty(new_file)) \
      strlcpy(playlist_path, new_file, sizeof(playlist_path)); \
} \

/**
 * config_set_defaults:
 *
 * Set 'default' configuration values.
 **/
void config_set_defaults(void *data)
{
   size_t i;
   global_t *global                 = (global_t*)data;
   settings_t *settings             = config_st;
   recording_state_t *recording_st  = recording_state_get_ptr();
   int bool_settings_size           = sizeof(settings->bools)   / sizeof(settings->bools.placeholder);
   int float_settings_size          = sizeof(settings->floats)  / sizeof(settings->floats.placeholder);
   int int_settings_size            = sizeof(settings->ints)    / sizeof(settings->ints.placeholder);
   int uint_settings_size           = sizeof(settings->uints)   / sizeof(settings->uints.placeholder);
   int size_settings_size           = sizeof(settings->sizes)   / sizeof(settings->sizes.placeholder);
   const char *def_video            = config_get_default_video();
   const char *def_audio            = config_get_default_audio();
#ifdef HAVE_MICROPHONE
   const char *def_microphone       = config_get_default_microphone();
#endif
   const char *def_audio_resampler  = config_get_default_audio_resampler();
   const char *def_input            = config_get_default_input();
   const char *def_joypad           = config_get_default_joypad();
   const char *def_camera           = config_get_default_camera();
   const char *def_bluetooth        = config_get_default_bluetooth();
   const char *def_wifi             = config_get_default_wifi();
   const char *def_led              = config_get_default_led();
   const char *def_cloudsync        = config_get_default_cloudsync();
   const char *def_location         = config_get_default_location();
   const char *def_record           = config_get_default_record();
   const char *def_midi             = config_get_default_midi();
   const char *def_mitm             = DEFAULT_NETPLAY_MITM_SERVER;
   struct video_viewport *custom_vp = &settings->video_vp_custom;
   struct config_float_setting      *float_settings = populate_settings_float (settings, &float_settings_size);
   struct config_bool_setting       *bool_settings  = populate_settings_bool  (settings, &bool_settings_size);
   struct config_int_setting        *int_settings   = populate_settings_int   (settings, &int_settings_size);
   struct config_uint_setting       *uint_settings  = populate_settings_uint  (settings, &uint_settings_size);
   struct config_size_setting       *size_settings  = populate_settings_size  (settings, &size_settings_size);

   if (bool_settings && (bool_settings_size > 0))
   {
      for (i = 0; i < (unsigned)bool_settings_size; i++)
      {
         if (bool_settings[i].flags & CFG_BOOL_FLG_DEF_ENABLE)
            *bool_settings[i].ptr = bool_settings[i].def;
      }

      free(bool_settings);
   }

   if (int_settings && (int_settings_size > 0))
   {
      for (i = 0; i < (unsigned)int_settings_size; i++)
      {
         if (int_settings[i].flags & CFG_BOOL_FLG_DEF_ENABLE)
            *int_settings[i].ptr = int_settings[i].def;
      }

      free(int_settings);
   }

   if (uint_settings && (uint_settings_size > 0))
   {
      for (i = 0; i < (unsigned)uint_settings_size; i++)
      {
         if (uint_settings[i].flags & CFG_BOOL_FLG_DEF_ENABLE)
            *uint_settings[i].ptr = uint_settings[i].def;
      }

      free(uint_settings);
   }

   if (size_settings && (size_settings_size > 0))
   {
      for (i = 0; i < (unsigned)size_settings_size; i++)
      {
         if (size_settings[i].flags & CFG_BOOL_FLG_DEF_ENABLE)
            *size_settings[i].ptr = size_settings[i].def;
      }

      free(size_settings);
   }

   if (float_settings && (float_settings_size > 0))
   {
      for (i = 0; i < (unsigned)float_settings_size; i++)
      {
         if (float_settings[i].flags & CFG_BOOL_FLG_DEF_ENABLE)
            *float_settings[i].ptr = float_settings[i].def;
      }

      free(float_settings);
   }

   if (def_camera)
      configuration_set_string(settings,
            settings->arrays.camera_driver,
            def_camera);
   if (def_bluetooth)
      configuration_set_string(settings,
            settings->arrays.bluetooth_driver,
            def_bluetooth);
   if (def_wifi)
      configuration_set_string(settings,
            settings->arrays.wifi_driver,
            def_wifi);
   if (def_led)
      configuration_set_string(settings,
            settings->arrays.led_driver,
            def_led);
   if (def_cloudsync)
      configuration_set_string(settings,
            settings->arrays.cloud_sync_driver,
            def_cloudsync);
   if (def_location)
      configuration_set_string(settings,
            settings->arrays.location_driver,
            def_location);
   if (def_video)
      configuration_set_string(settings,
            settings->arrays.video_driver,
            def_video);
   if (def_audio)
      configuration_set_string(settings,
            settings->arrays.audio_driver,
            def_audio);
#ifdef HAVE_MICROPHONE
   if (def_microphone)
      configuration_set_string(settings,
            settings->arrays.microphone_driver,
            def_microphone);
   if (def_audio_resampler)  /* not a typo, microphone's default sampler is the same as audio's */
      configuration_set_string(settings,
            settings->arrays.microphone_resampler,
            def_audio_resampler);
#endif // HAVE_MICROPHONE
   if (def_audio_resampler)
      configuration_set_string(settings,
            settings->arrays.audio_resampler,
            def_audio_resampler);
   if (def_input)
      configuration_set_string(settings,
            settings->arrays.input_driver,
            def_input);
   if (def_joypad)
      configuration_set_string(settings,
            settings->arrays.input_joypad_driver,
            def_joypad);
   if (def_record)
      configuration_set_string(settings,
            settings->arrays.record_driver,
            def_record);
   if (def_midi)
      configuration_set_string(settings,
            settings->arrays.midi_driver,
            def_midi);
   if (def_mitm)
      configuration_set_string(settings,
            settings->arrays.netplay_mitm_server,
            def_mitm);

   settings->uints.video_scale                 = DEFAULT_SCALE;

   video_driver_set_threaded(DEFAULT_VIDEO_THREADED);

   settings->floats.video_msg_color_r          = ((DEFAULT_MESSAGE_COLOR >> 16) & 0xff) / 255.0f;
   settings->floats.video_msg_color_g          = ((DEFAULT_MESSAGE_COLOR >>  8) & 0xff) / 255.0f;
   settings->floats.video_msg_color_b          = ((DEFAULT_MESSAGE_COLOR >>  0) & 0xff) / 255.0f;

   if (g_defaults.settings_video_refresh_rate > 0.0 &&
         g_defaults.settings_video_refresh_rate != DEFAULT_REFRESH_RATE)
      settings->floats.video_refresh_rate      = g_defaults.settings_video_refresh_rate;

   if (DEFAULT_AUDIO_DEVICE)
      configuration_set_string(settings,
            settings->arrays.audio_device,
            DEFAULT_AUDIO_DEVICE);

   if (!g_defaults.settings_out_latency)
      g_defaults.settings_out_latency          = DEFAULT_OUT_LATENCY;

   settings->uints.audio_latency               = g_defaults.settings_out_latency;

   if (!g_defaults.settings_in_latency)
      g_defaults.settings_in_latency          = DEFAULT_IN_LATENCY;


   audio_set_float(AUDIO_ACTION_VOLUME_GAIN, settings->floats.audio_volume);
#ifdef HAVE_AUDIOMIXER
   audio_set_float(AUDIO_ACTION_MIXER_VOLUME_GAIN, settings->floats.audio_mixer_volume);
#endif

#ifdef HAVE_MICROPHONE
   if (DEFAULT_MICROPHONE_DEVICE)
      configuration_set_string(settings,
            settings->arrays.microphone_device,
            DEFAULT_MICROPHONE_DEVICE);

   settings->uints.microphone_latency         = g_defaults.settings_in_latency;
#endif // HAVE_MICROPHONE

   configuration_set_string(settings,
         settings->arrays.midi_input,
         DEFAULT_MIDI_INPUT);
   configuration_set_string(settings,
         settings->arrays.midi_output,
         DEFAULT_MIDI_OUTPUT);

#ifdef HAVE_LAKKA
   configuration_set_bool(settings,
         settings->bools.ssh_enable, filestream_exists(LAKKA_SSH_PATH));
   configuration_set_bool(settings,
         settings->bools.samba_enable, filestream_exists(LAKKA_SAMBA_PATH));
   configuration_set_bool(settings,
         settings->bools.bluetooth_enable, filestream_exists(LAKKA_BLUETOOTH_PATH));
   configuration_set_bool(settings, settings->bools.localap_enable, false);
   load_timezone(settings->arrays.timezone, TIMEZONE_LENGTH);
#endif // HAVE_LAKKA

#if __APPLE__
   configuration_set_bool(settings,
         settings->bools.accessibility_enable, RAIsVoiceOverRunning());
#endif

#ifdef ANDROID
   configuration_set_bool(settings,
         settings->bools.accessibility_enable, is_screen_reader_enabled());
#endif

#ifdef HAVE_CHEEVOS
   *settings->arrays.cheevos_username                 = '\0';
   *settings->arrays.cheevos_password                 = '\0';
   *settings->arrays.cheevos_token                    = '\0';
#endif

   input_config_reset();
   input_remapping_deinit(false);
   input_remapping_set_defaults(false);

   *settings->arrays.input_keyboard_layout                = '\0';

   for (i = 0; i < MAX_USERS; i++)
   {
      settings->uints.input_joypad_index[i] = (unsigned)i;
#ifdef SWITCH /* Switch preferred default dpad mode */
      settings->uints.input_analog_dpad_mode[i] = ANALOG_DPAD_LSTICK;
#else
      settings->uints.input_analog_dpad_mode[i] = ANALOG_DPAD_NONE;
#endif
      input_config_set_device((unsigned)i, RETRO_DEVICE_JOYPAD);
      settings->uints.input_mouse_index[i] = (unsigned)i;
   }

   custom_vp->width  = 0;
   custom_vp->height = 0;
   custom_vp->x      = 0;
   custom_vp->y      = 0;

   /* Make sure settings from other configs carry over into defaults
    * for another config. */
   if (!retroarch_override_setting_is_set(RARCH_OVERRIDE_SETTING_SAVE_PATH, NULL))
      dir_clear(RARCH_DIR_SAVEFILE);
   if (!retroarch_override_setting_is_set(RARCH_OVERRIDE_SETTING_STATE_PATH, NULL))
      dir_clear(RARCH_DIR_SAVESTATE);

   *settings->paths.directory_start           = '\0';
   *settings->paths.directory_main_config     = '\0';
   *settings->paths.directory_input_remapping = '\0';
   *settings->paths.directory_autoconfig   = '\0';
   *settings->paths.directory_audio_filter = '\0';
   *settings->paths.directory_video_filter = '\0';
   *settings->paths.directory_assets       = '\0';
   *settings->paths.directory_libretro     = '\0';
   *settings->paths.path_libretro_info     = '\0';
   *settings->paths.directory_video_shader = '\0';
   *settings->paths.directory_user_video_shader = '\0';
   *settings->paths.directory_screenshot   = '\0';
   *settings->paths.directory_playlist     = '\0';
   *settings->paths.directory_cache        = '\0';
   *settings->paths.directory_thumbnails   = '\0';
   *settings->paths.path_content_database  = '\0';
   *settings->paths.path_cheat_database    = '\0';

   retroarch_ctl(RARCH_CTL_UNSET_UPS_PREF, NULL);
   retroarch_ctl(RARCH_CTL_UNSET_BPS_PREF, NULL);
   retroarch_ctl(RARCH_CTL_UNSET_IPS_PREF, NULL);
   retroarch_ctl(RARCH_CTL_UNSET_XDELTA_PREF, NULL);

   *recording_st->output_dir                     = '\0';
   *recording_st->config_dir                     = '\0';
   *settings->paths.path_core_options            = '\0';
   *settings->paths.path_cheat_settings          = '\0';
   *settings->paths.path_overlay           = '\0';
   *settings->paths.path_osk_overlay       = '\0';
   *settings->paths.path_record_config     = '\0';
   *settings->paths.path_stream_config     = '\0';
   *settings->paths.path_stream_url        = '\0';
   *settings->paths.path_softfilter_plugin = '\0';
   *settings->paths.path_audio_dsp_plugin = '\0';
   *settings->paths.log_dir = '\0';

   video_driver_default_settings(global);

   if (!string_is_empty(g_defaults.dirs[DEFAULT_DIR_START]))
      configuration_set_string(settings,
            settings->paths.directory_start,
            g_defaults.dirs[DEFAULT_DIR_START]);
   if (!string_is_empty(g_defaults.dirs[DEFAULT_DIR_MAIN_CONFIG]))
   {

      char config_file_path[PATH_MAX_LENGTH];
      configuration_set_string(settings,
         settings->paths.directory_main_config,
         g_defaults.dirs[DEFAULT_DIR_MAIN_CONFIG]);
         fill_pathname_join_special(config_file_path,
            settings->paths.directory_main_config,
            FILE_PATH_MAIN_CONFIG,
            sizeof(config_file_path));
         path_set(RARCH_PATH_CONFIG, config_file_path);
    }
   if (!string_is_empty(g_defaults.dirs[DEFAULT_DIR_REMAP]))
      configuration_set_string(settings,
            settings->paths.directory_input_remapping,
            g_defaults.dirs[DEFAULT_DIR_REMAP]);
   if (!string_is_empty(g_defaults.dirs[DEFAULT_DIR_AUTOCONFIG]))
      configuration_set_string(settings,
            settings->paths.directory_autoconfig,
            g_defaults.dirs[DEFAULT_DIR_AUTOCONFIG]);
   if (!string_is_empty(g_defaults.dirs[DEFAULT_DIR_AUDIO_FILTER]))
      configuration_set_string(settings,
            settings->paths.directory_audio_filter,
            g_defaults.dirs[DEFAULT_DIR_AUDIO_FILTER]);
   if (!string_is_empty(g_defaults.dirs[DEFAULT_DIR_VIDEO_FILTER]))
      configuration_set_string(settings,
            settings->paths.directory_video_filter,
            g_defaults.dirs[DEFAULT_DIR_VIDEO_FILTER]);
   if (!string_is_empty(g_defaults.dirs[DEFAULT_DIR_ASSETS]))
      configuration_set_string(settings,
            settings->paths.directory_assets,
            g_defaults.dirs[DEFAULT_DIR_ASSETS]);
   if (!string_is_empty(g_defaults.dirs[DEFAULT_DIR_CORE]))
      fill_pathname_expand_special(settings->paths.directory_libretro,
            g_defaults.dirs[DEFAULT_DIR_CORE],
            sizeof(settings->paths.directory_libretro));
   if (!string_is_empty(g_defaults.dirs[DEFAULT_DIR_CORE_INFO]))
      fill_pathname_expand_special(settings->paths.path_libretro_info,
            g_defaults.dirs[DEFAULT_DIR_CORE_INFO],
            sizeof(settings->paths.path_libretro_info));
#ifdef HAVE_OVERLAY
   if (!string_is_empty(g_defaults.dirs[DEFAULT_DIR_OVERLAY]))
   {
      fill_pathname_expand_special(settings->paths.directory_overlay,
            g_defaults.dirs[DEFAULT_DIR_OVERLAY],
            sizeof(settings->paths.directory_overlay));
#ifdef RARCH_MOBILE
      if (string_is_empty(settings->paths.path_overlay))
         fill_pathname_join_special(settings->paths.path_overlay,
               settings->paths.directory_overlay,
               FILE_PATH_DEFAULT_OVERLAY,
               sizeof(settings->paths.path_overlay));
#endif // RARCH_MOBILE
   }
   if (!string_is_empty(g_defaults.dirs[DEFAULT_DIR_OSK_OVERLAY]))
   {
      fill_pathname_expand_special(settings->paths.directory_osk_overlay,
            g_defaults.dirs[DEFAULT_DIR_OSK_OVERLAY],
            sizeof(settings->paths.directory_osk_overlay));
      if(string_is_empty(settings->paths.path_osk_overlay))
         fill_pathname_join_special(settings->paths.path_osk_overlay,
               settings->paths.directory_osk_overlay,
               FILE_PATH_DEFAULT_OSK_OVERLAY2,
               sizeof(settings->paths.path_osk_overlay));
   }
#endif // HAVE_OVERLAY
   if (!string_is_empty(g_defaults.dirs[DEFAULT_DIR_SHADER]))
      fill_pathname_expand_special(settings->paths.directory_video_shader,
            g_defaults.dirs[DEFAULT_DIR_SHADER],
            sizeof(settings->paths.directory_video_shader));
   if(!string_is_empty(g_defaults.dirs[DEFAULT_DIR_USER_SHADER]))
      fill_pathname_expand_special(settings->paths.directory_user_video_shader,
            g_defaults.dirs[DEFAULT_DIR_USER_SHADER],
            sizeof(settings->paths.directory_user_video_shader));
   if (!string_is_empty(g_defaults.dirs[DEFAULT_DIR_SAVESTATE]))
      dir_set(RARCH_DIR_SAVESTATE, g_defaults.dirs[DEFAULT_DIR_SAVESTATE]);
   if (!string_is_empty(g_defaults.dirs[DEFAULT_DIR_SRAM]))
      dir_set(RARCH_DIR_SAVEFILE, g_defaults.dirs[DEFAULT_DIR_SRAM]);
   if (!string_is_empty(g_defaults.dirs[DEFAULT_DIR_SCREENSHOT]))
      configuration_set_string(settings,
            settings->paths.directory_screenshot,
            g_defaults.dirs[DEFAULT_DIR_SCREENSHOT]);
   if (!string_is_empty(g_defaults.dirs[DEFAULT_DIR_PLAYLIST]))
      configuration_set_string(settings,
            settings->paths.directory_playlist,
            g_defaults.dirs[DEFAULT_DIR_PLAYLIST]);
   if (!string_is_empty(g_defaults.dirs[DEFAULT_DIR_THUMBNAILS]))
      configuration_set_string(settings,
            settings->paths.directory_thumbnails,
            g_defaults.dirs[DEFAULT_DIR_THUMBNAILS]);
   if (!string_is_empty(g_defaults.dirs[DEFAULT_DIR_CACHE]))
      configuration_set_string(settings,
            settings->paths.directory_cache,
            g_defaults.dirs[DEFAULT_DIR_CACHE]);
   if (!string_is_empty(g_defaults.dirs[DEFAULT_DIR_DATABASE]))
      configuration_set_string(settings,
            settings->paths.path_content_database,
            g_defaults.dirs[DEFAULT_DIR_DATABASE]);
   if (!string_is_empty(g_defaults.dirs[DEFAULT_DIR_CHEATS]))
      configuration_set_string(settings,
            settings->paths.path_cheat_database,
            g_defaults.dirs[DEFAULT_DIR_CHEATS]);

   if (!string_is_empty(g_defaults.dirs[DEFAULT_DIR_LOGS]))
      configuration_set_string(settings,
            settings->paths.log_dir,
            g_defaults.dirs[DEFAULT_DIR_LOGS]);
   if (!string_is_empty(g_defaults.dirs[DEFAULT_DIR_RECORD_OUTPUT]))
      fill_pathname_expand_special(recording_st->output_dir,
            g_defaults.dirs[DEFAULT_DIR_RECORD_OUTPUT],
            sizeof(recording_st->output_dir));
   if (!string_is_empty(g_defaults.dirs[DEFAULT_DIR_RECORD_CONFIG]))
      fill_pathname_expand_special(recording_st->config_dir,
            g_defaults.dirs[DEFAULT_DIR_RECORD_CONFIG],
            sizeof(recording_st->config_dir));

   if (!string_is_empty(g_defaults.path_config))
   {
      char temp_str[PATH_MAX_LENGTH];

      temp_str[0] = '\0';

      fill_pathname_expand_special(temp_str,
            g_defaults.path_config,
            sizeof(temp_str));
      path_set(RARCH_PATH_CONFIG, temp_str);
   }

   /* Built-in playlist default paths,
    * needed when creating a new cfg from scratch */
   {
      char new_path[PATH_MAX_LENGTH];

      fill_pathname_join_special(
            new_path,
            settings->paths.directory_playlist,
            FILE_PATH_BUILTIN,
            sizeof(new_path));

      if (!path_is_directory(new_path))
         path_mkdir(new_path);
   }

#ifdef HAVE_CONFIGFILE
   /* Avoid reloading config on every content load */
   if (DEFAULT_BLOCK_CONFIG_READ)
      retroarch_ctl(RARCH_CTL_SET_BLOCK_CONFIG_READ, NULL);
   else
      retroarch_ctl(RARCH_CTL_UNSET_BLOCK_CONFIG_READ, NULL);
#endif // HAVE_CONFIGFILE
}

/**
 * config_load:
 *
 * Loads a config file and reads all the values into memory.
 *
 */
void config_load(void *data)
{
   global_t *global = (global_t*)data;
   config_set_defaults(global);
#ifdef HAVE_CONFIGFILE
   config_parse_file(global);
#endif
}

#ifdef HAVE_CONFIGFILE
/**
 * open_default_config_file
 *
 * Open a default config file. Platform-specific.
 *
 * Returns: handle to config file if found, otherwise NULL.
 **/
config_file_t *open_default_config_file(void)
{
   char conf_path[PATH_MAX_LENGTH];
   config_file_t *conf                    = NULL;
#ifndef RARCH_CONSOLE
   char application_data[PATH_MAX_LENGTH] = {0};
#endif
#if defined(_WIN32) && !defined(_XBOX)
   char app_path[PATH_MAX_LENGTH]         = {0};
#if defined(__WINRT__) || defined(WINAPI_FAMILY) && WINAPI_FAMILY == WINAPI_FAMILY_PHONE_APP
   /* On UWP, the app install directory is not writable so use the writable LocalState dir instead */
   fill_pathname_home_dir(app_path, sizeof(app_path));
#else
   fill_pathname_application_dir(app_path, sizeof(app_path));
#endif
   fill_pathname_resolve_relative(conf_path, app_path,
         FILE_PATH_MAIN_CONFIG, sizeof(conf_path));

   conf = config_file_new_from_path_to_string(conf_path);

   if (!conf)
   {
      if (fill_pathname_application_data(application_data,
            sizeof(application_data)))
      {
         fill_pathname_join_special(conf_path, application_data,
               FILE_PATH_MAIN_CONFIG, sizeof(conf_path));
         conf = config_file_new_from_path_to_string(conf_path);
      }
   }

   if (!conf)
   {
      bool saved = false;

      /* Try to create a new config file. */
      conf = config_file_new_alloc();

      if (conf)
      {
         /* Since this is a clean config file, we can
          * safely use config_save_on_exit. */
         fill_pathname_resolve_relative(conf_path, app_path,
               FILE_PATH_MAIN_CONFIG, sizeof(conf_path));
         config_set_string(conf, "config_save_on_exit", "true");
         saved = config_file_write(conf, conf_path, true);
      }

      if (!saved)
      {
         /* WARN here to make sure user has a good chance of seeing it. */
         RARCH_ERR("[Config] Failed to create new config file in: \"%s\".\n",
               conf_path);
         goto error;
      }

      RARCH_LOG("[Config] Created new config file in: \"%s\".\n", conf_path);
   }
#elif defined(OSX)
   if (!fill_pathname_application_data(application_data,
            sizeof(application_data)))
      goto error;

   /* Group config file with menu configs, remaps, etc: */
   strlcat(application_data, "/config", sizeof(application_data));

   path_mkdir(application_data);

   fill_pathname_join_special(conf_path, application_data,
         FILE_PATH_MAIN_CONFIG, sizeof(conf_path));

   if (!(conf = config_file_new_from_path_to_string(conf_path)))
   {
      bool saved = false;

      if ((conf = config_file_new_alloc()))
      {
         config_set_string(conf, "config_save_on_exit", "true");
         saved = config_file_write(conf, conf_path, true);
      }

      if (!saved)
      {
         /* WARN here to make sure user has a good chance of seeing it. */
         RARCH_ERR("[Config] Failed to create new config file in: \"%s\".\n",
               conf_path);
         goto error;
      }

      RARCH_LOG("[Config] Created new config file in: \"%s\".\n", conf_path);
   }
#elif !defined(RARCH_CONSOLE)
   bool has_application_data =
      fill_pathname_application_data(application_data,
            sizeof(application_data));

   if (has_application_data)
   {
      fill_pathname_join_special(conf_path, application_data,
            FILE_PATH_MAIN_CONFIG, sizeof(conf_path));
      RARCH_LOG("[Config] Looking for config in: \"%s\".\n", conf_path);
      conf = config_file_new_from_path_to_string(conf_path);
   }

   /* Fallback to $HOME/.retroarch.cfg. */
   if (!conf && getenv("HOME"))
   {
      fill_pathname_join_special(conf_path, getenv("HOME"),
            "." FILE_PATH_MAIN_CONFIG, sizeof(conf_path));
      RARCH_LOG("[Config] Looking for config in: \"%s\".\n", conf_path);
      conf = config_file_new_from_path_to_string(conf_path);
   }

   if (!conf && has_application_data)
   {
      char basedir[DIR_MAX_LENGTH];
      /* Try to create a new config file. */
      fill_pathname_basedir(basedir, application_data, sizeof(basedir));
      fill_pathname_join_special(conf_path, application_data,
            FILE_PATH_MAIN_CONFIG, sizeof(conf_path));

      if ((path_mkdir(basedir)))
      {
         char skeleton_conf[PATH_MAX_LENGTH];
         bool saved          = false;
         /* Build a retroarch.cfg path from the
          * global config directory (/etc). */
         fill_pathname_join_special(skeleton_conf, GLOBAL_CONFIG_DIR,
            FILE_PATH_MAIN_CONFIG, sizeof(skeleton_conf));
         if ((conf = config_file_new_from_path_to_string(skeleton_conf)))
            RARCH_LOG("[Config] Using skeleton config \"%s\" as base for a new config file.\n", skeleton_conf);
         else
            conf = config_file_new_alloc();

         if (conf)
         {
            /* Since this is a clean config file, we can
             * safely use config_save_on_exit. */
            config_set_string(conf, "config_save_on_exit", "true");
            saved = config_file_write(conf, conf_path, true);
         }

         if (!saved)
         {
            /* WARN here to make sure user has a good chance of seeing it. */
            RARCH_ERR("[Config] Failed to create new config file in: \"%s\".\n",
                  conf_path);
            goto error;
         }

         RARCH_LOG("[Config] Created new config file in: \"%s\".\n",
               conf_path);
      }
   }
#endif

   if (!conf)
      goto error;

   path_set(RARCH_PATH_CONFIG, conf_path);

   return conf;

error:
   if (conf)
      config_file_free(conf);
   return NULL;
}

#ifdef RARCH_CONSOLE
static void video_driver_load_settings(global_t *global,
      config_file_t *conf)
{
   bool               tmp_bool = false;

   CONFIG_GET_INT_BASE(conf, global,
         console.screen.gamma_correction, "gamma_correction");

   if (config_get_bool(conf, "flicker_filter_enable",
         &tmp_bool))
      global->console.flickerfilter_enable = tmp_bool;

   if (config_get_bool(conf, "soft_filter_enable",
         &tmp_bool))
      global->console.softfilter_enable = tmp_bool;

   CONFIG_GET_INT_BASE(conf, global,
         console.screen.soft_filter_index,
         "soft_filter_index");
   CONFIG_GET_INT_BASE(conf, global,
         console.screen.resolutions.current.id,
         "current_resolution_id");
   CONFIG_GET_INT_BASE(conf, global,
         console.screen.flicker_filter_index,
         "flicker_filter_index");
}
#endif

static void check_verbosity_settings(config_file_t *conf,
      settings_t *settings)
{
   unsigned tmp_uint                               = 0;
   bool tmp_bool                                   = false;

   /* Make sure log_to_file is true if 'log-file' command line argument was used. */
   if (retroarch_override_setting_is_set(RARCH_OVERRIDE_SETTING_LOG_TO_FILE, NULL))
   {
      configuration_set_bool(settings, settings->bools.log_to_file, true);
   }
   else
   {
      /* Make sure current 'log_to_file' is effective */
      if (config_get_bool(conf, "log_to_file", &tmp_bool))
         configuration_set_bool(settings, settings->bools.log_to_file, tmp_bool);
   }

   /* Set frontend log level */
   if (config_get_uint(conf, "frontend_log_level", &tmp_uint))
      verbosity_set_log_level(tmp_uint);

   /* Set verbosity according to config only if command line argument was not used. */
   if (retroarch_override_setting_is_set(RARCH_OVERRIDE_SETTING_VERBOSITY, NULL))
   {
      verbosity_enable();
   }
   else
   {
      if (config_get_bool(conf, "log_verbosity", &tmp_bool))
      {
         if (tmp_bool)
            verbosity_enable();
         else
            verbosity_disable();
      }
   }
}

/**
 * config_load:
 * @path                : path to be read from.
 * @set_defaults        : set default values first before
 *                        reading the values from the config file
 *
 * Loads a config file and reads all the values into memory.
 *
 */
static bool config_load_file(global_t *global,
      const char *path, settings_t *settings)
{
   unsigned i;
   char tmp_str[PATH_MAX_LENGTH];
   static bool first_load                          = true;
   bool without_overrides                          = false;
   unsigned msg_color                              = 0;
   char *save                                      = NULL;
   char *override_username                         = NULL;
   runloop_state_t *runloop_st                     = runloop_state_get_ptr();
   int bool_settings_size                          = sizeof(settings->bools)  / sizeof(settings->bools.placeholder);
   int float_settings_size                         = sizeof(settings->floats) / sizeof(settings->floats.placeholder);
   int int_settings_size                           = sizeof(settings->ints)   / sizeof(settings->ints.placeholder);
   int uint_settings_size                          = sizeof(settings->uints)  / sizeof(settings->uints.placeholder);
   int size_settings_size                          = sizeof(settings->sizes)  / sizeof(settings->sizes.placeholder);
   int array_settings_size                         = sizeof(settings->arrays) / sizeof(settings->arrays.placeholder);
   int path_settings_size                          = sizeof(settings->paths)  / sizeof(settings->paths.placeholder);
   struct config_bool_setting *bool_settings       = NULL;
   struct config_float_setting *float_settings     = NULL;
   struct config_int_setting *int_settings         = NULL;
   struct config_uint_setting *uint_settings       = NULL;
   struct config_size_setting *size_settings       = NULL;
   struct config_array_setting *array_settings     = NULL;
   struct config_path_setting *path_settings       = NULL;
   config_file_t *conf                             = NULL;
   uint16_t rarch_flags                            = retroarch_get_flags();

   tmp_str[0]                                      = '\0';

   /* Override config comparison must be compared to config before overrides */
   if (string_is_equal(path, "without-overrides"))
   {
      path              = path_get(RARCH_PATH_CONFIG);
      without_overrides = true;
   }

   conf = (path) ? config_file_new_from_path_to_string(path) : open_default_config_file();

#if TARGET_OS_TV
   if (!conf && path && string_is_equal(path, path_get(RARCH_PATH_CONFIG)))
   {
      /* Sometimes the OS decides it needs to reclaim disk space
       * by emptying the cache, which is the only disk space we
       * have access to, other than NSUserDefaults. */
      conf = open_userdefaults_config_file();
   }
#endif // TARGET_OS_TV

   if (!conf)
   {
      first_load = false;
      if (!path)
         return true;
      return false;
   }

   bool_settings    = populate_settings_bool  (settings, &bool_settings_size);
   float_settings   = populate_settings_float (settings, &float_settings_size);
   int_settings     = populate_settings_int   (settings, &int_settings_size);
   uint_settings    = populate_settings_uint  (settings, &uint_settings_size);
   size_settings    = populate_settings_size  (settings, &size_settings_size);
   array_settings   = populate_settings_array (settings, &array_settings_size);
   path_settings    = populate_settings_path  (settings, &path_settings_size);

   /* Initialize verbosity settings */
   check_verbosity_settings(conf, settings);

   if (!first_load)
   {
      if (!path)
         RARCH_LOG("[Config] Loading default config.\n");
      else
         RARCH_LOG("[Config] Loading config: \"%s\".\n", path);
   }

   if (!path_is_empty(RARCH_PATH_CONFIG_APPEND))
   {
      /* Don't destroy append_config_path, store in temporary
       * variable. */
      char tmp_append_path[PATH_MAX_LENGTH];
      const char *extra_path = NULL;
      strlcpy(tmp_append_path, path_get(RARCH_PATH_CONFIG_APPEND),
            sizeof(tmp_append_path));
      extra_path = strtok_r(tmp_append_path, "|", &save);

      while (extra_path)
      {
         bool result = config_append_file(conf, extra_path);

         if (!first_load)
         {
            RARCH_LOG("[Config] Appending config: \"%s\".\n", extra_path);

            if (!result)
               RARCH_ERR("[Config] Failed to append config: \"%s\".\n", extra_path);
         }
         extra_path = strtok_r(NULL, "|", &save);
      }

      /* Re-check verbosity settings */
      check_verbosity_settings(conf, settings);
   }

   if (!path_is_empty(RARCH_PATH_CONFIG_OVERRIDE) && !without_overrides)
   {
      /* Don't destroy append_config_path, store in temporary
       * variable. */
      char tmp_append_path[PATH_MAX_LENGTH];
      const char *extra_path = NULL;
#ifdef HAVE_OVERLAY
      char old_overlay_path[PATH_MAX_LENGTH], new_overlay_path[PATH_MAX_LENGTH];
      config_get_path(conf, "input_overlay", old_overlay_path, sizeof(old_overlay_path));
#endif
      strlcpy(tmp_append_path, path_get(RARCH_PATH_CONFIG_OVERRIDE),
            sizeof(tmp_append_path));
      extra_path = strtok_r(tmp_append_path, "|", &save);

      while (extra_path)
      {
         bool result = config_append_file(conf, extra_path);

         if (!first_load)
         {
            RARCH_LOG("[Config] Appending override config: \"%s\".\n", extra_path);

            if (!result)
               RARCH_ERR("[Config] Failed to append override config: \"%s\".\n", extra_path);
         }
         extra_path = strtok_r(NULL, "|", &save);
      }

      /* Re-check verbosity settings */
      check_verbosity_settings(conf, settings);
#ifdef HAVE_OVERLAY
      config_get_path(conf, "input_overlay", new_overlay_path, sizeof(new_overlay_path));
      if (!string_is_equal(old_overlay_path, new_overlay_path))
         retroarch_override_setting_set(RARCH_OVERRIDE_SETTING_OVERLAY_PRESET, NULL);
#endif
   }

   /* Special case for perfcnt_enable */
   {
      bool tmp = false;
      config_get_bool(conf, "perfcnt_enable", &tmp);
      if (tmp)
         retroarch_ctl(RARCH_CTL_SET_PERFCNT_ENABLE, NULL);
   }

   /* Overrides */

   if (rarch_flags & RARCH_FLAGS_HAS_SET_USERNAME)
      override_username = strdup(settings->paths.username);

   /* Boolean settings */

   for (i = 0; i < (unsigned)bool_settings_size; i++)
   {
      bool tmp = false;
      if (config_get_bool(conf, bool_settings[i].ident, &tmp))
         *bool_settings[i].ptr = tmp;
   }

#ifdef HAVE_NETWORKGAMEPAD
   {
      char tmp[64];
      size_t _len = strlcpy(tmp, "network_remote_enable_user_p", sizeof(tmp));
      for (i = 0; i < MAX_USERS; i++)
      {
         bool tmp_bool = false;
         snprintf(tmp + _len, sizeof(tmp) - _len, "%u", i + 1);
         if (config_get_bool(conf, tmp, &tmp_bool))
            configuration_set_bool(settings,
                  settings->bools.network_remote_enable_user[i], tmp_bool);
      }
   }
#endif // HAVE_NETWORKGAMEPAD

   /* Integer settings */

   for (i = 0; i < (unsigned)int_settings_size; i++)
   {
      int tmp = 0;
      if (config_get_int(conf, int_settings[i].ident, &tmp))
         *int_settings[i].ptr = tmp;
   }

   for (i = 0; i < (unsigned)uint_settings_size; i++)
   {
      int tmp = 0;
      if (config_get_int(conf, uint_settings[i].ident, &tmp))
         *uint_settings[i].ptr = tmp;
   }

   for (i = 0; i < (unsigned)size_settings_size; i++)
   {
      size_t tmp = 0;
      if (config_get_size_t(conf, size_settings[i].ident, &tmp))
         *size_settings[i].ptr = tmp;
      /* Special case for rewind_buffer_size - need to convert
       * low values to what they were
       * intended to be based on the default value in config.def.h
       * If the value is less than 10000 then multiple by 1MB because if
       * the retroarch.cfg
       * file contains rewind_buffer_size = "100",
       * then that ultimately gets interpreted as
       * 100MB, so ensure the internal values represent that.*/
      if (string_is_equal(size_settings[i].ident, "rewind_buffer_size"))
         if (*size_settings[i].ptr < 10000)
            *size_settings[i].ptr  = *size_settings[i].ptr * 1024 * 1024;
   }

   {
      char prefix[64];
      size_t _len    = strlcpy(prefix, "input_player", sizeof(prefix));
      size_t old_len = _len;
      for (i = 0; i < MAX_USERS; i++)
      {
         _len  = old_len;
         _len += snprintf(prefix + _len, sizeof(prefix) - _len, "%u", i + 1);

         strlcpy(prefix + _len, "_mouse_index", sizeof(prefix) - _len);
         CONFIG_GET_INT_BASE(conf, settings, uints.input_mouse_index[i], prefix);

         strlcpy(prefix + _len, "_joypad_index", sizeof(prefix) - _len);
         CONFIG_GET_INT_BASE(conf, settings, uints.input_joypad_index[i], prefix);

         strlcpy(prefix + _len, "_analog_dpad_mode", sizeof(prefix) - _len);
         CONFIG_GET_INT_BASE(conf, settings, uints.input_analog_dpad_mode[i], prefix);

         strlcpy(prefix + _len, "_device_reservation_type", sizeof(prefix) - _len);
         CONFIG_GET_INT_BASE(conf, settings, uints.input_device_reservation_type[i], prefix);
      }
   }

   /* LED map for use by the led driver */
   for (i = 0; i < MAX_LEDS; i++)
   {
      char buf[64];

      buf[0] = '\0';

      snprintf(buf, sizeof(buf), "led%u_map", i + 1);

      /* TODO/FIXME - change of sign - led_map is unsigned */
      settings->uints.led_map[i] = -1;

      CONFIG_GET_INT_BASE(conf, settings, uints.led_map[i], buf);
   }

   /* Hexadecimal settings  */

   if (config_get_hex(conf, "video_message_color", &msg_color))
   {
      settings->floats.video_msg_color_r = ((msg_color >> 16) & 0xff) / 255.0f;
      settings->floats.video_msg_color_g = ((msg_color >>  8) & 0xff) / 255.0f;
      settings->floats.video_msg_color_b = ((msg_color >>  0) & 0xff) / 255.0f;
   }

   /* Float settings */
   for (i = 0; i < (unsigned)float_settings_size; i++)
   {
      float tmp = 0.0f;
      if (config_get_float(conf, float_settings[i].ident, &tmp))
         *float_settings[i].ptr = tmp;
   }

   /* Array settings  */
   for (i = 0; i < (unsigned)array_settings_size; i++)
   {
      if (array_settings[i].flags & CFG_BOOL_FLG_HANDLE)
         config_get_array(conf, array_settings[i].ident,
               array_settings[i].ptr, PATH_MAX_LENGTH);
   }

   /* Path settings  */
   for (i = 0; i < (unsigned)path_settings_size; i++)
   {
      if (!(path_settings[i].flags & CFG_BOOL_FLG_HANDLE))
         continue;

      if (config_get_path(conf, path_settings[i].ident, tmp_str, sizeof(tmp_str)))
         strlcpy(path_settings[i].ptr, tmp_str, PATH_MAX_LENGTH);
   }

#if !IOS
   if (config_get_path(conf, "libretro_directory", tmp_str, sizeof(tmp_str)))
      configuration_set_string(settings,
            settings->paths.directory_libretro, tmp_str);
#endif

#ifdef RARCH_CONSOLE
   if (conf)
      video_driver_load_settings(global, conf);
#endif

   if (     (rarch_flags & RARCH_FLAGS_HAS_SET_USERNAME)
         && (override_username))
   {
      configuration_set_string(settings,
            settings->paths.username,
            override_username);
      free(override_username);
   }

   if (settings->uints.video_hard_sync_frames > MAXIMUM_HARD_SYNC_FRAMES)
      settings->uints.video_hard_sync_frames = MAXIMUM_HARD_SYNC_FRAMES;

   if (settings->uints.video_max_swapchain_images < MINIMUM_MAX_SWAPCHAIN_IMAGES)
      settings->uints.video_max_swapchain_images = MINIMUM_MAX_SWAPCHAIN_IMAGES;
   if (settings->uints.video_max_swapchain_images > MAXIMUM_MAX_SWAPCHAIN_IMAGES)
      settings->uints.video_max_swapchain_images = MAXIMUM_MAX_SWAPCHAIN_IMAGES;

   if (settings->uints.video_frame_delay > MAXIMUM_FRAME_DELAY)
      settings->uints.video_frame_delay = MAXIMUM_FRAME_DELAY;

   settings->uints.video_swap_interval = MAX(settings->uints.video_swap_interval, 0);
   settings->uints.video_swap_interval = MIN(settings->uints.video_swap_interval, 4);

   audio_set_float(AUDIO_ACTION_VOLUME_GAIN, settings->floats.audio_volume);
#ifdef HAVE_AUDIOMIXER
   audio_set_float(AUDIO_ACTION_MIXER_VOLUME_GAIN, settings->floats.audio_mixer_volume);
#endif

#ifdef HAVE_WASAPI
   {
      /* Migrate from old deprecated negative value */
      int wasapi_sh_buffer_length = settings->uints.audio_wasapi_sh_buffer_length;
      if (wasapi_sh_buffer_length < 0)
         settings->uints.audio_wasapi_sh_buffer_length = 0;
   }
#endif // HAVE_WASAPI

   /* MIDI fallback for old OFF-string */
   if (string_is_equal(settings->arrays.midi_input, "Off"))
      configuration_set_string(settings,
            settings->arrays.midi_input,
            DEFAULT_MIDI_INPUT);
   if (string_is_equal(settings->arrays.midi_output, "Off"))
      configuration_set_string(settings,
            settings->arrays.midi_output,
            DEFAULT_MIDI_OUTPUT);

   /* Built-in playlist default legacy path migration */
   {
      const char *path_config = path_get(RARCH_PATH_CONFIG);
      char new_path[PATH_MAX_LENGTH];

      fill_pathname_join_special(
            new_path,
            settings->paths.directory_playlist,
            FILE_PATH_BUILTIN,
            sizeof(new_path));

      if (!path_is_directory(new_path))
         path_mkdir(new_path);
   }

   if (string_is_equal(settings->paths.directory_playlist, "default"))
      *settings->paths.directory_playlist = '\0';
#ifdef HAVE_OVERLAY
   if (string_is_equal(settings->paths.directory_overlay, "default"))
      *settings->paths.directory_overlay = '\0';
   if (string_is_equal(settings->paths.directory_osk_overlay, "default"))
      *settings->paths.directory_osk_overlay = '\0';
#endif // HAVE_OVERLAY

   /* Log directory is a special case, since it must contain
    * a valid path as soon as possible - if config file
    * value is 'default' must copy g_defaults.dirs[DEFAULT_DIR_LOGS]
    * directly... */
   if (string_is_equal(settings->paths.log_dir, "default"))
   {
      if (!string_is_empty(g_defaults.dirs[DEFAULT_DIR_LOGS]))
      {
         configuration_set_string(settings,
               settings->paths.log_dir,
               g_defaults.dirs[DEFAULT_DIR_LOGS]);
      }
      else
         *settings->paths.log_dir = '\0';
   }

   if (settings->floats.slowmotion_ratio < 1.0f)
      configuration_set_float(settings, settings->floats.slowmotion_ratio, 1.0f);

   /* Sanitize fastforward_ratio value - previously range was -1
    * and up (with 0 being skipped) */
   if (settings->floats.fastforward_ratio < 0.0f)
      configuration_set_float(settings, settings->floats.fastforward_ratio, 0.0f);

#ifdef HAVE_CHEEVOS
   if (!string_is_empty(settings->arrays.cheevos_leaderboards_enable))
   {
      if (string_is_equal(settings->arrays.cheevos_leaderboards_enable, "true"))
      {
         settings->bools.cheevos_visibility_lboard_start    = true;
         settings->bools.cheevos_visibility_lboard_submit   = true;
         settings->bools.cheevos_visibility_lboard_cancel   = true;
         settings->bools.cheevos_visibility_lboard_trackers = true;
      }
      else if (string_is_equal(settings->arrays.cheevos_leaderboards_enable, "trackers"))
      {
         settings->bools.cheevos_visibility_lboard_start    = false;
         settings->bools.cheevos_visibility_lboard_submit   = true;
         settings->bools.cheevos_visibility_lboard_cancel   = false;
         settings->bools.cheevos_visibility_lboard_trackers = true;
      }
      else if (string_is_equal(settings->arrays.cheevos_leaderboards_enable, "notifications"))
      {
         settings->bools.cheevos_visibility_lboard_start    = true;
         settings->bools.cheevos_visibility_lboard_submit   = true;
         settings->bools.cheevos_visibility_lboard_cancel   = true;
         settings->bools.cheevos_visibility_lboard_trackers = false;
      }
      else
      {
         settings->bools.cheevos_visibility_lboard_start    = false;
         settings->bools.cheevos_visibility_lboard_submit   = false;
         settings->bools.cheevos_visibility_lboard_cancel   = false;
         settings->bools.cheevos_visibility_lboard_trackers = false;
      }
      settings->arrays.cheevos_leaderboards_enable[0]       = '\0';
   }
#endif // HAVE_CHEEVOS

#ifdef HAVE_LAKKA
   configuration_set_bool(settings,
         settings->bools.ssh_enable, filestream_exists(LAKKA_SSH_PATH));
   configuration_set_bool(settings,
         settings->bools.samba_enable, filestream_exists(LAKKA_SAMBA_PATH));
   configuration_set_bool(settings,
         settings->bools.bluetooth_enable, filestream_exists(LAKKA_BLUETOOTH_PATH));
#endif // HAVE_LAKKA

   if (    !retroarch_override_setting_is_set(RARCH_OVERRIDE_SETTING_SAVE_PATH, NULL)
         && config_get_path(conf, "savefile_directory", tmp_str, sizeof(tmp_str)))
   {
      if (string_is_equal(tmp_str, "default"))
         dir_set(RARCH_DIR_SAVEFILE, g_defaults.dirs[DEFAULT_DIR_SRAM]);
      else if (path_is_directory(tmp_str))
      {
         dir_set(RARCH_DIR_SAVEFILE, tmp_str);

         strlcpy(runloop_st->name.savefile, tmp_str,
               sizeof(runloop_st->name.savefile));
         fill_pathname_dir(runloop_st->name.savefile,
               path_get(RARCH_PATH_BASENAME),
               FILE_PATH_SRM_EXTENSION,
               sizeof(runloop_st->name.savefile));
      }
      else
         RARCH_WARN("[Config] \"savefile_directory\" is not a directory, ignoring...\n");
   }

   if (    !retroarch_override_setting_is_set(RARCH_OVERRIDE_SETTING_STATE_PATH, NULL)
         && config_get_path(conf, "savestate_directory", tmp_str, sizeof(tmp_str)))
   {
      if (string_is_equal(tmp_str, "default"))
         dir_set(RARCH_DIR_SAVESTATE, g_defaults.dirs[DEFAULT_DIR_SAVESTATE]);
      else if (path_is_directory(tmp_str))
      {
         dir_set(RARCH_DIR_SAVESTATE, tmp_str);

         strlcpy(runloop_st->name.savestate, tmp_str,
               sizeof(runloop_st->name.savestate));
         fill_pathname_dir(runloop_st->name.savestate,
               path_get(RARCH_PATH_BASENAME),
               ".state",
               sizeof(runloop_st->name.savestate));
         strlcpy(runloop_st->name.replay, tmp_str,
               sizeof(runloop_st->name.replay));
         fill_pathname_dir(runloop_st->name.replay,
               path_get(RARCH_PATH_BASENAME),
               ".replay",
               sizeof(runloop_st->name.replay));
      }
      else
         RARCH_WARN("[Config] \"savestate_directory\" is not a directory, ignoring...\n");
   }

   config_read_keybinds_conf(conf);

#ifdef HAVE_LIBNX
   /* Apply initial clocks */
   extern void libnx_apply_overclock();
   libnx_apply_overclock();
#endif

#ifdef HAVE_LAKKA_SWITCH
   FILE* f = fopen(SWITCH_OC_TOGGLE_PATH, "w");
   if (settings->bools.switch_oc)
      fprintf(f, "1\n");
   else
      fprintf(f, "0\n");
   fclose(f);

   if (settings->bools.switch_cec)
   {
      FILE* f = fopen(SWITCH_CEC_TOGGLE_PATH, "w");
      fprintf(f, "\n");
      fclose(f);
   }
   else
      filestream_delete(SWITCH_CEC_TOGGLE_PATH);

   if (settings->bools.bluetooth_ertm_disable)
   {
      FILE* f = fopen(BLUETOOTH_ERTM_TOGGLE_PATH, "w");
      fprintf(f, "1\n");
      fclose(f);
   }
   else
   {
      FILE* f = fopen(BLUETOOTH_ERTM_TOGGLE_PATH, "w");
      fprintf(f, "0\n");
      fclose(f);
   }
#endif // HAVE_LAKKA_SWITCH

   frontend_driver_set_sustained_performance_mode(settings->bools.sustained_performance_mode);
   recording_driver_update_streaming_url();

   if (!(bool)RHMAP_HAS_STR(conf->entries_map, "user_language"))
      msg_hash_set_uint(MSG_HASH_USER_LANGUAGE, frontend_driver_get_user_language());

   if (frontend_driver_has_gamemode() &&
         !frontend_driver_set_gamemode(settings->bools.gamemode_enable) &&
         settings->bools.gamemode_enable)
   {
      RARCH_WARN("[Config] GameMode unsupported - disabling...\n");
      configuration_set_bool(settings,
            settings->bools.gamemode_enable, false);
   }

   if (conf)
      config_file_free(conf);
   if (bool_settings)
      free(bool_settings);
   if (int_settings)
      free(int_settings);
   if (uint_settings)
      free(uint_settings);
   if (float_settings)
      free(float_settings);
   if (array_settings)
      free(array_settings);
   if (path_settings)
      free(path_settings);
   if (size_settings)
      free(size_settings);
   first_load = false;
   return true;
}

/**
 * config_load_override:
 *
 * Tries to append game-specific and core-specific configuration.
 * These settings will always have precedence, thus this feature
 * can be used to enforce overrides.
 *
 * This function only has an effect if a game-specific or core-specific
 * configuration file exists at respective locations.
 *
 * core-specific: $CONFIG_DIR/$CORE_NAME/$CORE_NAME.cfg
 * fallback:      $CURRENT_CFG_LOCATION/$CORE_NAME/$CORE_NAME.cfg
 *
 * game-specific: $CONFIG_DIR/$CORE_NAME/$ROM_NAME.cfg
 * fallback:      $CURRENT_CFG_LOCATION/$CORE_NAME/$GAME_NAME.cfg
 *
 * Returns: false if there was an error or no action was performed.
 *
 */
bool config_load_override(void *data)
{
   char core_path[PATH_MAX_LENGTH];
   char game_path[PATH_MAX_LENGTH];
   char content_path[PATH_MAX_LENGTH];
   char config_directory[DIR_MAX_LENGTH];
   bool should_append                     = false;
   bool show_notification                 = true;
   rarch_system_info_t *sys_info          = (rarch_system_info_t*)data;
   const char *core_name                  = sys_info
      ? sys_info->info.library_name : NULL;
   const char *rarch_path_basename        = path_get(RARCH_PATH_BASENAME);
   const char *game_name                  = NULL;
   settings_t *settings                   = config_st;
   bool has_content                       = !string_is_empty(rarch_path_basename);

   core_path[0]        = '\0';
   game_path[0]        = '\0';
   content_path[0]     = '\0';
   config_directory[0] = '\0';

   path_clear(RARCH_PATH_CONFIG_OVERRIDE);

   /* Cannot load an override if we have no core */
   if (string_is_empty(core_name))
      return false;

   /* Get base config directory */
   fill_pathname_application_special(config_directory,
         sizeof(config_directory),
         APPLICATION_SPECIAL_DIRECTORY_CONFIG);

   /* Concatenate strings into full paths for core_path,
    * game_path, content_path */
   if (has_content)
   {
      char content_dir_name[DIR_MAX_LENGTH];
      fill_pathname_parent_dir_name(content_dir_name,
            rarch_path_basename, sizeof(content_dir_name));
      game_name = path_basename_nocompression(rarch_path_basename);

      fill_pathname_join_special_ext(game_path,
            config_directory, core_name,
            game_name,
            ".cfg",
            sizeof(game_path));

      fill_pathname_join_special_ext(content_path,
         config_directory, core_name,
         content_dir_name,
         ".cfg",
         sizeof(content_path));
   }

   fill_pathname_join_special_ext(core_path,
         config_directory, core_name,
         core_name,
         ".cfg",
         sizeof(core_path));

   /* Prevent "--appendconfig" from being ignored */
   if (!path_is_empty(RARCH_PATH_CONFIG_APPEND))
   {
      should_append     = true;
      show_notification = false;
   }

   /* per-core overrides */
   /* Create a new config file from core_path */
   if (path_is_valid(core_path))
   {
      char log_core_path[PATH_MAX_LENGTH] = { 0 };
      RARCH_LOG("[Override] Core-specific overrides found at \"%s\".\n",
            shorten_path_for_log(core_path, log_core_path, sizeof(log_core_path)));

      if (should_append && !string_is_empty(path_get(RARCH_PATH_CONFIG_OVERRIDE)))
      {
         char tmp_path[PATH_MAX_LENGTH];
         size_t _len      = strlcpy(tmp_path,
               path_get(RARCH_PATH_CONFIG_OVERRIDE),
               sizeof(tmp_path) - 2);
         tmp_path[  _len] = '|';
         tmp_path[++_len] = '\0';
         strlcpy(tmp_path + _len, core_path, sizeof(tmp_path) - _len);
         path_set(RARCH_PATH_CONFIG_OVERRIDE, tmp_path);
         RARCH_LOG("[Override] Core-specific overrides stacking on top of previous overrides.\n");
      }
      else
         path_set(RARCH_PATH_CONFIG_OVERRIDE, core_path);

      should_append     = true;
      show_notification = true;
   }

   if (has_content)
   {
      /* per-content-dir overrides */
      /* Create a new config file from content_path */
      if (path_is_valid(content_path))
      {
         char log_content_path[PATH_MAX_LENGTH] =  { 0 };
         RARCH_LOG("[Override] Content dir-specific overrides found at \"%s\".\n",
               shorten_path_for_log(content_path, log_content_path, sizeof(log_content_path)));

         if (should_append && !string_is_empty(path_get(RARCH_PATH_CONFIG_OVERRIDE)))
         {
            char tmp_path[PATH_MAX_LENGTH];
            size_t _len      = strlcpy(tmp_path,
                  path_get(RARCH_PATH_CONFIG_OVERRIDE),
                  sizeof(tmp_path) - 2);
            tmp_path[  _len] = '|';
            tmp_path[++_len] = '\0';
            strlcpy(tmp_path + _len, content_path, sizeof(tmp_path) - _len);
            path_set(RARCH_PATH_CONFIG_OVERRIDE, tmp_path);
            RARCH_LOG("[Override] Content dir-specific overrides stacking on top of previous overrides.\n");
         }
         else
            path_set(RARCH_PATH_CONFIG_OVERRIDE, content_path);

         should_append     = true;
         show_notification = true;
      }

      /* per-game overrides */
      /* Create a new config file from game_path */
      if (path_is_valid(game_path))
      {
         char log_game_path[PATH_MAX_LENGTH] = { 0 };
         RARCH_LOG("[Override] Game-specific overrides found at \"%s\".\n",
               shorten_path_for_log(game_path, log_game_path, sizeof(log_game_path)));

         if (should_append && !string_is_empty(path_get(RARCH_PATH_CONFIG_OVERRIDE)))
         {
            char tmp_path[PATH_MAX_LENGTH];
            size_t _len      = strlcpy(tmp_path,
                  path_get(RARCH_PATH_CONFIG_OVERRIDE),
                  sizeof(tmp_path) - 2);
            tmp_path[  _len] = '|';
            tmp_path[++_len] = '\0';
            strlcpy(tmp_path + _len, game_path, sizeof(tmp_path) - _len);
            path_set(RARCH_PATH_CONFIG_OVERRIDE, tmp_path);
            RARCH_LOG("[Override] Game-specific overrides stacking on top of previous overrides.\n");
         }
         else
            path_set(RARCH_PATH_CONFIG_OVERRIDE, game_path);

         should_append     = true;
         show_notification = true;
      }
   }

   if (!should_append)
      return false;

   /* Re-load the configuration with any overrides
    * that might have been found */

   /* Toggle has_save_path to false so it resets */
   retroarch_override_setting_unset(RARCH_OVERRIDE_SETTING_STATE_PATH, NULL);
   retroarch_override_setting_unset(RARCH_OVERRIDE_SETTING_SAVE_PATH, NULL);

   if (!config_load_file(global_get_ptr(),
            path_get(RARCH_PATH_CONFIG), settings))
      return false;

   if (settings->bools.notification_show_config_override_load
         && show_notification)
   {
      char msg[128];
      size_t _len = strlcpy(msg, msg_hash_to_str(MSG_CONFIG_OVERRIDE_LOADED), sizeof(msg));
      runloop_msg_queue_push(msg, _len, 2, 100, false, NULL,
            MESSAGE_QUEUE_ICON_DEFAULT, MESSAGE_QUEUE_CATEGORY_INFO);
   }

   /* Reset save paths. */
   retroarch_override_setting_set(RARCH_OVERRIDE_SETTING_STATE_PATH, NULL);
   retroarch_override_setting_set(RARCH_OVERRIDE_SETTING_SAVE_PATH, NULL);

   if (!string_is_empty(path_get(RARCH_PATH_CONFIG_OVERRIDE)))
      runloop_state_get_ptr()->flags |=  RUNLOOP_FLAG_OVERRIDES_ACTIVE;
   else
      runloop_state_get_ptr()->flags &= ~RUNLOOP_FLAG_OVERRIDES_ACTIVE;

   return true;
}

bool config_load_override_file(const char *config_path)
{
   settings_t *settings   = config_st;

   path_clear(RARCH_PATH_CONFIG_OVERRIDE);

   if (!path_is_valid(config_path))
      return false;

   path_set(RARCH_PATH_CONFIG_OVERRIDE, config_path);

   /* Re-load the configuration with any overrides
    * that might have been found */

   /* Toggle has_save_path to false so it resets */
   retroarch_override_setting_unset(RARCH_OVERRIDE_SETTING_STATE_PATH, NULL);
   retroarch_override_setting_unset(RARCH_OVERRIDE_SETTING_SAVE_PATH, NULL);

   if (!config_load_file(global_get_ptr(),
            path_get(RARCH_PATH_CONFIG), settings))
      return false;

   if (settings->bools.notification_show_config_override_load)
   {
      char msg[128];
      size_t _len = strlcpy(msg, msg_hash_to_str(MSG_CONFIG_OVERRIDE_LOADED), sizeof(msg));
      runloop_msg_queue_push(msg, _len, 2, 100, false, NULL,
            MESSAGE_QUEUE_ICON_DEFAULT, MESSAGE_QUEUE_CATEGORY_INFO);
   }

   /* Reset save paths. */
   retroarch_override_setting_set(RARCH_OVERRIDE_SETTING_STATE_PATH, NULL);
   retroarch_override_setting_set(RARCH_OVERRIDE_SETTING_SAVE_PATH, NULL);

   if (!string_is_empty(path_get(RARCH_PATH_CONFIG_OVERRIDE)))
      runloop_state_get_ptr()->flags |=  RUNLOOP_FLAG_OVERRIDES_ACTIVE;
   else
      runloop_state_get_ptr()->flags &= ~RUNLOOP_FLAG_OVERRIDES_ACTIVE;

   return true;
}

/**
 * config_unload_override:
 *
 * Unloads configuration overrides if overrides are active.
 *
 *
 * Returns: false if there was an error.
 */
bool config_unload_override(void)
{
   settings_t *settings        = config_st;
   runloop_state_t *runloop_st = runloop_state_get_ptr();
   bool fullscreen_prev        = settings->bools.video_fullscreen;

   runloop_st->flags &= ~RUNLOOP_FLAG_OVERRIDES_ACTIVE;
   path_clear(RARCH_PATH_CONFIG_OVERRIDE);

   /* Toggle has_save_path to false so it resets */
   retroarch_override_setting_unset(RARCH_OVERRIDE_SETTING_STATE_PATH, NULL);
   retroarch_override_setting_unset(RARCH_OVERRIDE_SETTING_SAVE_PATH, NULL);

   if (!config_load_file(global_get_ptr(),
            path_get(RARCH_PATH_CONFIG), config_st))
      return false;

   if (settings->bools.video_fullscreen != fullscreen_prev)
   {
      /* This is for 'win32_common.c', so we don't save
       * fullscreen size and position if we're switching
       * back to windowed mode.
       * Might be useful for other devices as well? */
      if (      settings->bools.video_window_save_positions
            && !settings->bools.video_fullscreen)
         settings->flags |= SETTINGS_FLG_SKIP_WINDOW_POSITIONS;

      if (runloop_st->flags & RUNLOOP_FLAG_CORE_RUNNING)
         command_event(CMD_EVENT_REINIT, NULL);
   }

   /* Turbo fire settings must be reloaded from remap */
   if (settings->bools.auto_remaps_enable)
      config_load_remap(settings->paths.directory_input_remapping, &runloop_st->system);

   RARCH_LOG("[Override] Configuration overrides unloaded, original configuration restored.\n");

   /* Reset save paths */
   retroarch_override_setting_set(RARCH_OVERRIDE_SETTING_STATE_PATH, NULL);
   retroarch_override_setting_set(RARCH_OVERRIDE_SETTING_SAVE_PATH, NULL);

   return true;
}

/**
 * config_load_remap:
 *
 * Tries to append game-specific and core-specific remap files.
 *
 * This function only has an effect if a game-specific or core-specific
 * configuration file exists at respective locations.
 *
 * core-specific: $REMAP_DIR/$CORE_NAME/$CORE_NAME.cfg
 * game-specific: $REMAP_DIR/$CORE_NAME/$GAME_NAME.cfg
 *
 * Returns: false if there was an error or no action was performed.
 */
bool config_load_remap(const char *directory_input_remapping,
      void *data)
{
   /* final path for core-specific configuration (prefix+suffix) */
   char core_path[PATH_MAX_LENGTH];
   /* final path for game-specific configuration (prefix+suffix) */
   char game_path[PATH_MAX_LENGTH];
   /* final path for content-dir-specific configuration (prefix+suffix) */
   char content_path[PATH_MAX_LENGTH];
   char remap_path[PATH_MAX_LENGTH];

   config_file_t *new_conf                = NULL;
   rarch_system_info_t *sys_info          = (rarch_system_info_t*)data;
   const char *core_name                  = sys_info ? sys_info->info.library_name : NULL;
   const char *rarch_path_basename        = path_get(RARCH_PATH_BASENAME);
   enum msg_hash_enums msg_remap_loaded   = MSG_GAME_REMAP_FILE_LOADED;
   settings_t *settings                   = config_st;
   bool notification_show_remap_load      = settings->bools.notification_show_remap_load;
   unsigned joypad_port                   = settings->uints.input_joypad_index[0];
   const char *inp_dev_name               = input_config_get_device_display_name(joypad_port);
   bool sort_remaps_by_controller         = settings->bools.input_remap_sort_by_controller_enable;

   /* > Cannot load remaps if we have no core
    * > Cannot load remaps if remap directory is unset */
   if (   string_is_empty(core_name)
       || string_is_empty(directory_input_remapping))
      return false;

   game_path[0]        = '\0';
   content_path[0]     = '\0';

   if (   sort_remaps_by_controller
       && !string_is_empty(inp_dev_name)
       )
   {
      /* Ensure directory does not contain special chars */
      const char *inp_dev_dir = sanitize_path_part(
            inp_dev_name, strlen(inp_dev_name));
      /*  Build the new path with the controller name */
      size_t _len = strlcpy(remap_path, core_name, sizeof(remap_path));
      _len += strlcpy(remap_path + _len, PATH_DEFAULT_SLASH(),
            sizeof(remap_path) - _len);
      _len += strlcpy(remap_path + _len, inp_dev_dir,
            sizeof(remap_path) - _len);
      /* Deallocate as we no longer this */
      free((char*)inp_dev_dir);
      inp_dev_dir = NULL;
   }
   else /* We're not using controller path, just use core name */
      strlcpy(remap_path, core_name, sizeof(remap_path));

   if (!string_is_empty(rarch_path_basename))
   {
      char content_dir_name[DIR_MAX_LENGTH];

      fill_pathname_join_special_ext(game_path,
            directory_input_remapping, remap_path,
            path_basename_nocompression(rarch_path_basename),
            FILE_PATH_REMAP_EXTENSION,
            sizeof(game_path));

      /* If a game remap file exists, load it. */
      if ((new_conf = config_file_new_from_path_to_string(game_path)))
      {
         bool ret = input_remapping_load_file(new_conf, game_path);
         config_file_free(new_conf);
         new_conf = NULL;
         RARCH_LOG("[Remap] Game-specific remap found at \"%s\".\n", game_path);
         if (ret)
         {
            retroarch_ctl(RARCH_CTL_SET_REMAPS_GAME_ACTIVE, NULL);
            /* msg_remap_loaded is set to MSG_GAME_REMAP_FILE_LOADED
             * by default - no need to change it here */
            goto success;
         }
      }

      fill_pathname_parent_dir_name(content_dir_name,
            rarch_path_basename, sizeof(content_dir_name));

      fill_pathname_join_special_ext(content_path,
            directory_input_remapping, remap_path,
            content_dir_name,
            FILE_PATH_REMAP_EXTENSION,
            sizeof(content_path));

      /* If a content-dir remap file exists, load it. */
      if ((new_conf = config_file_new_from_path_to_string(content_path)))
      {
         char log_content_path[PATH_MAX_LENGTH] = { 0 };
         bool ret = input_remapping_load_file(new_conf, content_path);
         config_file_free(new_conf);
         new_conf = NULL;
         RARCH_LOG("[Remap] Content-dir-specific remap found at \"%s\".\n", shorten_path_for_log(content_path, log_content_path, sizeof(log_content_path)));
         if (ret)
         {
            retroarch_ctl(RARCH_CTL_SET_REMAPS_CONTENT_DIR_ACTIVE, NULL);
            msg_remap_loaded = MSG_DIRECTORY_REMAP_FILE_LOADED;
            goto success;
         }
      }
   }

   fill_pathname_join_special_ext(core_path,
         directory_input_remapping, remap_path,
         core_name,
         FILE_PATH_REMAP_EXTENSION,
         sizeof(core_path));

   /* If a core remap file exists, load it. */
   if ((new_conf = config_file_new_from_path_to_string(core_path)))
   {
      char log_core_path[PATH_MAX_LENGTH] = { 0 };
      bool ret = input_remapping_load_file(new_conf, core_path);
      config_file_free(new_conf);
      new_conf = NULL;
      RARCH_LOG("[Remap] Core-specific remap found at \"%s\".\n", shorten_path_for_log(core_path, log_core_path, sizeof(log_core_path)));
      if (ret)
      {
         retroarch_ctl(RARCH_CTL_SET_REMAPS_CORE_ACTIVE, NULL);
         msg_remap_loaded = MSG_CORE_REMAP_FILE_LOADED;
         goto success;
      }
   }

   if (new_conf)
      config_file_free(new_conf);
   new_conf = NULL;

   return false;

success:
   if (notification_show_remap_load)
   {
      char msg[128];
      size_t _len = strlcpy(msg, msg_hash_to_str(msg_remap_loaded), sizeof(msg));
      runloop_msg_queue_push(msg, _len, 2, 100, false, NULL,
            MESSAGE_QUEUE_ICON_DEFAULT, MESSAGE_QUEUE_CATEGORY_INFO);
   }
   return true;
}

/**
 * config_parse_file:
 *
 * Loads a config file and reads all the values into memory.
 *
 */
static void config_parse_file(global_t *global)
{
   const char *config_path = path_get(RARCH_PATH_CONFIG);

   if (!config_load_file(global, config_path, config_st))
   {
      char log_config_path[PATH_MAX_LENGTH] = { 0 };
      shorten_path_for_log(config_path, log_config_path, sizeof(log_config_path));
      RARCH_LOG("[Config] main.cfg not found, creating: \"%s\".\n", log_config_path);
      config_save_file(config_path);
   }
}

static void video_driver_save_settings(global_t *global, config_file_t *conf)
{
   config_set_int(conf, "gamma_correction",
         global->console.screen.gamma_correction);
   config_set_string(conf, "flicker_filter_enable",
           global->console.flickerfilter_enable
         ? "true"
         : "false");
   config_set_string(conf, "soft_filter_enable",
           global->console.softfilter_enable
         ? "true"
         : "false");

   config_set_int(conf, "soft_filter_index",
         global->console.screen.soft_filter_index);
   config_set_int(conf, "current_resolution_id",
         global->console.screen.resolutions.current.id);
   config_set_int(conf, "flicker_filter_index",
         global->console.screen.flicker_filter_index);
}

static void save_keybind_hat(config_file_t *conf, const char *key,
      const struct retro_keybind *bind)
{
   size_t _len;
   char s[16];
   s[0]      = '\0';
   _len      = snprintf(s, sizeof(s), "h%u", GET_HAT(bind->joykey));

   switch (GET_HAT_DIR(bind->joykey))
   {
      case HAT_UP_MASK:
         strlcpy(s + _len, "up", sizeof(s) - _len);
         break;
      case HAT_DOWN_MASK:
         strlcpy(s + _len, "down", sizeof(s) - _len);
         break;
      case HAT_LEFT_MASK:
         strlcpy(s + _len, "left", sizeof(s) - _len);
         break;
      case HAT_RIGHT_MASK:
         strlcpy(s + _len, "right", sizeof(s) - _len);
         break;
      default:
         break;
   }

   config_set_string(conf, key, s);
}

static void save_keybind_joykey(config_file_t *conf,
      const char *prefix,
      const char *base,
      const struct retro_keybind *bind, bool save_empty)
{
   char key[64];
   size_t _len = fill_pathname_join_delim(key, prefix,
         base, '_', sizeof(key));
   strlcpy(key + _len, "_btn", sizeof(key) - _len);

   if (bind->joykey == NO_BTN)
   {
       if (save_empty)
         config_set_string(conf, key, "nul");
   }
   else if (GET_HAT_DIR(bind->joykey))
      save_keybind_hat(conf, key, bind);
   else
      config_set_uint64(conf, key, bind->joykey);
}

static void save_keybind_axis(config_file_t *conf,
      const char *prefix,
      const char *base,
      const struct retro_keybind *bind, bool save_empty)
{
   char key[64];
   char config[16];
   size_t _len = fill_pathname_join_delim(key, prefix, base, '_', sizeof(key));
   strlcpy(key + _len, "_axis", sizeof(key) - _len);

   if (bind->joyaxis == AXIS_NONE)
   {
      if (save_empty)
         config_set_string(conf, key, "nul");
      return;
   }

   if (AXIS_NEG_GET(bind->joyaxis) != AXIS_DIR_NONE)
   {
      snprintf(config, sizeof(config), "-%lu",
            (unsigned long)AXIS_NEG_GET(bind->joyaxis));
   }
   else if (AXIS_POS_GET(bind->joyaxis) != AXIS_DIR_NONE)
   {
      snprintf(config, sizeof(config), "+%lu",
            (unsigned long)AXIS_POS_GET(bind->joyaxis));
   }
   config_set_string(conf, key, config);
}

static void save_keybind_mbutton(config_file_t *conf,
      const char *prefix,
      const char *base,
      const struct retro_keybind *bind, bool save_empty)
{
   char key[64];
   size_t _len = fill_pathname_join_delim(key, prefix,
      base, '_', sizeof(key));
   strlcpy(key + _len, "_mbtn", sizeof(key) - _len);

   switch (bind->mbutton)
   {
      case RETRO_DEVICE_ID_MOUSE_LEFT:
         config_set_uint64(conf, key, 1);
         break;
      case RETRO_DEVICE_ID_MOUSE_RIGHT:
         config_set_uint64(conf, key, 2);
         break;
      case RETRO_DEVICE_ID_MOUSE_MIDDLE:
         config_set_uint64(conf, key, 3);
         break;
      case RETRO_DEVICE_ID_MOUSE_BUTTON_4:
         config_set_uint64(conf, key, 4);
         break;
      case RETRO_DEVICE_ID_MOUSE_BUTTON_5:
         config_set_uint64(conf, key, 5);
         break;
      case RETRO_DEVICE_ID_MOUSE_WHEELUP:
         config_set_string(conf, key, "wu");
         break;
      case RETRO_DEVICE_ID_MOUSE_WHEELDOWN:
         config_set_string(conf, key, "wd");
         break;
      case RETRO_DEVICE_ID_MOUSE_HORIZ_WHEELUP:
         config_set_string(conf, key, "whu");
         break;
      case RETRO_DEVICE_ID_MOUSE_HORIZ_WHEELDOWN:
         config_set_string(conf, key, "whd");
         break;
      default:
         if (save_empty)
            config_set_string(conf, key, "nul");
         break;
   }
}

const char *input_config_get_prefix(unsigned user, bool meta)
{
   static const char *bind_user_prefix[MAX_USERS] = {
      "input_player1",
      "input_player2",
      "input_player3",
      "input_player4",
      "input_player5",
      "input_player6",
      "input_player7",
      "input_player8",
      "input_player9",
      "input_player10",
      "input_player11",
      "input_player12",
      "input_player13",
      "input_player14",
      "input_player15",
      "input_player16",
   };
   if (meta)
   {
      if (user == 0)
         return "input";
      /* Don't bother with meta bind for anyone else than first user. */
      return NULL;
   }
   return bind_user_prefix[user];
}

/**
 * input_config_save_keybinds_user:
 * @conf               : pointer to config file object
 * @user               : user number
 *
 * Save the current keybinds of a user (@user) to the config file (@conf).
 */
static void input_config_save_keybinds_user(config_file_t *conf, unsigned user)
{
   unsigned i = 0;

   for (i = 0; input_config_bind_map_get_valid(i); i++)
   {
      char key[64];
      char btn[64];
      const struct input_bind_map *keybind =
         (const struct input_bind_map*)INPUT_CONFIG_BIND_MAP_GET(i);
      bool meta                            = keybind ? keybind->meta : false;
      const char *prefix                   = input_config_get_prefix(user, meta);
      const struct retro_keybind *bind     = &input_config_binds[user][i];
      const char                 *base     = NULL;

      if (!prefix || !bind->valid || !keybind)
         continue;

      base                                 = keybind->base;
      btn[0]                               = '\0';

      fill_pathname_join_delim(key, prefix, base, '_', sizeof(key));

      input_keymaps_translate_rk_to_str(bind->key, btn, sizeof(btn));

      config_set_string(conf, key, btn);
      save_keybind_joykey (conf, prefix, base, bind, true);
      save_keybind_axis   (conf, prefix, base, bind, true);
      save_keybind_mbutton(conf, prefix, base, bind, true);
   }
}

/**
 * input_config_save_keybinds_user_override:
 * @conf               : pointer to config file object
 * @user               : user number
 * @bind_id            : bind number
 * @override_bind      : override retro_keybind for comparison and saving
 *
 * Save the current bind (@override_bind) override of a user (@user) to the
 * config file (@conf), and skip binds that are not modified.
 */
static void input_config_save_keybinds_user_override(config_file_t *conf,
      unsigned user, unsigned bind_id,
      const struct retro_keybind *override_bind)
{
   unsigned i = bind_id;

   if (input_config_bind_map_get_valid(i))
   {
      char key[64];
      char btn[64];
      const struct input_bind_map *keybind =
         (const struct input_bind_map*)INPUT_CONFIG_BIND_MAP_GET(i);
      bool meta                            = keybind ? keybind->meta : false;
      const char *prefix                   = input_config_get_prefix(user, meta);
      const struct retro_keybind *bind     = &input_config_binds[user][i];
      const char                 *base     = NULL;

      if (!prefix || !bind->valid || !keybind)
         return;

      base                                 = keybind->base;
      btn[0]                               = '\0';

      fill_pathname_join_delim(key, prefix, base, '_', sizeof(key));

      input_keymaps_translate_rk_to_str(override_bind->key, btn, sizeof(btn));

      config_set_string(conf, key, btn);

      if (bind->joykey  != override_bind->joykey)
         save_keybind_joykey (conf, prefix, base, override_bind, true);
      if (bind->joyaxis != override_bind->joyaxis)
         save_keybind_axis   (conf, prefix, base, override_bind, true);
      if (bind->mbutton != override_bind->mbutton)
         save_keybind_mbutton(conf, prefix, base, override_bind, true);

      RARCH_DBG("[Override] %s = \"%s\"\n", key, btn);
   }
}

void config_get_autoconf_profile_filename(
      const char *device_name, unsigned user,
      char *s, size_t len)
{
   static const char* invalid_filename_chars[] = {
      /* https://support.microsoft.com/en-us/help/905231/information-about-the-characters-that-you-cannot-use-in-site-names--fo */
      "~", "#", "%", "&", "*", "{", "}", "\\", ":", "[", "]", "?", "/", "|", "\'", "\"",
      NULL
   };
   size_t _len;
   unsigned i;

   settings_t *settings                 = config_st;
   const char *autoconf_dir             = settings->paths.directory_autoconfig;
   const char *joypad_driver_fallback   = settings->arrays.input_joypad_driver;
   const char *joypad_driver            = NULL;
   char *sanitised_name                 = NULL;

   if (string_is_empty(device_name))
      goto end;

   /* Get currently set joypad driver */
   joypad_driver = input_config_get_device_joypad_driver(user);
   if (string_is_empty(joypad_driver))
   {
      /* This cannot happen, but if we reach this
       * point without a driver being set for the
       * current input device then use the value
       * from the settings struct as a fallback */
      joypad_driver = joypad_driver_fallback;

      if (string_is_empty(joypad_driver))
         goto end;
   }

   sanitised_name = strdup(device_name);

   /* Remove invalid filename characters from
    * input device name */
   for (i = 0; invalid_filename_chars[i]; i++)
   {
      for (;;)
      {
         char *tmp = strstr(sanitised_name,
               invalid_filename_chars[i]);

         if (tmp)
            *tmp = '_';
         else
            break;
      }
   }

   /* Generate autoconfig file path */
   fill_pathname_join_special(s, autoconf_dir, joypad_driver, len);

   /* Driver specific autoconf dir may not exist, if autoconfs are not downloaded. */
   if (!path_is_directory(s))
      _len = strlcpy(s, sanitised_name, len);
   else
      _len = fill_pathname_join_special(s, joypad_driver, sanitised_name, len);
   strlcpy(s + _len, ".cfg", len - _len);

end:
   if (sanitised_name)
      free(sanitised_name);
}

/**
 * config_save_autoconf_profile:
 * @device_name       : Input device name
 * @user              : Controller number to save
 * Writes a controller autoconf file to disk.
 **/
bool config_save_autoconf_profile(const char *device_name, unsigned user)
{
   unsigned i;
   char buf[PATH_MAX_LENGTH];
   char autoconf_file[PATH_MAX_LENGTH];
   config_file_t *conf                  = NULL;
   int32_t pid_user                     = 0;
   int32_t vid_user                     = 0;
   bool ret                             = false;
   settings_t *settings                 = config_st;
   const char *autoconf_dir             = settings->paths.directory_autoconfig;
   const char *joypad_driver_fallback   = settings->arrays.input_joypad_driver;
   const char *joypad_driver            = NULL;

   if (string_is_empty(device_name))
      goto end;

   /* Get currently set joypad driver */
   joypad_driver = input_config_get_device_joypad_driver(user);
   if (string_is_empty(joypad_driver))
   {
      /* This cannot happen, but if we reach this
       * point without a driver being set for the
       * current input device then use the value
       * from the settings struct as a fallback */
      joypad_driver = joypad_driver_fallback;

      if (string_is_empty(joypad_driver))
         goto end;
   }

   /* Generate autoconfig file path */
   config_get_autoconf_profile_filename(device_name, user, buf, sizeof(buf));
   fill_pathname_join_special(autoconf_file, autoconf_dir, buf, sizeof(autoconf_file));

   /* Open config file */
   if (     !(conf = config_file_new_from_path_to_string(autoconf_file))
         && !(conf = config_file_new_alloc())
      )
      goto end;

   /* Update config file */
   config_set_string(conf, "input_driver",
         joypad_driver);
   config_set_string(conf, "input_device",
         input_config_get_device_name(settings->uints.input_joypad_index[user]));

   pid_user = input_config_get_device_pid(settings->uints.input_joypad_index[user]);
   vid_user = input_config_get_device_vid(settings->uints.input_joypad_index[user]);

   if (pid_user && vid_user)
   {
      config_set_int(conf, "input_vendor_id",
            vid_user);
      config_set_int(conf, "input_product_id",
            pid_user);
   }

   for (i = 0; i < RARCH_FIRST_META_KEY; i++)
   {
      const struct retro_keybind *bind = &input_config_binds[user][i];
      if (bind->valid)
      {
         save_keybind_joykey(
               conf, "input", input_config_bind_map_get_base(i),
               bind, false);
         save_keybind_axis(
               conf, "input", input_config_bind_map_get_base(i),
               bind, false);
      }
   }

   RARCH_LOG("[Autoconf] Writing autoconf file for device \"%s\" to \"%s\".\n", device_name, autoconf_file);
   ret = config_file_write(conf, autoconf_file, false);

end:
   if (conf)
      config_file_free(conf);

   return ret;
}

/**
 * config_save_file:
 * @path            : Path that shall be written to.
 *
 * Writes a config file to disk.
 *
 * Returns: true (1) on success, otherwise returns false (0).
 **/
bool config_save_file(const char *path)
{
   float msg_color;
   unsigned i                                        = 0;
   bool ret                                          = false;
   struct config_bool_setting     *bool_settings     = NULL;
   struct config_int_setting     *int_settings       = NULL;
   struct config_uint_setting     *uint_settings     = NULL;
   struct config_size_setting     *size_settings     = NULL;
   struct config_float_setting     *float_settings   = NULL;
   struct config_array_setting     *array_settings   = NULL;
   struct config_path_setting     *path_settings     = NULL;
   uint32_t flags                                    = runloop_get_flags();
   config_file_t                              *conf  = config_file_new_from_path_to_string(path);
   settings_t                              *settings = config_st;
   global_t *global                                  = global_get_ptr();
   int bool_settings_size                            = sizeof(settings->bools) / sizeof(settings->bools.placeholder);
   int float_settings_size                           = sizeof(settings->floats)/ sizeof(settings->floats.placeholder);
   int int_settings_size                             = sizeof(settings->ints)  / sizeof(settings->ints.placeholder);
   int uint_settings_size                            = sizeof(settings->uints) / sizeof(settings->uints.placeholder);
   int size_settings_size                            = sizeof(settings->sizes) / sizeof(settings->sizes.placeholder);
   int array_settings_size                           = sizeof(settings->arrays)/ sizeof(settings->arrays.placeholder);
   int path_settings_size                            = sizeof(settings->paths) / sizeof(settings->paths.placeholder);

   if (!conf)
      conf = config_file_new_alloc();

   if (!conf || (flags & RUNLOOP_FLAG_OVERRIDES_ACTIVE))
   {
      if (conf)
         config_file_free(conf);
      return false;
   }

   bool_settings   = populate_settings_bool  (settings, &bool_settings_size);
   int_settings    = populate_settings_int   (settings, &int_settings_size);
   uint_settings   = populate_settings_uint  (settings, &uint_settings_size);
   size_settings   = populate_settings_size  (settings, &size_settings_size);
   float_settings  = populate_settings_float (settings, &float_settings_size);
   array_settings  = populate_settings_array (settings, &array_settings_size);
   path_settings   = populate_settings_path  (settings, &path_settings_size);

   /* Path settings */
   if (path_settings && (path_settings_size > 0))
   {
      for (i = 0; i < (unsigned)path_settings_size; i++)
      {
         const char *value = path_settings[i].ptr;

         if (path_settings[i].flags & CFG_BOOL_FLG_DEF_ENABLE)
            if (string_is_empty(path_settings[i].ptr))
               value = "default";

         config_set_path(conf, path_settings[i].ident, value);
      }

      free(path_settings);
   }

   /* String settings  */
   if (array_settings && (array_settings_size > 0))
   {
      for (i = 0; i < (unsigned)array_settings_size; i++)
         if (   !array_settings[i].override
             || !retroarch_override_setting_is_set(array_settings[i].override, NULL))
            config_set_string(conf,
                  array_settings[i].ident,
                  array_settings[i].ptr);

      free(array_settings);
   }

   /* Float settings  */
   if (float_settings && (float_settings_size > 0))
   {
      for (i = 0; i < (unsigned)float_settings_size; i++)
         if (   !float_settings[i].override
             || !retroarch_override_setting_is_set(float_settings[i].override, NULL))
            config_set_float(conf,
                  float_settings[i].ident,
                  *float_settings[i].ptr);

      free(float_settings);
   }

   /* Integer settings */
   if (int_settings && (int_settings_size > 0))
   {
      for (i = 0; i < (unsigned)int_settings_size; i++)
         if (   !int_settings[i].override
             || !retroarch_override_setting_is_set(int_settings[i].override, NULL))
            config_set_int(conf,
                  int_settings[i].ident,
                  *int_settings[i].ptr);

      free(int_settings);
   }

   if (uint_settings && (uint_settings_size > 0))
   {
      for (i = 0; i < (unsigned)uint_settings_size; i++)
         if (   !uint_settings[i].override
             || !retroarch_override_setting_is_set(uint_settings[i].override, NULL))
            config_set_int(conf,
                  uint_settings[i].ident,
                  *uint_settings[i].ptr);

      free(uint_settings);
   }

   if (size_settings && (size_settings_size > 0))
   {
      for (i = 0; i < (unsigned)size_settings_size; i++)
         if (   !size_settings[i].override
             || !retroarch_override_setting_is_set(size_settings[i].override, NULL))
            config_set_int(conf,
                  size_settings[i].ident,
                  (int)*size_settings[i].ptr);

      free(size_settings);
   }

   for (i = 0; i < MAX_USERS; i++)
   {
      size_t _len;
      char cfg[64];
      char formatted_number[4];
      formatted_number[0] = '\0';

      snprintf(formatted_number, sizeof(formatted_number), "%u", i + 1);

      _len = strlcpy(cfg, "input_device_p",     sizeof(cfg));
      strlcpy(cfg + _len, formatted_number,     sizeof(cfg) - _len);
      config_set_int(conf, cfg, settings->uints.input_device[i]);

      _len  = strlcpy(cfg, "input_player",          sizeof(cfg));
      _len += strlcpy(cfg + _len, formatted_number, sizeof(cfg) - _len);

      strlcpy(cfg + _len, "_mouse_index",       sizeof(cfg) - _len);
      config_set_int(conf, cfg, settings->uints.input_mouse_index[i]);

      strlcpy(cfg + _len, "_joypad_index",      sizeof(cfg) - _len);
      config_set_int(conf, cfg, settings->uints.input_joypad_index[i]);

      strlcpy(cfg + _len, "_analog_dpad_mode",  sizeof(cfg) - _len);
      config_set_int(conf, cfg, settings->uints.input_analog_dpad_mode[i]);

      strlcpy(cfg + _len, "_device_reservation_type",  sizeof(cfg) - _len);
      config_set_int(conf, cfg, settings->uints.input_device_reservation_type[i]);
   }

   /* Boolean settings */
   if (bool_settings && (bool_settings_size > 0))
   {
      for (i = 0; i < (unsigned)bool_settings_size; i++)
         if (   !bool_settings[i].override
             || !retroarch_override_setting_is_set(bool_settings[i].override, NULL))
            config_set_string(conf, bool_settings[i].ident,
                  *bool_settings[i].ptr
                  ? "true" : "false");

      free(bool_settings);
   }

#ifdef HAVE_NETWORKGAMEPAD
   {
      char tmp[64];
      size_t _len = strlcpy(tmp, "network_remote_enable_user_p", sizeof(tmp));
      for (i = 0; i < MAX_USERS; i++)
      {
         snprintf(tmp + _len, sizeof(tmp) - _len, "%u", i + 1);
         config_set_string(conf, tmp,
               settings->bools.network_remote_enable_user[i]
               ? "true" : "false");
      }
   }
#endif

   /* Verbosity isn't in bool_settings since it needs to be loaded differently */
   if (!retroarch_override_setting_is_set(RARCH_OVERRIDE_SETTING_VERBOSITY, NULL))
      config_set_string(conf, "log_verbosity",
            verbosity_is_enabled() ? "true" : "false");
   config_set_string(conf, "perfcnt_enable",
            retroarch_ctl(RARCH_CTL_IS_PERFCNT_ENABLE, NULL)
         ? "true" : "false");

   msg_color = (((int)(settings->floats.video_msg_color_r * 255.0f) & 0xff) << 16) +
               (((int)(settings->floats.video_msg_color_g * 255.0f) & 0xff) <<  8) +
               (((int)(settings->floats.video_msg_color_b * 255.0f) & 0xff));

   /* Hexadecimal settings */
   config_set_hex(conf, "video_message_color", msg_color);

   if (conf)
      video_driver_save_settings(global, conf);

#ifdef HAVE_LAKKA
   if (settings->bools.ssh_enable)
      filestream_close(filestream_open(LAKKA_SSH_PATH,
               RETRO_VFS_FILE_ACCESS_WRITE,
               RETRO_VFS_FILE_ACCESS_HINT_NONE));
   else
      filestream_delete(LAKKA_SSH_PATH);
   if (settings->bools.samba_enable)
      filestream_close(filestream_open(LAKKA_SAMBA_PATH,
               RETRO_VFS_FILE_ACCESS_WRITE,
               RETRO_VFS_FILE_ACCESS_HINT_NONE));
   else
      filestream_delete(LAKKA_SAMBA_PATH);
   if (settings->bools.bluetooth_enable)
      filestream_close(filestream_open(LAKKA_BLUETOOTH_PATH,
               RETRO_VFS_FILE_ACCESS_WRITE,
               RETRO_VFS_FILE_ACCESS_HINT_NONE));
   else
      filestream_delete(LAKKA_BLUETOOTH_PATH);
#endif

   for (i = 0; i < MAX_USERS; i++)
      input_config_save_keybinds_user(conf, i);

   ret = config_file_write(conf, path, true);
   config_file_free(conf);

#if TARGET_OS_TV
   if (ret && string_is_equal(path, path_get(RARCH_PATH_CONFIG)))
       write_userdefaults_config_file();
#endif

   return ret;
}

/**
 * config_save_overrides:
 * @path            : Path that shall be written to.
 *
 * Writes a config file override to disk.
 *
 * Returns: true (1) on success, (-1) if nothing to write, otherwise returns false (0).
 **/
int8_t config_save_overrides(enum override_type type,
      void *data, bool remove, const char *path)
{
   int tmp_i                                   = 0;
   unsigned i                                  = 0;
   int8_t ret                                  = 0;
   retro_keybind_set input_override_binds[MAX_USERS]
                                               = {0};
   config_file_t *conf                         = NULL;
   settings_t *settings                        = NULL;
   struct config_bool_setting *bool_settings   = NULL;
   struct config_bool_setting *bool_overrides  = NULL;
   struct config_int_setting *int_settings     = NULL;
   struct config_uint_setting *uint_settings   = NULL;
   struct config_size_setting *size_settings   = NULL;
   struct config_int_setting *int_overrides    = NULL;
   struct config_uint_setting *uint_overrides  = NULL;
   struct config_size_setting *size_overrides  = NULL;
   struct config_float_setting *float_settings = NULL;
   struct config_float_setting *float_overrides= NULL;
   struct config_array_setting *array_settings = NULL;
   struct config_array_setting *array_overrides= NULL;
   struct config_path_setting *path_settings   = NULL;
   struct config_path_setting *path_overrides  = NULL;
   char config_directory[DIR_MAX_LENGTH];
   char override_directory[DIR_MAX_LENGTH];
   char override_path[PATH_MAX_LENGTH];
   settings_t *overrides                       = config_st;
   int bool_settings_size                      = sizeof(settings->bools)  / sizeof(settings->bools.placeholder);
   int float_settings_size                     = sizeof(settings->floats) / sizeof(settings->floats.placeholder);
   int int_settings_size                       = sizeof(settings->ints)   / sizeof(settings->ints.placeholder);
   int uint_settings_size                      = sizeof(settings->uints)  / sizeof(settings->uints.placeholder);
   int size_settings_size                      = sizeof(settings->sizes)  / sizeof(settings->sizes.placeholder);
   int array_settings_size                     = sizeof(settings->arrays) / sizeof(settings->arrays.placeholder);
   int path_settings_size                      = sizeof(settings->paths)  / sizeof(settings->paths.placeholder);
   rarch_system_info_t *sys_info               = (rarch_system_info_t*)data;
   const char *core_name                       = sys_info ? sys_info->info.library_name : NULL;
   const char *rarch_path_basename             = path_get(RARCH_PATH_BASENAME);
   const char *game_name                       = NULL;
   bool has_content                            = !string_is_empty(rarch_path_basename);

   override_path[0]      = '\0';

   /* > Cannot save an override if we have no core
    * > Cannot save a per-game or per-content-directory
    *   override if we have no content */
   if (     string_is_empty(core_name)
       || (!has_content && (type != OVERRIDE_CORE)))
      return false;

   settings = (settings_t*)calloc(1, sizeof(settings_t));
   conf     = config_file_new_alloc();

   /* Get base config directory */
   fill_pathname_application_special(config_directory,
         sizeof(config_directory),
         APPLICATION_SPECIAL_DIRECTORY_CONFIG);

   fill_pathname_join_special(override_directory,
      config_directory, core_name,
      sizeof(override_directory));

   /* Ensure base config directory exists */
   if (!path_is_directory(override_directory))
      path_mkdir(override_directory);

   /* Store current binds as override binds */
   memcpy(input_override_binds, input_config_binds, sizeof(input_override_binds));

   /* Load the original config file in memory */
   config_load_file(global_get_ptr(),
         "without-overrides", settings);

   bool_settings       = populate_settings_bool(settings,   &bool_settings_size);
   tmp_i               = sizeof(settings->bools) / sizeof(settings->bools.placeholder);
   bool_overrides      = populate_settings_bool(overrides,  &tmp_i);

   int_settings        = populate_settings_int(settings,    &int_settings_size);
   tmp_i               = sizeof(settings->ints) / sizeof(settings->ints.placeholder);
   int_overrides       = populate_settings_int(overrides,   &tmp_i);

   uint_settings       = populate_settings_uint(settings,   &uint_settings_size);
   tmp_i               = sizeof(settings->uints) / sizeof(settings->uints.placeholder);
   uint_overrides      = populate_settings_uint(overrides,  &tmp_i);

   size_settings       = populate_settings_size(settings,   &size_settings_size);
   tmp_i               = sizeof(settings->sizes) / sizeof(settings->sizes.placeholder);
   size_overrides      = populate_settings_size(overrides,  &tmp_i);

   float_settings      = populate_settings_float(settings,  &float_settings_size);
   tmp_i               = sizeof(settings->floats) / sizeof(settings->floats.placeholder);
   float_overrides     = populate_settings_float(overrides, &tmp_i);

   array_settings      = populate_settings_array(settings,  &array_settings_size);
   tmp_i               = sizeof(settings->arrays) / sizeof(settings->arrays.placeholder);
   array_overrides     = populate_settings_array(overrides, &tmp_i);

   path_settings       = populate_settings_path(settings,   &path_settings_size);
   tmp_i               = sizeof(settings->paths) / sizeof(settings->paths.placeholder);
   path_overrides      = populate_settings_path(overrides,  &tmp_i);

   if (conf->flags & CONF_FILE_FLG_MODIFIED)
      RARCH_LOG("[Override] Looking for changed settings...\n");

   if (conf)
   {
      /* Turbo fire settings are saved to remaps and therefore skipped from overrides */
      for (i = 0; i < (unsigned)bool_settings_size; i++)
      {
         if (string_starts_with(bool_settings[i].ident, "input_turbo"))
            continue;

         if ((*bool_settings[i].ptr) != (*bool_overrides[i].ptr))
         {
            config_set_string(conf, bool_overrides[i].ident,
                  (*bool_overrides[i].ptr) ? "true" : "false");
            RARCH_DBG("[Override] %s = \"%s\"\n",
                  bool_overrides[i].ident,
                  (*bool_overrides[i].ptr) ? "true" : "false");
         }
      }
      for (i = 0; i < (unsigned)int_settings_size; i++)
      {
         if (string_starts_with(int_settings[i].ident, "input_turbo"))
            continue;

         if ((*int_settings[i].ptr) != (*int_overrides[i].ptr))
         {
            config_set_int(conf, int_overrides[i].ident,
                  (*int_overrides[i].ptr));
            RARCH_DBG("[Override] %s = \"%d\"\n",
                  int_overrides[i].ident, *int_overrides[i].ptr);
         }
      }
      for (i = 0; i < (unsigned)uint_settings_size; i++)
      {
         if (string_starts_with(uint_settings[i].ident, "input_turbo"))
            continue;

         if ((*uint_settings[i].ptr) != (*uint_overrides[i].ptr))
         {
            config_set_int(conf, uint_overrides[i].ident,
                  (*uint_overrides[i].ptr));
            RARCH_DBG("[Override] %s = \"%d\"\n",
                  uint_overrides[i].ident, *uint_overrides[i].ptr);
         }
      }
      for (i = 0; i < (unsigned)size_settings_size; i++)
      {
         if ((*size_settings[i].ptr) != (*size_overrides[i].ptr))
         {
            config_set_int(conf, size_overrides[i].ident,
                  (int)(*size_overrides[i].ptr));
            RARCH_DBG("[Override] %s = \"%d\"\n",
                  size_overrides[i].ident, *size_overrides[i].ptr);
         }
      }
      for (i = 0; i < (unsigned)float_settings_size; i++)
      {
         if ((*float_settings[i].ptr) != (*float_overrides[i].ptr))
         {
            config_set_float(conf, float_overrides[i].ident,
                  *float_overrides[i].ptr);
            RARCH_DBG("[Override] %s = \"%f\"\n",
                  float_overrides[i].ident, *float_overrides[i].ptr);
         }
      }

      for (i = 0; i < (unsigned)array_settings_size; i++)
      {
         if (!string_is_equal(array_settings[i].ptr, array_overrides[i].ptr))
         {
#ifdef HAVE_CHEEVOS
            /* As authentication doesn't occur until after content is loaded,
             * the achievement authentication token might only exist in the
             * override set, and therefore differ from the master config set.
             * Storing the achievement authentication token in an override
             * is a recipe for disaster. If it expires and the user generates
             * a new token, then the override will be out of date and the
             * user will have to reauthenticate for each override (and also
             * remember to update each override). Also exclude the username
             * as it's directly tied to the token and password.
             */
            if (   string_is_equal(array_settings[i].ident, "cheevos_token")
                || string_is_equal(array_settings[i].ident, "cheevos_password")
                || string_is_equal(array_settings[i].ident, "cheevos_username"))
               continue;
#endif // HAVE_CHEEVOS
            config_set_string(conf, array_overrides[i].ident,
                  array_overrides[i].ptr);
            RARCH_DBG("[Override] %s = \"%s\"\n",
                  array_overrides[i].ident, array_overrides[i].ptr);
         }
      }

      for (i = 0; i < (unsigned)path_settings_size; i++)
      {
         if (!string_is_equal(path_settings[i].ptr, path_overrides[i].ptr))
         {
#if IOS
            if (string_is_equal(path_settings[i].ident, "libretro_directory"))
               continue;
#endif
            config_set_path(conf, path_overrides[i].ident,
                  path_overrides[i].ptr);
            RARCH_DBG("[Override] %s = \"%s\"\n",
                  path_overrides[i].ident, path_overrides[i].ptr);
         }
      }

      for (i = 0; i < MAX_USERS; i++)
      {
         size_t _len;
         uint8_t j;
         char cfg[64];
         char formatted_number[4];
         cfg[0] = formatted_number[0] = '\0';

         snprintf(formatted_number, sizeof(formatted_number), "%u", i + 1);

         if (settings->uints.input_device[i]
               != overrides->uints.input_device[i])
         {
            size_t _len = strlcpy(cfg, "input_device_p", sizeof(cfg));
            strlcpy(cfg + _len, formatted_number, sizeof(cfg) - _len);
            config_set_int(conf, cfg, overrides->uints.input_device[i]);
            RARCH_DBG("[Override] %s = \"%u\"\n", cfg, overrides->uints.input_device[i]);
         }

         _len  = strlcpy(cfg, "input_player",          sizeof(cfg));
         _len += strlcpy(cfg + _len, formatted_number, sizeof(cfg) - _len);

         if (settings->uints.input_mouse_index[i]
               != overrides->uints.input_mouse_index[i])
         {
            strlcpy(cfg + _len, "_mouse_index",   sizeof(cfg) - _len);
            config_set_int(conf, cfg, overrides->uints.input_mouse_index[i]);
            RARCH_DBG("[Override] %s = \"%u\"\n", cfg, overrides->uints.input_mouse_index[i]);
         }

         if (settings->uints.input_joypad_index[i]
               != overrides->uints.input_joypad_index[i])
         {
            strlcpy(cfg + _len, "_joypad_index",  sizeof(cfg) - _len);
            config_set_int(conf, cfg, overrides->uints.input_joypad_index[i]);
            RARCH_DBG("[Override] %s = \"%u\"\n", cfg, overrides->uints.input_joypad_index[i]);
         }

         if (settings->uints.input_analog_dpad_mode[i]
               != overrides->uints.input_analog_dpad_mode[i])
         {
            strlcpy(cfg + _len, "_analog_dpad_mode", sizeof(cfg) - _len);
            config_set_int(conf, cfg, overrides->uints.input_analog_dpad_mode[i]);
            RARCH_DBG("[Override] %s = \"%u\"\n", cfg, overrides->uints.input_analog_dpad_mode[i]);
         }

        if (settings->uints.input_device_reservation_type[i]
               != overrides->uints.input_device_reservation_type[i])
         {
            strlcpy(cfg + _len, "_device_reservation_type", sizeof(cfg) - _len);
            config_set_int(conf, cfg, overrides->uints.input_device_reservation_type[i]);
            RARCH_DBG("[Override] %s = \"%u\"\n", cfg, overrides->uints.input_device_reservation_type[i]);
         }

         /* TODO: is this whole section really necessary? Does the loop above not do this? */
         if (!string_is_equal(settings->arrays.input_reserved_devices[i], overrides->arrays.input_reserved_devices[i]))
         {
            strlcpy(cfg + _len, "_device_reservation_type", sizeof(cfg) - _len);

            config_set_string(conf, cfg,
                  overrides->arrays.input_reserved_devices[i]);
            RARCH_DBG("[Override] %s = \"%s\"\n",
                  cfg, overrides->arrays.input_reserved_devices[i]);
         }

         for (j = 0; j < RARCH_BIND_LIST_END; j++)
         {
            const struct retro_keybind *override_bind = &input_override_binds[i][j];
            const struct retro_keybind *config_bind   = &input_config_binds[i][j];

            if (     config_bind->joyaxis != override_bind->joyaxis
                  || config_bind->joykey  != override_bind->joykey
                  || config_bind->key     != override_bind->key
                  || config_bind->mbutton != override_bind->mbutton
               )
               input_config_save_keybinds_user_override(conf, i, j, override_bind);
         }
      }

      ret = 0;

      switch (type)
      {
         case OVERRIDE_CORE:
            fill_pathname_join_special_ext(override_path,
                  config_directory, core_name,
                  core_name,
                  FILE_PATH_CONFIG_EXTENSION,
                  sizeof(override_path));
            break;
         case OVERRIDE_GAME:
            game_name = path_basename_nocompression(rarch_path_basename);
            fill_pathname_join_special_ext(override_path,
                  config_directory, core_name,
                  game_name,
                  FILE_PATH_CONFIG_EXTENSION,
                  sizeof(override_path));
            break;
         case OVERRIDE_CONTENT_DIR:
            {
               char content_dir_name[DIR_MAX_LENGTH];
               content_dir_name[0]   = '\0';
               fill_pathname_parent_dir_name(content_dir_name,
                     rarch_path_basename, sizeof(content_dir_name));
               fill_pathname_join_special_ext(override_path,
                     config_directory, core_name,
                     content_dir_name,
                     FILE_PATH_CONFIG_EXTENSION,
                     sizeof(override_path));
            }
            break;
         case OVERRIDE_AS:
            fill_pathname_join_special_ext(override_path,
                  config_directory, core_name,
                  path,
                  FILE_PATH_CONFIG_EXTENSION,
                  sizeof(override_path));
            break;
         case OVERRIDE_NONE:
         default:
            break;
      }

      if (!(conf->flags & CONF_FILE_FLG_MODIFIED) && !remove)
         ret = -1;

      if (!string_is_empty(override_path))
      {
         if (!(conf->flags & CONF_FILE_FLG_MODIFIED) && !remove)
            if (path_is_valid(override_path))
               remove = true;

         if (     remove
               && path_is_valid(override_path))
         {
            if (filestream_delete(override_path) == 0)
            {
               ret = -1;
               RARCH_LOG("[Override] %s: \"%s\".\n",
                     "Deleted", override_path);
            }
         }
         else if (conf->flags & CONF_FILE_FLG_MODIFIED)
         {
            ret = config_file_write(conf, override_path, true);

            if (ret)
            {
               path_set(RARCH_PATH_CONFIG_OVERRIDE, override_path);
               RARCH_LOG("[Override] %s: \"%s\".\n",
                     "Saved", override_path);
            }
            else
            {
               RARCH_LOG("[Override] %s: \"%s\".\n",
                     "Failed to save", override_path);
            }
         }
      }

      config_file_free(conf);
   }

   /* Since config_load_file resets binds, restore overrides back to current binds */
   memcpy(input_config_binds, input_override_binds, sizeof(input_config_binds));

   if (bool_settings)
      free(bool_settings);
   if (bool_overrides)
      free(bool_overrides);
   if (int_settings)
      free(int_settings);
   if (uint_settings)
      free(uint_settings);
   if (size_settings)
      free(size_settings);
   if (int_overrides)
      free(int_overrides);
   if (uint_overrides)
      free(uint_overrides);
   if (float_settings)
      free(float_settings);
   if (float_overrides)
      free(float_overrides);
   if (array_settings)
      free(array_settings);
   if (array_overrides)
      free(array_overrides);
   if (path_settings)
      free(path_settings);
   if (path_overrides)
      free(path_overrides);
   if (size_overrides)
      free(size_overrides);
   free(settings);

   return ret;
}

/* Replaces currently loaded configuration file with
 * another one. Will load a dummy core to flush state
 * properly. */
bool config_replace(bool config_replace_save_on_exit, char *path)
{
   content_ctx_info_t content_info = {0};
   const char *rarch_path_config   = path_get(RARCH_PATH_CONFIG);

   /* If config file to be replaced is the same as the
    * current config file, exit. */
   if (string_is_equal(path, rarch_path_config))
      return false;

   if (config_replace_save_on_exit && !path_is_empty(RARCH_PATH_CONFIG))
      config_save_file(rarch_path_config);

   path_set(RARCH_PATH_CONFIG, path);

   retroarch_ctl(RARCH_CTL_UNSET_BLOCK_CONFIG_READ, NULL);

   /* Load core in new (salamander) config. */
   path_clear(RARCH_PATH_CORE);

   return task_push_start_dummy_core(&content_info);
}
#endif // HAVE_CONFIGFILE

#if !defined(HAVE_DYNAMIC)
/* Salamander config file contains a single
 * entry (libretro_path), which is linked to
 * RARCH_PATH_CORE
 * > Used to select which core to load
 *   when launching a salamander build */

static bool config_file_salamander_get_path(char *s, size_t len)
{
   const char *rarch_config_path = g_defaults.path_config;

   if (!string_is_empty(rarch_config_path))
      fill_pathname_resolve_relative(s,
            rarch_config_path,
            FILE_PATH_SALAMANDER_CONFIG,
            len);
   else
      strlcpy(s, FILE_PATH_SALAMANDER_CONFIG, len);

   return !string_is_empty(s);
}

void config_load_file_salamander(void)
{
   char config_path[PATH_MAX_LENGTH];
   config_file_t *config = NULL;

   config_path[0]   = '\0';

   /* Get config file path */
   if (!config_file_salamander_get_path(
         config_path, sizeof(config_path)))
      return;

   /* Open config file */
   if (!(config = config_file_new_from_path_to_string(config_path)))
      return;

   /* Read 'libretro_path' value and update
    * RARCH_PATH_CORE */
   RARCH_LOG("[Config] Loading salamander config from: \"%s\".\n",
         config_path);

   if (config_get_path(config, "libretro_path",
         config_path, sizeof(config_path))
       && !string_is_empty(config_path)
       && !string_is_equal(config_path, "builtin"))
      path_set(RARCH_PATH_CORE, config_path);

   config_file_free(config);
}

void config_save_file_salamander(void)
{
   config_file_t *conf       = NULL;
   const char *libretro_path = path_get(RARCH_PATH_CORE);
   bool success              = false;
   char config_path[PATH_MAX_LENGTH];

   config_path[0] = '\0';

   if (   string_is_empty(libretro_path)
       || string_is_equal(libretro_path, "builtin"))
      return;

   /* Get config file path */
   if (!config_file_salamander_get_path(
         config_path, sizeof(config_path)))
      return;

   /* Open config file */
   if (     !(conf = config_file_new_from_path_to_string(config_path))
         && !(conf = config_file_new_alloc())
      )
      goto end;

   /* Update config file */
   config_set_path(conf, "libretro_path", libretro_path);

   /* Save config file
    * > Only one entry - no need to sort */
   success = config_file_write(conf, config_path, false);

end:
   if (success)
      RARCH_LOG("[Config] Saving salamander config to: \"%s\".\n",
            config_path);
   else
      RARCH_ERR("[Config] Failed to create new salamander config file in: \"%s\".\n",
            config_path);

   if (conf)
      config_file_free(conf);
}
#endif // !defined(HAVE_DYNAMIC)

bool input_config_bind_map_get_valid(unsigned bind_index)
{
   const struct input_bind_map *keybind =
      (const struct input_bind_map*)INPUT_CONFIG_BIND_MAP_GET(bind_index);
   if (!keybind)
      return false;
   return keybind->valid;
}

void input_config_reset_autoconfig_binds(unsigned port)
{
   unsigned i;

   if (port >= MAX_USERS)
      return;

   for (i = 0; i < RARCH_BIND_LIST_END; i++)
   {
      input_autoconf_binds[port][i].joykey  = NO_BTN;
      input_autoconf_binds[port][i].joyaxis = AXIS_NONE;

      if (input_autoconf_binds[port][i].joykey_label)
      {
         free(input_autoconf_binds[port][i].joykey_label);
         input_autoconf_binds[port][i].joykey_label = NULL;
      }

      if (input_autoconf_binds[port][i].joyaxis_label)
      {
         free(input_autoconf_binds[port][i].joyaxis_label);
         input_autoconf_binds[port][i].joyaxis_label = NULL;
      }
   }
}

void retroarch_config_deinit(void)
{
   if (config_st)
      free(config_st);
   config_st = NULL;
}

void retroarch_config_init(void)
{
   if (!config_st)
      config_st = (settings_t*)calloc(1, sizeof(settings_t));
}
