//
//  virtual_video_driver.m
//  RetroGo
//
//  Created by haharsw on 2026/4/10.
//  Copyright © 2026 haharsw. All rights reserved.
//
//  ---------------------------------------------------------------------------------
//  This file is part of RetroGo.
//  ---------------------------------------------------------------------------------
//
//  RetroGo is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  RetroGo is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

#import "virtual_video_driver.h"
#import <gfx/video_thread_wrapper.h>

#ifdef HAVE_OVERLAY
static void virtual_video_overlay_enable(void *ctx, bool state);
static bool virtual_video_overlay_load(void *ctx, const void *image_data, unsigned num_images);
static void virtual_video_overlay_tex_geom(void *ctx, unsigned idx, float x, float y, float w, float h);
static void virtual_video_overlay_vertex_geom(void *ctx, unsigned idx, float x, float y, float w, float h);
static void virtual_video_overlay_full_screen(void *ctx, bool enable);
static void virtual_video_overlay_set_alpha(void *ctx, unsigned idx, float mod);
#endif // HAVE_OVERLAY

static uint32_t virtual_video_get_flags(void *ctx);
static uintptr_t virtual_video_load_texture(void *ctx, void *data, bool threaded, enum texture_filter_type filter_type);
static void virtual_video_unload_texture(void *ctx, bool threaded, uintptr_t texture);
static void virtual_video_set_video_mode(void *ctx, unsigned width, unsigned height, bool video_fullscreen);
static void virtual_video_set_filtering(void *ctx, unsigned idx, bool smooth, bool ctx_scaling);
static void virtual_video_get_video_output_size(void *ctx, unsigned *width, unsigned *height, char *desc, size_t desc_len);
static void virtual_video_get_video_output_prev(void *ctx);
static void virtual_video_get_video_output_next(void *ctx);
static void virtual_video_set_aspect_ratio(void *ctx, unsigned aspect_ratio_idx);
static void virtual_video_apply_state_changes(void *ctx);
static void virtual_video_set_texture_frame(void *ctx, const void *frame, bool rgb32, unsigned width, unsigned height, float alpha);
static void virtual_video_set_texture_enable(void *ctx, bool state, bool full_screen);
static void virtual_video_set_osd_msg(void *ctx, const char *msg, const struct font_params *params, void *font);
static void virtual_video_show_mouse(void *ctx, bool state);
static void virtual_video_grab_mouse_toggle(void *ctx);
static struct video_shader *virtual_video_get_current_shader(void *ctx);
static void virtual_video_set_hdr_max_nits(void *ctx, float max_nits);
static void virtual_video_set_hdr_paper_white_nits(void *ctx, float paper_white_nits);
static void virtual_video_set_hdr_contrast(void *ctx, float contrast);
static void virtual_video_set_hdr_expand_gamut(void *ctx, bool expand_gamut);

NS_ASSUME_NONNULL_BEGIN

@implementation RAVirtualVideoDriver {
@public
    bool alive;
    const video_driver_t *driver;
    void *driver_data;

@private
    retro_time_t last_time;

    slock_t *lock;
    scond_t *cond_cmd;
    scond_t *cond_thread;

    video_info_t info;

#ifdef HAVE_OVERLAY
    const video_overlay_interface_t *overlay;
#endif
    const video_poke_interface_t *poke;

    input_driver_t **input;
    void **input_data;

    float *alpha_mod;
    slock_t *alpha_lock;

    struct {
        void *frame;
        size_t frame_cap;
        unsigned width;
        unsigned height;
        float alpha;
        bool frame_updated;
        bool rgb32;
        bool enable;
        bool full_screen;
    } texture;

    unsigned hit_count;
    unsigned miss_count;
    unsigned alpha_mods;

    struct video_viewport vp;
    struct video_viewport read_vp; /* Last viewport reported to caller. */

    thread_packet_t cmd_data;
    video_driver_t virtual_video;

    enum thread_cmd send_cmd;
    enum thread_cmd reply_cmd;
    bool alpha_update;

    struct {
        uint64_t count;
        slock_t *lock;
        uint8_t *buffer;
        unsigned width;
        unsigned height;
        unsigned pitch;
        char msg[NAME_MAX_LENGTH];
        bool updated;
        bool within_thread;
    } frame;

    bool apply_state_changes;


    bool focus;
    bool suppress_screensaver;
    bool has_windowed;
    bool nonblock;
    bool is_idle;

    const video_overlay_interface_t d_overlayInterface;
    const video_poke_interface_t    d_pokeInterface;
    CADisplayLink *d_displayLink;
}

