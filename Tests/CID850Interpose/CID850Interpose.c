#include "CID850Interpose.h"

#include <errno.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/clonefile.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/xattr.h>
#include <unistd.h>

typedef struct sqlite3 sqlite3;
extern const char *sqlite3_db_filename(sqlite3 *, const char *);
extern int sqlite3_open_v2(const char *, sqlite3 **, int, const char *);
extern int sqlite3_exec(sqlite3 *, const char *, void *, void *, char **);
extern int sqlite3_close_v2(sqlite3 *);
extern void sqlite3_free(void *);

enum cid850_mutation_kind {
    CID850_MUTATION_NONE = 0,
    CID850_MUTATION_MKDIRAT,
    CID850_MUTATION_FCLONEFILEAT,
    CID850_MUTATION_FCLONEFILEAT_CRASH,
    CID850_MUTATION_FCHFLAGS_RESTORE,
    CID850_MUTATION_RENAMEATX,
    CID850_MUTATION_RENAMEATX_SOURCE,
    CID850_MUTATION_RENAMEATX_CRASH,
    CID850_MUTATION_LSEEK,
    CID850_MUTATION_FTRUNCATE,
    CID850_MUTATION_SIDECAR_BEFORE_SWAP,
    CID850_MUTATION_SIDECAR_AFTER_SWAP,
    CID850_MUTATION_POST_SWAP_FSYNC,
    CID850_MUTATION_RESTORE_CRASH_AFTER_SWAP,
    CID851_MUTATION_RESTORE_CRASH_BEFORE_COMPLETION,
    CID851_MUTATION_MOVE_PATH_BEFORE_RESTORE_CLEANUP,
    CID851_MUTATION_REPLACE_PARENT_BEFORE_RESTORE_CLEANUP,
    CID850_MUTATION_RESTORE_REOPEN_AFTER_SWAP,
    CID850_MUTATION_RESTORE_INTEGRITY_AFTER_SWAP,
    CID850_MUTATION_RESTORE_RECORD_REMOVAL_FSYNC,
    CID850_MUTATION_STAGE_OWNERSHIP_PAUSE,
    CID850_MUTATION_CLONE_SOURCE_GROW,
    CID850_MUTATION_CLONE_SOURCE_REPLACE,
    CID850_MUTATION_CLONE_DESTINATION_GROW,
    CID850_MUTATION_CLONE_DESTINATION_REPLACE,
    CID851_MUTATION_MEMBER_BEFORE_RENAME,
    CID851_MUTATION_MEMBER_BEFORE_UNLINK,
    CID851_MUTATION_MEMBER_BEFORE_CLONE,
    CID851_MUTATION_CLEANUP_DESTINATION_EXISTS,
    CID851_MUTATION_CLEANUP_SOURCE_REOCCUPIED,
    CID851_MUTATION_HELD_AFTER_RETENTION,
};

static pthread_mutex_t cid850_lock = PTHREAD_MUTEX_INITIALIZER;
static enum cid850_mutation_kind cid850_kind = CID850_MUTATION_NONE;
static char cid850_suffix[128];
static char cid850_held_name[256];
static bool cid850_did_mutation_value = false;
static int cid850_lseek_ordinal = 0;
static int cid850_lseek_seen = 0;
static _Thread_local bool cid850_inside_interposer = false;
static int cid850_flock_probe_role = 0;
static int cid850_flock_exclusive_seen = 0;
static bool cid850_flock_probe_reported = false;
static char cid850_ready_path[PATH_MAX];
static char cid850_release_path[PATH_MAX];
static char cid850_result_path[PATH_MAX];
static int cid850_fsync_failures_remaining = 0;
static bool cid850_post_swap_fsync_armed = false;
static bool cid850_post_swap_seen = false;
static bool cid850_restore_record_removed = false;
static bool cid851_count_restore_authority = false;
static int cid851_restore_authority_acquisitions = 0;
static int cid851_restore_authority_releases = 0;
static char cid850_ownership_ready_path[PATH_MAX];
static char cid850_ownership_release_path[PATH_MAX];
static char cid851_cleanup_source_path[PATH_MAX];
static char cid851_cleanup_held_path[PATH_MAX];
static bool cid851_count_metadata = false;
static int cid851_legacy_metadata_writes = 0;
static int cid851_canonical_metadata_writes = 0;
static char cid851_parent_path[PATH_MAX];
static bool cid851_parent_lock_seen = false;
static int cid851_parent_reopens = 0;
static char cid851_sqlite_database_path[PATH_MAX];
static char cid851_sqlite_expected_database_path[PATH_MAX];
static char cid851_sqlite_sidecar_suffix[32];
static bool cid851_sqlite_sidecar_armed = false;
static int cid851_sqlite_callback_count = 0;
static int cid851_crash_boundary = 0;
static int cid851_crash_ordinal = 0;
static int cid851_crash_seen = 0;
static char cid851_crash_sqlite_path[PATH_MAX];
static sqlite3 *cid851_open_boundary_writer = NULL;
static char cid851_receipt_selector_action[32];
static int cid851_receipt_selector_manifest_seen = 0;
static bool cid851_count_retained_unlinks = false;
static int cid851_retained_unlink_attempts = 0;
static int cid851_retained_held_descriptor = -1;
static bool cid851_reoccupy_before_record_removal = false;
static char cid851_qualified_receipt_package_path[PATH_MAX];
static char cid851_qualified_receipt_member[NAME_MAX];
static char cid851_qualified_receipt_action[32];

static void cid850_configure(
    enum cid850_mutation_kind kind,
    const char *suffix,
    const char *held_name
);
static void cid851_crash_if_boundary(int boundary);

__attribute__((constructor))
static void cid851_configure_receipt_selector_process_race(void) {
    const char *action = getenv("CIDER_TEST_RECEIPT_SELECTOR_ACTION");
    if (action != NULL) {
        strlcpy(
            cid851_receipt_selector_action,
            action,
            sizeof(cid851_receipt_selector_action)
        );
    }
}

static void cid851_mutate_receipt_selector_before_final_manifest_open(
    int directory,
    const char *name
) {
    if (cid851_receipt_selector_action[0] == '\0'
            || name == NULL
            || strcmp(name, "manifest.json") != 0
            || cid850_inside_interposer) {
        return;
    }
    char package_path[PATH_MAX] = {0};
    if (fcntl(directory, F_GETPATH, package_path) != 0
            || strstr(package_path, "-pre-restore-") == NULL
            || strstr(package_path, ".ciderbackup") == NULL) {
        return;
    }
    char action[sizeof(cid851_receipt_selector_action)] = {0};
    pthread_mutex_lock(&cid850_lock);
    cid851_receipt_selector_manifest_seen += 1;
    if (cid851_receipt_selector_manifest_seen == 2) {
        strlcpy(action, cid851_receipt_selector_action, sizeof(action));
        cid851_receipt_selector_action[0] = '\0';
    }
    pthread_mutex_unlock(&cid850_lock);
    if (action[0] == '\0') return;

    cid850_inside_interposer = true;
    if (strcmp(action, "moved") == 0) {
        char held_path[PATH_MAX] = {0};
        snprintf(held_path, sizeof(held_path), "%s.receipt-race-held", package_path);
        (void)rename(package_path, held_path);
    } else if (strcmp(action, "replaced") == 0) {
        char held_path[PATH_MAX] = {0};
        snprintf(held_path, sizeof(held_path), "%s.receipt-race-held", package_path);
        if (rename(package_path, held_path) == 0) {
            (void)mkdir(package_path, 0700);
        }
    } else if (strcmp(action, "ineligible") == 0) {
        (void)fremovexattr(
            directory,
            "com.cider.cid850.package-owner-v1",
            0
        );
    }
    cid850_did_mutation_value = true;
    cid850_inside_interposer = false;
}

static bool cid851_take_restore_member_mutation(
    enum cid850_mutation_kind kind,
    const char *name
) {
    bool result = false;
    pthread_mutex_lock(&cid850_lock);
    if (!cid850_did_mutation_value && cid850_kind == kind
            && ((kind == CID851_MUTATION_MEMBER_BEFORE_CLONE)
                || (name != NULL && strstr(name, ".cid851-restore-") != NULL))) {
        cid850_did_mutation_value = true;
        result = true;
    }
    pthread_mutex_unlock(&cid850_lock);
    return result;
}

static void cid851_mutate_same_size_descriptor(int descriptor) {
    int writable = descriptor;
    char path[PATH_MAX] = {0};
    if (fcntl(descriptor, F_GETFL) >= 0
            && (fcntl(descriptor, F_GETFL) & O_ACCMODE) == O_RDONLY
            && fcntl(descriptor, F_GETPATH, path) == 0) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        writable = (int)syscall(SYS_open, path, O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0);
#pragma clang diagnostic pop
        if (writable < 0) return;
    }
    struct stat value = {0};
    if (fstat(writable, &value) != 0 || !S_ISREG(value.st_mode) || value.st_size < 2) {
        if (writable != descriptor) close(writable);
        return;
    }
    off_t offset = value.st_size > 100 ? 100 : value.st_size - 1;
    unsigned char byte = 0;
    if (pread(writable, &byte, 1, offset) != 1) {
        if (writable != descriptor) close(writable);
        return;
    }
    byte ^= 0x5a;
    if (pwrite(writable, &byte, 1, offset) == 1) (void)fsync(writable);
    if (writable != descriptor) close(writable);
}

