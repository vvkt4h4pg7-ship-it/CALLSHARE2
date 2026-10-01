#ifndef AMR_CODEC_BRIDGE_H
#define AMR_CODEC_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Encodes exactly one 20 ms AMR-NB frame (8 kHz, mono, 160 signed-16 PCM samples).
/// This intentionally matches the Android K7 source: mode=1 (MR515 / 5.15 kbps), DTX=0.
/// Returns the number of encoded bytes, or a negative error code.
int amr_codec_encode_frame(const int16_t *pcm160, size_t samples, uint8_t *out, size_t outCapacity);

/// Decodes one K7 AMR-NB frame into exactly 160 signed-16 PCM samples.
/// Returns 160 on success, or a negative error code.
int amr_codec_decode_frame(const uint8_t *amr, size_t length, int16_t *pcm160, size_t pcmCapacity);

/// Releases native encoder/decoder state. Safe to call more than once.
void amr_codec_reset(void);

#ifdef __cplusplus
}
#endif

#endif
