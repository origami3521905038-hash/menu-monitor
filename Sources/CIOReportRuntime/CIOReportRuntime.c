#include "CIOReportRuntime.h"

#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// These private function declarations are isolated in this runtime-loaded adapter.
// No Swift code reaches the IOReport ABI directly.
typedef CFDictionaryRef (*MMCopyChannelsInGroup)(CFStringRef, CFStringRef,
                                                  uint64_t, uint64_t, uint64_t);
typedef void *(*MMCreateSubscription)(void *, CFMutableDictionaryRef,
                                      CFMutableDictionaryRef *, uint64_t, CFTypeRef);
typedef CFDictionaryRef (*MMCreateSamples)(void *, CFMutableDictionaryRef, CFTypeRef);
typedef CFStringRef (*MMChannelString)(CFDictionaryRef);
typedef int32_t (*MMChannelFormat)(CFDictionaryRef);
typedef int64_t (*MMSimpleInteger)(CFDictionaryRef, int32_t);

struct MMIOReportRuntime {
    void *image;
    CFMutableDictionaryRef channels;
    void *subscription;
    MMCopyChannelsInGroup copyChannelsInGroup;
    MMCreateSamples createSamples;
    MMChannelString channelGroup;
    MMChannelString channelName;
    MMChannelString unitLabel;
    MMChannelFormat channelFormat;
    MMSimpleInteger integerValue;
    char failure[96];
};

static void MMSetFailure(MMIOReportRuntime *runtime, const char *message) {
    if (runtime == NULL) {
        return;
    }
    (void)snprintf(runtime->failure, sizeof(runtime->failure), "%s", message);
}

static bool MMLoadSymbol(void *image, const char *name, void **destination) {
    *destination = dlsym(image, name);
    return *destination != NULL;
}

static bool MMStringToUTF8(CFStringRef source, char *destination, CFIndex capacity) {
    if (source == NULL || CFGetTypeID(source) != CFStringGetTypeID()) {
        return false;
    }
    return CFStringGetCString(source, destination, capacity, kCFStringEncodingUTF8);
}

MMIOReportRuntime *MMIOReportRuntimeCreate(void) {
    MMIOReportRuntime *runtime = calloc(1, sizeof(MMIOReportRuntime));
    if (runtime == NULL) {
        return NULL;
    }

    runtime->image = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY | RTLD_LOCAL);
    if (runtime->image == NULL) {
        MMSetFailure(runtime, "IOReport runtime is unavailable");
        return runtime;
    }

    MMCreateSubscription createSubscription = NULL;
    bool loaded =
        MMLoadSymbol(runtime->image, "IOReportCopyChannelsInGroup",
                     (void **)&runtime->copyChannelsInGroup) &&
        MMLoadSymbol(runtime->image, "IOReportCreateSubscription",
                     (void **)&createSubscription) &&
        MMLoadSymbol(runtime->image, "IOReportCreateSamples",
                     (void **)&runtime->createSamples) &&
        MMLoadSymbol(runtime->image, "IOReportChannelGetGroup",
                     (void **)&runtime->channelGroup) &&
        MMLoadSymbol(runtime->image, "IOReportChannelGetChannelName",
                     (void **)&runtime->channelName) &&
        MMLoadSymbol(runtime->image, "IOReportChannelGetUnitLabel",
                     (void **)&runtime->unitLabel) &&
        MMLoadSymbol(runtime->image, "IOReportChannelGetFormat",
                     (void **)&runtime->channelFormat) &&
        MMLoadSymbol(runtime->image, "IOReportSimpleGetIntegerValue",
                     (void **)&runtime->integerValue);
    if (!loaded) {
        MMSetFailure(runtime, "IOReport symbols are unavailable");
        return runtime;
    }

    CFDictionaryRef discovered = runtime->copyChannelsInGroup(CFSTR("Energy Model"),
                                                                NULL, 0, 0, 0);
    if (discovered == NULL || CFGetTypeID(discovered) != CFDictionaryGetTypeID()) {
        if (discovered != NULL) {
            CFRelease(discovered);
        }
        MMSetFailure(runtime, "Energy Model channels are unavailable");
        return runtime;
    }

    runtime->channels = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, discovered);
    CFRelease(discovered);
    if (runtime->channels == NULL) {
        MMSetFailure(runtime, "Energy Model channels cannot be copied");
        return runtime;
    }

    const void *rawChannels = CFDictionaryGetValue(runtime->channels, CFSTR("IOReportChannels"));
    if (rawChannels == NULL || CFGetTypeID(rawChannels) != CFArrayGetTypeID() ||
        CFArrayGetCount((CFArrayRef)rawChannels) <= 0 ||
        CFArrayGetCount((CFArrayRef)rawChannels) > 256) {
        MMSetFailure(runtime, "Energy Model channel list is invalid");
        return runtime;
    }

    // Preserve the query dictionary metadata, but subscribe to only the exact aggregate
    // records this version understands. This avoids both unnecessary work and accidental
    // double counting of per-core, PCI, package, or diagnostic channels.
    CFArrayRef catalog = (CFArrayRef)rawChannels;
    CFMutableArrayRef selected = CFArrayCreateMutable(kCFAllocatorDefault, 3,
                                                       &kCFTypeArrayCallBacks);
    if (selected == NULL) {
        MMSetFailure(runtime, "Energy Model selection cannot be created");
        return runtime;
    }
    for (CFIndex index = 0; index < CFArrayGetCount(catalog); index++) {
        const void *item = CFArrayGetValueAtIndex(catalog, index);
        if (item == NULL || CFGetTypeID(item) != CFDictionaryGetTypeID()) {
            CFRelease(selected);
            MMSetFailure(runtime, "Energy Model catalog is malformed");
            return runtime;
        }
        CFDictionaryRef channel = (CFDictionaryRef)item;
        char group[32] = {0};
        char name[64] = {0};
        if (!MMStringToUTF8(runtime->channelGroup(channel), group, sizeof(group)) ||
            !MMStringToUTF8(runtime->channelName(channel), name, sizeof(name))) {
            CFRelease(selected);
            MMSetFailure(runtime, "Energy Model catalog label is invalid");
            return runtime;
        }
        if (strcmp(group, "Energy Model") == 0 &&
            (strcmp(name, "CPU Energy") == 0 ||
             strcmp(name, "GPU Energy") == 0 ||
             strcmp(name, "DRAM Energy") == 0)) {
            CFArrayAppendValue(selected, channel);
        }
    }
    if (CFArrayGetCount(selected) == 0) {
        CFRelease(selected);
        MMSetFailure(runtime, "Supported Energy Model channels are unavailable");
        return runtime;
    }
    CFDictionarySetValue(runtime->channels, CFSTR("IOReportChannels"), selected);
    CFRelease(selected);

    CFMutableDictionaryRef subscriptionChannels = NULL;
    runtime->subscription = createSubscription(NULL, runtime->channels,
                                                &subscriptionChannels, 0, NULL);
    if (subscriptionChannels != NULL) {
        CFRelease(subscriptionChannels);
    }
    if (runtime->subscription == NULL) {
        MMSetFailure(runtime, "Energy Model subscription cannot be created");
        return runtime;
    }

    MMSetFailure(runtime, "");
    return runtime;
}

