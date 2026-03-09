//
//  dr_mp3.c
//  RetroArchX
//
//  Created by haharsw on 2025/8/11.
//

#include "dr/dr_mp3.h"

void drmp3dec_init(drmp3dec *dec)
{
    dec->header[0] = 0;
}

int drmp3dec_decode_frame(drmp3dec *dec, const unsigned char *mp3, int mp3_bytes, short *pcm, drmp3dec_frame_info *info)
{
    int i = 0, igr, frame_size = 0, success = 1;
    const drmp3_uint8 *hdr;
    drmp3_bs bs_frame[1];
    drmp3dec_scratch scratch;

    if (mp3_bytes > 4 && dec->header[0] == 0xff && drmp3_hdr_compare(dec->header, mp3))
        {
        frame_size = drmp3_hdr_frame_bytes(mp3, dec->free_format_bytes) + drmp3_hdr_padding(mp3);
        if (frame_size != mp3_bytes && (frame_size + DRMP3_HDR_SIZE > mp3_bytes || !drmp3_hdr_compare(mp3, mp3 + frame_size)))
            {
            frame_size = 0;
            }
        }
    if (!frame_size)
        {
        memset(dec, 0, sizeof(drmp3dec));
        i = drmp3d_find_frame(mp3, mp3_bytes, &dec->free_format_bytes, &frame_size);
        if (!frame_size || i + frame_size > mp3_bytes)
            {
            info->frame_bytes = i;
            return 0;
            }
        }

    hdr = mp3 + i;
    memcpy(dec->header, hdr, DRMP3_HDR_SIZE);
    info->frame_bytes = i + frame_size;
    info->channels = DRMP3_HDR_IS_MONO(hdr) ? 1 : 2;
    info->hz = drmp3_hdr_sample_rate_hz(hdr);
    info->layer = 4 - DRMP3_HDR_GET_LAYER(hdr);
    info->bitrate_kbps = drmp3_hdr_bitrate_kbps(hdr);

    drmp3_bs_init(bs_frame, hdr + DRMP3_HDR_SIZE, frame_size - DRMP3_HDR_SIZE);
    if (DRMP3_HDR_IS_CRC(hdr))
        {
        drmp3_bs_get_bits(bs_frame, 16);
        }

    if (info->layer == 3)
        {
        int main_data_begin = drmp3_L3_read_side_info(bs_frame, scratch.gr_info, hdr);
        if (main_data_begin < 0 || bs_frame->pos > bs_frame->limit)
            {
            drmp3dec_init(dec);
            return 0;
            }
        success = drmp3_L3_restore_reservoir(dec, bs_frame, &scratch, main_data_begin);
        if (success)
            {
            for (igr = 0; igr < (DRMP3_HDR_TEST_MPEG1(hdr) ? 2 : 1); igr++, pcm += 576*info->channels)
                {
                memset(scratch.grbuf[0], 0, 576*2*sizeof(float));
                drmp3_L3_decode(dec, &scratch, scratch.gr_info + igr*info->channels, info->channels);
                drmp3d_synth_granule(dec->qmf_state, scratch.grbuf[0], 18, info->channels, pcm, scratch.syn[0]);
                }
            }
        drmp3_L3_save_reservoir(dec, &scratch);
        } else
            {
#ifdef DR_MP3_ONLY_MP3
            return 0;
#else
            drmp3_L12_scale_info sci[1];
            drmp3_L12_read_scale_info(hdr, bs_frame, sci);

            memset(scratch.grbuf[0], 0, 576*2*sizeof(float));
            for (i = 0, igr = 0; igr < 3; igr++)
                {
                if (12 == (i += drmp3_L12_dequantize_granule(scratch.grbuf[0] + i, bs_frame, sci, info->layer | 1)))
                    {
                    i = 0;
                    drmp3_L12_apply_scf_384(sci, sci->scf + igr, scratch.grbuf[0]);
                    drmp3d_synth_granule(dec->qmf_state, scratch.grbuf[0], 12, info->channels, pcm, scratch.syn[0]);
                    memset(scratch.grbuf[0], 0, 576*2*sizeof(float));
                    pcm += 384*info->channels;
                    }
                if (bs_frame->pos > bs_frame->limit)
                    {
                    drmp3dec_init(dec);
                    return 0;
                    }
                }
#endif
            }
    return success*drmp3_hdr_frame_samples(dec->header);
}

