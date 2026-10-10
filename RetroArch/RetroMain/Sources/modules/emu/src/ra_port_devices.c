#include <core/ra_port_devices.h>
#include <libretro.h>
#include <pthread.h>
#include <ctype.h>
#include <string.h>

static pthread_mutex_t ra_port_devices_lock = PTHREAD_MUTEX_INITIALIZER;
static char ra_port_devices_preferred[64];

void ra_port_devices_set_preferred(const char *name)
{
   pthread_mutex_lock(&ra_port_devices_lock);
   if (name)
   {
      strncpy(ra_port_devices_preferred, name, sizeof(ra_port_devices_preferred) - 1);
      ra_port_devices_preferred[sizeof(ra_port_devices_preferred) - 1] = '\0';
   }
   else
      ra_port_devices_preferred[0] = '\0';
   pthread_mutex_unlock(&ra_port_devices_lock);
}

static bool ra_port_devices_contains(const char *haystack, const char *needle)
{
   size_t i, j;
   size_t needle_len = strlen(needle);

   for (i = 0; haystack[i]; i++)
   {
      for (j = 0; j < needle_len; j++)
      {
         if (!haystack[i + j])
            return false;
         if (tolower((unsigned char)haystack[i + j]) != tolower((unsigned char)needle[j]))
            break;
      }
      if (j == needle_len)
         return true;
   }
   return false;
}

unsigned ra_port_devices_resolve(const struct retro_controller_info *info,
      unsigned device)
{
   unsigned i;
   char preferred[sizeof(ra_port_devices_preferred)];

   /* An unmapped port stays disabled. */
   if (!info || !info->types || device == RETRO_DEVICE_NONE)
      return device;

   pthread_mutex_lock(&ra_port_devices_lock);
   memcpy(preferred, ra_port_devices_preferred, sizeof(preferred));
   pthread_mutex_unlock(&ra_port_devices_lock);

   if (!preferred[0])
      return device;

   for (i = 0; i < info->num_types; i++)
   {
      const char *desc = info->types[i].desc;
      if (desc && ra_port_devices_contains(desc, preferred))
         return info->types[i].id;
   }
   return device;
}
