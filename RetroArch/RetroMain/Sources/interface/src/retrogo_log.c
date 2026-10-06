/*  RetroGo unified logging, see utils/retrogo_log.h. */

#include <utils/retrogo_log.h>

#include <dispatch/dispatch.h>
#include <CoreFoundation/CoreFoundation.h>

/* Must match the Swift `Log` categories. */
static const char *const retrogo_log_category_names[RETROGO_LOG_CAT_COUNT] = {
   "General",
   "Import",
   "Library",
   "Cheat",
   "Mame",
   "IAP",
   "ODR",
   "Game",
   "Runner",
   "CoreOption",
   "Database",
   "Netplay",
   "RetroArch",
   "Core",
};

static os_log_t retrogo_log_handles[RETROGO_LOG_CAT_COUNT];

static void retrogo_log_init(void *ctx)
{
   char subsystem[256] = "com.retrogo";
   CFBundleRef bundle  = CFBundleGetMainBundle();
   CFStringRef ident   = bundle ? CFBundleGetIdentifier(bundle) : NULL;
   int i;

   (void)ctx;
   if (ident)
      CFStringGetCString(ident, subsystem, sizeof(subsystem), kCFStringEncodingUTF8);

   for (i = 0; i < RETROGO_LOG_CAT_COUNT; i++)
      retrogo_log_handles[i] = os_log_create(subsystem, retrogo_log_category_names[i]);
}

os_log_t retrogo_log_handle(retrogo_log_category_t category)
{
   static dispatch_once_t once;
   dispatch_once_f(&once, NULL, retrogo_log_init);

   if ((unsigned)category >= RETROGO_LOG_CAT_COUNT)
      category = RETROGO_LOG_CAT_GENERAL;
   return retrogo_log_handles[category];
}
