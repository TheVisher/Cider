#include "CID850Interpose.h"

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/clonefile.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/xattr.h>
#include <unistd.h>

enum cid850_attack_kind {
    CID850_ATTACK_NONE = 0,
    CID850_ATTACK_MKDIRAT,
    CID850_ATTACK_FCLONEFILEAT,
    CID850_ATTACK_FCLONEFILEAT_CRASH,
    CID850_ATTACK_FCHFLAGS_RESTORE,
    CID850_ATTACK_RENAMEATX,
    CID850_ATTACK_RENAMEATX_SOURCE,
    CID850_ATTACK_RENAMEATX_CRASH,
    CID850_ATTACK_RENAMEATX_CRASH_AFTER,
    CID868_ATTACK_RESTORE_STATE_CRASH,
    CID868_ATTACK_RESTORE_REOPEN_FAILURE,
    CID868_ATTACK_RESTORE_INTEGRITY_FAILURE,
    CID868_ATTACK_FINAL_SOURCE_MUTATION,
    CID868_ATTACK_COMMITTED_CLEANUP_FAILURE,
    CID868_ATTACK_PARENT_SWAP_SQLITE_OPEN,
    CID850_ATTACK_LSEEK,
    CID850_ATTACK_FTRUNCATE,
    CID850_ATTACK_SIDECAR_BEFORE_SWAP,
    CID850_ATTACK_SIDECAR_AFTER_SWAP,
    CID850_ATTACK_POST_SWAP_FSYNC,
    CID850_ATTACK_STAGE_OWNERSHIP_PAUSE,
    CID850_ATTACK_CLONE_SOURCE_GROW,
    CID850_ATTACK_CLONE_SOURCE_REPLACE,
    CID850_ATTACK_CLONE_DESTINATION_GROW,
    CID850_ATTACK_CLONE_DESTINATION_REPLACE,
};

static pthread_mutex_t cid850_lock = PTHREAD_MUTEX_INITIALIZER;
static enum cid850_attack_kind cid850_kind = CID850_ATTACK_NONE;
static char cid850_suffix[128];
static char cid850_held_name[256];
static bool cid850_did_attack_value = false;
static int cid850_lseek_ordinal = 0;
static int cid850_lseek_seen = 0;
static int cid868_restore_state_ordinal = 0;
static int cid868_restore_state_seen = 0;
static bool cid868_restore_state_after = false;
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
static bool cid868_committed_cleanup_armed = false;
static bool cid868_committed_cleanup_persistent = false;
static char cid850_ownership_ready_path[PATH_MAX];
static char cid850_ownership_release_path[PATH_MAX];
static char cid868_source_database_path[PATH_MAX];
static char cid868_database_path[PATH_MAX];
static char cid868_database_parent_path[PATH_MAX];
static char cid868_decoy_parent_path[PATH_MAX];

static void cid850_configure(
    enum cid850_attack_kind kind,
    const char *suffix,
    const char *held_name
);

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

static int cid850_real_unlinkat(int directory, const char *name, int flags) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return (int)syscall(SYS_unlinkat, directory, name, flags);
#pragma clang diagnostic pop
}

static int cid850_real_open(const char *path, int flags, mode_t mode) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return (int)syscall(SYS_open, path, flags, mode);
#pragma clang diagnostic pop
}

static int cid850_real_renameatx_np(
    int source_directory,
    const char *source_name,
    int destination_directory,
    const char *destination_name,
    unsigned int flags
) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return (int)syscall(
        SYS_renameatx_np,
        source_directory,
        source_name,
        destination_directory,
        destination_name,
        flags
    );
#pragma clang diagnostic pop
}

#pragma clang diagnostic pop

static bool cid850_matches(const char *name, enum cid850_attack_kind kind, char *held_name) {
    bool matches = false;
    pthread_mutex_lock(&cid850_lock);
    if (!cid850_did_attack_value && cid850_kind == kind && name != NULL) {
        size_t name_length = strlen(name);
        size_t suffix_length = strlen(cid850_suffix);
        if (name_length >= suffix_length
                && strcmp(name + name_length - suffix_length, cid850_suffix) == 0) {
            cid850_did_attack_value = true;
            strlcpy(held_name, cid850_held_name, 256);
            matches = true;
        }
    }
    pthread_mutex_unlock(&cid850_lock);
    return matches;
}

