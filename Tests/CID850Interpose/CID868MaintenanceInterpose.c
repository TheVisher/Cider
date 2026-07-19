#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sqlite3.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

// CID-868 controls live only in this test dylib. Production selects no test
// behavior; subprocess tests insert this library into the real helper.
static const char *cid868_boundary;
static const char *cid868_action;
static const char *cid868_database;
static const char *cid868_marker;
static int cid868_occurrence = 1;
static int cid868_seen = 0;
static bool cid868_triggered = false;
static bool cid868_inside = false;
static sqlite3 *cid868_online_source;
static sqlite3 *cid868_online_destination;
static sqlite3 *cid868_terminal;
static sqlite3_backup *cid868_backup;
static bool cid868_backup_finished = false;
static int cid868_candidate_opens = 0;
static int cid868_retirement_directory = -1;

__attribute__((constructor))
static void cid868_configure(void) {
    cid868_boundary = getenv("CID868_INTERPOSE_BOUNDARY");
    cid868_action = getenv("CID868_INTERPOSE_ACTION");
    cid868_database = getenv("CID868_INTERPOSE_DATABASE");
    cid868_marker = getenv("CID868_INTERPOSE_MARKER");
    const char *raw_occurrence = getenv("CID868_INTERPOSE_OCCURRENCE");
    if (raw_occurrence != NULL && atoi(raw_occurrence) > 0) {
        cid868_occurrence = atoi(raw_occurrence);
    }
}

static bool cid868_named(const char *value) {
    return cid868_boundary != NULL && strcmp(cid868_boundary, value) == 0;
}

static void cid868_write_marker(void) {
    if (cid868_marker == NULL || cid868_marker[0] == '\0') {
        return;
    }
    cid868_inside = true;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    int descriptor = (int)syscall(
        SYS_openat,
        AT_FDCWD,
        cid868_marker,
        O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
        S_IRUSR | S_IWUSR
    );
#pragma clang diagnostic pop
    if (descriptor >= 0) {
        const char value = '1';
        (void)write(descriptor, &value, 1);
        (void)fsync(descriptor);
        close(descriptor);
    }
    cid868_inside = false;
}

static bool cid868_take(const char *boundary) {
    if (cid868_inside || cid868_triggered || cid868_action == NULL
            || !cid868_named(boundary)) {
        return false;
    }
    cid868_seen += 1;
    if (cid868_seen != cid868_occurrence) {
        return false;
    }
    cid868_triggered = true;
    cid868_write_marker();
    if (strcmp(cid868_action, "crash") == 0) {
        kill(getpid(), SIGKILL);
    } else if (strcmp(cid868_action, "pause") == 0) {
        raise(SIGSTOP);
    }
    return strcmp(cid868_action, "fail") == 0;
}

static bool cid868_has_suffix(const char *value, const char *suffix) {
    if (value == NULL) { return false; }
    size_t value_length = strlen(value);
    size_t suffix_length = strlen(suffix);
    return value_length >= suffix_length
        && strcmp(value + value_length - suffix_length, suffix) == 0;
}

