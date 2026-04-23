/* RetroArch - A frontend for libretro.
 * Copyright (C) 2010-2014 - Hans-Kristian Arntzen
 * Copyright (C) 2011-2017 - Daniel De Matteis
 * Copyright (C) 2012-2014 - Jason Fetters
 * Copyright (C) 2014-2015 - Jay McCarthy
 *
 * RetroArch is free software: you can redistribute it and/or modify it under the terms
 * of the GNU General Public License as published by the Free Software Found-
 * ation, either version 3 of the License, or (at your option) any later version.
 *
 * RetroArch is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
 * without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
 * PURPOSE. See the GNU General Public License for more details.
 * * You should have received a copy of the GNU General Public License along with RetroArch.
 * If not, see <http://www.gnu.org/licenses/>.
 */

#import <AVFoundation/AVFoundation.h>

#include <sys/sysctl.h>
#include <sys/utsname.h>

#include <utils/configuration.h>

typedef enum
{
   CFApplicationDirectory           = 1,   /* Supported applications (Applications) */
   CFDemoApplicationDirectory       = 2,   /* Unsupported applications, demonstration versions (Demos) */
   CFDeveloperApplicationDirectory  = 3,   /* Developer applications (Developer/Applications). DEPRECATED - there is no one single Developer directory. */
   CFAdminApplicationDirectory      = 4,   /* System and network administration applications (Administration) */
   CFLibraryDirectory               = 5,   /* various documentation, support, and configuration files, resources (Library) */
   CFDeveloperDirectory             = 6,   /* developer resources (Developer) DEPRECATED - there is no one single Developer directory. */
   CFUserDirectory                  = 7,   /* User home directories (Users) */
   CFDocumentationDirectory         = 8,   /* Documentation (Documentation) */
   CFDocumentDirectory              = 9,   /* Documents (Documents) */
   CFCoreServiceDirectory           = 10,  /* Location of CoreServices directory (System/Library/CoreServices) */
   CFAutosavedInformationDirectory  = 11,  /* Location of autosaved documents (Documents/Autosaved) */
   CFDesktopDirectory               = 12,  /* Location of user's desktop */
   CFCachesDirectory                = 13,  /* Location of discardable cache files (Library/Caches) */
   CFApplicationSupportDirectory    = 14,  /* Location of application support files (plug-ins, etc) (Library/Application Support) */
   CFDownloadsDirectory             = 15,  /* Location of the user's "Downloads" directory */
   CFInputMethodsDirectory          = 16,  /* Input methods (Library/Input Methods) */
   CFMoviesDirectory                = 17,  /* Location of user's Movies directory (~/Movies) */
   CFMusicDirectory                 = 18,  /* Location of user's Music directory (~/Music) */
   CFPicturesDirectory              = 19,  /* Location of user's Pictures directory (~/Pictures) */
   CFPrinterDescriptionDirectory    = 20,  /* Location of system's PPDs directory (Library/Printers/PPDs) */
   CFSharedPublicDirectory          = 21,  /* Location of user's Public sharing directory (~/Public) */
   CFPreferencePanesDirectory       = 22,  /* Location of the PreferencePanes directory for use with System Preferences (Library/PreferencePanes) */
   CFApplicationScriptsDirectory    = 23,  /* Location of the user scripts folder for the calling application (~/Library/Application Scripts/code-signing-id) */
   CFItemReplacementDirectory       = 99,  /* For use with NSFileManager's URLForDirectory:inDomain:appropriateForURL:create:error: */
   CFAllApplicationsDirectory       = 100, /* all directories where applications can occur */
   CFAllLibrariesDirectory          = 101, /* all directories where resources can occur */
   CFTrashDirectory                 = 102  /* location of Trash directory */
} CFSearchPathDirectory;

