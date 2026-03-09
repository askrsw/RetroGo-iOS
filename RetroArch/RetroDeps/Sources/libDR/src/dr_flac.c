//
//  dr_flac.c
//  RetroArchX
//
//  Created by haharsw on 2025/8/11.
//

#include "dr/dr_flac.h"

/* Disable some annoying warnings. */
#if defined(__clang__) || (defined(__GNUC__) && (__GNUC__ > 4 || (__GNUC__ == 4 && __GNUC_MINOR__ >= 6)))
#pragma GCC diagnostic push
#if __GNUC__ >= 7
#pragma GCC diagnostic ignored "-Wimplicit-fallthrough"
#endif
#endif

DRFLAC_API void drflac_version(drflac_uint32* pMajor, drflac_uint32* pMinor, drflac_uint32* pRevision)
{
    if (pMajor) {
        *pMajor = DRFLAC_VERSION_MAJOR;
    }

    if (pMinor) {
        *pMinor = DRFLAC_VERSION_MINOR;
    }

    if (pRevision) {
        *pRevision = DRFLAC_VERSION_REVISION;
    }
}

DRFLAC_API const char* drflac_version_string(void)
{
    return DRFLAC_VERSION_STRING;
}

DRFLAC_API drflac* drflac_open_file(const char* pFileName, const drflac_allocation_callbacks* pAllocationCallbacks)
{
    drflac* pFlac;
    FILE* pFile;

    if (drflac_fopen(&pFile, pFileName, "rb") != DRFLAC_SUCCESS) {
        return NULL;
    }

    pFlac = drflac_open(drflac__on_read_stdio, drflac__on_seek_stdio, (void*)pFile, pAllocationCallbacks);
    if (pFlac == NULL) {
        fclose(pFile);
        return NULL;
    }

    return pFlac;
}

#ifndef DR_FLAC_NO_WCHAR
DRFLAC_API drflac* drflac_open_file_w(const wchar_t* pFileName, const drflac_allocation_callbacks* pAllocationCallbacks)
{
    drflac* pFlac;
    FILE* pFile;

    if (drflac_wfopen(&pFile, pFileName, L"rb", pAllocationCallbacks) != DRFLAC_SUCCESS) {
        return NULL;
    }

    pFlac = drflac_open(drflac__on_read_stdio, drflac__on_seek_stdio, (void*)pFile, pAllocationCallbacks);
    if (pFlac == NULL) {
        fclose(pFile);
        return NULL;
    }

    return pFlac;
}
#endif

DRFLAC_API drflac* drflac_open_file_with_metadata(const char* pFileName, drflac_meta_proc onMeta, void* pUserData, const drflac_allocation_callbacks* pAllocationCallbacks)
{
    drflac* pFlac;
    FILE* pFile;

    if (drflac_fopen(&pFile, pFileName, "rb") != DRFLAC_SUCCESS) {
        return NULL;
    }

    pFlac = drflac_open_with_metadata_private(drflac__on_read_stdio, drflac__on_seek_stdio, onMeta, drflac_container_unknown, (void*)pFile, pUserData, pAllocationCallbacks);
    if (pFlac == NULL) {
        fclose(pFile);
        return pFlac;
    }

    return pFlac;
}

#ifndef DR_FLAC_NO_WCHAR
DRFLAC_API drflac* drflac_open_file_with_metadata_w(const wchar_t* pFileName, drflac_meta_proc onMeta, void* pUserData, const drflac_allocation_callbacks* pAllocationCallbacks)
{
    drflac* pFlac;
    FILE* pFile;

    if (drflac_wfopen(&pFile, pFileName, L"rb", pAllocationCallbacks) != DRFLAC_SUCCESS) {
        return NULL;
    }

    pFlac = drflac_open_with_metadata_private(drflac__on_read_stdio, drflac__on_seek_stdio, onMeta, drflac_container_unknown, (void*)pFile, pUserData, pAllocationCallbacks);
    if (pFlac == NULL) {
        fclose(pFile);
        return pFlac;
    }

    return pFlac;
}
#endif  /* DR_FLAC_NO_STDIO */

DRFLAC_API drflac* drflac_open_memory(const void* pData, size_t dataSize, const drflac_allocation_callbacks* pAllocationCallbacks)
{
    drflac__memory_stream memoryStream;
    drflac* pFlac;

    memoryStream.data = (const drflac_uint8*)pData;
    memoryStream.dataSize = dataSize;
    memoryStream.currentReadPos = 0;
    pFlac = drflac_open(drflac__on_read_memory, drflac__on_seek_memory, &memoryStream, pAllocationCallbacks);
    if (pFlac == NULL) {
        return NULL;
    }

    pFlac->memoryStream = memoryStream;

    /* This is an awful hack... */
#ifndef DR_FLAC_NO_OGG
    if (pFlac->container == drflac_container_ogg)
        {
        drflac_oggbs* oggbs = (drflac_oggbs*)pFlac->_oggbs;
        oggbs->pUserData = &pFlac->memoryStream;
        }
    else
#endif
        {
        pFlac->bs.pUserData = &pFlac->memoryStream;
        }

    return pFlac;
}

