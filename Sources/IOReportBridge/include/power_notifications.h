#pragma once

#include <IOKit/IOMessage.h>
#include <stdint.h>

// Swift cannot import these expression macros directly from IOMessage.h.
static const uint32_t IFanCanSystemSleep = kIOMessageCanSystemSleep;
static const uint32_t IFanSystemWillSleep = kIOMessageSystemWillSleep;
static const uint32_t IFanSystemHasPoweredOn = kIOMessageSystemHasPoweredOn;
