#include <CoreFoundation/CoreFoundation.h>

typedef struct IOReportSubscriptionRef* IOReportSubscriptionRef;

CFDictionaryRef IOReportCopyChannelsInGroup(CFStringRef a, CFStringRef b, uint64_t c, uint64_t d, uint64_t e);
void IOReportMergeChannels(CFDictionaryRef a, CFDictionaryRef b, CFTypeRef nullValue);
IOReportSubscriptionRef IOReportCreateSubscription(void* a, CFMutableDictionaryRef b, CFMutableDictionaryRef* c, uint64_t d, CFTypeRef e);
CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef a, CFMutableDictionaryRef b, CFTypeRef c);
CFStringRef IOReportChannelGetGroup(CFDictionaryRef a);
CFStringRef IOReportChannelGetChannelName(CFDictionaryRef a);
CFStringRef IOReportChannelGetUnitLabel(CFDictionaryRef a);
int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef a, int32_t b);
