#pragma once
#include <cstddef>
#include <cstdint>

template<typename T> struct HsdaBuffer { T *data; size_t len; uint32_t status; };
struct HsdaInputBytes { const uint8_t *data; size_t len; };
struct HsdaInputText { const uint16_t *data; size_t len; };
struct HsdaRankingBook {
    HsdaBuffer<uint16_t> fields[8];
    double rank, rating;
    uint32_t contentType;
};
struct HsdaRankingResult { HsdaBuffer<HsdaRankingBook> books; double fetchedAt; };
struct HsdaTxtSection {
    HsdaBuffer<uint16_t> title;
    HsdaBuffer<uint16_t> content;
    bool preserveChapter;
};
struct HsdaReaderDisplay { HsdaBuffer<uint16_t> text; HsdaBuffer<uint32_t> indents; };
struct HsdaSpeechSegment {
    HsdaBuffer<uint16_t> text;
    size_t start, end, leadingWhitespace, paragraphStart, paragraphEnd;
};
struct HsdaSubtitleInput { HsdaInputText text; double startMs, endMs; bool flag; };
struct HsdaSubtitleSpan { HsdaBuffer<uint16_t> text; double startMs, endMs; bool flag; };
struct HsdaSubtitleChunk {
    uint32_t index;
    const HsdaSubtitleInput *annotated;
    size_t annotatedCount;
    const HsdaSubtitleInput *cues;
    size_t cueCount;
};

extern "C" {
HsdaRankingResult hsda_ranking(const HsdaInputText *input, bool cached, double now);
void hsda_ranking_free(HsdaRankingResult result);
HsdaBuffer<uint16_t> hsda_text(const uint16_t *input, size_t length, uint32_t operation);
void hsda_text_free(HsdaBuffer<uint16_t> buffer);
HsdaBuffer<uint16_t> hsda_html_bounded(const uint16_t *input, size_t length, bool encode, uint32_t timeoutMs);
HsdaBuffer<uint32_t> hsda_search(const uint16_t *input, size_t length, const uint16_t *query,
    size_t queryLength, size_t limit);
void hsda_offsets_free(HsdaBuffer<uint32_t> buffer);
HsdaBuffer<uint32_t> hsda_source_tag_pairs(const uint16_t *input, size_t length,
    const uint16_t *tag, size_t tagLength);
void hsda_white_border(const uint8_t *input, size_t length, size_t width, size_t height, double *output);
HsdaBuffer<uint8_t> hsda_wave(const float *samples, size_t length, uint32_t rate);
HsdaBuffer<uint8_t> hsda_palmdoc(const uint8_t *input, size_t length, size_t capacity);
void hsda_bytes_free(HsdaBuffer<uint8_t> buffer);
void *hsda_huff_create(const HsdaInputBytes *records, size_t count, size_t capacity, uint32_t *status);
HsdaBuffer<uint8_t> hsda_huff_unpack(void *decoder, const uint8_t *input, size_t length);
void hsda_huff_release(void *decoder);
HsdaBuffer<HsdaBuffer<uint8_t>> hsda_kf8(const uint8_t *raw, size_t length,
    const HsdaInputBytes *records, size_t count, size_t skeletonCount);
void hsda_sections_free(HsdaBuffer<HsdaBuffer<uint8_t>> buffer);
HsdaBuffer<uint16_t> hsda_epub_body(const uint16_t *text, size_t length,
    const uint16_t *prefix, size_t prefixLength, const HsdaInputText *images, size_t count);
void *hsda_txt_create(const uint16_t *title, size_t length);
HsdaBuffer<HsdaTxtSection> hsda_txt_feed(void *parser, const uint16_t *input, size_t length, bool finalChunk);
void hsda_txt_release(void *parser);
void hsda_txt_sections_free(HsdaBuffer<HsdaTxtSection> sections);
HsdaReaderDisplay hsda_reader_indent(const uint16_t *input, size_t length, size_t hiddenPrefix);
void hsda_reader_display_free(HsdaReaderDisplay display);
HsdaBuffer<HsdaSpeechSegment> hsda_speech_split(const uint16_t *input, size_t length,
    const uint32_t *boundaries, size_t count, bool filter, size_t maxLength, size_t hardLimit);
void hsda_speech_free(HsdaBuffer<HsdaSpeechSegment> segments);
HsdaBuffer<HsdaSubtitleSpan> hsda_subtitle_join(const HsdaSubtitleInput *previous, size_t previousCount,
    const HsdaSubtitleInput *current, size_t currentCount, double boundaryMs);
HsdaBuffer<HsdaSubtitleSpan> hsda_subtitle_punctuate(const HsdaSubtitleInput *units, size_t count,
    const uint16_t *output, size_t length, bool finalChunk);
void *hsda_subtitle_dictionary(const HsdaInputText *words, size_t count);
void hsda_subtitle_dictionary_free(void *dictionary);
HsdaBuffer<HsdaSubtitleSpan> hsda_subtitle_timeline(const HsdaSubtitleChunk *chunks, size_t count,
    const void *dictionary);
void hsda_subtitle_free(HsdaBuffer<HsdaSubtitleSpan> spans);
}