static void cid851_mutate_same_size_member(int directory, const char *name) {
    int descriptor = openat(directory, name, O_RDWR | O_NOFOLLOW | O_CLOEXEC);
    if (descriptor < 0) return;
    cid851_mutate_same_size_descriptor(descriptor);
    close(descriptor);
}

static void cid851_create_cleanup_replacement(int directory, const char *name) {
    int descriptor = openat(
        directory,
        name,
        O_RDWR | O_CREAT | O_EXCL | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC,
        S_IRUSR | S_IWUSR
    );
    if (descriptor < 0) return;
    const char marker[] = "cid851-cleanup-source-replacement";
    (void)write(descriptor, marker, sizeof(marker) - 1);
    (void)fsync(descriptor);
    close(descriptor);
}

void cid851_interpose_mutate_restore_member_before_rename(void) {
    cid850_configure(CID851_MUTATION_MEMBER_BEFORE_RENAME, "", "");
}

void cid851_interpose_mutate_restore_member_before_unlink(void) {
    cid850_configure(CID851_MUTATION_MEMBER_BEFORE_UNLINK, "", "");
}

void cid851_interpose_mutate_restore_member_before_clone(void) {
    cid850_configure(CID851_MUTATION_MEMBER_BEFORE_CLONE, "", "");
}

void cid851_interpose_occupy_cleanup_retention_destination(void) {
    cid850_configure(CID851_MUTATION_CLEANUP_DESTINATION_EXISTS, "", "");
}

void cid851_interpose_count_retained_restore_unlinks(void) {
    pthread_mutex_lock(&cid850_lock);
    cid851_count_retained_unlinks = true;
    cid851_retained_unlink_attempts = 0;
    pthread_mutex_unlock(&cid850_lock);
}

int cid851_interpose_retained_restore_unlink_attempts(void) {
    pthread_mutex_lock(&cid850_lock);
    int result = cid851_retained_unlink_attempts;
    pthread_mutex_unlock(&cid850_lock);
    return result;
}

void cid851_interpose_reoccupy_cleanup_source_after_retention(void) {
    cid850_configure(CID851_MUTATION_CLEANUP_SOURCE_REOCCUPIED, "", "");
}

void cid851_interpose_mutate_held_descriptor_after_retention(int descriptor) {
    cid850_configure(CID851_MUTATION_HELD_AFTER_RETENTION, "", "");
    pthread_mutex_lock(&cid850_lock);
    cid851_retained_held_descriptor = dup(descriptor);
    pthread_mutex_unlock(&cid850_lock);
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static int cid850_real_mkdirat(int directory, const char *name, mode_t mode) {
    return (int)syscall(SYS_mkdirat, directory, name, mode);
}

static int cid850_real_fclonefileat(
    int source,
    int destination_directory,
    const char *destination_name,
    uint32_t flags
) {
    return (int)syscall(
        SYS_fclonefileat,
        source,
        destination_directory,
        destination_name,
        flags
    );
}

static int cid850_real_flock(int descriptor, int operation) {
    return (int)syscall(SYS_flock, descriptor, operation);
}

static int cid850_real_fsetxattr(
    int descriptor,
    const char *name,
    const void *value,
    size_t size,
    u_int32_t position,
    int options
) {
    return (int)syscall(
        SYS_fsetxattr,
        descriptor,
        name,
        value,
        size,
        position,
        options
    );
}

#pragma clang diagnostic pop

static bool cid850_matches(const char *name, enum cid850_mutation_kind kind, char *held_name) {
    bool matches = false;
    pthread_mutex_lock(&cid850_lock);
    if (!cid850_did_mutation_value && cid850_kind == kind && name != NULL) {
        size_t name_length = strlen(name);
        size_t suffix_length = strlen(cid850_suffix);
        if (name_length >= suffix_length
                && strcmp(name + name_length - suffix_length, cid850_suffix) == 0) {
            cid850_did_mutation_value = true;
            strlcpy(held_name, cid850_held_name, 256);
            matches = true;
        }
    }
    pthread_mutex_unlock(&cid850_lock);
    return matches;
}

void cid850_interpose_reset(void) {
    pthread_mutex_lock(&cid850_lock);
    cid850_kind = CID850_MUTATION_NONE;
    cid850_suffix[0] = '\0';
    cid850_held_name[0] = '\0';
    cid850_did_mutation_value = false;
    cid850_lseek_ordinal = 0;
    cid850_lseek_seen = 0;
    cid850_flock_probe_role = 0;
    cid850_flock_exclusive_seen = 0;
    cid850_flock_probe_reported = false;
    cid850_ready_path[0] = '\0';
    cid850_release_path[0] = '\0';
    cid850_result_path[0] = '\0';
    cid850_fsync_failures_remaining = 0;
    cid850_post_swap_fsync_armed = false;
    cid850_post_swap_seen = false;
    cid850_restore_record_removed = false;
    cid851_count_restore_authority = false;
    cid851_restore_authority_acquisitions = 0;
    cid851_restore_authority_releases = 0;
    cid850_ownership_ready_path[0] = '\0';
    cid850_ownership_release_path[0] = '\0';
    cid851_cleanup_source_path[0] = '\0';
    cid851_cleanup_held_path[0] = '\0';
    cid851_count_metadata = false;
    cid851_legacy_metadata_writes = 0;
    cid851_canonical_metadata_writes = 0;
    cid851_parent_path[0] = '\0';
    cid851_parent_lock_seen = false;
    cid851_parent_reopens = 0;
    cid851_sqlite_database_path[0] = '\0';
    cid851_sqlite_expected_database_path[0] = '\0';
    cid851_sqlite_sidecar_suffix[0] = '\0';
    cid851_sqlite_sidecar_armed = false;
    cid851_sqlite_callback_count = 0;
    cid851_crash_boundary = 0;
    cid851_crash_ordinal = 0;
    cid851_crash_seen = 0;
    cid851_crash_sqlite_path[0] = '\0';
    cid851_count_retained_unlinks = false;
    cid851_retained_unlink_attempts = 0;
    cid851_reoccupy_before_record_removal = false;
    cid851_qualified_receipt_package_path[0] = '\0';
    cid851_qualified_receipt_member[0] = '\0';
    cid851_qualified_receipt_action[0] = '\0';
    if (cid851_retained_held_descriptor >= 0) {
        close(cid851_retained_held_descriptor);
        cid851_retained_held_descriptor = -1;
    }
    pthread_mutex_unlock(&cid850_lock);
}

void cid851_interpose_count_restore_metadata(void) {
    pthread_mutex_lock(&cid850_lock);
    cid851_count_metadata = true;
    cid851_legacy_metadata_writes = 0;
    cid851_canonical_metadata_writes = 0;
    pthread_mutex_unlock(&cid850_lock);
}

void cid851_interpose_reoccupy_before_completed_record_removal(void) {
    pthread_mutex_lock(&cid850_lock);
    cid851_reoccupy_before_record_removal = true;
    cid850_did_mutation_value = false;
    pthread_mutex_unlock(&cid850_lock);
}

void cid851_interpose_qualified_receipt_member_race(
    const char *package_path,
    const char *member,
    const char *action
) {
    pthread_mutex_lock(&cid850_lock);
    char resolved_package_path[PATH_MAX] = {0};
    const char *canonical_package_path = realpath(package_path, resolved_package_path) == NULL
        ? package_path
        : resolved_package_path;
    strlcpy(
        cid851_qualified_receipt_package_path,
        canonical_package_path,
        sizeof(cid851_qualified_receipt_package_path)
    );
    strlcpy(cid851_qualified_receipt_member, member, sizeof(cid851_qualified_receipt_member));
    strlcpy(cid851_qualified_receipt_action, action, sizeof(cid851_qualified_receipt_action));
    cid850_did_mutation_value = false;
    pthread_mutex_unlock(&cid850_lock);
}

int cid851_interpose_legacy_restore_metadata_writes(void) {
    pthread_mutex_lock(&cid850_lock);
    int value = cid851_legacy_metadata_writes;
    pthread_mutex_unlock(&cid850_lock);
    return value;
}

int cid851_interpose_canonical_restore_metadata_writes(void) {
    pthread_mutex_lock(&cid850_lock);
    int value = cid851_canonical_metadata_writes;
    pthread_mutex_unlock(&cid850_lock);
    return value;
}

void cid851_interpose_count_parent_reopens(const char *parent_path) {
    pthread_mutex_lock(&cid850_lock);
    strlcpy(cid851_parent_path, parent_path, sizeof(cid851_parent_path));
    cid851_parent_lock_seen = false;
    cid851_parent_reopens = 0;
    pthread_mutex_unlock(&cid850_lock);
}

int cid851_interpose_parent_reopens_after_lock(void) {
    pthread_mutex_lock(&cid850_lock);
    int value = cid851_parent_reopens;
    pthread_mutex_unlock(&cid850_lock);
    return value;
}

static bool cid851_files_equal(const char *left_path, const char *right_path) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    int left = (int)syscall(SYS_open, left_path, O_RDONLY | O_CLOEXEC, 0);
    int right = (int)syscall(SYS_open, right_path, O_RDONLY | O_CLOEXEC, 0);
#pragma clang diagnostic pop
    if (left < 0 || right < 0) {
        if (left >= 0) close(left);
        if (right >= 0) close(right);
        return false;
    }
    bool equal = true;
    unsigned char left_bytes[4096];
    unsigned char right_bytes[4096];
    for (;;) {
        ssize_t left_count = read(left, left_bytes, sizeof(left_bytes));
        ssize_t right_count = read(right, right_bytes, sizeof(right_bytes));
        if (left_count != right_count || left_count < 0
                || (left_count > 0
                    && memcmp(left_bytes, right_bytes, (size_t)left_count) != 0)) {
            equal = false;
            break;
        }
        if (left_count == 0) break;
    }
    close(left);
    close(right);
    return equal;
}

