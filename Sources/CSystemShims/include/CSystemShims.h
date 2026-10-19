#ifndef CSYSTEMSHIMS_H
#define CSYSTEMSHIMS_H

#include <IOKit/hidsystem/IOHIDEventSystemClient.h>

// Private IOHID event system API, exported by IOKit.framework. The public
// IOHIDEventSystemClientCreateSimpleClient() lists the temperature services but
// cannot copy their events, so the full client is required. Works without root.

CF_ASSUME_NONNULL_BEGIN

typedef struct CF_BRIDGED_TYPE(id) __IOHIDEvent *IOHIDEventRef;

IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef _Nullable allocator) CF_RETURNS_RETAINED;

IOHIDEventRef _Nullable IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service,
                                                    int64_t type,
                                                    int32_t options,
                                                    int64_t timestamp) CF_RETURNS_RETAINED;

double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

CF_ASSUME_NONNULL_END

#endif
