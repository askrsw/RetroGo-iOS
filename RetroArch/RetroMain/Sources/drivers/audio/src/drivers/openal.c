/*  RetroArch - A frontend for libretro.
 *  Copyright (C) 2010-2014 - Hans-Kristian Arntzen
 *  Copyright (C) 2011-2017 - Daniel De Matteis
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

#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifdef __APPLE__
#include <OpenAL/al.h>
#include <OpenAL/alc.h>
#else
#include <AL/al.h>
#include <AL/alc.h>
#endif

#ifdef _WIN32
#include <windows.h>
#endif

#include <retro_miscellaneous.h>
#include <retro_timers.h>

#include <audio/audio_driver.h>
#include <utils/verbosity.h>

#define OPENAL_BUFSIZE 1024
#define OPENAL_RING_BLOCKS 32

typedef struct al
{
   ALuint source;
   ALuint *buffers;
   ALuint *res_buf;
   ALCdevice *handle;
   ALCcontext *ctx;
   size_t res_ptr;
   ALsizei num_buffers;
   uint8_t *ringbuf;
   size_t ringbuf_size;
   size_t ringbuf_read;
   size_t ringbuf_write;
   size_t ringbuf_fill;
   int rate;
   ALenum format;
   uint8_t tmpbuf[OPENAL_BUFSIZE];
   retro_time_t stats_start_time;
   uint64_t dropped_blocks;
   uint64_t dropped_bytes;
   float playback_speed;
   bool nonblock;
   bool is_paused;
} al_t;

static size_t al_ring_write_avail(const al_t *al)
{
   return al->ringbuf_size - al->ringbuf_fill;
}

static size_t al_ring_read_avail(const al_t *al)
{
   return al->ringbuf_fill;
}

static void al_ring_write(al_t *al, const uint8_t *src, size_t len)
{
   size_t first = MIN(len, al->ringbuf_size - al->ringbuf_write);
   memcpy(al->ringbuf + al->ringbuf_write, src, first);

   if (len > first)
      memcpy(al->ringbuf, src + first, len - first);

   al->ringbuf_write = (al->ringbuf_write + len) % al->ringbuf_size;
   al->ringbuf_fill += len;
}

static void al_ring_read(al_t *al, uint8_t *dst, size_t len)
{
   size_t first = MIN(len, al->ringbuf_size - al->ringbuf_read);
   memcpy(dst, al->ringbuf + al->ringbuf_read, first);

   if (len > first)
      memcpy(dst + first, al->ringbuf, len - first);

   al->ringbuf_read = (al->ringbuf_read + len) % al->ringbuf_size;
   al->ringbuf_fill -= len;
}

static void al_ring_drop_oldest(al_t *al, size_t len)
{
   len = MIN(len, al->ringbuf_fill);
   al->ringbuf_read = (al->ringbuf_read + len) % al->ringbuf_size;
   al->ringbuf_fill -= len;
}

static void al_log_drop_stats(al_t *al)
{
   retro_time_t now;

   if (!al)
      return;

   now = cpu_features_get_time_usec();

   if (al->stats_start_time == 0)
   {
      al->stats_start_time = now;
      return;
   }

   if ((now - al->stats_start_time) < (retro_time_t)60000000)
      return;

   RARCH_LOG("[OpenAL] drop_stats interval=60s dropped_blocks=%llu dropped_bytes=%llu ring_fill=%u/%u nonblock=%s\n",
         (unsigned long long)al->dropped_blocks,
         (unsigned long long)al->dropped_bytes,
         (unsigned)al->ringbuf_fill,
         (unsigned)al->ringbuf_size,
         al->nonblock ? "true" : "false");

   al->stats_start_time = now;
   al->dropped_blocks   = 0;
   al->dropped_bytes    = 0;
}

static void al_free(void *data)
{
   al_t *al = (al_t*)data;

   if (!al)
      return;

   alSourceStop(al->source);
   alDeleteSources(1, &al->source);

   if (al->buffers)
      alDeleteBuffers(al->num_buffers, al->buffers);

   free(al->buffers);
   free(al->res_buf);
   free(al->ringbuf);
   alcMakeContextCurrent(NULL);

   if (al->ctx)
      alcDestroyContext(al->ctx);
   if (al->handle)
      alcCloseDevice(al->handle);
   free(al);
}

static void *al_init(const char *device, unsigned rate, unsigned latency,
      unsigned block_frames,
      unsigned *new_rate)
{
   al_t *al;

   (void)device;

   al = (al_t*)calloc(1, sizeof(al_t));
   if (!al)
      return NULL;

   al->handle = alcOpenDevice(NULL);
   if (!al->handle)
      goto error;

   al->ctx = alcCreateContext(al->handle, NULL);
   if (!al->ctx)
      goto error;

   alcMakeContextCurrent(al->ctx);

   al->rate = rate;
   al->playback_speed = 1.0f;

   /* We already use one buffer for tmpbuf. */
   al->num_buffers = (latency * rate * 2 * sizeof(int16_t)) / (1000 * OPENAL_BUFSIZE) - 1;
   if (al->num_buffers < 2)
      al->num_buffers = 2;

   RARCH_LOG("[OpenAL] Using %u buffers of %u bytes.\n", (unsigned)al->num_buffers, OPENAL_BUFSIZE);

   al->buffers = (ALuint*)calloc(al->num_buffers, sizeof(ALuint));
   al->res_buf = (ALuint*)calloc(al->num_buffers, sizeof(ALuint));
   al->ringbuf_size = OPENAL_BUFSIZE * OPENAL_RING_BLOCKS;
   al->ringbuf = (uint8_t*)calloc(al->ringbuf_size, sizeof(uint8_t));
   if (!al->buffers || !al->res_buf || !al->ringbuf)
      goto error;

   alGenSources(1, &al->source);
   alGenBuffers(al->num_buffers, al->buffers);

   memcpy(al->res_buf, al->buffers, al->num_buffers * sizeof(ALuint));
   al->res_ptr = al->num_buffers;

   return al;