- (instancetype)initWithVideoInfo:(const video_info_t)info input:(input_driver_t **)input inputData:(void **)inputData {
    self = [super init];
    if (self) {
        const video_overlay_interface_t overlayInterface = {
            virtual_video_overlay_enable,
            virtual_video_overlay_load,
            virtual_video_overlay_tex_geom,
            virtual_video_overlay_vertex_geom,
            virtual_video_overlay_full_screen,
            virtual_video_overlay_set_alpha,
        };
        memcpy((void *)&d_overlayInterface, &overlayInterface, sizeof(overlayInterface));

        const video_poke_interface_t pokeInterface = {
            virtual_video_get_flags,
            virtual_video_load_texture,
            virtual_video_unload_texture,
            virtual_video_set_video_mode,
            NULL, /* get_refresh_rate */
            virtual_video_set_filtering,
            virtual_video_get_video_output_size,
            virtual_video_get_video_output_prev,
            virtual_video_get_video_output_next,
            NULL, /* get_current_framebuffer */
            NULL, /* get_proc_address */
            virtual_video_set_aspect_ratio,
            virtual_video_apply_state_changes,
            virtual_video_set_texture_frame,
            virtual_video_set_texture_enable,
            virtual_video_set_osd_msg,
            virtual_video_show_mouse,
            virtual_video_grab_mouse_toggle,
            virtual_video_get_current_shader,
            NULL, /* get_current_software_framebuffer */
            NULL, /* get_hw_render_interface */
            virtual_video_set_hdr_max_nits,
            virtual_video_set_hdr_paper_white_nits,
            virtual_video_set_hdr_contrast,
            virtual_video_set_hdr_expand_gamut
        };
        memcpy((void *)&d_pokeInterface, &pokeInterface, sizeof(pokeInterface));

        self->lock        = slock_new();
        self->alpha_lock  = slock_new();
        self->frame.lock  = slock_new();
        self->cond_cmd    = scond_new();
        self->cond_thread = scond_new();

        size_t max_size        = info.input_scale * RARCH_SCALE_BASE;
        max_size              *= max_size;
        max_size              *= info.rgb32 ? sizeof(uint32_t) : sizeof(uint16_t);
        frame.buffer      = (uint8_t*)malloc(max_size);
        if (!frame.buffer)
           return nil;

        memset(frame.buffer, 0x80, max_size);

        self->input                = input;
        self->input_data           = inputData;
        self->info                 = info;
        self->alive                = true;
        self->focus                = true;
        self->has_windowed         = true;
        self->suppress_screensaver = true;
        self->last_time            = cpu_features_get_time_usec();

        d_displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(step:)];
        if (@available(iOS 15.0, tvOS 15.0, *)) {
            [d_displayLink setPreferredFrameRateRange:CAFrameRateRangeDefault];
        }
        [d_displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];
    }

    return self;
}

- (CADisplayLink *)displayLink {
    return d_displayLink;
}

- (void)free {
    if (d_displayLink) {
        thread_packet_t pkt;
        pkt.type = CMD_FREE;
        [self sendAndWaitReply:&pkt];

        [d_displayLink invalidate];
        d_displayLink = nil;
    } else {
        /* If we don't have a thread,
         * we must call the driver's free function ourselves. */
        if (driver_data && driver && driver->free) {
            driver->free(driver_data);
        }
    }

    free(texture.frame);
    free(frame.buffer);
    free(alpha_mod);

    slock_free(frame.lock);
    slock_free(alpha_lock);
    slock_free(lock);
    scond_free(cond_cmd);
    scond_free(cond_thread);

    video_driver_state_t *video_st = video_state_get_ptr();
    if(video_st->poke == &d_pokeInterface) {
        video_st->poke = NULL;
    }

    RARCH_LOG("Threaded video stats: Frames pushed: %u, Frames dropped: %u.\n", hit_count, miss_count);
}

- (void)setRealVideoDriver:(const video_driver_t *)drv virtualDriver:(const video_driver_t *)virtual{
    self->virtual_video = *virtual;
    self->driver        = drv;

    if (drv) {
        /* Disable optional features if not present. */
        if (!drv->read_viewport)
            self->virtual_video.read_viewport     = NULL;
        if (!drv->set_viewport)
            self->virtual_video.set_viewport      = NULL;
        if (!drv->set_rotation)
            self->virtual_video.set_rotation      = NULL;
        if (!drv->set_shader)
            self->virtual_video.set_shader        = NULL;
#ifdef HAVE_OVERLAY
        if (!drv->overlay_interface)
            self->virtual_video.overlay_interface = NULL;
#endif
        if (!drv->poke_interface)
            self->virtual_video.poke_interface    = NULL;
    }

    thread_packet_t pkt;
    pkt.type = CMD_INIT;
    [self sendAndWaitReply:&pkt];
}

/* render -> logic */
- (void)reply:(const thread_packet_t *)pkt {
    slock_lock(lock);

    cmd_data  = *pkt;
    reply_cmd = pkt->type;
    send_cmd  = CMD_VIDEO_NONE;

    scond_signal(cond_cmd);
    slock_unlock(lock);
}

/* logic -> render */
- (void)sendPacket:(const thread_packet_t *)pkt {
    slock_lock(lock);

    cmd_data  = *pkt;
    send_cmd  = pkt->type;
    reply_cmd = CMD_VIDEO_NONE;

    scond_signal(cond_thread);
    slock_unlock(lock);
}

/* logic -> render */
- (void)waitReply:(thread_packet_t *)pkt {
    slock_lock(lock);

    while (pkt->type != reply_cmd)
       scond_wait(cond_cmd, lock);

    *pkt          = cmd_data;
    cmd_data.type = CMD_VIDEO_NONE;

    slock_unlock(lock);
}

/* logic -> render */
- (void)sendAndWaitReply:(thread_packet_t *)pkt {
    if ([NSThread isMainThread]) {
        [self handlePacket:pkt];

        slock_lock(lock);
        *pkt          = cmd_data;
        cmd_data.type = CMD_VIDEO_NONE;
        slock_unlock(lock);
        return;
    } else {
        [self sendPacket: pkt];
        [self waitReply: pkt];
    }
}

- (void)updateDriverState {
#ifdef HAVE_OVERLAY
    slock_lock(alpha_lock);
    if (alpha_update) {
        if (driver_data && overlay && overlay->set_alpha) {
            for (int i = 0; i < (int)alpha_mods; i++) {
                overlay->set_alpha(driver_data, i, alpha_mod[i]);
            }
        }
        alpha_update = false;
    }
    slock_unlock(alpha_lock);
#endif // HAVE_OVERLAY

    if (apply_state_changes) {
        if (driver_data && poke && poke->apply_state_changes)
            poke->apply_state_changes(driver_data);
        apply_state_changes = false;
    }
}

