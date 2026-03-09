//
//  stb_vorbis.c
//  RetroArch
//
//  Created by haharsw on 2025/7/27.
//

#include "stb_vorbis.h"

void stb_vorbis_close(stb_vorbis *p)
{
    if (p == NULL) return;
    vorbis_deinit(p);
    setup_free(p,p);
}

unsigned int stb_vorbis_get_file_offset(stb_vorbis *f)
{
    return (unsigned int)(f->stream - f->stream_start);
}

int stb_vorbis_get_sample_offset(stb_vorbis *f)
{
    if (f->current_loc_valid)
        return f->current_loc;
    return -1;
}

stb_vorbis_info stb_vorbis_get_info(stb_vorbis *f)
{
    stb_vorbis_info d;
    d.channels = f->channels;
    d.sample_rate = f->sample_rate;
    d.setup_memory_required = f->setup_memory_required;
    d.setup_temp_memory_required = f->setup_temp_memory_required;
    d.temp_memory_required = f->temp_memory_required;
    d.max_frame_size = f->blocksize_1 >> 1;
    return d;
}

int stb_vorbis_get_error(stb_vorbis *f)
{
    int e = f->error;
    f->error = VORBIS__no_error;
    return e;
}

int stb_vorbis_seek_frame(stb_vorbis *f, unsigned int sample_number)
{
    return vorbis_seek_base(f, sample_number, FALSE);
}

int stb_vorbis_seek(stb_vorbis *f, unsigned int sample_number)
{
    return vorbis_seek_base(f, sample_number, TRUE);
}

void stb_vorbis_seek_start(stb_vorbis *f)
{
    if (IS_PUSH_MODE(f)) { error(f, VORBIS_invalid_api_mixing); return; }
    set_file_offset(f, f->first_audio_page_offset);
    f->previous_length = 0;
    f->first_decode = TRUE;
    f->next_seg = -1;
    vorbis_pump_first_frame(f);
}

unsigned int stb_vorbis_stream_length_in_samples(stb_vorbis *f)
{
    unsigned int restore_offset, previous_safe;
    unsigned int end, last_page_loc;

    if (IS_PUSH_MODE(f)) return error(f, VORBIS_invalid_api_mixing);
    if (!f->total_samples) {
        unsigned int last;
        uint32_t lo,hi;
        char header[6];

        /* first, store the current decode position so we can restore it */
        restore_offset = stb_vorbis_get_file_offset(f);

        /* now we want to seek back 64K from the end (the last page must
         * be at most a little less than 64K, but let's allow a little slop) */
        if (f->stream_len >= 65536 && f->stream_len-65536 >= f->first_audio_page_offset)
            previous_safe = f->stream_len - 65536;
        else
            previous_safe = f->first_audio_page_offset;

        set_file_offset(f, previous_safe);
        /* previous_safe is now our candidate 'earliest known place that seeking
         * to will lead to the final page' */

        if (!vorbis_find_page(f, &end, &last)) {
            /* if we can't find a page, we're hosed! */
            f->error = VORBIS_cant_find_last_page;
            f->total_samples = 0xffffffff;
            goto done;
        }

        /* check if there are more pages */
        last_page_loc = stb_vorbis_get_file_offset(f);

        /* stop when the last_page flag is set, not when we reach eof;
         * this allows us to stop short of a 'file_section' end without
         * explicitly checking the length of the section */
        while (!last) {
            set_file_offset(f, end);
            if (!vorbis_find_page(f, &end, &last)) {
                /* the last page we found didn't have the 'last page' flag
                 * set. whoops! */
                break;
            }
            previous_safe = last_page_loc+1;
            last_page_loc = stb_vorbis_get_file_offset(f);
        }

        set_file_offset(f, last_page_loc);

        /* parse the header */
        getn(f, (unsigned char *)header, 6);
        /* extract the absolute granule position */
        lo = get32(f);
        hi = get32(f);
        if (lo == 0xffffffff && hi == 0xffffffff) {
            f->error = VORBIS_cant_find_last_page;
            f->total_samples = SAMPLE_unknown;
            goto done;
        }
        if (hi)
            lo = 0xfffffffe; /* saturate */
        f->total_samples = lo;

        f->p_last.page_start = last_page_loc;
        f->p_last.page_end   = end;
        f->p_last.last_decoded_sample = lo;
        f->p_last.first_decoded_sample = SAMPLE_unknown;
        f->p_last.after_previous_page_start = previous_safe;

    done:
        set_file_offset(f, restore_offset);
    }
    return f->total_samples == SAMPLE_unknown ? 0 : f->total_samples;
}