DRFLAC_API drflac* drflac_open_memory_with_metadata(const void* pData, size_t dataSize, drflac_meta_proc onMeta, void* pUserData, const drflac_allocation_callbacks* pAllocationCallbacks)
{
    drflac__memory_stream memoryStream;
    drflac* pFlac;

    memoryStream.data = (const drflac_uint8*)pData;
    memoryStream.dataSize = dataSize;
    memoryStream.currentReadPos = 0;
    pFlac = drflac_open_with_metadata_private(drflac__on_read_memory, drflac__on_seek_memory, onMeta, drflac_container_unknown, &memoryStream, pUserData, pAllocationCallbacks);
    if (pFlac == NULL) {
        return NULL;
    }

    pFlac->memoryStream = memoryStream;

    /* This is an awful hack... */
#ifndef DR_FLAC_NO_OGG
    if (pFlac->container == drflac_container_ogg)
        {
        drflac_oggbs* oggbs = (drflac_oggbs*)pFlac->_oggbs;
        oggbs->pUserData = &pFlac->memoryStream;
        }
    else
#endif
        {
        pFlac->bs.pUserData = &pFlac->memoryStream;
        }

    return pFlac;
}

DRFLAC_API drflac* drflac_open(drflac_read_proc onRead, drflac_seek_proc onSeek, void* pUserData, const drflac_allocation_callbacks* pAllocationCallbacks)
{
    return drflac_open_with_metadata_private(onRead, onSeek, NULL, drflac_container_unknown, pUserData, pUserData, pAllocationCallbacks);
}
DRFLAC_API drflac* drflac_open_relaxed(drflac_read_proc onRead, drflac_seek_proc onSeek, drflac_container container, void* pUserData, const drflac_allocation_callbacks* pAllocationCallbacks)
{
    return drflac_open_with_metadata_private(onRead, onSeek, NULL, container, pUserData, pUserData, pAllocationCallbacks);
}

DRFLAC_API drflac* drflac_open_with_metadata(drflac_read_proc onRead, drflac_seek_proc onSeek, drflac_meta_proc onMeta, void* pUserData, const drflac_allocation_callbacks* pAllocationCallbacks)
{
    return drflac_open_with_metadata_private(onRead, onSeek, onMeta, drflac_container_unknown, pUserData, pUserData, pAllocationCallbacks);
}
DRFLAC_API drflac* drflac_open_with_metadata_relaxed(drflac_read_proc onRead, drflac_seek_proc onSeek, drflac_meta_proc onMeta, drflac_container container, void* pUserData, const drflac_allocation_callbacks* pAllocationCallbacks)
{
    return drflac_open_with_metadata_private(onRead, onSeek, onMeta, container, pUserData, pUserData, pAllocationCallbacks);
}

DRFLAC_API void drflac_close(drflac* pFlac)
{
    if (pFlac == NULL) {
        return;
    }

#ifndef DR_FLAC_NO_STDIO
    /*
     If we opened the file with drflac_open_file() we will want to close the file handle. We can know whether or not drflac_open_file()
     was used by looking at the callbacks.
     */
    if (pFlac->bs.onRead == drflac__on_read_stdio) {
        fclose((FILE*)pFlac->bs.pUserData);
    }

#ifndef DR_FLAC_NO_OGG
    /* Need to clean up Ogg streams a bit differently due to the way the bit streaming is chained. */
    if (pFlac->container == drflac_container_ogg) {
        drflac_oggbs* oggbs = (drflac_oggbs*)pFlac->_oggbs;
        DRFLAC_ASSERT(pFlac->bs.onRead == drflac__on_read_ogg);

        if (oggbs->onRead == drflac__on_read_stdio) {
            fclose((FILE*)oggbs->pUserData);
        }
    }
#endif
#endif

    drflac__free_from_callbacks(pFlac, &pFlac->allocationCallbacks);
}

