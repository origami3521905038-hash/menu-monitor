#ifndef MENU_MONITOR_CIOHID_TEMPERATURE_RUNTIME_H
#define MENU_MONITOR_CIOHID_TEMPERATURE_RUNTIME_H

#include <stdbool.h>

typedef struct {
    bool hasCPU;
    bool hasGPU;
    double cpuCelsius;
    double gpuCelsius;
} MMHIDTemperatureSample;

/// Reads the read-only Apple Silicon temperature HID services.
/// Returns 0 when at least one validated sensor is available.
int MMHIDTemperatureRuntimeRead(MMHIDTemperatureSample *sample);

#endif