typedef enum
{
   CFUserDomainMask     = 1,       /* user's home directory --- place to install user's personal items (~) */
   CFLocalDomainMask    = 2,       /* local to the current machine --- place to install items available to everyone on this machine (/Library) */
   CFNetworkDomainMask  = 4,       /* publicly available location in the local area network --- place to install items available on the network (/Network) */
   CFSystemDomainMask   = 8,       /* provided by Apple, unmodifiable (/System) */
   CFAllDomainsMask     = 0x0ffff  /* All domains: all of the above and future items */
} CFDomainMask;

#if (defined(OSX) && (MAC_OS_X_VERSION_MAX_ALLOWED >= 101200))
static int speak_pid                            = 0;
#endif

static char darwin_cpu_model_name[64] = {0};

static void CFSearchPathForDirectoriesInDomains(
      char *s, size_t len)
{
#if TARGET_OS_TV
   NSSearchPathDirectory dir = NSCachesDirectory;
#else
   NSSearchPathDirectory dir = NSDocumentDirectory;
#endif
#if __has_feature(objc_arc)
   CFStringRef array_val     = (__bridge CFStringRef)[
         NSSearchPathForDirectoriesInDomains(dir,
            NSUserDomainMask, YES) firstObject];
#else
   CFStringRef array_val     = nil;
   NSArray *arr              =
      NSSearchPathForDirectoriesInDomains(dir,
            NSUserDomainMask, YES);
   if ([arr count] != 0)
      array_val              = (CFStringRef)[arr objectAtIndex:0];
#endif
   if (array_val)
      CFStringGetCString(array_val, s, len, kCFStringEncodingUTF8);
}

static void CFTemporaryDirectory(char *s, size_t len)
{
#if __has_feature(objc_arc)
   CFStringRef path = (__bridge CFStringRef)NSTemporaryDirectory();
#else
   CFStringRef path = (CFStringRef)NSTemporaryDirectory();
#endif
   CFStringGetCString(path, s, len, kCFStringEncodingUTF8);
}

void get_ios_version(int *major, int *minor);

static void frontend_darwin_get_name(char *s, size_t len)
{
   struct utsname buffer;
   if (uname(&buffer) == 0)
      strlcpy(s, buffer.machine, len);
}

static size_t frontend_darwin_get_os(char *s, size_t len, int *major, int *minor)
{
   size_t _len;
   get_ios_version(major, minor);
   _len = strlcpy(s, "iOS", len);
   return _len;
}

