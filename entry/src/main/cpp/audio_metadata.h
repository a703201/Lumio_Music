#pragma once

#include <string>

struct AudioMetadata {
    std::string title;
    std::string artist;
    std::string album;
    int durationMs;
    int sampleRate;
    int channels;
};

AudioMetadata parseAudioMetadata(const std::string& filePath);