drmp3_uint64 drmp3_src_read_frames_passthrough(drmp3_src* pSRC, drmp3_uint64 frameCount, void* pFramesOut, drmp3_bool32 flush);
drmp3_uint64 drmp3_src_read_frames_linear(drmp3_src* pSRC, drmp3_uint64 frameCount, void* pFramesOut, drmp3_bool32 flush);

void drmp3_src_cache_init(drmp3_src* pSRC, drmp3_src_cache* pCache)
{
    drmp3_assert(pSRC != NULL);
    drmp3_assert(pCache != NULL);

    pCache->pSRC = pSRC;
    pCache->cachedFrameCount = 0;
    pCache->iNextFrame = 0;
}


drmp3_uint64 drmp3_src_cache_read_frames(drmp3_src_cache* pCache, drmp3_uint64 frameCount, float* pFramesOut)
{
    drmp3_uint32 channels;
    drmp3_uint64 totalFramesRead = 0;

    drmp3_assert(pCache != NULL);
    drmp3_assert(pCache->pSRC != NULL);
    drmp3_assert(pCache->pSRC->onRead != NULL);
    drmp3_assert(frameCount > 0);
    drmp3_assert(pFramesOut != NULL);

    channels = pCache->pSRC->config.channels;

    while (frameCount > 0)
        {
        drmp3_uint32 framesToReadFromClient;
        /* If there's anything in memory go ahead and copy that over first. */
        drmp3_uint64 framesRemainingInMemory = pCache->cachedFrameCount - pCache->iNextFrame;
        drmp3_uint64 framesToReadFromMemory = frameCount;
        if (framesToReadFromMemory > framesRemainingInMemory)
            framesToReadFromMemory = framesRemainingInMemory;

        drmp3_copy_memory(pFramesOut, pCache->pCachedFrames + pCache->iNextFrame*channels, (drmp3_uint32)(framesToReadFromMemory * channels * sizeof(float)));
        pCache->iNextFrame += (drmp3_uint32)framesToReadFromMemory;

        totalFramesRead += framesToReadFromMemory;
        frameCount -= framesToReadFromMemory;
        if (frameCount == 0)
            break;


        /* At this point there are still more frames to read from the client, so we'll need to reload the cache with fresh data. */
        drmp3_assert(frameCount > 0);
        pFramesOut += framesToReadFromMemory * channels;

        pCache->iNextFrame = 0;
        pCache->cachedFrameCount = 0;

        framesToReadFromClient = drmp3_countof(pCache->pCachedFrames) / pCache->pSRC->config.channels;
        if (framesToReadFromClient > pCache->pSRC->config.cacheSizeInFrames)
            framesToReadFromClient = pCache->pSRC->config.cacheSizeInFrames;

        pCache->cachedFrameCount = (drmp3_uint32)pCache->pSRC->onRead(pCache->pSRC, framesToReadFromClient, pCache->pCachedFrames, pCache->pSRC->pUserData);


        /* Get out of this loop if nothing was able to be retrieved. */
        if (pCache->cachedFrameCount == 0)
            break;
        }

    return totalFramesRead;
}

drmp3_bool32 drmp3_src_init(const drmp3_src_config* pConfig, drmp3_src_read_proc onRead, void* pUserData, drmp3_src* pSRC)
{
    if (pSRC == NULL) return DRMP3_FALSE;
    drmp3_zero_object(pSRC);

    if (pConfig == NULL || onRead == NULL) return DRMP3_FALSE;
    if (pConfig->channels == 0 || pConfig->channels > 2) return DRMP3_FALSE;

    pSRC->config = *pConfig;
    pSRC->onRead = onRead;
    pSRC->pUserData = pUserData;

    if (pSRC->config.cacheSizeInFrames > DRMP3_SRC_CACHE_SIZE_IN_FRAMES || pSRC->config.cacheSizeInFrames == 0)
        pSRC->config.cacheSizeInFrames = DRMP3_SRC_CACHE_SIZE_IN_FRAMES;

    drmp3_src_cache_init(pSRC, &pSRC->cache);
    return DRMP3_TRUE;
}


