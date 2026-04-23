#ifndef SIGNALSMITH_STRETCH_C_H
#define SIGNALSMITH_STRETCH_C_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void *signalsmith_stretch_t;
typedef float (*signalsmith_stretch_freq_map_fn)(void *userdata, float input_freq);

signalsmith_stretch_t signalsmith_stretch_init(void);
signalsmith_stretch_t signalsmith_stretch_init_seed(long seed);
void signalsmith_stretch_release(signalsmith_stretch_t context);

void signalsmith_stretch_reset(signalsmith_stretch_t context);

void signalsmith_stretch_preset_default(signalsmith_stretch_t context, int channels, float sample_rate, bool split_computation);
void signalsmith_stretch_preset_cheaper(signalsmith_stretch_t context, int channels, float sample_rate, bool split_computation);
void signalsmith_stretch_configure(signalsmith_stretch_t context, int channels, int block_samples, int interval_samples, bool split_computation);

int signalsmith_stretch_input_latency(const signalsmith_stretch_t context);
int signalsmith_stretch_output_latency(const signalsmith_stretch_t context);
int signalsmith_stretch_block_samples(const signalsmith_stretch_t context);
int signalsmith_stretch_interval_samples(const signalsmith_stretch_t context);
bool signalsmith_stretch_split_computation(const signalsmith_stretch_t context);

void signalsmith_stretch_set_transpose_factor(signalsmith_stretch_t context, float multiplier, float tonality_limit);
void signalsmith_stretch_set_transpose_semitones(signalsmith_stretch_t context, float semitones, float tonality_limit);
void signalsmith_stretch_set_freq_map(signalsmith_stretch_t context, signalsmith_stretch_freq_map_fn callback, void *userdata);
void signalsmith_stretch_set_formant_factor(signalsmith_stretch_t context, float multiplier, bool compensate_pitch);
void signalsmith_stretch_set_formant_semitones(signalsmith_stretch_t context, float semitones, bool compensate_pitch);
void signalsmith_stretch_set_formant_base(signalsmith_stretch_t context, float base_freq);

void signalsmith_stretch_seek(signalsmith_stretch_t context, const float *const *inputs, int input_samples, double playback_rate);
int signalsmith_stretch_seek_length(const signalsmith_stretch_t context);
void signalsmith_stretch_output_seek(signalsmith_stretch_t context, const float *const *inputs, int input_length);
int signalsmith_stretch_output_seek_length(const signalsmith_stretch_t context, float playback_rate);

void signalsmith_stretch_process(
    signalsmith_stretch_t context,
    const float *const *inputs,
    int input_samples,
    float *const *outputs,
    int output_samples
);
void signalsmith_stretch_flush(signalsmith_stretch_t context, float *const *outputs, int output_samples, float playback_rate);
bool signalsmith_stretch_exact(
    signalsmith_stretch_t context,
    const float *const *inputs,
    int input_samples,
    float *const *outputs,
    int output_samples
);

#ifdef __cplusplus
}
#endif

#endif // !SIGNALSMITH_STRETCH_C_H
