
#include <signalsmith-stretch.h>
#include "stretch/signalsmith-stretch.h"

#include <new>

namespace {
struct SignalsmithStretchContext {
    signalsmith::stretch::SignalsmithStretch<float> stretch;

    SignalsmithStretchContext() = default;
    explicit SignalsmithStretchContext(long seed) : stretch(seed) {}
};

static SignalsmithStretchContext *unwrap(signalsmith_stretch_t context) {
    return static_cast<SignalsmithStretchContext *>(context);
}

static const SignalsmithStretchContext *unwrapConst(const signalsmith_stretch_t context) {
    return static_cast<const SignalsmithStretchContext *>(context);
}
} // namespace

extern "C" {

signalsmith_stretch_t signalsmith_stretch_init(void) {
    return new (std::nothrow) SignalsmithStretchContext();
}

signalsmith_stretch_t signalsmith_stretch_init_seed(long seed) {
    return new (std::nothrow) SignalsmithStretchContext(seed);
}

void signalsmith_stretch_release(signalsmith_stretch_t context) {
    delete unwrap(context);
}

void signalsmith_stretch_reset(signalsmith_stretch_t context) {
    auto *ctx = unwrap(context);
    if (!ctx) return;
    ctx->stretch.reset();
}

void signalsmith_stretch_preset_default(signalsmith_stretch_t context, int channels, float sample_rate, bool split_computation) {
    auto *ctx = unwrap(context);
    if (!ctx) return;
    ctx->stretch.presetDefault(channels, sample_rate, split_computation);
}

void signalsmith_stretch_preset_cheaper(signalsmith_stretch_t context, int channels, float sample_rate, bool split_computation) {
    auto *ctx = unwrap(context);
    if (!ctx) return;
    ctx->stretch.presetCheaper(channels, sample_rate, split_computation);
}

void signalsmith_stretch_configure(signalsmith_stretch_t context, int channels, int block_samples, int interval_samples, bool split_computation) {
    auto *ctx = unwrap(context);
    if (!ctx) return;
    ctx->stretch.configure(channels, block_samples, interval_samples, split_computation);
}

int signalsmith_stretch_input_latency(const signalsmith_stretch_t context) {
    auto *ctx = unwrapConst(context);
    return ctx ? ctx->stretch.inputLatency() : 0;
}

int signalsmith_stretch_output_latency(const signalsmith_stretch_t context) {
    auto *ctx = unwrapConst(context);
    return ctx ? ctx->stretch.outputLatency() : 0;
}

int signalsmith_stretch_block_samples(const signalsmith_stretch_t context) {
    auto *ctx = unwrapConst(context);
    return ctx ? ctx->stretch.blockSamples() : 0;
}

int signalsmith_stretch_interval_samples(const signalsmith_stretch_t context) {
    auto *ctx = unwrapConst(context);
    return ctx ? ctx->stretch.intervalSamples() : 0;
}

bool signalsmith_stretch_split_computation(const signalsmith_stretch_t context) {
    auto *ctx = unwrapConst(context);
    return ctx && ctx->stretch.splitComputation();
}

void signalsmith_stretch_set_transpose_factor(signalsmith_stretch_t context, float multiplier, float tonality_limit) {
    auto *ctx = unwrap(context);
    if (!ctx) return;
    ctx->stretch.setTransposeFactor(multiplier, tonality_limit);
}

void signalsmith_stretch_set_transpose_semitones(signalsmith_stretch_t context, float semitones, float tonality_limit) {
    auto *ctx = unwrap(context);
    if (!ctx) return;
    ctx->stretch.setTransposeSemitones(semitones, tonality_limit);
}

void signalsmith_stretch_set_freq_map(signalsmith_stretch_t context, signalsmith_stretch_freq_map_fn callback, void *userdata) {
    auto *ctx = unwrap(context);
    if (!ctx) return;

    if (!callback) {
        ctx->stretch.setFreqMap(nullptr);
        return;
    }

    ctx->stretch.setFreqMap([callback, userdata](float input_freq) {
        return callback(userdata, input_freq);
    });
}

void signalsmith_stretch_set_formant_factor(signalsmith_stretch_t context, float multiplier, bool compensate_pitch) {
    auto *ctx = unwrap(context);
    if (!ctx) return;
    ctx->stretch.setFormantFactor(multiplier, compensate_pitch);
}

void signalsmith_stretch_set_formant_semitones(signalsmith_stretch_t context, float semitones, bool compensate_pitch) {
    auto *ctx = unwrap(context);
    if (!ctx) return;
    ctx->stretch.setFormantSemitones(semitones, compensate_pitch);
}

void signalsmith_stretch_set_formant_base(signalsmith_stretch_t context, float base_freq) {
    auto *ctx = unwrap(context);
    if (!ctx) return;
    ctx->stretch.setFormantBase(base_freq);
}

void signalsmith_stretch_seek(signalsmith_stretch_t context, const float *const *inputs, int input_samples, double playback_rate) {
    auto *ctx = unwrap(context);
    if (!ctx) return;
    ctx->stretch.seek(inputs, input_samples, playback_rate);
}

int signalsmith_stretch_seek_length(const signalsmith_stretch_t context) {
    auto *ctx = unwrapConst(context);
    return ctx ? ctx->stretch.seekLength() : 0;
}

void signalsmith_stretch_output_seek(signalsmith_stretch_t context, const float *const *inputs, int input_length) {
    auto *ctx = unwrap(context);
    if (!ctx) return;
    ctx->stretch.outputSeek(inputs, input_length);
}

int signalsmith_stretch_output_seek_length(const signalsmith_stretch_t context, float playback_rate) {
    auto *ctx = unwrapConst(context);
    return ctx ? ctx->stretch.outputSeekLength(playback_rate) : 0;
}

void signalsmith_stretch_process(
    signalsmith_stretch_t context,
    const float *const *inputs,
    int input_samples,
    float *const *outputs,
    int output_samples
) {
    auto *ctx = unwrap(context);
    if (!ctx) return;
    ctx->stretch.process(inputs, input_samples, outputs, output_samples);
}

void signalsmith_stretch_flush(signalsmith_stretch_t context, float *const *outputs, int output_samples, float playback_rate) {
    auto *ctx = unwrap(context);
    if (!ctx) return;
    ctx->stretch.flush(outputs, output_samples, playback_rate);
}

bool signalsmith_stretch_exact(
    signalsmith_stretch_t context,
    const float *const *inputs,
    int input_samples,
    float *const *outputs,
    int output_samples
) {
    auto *ctx = unwrap(context);
    if (!ctx) return false;
    return ctx->stretch.exact(inputs, input_samples, outputs, output_samples);
}

} // extern "C"