DRFLAC_API drflac_uint64 drflac_read_pcm_frames_s32(drflac* pFlac, drflac_uint64 framesToRead, drflac_int32* pBufferOut)
{
    drflac_uint64 framesRead;
    drflac_uint32 unusedBitsPerSample;

    if (pFlac == NULL || framesToRead == 0) {
        return 0;
    }

    if (pBufferOut == NULL) {
        return drflac__seek_forward_by_pcm_frames(pFlac, framesToRead);
    }

    DRFLAC_ASSERT(pFlac->bitsPerSample <= 32);
    unusedBitsPerSample = 32 - pFlac->bitsPerSample;

    framesRead = 0;
    while (framesToRead > 0) {
        /* If we've run out of samples in this frame, go to the next. */
        if (pFlac->currentFLACFrame.pcmFramesRemaining == 0) {
            if (!drflac__read_and_decode_next_flac_frame(pFlac)) {
                break;  /* Couldn't read the next frame, so just break from the loop and return. */
            }
        } else {
            unsigned int channelCount = drflac__get_channel_count_from_channel_assignment(pFlac->currentFLACFrame.header.channelAssignment);
            drflac_uint64 iFirstPCMFrame = pFlac->currentFLACFrame.header.blockSizeInPCMFrames - pFlac->currentFLACFrame.pcmFramesRemaining;
            drflac_uint64 frameCountThisIteration = framesToRead;

            if (frameCountThisIteration > pFlac->currentFLACFrame.pcmFramesRemaining) {
                frameCountThisIteration = pFlac->currentFLACFrame.pcmFramesRemaining;
            }

            if (channelCount == 2) {
                const drflac_int32* pDecodedSamples0 = pFlac->currentFLACFrame.subframes[0].pSamplesS32 + iFirstPCMFrame;
                const drflac_int32* pDecodedSamples1 = pFlac->currentFLACFrame.subframes[1].pSamplesS32 + iFirstPCMFrame;

                switch (pFlac->currentFLACFrame.header.channelAssignment)
                    {
                        case DRFLAC_CHANNEL_ASSIGNMENT_LEFT_SIDE:
                        {
                        drflac_read_pcm_frames_s32__decode_left_side(pFlac, frameCountThisIteration, unusedBitsPerSample, pDecodedSamples0, pDecodedSamples1, pBufferOut);
                        } break;

                        case DRFLAC_CHANNEL_ASSIGNMENT_RIGHT_SIDE:
                        {
                        drflac_read_pcm_frames_s32__decode_right_side(pFlac, frameCountThisIteration, unusedBitsPerSample, pDecodedSamples0, pDecodedSamples1, pBufferOut);
                        } break;

                        case DRFLAC_CHANNEL_ASSIGNMENT_MID_SIDE:
                        {
                        drflac_read_pcm_frames_s32__decode_mid_side(pFlac, frameCountThisIteration, unusedBitsPerSample, pDecodedSamples0, pDecodedSamples1, pBufferOut);
                        } break;

                        case DRFLAC_CHANNEL_ASSIGNMENT_INDEPENDENT:
                        default:
                        {
                        drflac_read_pcm_frames_s32__decode_independent_stereo(pFlac, frameCountThisIteration, unusedBitsPerSample, pDecodedSamples0, pDecodedSamples1, pBufferOut);
                        } break;
                    }
            } else {
                /* Generic interleaving. */
                drflac_uint64 i;
                for (i = 0; i < frameCountThisIteration; ++i) {
                    unsigned int j;
                    for (j = 0; j < channelCount; ++j) {
                        pBufferOut[(i*channelCount)+j] = (drflac_int32)((drflac_uint32)(pFlac->currentFLACFrame.subframes[j].pSamplesS32[iFirstPCMFrame + i]) << (unusedBitsPerSample + pFlac->currentFLACFrame.subframes[j].wastedBitsPerSample));
                    }
                }
            }

            framesRead                += frameCountThisIteration;
            pBufferOut                += frameCountThisIteration * channelCount;
            framesToRead              -= frameCountThisIteration;
            pFlac->currentPCMFrame    += frameCountThisIteration;
            pFlac->currentFLACFrame.pcmFramesRemaining -= (drflac_uint32)frameCountThisIteration;
        }
    }

    return framesRead;
}