drmp3_bool32 drmp3_src_set_input_sample_rate(drmp3_src* pSRC, drmp3_uint32 sampleRateIn)
{
    if (pSRC == NULL) return DRMP3_FALSE;

    /* Must have a sample rate of > 0. */
    if (sampleRateIn == 0)
        return DRMP3_FALSE;

    pSRC->config.sampleRateIn = sampleRateIn;
    return DRMP3_TRUE;
}

drmp3_bool32 drmp3_src_set_output_sample_rate(drmp3_src* pSRC, drmp3_uint32 sampleRateOut)
{
    if (pSRC == NULL) return DRMP3_FALSE;

    /* Must have a sample rate of > 0. */
    if (sampleRateOut == 0)
        return DRMP3_FALSE;

    pSRC->config.sampleRateOut = sampleRateOut;
    return DRMP3_TRUE;
}

drmp3_uint64 drmp3_src_read_frames_ex(drmp3_src* pSRC, drmp3_uint64 frameCount, void* pFramesOut, drmp3_bool32 flush)
{
    drmp3_src_algorithm algorithm;
    if (pSRC == NULL || frameCount == 0 || pFramesOut == NULL) return 0;

    algorithm = pSRC->config.algorithm;

    /* Always use passthrough if the sample rates are the same. */
    if (pSRC->config.sampleRateIn == pSRC->config.sampleRateOut)
        algorithm = drmp3_src_algorithm_none;

    /* Could just use a function pointer instead of a switch for this... */
    switch (algorithm)
        {
            case drmp3_src_algorithm_none:   return drmp3_src_read_frames_passthrough(pSRC, frameCount, pFramesOut, flush);
            case drmp3_src_algorithm_linear: return drmp3_src_read_frames_linear(pSRC, frameCount, pFramesOut, flush);
            default: return 0;
        }
}

drmp3_uint64 drmp3_src_read_frames(drmp3_src* pSRC, drmp3_uint64 frameCount, void* pFramesOut)
{
    return drmp3_src_read_frames_ex(pSRC, frameCount, pFramesOut, DRMP3_FALSE);
}

drmp3_uint64 drmp3_src_read_frames_passthrough(drmp3_src* pSRC, drmp3_uint64 frameCount, void* pFramesOut, drmp3_bool32 flush)
{
    drmp3_assert(pSRC != NULL);
    drmp3_assert(frameCount > 0);
    drmp3_assert(pFramesOut != NULL);

    (void)flush;    /* Passthrough need not care about flushing. */
    return pSRC->onRead(pSRC, frameCount, pFramesOut, pSRC->pUserData);
}

