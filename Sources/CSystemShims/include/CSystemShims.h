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

// Used by tests to build the events that sensor-less machines (CI VMs) never return.
IOHIDEventRef IOHIDEventCreate(CFAllocatorRef _Nullable allocator, uint32_t type, uint64_t timestamp, uint32_t options) CF_RETURNS_RETAINED;
void IOHIDEventSetFloatValue(IOHIDEventRef event, int32_t field, double value);

CF_ASSUME_NONNULL_END

// The AppleSMC user client's parameter block, passed in and out of IOConnectCallStructMethod
// (selector 2). The kernel extension fixes this 80-byte layout; open-source SMC readers use the
// same one. Reads only need `key`, `keyInfo.dataSize`, `data8` (the command) and `data32` (an index),
// and answer in `result`, `key`, `keyInfo` and `bytes`. Works without root.

typedef struct {
    uint8_t major;
    uint8_t minor;
    uint8_t build;
    uint8_t reserved;
    uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCPLimitData;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
} SMCKeyInfo;

typedef struct {
    uint32_t key;
    SMCVersion vers;
    SMCPLimitData pLimitData;
    SMCKeyInfo keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParamStruct;

_Static_assert(sizeof(SMCParamStruct) == 80, "AppleSMC expects an 80-byte parameter block");
_Static_assert(__builtin_offsetof(SMCParamStruct, keyInfo) == 28, "keyInfo at byte 28");
_Static_assert(__builtin_offsetof(SMCParamStruct, data8) == 42, "data8 at byte 42");
_Static_assert(__builtin_offsetof(SMCParamStruct, bytes) == 48, "bytes at byte 48");

#endif