static void frontend_darwin_get_env(int *argc, char *argv[],
      void *args, void *params_data)
{
   CFURLRef bundle_url;
   CFStringRef bundle_path;
   char temp_dir[DIR_MAX_LENGTH]           = {0};
   char bundle_path_buf[PATH_MAX_LENGTH]   = {0};
   char documents_dir_buf[DIR_MAX_LENGTH]  = {0};
   char application_data[PATH_MAX_LENGTH]  = {0};
   CFBundleRef bundle                      = CFBundleGetMainBundle();

   if (!bundle)
      return;

   bundle_url    = CFBundleCopyBundleURL(bundle);
   bundle_path   = CFURLCopyFileSystemPath(bundle_url, kCFURLPOSIXPathStyle);
   CFStringGetCString(bundle_path, bundle_path_buf, sizeof(bundle_path_buf), kCFStringEncodingUTF8);
   CFRelease(bundle_path);
   CFRelease(bundle_url);
   path_resolve_realpath(bundle_path_buf, sizeof(bundle_path_buf), true);

   CFSearchPathForDirectoriesInDomains(documents_dir_buf, sizeof(documents_dir_buf));
   path_resolve_realpath(documents_dir_buf, sizeof(documents_dir_buf), true);

   strlcpy(g_defaults.dirs[DEFAULT_DIR_BUNDLE_ROOT], bundle_path_buf,
         sizeof(g_defaults.dirs[DEFAULT_DIR_BUNDLE_ROOT]));
   strlcpy(g_defaults.dirs[DEFAULT_DIR_USER_DOCUMENT], documents_dir_buf, sizeof(g_defaults.dirs[DEFAULT_DIR_USER_DOCUMENT]));
   fill_pathname_join(g_defaults.dirs[DEFAULT_DIR_START], documents_dir_buf, "emu", sizeof(g_defaults.dirs[DEFAULT_DIR_START]));
   fill_pathname_join(g_defaults.dirs[DEFAULT_DIR_MAIN_CONFIG], g_defaults.dirs[DEFAULT_DIR_START], "config", sizeof(g_defaults.dirs[DEFAULT_DIR_MAIN_CONFIG]));
   fill_pathname_join(g_defaults.dirs[DEFAULT_DIR_REMAP], g_defaults.dirs[DEFAULT_DIR_MAIN_CONFIG], "remaps", sizeof(g_defaults.dirs[DEFAULT_DIR_REMAP]));
   fill_pathname_join(g_defaults.dirs[DEFAULT_DIR_AUTOCONFIG], bundle_path_buf, "Data/autoconfig", sizeof(g_defaults.dirs[DEFAULT_DIR_AUTOCONFIG]));
   fill_pathname_join(g_defaults.dirs[DEFAULT_DIR_AUDIO_FILTER], bundle_path_buf, "Data/filters/audio", sizeof(g_defaults.dirs[DEFAULT_DIR_AUDIO_FILTER]));
   fill_pathname_join(g_defaults.dirs[DEFAULT_DIR_VIDEO_FILTER], bundle_path_buf, "Data/filters/video", sizeof(g_defaults.dirs[DEFAULT_DIR_VIDEO_FILTER]));
   fill_pathname_join(g_defaults.dirs[DEFAULT_DIR_ASSETS], bundle_path_buf, "Data/assets", sizeof(g_defaults.dirs[DEFAULT_DIR_ASSETS]));
   fill_pathname_join(g_defaults.dirs[DEFAULT_DIR_CORE_INFO], bundle_path_buf, "Data/info", sizeof(g_defaults.dirs[DEFAULT_DIR_CORE_INFO]));
   fill_pathname_join(g_defaults.dirs[DEFAULT_DIR_OVERLAY], bundle_path_buf, "Data/overlays", sizeof(g_defaults.dirs[DEFAULT_DIR_OVERLAY]));
   fill_pathname_join(g_defaults.dirs[DEFAULT_DIR_OSK_OVERLAY], g_defaults.dirs[DEFAULT_DIR_OVERLAY], "retroarch/keyboards", sizeof(g_defaults.dirs[DEFAULT_DIR_OSK_OVERLAY]));
   fill_pathname_join(g_defaults.dirs[DEFAULT_DIR_SHADER], bundle_path_buf, "Data/shaders", sizeof(g_defaults.dirs[DEFAULT_DIR_SHADER]));
   fill_pathname_join(g_defaults.dirs[DEFAULT_DIR_USER_SHADER], g_defaults.dirs[DEFAULT_DIR_MAIN_CONFIG], "shader", sizeof(g_defaults.dirs[DEFAULT_DIR_USER_SHADER]));
   fill_pathname_join(g_defaults.dirs[DEFAULT_DIR_SAVESTATE], g_defaults.dirs[DEFAULT_DIR_START], "states", sizeof(g_defaults.dirs[DEFAULT_DIR_SAVESTATE]));
   fill_pathname_join(g_defaults.dirs[DEFAULT_DIR_SRAM], g_defaults.dirs[DEFAULT_DIR_START], "saves", sizeof(g_defaults.dirs[DEFAULT_DIR_SRAM]));
   fill_pathname_join(g_defaults.dirs[DEFAULT_DIR_SCREENSHOT], g_defaults.dirs[DEFAULT_DIR_START], "screenshots", sizeof(g_defaults.dirs[DEFAULT_DIR_SCREENSHOT]));
   fill_pathname_join(g_defaults.dirs[DEFAULT_DIR_PLAYLIST], g_defaults.dirs[DEFAULT_DIR_START], "playlists", sizeof(g_defaults.dirs[DEFAULT_DIR_PLAYLIST]));
   fill_pathname_join(g_defaults.dirs[DEFAULT_DIR_THUMBNAILS], g_defaults.dirs[DEFAULT_DIR_START], "thumbnails", sizeof(g_defaults.dirs[DEFAULT_DIR_THUMBNAILS]));
   fill_pathname_join(g_defaults.dirs[DEFAULT_DIR_DATABASE], bundle_path_buf, "Data/rdb", sizeof(g_defaults.dirs[DEFAULT_DIR_DATABASE]));
   fill_pathname_join(g_defaults.dirs[DEFAULT_DIR_CHEATS], bundle_path_buf, "Data/cht", sizeof(g_defaults.dirs[DEFAULT_DIR_CHEATS]));
   fill_pathname_join(g_defaults.dirs[DEFAULT_DIR_RECORD_CONFIG], g_defaults.dirs[DEFAULT_DIR_MAIN_CONFIG], "records", sizeof(g_defaults.dirs[DEFAULT_DIR_RECORD_CONFIG]));
   fill_pathname_join(g_defaults.dirs[DEFAULT_DIR_RECORD_OUTPUT], g_defaults.dirs[DEFAULT_DIR_START], "records", sizeof(g_defaults.dirs[DEFAULT_DIR_RECORD_OUTPUT]));
   fill_pathname_join(g_defaults.dirs[DEFAULT_DIR_LOGS], g_defaults.dirs[DEFAULT_DIR_START], "logs", sizeof(g_defaults.dirs[DEFAULT_DIR_LOGS]));

#if CORE_IN_FRAMEWORKS
   fill_pathname_join(g_defaults.dirs[DEFAULT_DIR_CORE], bundle_path_buf, "Frameworks", sizeof(g_defaults.dirs[DEFAULT_DIR_CORE]));
#else
   fill_pathname_join(g_defaults.dirs[DEFAULT_DIR_CORE], bundle_path_buf, "Data/cores", sizeof(g_defaults.dirs[DEFAULT_DIR_CORE]));
#endif

   CFTemporaryDirectory(temp_dir, sizeof(temp_dir));
   strlcpy(g_defaults.dirs[DEFAULT_DIR_CACHE],
         temp_dir,
         sizeof(g_defaults.dirs[DEFAULT_DIR_CACHE]));

   if (!path_is_directory(g_defaults.dirs[DEFAULT_DIR_MAIN_CONFIG]))
      path_mkdir(g_defaults.dirs[DEFAULT_DIR_MAIN_CONFIG]);
}