drmp3_uint64 drmp3_src_read_frames_linear(drmp3_src* pSRC, drmp3_uint64 frameCount, void* pFramesOut, drmp3_bool32 flush)
{
    float factor;
    drmp3_uint64 totalFramesRead = 0;

    drmp3_assert(pSRC != NULL);
    drmp3_assert(frameCount > 0);
    drmp3_assert(pFramesOut != NULL);

    /* For linear SRC, the bin is only 2 frames: 1 prior, 1 future. */

    /* Load the bin if necessary. */
    if (!pSRC->algo.linear.isPrevFramesLoaded)
        {
        drmp3_uint64 framesRead = drmp3_src_cache_read_frames(&pSRC->cache, 1, pSRC->bin);
        if (framesRead == 0)
            return 0;
        pSRC->algo.linear.isPrevFramesLoaded = DRMP3_TRUE;
        }
    if (!pSRC->algo.linear.isNextFramesLoaded)
        {
        drmp3_uint64 framesRead = drmp3_src_cache_read_frames(&pSRC->cache, 1, pSRC->bin + pSRC->config.channels);
        if (framesRead == 0)
            return 0;
        pSRC->algo.linear.isNextFramesLoaded = DRMP3_TRUE;
        }

    factor = (float)pSRC->config.sampleRateIn / pSRC->config.sampleRateOut;

    while (frameCount > 0)
        {
        drmp3_uint32 i;
        drmp3_uint32 framesToReadFromClient;
        /* The bin is where the previous and next frames are located. */
        float* pPrevFrame = pSRC->bin;
        float* pNextFrame = pSRC->bin + pSRC->config.channels;

        drmp3_blend_f32((float*)pFramesOut, pPrevFrame, pNextFrame, pSRC->algo.linear.alpha, pSRC->config.channels);

        pSRC->algo.linear.alpha += factor;

        /* The new alpha value is how we determine whether or not we need to read fresh frames. */
        framesToReadFromClient = (drmp3_uint32)pSRC->algo.linear.alpha;
        pSRC->algo.linear.alpha = pSRC->algo.linear.alpha - framesToReadFromClient;

        for (i = 0; i < framesToReadFromClient; ++i)
            {
            drmp3_uint32 j;
            drmp3_uint64 framesRead;
            for (j = 0; j < pSRC->config.channels; ++j)
                pPrevFrame[j] = pNextFrame[j];

            framesRead = drmp3_src_cache_read_frames(&pSRC->cache, 1, pNextFrame);
            if (framesRead == 0)
                {
                drmp3_uint32 j;
                for (j = 0; j < pSRC->config.channels; ++j)
                    pNextFrame[j] = 0;

                if (pSRC->algo.linear.isNextFramesLoaded)
                    pSRC->algo.linear.isNextFramesLoaded = DRMP3_FALSE;
                else
                    {
                    if (flush)
                        pSRC->algo.linear.isPrevFramesLoaded = DRMP3_FALSE;
                    }

                break;
                }
            }

        pFramesOut  = (drmp3_uint8*)pFramesOut + (1 * pSRC->config.channels * sizeof(float));
        frameCount -= 1;
        totalFramesRead += 1;

        /* If there's no frames available we need to get out of this loop. */
        if (!pSRC->algo.linear.isNextFramesLoaded && (!flush || !pSRC->algo.linear.isPrevFramesLoaded))
            break;
        }

    return totalFramesRead;
}


drmp3_bool32 drmp3_init_internal(drmp3* pMP3, drmp3_read_proc onRead, drmp3_seek_proc onSeek, void* pUserData, const drmp3_config* pConfig)
{
    drmp3_config config;
    drmp3_src_config srcConfig;

    drmp3_assert(pMP3 != NULL);
    drmp3_assert(onRead != NULL);

    /* This function assumes the output object has already been reset to 0. Do not do that here, otherwise things will break. */
    drmp3dec_init(&pMP3->decoder);

    /* The config can be null in which case we use defaults. */
    if (pConfig != NULL)
        config = *pConfig;
    else
        drmp3_zero_object(&config);

    pMP3->channels = config.outputChannels;
    if (pMP3->channels == 0)
        pMP3->channels = DR_MP3_DEFAULT_CHANNELS;

    /* Cannot have more than 2 channels. */
    if (pMP3->channels > 2)
        pMP3->channels = 2;

    pMP3->sampleRate = config.outputSampleRate;
    if (pMP3->sampleRate == 0)
        pMP3->sampleRate = DR_MP3_DEFAULT_SAMPLE_RATE;

    pMP3->onRead = onRead;
    pMP3->onSeek = onSeek;
    pMP3->pUserData = pUserData;

    /* We need a sample rate converter for converting the sample rate from the MP3 frames to the requested output sample rate. */
    drmp3_zero_object(&srcConfig);
    srcConfig.sampleRateIn = DR_MP3_DEFAULT_SAMPLE_RATE;
    srcConfig.sampleRateOut = pMP3->sampleRate;
    srcConfig.channels = pMP3->channels;
    srcConfig.algorithm = drmp3_src_algorithm_linear;
    if (!drmp3_src_init(&srcConfig, drmp3_read_src, pMP3, &pMP3->src))
        return DRMP3_FALSE;

    /* Decode the first frame to confirm that it is indeed a valid MP3 stream. */
    if (!drmp3_decode_next_frame(pMP3))
        return DRMP3_FALSE; /* Not a valid MP3 stream. */

    return DRMP3_TRUE;
}