/* returns true when video_thread_loop should quit */
- (BOOL)handlePacket:(const thread_packet_t *)incoming {
    thread_packet_t pkt = *incoming;

    switch (pkt.type) {
        case CMD_INIT:
            if (driver && driver->init) {
                driver_data = driver->init(&info, input, input_data);
                if (driver_data && driver->viewport_info) {
                    driver->viewport_info(driver_data, &vp);
                }
            } else {
                driver_data = NULL;
            }
            pkt.data.b = (driver_data != NULL);
            [self reply: &pkt];
            break;

        case CMD_FREE:
            if (driver_data && driver && driver->free) {
                driver->free(driver_data);
            }
            driver_data = NULL;
            [self reply: &pkt];
            return YES;

        case CMD_SET_ROTATION:
            if (driver_data && driver && driver->set_rotation)
                driver->set_rotation(driver_data, pkt.data.i);
            [self reply: &pkt];
            break;

        case CMD_SET_VIEWPORT:
            if (driver_data && driver && driver->set_viewport) {
                driver->set_viewport(driver_data, pkt.data.set_viewport.width, pkt.data.set_viewport.height, pkt.data.set_viewport.force_full, pkt.data.set_viewport.allow_rotate);
            }
            [self reply:&pkt];
            break;

        case CMD_READ_VIEWPORT:
            if (driver_data && driver && driver->viewport_info && driver->read_viewport) {
                video_viewport_t vp = { 0 };
                driver->viewport_info(driver_data, &vp);
                if (!memcmp(&vp, &read_vp, sizeof(vp))) {
                    /* We can read safely
                     *
                     * read_viewport() in GL driver calls
                     * 'cached frame render' to be able to read from
                     * back buffer.
                     *
                     * This means frame() callback in threaded wrapper will
                     * be called from this thread, causing a timeout, and
                     * no frame to be rendered.
                     *
                     * To avoid this, set a flag so wrapper can see if
                     * it's called in this "special" way. */
                    frame.within_thread = true;
                    pkt.data.b = driver->read_viewport(driver_data, (uint8_t*)pkt.data.v, is_idle);
                    frame.within_thread = false;
                } else {
                    /* Viewport dimensions changed right after main
                     * thread read the async value. Cannot read safely. */
                    pkt.data.b = false;
                }
            } else {
                pkt.data.b = false;
            }
            [self reply: &pkt];
            break;

        case CMD_SET_SHADER:
            if (driver_data && driver && driver->set_shader) {
                pkt.data.b = driver->set_shader(driver_data, pkt.data.set_shader.type, pkt.data.set_shader.path);
            } else {
                pkt.data.b = false;
            }
            [self reply: &pkt];
            break;

        case CMD_ALIVE:
            if (driver_data && driver && driver->alive) {
                pkt.data.b = driver->alive(driver_data);
            } else {
                pkt.data.b = false;
            }
            [self reply: &pkt];
            break;

#ifdef HAVE_OVERLAY
        case CMD_OVERLAY_ENABLE:
            if (driver_data && overlay && overlay->enable) {
                overlay->enable(driver_data, pkt.data.b);
            }
            [self reply: &pkt];
            break;

        case CMD_OVERLAY_LOAD: {
            unsigned tmp_alpha_mods = pkt.data.image.num;
            if (driver_data && overlay && overlay->load) {
                pkt.data.b = overlay->load(driver_data, pkt.data.image.data, pkt.data.image.num);
            } else {
                pkt.data.b = false;
            }

            if (tmp_alpha_mods > 0) {
                float *tmp_alpha_mod = (float*)realloc(alpha_mod, tmp_alpha_mods * sizeof(float));
                if (tmp_alpha_mod) {
                    /* Avoid temporary garbage data. */
                    for (int i = 0; i < (int)tmp_alpha_mods; i++) {
                        tmp_alpha_mod[i] = 1.0f;
                    }
                    alpha_mods = tmp_alpha_mods;
                    alpha_mod  = tmp_alpha_mod;
                }
            } else {
                free(alpha_mod);
                alpha_mods = 0;
                alpha_mod  = NULL;
            }
            [self reply: &pkt];
            break;
        }

        case CMD_OVERLAY_TEX_GEOM:
            if (driver_data && overlay && overlay->tex_geom) {
                overlay->tex_geom(driver_data, pkt.data.rect.index, pkt.data.rect.x, pkt.data.rect.y, pkt.data.rect.w, pkt.data.rect.h);
            }
            [self reply: &pkt];
            break;

        case CMD_OVERLAY_VERTEX_GEOM:
            if (driver_data && overlay && overlay->vertex_geom) {
                overlay->vertex_geom(driver_data, pkt.data.rect.index, pkt.data.rect.x, pkt.data.rect.y, pkt.data.rect.w, pkt.data.rect.h);
            }
            [self reply: &pkt];
            break;

        case CMD_OVERLAY_FULL_SCREEN:
            if (driver_data && overlay && overlay->full_screen) {
                overlay->full_screen(driver_data, pkt.data.b);
            }
            [self reply: &pkt];
            break;
#endif // HAVE_OVERLAY

        case CMD_POKE_SET_VIDEO_MODE:
            if (driver_data && poke && poke->set_video_mode) {
                poke->set_video_mode(driver_data, pkt.data.new_mode.width, pkt.data.new_mode.height, pkt.data.new_mode.fullscreen);
            }
            [self reply: &pkt];
            break;

        case CMD_POKE_SET_FILTERING:
            if (driver_data && poke && poke->set_filtering) {
                poke->set_filtering(driver_data, pkt.data.filtering.index, pkt.data.filtering.smooth, pkt.data.filtering.ctx_scaling);
            }
            [self reply: &pkt];
            break;

        case CMD_POKE_SET_ASPECT_RATIO:
            if (driver_data && poke && poke->set_aspect_ratio) {
                poke->set_aspect_ratio(driver_data, pkt.data.i);
            }
            [self reply: &pkt];
            break;

        case CMD_FONT_INIT:
            if (pkt.data.font_init.method) {
                pkt.data.font_init.return_value = pkt.data.font_init.method( pkt.data.font_init.font_driver, pkt.data.font_init.font_handle, pkt.data.font_init.video_data, pkt.data.font_init.font_path, pkt.data.font_init.font_size, pkt.data.font_init.api, pkt.data.font_init.is_threaded);
            }
            [self reply: &pkt];
            break;

        case CMD_CUSTOM_COMMAND:
            if (pkt.data.custom_command.method) {
                pkt.data.custom_command.return_value = pkt.data.custom_command.method(pkt.data.custom_command.data);
            }
            [self reply: &pkt];
            break;

        case CMD_POKE_SHOW_MOUSE:
            if (driver_data && poke && poke->show_mouse) {
                poke->show_mouse(driver_data, pkt.data.b);
            }
            [self reply: &pkt];
            break;

        case CMD_POKE_GRAB_MOUSE_TOGGLE:
            if (driver_data && poke && poke->grab_mouse_toggle) {
                poke->grab_mouse_toggle(driver_data);
            }
            [self reply: &pkt];
            break;

        case CMD_VIDEO_NONE:
            /* Never reply on no command. Possible deadlock if
             * thread sends command right after frame update. */
            break;

        case CMD_POKE_SET_HDR_MAX_NITS:
            if (driver_data && poke && poke->set_hdr_max_nits) {
                poke->set_hdr_max_nits(driver_data, pkt.data.hdr.max_nits);
            }
            [self reply: &pkt];
            break;

        case CMD_POKE_SET_HDR_PAPER_WHITE_NITS:
            if (driver_data && poke && poke->set_hdr_paper_white_nits) {
                poke->set_hdr_paper_white_nits(driver_data, pkt.data.hdr.paper_white_nits);
            }
            [self reply: &pkt];
            break;

        case CMD_POKE_SET_HDR_CONTRAST:
            if (driver_data && poke && poke->set_hdr_contrast) {
                poke->set_hdr_contrast(driver_data, pkt.data.hdr.contrast);
            }
            [self reply: &pkt];
            break;

        case CMD_POKE_SET_HDR_EXPAND_GAMUT:
            if (driver_data && poke && poke->set_hdr_expand_gamut) {
                poke->set_hdr_expand_gamut(driver_data, pkt.data.hdr.expand_gamut);
            }
            [self reply: &pkt];
            break;

        default:
            [self reply: &pkt];
            break;
    }

    return NO;
}