DRFLAC_API drflac_uint64 drflac_read_pcm_frames_s16(drflac* pFlac, drflac_uint64 framesToRead, drflac_int16* pBufferOut)
{
    drflac_uint64 framesRead;
    drflac_uint32 unusedBitsPerSample;

    if (pFlac == NULL || framesToRead == 0) {
        return 0;
    }

    if (pBufferOut == NULL) {
        return drflac__seek_forward_by_pcm_frames(pFlac, framesToRead);
    }

    DRFLAC_ASSERT(pFlac->bitsPerSample <= 32);
    unusedBitsPerSample = 32 - pFlac->bitsPerSample;

    framesRead = 0;
    while (framesToRead > 0) {
        /* If we've run out of samples in this frame, go to the next. */
        if (pFlac->currentFLACFrame.pcmFramesRemaining == 0) {
            if (!drflac__read_and_decode_next_flac_frame(pFlac)) {
                break;  /* Couldn't read the next frame, so just break from the loop and return. */
            }
        } else {
            unsigned int channelCount = drflac__get_channel_count_from_channel_assignment(pFlac->currentFLACFrame.header.channelAssignment);
            drflac_uint64 iFirstPCMFrame = pFlac->currentFLACFrame.header.blockSizeInPCMFrames - pFlac->currentFLACFrame.pcmFramesRemaining;
            drflac_uint64 frameCountThisIteration = framesToRead;

            if (frameCountThisIteration > pFlac->currentFLACFrame.pcmFramesRemaining) {
                frameCountThisIteration = pFlac->currentFLACFrame.pcmFramesRemaining;
            }

            if (channelCount == 2) {
                const drflac_int32* pDecodedSamples0 = pFlac->currentFLACFrame.subframes[0].pSamplesS32 + iFirstPCMFrame;
                const drflac_int32* pDecodedSamples1 = pFlac->currentFLACFrame.subframes[1].pSamplesS32 + iFirstPCMFrame;

                switch (pFlac->currentFLACFrame.header.channelAssignment)
                    {
                        case DRFLAC_CHANNEL_ASSIGNMENT_LEFT_SIDE:
                        {
                        drflac_read_pcm_frames_s16__decode_left_side(pFlac, frameCountThisIteration, unusedBitsPerSample, pDecodedSamples0, pDecodedSamples1, pBufferOut);
                        } break;

                        case DRFLAC_CHANNEL_ASSIGNMENT_RIGHT_SIDE:
                        {
                        drflac_read_pcm_frames_s16__decode_right_side(pFlac, frameCountThisIteration, unusedBitsPerSample, pDecodedSamples0, pDecodedSamples1, pBufferOut);
                        } break;

                        case DRFLAC_CHANNEL_ASSIGNMENT_MID_SIDE:
                        {
                        drflac_read_pcm_frames_s16__decode_mid_side(pFlac, frameCountThisIteration, unusedBitsPerSample, pDecodedSamples0, pDecodedSamples1, pBufferOut);
                        } break;

                        case DRFLAC_CHANNEL_ASSIGNMENT_INDEPENDENT:
                        default:
                        {
                        drflac_read_pcm_frames_s16__decode_independent_stereo(pFlac, frameCountThisIteration, unusedBitsPerSample, pDecodedSamples0, pDecodedSamples1, pBufferOut);
                        } break;
                    }
            } else {
                /* Generic interleaving. */
                drflac_uint64 i;
                for (i = 0; i < frameCountThisIteration; ++i) {
                    unsigned int j;
                    for (j = 0; j < channelCount; ++j) {
                        drflac_int32 sampleS32 = (drflac_int32)((drflac_uint32)(pFlac->currentFLACFrame.subframes[j].pSamplesS32[iFirstPCMFrame + i]) << (unusedBitsPerSample + pFlac->currentFLACFrame.subframes[j].wastedBitsPerSample));
                        pBufferOut[(i*channelCount)+j] = (drflac_int16)(sampleS32 >> 16);
                    }
                }
            }

            framesRead                += frameCountThisIteration;
            pBufferOut                += frameCountThisIteration * channelCount;
            framesToRead              -= frameCountThisIteration;
            pFlac->currentPCMFrame    += frameCountThisIteration;
            pFlac->currentFLACFrame.pcmFramesRemaining -= (drflac_uint32)frameCountThisIteration;
        }
    }

    return framesRead;
}

