#include "audio_metadata.h"

AudioMetadata parseAudioMetadata(const std::string& filePath) {
    AudioMetadata metadata;
    metadata.title = "";
    metadata.artist = "未知艺术家";
    metadata.album = "未知专辑";
    metadata.durationMs = 0;
    metadata.sampleRate = 44100;
    metadata.channels = 2;

    size_t lastSlash = filePath.find_last_of('/');
    size_t lastDot = filePath.find_last_of('.');
    if (lastSlash != std::string::npos && lastDot != std::string::npos && lastDot > lastSlash) {
        metadata.title = filePath.substr(lastSlash + 1, lastDot - lastSlash - 1);
    } else if (lastSlash != std::string::npos) {
        metadata.title = filePath.substr(lastSlash + 1);
    } else {
        metadata.title = filePath;
    }

    return metadata;
}