- (void)step:(CADisplayLink*)target {
    slock_lock(lock);
    bool hasCommand = (send_cmd != CMD_VIDEO_NONE);
    bool updated = frame.updated;

    /* To avoid race condition where send_cmd is updated
     * right after the switch is checked. */
    thread_packet_t pkt = cmd_data;

    slock_unlock(lock);

    if (!hasCommand && !updated) {
        return;
    }

    if (hasCommand && [self handlePacket: &pkt]) {
        [d_displayLink invalidate];
        d_displayLink = nil;
        return;
    }

    if (updated) {
        struct video_viewport vp = { 0 };
        bool               alive = false;
        bool               focus = false;
        bool        has_windowed = false;

        slock_lock(frame.lock);

        [self updateDriverState];

        if (driver_data && driver) {
            if (driver->frame) {
                video_frame_info_t video_info = { 0 };
                bool               ret;

                /* TODO/FIXME - not thread-safe - should get
                 * rid of this */
                video_driver_build_info(&video_info);

                ret = driver->frame(driver_data, frame.buffer, frame.width, frame.height, frame.count, frame.pitch, *frame.msg ? frame.msg : NULL, &video_info);

                slock_unlock(frame.lock);

                if (ret) {
                    if (driver->alive) {
                        alive = driver->alive(driver_data);
                    }
                    if (driver->focus) {
                        focus = driver->focus(driver_data);
                    }
                    if (driver->has_windowed) {
                        has_windowed = driver->has_windowed(driver_data);
                    }
                }
            } else {
                slock_unlock(frame.lock);
            }

            if (driver->viewport_info) {
                driver->viewport_info(driver_data, &vp);
            }
        } else {
            slock_unlock(frame.lock);
        }

        slock_lock(lock);
        self->alive         = alive;
        self->focus         = focus;
        self->has_windowed  = has_windowed;
        self->vp            = vp;
        self->frame.updated = false;
        scond_signal(cond_cmd);
        slock_unlock(lock);
    }
}

- (bool)isAlive {
    uint32_t runloop_flags = runloop_get_flags();

    if (runloop_flags & RUNLOOP_FLAG_PAUSED) {
        thread_packet_t pkt;
        pkt.type = CMD_ALIVE;
        [self sendAndWaitReply: &pkt];
        return pkt.data.b;
    }

    slock_lock(lock);
    bool ret = alive;
    slock_unlock(lock);
    return ret;
}

- (bool)isFocused {
   slock_lock(lock);
   bool ret = focus;
   slock_unlock(lock);
   return ret;
}

- (bool)isSuppressScreensaver {
   slock_lock(lock);
   bool ret = suppress_screensaver;
   slock_unlock(lock);
   return ret;
}

- (bool)hasWindowed {
   slock_lock(lock);
   bool ret = has_windowed;
   slock_unlock(lock);
   return ret;
}