static bool cid851_paths_name_same_node(const char *left_path, const char *right_path) {
    struct stat left = {0};
    struct stat right = {0};
    return left_path != NULL
        && right_path != NULL
        && lstat(left_path, &left) == 0
        && lstat(right_path, &right) == 0
        && left.st_dev == right.st_dev
        && left.st_ino == right.st_ino;
}

static int cid851_sqlite_open_sidecar_extension(
    sqlite3 *database,
    char **error_message,
    const void *api
) {
    (void)error_message;
    (void)api;
    const char *main_path = sqlite3_db_filename(database, "main");
    char expected_path[PATH_MAX] = {0};
    char database_path[PATH_MAX] = {0};
    char sidecar_suffix[32] = {0};
    bool should_mutation = false;
    pthread_mutex_lock(&cid850_lock);
    cid851_sqlite_callback_count += 1;
    if (cid851_sqlite_sidecar_armed && !cid850_did_mutation_value
            && main_path != NULL
            && cid851_paths_name_same_node(
                main_path,
                cid851_sqlite_database_path
            )) {
        strlcpy(
            expected_path,
            cid851_sqlite_expected_database_path,
            sizeof(expected_path)
        );
        strlcpy(database_path, cid851_sqlite_database_path, sizeof(database_path));
        strlcpy(sidecar_suffix, cid851_sqlite_sidecar_suffix, sizeof(sidecar_suffix));
        should_mutation = true;
    }
    pthread_mutex_unlock(&cid850_lock);
    if (!should_mutation || !cid851_files_equal(main_path, expected_path)) {
        return 0;
    }
    (void)sidecar_suffix;
    // Create a real committed SQLite WAL/SHM before the caller's actual open
    // returns. This is intentionally not marker-byte shape testing: the WAL is
    // structurally valid and contains a committed frame that SQLite could
    // consume if the production boundary were not private/immutable.
    cid850_inside_interposer = true;
    sqlite3 *writer = NULL;
    int open_result = sqlite3_open_v2(
        database_path,
        &writer,
        0x00000002 | 0x00010000,
        NULL
    );
    if (open_result == 0 && writer != NULL) {
        char *message = NULL;
        int exec_result = sqlite3_exec(
            writer,
            "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; "
            "CREATE TABLE IF NOT EXISTS cid851_open_boundary(value INTEGER NOT NULL); "
            "INSERT INTO cid851_open_boundary(value) VALUES (851);",
            NULL,
            NULL,
            &message
        );
        if (message != NULL) sqlite3_free(message);
        if (exec_result == 0) {
            cid851_open_boundary_writer = writer;
        } else {
            (void)sqlite3_close_v2(writer);
        }
    }
    cid850_inside_interposer = false;
    pthread_mutex_lock(&cid850_lock);
    cid851_sqlite_sidecar_armed = false;
    cid850_did_mutation_value = true;
    pthread_mutex_unlock(&cid850_lock);
    return 0;
}

void cid851_install_sidecar_at_sqlite_open(
    const char *database_path,
    const char *expected_database_path,
    const char *sidecar_suffix
) {
    pthread_mutex_lock(&cid850_lock);
    strlcpy(cid851_sqlite_database_path, database_path, sizeof(cid851_sqlite_database_path));
    strlcpy(
        cid851_sqlite_expected_database_path,
        expected_database_path,
        sizeof(cid851_sqlite_expected_database_path)
    );
    strlcpy(cid851_sqlite_sidecar_suffix, sidecar_suffix, sizeof(cid851_sqlite_sidecar_suffix));
    cid851_sqlite_sidecar_armed = true;
    cid851_sqlite_callback_count = 0;
    cid850_did_mutation_value = false;
    pthread_mutex_unlock(&cid850_lock);
}

int cid851_sqlite_open_callback_count(void) {
    pthread_mutex_lock(&cid850_lock);
    int value = cid851_sqlite_callback_count;
    pthread_mutex_unlock(&cid850_lock);
    return value;
}

void cid851_reset_sqlite_open_sidecar(void) {
    if (cid851_open_boundary_writer != NULL) {
        (void)sqlite3_close_v2(cid851_open_boundary_writer);
        cid851_open_boundary_writer = NULL;
    }
    pthread_mutex_lock(&cid850_lock);
    cid851_sqlite_sidecar_armed = false;
    pthread_mutex_unlock(&cid850_lock);
}

static int cid851_sqlite3_open_v2(
    const char *filename,
    sqlite3 **database,
    int flags,
    const char *vfs
) {
    int result = sqlite3_open_v2(filename, database, flags, vfs);
    if (result == 0 && database != NULL && *database != NULL
            && !cid850_inside_interposer) {
        (void)cid851_sqlite_open_sidecar_extension(*database, NULL, NULL);
        char crash_path[PATH_MAX] = {0};
        pthread_mutex_lock(&cid850_lock);
        strlcpy(crash_path, cid851_crash_sqlite_path, sizeof(crash_path));
        pthread_mutex_unlock(&cid850_lock);
        if (crash_path[0] != '\0'
                && cid851_paths_name_same_node(filename, crash_path)) {
            // Boundary 9 is the first normal production open. The restore
            // transaction must already be durably committed and its record
            // removed before this point, so do not require transaction
            // metadata to still exist in order to exercise the boundary.
            cid851_crash_if_boundary(9);
        }
    }
    return result;
}

void cid851_interpose_crash_restore_boundary(int boundary, int ordinal) {
    pthread_mutex_lock(&cid850_lock);
    cid851_crash_boundary = boundary;
    cid851_crash_ordinal = ordinal;
    cid851_crash_seen = 0;
    pthread_mutex_unlock(&cid850_lock);
}

void cid851_interpose_crash_sqlite_open_for_path(const char *database_path) {
    pthread_mutex_lock(&cid850_lock);
    strlcpy(cid851_crash_sqlite_path, database_path, sizeof(cid851_crash_sqlite_path));
    pthread_mutex_unlock(&cid850_lock);
}

int cid851_interpose_restore_boundary_seen(void) {
    pthread_mutex_lock(&cid850_lock);
    int value = cid851_crash_seen;
    pthread_mutex_unlock(&cid850_lock);
    return value;
}

static void cid851_crash_if_boundary(int boundary) {
    bool should_crash = false;
    pthread_mutex_lock(&cid850_lock);
    if (cid851_crash_boundary == boundary) {
        cid851_crash_seen += 1;
        should_crash = cid851_crash_seen == cid851_crash_ordinal;
        if (should_crash) {
            cid850_did_mutation_value = true;
        }
    }
    pthread_mutex_unlock(&cid850_lock);
    if (should_crash) {
        _exit(90 + boundary);
    }
}

void cid851_interpose_move_source_before_restore_cleanup(
    const char *source_path,
    const char *held_path
) {
    pthread_mutex_lock(&cid850_lock);
    cid850_kind = CID851_MUTATION_MOVE_PATH_BEFORE_RESTORE_CLEANUP;
    cid850_did_mutation_value = false;
    strlcpy(cid851_cleanup_source_path, source_path, sizeof(cid851_cleanup_source_path));
    strlcpy(cid851_cleanup_held_path, held_path, sizeof(cid851_cleanup_held_path));
    pthread_mutex_unlock(&cid850_lock);
}

void cid851_interpose_replace_parent_before_restore_cleanup(
    const char *parent_path,
    const char *held_path
) {
    pthread_mutex_lock(&cid850_lock);
    cid850_kind = CID851_MUTATION_REPLACE_PARENT_BEFORE_RESTORE_CLEANUP;
    cid850_did_mutation_value = false;
    strlcpy(cid851_cleanup_source_path, parent_path, sizeof(cid851_cleanup_source_path));
    strlcpy(cid851_cleanup_held_path, held_path, sizeof(cid851_cleanup_held_path));
    pthread_mutex_unlock(&cid850_lock);
}

void cid850_interpose_pause_after_stage_ownership(
    const char *ready_path,
    const char *release_path
) {
    pthread_mutex_lock(&cid850_lock);
    cid850_kind = CID850_MUTATION_STAGE_OWNERSHIP_PAUSE;
    cid850_did_mutation_value = false;
    strlcpy(cid850_ownership_ready_path, ready_path, sizeof(cid850_ownership_ready_path));
    strlcpy(cid850_ownership_release_path, release_path, sizeof(cid850_ownership_release_path));
    pthread_mutex_unlock(&cid850_lock);
}

