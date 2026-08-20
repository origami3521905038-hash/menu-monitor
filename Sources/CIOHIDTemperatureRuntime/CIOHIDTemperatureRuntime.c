#include "CIOHIDTemperatureRuntime.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <math.h>
#include <stdint.h>
#include <string.h>

// The HID temperature event is exposed by Apple's Apple-vendor sensor services.
// These declarations are present in IOKit.framework but are intentionally kept
// out of the public SDK header; all access remains in this narrow read-only shim.
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client,
                                               CFDictionaryRef matching);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service,
                                                   int64_t eventType,
                                                   int32_t options,
                                                   int64_t timeout);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service,
                                                  CFStringRef property);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

enum {
    MMHIDTemperatureUsagePage = 0xff00,
    MMHIDTemperatureUsage = 0x0005,
    MMHIDTemperatureEventType = 15,
    MMHIDTemperatureField = MMHIDTemperatureEventType << 16
};

static bool MMReadProduct(IOHIDServiceClientRef service, char *buffer, size_t capacity) {
    if (buffer == NULL || capacity == 0) {
        return false;
    }
    buffer[0] = '\0';
    CFTypeRef product = IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
    if (product == NULL || CFGetTypeID(product) != CFStringGetTypeID()) {
        if (product != NULL) {
            CFRelease(product);
        }
        return false;
    }
    bool copied = CFStringGetCString((CFStringRef)product,
                                     buffer,
                                     (CFIndex)capacity,
                                     kCFStringEncodingUTF8);
    CFRelease(product);
    return copied;
}

static bool MMIsValidatedTemperature(double value) {
    return isfinite(value) && value >= 0.0 && value <= 150.0;
}

int MMHIDTemperatureRuntimeRead(MMHIDTemperatureSample *sample) {
    if (sample == NULL) {
        return 2;
    }
    sample->hasCPU = false;
    sample->hasGPU = false;
    sample->cpuCelsius = 0.0;
    sample->gpuCelsius = 0.0;

    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (client == NULL) {
        return 1;
    }

    int32_t page = MMHIDTemperatureUsagePage;
    int32_t usage = MMHIDTemperatureUsage;
    const void *keys[] = {CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage")};
    const void *values[] = {
        CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &page),
        CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &usage)
    };
    CFDictionaryRef matching = CFDictionaryCreate(kCFAllocatorDefault,
                                                   keys,
                                                   values,
                                                   2,
                                                   &kCFTypeDictionaryKeyCallBacks,
                                                   &kCFTypeDictionaryValueCallBacks);
    if (values[0] != NULL) {
        CFRelease(values[0]);
    }
    if (values[1] != NULL) {
        CFRelease(values[1]);
    }
    if (matching == NULL) {
        if (matching != NULL) {
            CFRelease(matching);
        }
        CFRelease(client);
        return 1;
    }
    // The SDK's declaration is intentionally opaque on some macOS 26 SDKs;
    // the call itself is the contract and its return value is not stable.
    (void)IOHIDEventSystemClientSetMatching(client, matching);
    CFRelease(matching);

    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    if (services == NULL || CFGetTypeID(services) != CFArrayGetTypeID()) {
        if (services != NULL) {
            CFRelease(services);
        }
        CFRelease(client);
        return 1;
    }

    double cpuTotal = 0.0;
    double gpuTotal = 0.0;
    size_t cpuCount = 0;
    size_t gpuCount = 0;
    CFIndex serviceCount = CFArrayGetCount(services);
    if (serviceCount < 0 || serviceCount > 256) {
        CFRelease(services);
        CFRelease(client);
        return 1;
    }

    for (CFIndex index = 0; index < serviceCount; index++) {
        const void *rawService = CFArrayGetValueAtIndex(services, index);
        if (rawService == NULL) {
            continue;
        }
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)rawService;
        char product[128] = {0};
        if (!MMReadProduct(service, product, sizeof(product))) {
            continue;
        }
        bool isCPU = strncmp(product, "pACC MTR Temp Sensor", 20) == 0 ||
                     strncmp(product, "eACC MTR Temp Sensor", 20) == 0;
        bool isGPU = strncmp(product, "GPU MTR Temp Sensor", 19) == 0;
        if (!isCPU && !isGPU) {
            continue;
        }
        IOHIDEventRef event = IOHIDServiceClientCopyEvent(
            service, MMHIDTemperatureEventType, 0, 0);
        if (event == NULL) {
            continue;
        }
        double value = IOHIDEventGetFloatValue(event, MMHIDTemperatureField);
        if (MMIsValidatedTemperature(value)) {
            if (isCPU) {
                cpuTotal += value;
                cpuCount += 1;
            } else {
                gpuTotal += value;
                gpuCount += 1;
            }
        }
        CFRelease(event);
    }

    CFRelease(services);
    CFRelease(client);

    if (cpuCount > 0) {
        sample->hasCPU = true;
        sample->cpuCelsius = cpuTotal / (double)cpuCount;
    }
    if (gpuCount > 0) {
        sample->hasGPU = true;
        sample->gpuCelsius = gpuTotal / (double)gpuCount;
    }
    return sample->hasCPU || sample->hasGPU ? 0 : 1;
}