float stb_vorbis_stream_length_in_seconds(stb_vorbis *f)
{
    return stb_vorbis_stream_length_in_samples(f) / (float) f->sample_rate;
}



int stb_vorbis_get_frame_float(stb_vorbis *f, int *channels, float ***output)
{
    int len, right,left,i;
    if (IS_PUSH_MODE(f)) return error(f, VORBIS_invalid_api_mixing);

    if (!vorbis_decode_packet(f, &len, &left, &right)) {
        f->channel_buffer_start = f->channel_buffer_end = 0;
        return 0;
    }

    len = vorbis_finish_frame(f, len, left, right);
    for (i=0; i < f->channels; ++i)
        f->outputs[i] = f->channel_buffers[i] + left;

    f->channel_buffer_start = left;
    f->channel_buffer_end   = left+len;

    if (channels) *channels = f->channels;
    if (output)   *output = f->outputs;
    return len;
}

stb_vorbis * stb_vorbis_open_memory(const unsigned char *data, int len, int *error, stb_vorbis_alloc *alloc)
{
    stb_vorbis *f, p;
    if (data == NULL) return NULL;
    vorbis_init(&p, alloc);
    p.stream = (uint8_t *) data;
    p.stream_end = (uint8_t *) data + len;
    p.stream_start = (uint8_t *) p.stream;
    p.stream_len = len;
    p.push_mode = FALSE;
    if (start_decoder(&p)) {
        f = vorbis_alloc(&p);
        if (f) {
            *f = p;
            vorbis_pump_first_frame(f);
            return f;
        }
    }
    if (error) *error = p.error;
    vorbis_deinit(&p);
    return NULL;
}

int stb_vorbis_get_samples_float_interleaved(stb_vorbis *f, int channels, float *buffer, int num_floats)
{
    float **outputs;
    int len = num_floats / channels;
    int n=0;
    int z = f->channels;
    if (z > channels) z = channels;
    while (n < len) {
        int i,j;
        int k = f->channel_buffer_end - f->channel_buffer_start;
        if (n+k >= len) k = len - n;
        for (j=0; j < k; ++j) {
            for (i=0; i < z; ++i)
                *buffer++ = f->channel_buffers[i][f->channel_buffer_start+j];
            for (   ; i < channels; ++i)
                *buffer++ = 0;
        }
        n += k;
        f->channel_buffer_start += k;
        if (n == len)
            break;
        if (!stb_vorbis_get_frame_float(f, NULL, &outputs))
            break;
    }
    return n;
}

int stb_vorbis_get_samples_float(stb_vorbis *f, int channels, float **buffer, int num_samples)
{
    float **outputs;
    int n=0;
    int z = f->channels;
    if (z > channels) z = channels;
    while (n < num_samples) {
        int i;
        int k = f->channel_buffer_end - f->channel_buffer_start;
        if (n+k >= num_samples) k = num_samples - n;
        if (k) {
            for (i=0; i < z; ++i)
                memcpy(buffer[i]+n, f->channel_buffers[i]+f->channel_buffer_start, sizeof(float)*k);
            for (   ; i < channels; ++i)
                memset(buffer[i]+n, 0, sizeof(float) * k);
        }
        n += k;
        f->channel_buffer_start += k;
        if (n == num_samples)
            break;
        if (!stb_vorbis_get_frame_float(f, NULL, &outputs))
            break;
    }
    return n;
}