drmp3_bool32 drmp3_init(drmp3* pMP3, drmp3_read_proc onRead, drmp3_seek_proc onSeek, void* pUserData, const drmp3_config* pConfig)
{
    if (pMP3 == NULL || onRead == NULL)
        return DRMP3_FALSE;

    drmp3_zero_object(pMP3);
    return drmp3_init_internal(pMP3, onRead, onSeek, pUserData, pConfig);
}

drmp3_bool32 drmp3_init_memory(drmp3* pMP3, const void* pData, size_t dataSize, const drmp3_config* pConfig)
{
    if (pMP3 == NULL)
        return DRMP3_FALSE;

    drmp3_zero_object(pMP3);

    if (pData == NULL || dataSize == 0)
        return DRMP3_FALSE;

    pMP3->memory.pData = (const drmp3_uint8*)pData;
    pMP3->memory.dataSize = dataSize;
    pMP3->memory.currentReadPos = 0;

    return drmp3_init_internal(pMP3, drmp3__on_read_memory, drmp3__on_seek_memory, pMP3, pConfig);
}

#ifndef DR_MP3_NO_STDIO
#include <stdio.h>

static size_t drmp3__on_read_stdio(void* pUserData, void* pBufferOut, size_t bytesToRead)
{
    return fread(pBufferOut, 1, bytesToRead, (FILE*)pUserData);
}

static drmp3_bool32 drmp3__on_seek_stdio(void* pUserData, int offset, drmp3_seek_origin origin)
{
    return fseek((FILE*)pUserData, offset, (origin == drmp3_seek_origin_current) ? SEEK_CUR : SEEK_SET) == 0;
}

drmp3_bool32 drmp3_init_file(drmp3* pMP3, const char* filePath, const drmp3_config* pConfig)
{
    FILE* pFile;
#if defined(_MSC_VER) && _MSC_VER >= 1400
    if (fopen_s(&pFile, filePath, "rb") != 0)
        return DRMP3_FALSE;
#else
    pFile = fopen(filePath, "rb");
    if (pFile == NULL)
        return DRMP3_FALSE;
#endif

    return drmp3_init(pMP3, drmp3__on_read_stdio, drmp3__on_seek_stdio, (void*)pFile, pConfig);
}
#endif


void drmp3_uninit(drmp3* pMP3)
{
    if (pMP3 == NULL) return;

#ifndef DR_MP3_NO_STDIO
    if (pMP3->onRead == drmp3__on_read_stdio)
        fclose((FILE*)pMP3->pUserData);
#endif

    drmp3_free(pMP3->pData);
}

drmp3_uint64 drmp3_read_f32(drmp3* pMP3, drmp3_uint64 framesToRead, float* pBufferOut)
{
    drmp3_uint64 totalFramesRead = 0;
    if (pMP3 == NULL || pMP3->onRead == NULL) return 0;

    if (pBufferOut == NULL)
        {
        float temp[4096];
        while (framesToRead > 0)
            {
            drmp3_uint64 framesJustRead;
            drmp3_uint64 framesToReadRightNow = sizeof(temp)/sizeof(temp[0]) / pMP3->channels;
            if (framesToReadRightNow > framesToRead)
                framesToReadRightNow = framesToRead;

            framesJustRead = drmp3_read_f32(pMP3, framesToReadRightNow, temp);
            if (framesJustRead == 0)
                break;

            framesToRead -= framesJustRead;
            totalFramesRead += framesJustRead;
            }
        } else {
            totalFramesRead = drmp3_src_read_frames_ex(&pMP3->src, framesToRead, pBufferOut, DRMP3_TRUE);
        }

    return totalFramesRead;
}