void cid850_interpose_reset(void) {
    pthread_mutex_lock(&cid850_lock);
    cid850_kind = CID850_ATTACK_NONE;
    cid850_suffix[0] = '\0';
    cid850_held_name[0] = '\0';
    cid850_did_attack_value = false;
    cid850_lseek_ordinal = 0;
    cid850_lseek_seen = 0;
    cid868_restore_state_ordinal = 0;
    cid868_restore_state_seen = 0;
    cid868_restore_state_after = false;
    cid850_flock_probe_role = 0;
    cid850_flock_exclusive_seen = 0;
    cid850_flock_probe_reported = false;
    cid850_ready_path[0] = '\0';
    cid850_release_path[0] = '\0';
    cid850_result_path[0] = '\0';
    cid850_fsync_failures_remaining = 0;
    cid850_post_swap_fsync_armed = false;
    cid850_post_swap_seen = false;
    cid868_committed_cleanup_armed = false;
    cid868_committed_cleanup_persistent = false;
    cid850_ownership_ready_path[0] = '\0';
    cid850_ownership_release_path[0] = '\0';
    cid868_source_database_path[0] = '\0';
    cid868_database_path[0] = '\0';
    cid868_database_parent_path[0] = '\0';
    cid868_decoy_parent_path[0] = '\0';
    pthread_mutex_unlock(&cid850_lock);
}

void cid850_interpose_pause_after_stage_ownership(
    const char *ready_path,
    const char *release_path
) {
    pthread_mutex_lock(&cid850_lock);
    cid850_kind = CID850_ATTACK_STAGE_OWNERSHIP_PAUSE;
    cid850_did_attack_value = false;
    strlcpy(cid850_ownership_ready_path, ready_path, sizeof(cid850_ownership_ready_path));
    strlcpy(cid850_ownership_release_path, release_path, sizeof(cid850_ownership_release_path));
    pthread_mutex_unlock(&cid850_lock);
}

void cid850_interpose_grow_staged_child_before_clone(void) {
    cid850_configure(CID850_ATTACK_CLONE_SOURCE_GROW, ".ciderbackup", "");
}

void cid850_interpose_replace_staged_child_before_clone(void) {
    cid850_configure(CID850_ATTACK_CLONE_SOURCE_REPLACE, ".ciderbackup", "");
}

void cid850_interpose_grow_published_child_after_clone(void) {
    cid850_configure(CID850_ATTACK_CLONE_DESTINATION_GROW, ".ciderbackup", "");
}

