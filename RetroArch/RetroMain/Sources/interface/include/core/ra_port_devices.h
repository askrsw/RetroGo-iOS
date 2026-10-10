#ifndef RA_PORT_DEVICES_H
#define RA_PORT_DEVICES_H

#include <retro_common_api.h>

RETRO_BEGIN_DECLS

struct retro_controller_info;

/* RetroGo has no RetroArch menu to choose a port's device type, so the game
 * config names it instead: the device whose description contains `name`
 * (case-insensitive), e.g. "dualshock", for every port. NULL or "" keeps the
 * standard RetroPad. Copied; read by the next CMD_EVENT_CONTROLLER_INIT. */
void ra_port_devices_set_preferred(const char *name);

/* For a core port mapped to `device`: the id of the preferred device when the
 * core lists one for this port (`info` from SET_CONTROLLER_INFO), else `device`. */
unsigned ra_port_devices_resolve(const struct retro_controller_info *info,
      unsigned device);

RETRO_END_DECLS

#endif
