# CALLSHARE AMR-NB V1

This build replaces the empty iOS AMR adapter with an iOS-compileable OpenCORE AMR-NB implementation.

## Android/K7 compatibility verified from the supplied K7 source

- Audio sample rate: 8000 Hz
- Mono PCM: signed 16-bit
- Frame size: 160 samples (20 ms)
- `AmrEncoder.init(0)` => DTX disabled
- `AmrEncoder.encode(1, pcm, out)` => OpenCORE mode 1 = `MR515` / 5.15 kbps
- K7 transport: channel 3
- Android sends the encoder output bytes directly in the channel-3 frame
- Android decoder receives the channel-3 AMR payload directly and outputs 160 PCM samples

The OpenCORE wrapper in this project uses the same `Encoder_Interface_Encode` / `Decoder_Interface_Decode` APIs and the same mode 1 (`MR515`) path.

## iOS changes

- Added `AMRCodecBridge.cpp/.h`
- Added `J7Bridge-Bridging-Header.h`
- Added the OpenCORE AMR-NB source tree under `J7Bridge/OpenCoreAMR/`
- Added the required OpenCORE source files to the Xcode Sources build phase
- `VoiceEngine` now encodes microphone PCM to AMR and sends it through the existing K7 channel-3 BLE framing
- `VoiceEngine` now decodes incoming K7 AMR frames to 8 kHz PCM and schedules them to an `AVAudioPlayerNode`
- `AppModel.maybeStartVoice()` starts local voice as soon as CallKit has activated audio for an ACTIVE call; K7 voice-open is still sent by the existing answer-event path.

## Important

The project cannot be device-built in this Linux environment because Xcode/iOS SDK are not available here. The OpenCORE source set was nevertheless compiled and link-tested on Linux using the same bridge APIs: a silent 160-sample frame encoded successfully and decoded back to 160 samples.
