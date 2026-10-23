#include "bounded_image_transform.h"
#include <multimedia/image_framework/image/image_source_native.h>
#include <multimedia/image_framework/image/image_packer_native.h>
#include <multimedia/image_framework/image/pixelmap_native.h>
#include <cmath>
#include <cstring>
#include <memory>
#include <stdexcept>

namespace {
constexpr size_t MAX_BYTES = 20 * 1024 * 1024;
constexpr size_t MAX_PIXELS = 4 * 1024 * 1024;

struct StripOptions {
    uint32_t count = 0;
    std::vector<uint32_t> order;
    bool remainderFirst = false;
    std::string format = "image/png";
    uint32_t quality = 95;
};

bool Number(JSContext* ctx, JSValueConst value, uint32_t max, uint32_t& output) {
    double number = 0;
    if (!JS_IsNumber(value) || JS_ToFloat64(ctx, &number, value) < 0 || !std::isfinite(number) ||
        number < 0 || number > max || std::floor(number) != number) return false;
    output = static_cast<uint32_t>(number);
    return true;
}

bool String(JSContext* ctx, JSValueConst value, std::string& output) {
    if (!JS_IsString(value)) return false;
    const char* text = JS_ToCString(ctx, value);
    if (!text) return false;
    output = text;
    JS_FreeCString(ctx, text);
    return true;
}

bool Parse(JSContext* ctx, const std::string& text, StripOptions& options) {
    JSValue object = JS_ParseJSON(ctx, text.c_str(), text.size(), "image.reorderStrips");
    if (JS_IsException(object)) {
        JS_FreeValue(ctx, JS_GetException(ctx));
        return false;
    }
    if (!JS_IsObject(object) || JS_IsNull(object) || JS_IsArray(ctx, object)) {
        JS_FreeValue(ctx, object);
        return false;
    }
    JSValue value = JS_GetPropertyStr(ctx, object, "count");
    bool valid = Number(ctx, value, 256, options.count) && options.count > 0;
    JS_FreeValue(ctx, value);
    value = JS_GetPropertyStr(ctx, object, "remainder");
    if (!JS_IsUndefined(value)) {
        std::string remainder;
        valid = String(ctx, value, remainder) && (remainder == "first" || remainder == "last") && valid;
        options.remainderFirst = remainder == "first";
    }
    JS_FreeValue(ctx, value);
    value = JS_GetPropertyStr(ctx, object, "format");
    if (!JS_IsUndefined(value)) valid = String(ctx, value, options.format) && valid;
    valid = (options.format == "image/png" || options.format == "image/jpeg" || options.format == "image/webp") && valid;
    JS_FreeValue(ctx, value);
    value = JS_GetPropertyStr(ctx, object, "quality");
    if (!JS_IsUndefined(value)) valid = Number(ctx, value, 100, options.quality) && valid;
    JS_FreeValue(ctx, value);
    value = JS_GetPropertyStr(ctx, object, "order");
    if (JS_IsUndefined(value)) {
        for (uint32_t index = options.count; index > 0; --index) options.order.push_back(index - 1);
    } else if (JS_IsArray(ctx, value)) {
        JSValue length = JS_GetPropertyStr(ctx, value, "length");
        uint32_t size = 0;
        valid = Number(ctx, length, 256, size) && size == options.count && valid;
        JS_FreeValue(ctx, length);
        bool used[256] = {};
        for (uint32_t index = 0; valid && index < size; ++index) {
            JSValue item = JS_GetPropertyUint32(ctx, value, index);
            uint32_t number = 0;
            valid = Number(ctx, item, options.count - 1, number) && !used[number];
            JS_FreeValue(ctx, item);
            used[number] = true;
            options.order.push_back(number);
        }
    } else valid = false;
    JS_FreeValue(ctx, value);
    JS_FreeValue(ctx, object);
    return valid;
}

void Check(Image_ErrorCode code) {
    if (code != IMAGE_SUCCESS) throw std::runtime_error("reorderStrips ImageKit error " + std::to_string(code));
}

struct Resources {
    OH_ImageSourceNative* source = nullptr;
    OH_ImageSource_Info* info = nullptr;
    OH_DecodingOptions* decoding = nullptr;
    OH_PixelmapNative* pixelmap = nullptr;
    OH_Pixelmap_ImageInfo* pixelInfo = nullptr;
    OH_Pixelmap_InitializationOptions* initialization = nullptr;
    OH_ImagePackerNative* packer = nullptr;
    OH_PackingOptions* packing = nullptr;
    ~Resources() {
        if (packing) OH_PackingOptions_Release(packing);
        if (packer) OH_ImagePackerNative_Release(packer);
        if (initialization) OH_PixelmapInitializationOptions_Release(initialization);
        if (pixelInfo) OH_PixelmapImageInfo_Release(pixelInfo);
        if (pixelmap) OH_PixelmapNative_Release(pixelmap);
        if (decoding) OH_DecodingOptions_Release(decoding);
        if (info) OH_ImageSourceInfo_Release(info);
        if (source) OH_ImageSourceNative_Release(source);
    }
};
}

