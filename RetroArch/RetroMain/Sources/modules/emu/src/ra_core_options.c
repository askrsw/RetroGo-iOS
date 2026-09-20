#include <core/ra_core_options.h>
#include <core/core_option_manager.h>
#include <main/runloop.h>
#include <lists/string_list.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct ra_option_pair { char *key; char *value; };
static pthread_mutex_t snapshot_lock = PTHREAD_MUTEX_INITIALIZER;
static struct ra_option_pair *snapshot;
static size_t snapshot_count;
static bool snapshot_enabled;
/* Live updates waiting for the game thread; guarded by snapshot_lock. */
static struct ra_option_pair *pending;
static size_t pending_count;
static atomic_bool has_pending;

static void free_pairs(struct ra_option_pair *pairs, size_t count)
{
   size_t i;
   for (i = 0; i < count; i++) { free(pairs[i].key); free(pairs[i].value); }
   free(pairs);
}

bool ra_core_options_set(const char *const *keys, const char *const *values,
      size_t count, bool enabled)
{
   size_t i;
   struct ra_option_pair *copy = NULL;
   if (!enabled) count = 0;
   if (count)
   {
      if (!keys || !values || !(copy = calloc(count, sizeof(*copy))))
         goto failure;
      for (i = 0; i < count; i++)
         if (!keys[i] || !values[i] ||
             !(copy[i].key = strdup(keys[i])) ||
             !(copy[i].value = strdup(values[i])))
            goto failure;
   }
   pthread_mutex_lock(&snapshot_lock);
   free_pairs(snapshot, snapshot_count);
   snapshot = copy;
   snapshot_count = count;
   snapshot_enabled = enabled;
   free_pairs(pending, pending_count);
   pending = NULL;
   pending_count = 0;
   atomic_store(&has_pending, false);
   pthread_mutex_unlock(&snapshot_lock);
   return true;
failure:
   if (copy) free_pairs(copy, count);
   ra_core_options_clear();
   return false;
}

void ra_core_options_clear(void) { ra_core_options_set(NULL, NULL, 0, false); }

bool ra_core_options_enabled(void)
{
   bool enabled;
   pthread_mutex_lock(&snapshot_lock);
   enabled = snapshot_enabled;
   pthread_mutex_unlock(&snapshot_lock);
   return enabled;
}

void ra_core_options_apply(struct core_option_manager *manager)
{
   size_t i, j, k;
   if (!manager) return;
   pthread_mutex_lock(&snapshot_lock);
   if (snapshot_enabled)
   {
      for (i = 0; i < manager->size; i++)
      {
         struct core_option *option = &manager->opts[i];
         if (!option->key || !option->vals || !option->vals->size) continue;
         option->index = option->default_index < option->vals->size ? option->default_index : 0;
         for (j = 0; j < snapshot_count; j++)
         {
            if (strcmp(option->key, snapshot[j].key)) continue;
            for (k = 0; k < option->vals->size; k++)
               if (!strcmp(option->vals->elems[k].data, snapshot[j].value))
               {
                  option->index = k;
                  break;
               }
            break;
         }
      }
      /* Apply the whole initial snapshot without invoking core callbacks while
       * registration is still in progress. GET_VARIABLE_UPDATE observes it. */
      manager->updated = true;
   }
   pthread_mutex_unlock(&snapshot_lock);
}

/* Replaces or appends key=value; caller holds snapshot_lock. */
static bool upsert_pair(struct ra_option_pair **pairs, size_t *count,
      const char *key, const char *value)
{
   size_t i;
   char *copy;
   struct ra_option_pair *grown;
   for (i = 0; i < *count; i++)
   {
      if (strcmp((*pairs)[i].key, key)) continue;
      if (!(copy = strdup(value))) return false;
      free((*pairs)[i].value);
      (*pairs)[i].value = copy;
      return true;
   }
   if (!(grown = realloc(*pairs, (*count + 1) * sizeof(**pairs)))) return false;
   *pairs = grown;
   grown[*count].key = strdup(key);
   grown[*count].value = strdup(value);
   if (!grown[*count].key || !grown[*count].value)
   {
      free(grown[*count].key);
      free(grown[*count].value);
      return false;
   }
   (*count)++;
   return true;
}

bool ra_core_options_queue_update(const char *key, const char *value)
{
   bool ok;
   if (!key || !value) return false;
   pthread_mutex_lock(&snapshot_lock);
   /* The snapshot keeps the value if the core re-registers its options. */
   ok = snapshot_enabled
      && upsert_pair(&snapshot, &snapshot_count, key, value)
      && upsert_pair(&pending, &pending_count, key, value);
   if (ok) atomic_store(&has_pending, true);
   pthread_mutex_unlock(&snapshot_lock);
   return ok;
}

void ra_core_options_apply_pending(void)
{
   size_t i, idx, k, count;
   struct ra_option_pair *pairs;
   core_option_manager_t *manager;
   if (!atomic_load(&has_pending)) return;

   pthread_mutex_lock(&snapshot_lock);
   pairs = pending;
   count = pending_count;
   pending = NULL;
   pending_count = 0;
   atomic_store(&has_pending, false);
   pthread_mutex_unlock(&snapshot_lock);

   manager = runloop_state_get_ptr()->core_options;
   for (i = 0; manager && i < count; i++)
   {
      struct core_option *option;
      if (!core_option_manager_get_idx(manager, pairs[i].key, &idx)) continue;
      option = &manager->opts[idx];
      for (k = 0; option->vals && k < option->vals->size; k++)
      {
         if (strcmp(option->vals->elems[k].data, pairs[i].value)) continue;
         /* Sets manager->updated; the core re-reads on GET_VARIABLE_UPDATE. */
         if (option->index != k)
            core_option_manager_set_val(manager, idx, k, false);
         break;
      }
   }
   free_pairs(pairs, count);
}
