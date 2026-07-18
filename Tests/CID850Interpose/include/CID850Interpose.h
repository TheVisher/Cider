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
bool cid850_interpose_did_attack(void);

#endif