static int cid868_openat(int directory, const char *name, int flags, mode_t mode) {
    if (!cid868_inside && name != NULL) {
        if (strcmp(name, "active-restore-v1.json") == 0
                && (flags & O_CREAT) != 0
                && cid868_take("beforeIntentPublication")) {
            errno = EIO;
            return -1;
        }
        if (strncmp(name, "restore-", 8) == 0
                && cid868_has_suffix(name, ".json")
                && (flags & O_CREAT) != 0
                && cid868_take("beforeReceiptPublication")) {
            errno = EIO;
            return -1;
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return (int)syscall(SYS_openat, directory, name, flags, mode);
#pragma clang diagnostic pop
}

static int cid868_unlinkat(int directory, const char *name, int flags) {
    if (!cid868_inside && name != NULL
            && strcmp(name, "active-restore-v1.json") == 0) {
        if (cid868_take("afterReceiptPublication")) {
            errno = EIO;
            return -1;
        }
        if (cid868_take("intentUnlink")) {
            errno = EIO;
            return -1;
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    int result = (int)syscall(SYS_unlinkat, directory, name, flags);
#pragma clang diagnostic pop
    if (result == 0 && name != NULL
            && strcmp(name, "active-restore-v1.json") == 0
            && cid868_named("intentParentFsync")) {
        cid868_retirement_directory = directory;
    }
    return result;
}

int cid868_test_fsync_result(int descriptor, bool *handled) {
    if (descriptor == cid868_retirement_directory
            && cid868_take("intentParentFsync")) {
        *handled = true;
        errno = EIO;
        return -1;
    }
    *handled = false;
    return 0;
}

static int cid868_sqlite3_open_v2(
    const char *filename,
    sqlite3 **database,
    int flags,
    const char *vfs
) {
    bool candidate = filename != NULL && strstr(filename, "/.candidate-") != NULL;
    if (candidate) {
        cid868_candidate_opens += 1;
        if (cid868_candidate_opens == 2 && cid868_take("sourceOpen")) {
            *database = NULL;
            return SQLITE_CANTOPEN;
        }
    }
    bool destination = filename != NULL && cid868_database != NULL
        && strcmp(filename, cid868_database) == 0;
    if (destination && cid868_online_source != NULL
            && cid868_online_destination == NULL
            && cid868_take("destinationOpen")) {
        *database = NULL;
        return SQLITE_CANTOPEN;
    }
    if (destination && cid868_backup_finished) {
        if (cid868_take("beforeTerminalVerification")) {
            *database = NULL;
            return SQLITE_CANTOPEN;
        }
        if (cid868_take("reopen")) {
            *database = NULL;
            return SQLITE_CANTOPEN;
        }
    }
    int result = sqlite3_open_v2(filename, database, flags, vfs);
    if (result == SQLITE_OK && candidate && cid868_candidate_opens == 2) {
        cid868_online_source = *database;
    } else if (result == SQLITE_OK && destination && cid868_online_source != NULL
            && cid868_online_destination == NULL) {
        cid868_online_destination = *database;
    } else if (result == SQLITE_OK && destination && cid868_backup_finished) {
        cid868_terminal = *database;
    }
    return result;
}

static sqlite3_backup *cid868_sqlite3_backup_init(
    sqlite3 *destination,
    const char *destination_name,
    sqlite3 *source,
    const char *source_name
) {
    if (destination == cid868_online_destination && source == cid868_online_source
            && cid868_take("backupInit")) {
        return NULL;
    }
    sqlite3_backup *result = sqlite3_backup_init(
        destination,
        destination_name,
        source,
        source_name
    );
    if (destination == cid868_online_destination && source == cid868_online_source) {
        cid868_backup = result;
    }
    return result;
}

static int cid868_sqlite3_backup_step(sqlite3_backup *backup, int pages) {
    if (backup == cid868_backup) {
        if (cid868_take("beforeFirstBackupStep") || cid868_take("backupStep")) {
            return SQLITE_IOERR;
        }
    }
    int result = sqlite3_backup_step(backup, pages);
    if (backup == cid868_backup) {
        if (result == SQLITE_OK) {
            (void)cid868_take("duringBackupSteps");
        } else if (result == SQLITE_DONE) {
            (void)cid868_take("atSQLiteDone");
        }
    }
    return result;
}

static int cid868_sqlite3_backup_finish(sqlite3_backup *backup) {
    int result = sqlite3_backup_finish(backup);
    if (backup == cid868_backup) {
        cid868_backup_finished = true;
        if (cid868_take("backupFinish")) {
            return SQLITE_IOERR;
        }
    }
    return result;
}

static int cid868_sqlite3_close_v2(sqlite3 *database) {
    int result = sqlite3_close_v2(database);
    if (database == cid868_online_destination && cid868_backup_finished) {
        (void)cid868_take("afterDestinationClose");
    }
    return result;
}

static int cid868_sqlite3_prepare_v2(
    sqlite3 *database,
    const char *sql,
    int bytes,
    sqlite3_stmt **statement,
    const char **tail
) {
    if (database == cid868_terminal && sql != NULL
            && strstr(sql, "PRAGMA integrity_check") != NULL
            && cid868_take("integrity")) {
        *statement = NULL;
        return SQLITE_IOERR;
    }
    return sqlite3_prepare_v2(database, sql, bytes, statement, tail);
}

struct cid868_interpose_pair {
    const void *replacement;
    const void *replacee;
};

__attribute__((used))
static struct cid868_interpose_pair cid868_interposers[]
    __attribute__((section("__DATA,__interpose"))) = {
        { (const void *)cid868_openat, (const void *)openat },
        { (const void *)cid868_unlinkat, (const void *)unlinkat },
        { (const void *)cid868_sqlite3_open_v2, (const void *)sqlite3_open_v2 },
        { (const void *)cid868_sqlite3_backup_init, (const void *)sqlite3_backup_init },
        { (const void *)cid868_sqlite3_backup_step, (const void *)sqlite3_backup_step },
        { (const void *)cid868_sqlite3_backup_finish, (const void *)sqlite3_backup_finish },
        { (const void *)cid868_sqlite3_close_v2, (const void *)sqlite3_close_v2 },
        { (const void *)cid868_sqlite3_prepare_v2, (const void *)sqlite3_prepare_v2 },
    };