void cid850_interpose_grow_staged_child_before_clone(void) {
    cid850_configure(CID850_MUTATION_CLONE_SOURCE_GROW, ".ciderbackup", "");
}

void cid850_interpose_replace_staged_child_before_clone(void) {
    cid850_configure(CID850_MUTATION_CLONE_SOURCE_REPLACE, ".ciderbackup", "");
}

void cid850_interpose_grow_published_child_after_clone(void) {
    cid850_configure(CID850_MUTATION_CLONE_DESTINATION_GROW, ".ciderbackup", "");
}

void cid850_interpose_replace_published_child_after_clone(void) {
    cid850_configure(CID850_MUTATION_CLONE_DESTINATION_REPLACE, ".ciderbackup", "");
}

void cid850_interpose_configure_flock_probe(
    int role,
    const char *ready_path,
    const char *release_path,
    const char *result_path
) {
    pthread_mutex_lock(&cid850_lock);
    cid850_flock_probe_role = role;
    cid850_flock_exclusive_seen = 0;
    cid850_flock_probe_reported = false;
    strlcpy(cid850_ready_path, ready_path, sizeof(cid850_ready_path));
    strlcpy(cid850_release_path, release_path, sizeof(cid850_release_path));
    strlcpy(cid850_result_path, result_path, sizeof(cid850_result_path));
    pthread_mutex_unlock(&cid850_lock);
}

static void cid850_write_probe_byte(const char *path, char value) {
    int descriptor = open(path, O_WRONLY | O_CLOEXEC);
    if (descriptor >= 0) {
        (void)write(descriptor, &value, 1);
        close(descriptor);
    }
}

static void cid850_release_probe_a(void) {
    cid850_write_probe_byte(cid850_release_path, 'R');
}

static int cid850_flock(int descriptor, int operation) {
    if (cid850_inside_interposer) {
        return cid850_real_flock(descriptor, operation);
    }
    if ((operation & LOCK_UN) != 0) {
        int result = cid850_real_flock(descriptor, operation);
        pthread_mutex_lock(&cid850_lock);
        if (result == 0 && cid851_count_restore_authority) {
            cid851_restore_authority_releases += 1;
        }
        pthread_mutex_unlock(&cid850_lock);
        return result;
    }
    int role = 0;
    int ordinal = 0;
    pthread_mutex_lock(&cid850_lock);
    role = cid850_flock_probe_role;
    if (role != 0 && (operation & LOCK_EX) != 0) {
        cid850_flock_exclusive_seen += 1;
        ordinal = cid850_flock_exclusive_seen;
    }
    pthread_mutex_unlock(&cid850_lock);
    if (role == 0 || ordinal == 0) {
        int result = cid850_real_flock(descriptor, operation);
        pthread_mutex_lock(&cid850_lock);
        if (result == 0 && cid851_count_restore_authority
                && (operation & LOCK_EX) != 0) {
            cid851_restore_authority_acquisitions += 1;
        }
        if (result == 0 && cid851_parent_path[0] != '\0'
                && (operation & LOCK_EX) != 0) {
            char path[PATH_MAX] = {0};
            if (fcntl(descriptor, F_GETPATH, path) == 0
                    && strcmp(path, cid851_parent_path) == 0) {
                cid851_parent_lock_seen = true;
            }
        }
        pthread_mutex_unlock(&cid850_lock);
        return result;
    }

    cid850_inside_interposer = true;
    if (role == 1) {
        int result = cid850_real_flock(descriptor, operation);
        if (result == 0 && ordinal == 2) {
            cid850_write_probe_byte(cid850_ready_path, 'A');
            int release_descriptor = open(cid850_release_path, O_RDONLY | O_CLOEXEC);
            if (release_descriptor >= 0) {
                char value = 0;
                (void)read(release_descriptor, &value, 1);
                close(release_descriptor);
            }
        }
        cid850_inside_interposer = false;
        return result;
    }

    if (ordinal != 1) {
        return cid850_real_flock(descriptor, operation);
    }

    int probe = cid850_real_flock(descriptor, operation | LOCK_NB);
    if (probe == 0) {
        cid850_write_probe_byte(cid850_result_path, '1');
        cid850_release_probe_a();
        pthread_mutex_lock(&cid850_lock);
        cid850_flock_probe_reported = true;
        pthread_mutex_unlock(&cid850_lock);
        cid850_inside_interposer = false;
        return 0;
    }
    int probe_error = errno;
    if (probe_error == EWOULDBLOCK) {
        cid850_write_probe_byte(cid850_result_path, '0');
        cid850_release_probe_a();
        pthread_mutex_lock(&cid850_lock);
        cid850_flock_probe_reported = true;
        pthread_mutex_unlock(&cid850_lock);
        int result = cid850_real_flock(descriptor, operation & ~LOCK_NB);
        cid850_inside_interposer = false;
        return result;
    }
    errno = probe_error;
    cid850_inside_interposer = false;
    return -1;
}

static void cid850_configure(
    enum cid850_mutation_kind kind,
    const char *suffix,
    const char *held_name
) {
    pthread_mutex_lock(&cid850_lock);
    cid850_kind = kind;
    strlcpy(cid850_suffix, suffix, sizeof(cid850_suffix));
    strlcpy(cid850_held_name, held_name, sizeof(cid850_held_name));
    cid850_did_mutation_value = false;
    pthread_mutex_unlock(&cid850_lock);
}

void cid850_interpose_replace_after_mkdirat(const char *suffix, const char *held_name) {
    cid850_configure(CID850_MUTATION_MKDIRAT, suffix, held_name);
}

void cid850_interpose_replace_after_fclonefileat(const char *suffix, const char *held_name) {
    cid850_configure(CID850_MUTATION_FCLONEFILEAT, suffix, held_name);
}

void cid850_interpose_crash_after_fclonefileat(const char *suffix) {
    cid850_configure(CID850_MUTATION_FCLONEFILEAT_CRASH, suffix, "");
}

void cid850_interpose_fail_append_guard_restoration(void) {
    cid850_configure(CID850_MUTATION_FCHFLAGS_RESTORE, "", "");
}

void cid850_interpose_replace_after_renameatx_np(const char *suffix, const char *held_name) {
    cid850_configure(CID850_MUTATION_RENAMEATX, suffix, held_name);
}

void cid850_interpose_replace_before_renameatx_np(const char *suffix, const char *held_name) {
    cid850_configure(CID850_MUTATION_RENAMEATX_SOURCE, suffix, held_name);
}

void cid850_interpose_crash_before_renameatx_np(const char *suffix) {
    cid850_configure(CID850_MUTATION_RENAMEATX_CRASH, suffix, "");
}

void cid850_interpose_replace_before_lseek(
    const char *suffix,
    const char *held_name,
    int ordinal
) {
    cid850_configure(CID850_MUTATION_LSEEK, suffix, held_name);
    pthread_mutex_lock(&cid850_lock);
    cid850_lseek_ordinal = ordinal;
    cid850_lseek_seen = 0;
    pthread_mutex_unlock(&cid850_lock);
}

void cid850_interpose_replace_before_ftruncate(const char *suffix, const char *held_name) {
    cid850_configure(CID850_MUTATION_FTRUNCATE, suffix, held_name);
}

void cid850_interpose_create_sidecar_before_swap(
    const char *database_suffix,
    const char *sidecar_suffix
) {
    cid850_configure(CID850_MUTATION_SIDECAR_BEFORE_SWAP, database_suffix, sidecar_suffix);
}

void cid850_interpose_create_sidecar_after_swap(
    const char *database_suffix,
    const char *sidecar_suffix
) {
    cid850_configure(CID850_MUTATION_SIDECAR_AFTER_SWAP, database_suffix, sidecar_suffix);
}

void cid850_interpose_fail_post_swap_parent_fsync(
    const char *database_suffix,
    int failure_count
) {
    cid850_configure(CID850_MUTATION_POST_SWAP_FSYNC, database_suffix, "");
    pthread_mutex_lock(&cid850_lock);
    cid850_fsync_failures_remaining = failure_count;
    cid850_post_swap_fsync_armed = false;
    cid850_post_swap_seen = false;
    pthread_mutex_unlock(&cid850_lock);
}

void cid850_interpose_crash_after_restore_swap(const char *database_suffix) {
    cid850_configure(CID850_MUTATION_RESTORE_CRASH_AFTER_SWAP, database_suffix, "");
}

void cid851_interpose_crash_before_restore_completion(const char *database_suffix) {
    cid850_configure(CID851_MUTATION_RESTORE_CRASH_BEFORE_COMPLETION, database_suffix, "");
}

void cid850_interpose_fail_restore_reopen_after_swap(const char *database_suffix) {
    cid850_configure(CID850_MUTATION_RESTORE_REOPEN_AFTER_SWAP, database_suffix, "");
}

void cid850_interpose_fail_restore_integrity_after_swap(const char *database_suffix) {
    cid850_configure(CID850_MUTATION_RESTORE_INTEGRITY_AFTER_SWAP, database_suffix, "");
}

void cid850_interpose_fail_restore_record_removal_fsync(void) {
    cid850_configure(CID850_MUTATION_RESTORE_RECORD_REMOVAL_FSYNC, "", "");
}

