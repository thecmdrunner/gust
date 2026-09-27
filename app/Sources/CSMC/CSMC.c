#include "CSMC.h"
#include <IOKit/IOKitLib.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <sys/un.h>
#include <sys/types.h>
#include <sys/time.h>
#include <mach/mach_time.h>
#include <unistd.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>

// AppleSMC's 80-byte user-client ABI. See docs/engineering.md.
typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } Version;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, memory; } Limits;
typedef struct { uint32_t size, type; uint8_t attributes; } KeyInfo;
typedef struct {
    uint32_t key; Version version; Limits limits; KeyInfo info;
    uint8_t result, status, command; uint32_t index; uint8_t bytes[32];
} Packet;
_Static_assert(sizeof(Packet) == 80, "AppleSMC ABI mismatch");
static uint32_t fourcc(const char *s) {
    return ((uint32_t)s[0]<<24)|((uint32_t)s[1]<<16)|((uint32_t)s[2]<<8)|(uint32_t)s[3];
}
static int call(uint32_t connection, Packet *in, Packet *out) {
    size_t size = sizeof(*out);
    kern_return_t result = IOConnectCallStructMethod(connection, 2, in, sizeof(*in), out, &size);
    if (result != KERN_SUCCESS) return (int)result;
    if (size != sizeof(*out)) return -1;
    return out->result;
}
int gust_smc_open(uint32_t *connection) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return -1;
    int result = IOServiceOpen(service, mach_task_self(), 0, connection);
    IOObjectRelease(service);
    return result;
}
void gust_smc_close(uint32_t connection) { IOServiceClose(connection); }
static int info(uint32_t connection, const char *key, Packet *out) {
    if (strlen(key) != 4) return -1;
    Packet in = {0}; in.key = fourcc(key); in.command = 9;
    int result = call(connection, &in, out);
    if (result) return result;
    return out->info.size > 0 && out->info.size <= 32 ? 0 : -1;
}
int gust_smc_read(uint32_t connection, const char *key, GustValue *value) {
    Packet meta = {0}; int result = info(connection, key, &meta); if (result) return result;
    Packet in = {0}, out = {0}; in.key = fourcc(key); in.command = 5; in.info.size = meta.info.size;
    result = call(connection, &in, &out); if (result) return result;
    value->type = meta.info.type; value->size = meta.info.size;
    memcpy(value->bytes, out.bytes, meta.info.size); return 0;
}
int gust_smc_write(uint32_t connection, const char *key, const GustValue *value) {
    Packet meta = {0}; int result = info(connection, key, &meta); if (result) return result;
    if (meta.info.size != value->size || meta.info.type != value->type) return -1;
    Packet in = {0}, out = {0}; in.key = fourcc(key); in.command = 6; in.info.size = value->size;
    memcpy(in.bytes, value->bytes, value->size); return call(connection, &in, &out);
}

static int lock_fd = -1;
static volatile sig_atomic_t stopped = 0;
static void on_signal(int s) { stopped = 1; }
void gust_signals_install(void) {
    signal(SIGTERM, on_signal); signal(SIGINT, on_signal); signal(SIGHUP, on_signal); signal(SIGPIPE, SIG_IGN);
}
int gust_stopping(void) { return stopped; }
double gust_uptime(void) {
    mach_timebase_info_data_t time; mach_timebase_info(&time);
    return (double)mach_continuous_time() * time.numer / time.denom / 1e9;
}
static struct sockaddr_un address(uint32_t uid, int pid) {
    struct sockaddr_un addr = {0}; addr.sun_family = AF_UNIX;
    snprintf(addr.sun_path, sizeof(addr.sun_path), "/var/run/gust-fan/%u-%d.sock", uid, pid);
    addr.sun_len = sizeof(addr); return addr;
}
static void timeout(int fd) {
    struct timeval t = {.tv_sec=1, .tv_usec=0};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &t, sizeof(t));
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &t, sizeof(t));
    int yes = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
}
int gust_server_open(uint32_t uid, int pid) {
    if (geteuid() != 0 || uid == 0 || pid <= 1) return -1;
    if (mkdir("/var/run/gust-fan", 0755) && errno != EEXIST) return -1;
    struct stat st;
    if (lstat("/var/run/gust-fan", &st) || !S_ISDIR(st.st_mode) || st.st_uid != 0 || (st.st_mode & 022)) return -1;
    lock_fd = open("/var/run/gust-fan/control.lock", O_CREAT|O_RDWR|O_NOFOLLOW, 0600);
    if (lock_fd < 0 || flock(lock_fd, LOCK_EX|LOCK_NB)) return -1;
    int fd = socket(AF_UNIX, SOCK_STREAM, 0); if (fd < 0) return -1;
    struct sockaddr_un addr = address(uid, pid); unlink(addr.sun_path);
    mode_t old = umask(077);
    int result = bind(fd, (struct sockaddr*)&addr, sizeof(addr)); umask(old);
    if (result || chown(addr.sun_path, uid, (gid_t)-1) || chmod(addr.sun_path, 0600) || listen(fd, 4)) {
        close(fd); unlink(addr.sun_path); return -1;
    }
    return fd;
}
int gust_server_next(int server, uint32_t uid, int pid, char *buffer, size_t size) {
    struct pollfd p = {.fd=server,.events=POLLIN};
    if (poll(&p, 1, 200) <= 0) return -1;
    int fd = accept(server, NULL, NULL); if (fd < 0) return -1;
    timeout(fd);
    uid_t peer; gid_t group; pid_t peer_pid = 0; socklen_t len = sizeof(peer_pid);
    if (getpeereid(fd, &peer, &group) || peer != uid ||
        getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &peer_pid, &len) || peer_pid != pid) { close(fd); return -1; }
    size_t used = 0;
    while (used + 1 < size) {
        char c; if (read(fd, &c, 1) != 1) { close(fd); return -1; }
        if (c == '\n') { buffer[used] = 0; return fd; }
        buffer[used++] = c;
    }
    close(fd); return -1;
}
void gust_server_reply(int client, const char *reply) {
    send(client, reply, strlen(reply), 0); shutdown(client, SHUT_WR); close(client);
}
void gust_server_close(int server, uint32_t uid, int pid) {
    struct sockaddr_un addr = address(uid, pid); close(server); unlink(addr.sun_path);
    if (lock_fd >= 0) close(lock_fd);
}
int gust_request(uint32_t uid, int pid, const char *command, char *reply, size_t size) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0); if (fd < 0) return -1; timeout(fd);
    // Unlocking Apple Silicon arbitration may take a few seconds.
    struct timeval t = {.tv_sec=strncmp(command, "set ", 4) == 0 ? GUST_SET_REPLY_TIMEOUT_SECONDS : 8};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &t, sizeof(t));
    struct sockaddr_un addr = address(uid, pid);
    if (connect(fd, (struct sockaddr*)&addr, sizeof(addr))) { close(fd); return -1; }
    uid_t peer; gid_t group;
    if (getpeereid(fd, &peer, &group) || peer != 0) { close(fd); return -1; }
    size_t length = strlen(command);
    if (send(fd, command, length, 0) != length || send(fd, "\n", 1, 0) != 1) { close(fd); return -1; }
    size_t used = 0; ssize_t n;
    while (used + 1 < size && (n = read(fd, reply + used, size - used - 1)) > 0) used += n;
    reply[used] = 0; close(fd); return used ? 0 : -1;
}