- (bool)frame:(const void *)f width:(unsigned)w height:(unsigned)h frameCount:(uint64_t)fCount pitch:(unsigned)pitch message:(const char *)msg videoInfo:(video_frame_info_t *)video_info {
    /* If called from within read_viewport, we're actually in the
     * driver thread, so just render directly. */
    if (frame.within_thread) {
        [self updateDriverState];

        if (driver_data && driver && driver->frame) {
            return driver->frame(driver_data, f, w, h, fCount, pitch, msg, video_info);
        }

        return false;
    }

    slock_lock(lock);

    if (!nonblock) {
        retro_time_t target_frame_time = (retro_time_t)roundf(1000000 / video_info->refresh_rate);
        retro_time_t target            = last_time + target_frame_time;

        /* Ideally, use absolute time, but that is only a good idea on POSIX. */
        while (frame.updated) {
            retro_time_t current = cpu_features_get_time_usec();
            retro_time_t delta   = target - current;

            if (delta <= 0)
                break;

            if (!scond_wait_timeout(cond_cmd, lock, delta))
                break;
        }
    }

    /* Drop frame if updated flag is still set, as thread is
     * still working on last frame. */
    if (!frame.updated) {
        const uint8_t *src   = (const uint8_t*)f;
        uint8_t       *dst   = frame.buffer;
        unsigned copy_stride = w * (info.rgb32 ? sizeof(uint32_t) : sizeof(uint16_t));

        if (src) {
            /* TODO/FIXME - increment counter never meaningfully used */
            for (int i = 0; i < (int)h; i++, src += pitch, dst += copy_stride) {
                memcpy(dst, src, copy_stride);
            }
        }

        frame.updated = true;
        frame.width   = w;
        frame.height  = h;
        frame.count   = fCount;
        frame.pitch   = copy_stride;

        if (msg) {
            strlcpy(frame.msg, msg, sizeof(frame.msg));
        } else {
            *frame.msg = '\0';
        }

        scond_signal(cond_thread);
        hit_count++;
    } else {
        miss_count++;
    }

    slock_unlock(lock);

    last_time = cpu_features_get_time_usec();

    return true;
}

- (void)setNonblockState:(bool)v {
    nonblock = v;
}

- (bool)setShader:(enum rarch_shader_type)type path:(const char *)path {
    thread_packet_t pkt;
    pkt.type                 = CMD_SET_SHADER;
    pkt.data.set_shader.type = type;
    pkt.data.set_shader.path = path;

    [self sendAndWaitReply: &pkt];
    return pkt.data.b;
}

- (void)setViewportWithWidth:(unsigned)width height:(unsigned)height forceFull:(bool)forceFull videoAllowRotate:(bool)videoAllowRotate {
    thread_packet_t pkt;
    pkt.type                           = CMD_SET_VIEWPORT;
    pkt.data.set_viewport.width        = width;
    pkt.data.set_viewport.height       = height;
    pkt.data.set_viewport.force_full   = forceFull;
    pkt.data.set_viewport.allow_rotate = videoAllowRotate;
    [self sendAndWaitReply:&pkt];
}

- (void)setRotation:(unsigned)rotation {
    thread_packet_t pkt;
    pkt.type   = CMD_SET_ROTATION;
    pkt.data.i = rotation;
    [self sendAndWaitReply: &pkt];
}

/* This value is set async as stalling on the video driver for
 * every query is too slow.
 *
 * This means this value might not be correct, so viewport
 * reads are not supported for now. */
- (void)getViewportInfo:(video_viewport_t *)vp {
    slock_lock(lock);

    *vp = self->vp;

    /* Explicitly mem-copied so we can use memcmp correctly later. */
    memcpy(&(self->read_vp), &(self->vp), sizeof(self->read_vp));

    slock_unlock(lock);
}

- (bool)readViewport:(uint8_t *)buffer isIdle:(bool)isIdle {
    thread_packet_t pkt;
    pkt.type            = CMD_READ_VIEWPORT;
    pkt.data.v          = buffer;

    self->is_idle        = isIdle;
    [self sendAndWaitReply: &pkt];

    return pkt.data.b;
}

#ifdef HAVE_OVERLAY
- (void)overlayEnable:(bool)v {
    thread_packet_t pkt;
    pkt.type   = CMD_OVERLAY_ENABLE;
    pkt.data.b = v;
    [self sendAndWaitReply: &pkt];
}

- (bool)overlayLoad:(const void *)image_data count:(unsigned)numImages {
    thread_packet_t pkt;
    pkt.type            = CMD_OVERLAY_LOAD;
    pkt.data.image.data = (const struct texture_image*)image_data;
    pkt.data.image.num  = numImages;
    [self sendAndWaitReply: &pkt];
    return pkt.data.b;
}

- (void)overlayTexGeom:(unsigned)idx x:(float)x y:(float)y w:(float)w h:(float)h {
    thread_packet_t pkt;
    pkt.type            = CMD_OVERLAY_TEX_GEOM;
    pkt.data.rect.index = idx;
    pkt.data.rect.x     = x;
    pkt.data.rect.y     = y;
    pkt.data.rect.w     = w;
    pkt.data.rect.h     = h;
    [self sendAndWaitReply: &pkt];
}

- (void)overlayVertexGeom:(unsigned)idx x:(float)x y:(float)y w:(float)w h:(float)h {
    thread_packet_t pkt;
    pkt.type            = CMD_OVERLAY_VERTEX_GEOM;
    pkt.data.rect.index = idx;
    pkt.data.rect.x     = x;
    pkt.data.rect.y     = y;
    pkt.data.rect.w     = w;
    pkt.data.rect.h     = h;
    [self sendAndWaitReply: &pkt];
}