DRFLAC_API drflac_uint64 drflac_read_pcm_frames_f32(drflac* pFlac, drflac_uint64 framesToRead, float* pBufferOut)
{
    drflac_uint64 framesRead;
    drflac_uint32 unusedBitsPerSample;

    if (pFlac == NULL || framesToRead == 0) {
        return 0;
    }

    if (pBufferOut == NULL) {
        return drflac__seek_forward_by_pcm_frames(pFlac, framesToRead);
    }

    DRFLAC_ASSERT(pFlac->bitsPerSample <= 32);
    unusedBitsPerSample = 32 - pFlac->bitsPerSample;

    framesRead = 0;
    while (framesToRead > 0) {
        /* If we've run out of samples in this frame, go to the next. */
        if (pFlac->currentFLACFrame.pcmFramesRemaining == 0) {
            if (!drflac__read_and_decode_next_flac_frame(pFlac)) {
                break;  /* Couldn't read the next frame, so just break from the loop and return. */
            }
        } else {
            unsigned int channelCount = drflac__get_channel_count_from_channel_assignment(pFlac->currentFLACFrame.header.channelAssignment);
            drflac_uint64 iFirstPCMFrame = pFlac->currentFLACFrame.header.blockSizeInPCMFrames - pFlac->currentFLACFrame.pcmFramesRemaining;
            drflac_uint64 frameCountThisIteration = framesToRead;

            if (frameCountThisIteration > pFlac->currentFLACFrame.pcmFramesRemaining) {
                frameCountThisIteration = pFlac->currentFLACFrame.pcmFramesRemaining;
            }

            if (channelCount == 2) {
                const drflac_int32* pDecodedSamples0 = pFlac->currentFLACFrame.subframes[0].pSamplesS32 + iFirstPCMFrame;
                const drflac_int32* pDecodedSamples1 = pFlac->currentFLACFrame.subframes[1].pSamplesS32 + iFirstPCMFrame;

                switch (pFlac->currentFLACFrame.header.channelAssignment)
                    {
                        case DRFLAC_CHANNEL_ASSIGNMENT_LEFT_SIDE:
                        {
                        drflac_read_pcm_frames_f32__decode_left_side(pFlac, frameCountThisIteration, unusedBitsPerSample, pDecodedSamples0, pDecodedSamples1, pBufferOut);
                        } break;

                        case DRFLAC_CHANNEL_ASSIGNMENT_RIGHT_SIDE:
                        {
                        drflac_read_pcm_frames_f32__decode_right_side(pFlac, frameCountThisIteration, unusedBitsPerSample, pDecodedSamples0, pDecodedSamples1, pBufferOut);
                        } break;

                        case DRFLAC_CHANNEL_ASSIGNMENT_MID_SIDE:
                        {
                        drflac_read_pcm_frames_f32__decode_mid_side(pFlac, frameCountThisIteration, unusedBitsPerSample, pDecodedSamples0, pDecodedSamples1, pBufferOut);
                        } break;

                        case DRFLAC_CHANNEL_ASSIGNMENT_INDEPENDENT:
                        default:
                        {
                        drflac_read_pcm_frames_f32__decode_independent_stereo(pFlac, frameCountThisIteration, unusedBitsPerSample, pDecodedSamples0, pDecodedSamples1, pBufferOut);
                        } break;
                    }
            } else {
                /* Generic interleaving. */
                drflac_uint64 i;
                for (i = 0; i < frameCountThisIteration; ++i) {
                    unsigned int j;
                    for (j = 0; j < channelCount; ++j) {
                        drflac_int32 sampleS32 = (drflac_int32)((drflac_uint32)(pFlac->currentFLACFrame.subframes[j].pSamplesS32[iFirstPCMFrame + i]) << (unusedBitsPerSample + pFlac->currentFLACFrame.subframes[j].wastedBitsPerSample));
                        pBufferOut[(i*channelCount)+j] = (float)(sampleS32 / 2147483648.0);
                    }
                }
            }

            framesRead                += frameCountThisIteration;
            pBufferOut                += frameCountThisIteration * channelCount;
            framesToRead              -= frameCountThisIteration;
            pFlac->currentPCMFrame    += frameCountThisIteration;
            pFlac->currentFLACFrame.pcmFramesRemaining -= (unsigned int)frameCountThisIteration;
        }
    }

    return framesRead;
}


