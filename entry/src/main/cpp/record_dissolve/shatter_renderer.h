// Adapted from Petrel by miramira8295 and contributors, Apache-2.0.
// Upstream commit: ed218f4559cf083b51b08c5bf0bb27ea6215cbb9
// See rawfile/third_party/petrel/LICENSE.txt and NOTICE.txt.
// Modifications: independent module, bounded row ownership and render timing summaries.
#ifndef PETRELGRAM_SHATTER_RENDERER_H
#define PETRELGRAM_SHATTER_RENDERER_H

#include "napi/native_api.h"

void ShatterRegister(napi_env env, napi_value exports);

#endif