- (void)overlayFullScreen:(bool)v {
    thread_packet_t pkt;
    pkt.type   = CMD_OVERLAY_FULL_SCREEN;
    pkt.data.b = v;
    [self sendAndWaitReply: &pkt];
}

/* We cannot wait for this to complete. Totally blocks the main thread. */
- (void)overlaySetAlpha:(unsigned)idx mod:(float)mod {
    slock_lock(alpha_lock);
    alpha_mod[idx] = mod;
    alpha_update   = true;
    slock_unlock(alpha_lock);
}

- (void)getOverlayInterface:(const video_overlay_interface_t **)iface {
    if (driver_data && driver && driver->overlay_interface) {
        driver->overlay_interface(driver_data, &overlay);
        *iface = &d_overlayInterface;
    } else {
        *iface = NULL;
    }
}
#endif // HAVE_OVERLAY

- (uint32_t)getFlags {
    if (driver_data && poke && poke->get_flags)
        return poke->get_flags(driver_data);
    return 0;
}

- (uintptr_t)loadTexture:(void *)data threaded:(bool)threaded filterType:(enum texture_filter_type)filterType {
    if (driver_data && poke && poke->load_texture)
        return poke->load_texture(driver_data, data, threaded, filterType);
    return 0;
}

- (void)unloadTexture:(uintptr_t)texture threaded:(bool)threaded {
    if (driver_data && poke && poke->unload_texture)
        poke->unload_texture(driver_data, threaded, texture);
}

- (void)setVideoMode:(unsigned)width height:(unsigned)height videoFullscreen:(bool)videFullscreen {
    thread_packet_t pkt;
    pkt.type                     = CMD_POKE_SET_VIDEO_MODE;
    pkt.data.new_mode.width      = width;
    pkt.data.new_mode.height     = height;
    pkt.data.new_mode.fullscreen = videFullscreen;
    [self sendAndWaitReply: &pkt];
}

- (void)setFiltering:(unsigned)idx smooth:(bool)smooth {
    thread_packet_t pkt;
    pkt.type                  = CMD_POKE_SET_FILTERING;
    pkt.data.filtering.index  = idx;
    pkt.data.filtering.smooth = smooth;
    [self sendAndWaitReply: &pkt];
}

- (void)getVideoOutputSize:(unsigned *)width height:(unsigned *)height desc:(char *)desc descLen:(size_t)descLen {
    if (driver_data && poke && poke->get_video_output_size)
        poke->get_video_output_size(driver_data, width, height, desc, descLen);
}

- (void)getVideoOutputPrev {
    if (driver_data && poke && poke->get_video_output_prev)
        poke->get_video_output_prev(driver_data);
}

- (void)getVideoOutputNext {
    if (driver_data && poke && poke->get_video_output_next)
        poke->get_video_output_next(driver_data);
}

- (void)setAspectRatio:(unsigned)idx {
    thread_packet_t pkt;
    pkt.type   = CMD_POKE_SET_ASPECT_RATIO;
    pkt.data.i = idx;
    [self sendAndWaitReply: &pkt];
}

- (void)applyStateChanges {
    slock_lock(frame.lock);
    apply_state_changes = true;
    slock_unlock(frame.lock);
}

- (void)setTextureFrame:(const void *)f rgb32:(bool)rgb32 width:(unsigned)width height:(unsigned)height alpha:(float)alpha {

    size_t required = width * height * (rgb32 ? sizeof(uint32_t) : sizeof(uint16_t));

    slock_lock(frame.lock);

    if (!texture.frame || required > texture.frame_cap) {
        void *tmp_frame = realloc(texture.frame, required);
        if (!tmp_frame)
            goto end;

        texture.frame     = tmp_frame;
        texture.frame_cap = required;
    }

    memcpy(texture.frame, f, required);

    texture.rgb32         = rgb32;
    texture.width         = width;
    texture.height        = height;
    texture.alpha         = alpha;
    texture.frame_updated = true;

end:
   slock_unlock(frame.lock);
}

- (void)setTextureEnable:(bool)v fullscreen:(bool)fullscreen {
    slock_lock(frame.lock);
    texture.enable      = v;
    texture.full_screen = fullscreen;
    slock_unlock(frame.lock);
}

- (void)setOsdMsg:(const char *)msg params:(const struct font_params *)params font:(void *)font {
    /* TODO : find a way to determine if the calling
     * thread is the driver thread or not. */
    if (driver_data && poke && poke->set_osd_msg)
        poke->set_osd_msg(driver_data, msg, params, font);
}

- (void)showMouse:(bool)v {
    thread_packet_t pkt;
    pkt.type   = CMD_POKE_SHOW_MOUSE;
    pkt.data.b = v;
    [self sendAndWaitReply: &pkt];
}

- (void)grabMouseToggle {
    thread_packet_t pkt;
    pkt.type = CMD_POKE_GRAB_MOUSE_TOGGLE;
    [self sendAndWaitReply: &pkt];
}

/* This is read-only state which should not
 * have any kind of race condition. */
- (struct video_shader *)getCurrentShader {
   if (driver_data && poke && poke->get_current_shader)
      return poke->get_current_shader(driver_data);
   return NULL;
}

- (void)setHdrMaxNits:(float)maxNits {
    thread_packet_t pkt;
    pkt.type              = CMD_POKE_SET_HDR_MAX_NITS;
    pkt.data.hdr.max_nits = maxNits;
    [self sendAndWaitReply: &pkt];
}

- (void)setHdrPapeWhiteNits:(float)paperWhiteNits {
    thread_packet_t pkt;
    pkt.type                      = CMD_POKE_SET_HDR_PAPER_WHITE_NITS;
    pkt.data.hdr.paper_white_nits = paperWhiteNits;
    [self sendAndWaitReply: &pkt];
}