void cid851_interpose_count_restore_authority(void) {
    pthread_mutex_lock(&cid850_lock);
    cid851_count_restore_authority = true;
    cid851_restore_authority_acquisitions = 0;
    cid851_restore_authority_releases = 0;
    pthread_mutex_unlock(&cid850_lock);
}

int cid851_interpose_restore_authority_acquisitions(void) {
    pthread_mutex_lock(&cid850_lock);
    int value = cid851_restore_authority_acquisitions;
    pthread_mutex_unlock(&cid850_lock);
    return value;
}

int cid851_interpose_restore_authority_releases(void) {
    pthread_mutex_lock(&cid850_lock);
    int value = cid851_restore_authority_releases;
    pthread_mutex_unlock(&cid850_lock);
    return value;
}

bool cid850_interpose_did_mutation(void) {
    pthread_mutex_lock(&cid850_lock);
    bool value = cid850_did_mutation_value;
    pthread_mutex_unlock(&cid850_lock);
    return value;
}

static int cid851_open(const char *path, int flags, ...) {
    mode_t mode = 0;
    if ((flags & O_CREAT) != 0) {
        va_list arguments;
        va_start(arguments, flags);
        mode = (mode_t)va_arg(arguments, int);
        va_end(arguments);
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    int result = (int)syscall(SYS_open, path, flags, mode);
#pragma clang diagnostic pop
    int saved_errno = errno;
    if (result >= 0 && !cid850_inside_interposer && path != NULL) {
        pthread_mutex_lock(&cid850_lock);
        if (cid851_parent_lock_seen && cid851_parent_path[0] != '\0'
                && strcmp(path, cid851_parent_path) == 0) {
            cid851_parent_reopens += 1;
        }
        pthread_mutex_unlock(&cid850_lock);
    }
    errno = saved_errno;
    return result;
}

static void cid851_apply_qualified_receipt_preopen_race(
    int directory,
    const char *name
) {
    if (cid850_inside_interposer || name == NULL) return;
    char directory_path[PATH_MAX] = {0};
    if (fcntl(directory, F_GETPATH, directory_path) != 0) return;
    char action[32] = {0};
    pthread_mutex_lock(&cid850_lock);
    if (strcmp(directory_path, cid851_qualified_receipt_package_path) == 0
            && strcmp(name, cid851_qualified_receipt_member) == 0
            && (strcmp(cid851_qualified_receipt_action, "before-open-identical") == 0
                || strcmp(cid851_qualified_receipt_action, "before-open-oversized") == 0)) {
        strlcpy(action, cid851_qualified_receipt_action, sizeof(action));
        cid851_qualified_receipt_action[0] = '\0';
        cid850_did_mutation_value = true;
    }
    pthread_mutex_unlock(&cid850_lock);
    if (action[0] == '\0') return;

    cid850_inside_interposer = true;
    int original = openat(directory, name, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC);
    struct stat metadata;
    if (original >= 0 && fstat(original, &metadata) == 0 && S_ISREG(metadata.st_mode)) {
        char held[NAME_MAX] = {0};
        snprintf(held, sizeof(held), ".cid851-receipt-held-%s", name);
        (void)unlinkat(directory, held, 0);
        if (strcmp(action, "before-open-identical") == 0) {
            char temporary[NAME_MAX] = {0};
            snprintf(temporary, sizeof(temporary), ".cid851-receipt-new-%s", name);
            (void)unlinkat(directory, temporary, 0);
            if (fclonefileat(original, directory, temporary, 0) == 0
                    && renameat(directory, name, directory, held) == 0) {
                (void)renameat(directory, temporary, directory, name);
            }
        } else if (renameat(directory, name, directory, held) == 0) {
            int replacement = openat(
                directory,
                name,
                O_RDWR | O_CREAT | O_EXCL | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            );
            if (replacement >= 0) {
                (void)ftruncate(replacement, metadata.st_size + (off_t)(2 * 1024 * 1024));
                (void)fsync(replacement);
                close(replacement);
            }
        }
    }
    if (original >= 0) close(original);
    cid850_inside_interposer = false;
}

static int cid851_openat(int directory, const char *name, int flags, ...) {
    mode_t mode = 0;
    if ((flags & O_CREAT) != 0) {
        va_list arguments;
        va_start(arguments, flags);
        mode = (mode_t)va_arg(arguments, int);
        va_end(arguments);
    }
    cid851_mutate_receipt_selector_before_final_manifest_open(directory, name);
    cid851_apply_qualified_receipt_preopen_race(directory, name);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    int result = (int)syscall(SYS_openat, directory, name, flags, mode);
#pragma clang diagnostic pop
    int saved_errno = errno;
    if (result >= 0 && !cid850_inside_interposer && name != NULL
            && (flags & O_CREAT) != 0 && (flags & O_EXCL) != 0) {
        bool is_record = strncmp(name, ".cid851-restore-", 16) == 0
            && strstr(name, ".json") != NULL;
        bool is_member = strncmp(name, ".cid851-restore-", 16) == 0
            && strstr(name, "-staging.sqlite") != NULL;
        pthread_mutex_lock(&cid850_lock);
        if (is_record && cid851_count_metadata) {
            cid851_canonical_metadata_writes += 1;
        }
        pthread_mutex_unlock(&cid850_lock);
        if (is_record) {
            cid851_crash_if_boundary(1);
        } else if (is_member) {
            cid851_crash_if_boundary(2);
        }
    }
    errno = saved_errno;
    return result;
}

static ssize_t cid851_pread(int descriptor, void *buffer, size_t count, off_t offset) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    ssize_t result = (ssize_t)syscall(SYS_pread, descriptor, buffer, count, offset);
#pragma clang diagnostic pop
    if (result <= 0 || cid850_inside_interposer) return result;
    char descriptor_path[PATH_MAX] = {0};
    if (fcntl(descriptor, F_GETPATH, descriptor_path) != 0) return result;
    char expected_path[PATH_MAX] = {0};
    pthread_mutex_lock(&cid850_lock);
    snprintf(
        expected_path,
        sizeof(expected_path),
        "%s/%s",
        cid851_qualified_receipt_package_path,
        cid851_qualified_receipt_member
    );
    bool mutate = strcmp(cid851_qualified_receipt_action, "post-read-mutate") == 0
        && strcmp(descriptor_path, expected_path) == 0;
    if (mutate) {
        cid851_qualified_receipt_action[0] = '\0';
        cid850_did_mutation_value = true;
    }
    pthread_mutex_unlock(&cid850_lock);
    if (!mutate) return result;

    cid850_inside_interposer = true;
    int writable = open(descriptor_path, O_RDWR | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC);
    if (writable >= 0) {
        unsigned char byte = 0;
        if (syscall(SYS_pread, writable, &byte, 1, 0) == 1) {
            byte ^= 0x5a;
            (void)pwrite(writable, &byte, 1, 0);
            (void)fsync(writable);
        }
        close(writable);
    }
    cid850_inside_interposer = false;
    return result;
}

static int cid850_mkdirat(int directory, const char *name, mode_t mode) {
    int result = cid850_real_mkdirat(directory, name, mode);
    int saved_errno = errno;
    if (result == 0 && !cid850_inside_interposer) {
        char held_name[256];
        if (cid850_matches(name, CID850_MUTATION_MKDIRAT, held_name)) {
            cid850_inside_interposer = true;
            if (renameat(directory, name, directory, held_name) == 0) {
                (void)cid850_real_mkdirat(directory, name, mode);
            }
            cid850_inside_interposer = false;
        }
    }
    errno = saved_errno;
    return result;
}

static bool cid850_take_clone_child_mutation(
    const char *destination_name,
    bool before_clone,
    bool *replace
) {
    bool mutation = false;
    pthread_mutex_lock(&cid850_lock);
    enum cid850_mutation_kind grow_kind = before_clone
        ? CID850_MUTATION_CLONE_SOURCE_GROW
        : CID850_MUTATION_CLONE_DESTINATION_GROW;
    enum cid850_mutation_kind replace_kind = before_clone
        ? CID850_MUTATION_CLONE_SOURCE_REPLACE
        : CID850_MUTATION_CLONE_DESTINATION_REPLACE;
    if (!cid850_did_mutation_value
            && (cid850_kind == grow_kind || cid850_kind == replace_kind)
            && destination_name != NULL) {
        size_t name_length = strlen(destination_name);
        size_t suffix_length = strlen(cid850_suffix);
        if (name_length >= suffix_length
                && strcmp(destination_name + name_length - suffix_length, cid850_suffix) == 0) {
            *replace = cid850_kind == replace_kind;
            cid850_did_mutation_value = true;
            mutation = true;
        }
    }
    pthread_mutex_unlock(&cid850_lock);
    return mutation;
}

