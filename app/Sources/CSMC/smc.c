#include "smc.h"
#include <IOKit/IOKitLib.h>
#include <string.h>

enum { kSMCHandleYPCEvent = 2, kSMCReadKey = 5, kSMCWriteKey = 6, kSMCGetKeyFromIndex = 8, kSMCGetKeyInfo = 9 };

typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } SMCVers;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, mem; } SMCPLimit;
typedef struct { uint32_t dataSize; uint32_t dataType; uint8_t dataAttributes; } SMCKeyInfo;
typedef struct {
    uint32_t key;
    SMCVers vers;
    SMCPLimit pLimit;
    SMCKeyInfo keyInfo;
    uint8_t result, status, data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParam;

static io_connect_t conn = 0;

static uint32_t fourcc(const char *s) { return ((uint32_t)s[0] << 24) | ((uint32_t)s[1] << 16) | ((uint32_t)s[2] << 8) | (uint32_t)s[3]; }
static void unfourcc(uint32_t v, char out[5]) { out[0] = v >> 24; out[1] = v >> 16; out[2] = v >> 8; out[3] = v; out[4] = 0; }

static int call(SMCParam *in, SMCParam *out) {
    size_t outSize = sizeof(SMCParam);
    kern_return_t r = IOConnectCallStructMethod(conn, kSMCHandleYPCEvent, in, sizeof(SMCParam), out, &outSize);
    if (r != KERN_SUCCESS) return (int)r;
    return out->result == 0 ? 0 : -(int)out->result;
}

int smc_open(void) {
    if (conn) return 0;
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return -1;
    kern_return_t r = IOServiceOpen(svc, mach_task_self(), 0, &conn);
    IOObjectRelease(svc);
    return r == KERN_SUCCESS ? 0 : (int)r;
}

void smc_close(void) { if (conn) { IOServiceClose(conn); conn = 0; } }

static int key_info(const char *key, SMCKeyInfo *info) {
    SMCParam in = {0}, out = {0};
    in.key = fourcc(key);
    in.data8 = kSMCGetKeyInfo;
    int r = call(&in, &out);
    if (r == 0) *info = out.keyInfo;
    return r;
}

int smc_read(const char *key, SMCVal *val) {
    if (smc_open() != 0) return -1;
    SMCKeyInfo info;
    int r = key_info(key, &info);
    if (r) return r;
    SMCParam in = {0}, out = {0};
    in.key = fourcc(key);
    in.keyInfo.dataSize = info.dataSize;
    in.data8 = kSMCReadKey;
    r = call(&in, &out);
    if (r) return r;
    memset(val, 0, sizeof(*val));
    val->size = info.dataSize > 32 ? 32 : info.dataSize;
    unfourcc(info.dataType, val->type);
    memcpy(val->bytes, out.bytes, val->size);
    return 0;
}

int smc_write(const char *key, const uint8_t *bytes, uint32_t size) {
    if (smc_open() != 0) return -1;
    SMCKeyInfo info;
    int r = key_info(key, &info);
    if (r) return r;
    if (info.dataSize != size) return -100;
    SMCParam in = {0}, out = {0};
    in.key = fourcc(key);
    in.keyInfo.dataSize = size;
    in.data8 = kSMCWriteKey;
    memcpy(in.bytes, bytes, size);
    return call(&in, &out);
}

uint32_t smc_key_count(void) {
    SMCVal v;
    if (smc_read("#KEY", &v)) return 0;
    return ((uint32_t)v.bytes[0] << 24) | ((uint32_t)v.bytes[1] << 16) | ((uint32_t)v.bytes[2] << 8) | v.bytes[3];
}

int smc_key_at(uint32_t index, char out[5]) {
    if (smc_open() != 0) return -1;
    SMCParam in = {0}, o = {0};
    in.data8 = kSMCGetKeyFromIndex;
    in.data32 = index;
    int r = call(&in, &o);
    if (r == 0) unfourcc(o.key, out);
    return r;
}
