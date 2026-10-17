#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/ps/IOPSKeys.h>
#include <IOKit/ps/IOPowerSources.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t stopping = 0;
static void stop_signal(int signal_number) { (void)signal_number; stopping = 1; }

static time_t monotonic_seconds(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec;
}

// An absent SleepDisabled key means the system default, false.
static int parse_sleep_setting(FILE *stream) {
    char line[1024];
    while (fgets(line, sizeof(line), stream)) {
        int value;
        if (sscanf(line, " SleepDisabled %d", &value) == 1)
            return value == 0 ? 0 : 1;
    }
    return ferror(stream) ? -1 : 0;
}

static int read_sleep_setting(void) {
    FILE *stream = popen("/usr/bin/pmset -g", "r");
    if (!stream) return -1;
    int result = parse_sleep_setting(stream);
    return pclose(stream) == 0 ? result : -1;
}

static bool set_sleep_setting(int disabled) {
    pid_t child = fork();
    if (child < 0) return false;
    if (child == 0) {
        execl("/usr/bin/pmset", "pmset", "-a", "disablesleep",
              disabled ? "1" : "0", (char *)NULL);
        _exit(127);
    }
    int status;
    while (waitpid(child, &status, 0) < 0) {
        if (errno != EINTR) return false;
    }
    return WIFEXITED(status) && WEXITSTATUS(status) == 0 &&
           read_sleep_setting() == disabled;
}

static bool battery_is_low(void) {
    bool low = false;
    CFTypeRef info = IOPSCopyPowerSourcesInfo();
    if (!info) return false;
    CFArrayRef sources = IOPSCopyPowerSourcesList(info);
    if (sources) {
        for (CFIndex i = 0; i < CFArrayGetCount(sources); i++) {
            CFDictionaryRef source = IOPSGetPowerSourceDescription(info, CFArrayGetValueAtIndex(sources, i));
            if (!source) continue;
            CFStringRef state = CFDictionaryGetValue(source, CFSTR(kIOPSPowerSourceStateKey));
            CFNumberRef current = CFDictionaryGetValue(source, CFSTR(kIOPSCurrentCapacityKey));
            CFNumberRef maximum = CFDictionaryGetValue(source, CFSTR(kIOPSMaxCapacityKey));
            int c = 0, m = 0;
            if (state && CFEqual(state, CFSTR(kIOPSBatteryPowerValue)) && current && maximum &&
                CFNumberGetValue(current, kCFNumberIntType, &c) &&
                CFNumberGetValue(maximum, kCFNumberIntType, &m) && m > 0 &&
                (double)c / m <= 0.10) low = true;
        }
        CFRelease(sources);
    }
    CFRelease(info);
    return low;
}

static bool send_byte(int socket_fd, char value) {
    return send(socket_fd, &value, 1, 0) == 1;
}

// The socket is the lease. EOF, an explicit stop, or a missed heartbeat ends it.
// Callers receive '1' only after pmset has been read back successfully.
static int run_session(int socket_fd, int (*read_setting)(void),
                       bool (*write_setting)(int), bool (*low_battery)(void),
                       time_t heartbeat_timeout) {
    int original = read_setting();
    if (original < 0 || !send_byte(socket_fd, 'R')) return 1;
    bool touched = false;
    char final_status = '0';
    time_t heartbeat = monotonic_seconds();
    while (!stopping) {
        struct pollfd pfd = {.fd = socket_fd, .events = POLLIN};
        int ready = poll(&pfd, 1, 1000);
        if (ready < 0) { if (errno == EINTR) continue; break; }
        if (monotonic_seconds() - heartbeat >= heartbeat_timeout) break;
        if (touched && low_battery()) { final_status = 'B'; break; }
        if (!ready) continue;
        char command;
        if (recv(socket_fd, &command, 1, 0) != 1) break;
        if (command == 'H') { heartbeat = monotonic_seconds(); continue; }
        if (command == 'D') break;
        if (command != 'E' || touched) { final_status = 'F'; break; }
        if (low_battery()) { final_status = 'B'; break; }
        // Mark before writing: a partial failure still requires restoration.
        touched = true;
        if (!write_setting(1)) { final_status = 'F'; break; }
        heartbeat = monotonic_seconds();
        if (!send_byte(socket_fd, '1')) break;
    }
    bool restored = true;
    if (touched) {
        restored = false;
        for (int attempt = 0; attempt < 3 && !restored; attempt++) {
            restored = write_setting(original);
            if (!restored) sleep(1);
        }
    }
    send_byte(socket_fd, restored ? final_status : 'X');
    return restored ? 0 : 2;
}

int main(int argc, char **argv) {
    if (argc != 3 || geteuid() != 0) {
        fprintf(stderr, "TaurinePower is launched by Taurine with administrator authorization.\n");
        return 1;
    }
    char *end;
    unsigned long raw_uid = strtoul(argv[2], &end, 10);
    if (!*argv[2] || *end || raw_uid == 0 || raw_uid > UINT32_MAX) return 1;
    uid_t owner = (uid_t)raw_uid;
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    if (strlen(argv[1]) >= sizeof(address.sun_path)) return 1;
    strlcpy(address.sun_path, argv[1], sizeof(address.sun_path));
    struct stat metadata;
    if (lstat(argv[1], &metadata) != 0 || !S_ISSOCK(metadata.st_mode) || metadata.st_uid != owner) return 1;

    // Do not install a daemon: this process lives only for one app session.
    pid_t child = fork();
    if (child < 0) return 1;
    if (child > 0) return 0;
    if (setsid() < 0) _exit(1);
    chdir("/");
    int null_fd = open("/dev/null", O_RDWR);
    if (null_fd < 0) _exit(1);
    for (int fd = 0; fd <= 2; fd++) dup2(null_fd, fd);
    if (null_fd > 2) close(null_fd);
    signal(SIGPIPE, SIG_IGN);
    signal(SIGTERM, stop_signal);
    signal(SIGINT, stop_signal);
    signal(SIGHUP, stop_signal);

    // Serialize apps/users so two sessions cannot restore over each other.
    // Keep the original lock name so a legacy Caffeine session also excludes us.
    int lock_fd = open("/var/run/com.christianfurr.Caffeine.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (lock_fd < 0) _exit(1);
    int socket_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (socket_fd < 0 || connect(socket_fd, (struct sockaddr *)&address, sizeof(address)) != 0) _exit(1);
    uid_t peer_uid; gid_t peer_gid;
    if (getpeereid(socket_fd, &peer_uid, &peer_gid) != 0 || peer_uid != owner) _exit(1);
    if (flock(lock_fd, LOCK_EX | LOCK_NB) != 0) { send_byte(socket_fd, 'L'); _exit(1); }
    int result = run_session(socket_fd, read_sleep_setting, set_sleep_setting, battery_is_low, 15);
    close(socket_fd);
    close(lock_fd);
    _exit(result);
}