static int frontend_darwin_get_rating(void)
{
   char model[PATH_MAX_LENGTH] = {0};

   frontend_darwin_get_name(model, sizeof(model));

   /* iPhone 4 */
#if 0
   if (strstr(model, "iPhone3"))
      return -1;
#endif

   /* iPad 1 */
#if 0
   if (strstr(model, "iPad1,1"))
      return -1;
#endif

   /* iPhone 4S */
   if (strstr(model, "iPhone4,1"))
      return 8;

   /* iPad 2/iPad Mini 1 */
   if (strstr(model, "iPad2"))
      return 9;

   /* iPhone 5/5C */
   if (strstr(model, "iPhone5"))
      return 13;

   /* iPhone 5S */
   if (strstr(model, "iPhone6,1") || strstr(model, "iPhone6,2"))
      return 14;

   /* iPad Mini 2/3 */
   if (     strstr(model, "iPad4,4")
         || strstr(model, "iPad4,5")
         || strstr(model, "iPad4,6")
         || strstr(model, "iPad4,7")
         || strstr(model, "iPad4,8")
         || strstr(model, "iPad4,9")
      )
      return 15;

   /* iPad Air */
   if (     strstr(model, "iPad4,1")
         || strstr(model, "iPad4,2")
         || strstr(model, "iPad4,3")
      )
      return 16;

   /* iPhone 6, iPhone 6 Plus */
   if (strstr(model, "iPhone7"))
      return 17;

   /* iPad Air 2 */
   if (strstr(model, "iPad5,3") || strstr(model, "iPad5,4"))
      return 18;

   /* iPad Pro (12.9 Inch) */
   if (strstr(model, "iPad6,7") || strstr(model, "iPad6,8"))
     return 19;

   /* iPad Pro (9.7 Inch) */
   if (strstr(model, "iPad6,3") || strstr(model, "iPad6,4"))
     return 19;

   /* iPad 5th Generation */
   if (strstr(model, "iPad6,11") || strstr(model, "iPad6,12"))
     return 19;

   /* iPad Pro (12.9 Inch 2nd Generation) */
   if (strstr(model, "iPad7,1") || strstr(model, "iPad7,2"))
     return 19;

   /* iPad Pro (10.5 Inch) */
   if (strstr(model, "iPad7,3") || strstr(model, "iPad7,4"))
     return 19;

   /* iPad Pro 6th Generation) */
   if (strstr(model, "iPad7,5") || strstr(model, "iPad7,6"))
     return 19;

   /* iPad Pro (11 Inch) */
   if (     strstr(model, "iPad8,1")
         || strstr(model, "iPad8,2")
         || strstr(model, "iPad8,3")
         || strstr(model, "iPad8,4")
      )
      return 19;

   /* iPad Pro (12.9 3rd Generation) */
    if (   strstr(model, "iPad8,5")
        || strstr(model, "iPad8,6")
        || strstr(model, "iPad8,7")
        || strstr(model, "iPad8,8")
       )
       return 19;

   /* iPad Air 3rd Generation) */
    if (   strstr(model, "iPad11,3")
        || strstr(model, "iPad11,4"))
       return 19;

   /* TODO/FIXME -
      - more ratings for more systems
      - determine rating more intelligently*/
   return -1;
}

