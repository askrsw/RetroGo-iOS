/*  RetroGo unified logging for C and Objective-C.
 *
 *  Thin wrapper over Apple's unified logging (os_log). Every message goes to
 *  subsystem = main bundle identifier, with a per-module category, so logs can
 *  be filtered in Console.app by subsystem / category / level.
 *
 *  Usage:
 *     RETROGO_LOG(RETROGO_LOG_CAT_RETROARCH, RETROGO_LOG_INFO, "Loaded core %{public}s", core_id);
 *     RETROGO_LOGI(RETROARCH, "Loaded core %{public}s", core_id);   // shorthand
 *
 *  Privacy: dynamic strings are private by default (os_log rules). Mark core
 *  IDs, error codes and similar non-user data with %{public}s / %{public}d.
 *  User file names and paths must stay private.
 */

#ifndef __RETROGO_LOG_H
#define __RETROGO_LOG_H

#include <os/log.h>
#include <retro_common_api.h>

RETRO_BEGIN_DECLS

typedef enum retrogo_log_category
{
   RETROGO_LOG_CAT_GENERAL = 0,
   RETROGO_LOG_CAT_IMPORT,
   RETROGO_LOG_CAT_LIBRARY,
   RETROGO_LOG_CAT_CHEAT,
   RETROGO_LOG_CAT_MAME,
   RETROGO_LOG_CAT_IAP,
   RETROGO_LOG_CAT_ODR,
   RETROGO_LOG_CAT_GAME,
   RETROGO_LOG_CAT_RUNNER,
   RETROGO_LOG_CAT_CORE_OPTION,
   RETROGO_LOG_CAT_DATABASE,
   RETROGO_LOG_CAT_NETPLAY,
   RETROGO_LOG_CAT_RETROARCH,
   RETROGO_LOG_CAT_CORE,
   RETROGO_LOG_CAT_COUNT
} retrogo_log_category_t;

/* Level aliases; NOTICE maps to os_log's default level. */
#define RETROGO_LOG_DEBUG  OS_LOG_TYPE_DEBUG
#define RETROGO_LOG_INFO   OS_LOG_TYPE_INFO
#define RETROGO_LOG_NOTICE OS_LOG_TYPE_DEFAULT
#define RETROGO_LOG_ERROR  OS_LOG_TYPE_ERROR
#define RETROGO_LOG_FAULT  OS_LOG_TYPE_FAULT

/* Returns the cached os_log_t for a category. Thread-safe. */
os_log_t retrogo_log_handle(retrogo_log_category_t category);

/* fmt must be a string literal (os_log requirement). */
#define RETROGO_LOG(category, level, fmt, ...) \
   os_log_with_type(retrogo_log_handle(category), (level), fmt, ##__VA_ARGS__)

/* Shorthands: category is the RETROGO_LOG_CAT_ suffix, e.g. RETROGO_LOGE(MAME, "..."). */
#define RETROGO_LOGD(cat, fmt, ...) RETROGO_LOG(RETROGO_LOG_CAT_##cat, RETROGO_LOG_DEBUG,  fmt, ##__VA_ARGS__)
#define RETROGO_LOGI(cat, fmt, ...) RETROGO_LOG(RETROGO_LOG_CAT_##cat, RETROGO_LOG_INFO,   fmt, ##__VA_ARGS__)
#define RETROGO_LOGN(cat, fmt, ...) RETROGO_LOG(RETROGO_LOG_CAT_##cat, RETROGO_LOG_NOTICE, fmt, ##__VA_ARGS__)
#define RETROGO_LOGE(cat, fmt, ...) RETROGO_LOG(RETROGO_LOG_CAT_##cat, RETROGO_LOG_ERROR,  fmt, ##__VA_ARGS__)
#define RETROGO_LOGF(cat, fmt, ...) RETROGO_LOG(RETROGO_LOG_CAT_##cat, RETROGO_LOG_FAULT,  fmt, ##__VA_ARGS__)

RETRO_END_DECLS

#endif /* __RETROGO_LOG_H */