void MMIOReportRuntimeDestroy(MMIOReportRuntime *runtime) {
    if (runtime == NULL) {
        return;
    }
    // IOReport exposes no documented subscription destructor. Keep the dylib loaded
    // until process termination and release only ownership we can prove is CF-managed.
    if (runtime->channels != NULL) {
        CFRelease(runtime->channels);
    }
    free(runtime);
}

int MMIOReportRuntimeRead(MMIOReportRuntime *runtime,
                          MMIOReportChannel *channels,
                          size_t capacity,
                          size_t *count) {
    if (count != NULL) {
        *count = 0;
    }
    if (runtime == NULL || channels == NULL || count == NULL || capacity == 0 ||
        runtime->subscription == NULL || runtime->channels == NULL ||
        runtime->createSamples == NULL) {
        return MMIOReportResultUnavailable;
    }

    CFDictionaryRef samples = runtime->createSamples(runtime->subscription, runtime->channels, NULL);
    if (samples == NULL || CFGetTypeID(samples) != CFDictionaryGetTypeID()) {
        if (samples != NULL) {
            CFRelease(samples);
        }
        MMSetFailure(runtime, "Energy Model sample is invalid");
        return MMIOReportResultMalformed;
    }

    const void *rawChannels = CFDictionaryGetValue(samples, CFSTR("IOReportChannels"));
    if (rawChannels == NULL || CFGetTypeID(rawChannels) != CFArrayGetTypeID()) {
        CFRelease(samples);
        MMSetFailure(runtime, "Energy Model sample channels are invalid");
        return MMIOReportResultMalformed;
    }

    CFArrayRef source = (CFArrayRef)rawChannels;
    CFIndex sourceCount = CFArrayGetCount(source);
    if (sourceCount < 0 || sourceCount > 256) {
        CFRelease(samples);
        MMSetFailure(runtime, "Energy Model sample count is invalid");
        return MMIOReportResultMalformed;
    }

    size_t written = 0;
    for (CFIndex index = 0; index < sourceCount; index++) {
        const void *item = CFArrayGetValueAtIndex(source, index);
        if (item == NULL || CFGetTypeID(item) != CFDictionaryGetTypeID()) {
            CFRelease(samples);
            MMSetFailure(runtime, "Energy Model channel is invalid");
            return MMIOReportResultMalformed;
        }
        CFDictionaryRef channel = (CFDictionaryRef)item;
        CFStringRef group = runtime->channelGroup(channel);
        CFStringRef name = runtime->channelName(channel);
        CFStringRef unit = runtime->unitLabel(channel);
        char groupBuffer[32] = {0};
        if (!MMStringToUTF8(group, groupBuffer, sizeof(groupBuffer)) ||
            strcmp(groupBuffer, "Energy Model") != 0) {
            continue;
        }
        if (written >= capacity) {
            CFRelease(samples);
            MMSetFailure(runtime, "Energy Model output capacity exceeded");
            return MMIOReportResultCapacityExceeded;
        }
        if (!MMStringToUTF8(name, channels[written].name, sizeof(channels[written].name)) ||
            !MMStringToUTF8(unit, channels[written].unit, sizeof(channels[written].unit))) {
            CFRelease(samples);
            MMSetFailure(runtime, "Energy Model label is invalid");
            return MMIOReportResultMalformed;
        }
        // IOReportSimpleGetIntegerValue is valid only for simple integer channels.
        // A same-named channel with another representation is unsupported rather
        // than an invitation to reinterpret private ABI data.
        if (runtime->channelFormat(channel) != 1) {
            CFRelease(samples);
            MMSetFailure(runtime, "Energy Model channel format is unsupported");
            return MMIOReportResultMalformed;
        }
        channels[written].cumulativeValue = runtime->integerValue(channel, 0);
        written++;
    }

    CFRelease(samples);
    *count = written;
    return MMIOReportResultOK;
}

const char *MMIOReportRuntimeFailure(MMIOReportRuntime *runtime) {
    return runtime == NULL ? "IOReport runtime is unavailable" : runtime->failure;
}