DRFLAC_API drflac_bool32 drflac_seek_to_pcm_frame(drflac* pFlac, drflac_uint64 pcmFrameIndex)
{
    if (pFlac == NULL) {
        return DRFLAC_FALSE;
    }

    /* Don't do anything if we're already on the seek point. */
    if (pFlac->currentPCMFrame == pcmFrameIndex) {
        return DRFLAC_TRUE;
    }

    /*
     If we don't know where the first frame begins then we can't seek. This will happen when the STREAMINFO block was not present
     when the decoder was opened.
     */
    if (pFlac->firstFLACFramePosInBytes == 0) {
        return DRFLAC_FALSE;
    }

    if (pcmFrameIndex == 0) {
        pFlac->currentPCMFrame = 0;
        return drflac__seek_to_first_frame(pFlac);
    } else {
        drflac_bool32 wasSuccessful = DRFLAC_FALSE;
        drflac_uint64 originalPCMFrame = pFlac->currentPCMFrame;

        /* Clamp the sample to the end. */
        if (pcmFrameIndex > pFlac->totalPCMFrameCount) {
            pcmFrameIndex = pFlac->totalPCMFrameCount;
        }

        /* If the target sample and the current sample are in the same frame we just move the position forward. */
        if (pcmFrameIndex > pFlac->currentPCMFrame) {
            /* Forward. */
            drflac_uint32 offset = (drflac_uint32)(pcmFrameIndex - pFlac->currentPCMFrame);
            if (pFlac->currentFLACFrame.pcmFramesRemaining >  offset) {
                pFlac->currentFLACFrame.pcmFramesRemaining -= offset;
                pFlac->currentPCMFrame = pcmFrameIndex;
                return DRFLAC_TRUE;
            }
        } else {
            /* Backward. */
            drflac_uint32 offsetAbs = (drflac_uint32)(pFlac->currentPCMFrame - pcmFrameIndex);
            drflac_uint32 currentFLACFramePCMFrameCount = pFlac->currentFLACFrame.header.blockSizeInPCMFrames;
            drflac_uint32 currentFLACFramePCMFramesConsumed = currentFLACFramePCMFrameCount - pFlac->currentFLACFrame.pcmFramesRemaining;
            if (currentFLACFramePCMFramesConsumed > offsetAbs) {
                pFlac->currentFLACFrame.pcmFramesRemaining += offsetAbs;
                pFlac->currentPCMFrame = pcmFrameIndex;
                return DRFLAC_TRUE;
            }
        }

        /*
         Different techniques depending on encapsulation. Using the native FLAC seektable with Ogg encapsulation is a bit awkward so
         we'll instead use Ogg's natural seeking facility.
         */
#ifndef DR_FLAC_NO_OGG
        if (pFlac->container == drflac_container_ogg)
            {
            wasSuccessful = drflac_ogg__seek_to_pcm_frame(pFlac, pcmFrameIndex);
            }
        else
#endif
            {
            /* First try seeking via the seek table. If this fails, fall back to a brute force seek which is much slower. */
            if (/*!wasSuccessful && */!pFlac->_noSeekTableSeek) {
                wasSuccessful = drflac__seek_to_pcm_frame__seek_table(pFlac, pcmFrameIndex);
            }

#if !defined(DR_FLAC_NO_CRC)
            /* Fall back to binary search if seek table seeking fails. This requires the length of the stream to be known. */
            if (!wasSuccessful && !pFlac->_noBinarySearchSeek && pFlac->totalPCMFrameCount > 0) {
                wasSuccessful = drflac__seek_to_pcm_frame__binary_search(pFlac, pcmFrameIndex);
            }
#endif

            /* Fall back to brute force if all else fails. */
            if (!wasSuccessful && !pFlac->_noBruteForceSeek) {
                wasSuccessful = drflac__seek_to_pcm_frame__brute_force(pFlac, pcmFrameIndex);
            }
            }

        if (wasSuccessful) {
            pFlac->currentPCMFrame = pcmFrameIndex;
        } else {
            /* Seek failed. Try putting the decoder back to it's original state. */
            if (drflac_seek_to_pcm_frame(pFlac, originalPCMFrame) == DRFLAC_FALSE) {
                /* Failed to seek back to the original PCM frame. Fall back to 0. */
                drflac_seek_to_pcm_frame(pFlac, 0);
            }
        }

        return wasSuccessful;
    }
}

DRFLAC_API drflac_int32* drflac_open_and_read_pcm_frames_s32(drflac_read_proc onRead, drflac_seek_proc onSeek, void* pUserData, unsigned int* channelsOut, unsigned int* sampleRateOut, drflac_uint64* totalPCMFrameCountOut, const drflac_allocation_callbacks* pAllocationCallbacks)
{
    drflac* pFlac;

    if (channelsOut) {
        *channelsOut = 0;
    }
    if (sampleRateOut) {
        *sampleRateOut = 0;
    }
    if (totalPCMFrameCountOut) {
        *totalPCMFrameCountOut = 0;
    }

    pFlac = drflac_open(onRead, onSeek, pUserData, pAllocationCallbacks);
    if (pFlac == NULL) {
        return NULL;
    }

    return drflac__full_read_and_close_s32(pFlac, channelsOut, sampleRateOut, totalPCMFrameCountOut);
}

DRFLAC_API drflac_int16* drflac_open_and_read_pcm_frames_s16(drflac_read_proc onRead, drflac_seek_proc onSeek, void* pUserData, unsigned int* channelsOut, unsigned int* sampleRateOut, drflac_uint64* totalPCMFrameCountOut, const drflac_allocation_callbacks* pAllocationCallbacks)
{
    drflac* pFlac;

    if (channelsOut) {
        *channelsOut = 0;
    }
    if (sampleRateOut) {
        *sampleRateOut = 0;
    }
    if (totalPCMFrameCountOut) {
        *totalPCMFrameCountOut = 0;
    }

    pFlac = drflac_open(onRead, onSeek, pUserData, pAllocationCallbacks);
    if (pFlac == NULL) {
        return NULL;
    }

    return drflac__full_read_and_close_s16(pFlac, channelsOut, sampleRateOut, totalPCMFrameCountOut);
}