void cid850_interpose_replace_published_child_after_clone(void) {
    cid850_configure(CID850_ATTACK_CLONE_DESTINATION_REPLACE, ".ciderbackup", "");
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
    if (cid850_inside_interposer || (operation & LOCK_UN) != 0) {
        return cid850_real_flock(descriptor, operation);
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
        return cid850_real_flock(descriptor, operation);
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
    enum cid850_attack_kind kind,
    const char *suffix,
    const char *held_name
) {
    pthread_mutex_lock(&cid850_lock);
    cid850_kind = kind;
    strlcpy(cid850_suffix, suffix, sizeof(cid850_suffix));
    strlcpy(cid850_held_name, held_name, sizeof(cid850_held_name));
    cid850_did_attack_value = false;
    pthread_mutex_unlock(&cid850_lock);
}

void cid850_interpose_replace_after_mkdirat(const char *suffix, const char *held_name) {
    cid850_configure(CID850_ATTACK_MKDIRAT, suffix, held_name);
}

void cid850_interpose_replace_after_fclonefileat(const char *suffix, const char *held_name) {
    cid850_configure(CID850_ATTACK_FCLONEFILEAT, suffix, held_name);
}

void cid850_interpose_crash_after_fclonefileat(const char *suffix) {
    cid850_configure(CID850_ATTACK_FCLONEFILEAT_CRASH, suffix, "");
}

void cid850_interpose_fail_append_guard_restoration(void) {
    cid850_configure(CID850_ATTACK_FCHFLAGS_RESTORE, "", "");
}

void cid850_interpose_replace_after_renameatx_np(const char *suffix, const char *held_name) {
    cid850_configure(CID850_ATTACK_RENAMEATX, suffix, held_name);
}

void cid850_interpose_replace_before_renameatx_np(const char *suffix, const char *held_name) {
    cid850_configure(CID850_ATTACK_RENAMEATX_SOURCE, suffix, held_name);
}

void cid850_interpose_crash_before_renameatx_np(const char *suffix) {
    cid850_configure(CID850_ATTACK_RENAMEATX_CRASH, suffix, "");
}

void cid850_interpose_crash_after_renameatx_np(const char *suffix) {
    cid850_configure(CID850_ATTACK_RENAMEATX_CRASH_AFTER, suffix, "");
}

void cid868_interpose_crash_restore_state(int ordinal, bool after_write) {
    cid850_configure(CID868_ATTACK_RESTORE_STATE_CRASH, "", "");
    pthread_mutex_lock(&cid850_lock);
    cid868_restore_state_ordinal = ordinal;
    cid868_restore_state_seen = 0;
    cid868_restore_state_after = after_write;
    pthread_mutex_unlock(&cid850_lock);
}

void cid868_interpose_fail_restore_reopen(void) {
    cid850_configure(CID868_ATTACK_RESTORE_REOPEN_FAILURE, "", "");
}

void cid868_interpose_fail_restore_integrity(void) {
    cid850_configure(CID868_ATTACK_RESTORE_INTEGRITY_FAILURE, "", "");
}

void cid868_interpose_mutate_source_after_reopened(const char *source_database_path) {
    cid850_configure(CID868_ATTACK_FINAL_SOURCE_MUTATION, "", "");
    pthread_mutex_lock(&cid850_lock);
    strlcpy(cid868_source_database_path, source_database_path, sizeof(cid868_source_database_path));
    pthread_mutex_unlock(&cid850_lock);
}

void cid868_interpose_fail_committed_cleanup_once(void) {
    cid850_configure(CID868_ATTACK_COMMITTED_CLEANUP_FAILURE, "", "");
}

void cid868_interpose_fail_committed_cleanup_persistently(void) {
    cid850_configure(CID868_ATTACK_COMMITTED_CLEANUP_FAILURE, "", "");
    pthread_mutex_lock(&cid850_lock);
    cid868_committed_cleanup_persistent = true;
    pthread_mutex_unlock(&cid850_lock);
}

void cid868_interpose_swap_parent_during_sqlite_open(
    const char *database_path,
    const char *decoy_parent_path
) {
    cid850_configure(CID868_ATTACK_PARENT_SWAP_SQLITE_OPEN, "", "");
    pthread_mutex_lock(&cid850_lock);
    strlcpy(cid868_database_path, database_path, sizeof(cid868_database_path));
    strlcpy(cid868_database_parent_path, database_path, sizeof(cid868_database_parent_path));
    char *separator = strrchr(cid868_database_parent_path, '/');
    if (separator != NULL) {
        *separator = '\0';
    }
    strlcpy(cid868_decoy_parent_path, decoy_parent_path, sizeof(cid868_decoy_parent_path));
    pthread_mutex_unlock(&cid850_lock);
}

void cid850_interpose_replace_before_lseek(
    const char *suffix,
    const char *held_name,
    int ordinal
) {
    cid850_configure(CID850_ATTACK_LSEEK, suffix, held_name);
    pthread_mutex_lock(&cid850_lock);
    cid850_lseek_ordinal = ordinal;
    cid850_lseek_seen = 0;
    pthread_mutex_unlock(&cid850_lock);
}

void cid850_interpose_replace_before_ftruncate(const char *suffix, const char *held_name) {
    cid850_configure(CID850_ATTACK_FTRUNCATE, suffix, held_name);
}

void cid850_interpose_create_sidecar_before_swap(
    const char *database_suffix,
    const char *sidecar_suffix
) {
    cid850_configure(CID850_ATTACK_SIDECAR_BEFORE_SWAP, database_suffix, sidecar_suffix);
}

void cid850_interpose_create_sidecar_after_swap(
    const char *database_suffix,
    const char *sidecar_suffix
) {
    cid850_configure(CID850_ATTACK_SIDECAR_AFTER_SWAP, database_suffix, sidecar_suffix);
}

void cid850_interpose_fail_post_swap_parent_fsync(
    const char *database_suffix,
    int failure_count
) {
    cid850_configure(CID850_ATTACK_POST_SWAP_FSYNC, database_suffix, "");
    pthread_mutex_lock(&cid850_lock);
    cid850_fsync_failures_remaining = failure_count;
    cid850_post_swap_fsync_armed = false;
    cid850_post_swap_seen = false;
    pthread_mutex_unlock(&cid850_lock);
}

bool cid850_interpose_did_attack(void) {
    pthread_mutex_lock(&cid850_lock);
    bool value = cid850_did_attack_value;
    pthread_mutex_unlock(&cid850_lock);
    return value;
}

static int cid850_mkdirat(int directory, const char *name, mode_t mode) {
    int result = cid850_real_mkdirat(directory, name, mode);
    int saved_errno = errno;
    if (result == 0 && !cid850_inside_interposer) {
        char held_name[256];
        if (cid850_matches(name, CID850_ATTACK_MKDIRAT, held_name)) {
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

static bool cid850_take_clone_child_attack(
    const char *destination_name,
    bool before_clone,
    bool *replace
) {
    bool attack = false;
    pthread_mutex_lock(&cid850_lock);
    enum cid850_attack_kind grow_kind = before_clone
        ? CID850_ATTACK_CLONE_SOURCE_GROW
        : CID850_ATTACK_CLONE_DESTINATION_GROW;
    enum cid850_attack_kind replace_kind = before_clone
        ? CID850_ATTACK_CLONE_SOURCE_REPLACE
        : CID850_ATTACK_CLONE_DESTINATION_REPLACE;
    if (!cid850_did_attack_value
            && (cid850_kind == grow_kind || cid850_kind == replace_kind)
            && destination_name != NULL) {
        size_t name_length = strlen(destination_name);
        size_t suffix_length = strlen(cid850_suffix);
        if (name_length >= suffix_length
                && strcmp(destination_name + name_length - suffix_length, cid850_suffix) == 0) {
            *replace = cid850_kind == replace_kind;
            cid850_did_attack_value = true;
            attack = true;
        }
    }
    pthread_mutex_unlock(&cid850_lock);
    return attack;
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
    bool replace_source = false;
    if (!cid850_inside_interposer
            && cid850_take_clone_child_attack(destination_name, true, &replace_source)) {
        cid850_inside_interposer = true;
        cid850_mutate_cloned_package_child(source, replace_source);
        cid850_inside_interposer = false;
    }
    int result = cid850_real_fclonefileat(source, destination_directory, destination_name, flags);
    int saved_errno = errno;
    if (result == 0 && !cid850_inside_interposer) {
        bool replace_destination = false;
        if (cid850_take_clone_child_attack(destination_name, false, &replace_destination)) {
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
        if (cid850_matches(destination_name, CID850_ATTACK_FCLONEFILEAT_CRASH, unused_name)) {
            _exit(88);
        }
        char held_name[256];
        if (cid850_matches(destination_name, CID850_ATTACK_FCLONEFILEAT, held_name)) {
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
    }
    errno = saved_errno;
    return result;
}

static int cid850_fsync(int descriptor) {
    bool should_fail = false;
    pthread_mutex_lock(&cid850_lock);
    if (!cid850_inside_interposer
            && cid850_kind == CID850_ATTACK_POST_SWAP_FSYNC
            && cid850_post_swap_fsync_armed
            && cid850_fsync_failures_remaining > 0) {
        cid850_fsync_failures_remaining -= 1;
        cid850_did_attack_value = true;
        should_fail = true;
    }
    pthread_mutex_unlock(&cid850_lock);
    if (should_fail) {
        errno = EIO;
        return -1;
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return (int)syscall(SYS_fsync, descriptor);
#pragma clang diagnostic pop
}

static int cid850_fchflags(int descriptor, unsigned int flags) {
    pthread_mutex_lock(&cid850_lock);
    bool should_fail = cid850_kind == CID850_ATTACK_FCHFLAGS_RESTORE
        && (flags & UF_APPEND) == 0;
    if (should_fail) {
        cid850_did_attack_value = true;
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
    if (!cid850_inside_interposer) {
        char sidecar_suffix[256];
        if (cid850_matches(destination_name, CID850_ATTACK_SIDECAR_BEFORE_SWAP, sidecar_suffix)) {
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
        if (cid850_matches(source_name, CID850_ATTACK_RENAMEATX_CRASH, unused_name)) {
            _exit(86);
        }
        char held_name[256];
        if (cid850_matches(source_name, CID850_ATTACK_RENAMEATX_SOURCE, held_name)) {
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
    if (result == 0 && !cid850_inside_interposer) {
        char unused_name[256];
        if (cid850_matches(source_name, CID850_ATTACK_RENAMEATX_CRASH_AFTER, unused_name)) {
            _exit(87);
        }
    }
    if (result == 0 && !cid850_inside_interposer && (flags & RENAME_SWAP) != 0) {
        pthread_mutex_lock(&cid850_lock);
        if (cid850_kind == CID868_ATTACK_RESTORE_REOPEN_FAILURE
                || cid850_kind == CID868_ATTACK_RESTORE_INTEGRITY_FAILURE) {
            cid850_did_attack_value = true;
            cid850_inside_interposer = true;
            int live = openat(
                destination_directory,
                destination_name,
                O_RDWR | O_NOFOLLOW | O_CLOEXEC
            );
            if (live >= 0) {
                if (cid850_kind == CID868_ATTACK_RESTORE_REOPEN_FAILURE) {
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
        if (cid850_kind == CID850_ATTACK_POST_SWAP_FSYNC
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
    if (result == 0 && !cid850_inside_interposer) {
        char sidecar_suffix[256];
        if (cid850_matches(destination_name, CID850_ATTACK_SIDECAR_AFTER_SWAP, sidecar_suffix)) {
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
        if (cid850_matches(destination_name, CID850_ATTACK_RENAMEATX, held_name)) {
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
            bool should_attack = false;
            pthread_mutex_lock(&cid850_lock);
            if (!cid850_did_attack_value && cid850_kind == CID850_ATTACK_LSEEK) {
                size_t path_length = strlen(path);
                size_t suffix_length = strlen(cid850_suffix);
                if (path_length >= suffix_length
                        && strcmp(path + path_length - suffix_length, cid850_suffix) == 0) {
                    cid850_lseek_seen += 1;
                    if (cid850_lseek_seen == cid850_lseek_ordinal) {
                        cid850_did_attack_value = true;
                        strlcpy(held_name, cid850_held_name, sizeof(held_name));
                        should_attack = true;
                    }
                }
            }
            pthread_mutex_unlock(&cid850_lock);
            if (should_attack) {
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
                && cid850_matches(path, CID850_ATTACK_FTRUNCATE, held_name)) {
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
    bool crash_before = false;
    bool crash_after = false;
    if (!cid850_inside_interposer && name != NULL
            && strcmp(name, "com.cider.cid868.restore-transaction-v1") == 0) {
        pthread_mutex_lock(&cid850_lock);
        if (cid850_kind == CID868_ATTACK_RESTORE_STATE_CRASH) {
            cid868_restore_state_seen += 1;
            if (cid868_restore_state_seen == cid868_restore_state_ordinal) {
                cid850_did_attack_value = true;
                crash_before = !cid868_restore_state_after;
                crash_after = cid868_restore_state_after;
            }
        }
        pthread_mutex_unlock(&cid850_lock);
    }
    if (crash_before) {
        _exit(91);
    }
    int result = cid850_real_fsetxattr(
        descriptor,
        name,
        value,
        size,
        position,
        options
    );
    if (result == 0 && crash_after) {
        _exit(92);
    }
    if (result == 0 && !cid850_inside_interposer && name != NULL
            && strcmp(name, "com.cider.cid868.restore-transaction-v1") == 0) {
        bool mutate_source = false;
        pthread_mutex_lock(&cid850_lock);
        if (cid850_kind == CID868_ATTACK_FINAL_SOURCE_MUTATION
                && !cid850_did_attack_value
                && memmem(
                    value,
                    size,
                    "\"phase\":\"reopened\"",
                    strlen("\"phase\":\"reopened\"")
                ) != NULL) {
            mutate_source = true;
        }
        if (cid850_kind == CID868_ATTACK_COMMITTED_CLEANUP_FAILURE
                && !cid850_did_attack_value
                && memmem(
                    value,
                    size,
                    "\"phase\":\"committed\"",
                    strlen("\"phase\":\"committed\"")
                ) != NULL) {
            cid868_committed_cleanup_armed = true;
        }
        pthread_mutex_unlock(&cid850_lock);
        if (mutate_source) {
            cid850_inside_interposer = true;
            int source = open(
                cid868_source_database_path,
                O_RDWR | O_NOFOLLOW | O_CLOEXEC
            );
            if (source >= 0) {
                struct stat metadata;
                const char marker[] = "cid868-final-source-mutation";
                if (fstat(source, &metadata) == 0
                        && pwrite(
                            source,
                            marker,
                            sizeof(marker) - 1,
                            metadata.st_size
                        ) == sizeof(marker) - 1
                        && fsync(source) == 0) {
                    pthread_mutex_lock(&cid850_lock);
                    cid850_did_attack_value = true;
                    pthread_mutex_unlock(&cid850_lock);
                }
                close(source);
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
    if (cid850_kind == CID850_ATTACK_STAGE_OWNERSHIP_PAUSE
            && !cid850_did_attack_value) {
        cid850_did_attack_value = true;
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

static int cid850_unlinkat(int directory, const char *name, int flags) {
    bool should_fail = false;
    pthread_mutex_lock(&cid850_lock);
    if (!cid850_inside_interposer
            && cid850_kind == CID868_ATTACK_COMMITTED_CLEANUP_FAILURE
            && cid868_committed_cleanup_armed
            && (!cid850_did_attack_value || cid868_committed_cleanup_persistent)) {
        cid850_did_attack_value = true;
        if (!cid868_committed_cleanup_persistent) {
            cid868_committed_cleanup_armed = false;
        }
        should_fail = true;
    }
    pthread_mutex_unlock(&cid850_lock);
    if (should_fail) {
        errno = EIO;
        return -1;
    }
    return cid850_real_unlinkat(directory, name, flags);
}

static int cid850_open(const char *path, int flags, ...) {
    mode_t mode = 0;
    if ((flags & O_CREAT) != 0) {
        va_list arguments;
        va_start(arguments, flags);
        mode = (mode_t)va_arg(arguments, int);
        va_end(arguments);
    }
    bool should_swap = false;
    char parent_path[PATH_MAX] = {0};
    char decoy_path[PATH_MAX] = {0};
    pthread_mutex_lock(&cid850_lock);
    if (!cid850_inside_interposer
            && !cid850_did_attack_value
            && cid850_kind == CID868_ATTACK_PARENT_SWAP_SQLITE_OPEN
            && path != NULL
            && strcmp(path, cid868_database_path) == 0) {
        strlcpy(parent_path, cid868_database_parent_path, sizeof(parent_path));
        strlcpy(decoy_path, cid868_decoy_parent_path, sizeof(decoy_path));
        should_swap = true;
    }
    pthread_mutex_unlock(&cid850_lock);

    if (!should_swap) {
        return cid850_real_open(path, flags, mode);
    }

    cid850_inside_interposer = true;
    bool swapped = cid850_real_renameatx_np(
        AT_FDCWD,
        parent_path,
        AT_FDCWD,
        decoy_path,
        RENAME_SWAP
    ) == 0;
    if (swapped) {
        pthread_mutex_lock(&cid850_lock);
        cid850_did_attack_value = true;
        pthread_mutex_unlock(&cid850_lock);
    }
    int result = cid850_real_open(path, flags, mode);
    if (swapped) {
        (void)cid850_real_renameatx_np(
            AT_FDCWD,
            parent_path,
            AT_FDCWD,
            decoy_path,
            RENAME_SWAP
        );
    }
    cid850_inside_interposer = false;
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
        { (const void *)cid850_fclonefileat, (const void *)fclonefileat },
        { (const void *)cid850_fchflags, (const void *)fchflags },
        { (const void *)cid850_renameatx_np, (const void *)renameatx_np },
        { (const void *)cid850_lseek, (const void *)lseek },
        { (const void *)cid850_ftruncate, (const void *)ftruncate },
        { (const void *)cid850_flock, (const void *)flock },
        { (const void *)cid850_fsync, (const void *)fsync },
        { (const void *)cid850_fsetxattr, (const void *)fsetxattr },
        { (const void *)cid850_unlinkat, (const void *)unlinkat },
        { (const void *)cid850_open, (const void *)open },
    };
