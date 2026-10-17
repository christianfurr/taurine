// Exercise the real socket protocol with an in-memory power backend.
// No privilege request or system power-setting mutation occurs in these tests.
#define main taurine_helper_main
#include "../Sources/PowerSession.c"
#undef main
#include <assert.h>

static int setting, writes, fail_next, battery_after_enable;
static bool low;
static int fake_read(void) { return setting; }
static bool fake_write(int value) {
    setting = value;
    writes++;
    if (fail_next) { fail_next = 0; return false; }
    return true;
}
static bool fake_battery(void) { return low || (battery_after_enable && writes > 0); }

static char receive_byte(int fd) {
    struct pollfd pfd = {.fd = fd, .events = POLLIN};
    assert(poll(&pfd, 1, 6000) > 0);
    char value;
    assert(recv(fd, &value, 1, 0) == 1);
    return value;
}

static void scenario(const char *name, int original, char command, char expected,
                     int fail, bool initial_low, bool drops_low, bool abandon,
                     bool timeout) {
    int pair[2];
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
    pid_t child = fork();
    assert(child >= 0);
    if (child == 0) {
        close(pair[0]);
        setting = original; writes = 0; fail_next = fail;
        low = initial_low; battery_after_enable = drops_low;
        stopping = 0;
        int result = run_session(pair[1], fake_read, fake_write, fake_battery, timeout ? 1 : 15);
        assert(result == 0);
        assert(setting == original);
        assert(writes == ((command == 'E' && !initial_low) ? 2 : 0));
        close(pair[1]);
        _exit(0);
    }
    close(pair[1]);
    assert(receive_byte(pair[0]) == 'R');
    assert(send_byte(pair[0], command));
    if (command == 'E' && !fail && !initial_low) {
        assert(receive_byte(pair[0]) == '1');
        if (abandon) { close(pair[0]); pair[0] = -1; }
        else if (!timeout && !drops_low) assert(send_byte(pair[0], 'D'));
    }
    if (!abandon) assert(receive_byte(pair[0]) == expected);
    if (pair[0] >= 0) close(pair[0]);
    int status;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    printf("PASS %s\n", name);
}

int main(void) {
    signal(SIGPIPE, SIG_IGN);
    const char *samples[] = {
        "System-wide power settings:\nCurrently in use:\n sleep 1\n",
        "System-wide power settings:\n SleepDisabled\t\t0\n",
        "System-wide power settings:\n SleepDisabled\t\t1\n"
    };
    for (int i = 0; i < 3; i++) {
        FILE *stream = tmpfile();
        assert(stream);
        fputs(samples[i], stream); rewind(stream);
        assert(parse_sleep_setting(stream) == (i == 2));
        fclose(stream);
    }
    puts("PASS pmset output parsing");
    scenario("enable, readback, disable restores normal sleep", 0, 'E', '0', 0, false, false, false, false);
    scenario("prior disabled setting is preserved", 1, 'E', '0', 0, false, false, false, false);
    scenario("app crash/disconnect restores setting", 0, 'E', '0', 0, false, false, true, false);
    scenario("missed heartbeat restores setting", 0, 'E', '0', 0, false, false, false, true);
    scenario("partial enable failure restores setting", 0, 'E', 'F', 1, false, false, false, false);
    scenario("low battery refuses enable", 0, 'E', 'B', 0, true, false, false, false);
    scenario("battery dropping to threshold restores setting", 0, 'E', 'B', 0, false, true, false, false);
    scenario("cancel before enable makes no changes", 0, 'D', '0', 0, false, false, false, false);
    scenario("invalid protocol makes no changes", 0, '?', 'F', 0, false, false, false, false);
    return 0;
}