error:
   al_free(al);
   return NULL;
}

static bool al_unqueue_buffers(al_t *al)
{
   ALint val;

   alGetSourcei(al->source, AL_BUFFERS_PROCESSED, &val);

   if (val <= 0)
      return false;

   alSourceUnqueueBuffers(al->source, val, &al->res_buf[al->res_ptr]);
   al->res_ptr += val;
   return true;
}

static bool al_get_buffer(al_t *al, ALuint *buffer)
{
   if (!al->res_ptr)
   {
      for (;;)
      {
         if (al_unqueue_buffers(al))
            break;

         if (al->nonblock)
            return false;

         /* Must sleep as there is no proper blocking method. */
         retro_sleep(1);
      }
   }

   *buffer = al->res_buf[--al->res_ptr];
   return true;
}

static bool al_queue_from_ring(al_t *al)
{
   ALint source_state;
   ALuint buffer;

   if (al_ring_read_avail(al) < OPENAL_BUFSIZE)
      return false;

   if (!al_get_buffer(al, &buffer))
      return false;

   al_ring_read(al, al->tmpbuf, OPENAL_BUFSIZE);
   alBufferData(buffer, AL_FORMAT_STEREO16, al->tmpbuf, OPENAL_BUFSIZE, al->rate);
   alSourceQueueBuffers(al->source, 1, &buffer);

   if (alGetError() != AL_NO_ERROR)
      return false;

   alGetSourcei(al->source, AL_SOURCE_STATE, &source_state);
   if (source_state != AL_PLAYING)
   {
      alSourcePlay(al->source);
   }

   return alGetError() == AL_NO_ERROR;
}

static void al_drain_ring(al_t *al)
{
   while (al_ring_read_avail(al) >= OPENAL_BUFSIZE)
   {
      if (!al_queue_from_ring(al))
         break;
   }
}

static ssize_t al_write(void *data, const void *s, size_t len)
{
   al_t           *al = (al_t*)data;
   const uint8_t *buf = (const uint8_t*)s;
   size_t original_len = len;

   if (!al)
      return 0;

   /*
    * This driver-local ring buffer decouples libretro's push-style audio writes
    * from OpenAL's fixed-size queued buffers. The goal is to make the output
    * path behave more like the NES/OpenAL implementation: accumulate PCM in a
    * stable queue, then submit fixed-size blocks to OpenAL when buffers become
    * available.
    */
   while (len > 0)
   {
      size_t write_avail = al_ring_write_avail(al);

      if (write_avail == 0)
      {
         al_drain_ring(al);
         write_avail = al_ring_write_avail(al);
      }

      if (write_avail == 0)
      {
         if (al->nonblock)
         {
            /*
             * In fast/non-blocking mode, prefer the most recent audio. Drop one
             * fixed block from the head of the queue so new data can enter.
             */
            al_ring_drop_oldest(al, OPENAL_BUFSIZE);
            al->dropped_blocks++;
            al->dropped_bytes += OPENAL_BUFSIZE;
            write_avail = al_ring_write_avail(al);
         }
         else
         {
            retro_sleep(1);
            continue;
         }
      }

      {
         size_t to_write = MIN(len, write_avail);
         al_ring_write(al, buf, to_write);
         buf += to_write;
         len -= to_write;
      }

      al_drain_ring(al);
   }

   al_log_drop_stats(al);

   return original_len;
}

static bool al_stop(void *data)
{
   al_t *al = (al_t*)data;
   if (al)
      al->is_paused = true;
   return true;
}

static bool al_alive(void *data)
{
   al_t *al = (al_t*)data;
   if (!al)
      return false;
   return !al->is_paused;
}

static void al_set_nonblock_state(void *data, bool state)
{
   al_t *al = (al_t*)data;
   if (al)
      al->nonblock = state;
}

static bool al_start(void *data, bool is_shutdown)
{
   al_t *al = (al_t*)data;
   if (al)
   {
      al->is_paused = false;
   }
   return true;
}

static size_t al_write_avail(void *data)
{
   al_t *al = (al_t*)data;
   al_unqueue_buffers(al);
   al_drain_ring(al);
   return al_ring_write_avail(al);
}

static size_t al_buffer_size(void *data)
{
   al_t *al = (al_t*)data;
   return al ? al->ringbuf_size : 0;
}

static bool al_use_float(void *data) { return false; }

audio_driver_t audio_openal = {
   al_init,
   al_write,
   al_stop,
   al_start,
   al_alive,
   al_set_nonblock_state,
   al_free,
   al_use_float,
   "openal",
   NULL,
   NULL,
   al_write_avail,
   al_buffer_size,
};
