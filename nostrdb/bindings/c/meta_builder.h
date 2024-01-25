#ifndef META_BUILDER_H
#define META_BUILDER_H

/* Generated by flatcc 0.6.1 FlatBuffers schema compiler for C by dvide.com */

#ifndef META_READER_H
#include "meta_reader.h"
#endif
#ifndef FLATBUFFERS_COMMON_BUILDER_H
#include "flatbuffers_common_builder.h"
#endif
#include "flatcc/flatcc_prologue.h"
#ifndef flatbuffers_identifier
#define flatbuffers_identifier 0
#endif
#ifndef flatbuffers_extension
#define flatbuffers_extension "bin"
#endif

static const flatbuffers_voffset_t __NdbEventMeta_required[] = { 0 };
typedef flatbuffers_ref_t NdbEventMeta_ref_t;
static NdbEventMeta_ref_t NdbEventMeta_clone(flatbuffers_builder_t *B, NdbEventMeta_table_t t);
__flatbuffers_build_table(flatbuffers_, NdbEventMeta, 6)

#define __NdbEventMeta_formal_args ,\
  int32_t v0, int32_t v1, int32_t v2, int32_t v3, int32_t v4, int64_t v5
#define __NdbEventMeta_call_args ,\
  v0, v1, v2, v3, v4, v5
static inline NdbEventMeta_ref_t NdbEventMeta_create(flatbuffers_builder_t *B __NdbEventMeta_formal_args);
__flatbuffers_build_table_prolog(flatbuffers_, NdbEventMeta, NdbEventMeta_file_identifier, NdbEventMeta_type_identifier)

__flatbuffers_build_scalar_field(0, flatbuffers_, NdbEventMeta_received_at, flatbuffers_int32, int32_t, 4, 4, INT32_C(0), NdbEventMeta)
__flatbuffers_build_scalar_field(1, flatbuffers_, NdbEventMeta_reactions, flatbuffers_int32, int32_t, 4, 4, INT32_C(0), NdbEventMeta)
__flatbuffers_build_scalar_field(2, flatbuffers_, NdbEventMeta_quotes, flatbuffers_int32, int32_t, 4, 4, INT32_C(0), NdbEventMeta)
__flatbuffers_build_scalar_field(3, flatbuffers_, NdbEventMeta_reposts, flatbuffers_int32, int32_t, 4, 4, INT32_C(0), NdbEventMeta)
__flatbuffers_build_scalar_field(4, flatbuffers_, NdbEventMeta_zaps, flatbuffers_int32, int32_t, 4, 4, INT32_C(0), NdbEventMeta)
__flatbuffers_build_scalar_field(5, flatbuffers_, NdbEventMeta_zap_total, flatbuffers_int64, int64_t, 8, 8, INT64_C(0), NdbEventMeta)

static inline NdbEventMeta_ref_t NdbEventMeta_create(flatbuffers_builder_t *B __NdbEventMeta_formal_args)
{
    if (NdbEventMeta_start(B)
        || NdbEventMeta_zap_total_add(B, v5)
        || NdbEventMeta_received_at_add(B, v0)
        || NdbEventMeta_reactions_add(B, v1)
        || NdbEventMeta_quotes_add(B, v2)
        || NdbEventMeta_reposts_add(B, v3)
        || NdbEventMeta_zaps_add(B, v4)) {
        return 0;
    }
    return NdbEventMeta_end(B);
}

static NdbEventMeta_ref_t NdbEventMeta_clone(flatbuffers_builder_t *B, NdbEventMeta_table_t t)
{
    __flatbuffers_memoize_begin(B, t);
    if (NdbEventMeta_start(B)
        || NdbEventMeta_zap_total_pick(B, t)
        || NdbEventMeta_received_at_pick(B, t)
        || NdbEventMeta_reactions_pick(B, t)
        || NdbEventMeta_quotes_pick(B, t)
        || NdbEventMeta_reposts_pick(B, t)
        || NdbEventMeta_zaps_pick(B, t)) {
        return 0;
    }
    __flatbuffers_memoize_end(B, t, NdbEventMeta_end(B));
}

#include "flatcc/flatcc_epilogue.h"
#endif /* META_BUILDER_H */