static void cid850_mutate_cloned_package_child(int package_directory, bool replace) {
    const char *child_name = "database.sqlite";
    int child = openat(
        package_directory,
        child_name,
        O_RDWR | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
    );
    if (child < 0) {
        return;
    }
    struct stat metadata;
    if (fstat(child, &metadata) != 0 || !S_ISREG(metadata.st_mode)) {
        close(child);
        return;
    }
    off_t enlarged_size = metadata.st_size + (off_t)(2 * 1024 * 1024);
    if (replace) {
        close(child);
        if (unlinkat(package_directory, child_name, 0) != 0) {
            return;
        }
        child = openat(
            package_directory,
            child_name,
            O_RDWR | O_CREAT | O_EXCL | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        );
        if (child < 0) {
            return;
        }
        const char marker[] = "cid850-clone-seam-replacement";
        (void)write(child, marker, sizeof(marker) - 1);
    }
    (void)ftruncate(child, enlarged_size);
    (void)fsync(child);
    close(child);
}

static int cid850_fclonefileat(
    int source,
    int destination_directory,
    const char *destination_name,
    uint32_t flags
) {
    if (!cid850_inside_interposer
            && cid851_take_restore_member_mutation(
                CID851_MUTATION_MEMBER_BEFORE_CLONE,
                destination_name
            )) {
        cid850_inside_interposer = true;
        cid851_mutate_same_size_descriptor(source);
        cid850_inside_interposer = false;
    }
    bool replace_source = false;
    if (!cid850_inside_interposer
            && cid850_take_clone_child_mutation(destination_name, true, &replace_source)) {
        cid850_inside_interposer = true;
        cid850_mutate_cloned_package_child(source, replace_source);
        cid850_inside_interposer = false;
    }
    int result = cid850_real_fclonefileat(source, destination_directory, destination_name, flags);
    int saved_errno = errno;
    if (result == 0 && !cid850_inside_interposer) {
        bool replace_destination = false;
        if (cid850_take_clone_child_mutation(destination_name, false, &replace_destination)) {
            cid850_inside_interposer = true;
            int published = openat(
                destination_directory,
                destination_name,
                O_RDONLY | O_DIRECTORY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC
            );
            if (published >= 0) {
                cid850_mutate_cloned_package_child(published, replace_destination);
                close(published);
            }
            cid850_inside_interposer = false;
        }
        char unused_name[256];
        if (cid850_matches(destination_name, CID850_MUTATION_FCLONEFILEAT_CRASH, unused_name)) {
            _exit(88);
        }
        char held_name[256];
        if (cid850_matches(destination_name, CID850_MUTATION_FCLONEFILEAT, held_name)) {
            cid850_inside_interposer = true;
            if (renameat(destination_directory, destination_name, destination_directory, held_name) == 0) {
                (void)cid850_real_fclonefileat(
                    source,
                    destination_directory,
                    destination_name,
                    flags
                );
            }
            cid850_inside_interposer = false;
        }
        if (destination_name != NULL
                && strstr(destination_name, ".ciderbackup") == NULL) {
            cid851_crash_if_boundary(4);
        }
    }
    errno = saved_errno;
    return result;
}

static int cid850_fsync(int descriptor) {
    bool should_fail = false;
    pthread_mutex_lock(&cid850_lock);
    if (!cid850_inside_interposer
            && cid850_kind == CID850_MUTATION_RESTORE_RECORD_REMOVAL_FSYNC
            && cid850_restore_record_removed
            && !cid850_did_mutation_value) {
        cid850_did_mutation_value = true;
        should_fail = true;
    }
    if (!cid850_inside_interposer
            && cid850_kind == CID850_MUTATION_POST_SWAP_FSYNC
            && cid850_post_swap_fsync_armed
            && cid850_fsync_failures_remaining > 0) {
        cid850_fsync_failures_remaining -= 1;
        cid850_did_mutation_value = true;
        should_fail = true;
    }
    pthread_mutex_unlock(&cid850_lock);
    if (should_fail) {
        errno = EIO;
        return -1;
    }
    cid851_crash_if_boundary(7);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return (int)syscall(SYS_fsync, descriptor);
#pragma clang diagnostic pop
}