static enum frontend_powerstate frontend_darwin_get_powerstate(
      int *seconds, int *percent)
{
   enum frontend_powerstate ret = FRONTEND_POWERSTATE_NONE;
   float level;
   UIDevice *uidev = [UIDevice currentDevice];
   if (uidev)
   {
      [uidev setBatteryMonitoringEnabled:true];

      switch (uidev.batteryState)
      {
         case UIDeviceBatteryStateCharging:
            ret = FRONTEND_POWERSTATE_CHARGING;
            break;
         case UIDeviceBatteryStateFull:
            ret = FRONTEND_POWERSTATE_CHARGED;
            break;
         case UIDeviceBatteryStateUnplugged:
            ret = FRONTEND_POWERSTATE_ON_POWER_SOURCE;
            break;
         case UIDeviceBatteryStateUnknown:
            break;
      }

      level = uidev.batteryLevel;

      *percent = ((level < 0.0f) ? -1 : ((int)((level * 100) + 0.5f)));

      [uidev setBatteryMonitoringEnabled:false];
   }
   return ret;
}

#ifndef OSX
#ifndef CPU_ARCH_ABI64
#define CPU_ARCH_ABI64          0x01000000
#endif

#ifndef CPU_TYPE_ARM64
#define CPU_TYPE_ARM64          (CPU_TYPE_ARM | CPU_ARCH_ABI64)
#endif
#endif

static enum frontend_architecture frontend_darwin_get_arch(void)
{
   cpu_type_t type;
   size_t _len = sizeof(type);
   sysctlbyname("hw.cputype", &type, &_len, NULL, 0);
   if (type == CPU_TYPE_X86_64)
      return FRONTEND_ARCH_X86_64;
   else if (type == CPU_TYPE_X86)
      return FRONTEND_ARCH_X86;
   else if (type == CPU_TYPE_ARM64)
      return FRONTEND_ARCH_ARMV8;
   else if (type == CPU_TYPE_ARM)
      return FRONTEND_ARCH_ARMV7;
    return FRONTEND_ARCH_NONE;
}

static int frontend_darwin_parse_drive_list(void *data, bool load_content)
{
   int ret = -1;
   return ret;
}

static uint64_t frontend_darwin_get_total_mem(void)
{
    task_vm_info_data_t vm_info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t) &vm_info, &count) == KERN_SUCCESS)
       return vm_info.phys_footprint + vm_info.limit_bytes_remaining;
    return 0;
}

