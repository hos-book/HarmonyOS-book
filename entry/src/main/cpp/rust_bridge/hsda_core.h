#pragma once
#include <cstddef>
#include <cstdint>

template<typename T> struct HsdaBuffer { T *data; size_t len; uint32_t status; };
struct HsdaInputBytes { const uint8_t *data; size_t len; };
struct HsdaInputText { const uint16_t *data; size_t len; };

extern "C" {
HsdaBuffer<uint16_t> hsda_text(const uint16_t *input, size_t length, uint32_t operation);
void hsda_text_free(HsdaBuffer<uint16_t> buffer);
HsdaBuffer<uint16_t> hsda_html_bounded(const uint16_t *input, size_t length, bool encode, uint32_t timeoutMs);
HsdaBuffer<uint32_t> hsda_search(const uint16_t *input, size_t length, const uint16_t *query,
    size_t queryLength, size_t limit);
void hsda_offsets_free(HsdaBuffer<uint32_t> buffer);
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
HsdaBuffer<uint16_t> hsda_epub_images(const uint16_t *text, size_t length,
    const uint16_t *prefix, size_t prefixLength, const HsdaInputText *images, size_t count);
}
