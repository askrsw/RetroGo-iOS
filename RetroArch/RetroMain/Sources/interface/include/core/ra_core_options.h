#ifndef RA_CORE_OPTIONS_H
#define RA_CORE_OPTIONS_H

#include <stdbool.h>
#include <stddef.h>

#include <retro_common_api.h>

RETRO_BEGIN_DECLS

struct core_option_manager;
/* Copies immutable launch values. NULL/0 with enabled=true means defaults only. */
bool ra_core_options_set(const char *const *keys, const char *const *values,
      size_t count, bool enabled);
void ra_core_options_clear(void);
bool ra_core_options_enabled(void);
void ra_core_options_apply(struct core_option_manager *manager);
/* Live change while a game runs: records key=value in the launch snapshot and
 * queues it for the running core. Returns false if options are not managed. */
bool ra_core_options_queue_update(const char *key, const char *value);
/* Game thread only, before each frame: pushes queued values into the running
 * core's option manager so the core sees them via GET_VARIABLE_UPDATE. */
void ra_core_options_apply_pending(void);

RETRO_END_DECLS

#endif
