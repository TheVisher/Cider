#ifndef CID850_INTERPOSE_H
#define CID850_INTERPOSE_H

#include <stdbool.h>

void cid850_interpose_reset(void);
void cid850_interpose_replace_after_mkdirat(const char *suffix, const char *held_name);
void cid850_interpose_replace_after_fclonefileat(const char *suffix, const char *held_name);
void cid850_interpose_crash_after_fclonefileat(const char *suffix);
void cid850_interpose_replace_after_renameatx_np(const char *suffix, const char *held_name);
void cid850_interpose_replace_before_renameatx_np(const char *suffix, const char *held_name);
void cid850_interpose_crash_before_renameatx_np(const char *suffix);
void cid850_interpose_replace_before_lseek(
    const char *suffix,
    const char *held_name,
    int ordinal
);
void cid850_interpose_replace_before_ftruncate(const char *suffix, const char *held_name);
void cid850_interpose_create_sidecar_before_swap(
    const char *database_suffix,
    const char *sidecar_suffix
);
void cid850_interpose_create_sidecar_after_swap(
    const char *database_suffix,
    const char *sidecar_suffix
);
void cid850_interpose_fail_post_swap_parent_fsync(
    const char *database_suffix,
    int failure_count
);
void cid850_interpose_crash_after_restore_swap(const char *database_suffix);
void cid851_interpose_crash_before_restore_completion(const char *database_suffix);
void cid851_interpose_move_source_before_restore_cleanup(
    const char *source_path,
    const char *held_path
);
void cid851_interpose_replace_parent_before_restore_cleanup(
    const char *parent_path,
    const char *held_path
);
void cid850_interpose_fail_restore_reopen_after_swap(const char *database_suffix);
void cid850_interpose_fail_restore_integrity_after_swap(const char *database_suffix);
void cid850_interpose_fail_restore_record_removal_fsync(void);
void cid851_interpose_count_restore_authority(void);
int cid851_interpose_restore_authority_acquisitions(void);
int cid851_interpose_restore_authority_releases(void);
void cid851_interpose_count_restore_metadata(void);
int cid851_interpose_legacy_restore_metadata_writes(void);
int cid851_interpose_canonical_restore_metadata_writes(void);
void cid851_interpose_count_parent_reopens(const char *parent_path);
int cid851_interpose_parent_reopens_after_lock(void);
void cid851_install_sidecar_at_sqlite_open(
    const char *database_path,
    const char *expected_database_path,
    const char *sidecar_suffix
);
void cid851_reset_sqlite_open_sidecar(void);
int cid851_sqlite_open_callback_count(void);
void cid851_interpose_crash_restore_boundary(int boundary, int ordinal);
void cid851_interpose_crash_sqlite_open_for_path(const char *database_path);
int cid851_interpose_restore_boundary_seen(void);
void cid851_interpose_mutate_restore_member_before_rename(void);
void cid851_interpose_mutate_restore_member_before_unlink(void);
void cid851_interpose_mutate_restore_member_before_clone(void);
void cid851_interpose_occupy_cleanup_retention_destination(void);
void cid851_interpose_count_retained_restore_unlinks(void);
int cid851_interpose_retained_restore_unlink_attempts(void);
void cid851_interpose_reoccupy_cleanup_source_after_retention(void);
void cid851_interpose_reoccupy_before_completed_record_removal(void);
void cid851_interpose_qualified_receipt_member_race(
    const char *package_path,
    const char *member,
    const char *action
);
void cid851_interpose_mutate_held_descriptor_after_retention(int descriptor);
void cid850_interpose_fail_append_guard_restoration(void);
void cid850_interpose_configure_flock_probe(
    int role,
    const char *ready_path,
    const char *release_path,
    const char *result_path
);
void cid850_interpose_pause_after_stage_ownership(
    const char *ready_path,
    const char *release_path
);
void cid850_interpose_grow_staged_child_before_clone(void);
void cid850_interpose_replace_staged_child_before_clone(void);
void cid850_interpose_grow_published_child_after_clone(void);
void cid850_interpose_replace_published_child_after_clone(void);
bool cid850_interpose_did_mutation(void);

#endif