- (void)setHdrContrast:(float)contrast {
    thread_packet_t pkt;
    pkt.type              = CMD_POKE_SET_HDR_CONTRAST;
    pkt.data.hdr.contrast = contrast;
    [self sendAndWaitReply: &pkt];
}

- (void)setHdrExpandGamut:(bool)expandGamut {
    thread_packet_t pkt;
    pkt.type                  = CMD_POKE_SET_HDR_EXPAND_GAMUT;
    pkt.data.hdr.expand_gamut = expandGamut;
    [self sendAndWaitReply: &pkt];
}

- (void)getPokeInterface:(const video_poke_interface_t **)iface {
    if (driver_data && driver && driver->poke_interface) {
        driver->poke_interface(driver_data, &poke);
        *iface = &d_pokeInterface;
    } else {
        *iface = NULL;
    }
}

@end

NS_ASSUME_NONNULL_END

static void *virtual_video_init_never_call(const video_info_t *video, input_driver_t **input, void **input_data) {
    (void)video;
    (void)input;
    (void)input_data;
    RARCH_ERR("Sanity check fail! Virtual Video Driver mustn't be reinit.\n");
    abort();
    return NULL;
}

static bool virtual_video_frame(void *ctx, const void *frame_, unsigned width, unsigned height, uint64_t frame_count, unsigned pitch, const char *msg, video_frame_info_t *video_info) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    return [driver frame:frame_ width:width height:height frameCount:frame_count pitch:pitch message:msg videoInfo:video_info];
}

static void virtual_video_set_nonblock_state(void *ctx, bool state, bool adaptive_vsync_enabled, unsigned swap_interval) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver setNonblockState:state];
}

static bool virtual_video_alive(void *ctx) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    return [driver isAlive];
}

static bool virtual_video_focus(void *ctx) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    return [driver isFocused];
}

static bool virtual_video_suppress_screensaver(void *ctx, bool enable) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    return [driver isSuppressScreensaver];
}

static bool virtual_video_has_windowed(void *ctx) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    return [driver hasWindowed];
}

static bool virtual_video_set_shader(void *ctx, enum rarch_shader_type type, const char *path) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    return [driver setShader:type path:path];
}

static void virtual_video_free(void *ctx) {
    RAVirtualVideoDriver *driver = (__bridge_transfer RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver free];
}

static void virtual_video_set_viewport(void *ctx, unsigned width, unsigned height, bool force_full, bool video_allow_rotate) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver setViewportWithWidth:width height:height forceFull:force_full videoAllowRotate:video_allow_rotate];
}

static void virtual_video_set_rotation(void *ctx, unsigned rotation) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver setRotation:rotation];
}

static void virtual_video_viewport_info(void *ctx, struct video_viewport *vp) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver getViewportInfo:vp];
}

static bool virtual_video_read_viewport(void *ctx, uint8_t *buffer, bool is_idle) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    return [driver readViewport:buffer isIdle:is_idle];
}

#ifdef HAVE_OVERLAY
static void virtual_video_overlay_enable(void *ctx, bool state) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver overlayEnable:state];
}

static bool virtual_video_overlay_load(void *ctx, const void *image_data, unsigned num_images) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    return [driver overlayLoad:image_data count:num_images];
}

static void virtual_video_overlay_tex_geom(void *ctx, unsigned idx, float x, float y, float w, float h) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver overlayTexGeom:idx x:x y:y w:w h:h];
}

static void virtual_video_overlay_vertex_geom(void *ctx, unsigned idx, float x, float y, float w, float h) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver overlayVertexGeom:idx x:x y:y w:w h:h];
}

static void virtual_video_overlay_full_screen(void *ctx, bool enable) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver overlayFullScreen:enable];
}

static void virtual_video_overlay_set_alpha(void *ctx, unsigned idx, float mod) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver overlaySetAlpha:idx mod:mod];
}

static void virtual_video_get_overlay_interface(void *ctx, const video_overlay_interface_t **iface) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver getOverlayInterface:iface];
}
#endif // HAVE_OVERLAY

static uint32_t virtual_video_get_flags(void *ctx) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    return [driver getFlags];
}

static uintptr_t virtual_video_load_texture(void *ctx, void *data, bool threaded, enum texture_filter_type filter_type) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    return [driver loadTexture:data threaded:threaded filterType:filter_type];
}

static void virtual_video_unload_texture(void *ctx, bool threaded, uintptr_t texture) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver unloadTexture:texture threaded:threaded];
}

static void virtual_video_set_video_mode(void *ctx, unsigned width, unsigned height, bool video_fullscreen) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver setVideoMode:width height:height videoFullscreen:video_fullscreen];
}

static void virtual_video_set_filtering(void *ctx, unsigned idx, bool smooth, bool ctx_scaling) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    [driver setFiltering:idx smooth:smooth];
}

static void virtual_video_get_video_output_size(void *ctx, unsigned *width, unsigned *height, char *desc, size_t desc_len) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver getVideoOutputSize:width height:height desc:desc descLen:desc_len];
}

static void virtual_video_get_video_output_prev(void *ctx) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver getVideoOutputPrev];
}

static void virtual_video_get_video_output_next(void *ctx) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver getVideoOutputNext];
}

static void virtual_video_set_aspect_ratio(void *ctx, unsigned aspect_ratio_idx) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver setAspectRatio:aspect_ratio_idx];
}

static void virtual_video_apply_state_changes(void *ctx) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver applyStateChanges];
}

static void virtual_video_set_texture_frame(void *ctx, const void *frame, bool rgb32, unsigned width, unsigned height, float alpha) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver setTextureFrame:frame rgb32:rgb32 width:width height:height alpha:alpha];
}

