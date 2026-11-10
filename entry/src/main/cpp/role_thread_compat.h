#pragma once
#include <pthread.h>
#include <sched.h>
#include <errno.h>

// OHOS exposes sched_setaffinity but not pthread_setaffinity_np. ggml calls this
// only for its current worker. Keep upstream sources intact and use the public API.
static inline int role_set_current_affinity(pthread_t thread, size_t size, const cpu_set_t *set) {
    if (!pthread_equal(thread, pthread_self())) return ENOTSUP;
    return sched_setaffinity(0, size, set) == 0 ? 0 : errno;
}
#define pthread_setaffinity_np role_set_current_affinity
