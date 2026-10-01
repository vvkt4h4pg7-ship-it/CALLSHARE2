#include "AMRCodecBridge.h"

#include <mutex>

#include "OpenCoreAMR/opencore-amr-master/amrnb/interf_enc.h"
#include "OpenCoreAMR/opencore-amr-master/amrnb/interf_dec.h"

namespace {

void *gEncoder = nullptr;
void *gDecoder = nullptr;
std::mutex gEncoderMutex;
std::mutex gDecoderMutex;

}

extern "C" int amr_codec_encode_frame(const int16_t *pcm160,
                                        size_t samples,
                                        uint8_t *out,
                                        size_t outCapacity) {
    if (pcm160 == nullptr || out == nullptr || samples != 160 || outCapacity < 64) {
        return -1;
    }

    std::lock_guard<std::mutex> lock(gEncoderMutex);
    if (gEncoder == nullptr) {
        // Android K7 source: AmrEncoder.init(0) and AmrEncoder.encode(1, ...).
        // OpenCORE enum value 1 is MR515 (5.15 kbps).
        gEncoder = Encoder_Interface_init(0);
    }
    if (gEncoder == nullptr) {
        return -2;
    }

    return Encoder_Interface_Encode(gEncoder,
                                    MR515,
                                    reinterpret_cast<const short *>(pcm160),
                                    reinterpret_cast<unsigned char *>(out),
                                    0);
}

extern "C" int amr_codec_decode_frame(const uint8_t *amr,
                                        size_t length,
                                        int16_t *pcm160,
                                        size_t pcmCapacity) {
    if (amr == nullptr || pcm160 == nullptr || length == 0 || pcmCapacity < 160) {
        return -1;
    }

    std::lock_guard<std::mutex> lock(gDecoderMutex);
    if (gDecoder == nullptr) {
        gDecoder = Decoder_Interface_init();
    }
    if (gDecoder == nullptr) {
        return -2;
    }

    Decoder_Interface_Decode(gDecoder,
                             reinterpret_cast<const unsigned char *>(amr),
                             reinterpret_cast<short *>(pcm160),
                             0);
    return 160;
}

extern "C" void amr_codec_reset(void) {
    {
        std::lock_guard<std::mutex> lock(gEncoderMutex);
        if (gEncoder != nullptr) {
            Encoder_Interface_exit(gEncoder);
            gEncoder = nullptr;
        }
    }

    {
        std::lock_guard<std::mutex> lock(gDecoderMutex);
        if (gDecoder != nullptr) {
            Decoder_Interface_exit(gDecoder);
            gDecoder = nullptr;
        }
    }
}