bool ReorderImageStrips(JSContext* ctx, const std::string& json, const uint8_t* input, size_t inputSize,
    const std::function<bool()>& stopped, std::vector<uint8_t>& output, std::string& error) {
    try {
        StripOptions options;
        if (!Parse(ctx, json, options)) throw std::runtime_error("reorderStrips invalid count/order/remainder/format/quality");
        if (!input || !inputSize || inputSize > MAX_BYTES) throw std::runtime_error("reorderStrips image exceeds 20 MiB");
        const auto check = [&]() { if (stopped()) throw std::runtime_error("reorderStrips stopped"); };
        check();
        if (options.count == 1) { output.assign(input, input + inputSize); return true; }
        Resources resources;
        Check(OH_ImageSourceNative_CreateFromData(const_cast<uint8_t*>(input), inputSize, &resources.source));
        Check(OH_ImageSourceInfo_Create(&resources.info));
        Check(OH_ImageSourceNative_GetImageInfo(resources.source, 0, resources.info));
        uint32_t width = 0, height = 0, frames = 0;
        Check(OH_ImageSourceInfo_GetWidth(resources.info, &width));
        Check(OH_ImageSourceInfo_GetHeight(resources.info, &height));
        if (!width || width > 16384 || height < options.count || height > 16384 ||
            static_cast<uint64_t>(width) * height > MAX_PIXELS) throw std::runtime_error("reorderStrips image exceeds 4 Mi pixels or dimensions");
        Check(OH_ImageSourceNative_GetFrameCount(resources.source, &frames));
        if (frames != 1) throw std::runtime_error("reorderStrips does not process animated images");
        check();
        Check(OH_DecodingOptions_Create(&resources.decoding));
        Check(OH_DecodingOptions_SetPixelFormat(resources.decoding, PIXEL_FORMAT_RGBA_8888));
        Check(OH_ImageSourceNative_CreatePixelmap(resources.source, resources.decoding, &resources.pixelmap));
        Check(OH_PixelmapImageInfo_Create(&resources.pixelInfo));
        Check(OH_PixelmapNative_GetImageInfo(resources.pixelmap, resources.pixelInfo));
        uint32_t stride = 0;
        uint32_t decodedWidth = 0, decodedHeight = 0;
        int32_t pixelFormat = 0, alphaType = 0;
        Check(OH_PixelmapImageInfo_GetWidth(resources.pixelInfo, &decodedWidth));
        Check(OH_PixelmapImageInfo_GetHeight(resources.pixelInfo, &decodedHeight));
        Check(OH_PixelmapImageInfo_GetPixelFormat(resources.pixelInfo, &pixelFormat));
        Check(OH_PixelmapImageInfo_GetAlphaType(resources.pixelInfo, &alphaType));
        if (decodedWidth != width || decodedHeight != height || pixelFormat != PIXEL_FORMAT_RGBA_8888) {
            throw std::runtime_error("reorderStrips unexpected decoded pixel layout");
        }
        Check(OH_PixelmapImageInfo_GetRowStride(resources.pixelInfo, &stride));
        const size_t bytes = static_cast<size_t>(stride) * height;
        if (stride < width * 4 || bytes > MAX_BYTES) throw std::runtime_error("reorderStrips pixel buffer exceeds limit");
        std::vector<uint8_t> original(bytes);
        size_t readSize = original.size();
        Check(OH_PixelmapNative_ReadPixels(resources.pixelmap, original.data(), &readSize));
        if (readSize != bytes) throw std::runtime_error("reorderStrips incomplete pixel data");
        Check(OH_PixelmapNative_Release(resources.pixelmap));
        resources.pixelmap = nullptr;
        check();
        // Build tightly packed RGBA output; decoder row padding must not become image pixels.
        std::vector<uint8_t> reordered(static_cast<size_t>(width) * height * 4);
        const uint32_t base = height / options.count, extra = height % options.count;
        const uint32_t extraIndex = options.remainderFirst ? 0 : options.count - 1;
        uint32_t targetY = 0;
        for (const uint32_t index : options.order) {
            check();
            const uint32_t sourceY = index * base + (index > extraIndex ? extra : 0);
            const uint32_t rows = base + (index == extraIndex ? extra : 0);
            for (uint32_t row = 0; row < rows; ++row) {
                std::memcpy(reordered.data() + static_cast<size_t>(targetY + row) * width * 4,
                    original.data() + static_cast<size_t>(sourceY + row) * stride, width * 4);
            }
            targetY += rows;
        }
        std::vector<uint8_t>().swap(original);
        Check(OH_PixelmapInitializationOptions_Create(&resources.initialization));
        Check(OH_PixelmapInitializationOptions_SetWidth(resources.initialization, width));
        Check(OH_PixelmapInitializationOptions_SetHeight(resources.initialization, height));
        Check(OH_PixelmapInitializationOptions_SetPixelFormat(resources.initialization, PIXEL_FORMAT_RGBA_8888));
        Check(OH_PixelmapInitializationOptions_SetSrcPixelFormat(resources.initialization, PIXEL_FORMAT_RGBA_8888));
        Check(OH_PixelmapInitializationOptions_SetAlphaType(resources.initialization, alphaType));
        Check(OH_PixelmapNative_CreatePixelmap(reordered.data(), reordered.size(), resources.initialization, &resources.pixelmap));
        check();
        Check(OH_ImagePackerNative_Create(&resources.packer));
        Check(OH_PackingOptions_Create(&resources.packing));
        Image_MimeType mime = { const_cast<char*>(options.format.c_str()), options.format.size() };
        Check(OH_PackingOptions_SetMimeType(resources.packing, &mime));
        Check(OH_PackingOptions_SetQuality(resources.packing, options.quality));
        output.resize(MAX_BYTES);
        size_t packedSize = output.size();
        Check(OH_ImagePackerNative_PackToDataFromPixelmap(resources.packer, resources.packing, resources.pixelmap, output.data(), &packedSize));
        if (!packedSize || packedSize > MAX_BYTES) throw std::runtime_error("reorderStrips output exceeds 20 MiB");
        output.resize(packedSize);
        check();
        return true;
    } catch (const std::exception& exception) {
        output.clear();
        error = exception.what();
        return false;
    }
}
