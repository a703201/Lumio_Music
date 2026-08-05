#pragma once

#include <string>

struct AudioMetadata {
    std::string title;
    std::string artist;
    std::string album;
    std::string year;   // 年代（4 位年份，从 DATE / TYER / TDRC / ©day 提取）
    int durationMs;
    int sampleRate;
    int channels;
};

AudioMetadata parseAudioMetadata(const std::string& filePath);