static void virtual_video_set_texture_enable(void *ctx, bool state, bool full_screen) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver setTextureEnable:state fullscreen:full_screen];
}

static void virtual_video_set_osd_msg(void *ctx, const char *msg, const struct font_params *params, void *font) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver setOsdMsg:msg params:params font:font];
}

static void virtual_video_show_mouse(void *ctx, bool state) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver showMouse:state];
}

static void virtual_video_grab_mouse_toggle(void *ctx) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver grabMouseToggle];
}

static struct video_shader *virtual_video_get_current_shader(void *ctx) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    return [driver getCurrentShader];
}

static void virtual_video_set_hdr_max_nits(void *ctx, float max_nits) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver setHdrMaxNits:max_nits];
}

static void virtual_video_set_hdr_paper_white_nits(void *ctx, float paper_white_nits) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver setHdrPapeWhiteNits:paper_white_nits];
}

static void virtual_video_set_hdr_contrast(void *ctx, float contrast) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver setHdrContrast:contrast];
}

static void virtual_video_set_hdr_expand_gamut(void *ctx, bool expand_gamut) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver setHdrExpandGamut:expand_gamut];
}

static void virtual_video_get_poke_interface(void *ctx, const video_poke_interface_t **iface) {
    RAVirtualVideoDriver *driver = (__bridge RAVirtualVideoDriver *)ctx;
    NSCAssert(driver != nil, @"RAVirtualVideoDriver context must not be nil");
    [driver getPokeInterface:iface];
}

static const video_driver_t virtual_video = {
    virtual_video_init_never_call, /* Should never be called directly. */
    virtual_video_frame,
    virtual_video_set_nonblock_state,
    virtual_video_alive,
    virtual_video_focus,
    virtual_video_suppress_screensaver,
    virtual_video_has_windowed,
    virtual_video_set_shader,
    virtual_video_free,
    "Virtual Video",
    virtual_video_set_viewport,
    virtual_video_set_rotation,
    virtual_video_viewport_info,
    virtual_video_read_viewport,
    NULL, /* read_frame_raw */
#ifdef HAVE_OVERLAY
    virtual_video_get_overlay_interface,
#endif
    virtual_video_get_poke_interface,
    NULL, /* wrap_type_to_enum */
};

/**
 * virtual_video_init:
 * @out_driver                : Output video driver
 * @out_data                  : Output video data
 * @input                     : Input input driver
 * @input_data                : Input input data
 * @driver                    : Input Video driver
 * @info                      : Video info handle.
 *
 * Creates, initializes and starts a video driver in a new thread.
 * Access to video driver will be mediated through this driver.
 *
 * Returns: true (1) if successful, otherwise false (0).
 **/
bool virtual_video_init(const video_driver_t **out_driver, void **out_data, input_driver_t **input, void **input_data, const video_driver_t *drv, const video_info_t info) {
    RAVirtualVideoDriver *virtual = [[RAVirtualVideoDriver alloc] initWithVideoInfo:info input:input inputData:input_data];
    if (!virtual) {
        return false;
    }

    [virtual setRealVideoDriver:drv virtualDriver:&virtual_video];

    *out_driver = &virtual_video;
    *out_data   = (void *)CFBridgingRetain(virtual);
    return true;
}

bool virtual_video_font_init(const void **font_driver, void **font_handle, void *data, const char *font_path, float video_font_size, enum font_driver_render_api api, custom_font_command_method_t func, bool is_threaded) {
    thread_packet_t pkt;
    video_driver_state_t *video_st = video_state_get_ptr();
    RAVirtualVideoDriver *virtual = (__bridge RAVirtualVideoDriver *)video_st->data;

    if (!virtual)
        return false;

    pkt.type                       = CMD_FONT_INIT;
    pkt.data.font_init.method      = func;
    pkt.data.font_init.font_driver = font_driver;
    pkt.data.font_init.font_handle = font_handle;
    pkt.data.font_init.video_data  = data;
    pkt.data.font_init.font_path   = font_path;
    pkt.data.font_init.font_size   = video_font_size;
    pkt.data.font_init.is_threaded = is_threaded;
    pkt.data.font_init.api         = api;

    [virtual sendAndWaitReply: &pkt];

   return pkt.data.font_init.return_value;
}

unsigned virtual_video_texture_handle(void *data, custom_command_method_t func) {
    thread_packet_t pkt;
    video_driver_state_t *video_st = video_state_get_ptr();
    RAVirtualVideoDriver *virtual = (__bridge RAVirtualVideoDriver *)video_st->data;

    if (!virtual)
        return 0;

    /* if we're already on the video thread, just call the function, otherwise
     * we may deadlock with ourself waiting for the packet to be processed. */
    if([NSThread isMainThread] || !virtual->alive) {
        return func(data);
    }

    pkt.type                       = CMD_CUSTOM_COMMAND;
    pkt.data.custom_command.method = func;
    pkt.data.custom_command.data   = data;

    [virtual sendAndWaitReply: &pkt];

    return pkt.data.custom_command.return_value;
}

const video_driver_t *virtual_video_get_real_driver() {
    video_driver_state_t *video_st = video_state_get_ptr();
    RAVirtualVideoDriver *virtual = (__bridge RAVirtualVideoDriver *)video_st->data;
    if(virtual != nil) {
        return virtual->driver;
    } else {
        return nil;
    }
}

const void *virtual_video_get_real_driver_data() {
    video_driver_state_t *video_st = video_state_get_ptr();
    RAVirtualVideoDriver *virtual = (__bridge RAVirtualVideoDriver *)video_st->data;
    if(virtual != nil) {
        return virtual->driver_data;
    } else {
        return nil;
    }
}