static uint64_t frontend_darwin_get_free_mem(void)
{
    task_vm_info_data_t vm_info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t) &vm_info, &count) == KERN_SUCCESS)
        return vm_info.limit_bytes_remaining;
    return 0;
}

static const char* frontend_darwin_get_cpu_model_name(void)
{
   cpu_features_get_model_name(darwin_cpu_model_name,
         sizeof(darwin_cpu_model_name));
   return darwin_cpu_model_name;
}

static enum retro_language frontend_darwin_get_user_language(void)
{
   char s[128];
   CFArrayRef langs = CFLocaleCopyPreferredLanguages();
   CFStringRef langCode = CFArrayGetValueAtIndex(langs, 0);
   CFStringGetCString(langCode, s, sizeof(s), kCFStringEncodingUTF8);
   /* iOS and OS X only support the language ID syntax consisting
    * of a language designator and optional region or script designator. */
   string_replace_all_chars(s, '-', '_');
   return retroarch_get_language_from_iso(s);
}

static bool frontend_darwin_is_narrator_running(void)
{
   if (@available(macOS 10.14, iOS 7, tvOS 9, *))
      return true;
   return false;
}

static bool frontend_darwin_accessibility_speak(int speed,
      const char* speak_text, int priority)
{
   if (speed < 1)
      speed               = 1;
   else if (speed > 10)
      speed               = 10;

   if (@available(macOS 10.14, iOS 7, tvOS 9, *))
   {
      static dispatch_once_t once;
      static AVSpeechSynthesizer *synth;
      dispatch_once(&once, ^{
         synth = [[AVSpeechSynthesizer alloc] init];
      });
      if ([synth isSpeaking])
      {
         if (priority < 10)
            return true;
         else
            [synth stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
      }

      AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:[NSString stringWithUTF8String:speak_text]];
      if (!utterance)
         return false;
      utterance.rate = (float)speed / 10.0f;
      const char *language = get_user_language_iso639_1(false);
      utterance.voice = [AVSpeechSynthesisVoice voiceWithLanguage:[NSString stringWithUTF8String:language]];
      [synth speakUtterance:utterance];
      return true;
   }

#if defined(OSX)
   return accessibility_speak_macos(speed, speak_text, priority);
#else
   return false;
#endif
}

frontend_ctx_driver_t frontend_ctx_darwin = {
   frontend_darwin_get_env,         /* get_env */
   NULL,                            /* init */
   NULL,                            /* deinit */
   NULL,                            /* exitspawn */
   NULL,                            /* process_args */
   NULL,                            /* exec */
   NULL,                            /* set_fork */
   NULL,                            /* shutdown */
   frontend_darwin_get_name,        /* get_name */
   frontend_darwin_get_os,          /* get_os               */
   frontend_darwin_get_rating,      /* get_rating           */
   NULL,                            /* content_loaded       */
   frontend_darwin_get_arch,        /* get_architecture     */
   frontend_darwin_get_powerstate,  /* get_powerstate       */
   frontend_darwin_parse_drive_list,/* parse_drive_list     */
   frontend_darwin_get_total_mem,   /* get_total_mem        */
   frontend_darwin_get_free_mem,    /* get_free_mem         */
   NULL,                            /* install_signal_handler */
   NULL,                            /* get_sighandler_state */
   NULL,                            /* set_sighandler_state */
   NULL,                            /* destroy_signal_handler_state */
   NULL,                            /* attach_console */
   NULL,                            /* detach_console */
   NULL,                            /* get_lakka_version */
   NULL,                            /* set_screen_brightness */
   NULL,                            /* watch_path_for_changes */
   NULL,                            /* check_for_path_changes */
   NULL,                            /* set_sustained_performance_mode */
   frontend_darwin_get_cpu_model_name, /* get_cpu_model_name */
   frontend_darwin_get_user_language, /* get_user_language   */
   frontend_darwin_is_narrator_running, /* is_narrator_running */
   frontend_darwin_accessibility_speak, /* accessibility_speak */
   NULL,                            /* set_gamemode        */
   "darwin",                        /* ident               */
    NULL                            /* get_video_driver    */
};