DRFLAC_API float* drflac_open_and_read_pcm_frames_f32(drflac_read_proc onRead, drflac_seek_proc onSeek, void* pUserData, unsigned int* channelsOut, unsigned int* sampleRateOut, drflac_uint64* totalPCMFrameCountOut, const drflac_allocation_callbacks* pAllocationCallbacks)
{
    drflac* pFlac;

    if (channelsOut) {
        *channelsOut = 0;
    }
    if (sampleRateOut) {
        *sampleRateOut = 0;
    }
    if (totalPCMFrameCountOut) {
        *totalPCMFrameCountOut = 0;
    }

    pFlac = drflac_open(onRead, onSeek, pUserData, pAllocationCallbacks);
    if (pFlac == NULL) {
        return NULL;
    }

    return drflac__full_read_and_close_f32(pFlac, channelsOut, sampleRateOut, totalPCMFrameCountOut);
}

#ifndef DR_FLAC_NO_STDIO
DRFLAC_API drflac_int32* drflac_open_file_and_read_pcm_frames_s32(const char* filename, unsigned int* channels, unsigned int* sampleRate, drflac_uint64* totalPCMFrameCount, const drflac_allocation_callbacks* pAllocationCallbacks)
{
    drflac* pFlac;

    if (sampleRate) {
        *sampleRate = 0;
    }
    if (channels) {
        *channels = 0;
    }
    if (totalPCMFrameCount) {
        *totalPCMFrameCount = 0;
    }

    pFlac = drflac_open_file(filename, pAllocationCallbacks);
    if (pFlac == NULL) {
        return NULL;
    }

    return drflac__full_read_and_close_s32(pFlac, channels, sampleRate, totalPCMFrameCount);
}

DRFLAC_API drflac_int16* drflac_open_file_and_read_pcm_frames_s16(const char* filename, unsigned int* channels, unsigned int* sampleRate, drflac_uint64* totalPCMFrameCount, const drflac_allocation_callbacks* pAllocationCallbacks)
{
    drflac* pFlac;

    if (sampleRate) {
        *sampleRate = 0;
    }
    if (channels) {
        *channels = 0;
    }
    if (totalPCMFrameCount) {
        *totalPCMFrameCount = 0;
    }

    pFlac = drflac_open_file(filename, pAllocationCallbacks);
    if (pFlac == NULL) {
        return NULL;
    }

    return drflac__full_read_and_close_s16(pFlac, channels, sampleRate, totalPCMFrameCount);
}

DRFLAC_API float* drflac_open_file_and_read_pcm_frames_f32(const char* filename, unsigned int* channels, unsigned int* sampleRate, drflac_uint64* totalPCMFrameCount, const drflac_allocation_callbacks* pAllocationCallbacks)
{
    drflac* pFlac;

    if (sampleRate) {
        *sampleRate = 0;
    }
    if (channels) {
        *channels = 0;
    }
    if (totalPCMFrameCount) {
        *totalPCMFrameCount = 0;
    }

    pFlac = drflac_open_file(filename, pAllocationCallbacks);
    if (pFlac == NULL) {
        return NULL;
    }

    return drflac__full_read_and_close_f32(pFlac, channels, sampleRate, totalPCMFrameCount);
}
#endif

DRFLAC_API drflac_int32* drflac_open_memory_and_read_pcm_frames_s32(const void* data, size_t dataSize, unsigned int* channels, unsigned int* sampleRate, drflac_uint64* totalPCMFrameCount, const drflac_allocation_callbacks* pAllocationCallbacks)
{
    drflac* pFlac;

    if (sampleRate) {
        *sampleRate = 0;
    }
    if (channels) {
        *channels = 0;
    }
    if (totalPCMFrameCount) {
        *totalPCMFrameCount = 0;
    }

    pFlac = drflac_open_memory(data, dataSize, pAllocationCallbacks);
    if (pFlac == NULL) {
        return NULL;
    }

    return drflac__full_read_and_close_s32(pFlac, channels, sampleRate, totalPCMFrameCount);
}

DRFLAC_API drflac_int16* drflac_open_memory_and_read_pcm_frames_s16(const void* data, size_t dataSize, unsigned int* channels, unsigned int* sampleRate, drflac_uint64* totalPCMFrameCount, const drflac_allocation_callbacks* pAllocationCallbacks)
{
    drflac* pFlac;

    if (sampleRate) {
        *sampleRate = 0;
    }
    if (channels) {
        *channels = 0;
    }
    if (totalPCMFrameCount) {
        *totalPCMFrameCount = 0;
    }

    pFlac = drflac_open_memory(data, dataSize, pAllocationCallbacks);
    if (pFlac == NULL) {
        return NULL;
    }

    return drflac__full_read_and_close_s16(pFlac, channels, sampleRate, totalPCMFrameCount);
}

