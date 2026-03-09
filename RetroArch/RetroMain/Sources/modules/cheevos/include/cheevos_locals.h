/*  RetroArch - A frontend for libretro.
 *  Copyright (C) 2015-2018 - Andre Leiradella
 *  Copyright (C) 2019-2023 - Brian Weiss
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

#ifndef __RARCH_CHEEVOS_LOCALS_H
#define __RARCH_CHEEVOS_LOCALS_H

#include "rc_client.h"
#include "rc_runtime.h"
#include "rc_libretro.h"

#include <boolean.h>
#include <queues/task_queue.h>

#ifdef HAVE_THREADS
#include <rthreads/rthreads.h>
#endif

#include <retro_common_api.h>
#include <utils/verbosity.h>
#include <defines/command_defines.h>

#include <intl/msg_hash.h>

RETRO_BEGIN_DECLS

/************************************************************************
 * Logging                                                              *
 ************************************************************************/

/* Define this macro to get extra-verbose log for cheevos. */
#define CHEEVOS_VERBOSE

#define RCHEEVOS_TAG "[RCHEEVOS] "
#define CHEEVOS_FREE(p) do { void* q = (void*)p; if (q) free(q); } while (0)

#ifdef CHEEVOS_VERBOSE
 #define CHEEVOS_LOG RARCH_LOG
 #define CHEEVOS_ERR RARCH_ERR
#else
 void rcheevos_log(const char *fmt, ...);
 #define CHEEVOS_LOG rcheevos_log
 #define CHEEVOS_ERR RARCH_ERR
#endif

/************************************************************************
 * State                                                                *
 ************************************************************************/

enum rcheevos_summary_notif
{
   RCHEEVOS_SUMMARY_ALLGAMES = 0,
   RCHEEVOS_SUMMARY_HASCHEEVOS,
   RCHEEVOS_SUMMARY_OFF,
   RCHEEVOS_SUMMARY_LAST
};

typedef struct rcheevos_locals_t
{
   rc_client_t* client;               /* rcheevos client state */
   rc_libretro_memory_regions_t memory;/* achievement addresses to core memory mappings */

#ifdef HAVE_THREADS
   enum event_command queued_command; /* action queued by background thread to be run on main thread */
#endif

   char user_agent_prefix[128];       /* RetroArch/OS version information */
   char user_agent_core[256];         /* RetroArch/OS/Core version information */

   bool hardcore_allowed;             /* prevents enabling hardcore if illegal settings detected */
   bool hardcore_being_enabled;       /* allows callers to detect hardcore mode while it's being enabled */

   bool core_supports;                /* false if core explicitly disables achievements */
} rcheevos_locals_t;

rcheevos_locals_t* get_rcheevos_locals(void);

RETRO_END_DECLS

#endif /* __RARCH_CHEEVOS_LOCALS_H */
