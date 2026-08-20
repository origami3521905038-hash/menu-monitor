#ifndef MENU_MONITOR_CIOREPORT_RUNTIME_H
#define MENU_MONITOR_CIOREPORT_RUNTIME_H

#include <stddef.h>
#include <stdint.h>

typedef struct MMIOReportRuntime MMIOReportRuntime;

typedef struct {
    char name[64];
    char unit[16];
    int64_t cumulativeValue;
} MMIOReportChannel;

enum {
    MMIOReportResultOK = 0,
    MMIOReportResultUnavailable = 1,
    MMIOReportResultMalformed = 2,
    MMIOReportResultCapacityExceeded = 3
};

MMIOReportRuntime *MMIOReportRuntimeCreate(void);
void MMIOReportRuntimeDestroy(MMIOReportRuntime *runtime);
int MMIOReportRuntimeRead(MMIOReportRuntime *runtime,
                          MMIOReportChannel *channels,
                          size_t capacity,
                          size_t *count);
const char *MMIOReportRuntimeFailure(MMIOReportRuntime *runtime);

#endif