static int cid850_unlinkat(int directory, const char *name, int flags) {
    if (!cid850_inside_interposer
            && name != NULL
            && strstr(name, ".cid851-restore-") == name
            && strstr(name, "-cleanup-retained-") != NULL) {
        pthread_mutex_lock(&cid850_lock);
        if (cid851_count_retained_unlinks) {
            cid851_retained_unlink_attempts += 1;
        }
        pthread_mutex_unlock(&cid850_lock);
    }
    bool cleanup_boundary = !cid850_inside_interposer
        && cid851_take_restore_member_mutation(
                CID851_MUTATION_MEMBER_BEFORE_UNLINK,
                name
            );
    if (cleanup_boundary) {
        cid850_inside_interposer = true;
        cid851_mutate_same_size_member(directory, name);
        cid850_inside_interposer = false;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    int result = (int)syscall(SYS_unlinkat, directory, name, flags);
#pragma clang diagnostic pop
    if (result == 0 && cleanup_boundary) {
        cid850_inside_interposer = true;
        cid851_create_cleanup_replacement(directory, name);
        cid850_inside_interposer = false;
    }
    if (result == 0 && name != NULL) {
        size_t length = strlen(name);
        const char *prefix = ".cid851-restore-";
        const char *suffix = ".json";
        size_t prefix_length = strlen(prefix);
        size_t suffix_length = strlen(suffix);
        pthread_mutex_lock(&cid850_lock);
        if (cid850_kind == CID850_MUTATION_RESTORE_RECORD_REMOVAL_FSYNC
                && length > prefix_length + suffix_length
                && strncmp(name, prefix, prefix_length) == 0
                && strcmp(name + length - suffix_length, suffix) == 0) {
            cid850_restore_record_removed = true;
        }
        pthread_mutex_unlock(&cid850_lock);
        if (strstr(name, "restore-") != NULL) {
            cid851_crash_if_boundary(6);
        }
    }
    return result;
}

static int cid851_fremovexattr(int descriptor, const char *name, int options) {
    bool reoccupy = false;
    if (!cid850_inside_interposer && name != NULL
            && strcmp(name, "com.cider.cid851.restore-transaction-v2") == 0) {
        pthread_mutex_lock(&cid850_lock);
        if (cid851_reoccupy_before_record_removal) {
            cid851_reoccupy_before_record_removal = false;
            cid850_did_mutation_value = true;
            reoccupy = true;
        }
        pthread_mutex_unlock(&cid850_lock);
    }
    if (reoccupy) {
        cid850_inside_interposer = true;
        int occupant = openat(
            descriptor,
            ".cid851-restore-fixed-staging.sqlite",
            O_WRONLY | O_CREAT | O_EXCL | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        );
        if (occupant >= 0) {
            const char marker[] = "record-removal-reoccupation";
            (void)write(occupant, marker, sizeof(marker) - 1);
            (void)fsync(occupant);
            close(occupant);
        }
        cid850_inside_interposer = false;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    int result = (int)syscall(SYS_fremovexattr, descriptor, name, options);
#pragma clang diagnostic pop
    if (result == 0 && name != NULL
            && strcmp(name, "com.cider.cid851.restore-transaction-v2") == 0) {
        cid851_crash_if_boundary(8);
    }
    return result;
}

static int cid850_fchflags(int descriptor, unsigned int flags) {
    pthread_mutex_lock(&cid850_lock);
    bool should_fail = cid850_kind == CID850_MUTATION_FCHFLAGS_RESTORE
        && (flags & UF_APPEND) == 0;
    if (should_fail) {
        cid850_did_mutation_value = true;
    }
    pthread_mutex_unlock(&cid850_lock);
    if (should_fail) {
        errno = EPERM;
        return -1;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return (int)syscall(SYS_fchflags, descriptor, flags);
#pragma clang diagnostic pop
}

static int cid850_renameatx_np(
    int source_directory,
    const char *source_name,
    int destination_directory,
    const char *destination_name,
    unsigned int flags
) {
    bool occupy_cleanup_destination = false;
    if (!cid850_inside_interposer
            && destination_name != NULL
            && strstr(destination_name, "-cleanup-retained-") != NULL) {
        pthread_mutex_lock(&cid850_lock);
        if (!cid850_did_mutation_value
                && cid850_kind == CID851_MUTATION_CLEANUP_DESTINATION_EXISTS) {
            cid850_did_mutation_value = true;
            occupy_cleanup_destination = true;
        }
        pthread_mutex_unlock(&cid850_lock);
        if (occupy_cleanup_destination) {
            cid850_inside_interposer = true;
            int occupant = openat(
                destination_directory,
                destination_name,
                O_RDWR | O_CREAT | O_EXCL | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            );
            if (occupant >= 0) {
                const char marker[] = "cid851-cleanup-destination-occupant";
                (void)write(occupant, marker, sizeof(marker) - 1);
                (void)fsync(occupant);
                close(occupant);
            }
            cid850_inside_interposer = false;
        }
    }
    bool cleanup_boundary = false;
    if (!cid850_inside_interposer
            && destination_name != NULL
            && strstr(destination_name, "-cleanup-retained-") != NULL) {
        cleanup_boundary = cid851_take_restore_member_mutation(
            CID851_MUTATION_MEMBER_BEFORE_UNLINK,
            source_name
        );
        if (cleanup_boundary) {
            cid850_inside_interposer = true;
            cid851_mutate_same_size_member(source_directory, source_name);
            cid850_inside_interposer = false;
        }
    }
    if (!cid850_inside_interposer
            && cid851_take_restore_member_mutation(
                CID851_MUTATION_MEMBER_BEFORE_RENAME,
                source_name
            )) {
        cid850_inside_interposer = true;
        cid851_mutate_same_size_member(source_directory, source_name);
        cid850_inside_interposer = false;
    }
    if (!cid850_inside_interposer) {
        char sidecar_suffix[256];
        if (cid850_matches(destination_name, CID850_MUTATION_SIDECAR_BEFORE_SWAP, sidecar_suffix)) {
            cid850_inside_interposer = true;
            char sidecar_name[PATH_MAX];
            (void)snprintf(sidecar_name, sizeof(sidecar_name), "%s%s", destination_name, sidecar_suffix);
            int sidecar = openat(
                destination_directory,
                sidecar_name,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            );
            if (sidecar >= 0) {
                const char marker[] = "cid850-unexpected-sidecar";
                (void)write(sidecar, marker, sizeof(marker) - 1);
                (void)fsync(sidecar);
                close(sidecar);
            }
            cid850_inside_interposer = false;
        }
    }
    if (!cid850_inside_interposer) {
        char unused_name[256];
        if (cid850_matches(source_name, CID850_MUTATION_RENAMEATX_CRASH, unused_name)) {
            _exit(86);
        }
        char held_name[256];
        if (cid850_matches(source_name, CID850_MUTATION_RENAMEATX_SOURCE, held_name)) {
            cid850_inside_interposer = true;
            if (renameat(source_directory, source_name, source_directory, held_name) == 0) {
                int held_descriptor = openat(
                    source_directory,
                    held_name,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC
                );
                if (held_descriptor >= 0) {
                    (void)cid850_real_fclonefileat(
                        held_descriptor,
                        source_directory,
                        source_name,
                        0
                    );
                    close(held_descriptor);
                }
            }
            cid850_inside_interposer = false;
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    int result = (int)syscall(
        SYS_renameatx_np,
        source_directory,
        source_name,
        destination_directory,
        destination_name,
        flags
    );
#pragma clang diagnostic pop
    int saved_errno = errno;
    if (result == 0 && cleanup_boundary) {
        cid850_inside_interposer = true;
        cid851_create_cleanup_replacement(source_directory, source_name);
        cid850_inside_interposer = false;
    }
    if (result == 0
            && !cid850_inside_interposer
            && destination_name != NULL
            && strstr(destination_name, "-cleanup-retained-") != NULL) {
        bool reoccupy = false;
        bool mutate_held = false;
        int held = -1;
        pthread_mutex_lock(&cid850_lock);
        if (!cid850_did_mutation_value
                && cid850_kind == CID851_MUTATION_CLEANUP_SOURCE_REOCCUPIED) {
            cid850_did_mutation_value = true;
            reoccupy = true;
        } else if (!cid850_did_mutation_value
                && cid850_kind == CID851_MUTATION_HELD_AFTER_RETENTION
                && cid851_retained_held_descriptor >= 0) {
            cid850_did_mutation_value = true;
            mutate_held = true;
            held = cid851_retained_held_descriptor;
        }
        pthread_mutex_unlock(&cid850_lock);
        cid850_inside_interposer = true;
        if (reoccupy) {
            cid851_create_cleanup_replacement(source_directory, source_name);
        }
        if (mutate_held) {
            cid851_mutate_same_size_descriptor(held);
        }
        cid850_inside_interposer = false;
    }
    if (result == 0 && !cid850_inside_interposer
            && ((source_name != NULL && strstr(source_name, "restore-") != NULL)
                || (destination_name != NULL && strstr(destination_name, "restore-") != NULL))) {
        cid851_crash_if_boundary(5);
    }
    if (result == 0
            && !cid850_inside_interposer
            && (flags & RENAME_SWAP) != 0) {
        char unused_name[256];
        if (cid850_matches(
                destination_name,
                CID850_MUTATION_RESTORE_CRASH_AFTER_SWAP,
                unused_name
            )) {
            _exit(87);
        }
    }
    if (result == 0 && !cid850_inside_interposer && (flags & RENAME_SWAP) != 0) {
        char unused_name[256];
        if (cid850_matches(
                destination_name,
                CID851_MUTATION_RESTORE_CRASH_BEFORE_COMPLETION,
                unused_name
            )) {
            pthread_mutex_lock(&cid850_lock);
            cid850_post_swap_seen = true;
            pthread_mutex_unlock(&cid850_lock);
        }
    }
    if (result == 0 && !cid850_inside_interposer && (flags & RENAME_SWAP) != 0) {
        char unused_name[256];
        bool fail_reopen = cid850_matches(
            destination_name,
            CID850_MUTATION_RESTORE_REOPEN_AFTER_SWAP,
            unused_name
        );
        bool fail_integrity = cid850_matches(
            destination_name,
            CID850_MUTATION_RESTORE_INTEGRITY_AFTER_SWAP,
            unused_name
        );
        if (fail_reopen || fail_integrity) {
            cid850_inside_interposer = true;
            int live = openat(
                destination_directory,
                destination_name,
                fail_reopen ? O_RDONLY | O_NOFOLLOW | O_CLOEXEC
                    : O_RDWR | O_NOFOLLOW | O_CLOEXEC
            );
            if (live >= 0) {
                if (fail_reopen) {
                    (void)fchmod(live, 0);
                } else {
                    unsigned char damage[256] = {0};
                    (void)pwrite(live, damage, sizeof(damage), 100);
                }
                (void)fsync(live);
                close(live);
            }
            cid850_inside_interposer = false;
        }
    }
    if (result == 0 && !cid850_inside_interposer && (flags & RENAME_SWAP) != 0) {
        pthread_mutex_lock(&cid850_lock);
        if (cid850_kind == CID850_MUTATION_POST_SWAP_FSYNC
                && !cid850_post_swap_seen
                && destination_name != NULL) {
            size_t name_length = strlen(destination_name);
            size_t suffix_length = strlen(cid850_suffix);
            if (name_length >= suffix_length
                    && strcmp(destination_name + name_length - suffix_length, cid850_suffix) == 0) {
                cid850_post_swap_seen = true;
                cid850_post_swap_fsync_armed = true;
            }
        }
        pthread_mutex_unlock(&cid850_lock);
    }
    if (result == 0 && !cid850_inside_interposer && (flags & RENAME_SWAP) != 0) {
        pthread_mutex_lock(&cid850_lock);
        if ((cid850_kind == CID850_MUTATION_RESTORE_REOPEN_AFTER_SWAP
                || cid850_kind == CID850_MUTATION_RESTORE_INTEGRITY_AFTER_SWAP)
                && destination_name != NULL) {
            size_t name_length = strlen(destination_name);
            size_t suffix_length = strlen(cid850_suffix);
            if (name_length >= suffix_length
                    && strcmp(destination_name + name_length - suffix_length, cid850_suffix) == 0) {
                cid850_post_swap_seen = true;
            }
        }
        pthread_mutex_unlock(&cid850_lock);
    }
    if (result == 0 && !cid850_inside_interposer) {
        char sidecar_suffix[256];
        if (cid850_matches(destination_name, CID850_MUTATION_SIDECAR_AFTER_SWAP, sidecar_suffix)) {
            cid850_inside_interposer = true;
            char sidecar_name[PATH_MAX];
            (void)snprintf(sidecar_name, sizeof(sidecar_name), "%s%s", destination_name, sidecar_suffix);
            int sidecar = openat(
                destination_directory,
                sidecar_name,
                O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            );
            if (sidecar >= 0) {
                const char marker[] = "cid850-unexpected-sidecar";
                (void)write(sidecar, marker, sizeof(marker) - 1);
                (void)fsync(sidecar);
                close(sidecar);
            }
            cid850_inside_interposer = false;
        }
    }
    if (result == 0 && !cid850_inside_interposer) {
        char held_name[256];
        if (cid850_matches(destination_name, CID850_MUTATION_RENAMEATX, held_name)) {
            cid850_inside_interposer = true;
            if (renameat(destination_directory, destination_name, destination_directory, held_name) == 0) {
                int held_descriptor = openat(
                    destination_directory,
                    held_name,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC
                );
                if (held_descriptor >= 0) {
                    (void)cid850_real_fclonefileat(
                        held_descriptor,
                        destination_directory,
                        destination_name,
                        0
                    );
                    close(held_descriptor);
                }
            }
            cid850_inside_interposer = false;
        }
    }
    errno = saved_errno;
    return result;
}

static off_t cid850_lseek(int descriptor, off_t offset, int whence) {
    if (!cid850_inside_interposer) {
        char path[PATH_MAX];
        if (fcntl(descriptor, F_GETPATH, path) == 0) {
            char held_name[256] = {0};
            bool should_mutation = false;
            pthread_mutex_lock(&cid850_lock);
            if (!cid850_did_mutation_value && cid850_kind == CID850_MUTATION_LSEEK) {
                size_t path_length = strlen(path);
                size_t suffix_length = strlen(cid850_suffix);
                if (path_length >= suffix_length
                        && strcmp(path + path_length - suffix_length, cid850_suffix) == 0) {
                    cid850_lseek_seen += 1;
                    if (cid850_lseek_seen == cid850_lseek_ordinal) {
                        cid850_did_mutation_value = true;
                        strlcpy(held_name, cid850_held_name, sizeof(held_name));
                        should_mutation = true;
                    }
                }
            }
            pthread_mutex_unlock(&cid850_lock);
            if (should_mutation) {
                cid850_inside_interposer = true;
                char package_path[PATH_MAX];
                strlcpy(package_path, path, sizeof(package_path));
                char *last_slash = strrchr(package_path, '/');
                if (last_slash != NULL) {
                    *last_slash = '\0';
                    char *package_slash = strrchr(package_path, '/');
                    if (package_slash != NULL) {
                        const char *package_name = package_slash + 1;
                        *package_slash = '\0';
                        int policy_descriptor = open(
                            package_path,
                            O_RDONLY | O_DIRECTORY | O_CLOEXEC
                        );
                        if (policy_descriptor >= 0
                                && renameat(
                                    policy_descriptor,
                                    package_name,
                                    policy_descriptor,
                                    held_name
                                ) == 0) {
                            int held_descriptor = openat(
                                policy_descriptor,
                                held_name,
                                O_RDONLY | O_DIRECTORY | O_CLOEXEC
                            );
                            if (held_descriptor >= 0) {
                                (void)cid850_real_fclonefileat(
                                    held_descriptor,
                                    policy_descriptor,
                                    package_name,
                                    0
                                );
                                close(held_descriptor);
                            }
                        }
                        if (policy_descriptor >= 0) {
                            close(policy_descriptor);
                        }
                    }
                }
                cid850_inside_interposer = false;
            }
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return (off_t)syscall(SYS_lseek, descriptor, offset, whence);
#pragma clang diagnostic pop
}

static int cid850_ftruncate(int descriptor, off_t length) {
    if (!cid850_inside_interposer) {
        char path[PATH_MAX];
        char held_name[256] = {0};
        if (fcntl(descriptor, F_GETPATH, path) == 0
                && cid850_matches(path, CID850_MUTATION_FTRUNCATE, held_name)) {
            cid850_inside_interposer = true;
            char package_path[PATH_MAX];
            strlcpy(package_path, path, sizeof(package_path));
            char *last_slash = strrchr(package_path, '/');
            if (last_slash != NULL) {
                *last_slash = '\0';
                char *package_slash = strrchr(package_path, '/');
                if (package_slash != NULL) {
                    const char *package_name = package_slash + 1;
                    *package_slash = '\0';
                    int policy_descriptor = open(
                        package_path,
                        O_RDONLY | O_DIRECTORY | O_CLOEXEC
                    );
                    if (policy_descriptor >= 0
                            && renameat(
                                policy_descriptor,
                                package_name,
                                policy_descriptor,
                                held_name
                            ) == 0) {
                        int held_descriptor = openat(
                            policy_descriptor,
                            held_name,
                            O_RDONLY | O_DIRECTORY | O_CLOEXEC
                        );
                        if (held_descriptor >= 0) {
                            (void)cid850_real_fclonefileat(
                                held_descriptor,
                                policy_descriptor,
                                package_name,
                                0
                            );
                            close(held_descriptor);
                        }
                    }
                    if (policy_descriptor >= 0) {
                        close(policy_descriptor);
                    }
                }
            }
            cid850_inside_interposer = false;
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return (int)syscall(SYS_ftruncate, descriptor, length);
#pragma clang diagnostic pop
}

static int cid850_fsetxattr(
    int descriptor,
    const char *name,
    const void *value,
    size_t size,
    u_int32_t position,
    int options
) {
    bool is_legacy_restore_metadata = name != NULL
        && (strcmp(name, "com.cider.cid851.restore-journal-registration-v1") == 0
            || strcmp(name, "com.cider.cid851.restore-staging-intent-v1") == 0);
    bool is_canonical_restore_metadata = name != NULL
        && strcmp(name, "com.cider.cid851.restore-transaction-v2") == 0;
    bool is_restore_completion = !cid850_inside_interposer && name != NULL && value != NULL
        && ((strcmp(name, "com.cider.cid851.restore-journal-registration-v1") == 0
                && memmem(value, size, "\"completion\":{", 14) != NULL)
            || (is_canonical_restore_metadata
                && memmem(value, size, "\"phase\":\"cleaning\"", 18) != NULL));
    if (is_restore_completion
            && strcmp(name, "com.cider.cid851.restore-journal-registration-v1") == 0) {
        bool should_crash = false;
        pthread_mutex_lock(&cid850_lock);
        if (cid850_kind == CID851_MUTATION_RESTORE_CRASH_BEFORE_COMPLETION
                && cid850_post_swap_seen
                && memmem(value, size, "\"completion\":{", 14) != NULL) {
            cid850_did_mutation_value = true;
            should_crash = true;
        }
        pthread_mutex_unlock(&cid850_lock);
        if (should_crash) {
            _exit(88);
        }
    }
    int result = cid850_real_fsetxattr(
        descriptor,
        name,
        value,
        size,
        position,
        options
    );
    if (result == 0 && (is_legacy_restore_metadata || is_canonical_restore_metadata)) {
        pthread_mutex_lock(&cid850_lock);
        if (cid851_count_metadata) {
            if (is_legacy_restore_metadata) {
                cid851_legacy_metadata_writes += 1;
            }
            if (is_canonical_restore_metadata) {
                cid851_canonical_metadata_writes += 1;
            }
        }
        pthread_mutex_unlock(&cid850_lock);
        if (is_legacy_restore_metadata || is_canonical_restore_metadata) {
            cid851_crash_if_boundary(3);
        }
    }
    if (result == 0 && is_restore_completion) {
        enum cid850_mutation_kind cleanup_kind = CID850_MUTATION_NONE;
        char source_path[PATH_MAX] = {0};
        char held_path[PATH_MAX] = {0};
        pthread_mutex_lock(&cid850_lock);
        if (!cid850_did_mutation_value
                && (cid850_kind == CID851_MUTATION_MOVE_PATH_BEFORE_RESTORE_CLEANUP
                    || cid850_kind == CID851_MUTATION_REPLACE_PARENT_BEFORE_RESTORE_CLEANUP)) {
            cleanup_kind = cid850_kind;
            cid850_did_mutation_value = true;
            strlcpy(source_path, cid851_cleanup_source_path, sizeof(source_path));
            strlcpy(held_path, cid851_cleanup_held_path, sizeof(held_path));
        }
        pthread_mutex_unlock(&cid850_lock);
        if (cleanup_kind != CID850_MUTATION_NONE) {
            cid850_inside_interposer = true;
            if (rename(source_path, held_path) == 0
                    && cleanup_kind == CID851_MUTATION_REPLACE_PARENT_BEFORE_RESTORE_CLEANUP) {
                (void)mkdir(source_path, S_IRWXU);
            }
            cid850_inside_interposer = false;
        }
    }
    if (result != 0 || cid850_inside_interposer || name == NULL
            || strcmp(name, "com.cider.cid850.package-owner-v1") != 0) {
        return result;
    }

    bool should_pause = false;
    char ready_path[PATH_MAX] = {0};
    char release_path[PATH_MAX] = {0};
    pthread_mutex_lock(&cid850_lock);
    if (cid850_kind == CID850_MUTATION_STAGE_OWNERSHIP_PAUSE
            && !cid850_did_mutation_value) {
        cid850_did_mutation_value = true;
        strlcpy(ready_path, cid850_ownership_ready_path, sizeof(ready_path));
        strlcpy(release_path, cid850_ownership_release_path, sizeof(release_path));
        should_pause = true;
    }
    pthread_mutex_unlock(&cid850_lock);

    if (should_pause) {
        cid850_inside_interposer = true;
        cid850_write_probe_byte(ready_path, 'R');
        int release_descriptor = open(release_path, O_RDONLY | O_CLOEXEC);
        if (release_descriptor >= 0) {
            char byte = 0;
            (void)read(release_descriptor, &byte, 1);
            close(release_descriptor);
        }
        cid850_inside_interposer = false;
    }
    return result;
}

struct cid850_interpose_pair {
    const void *replacement;
    const void *replacee;
};

__attribute__((used))
static struct cid850_interpose_pair cid850_interposers[]
    __attribute__((section("__DATA,__interpose"))) = {
        { (const void *)cid850_mkdirat, (const void *)mkdirat },
        { (const void *)cid851_open, (const void *)open },
        { (const void *)cid851_openat, (const void *)openat },
        { (const void *)cid851_pread, (const void *)pread },
        { (const void *)cid850_fclonefileat, (const void *)fclonefileat },
        { (const void *)cid850_fchflags, (const void *)fchflags },
        { (const void *)cid850_renameatx_np, (const void *)renameatx_np },
        { (const void *)cid850_lseek, (const void *)lseek },
        { (const void *)cid850_ftruncate, (const void *)ftruncate },
        { (const void *)cid850_flock, (const void *)flock },
        { (const void *)cid850_fsync, (const void *)fsync },
        { (const void *)cid850_fsetxattr, (const void *)fsetxattr },
        { (const void *)cid850_unlinkat, (const void *)unlinkat },
        { (const void *)cid851_fremovexattr, (const void *)fremovexattr },
        { (const void *)cid851_sqlite3_open_v2, (const void *)sqlite3_open_v2 },
    };