drmp3_bool32 drmp3_seek_to_frame(drmp3* pMP3, drmp3_uint64 frameIndex)
{
    drmp3_uint64 framesRead;

    if (pMP3 == NULL || pMP3->onSeek == NULL) return DRMP3_FALSE;

    /* Seek to the start of the stream to begin with. */
    if (!pMP3->onSeek(pMP3->pUserData, 0, drmp3_seek_origin_start))
        return DRMP3_FALSE;

    /* Clear any cached data. */
    pMP3->framesConsumed = 0;
    pMP3->framesRemaining = 0;
    pMP3->dataSize = 0;
    pMP3->atEnd = DRMP3_FALSE;

    /* TODO: Optimize.
     *
     * This is inefficient. We simply read frames from the start of the stream. */
    framesRead = drmp3_read_f32(pMP3, frameIndex, NULL);
    if (framesRead != frameIndex)
        return DRMP3_FALSE;

    return DRMP3_TRUE;
}



float* drmp3__full_decode_and_close_f32(drmp3* pMP3, drmp3_config* pConfig, drmp3_uint64* pTotalFrameCount)
{
    drmp3_uint64 totalFramesRead = 0;
    drmp3_uint64 framesCapacity = 0;
    float* pFrames = NULL;

    float temp[4096];

    drmp3_assert(pMP3 != NULL);

    for (;;)
        {
        drmp3_uint64 framesToReadRightNow = drmp3_countof(temp) / pMP3->channels;
        drmp3_uint64 framesJustRead = drmp3_read_f32(pMP3, framesToReadRightNow, temp);
        if (framesJustRead == 0)
            break;

        /* Reallocate the output buffer if there's not enough room. */
        if (framesCapacity < totalFramesRead + framesJustRead)
            {
            float* pNewFrames;
            drmp3_uint64 newFramesBufferSize;

            framesCapacity *= 2;
            if (framesCapacity < totalFramesRead + framesJustRead)
                framesCapacity = totalFramesRead + framesJustRead;

            newFramesBufferSize = framesCapacity*pMP3->channels*sizeof(float);
            if (newFramesBufferSize > SIZE_MAX)
                break;

            pNewFrames = (float*)drmp3_realloc(pFrames, (size_t)newFramesBufferSize);
            if (pNewFrames == NULL)
                {
                drmp3_free(pFrames);
                break;
                }

            pFrames = pNewFrames;
            }

        drmp3_copy_memory(pFrames + totalFramesRead*pMP3->channels, temp, (size_t)(framesJustRead*pMP3->channels*sizeof(float)));
        totalFramesRead += framesJustRead;

        /* If the number of frames we asked for is less that what we actually read it means we've reached the end. */
        if (framesJustRead != framesToReadRightNow)
            break;
        }

    if (pConfig != NULL)
        {
        pConfig->outputChannels = pMP3->channels;
        pConfig->outputSampleRate = pMP3->sampleRate;
        }

    drmp3_uninit(pMP3);

    if (pTotalFrameCount) *pTotalFrameCount = totalFramesRead;
    return pFrames;
}

float* drmp3_open_and_decode_f32(drmp3_read_proc onRead, drmp3_seek_proc onSeek, void* pUserData, drmp3_config* pConfig, drmp3_uint64* pTotalFrameCount)
{
    drmp3 mp3;
    if (!drmp3_init(&mp3, onRead, onSeek, pUserData, pConfig))
        return NULL;

    return drmp3__full_decode_and_close_f32(&mp3, pConfig, pTotalFrameCount);
}

float* drmp3_open_and_decode_memory_f32(const void* pData, size_t dataSize, drmp3_config* pConfig, drmp3_uint64* pTotalFrameCount)
{
    drmp3 mp3;
    if (!drmp3_init_memory(&mp3, pData, dataSize, pConfig))
        return NULL;

    return drmp3__full_decode_and_close_f32(&mp3, pConfig, pTotalFrameCount);
}

#ifndef DR_MP3_NO_STDIO
float* drmp3_open_and_decode_file_f32(const char* filePath, drmp3_config* pConfig, drmp3_uint64* pTotalFrameCount)
{
    drmp3 mp3;
    if (!drmp3_init_file(&mp3, filePath, pConfig))
        return NULL;

    return drmp3__full_decode_and_close_f32(&mp3, pConfig, pTotalFrameCount);
}
#endif

void drmp3_free(void* p)
{
    DRMP3_FREE(p);
}