DRFLAC_API float* drflac_open_memory_and_read_pcm_frames_f32(const void* data, size_t dataSize, unsigned int* channels, unsigned int* sampleRate, drflac_uint64* totalPCMFrameCount, const drflac_allocation_callbacks* pAllocationCallbacks)
{
    drflac* pFlac;

    if (sampleRate) {
        *sampleRate = 0;
    }
    if (channels) {
        *channels = 0;
    }
    if (totalPCMFrameCount) {
        *totalPCMFrameCount = 0;
    }

    pFlac = drflac_open_memory(data, dataSize, pAllocationCallbacks);
    if (pFlac == NULL) {
        return NULL;
    }

    return drflac__full_read_and_close_f32(pFlac, channels, sampleRate, totalPCMFrameCount);
}


DRFLAC_API void drflac_free(void* p, const drflac_allocation_callbacks* pAllocationCallbacks)
{
    if (pAllocationCallbacks != NULL) {
        drflac__free_from_callbacks(p, pAllocationCallbacks);
    } else {
        drflac__free_default(p, NULL);
    }
}




DRFLAC_API void drflac_init_vorbis_comment_iterator(drflac_vorbis_comment_iterator* pIter, drflac_uint32 commentCount, const void* pComments)
{
    if (pIter == NULL) {
        return;
    }

    pIter->countRemaining = commentCount;
    pIter->pRunningData   = (const char*)pComments;
}

DRFLAC_API const char* drflac_next_vorbis_comment(drflac_vorbis_comment_iterator* pIter, drflac_uint32* pCommentLengthOut)
{
    drflac_int32 length;
    const char* pComment;

    /* Safety. */
    if (pCommentLengthOut) {
        *pCommentLengthOut = 0;
    }

    if (pIter == NULL || pIter->countRemaining == 0 || pIter->pRunningData == NULL) {
        return NULL;
    }

    length = drflac__le2host_32_ptr_unaligned(pIter->pRunningData);
    pIter->pRunningData += 4;

    pComment = pIter->pRunningData;
    pIter->pRunningData += length;
    pIter->countRemaining -= 1;

    if (pCommentLengthOut) {
        *pCommentLengthOut = length;
    }

    return pComment;
}

DRFLAC_API void drflac_init_cuesheet_track_iterator(drflac_cuesheet_track_iterator* pIter, drflac_uint32 trackCount, const void* pTrackData)
{
    if (pIter == NULL) {
        return;
    }

    pIter->countRemaining = trackCount;
    pIter->pRunningData   = (const char*)pTrackData;
}

DRFLAC_API drflac_bool32 drflac_next_cuesheet_track(drflac_cuesheet_track_iterator* pIter, drflac_cuesheet_track* pCuesheetTrack)
{
    drflac_cuesheet_track cuesheetTrack;
    const char* pRunningData;
    drflac_uint64 offsetHi;
    drflac_uint64 offsetLo;

    if (pIter == NULL || pIter->countRemaining == 0 || pIter->pRunningData == NULL) {
        return DRFLAC_FALSE;
    }

    pRunningData = pIter->pRunningData;

    offsetHi                   = drflac__be2host_32(*(const drflac_uint32*)pRunningData); pRunningData += 4;
    offsetLo                   = drflac__be2host_32(*(const drflac_uint32*)pRunningData); pRunningData += 4;
    cuesheetTrack.offset       = offsetLo | (offsetHi << 32);
    cuesheetTrack.trackNumber  = pRunningData[0];                                         pRunningData += 1;
    DRFLAC_COPY_MEMORY(cuesheetTrack.ISRC, pRunningData, sizeof(cuesheetTrack.ISRC));     pRunningData += 12;
    cuesheetTrack.isAudio      = (pRunningData[0] & 0x80) != 0;
    cuesheetTrack.preEmphasis  = (pRunningData[0] & 0x40) != 0;                           pRunningData += 14;
    cuesheetTrack.indexCount   = pRunningData[0];                                         pRunningData += 1;
    cuesheetTrack.pIndexPoints = (const drflac_cuesheet_track_index*)pRunningData;        pRunningData += cuesheetTrack.indexCount * sizeof(drflac_cuesheet_track_index);

    pIter->pRunningData = pRunningData;
    pIter->countRemaining -= 1;

    if (pCuesheetTrack) {
        *pCuesheetTrack = cuesheetTrack;
    }

    return DRFLAC_TRUE;
}

#if defined(__clang__) || (defined(__GNUC__) && (__GNUC__ > 4 || (__GNUC__ == 4 && __GNUC_MINOR__ >= 6)))
#pragma GCC diagnostic pop
#endif
