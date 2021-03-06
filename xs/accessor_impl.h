#ifndef __INHERITED_XS_IMPL_H_
#define __INHERITED_XS_IMPL_H_

/*
    av_extend() always gives us at least 4 elements, so don't bother with
    saving memory for need_cb = false version until this struct grows larger
*/

struct shared_keys {
    union {
        SV* hash_key;
        SV* storage;
    };
    SV* pkg_key;
    SV* read_cb;
    SV* write_cb;
};

enum AccessorTypes {
    Inherited,
    InheritedCb,
    PrivateClass
};

/*
    These macroses have the following constraints:
        - SP is at the start of the args list
        - afterwards SP may become invalid, so don't touch it
        - PL_stack_sp is updated when needed

    The latter may be not that obvious, but it's a result of a callback doing stack work for us.
    But all non-essential updates are not performed after callbacks.
*/

#define CALL_READ_CB(result, cb)        \
    if ((type == InheritedCb) && cb) {  \
        ENTER;                          \
        PUSHMARK(SP);                   \
        *(SP+1) = result;               \
        call_sv(cb, G_SCALAR);          \
        LEAVE;                          \
    } else {                            \
        *(SP+1) = result;               \
    }                                   \

#define CALL_WRITE_CB(slot, cb, need_alloc) \
    if ((type == InheritedCb) && cb) {      \
        ENTER;                              \
        PUSHMARK(SP);                       \
        call_sv(cb, G_SCALAR);              \
        SPAGAIN;                            \
        LEAVE;                              \
        if (need_alloc) slot = newSV(0);    \
        sv_setsv(slot, *SP);                \
        *SP = slot;                         \
    } else {                                \
        if (need_alloc) slot = newSV(0);    \
        sv_setsv(slot, *(SP+2));            \
        PUSHs(slot);                        \
        PUTBACK;                            \
    }                                       \

#define OP_UNSTEAL(name) STMT_START {       \
        PL_op->op_ppaddr = PL_ppaddr[name]; \
        return PL_ppaddr[name](aTHX);       \
    } STMT_END                              \

template <AccessorTypes type>
inline void
CAIXS_accessor(pTHX_ SV** SP, CV* cv, HV* stash);

template <AccessorTypes type> static
XSPROTO(CAIXS_entersub_wrapper) {
    dSP;

    CAIXS_accessor<type>(aTHX_ SP, cv, NULL);

    return;
}

#ifdef OPTIMIZE_OPMETHOD

template <AccessorTypes type, int optype> static
OP *
CAIXS_opmethod_wrapper(pTHX) {
    dSP;

    SV* self = PL_stack_base + TOPMARK == SP ? (SV*)NULL : *(PL_stack_base + TOPMARK + 1);
    HV* stash = NULL;

    /*
        this block isn't required for the 'goto gotcv' case, but skipping it
        (or swapping those blocks) will make unstealing inside 'goto gotcv' block impossible,
        thus requiring additional check in the fast case, and subref is a failure anyway most of the times
    */
#ifndef GV_CACHE_ONLY
    if (LIKELY(self != NULL)) {
        SvGETMAGIC(self);
#else
    if (LIKELY(self && !SvGMAGICAL(self))) {
        /* SvIsCOW_shared_hash is incompatible with SvGMAGICAL, so skip it completely */
        if (SvIsCOW_shared_hash(self)) {
            stash = gv_stashsv(self, GV_CACHE_ONLY);
        } else
#endif
        if (SvROK(self)) {
            SV* ob = SvRV(self);
            if (SvOBJECT(ob)) stash = SvSTASH(ob);

        } else if (SvPOK(self)) {
            const char* packname = SvPVX_const(self);
            const STRLEN packlen = SvCUR(self);
            const int is_utf8 = SvUTF8(self);

#ifndef GV_CACHE_ONLY
            const HE* const he = (const HE *)hv_common(PL_stashcache, NULL, packname, packlen, is_utf8, 0, NULL, 0);
            if (he) stash = INT2PTR(HV*, SvIV(HeVAL(he)));
            else
#endif
            stash = gv_stashpvn(packname, packlen, is_utf8);
        }
    }

    SV* meth;
    CV* cv = NULL;
    U32 hash;

    if (optype == OP_METHOD) {
        meth = TOPs;
        if (SvROK(meth)) {
            SV* const rmeth = SvRV(meth);
            if (SvTYPE(rmeth) == SVt_PVCV) {
                cv = (CV*)rmeth;
                goto gotcv; /* we don't care about the 'stash' var here */
            }
        }

        hash = 0;

    } else if (optype == OP_METHOD_NAMED) {
        meth = cSVOPx_sv(PL_op);

#ifndef GV_CACHE_ONLY
        hash = SvSHARED_HASH(meth);
#else
        hash = 0;
#endif
    }

    /* SvTYPE check appeared only since 5.22, but execute it for all perls nevertheless */
    if (UNLIKELY(!stash || SvTYPE(stash) != SVt_PVHV)) {
        OP_UNSTEAL(optype);
    }

    HE* he; /* to allow 'goto' to jump over this */
    if ((he = hv_fetch_ent(stash, meth, 0, hash))) {
        GV* gv = (GV*)(HeVAL(he));
        if (isGV(gv) && GvCV(gv) && (!GvCVGEN(gv) || GvCVGEN(gv) == (PL_sub_generation + HvMROMETA(stash)->cache_gen))) {
            cv = GvCV(gv);
        }
    }

    if (UNLIKELY(!cv)) {
        GV* gv = gv_fetchmethod_sv_flags(stash, meth, GV_AUTOLOAD|GV_CROAK);
        assert(gv);

        cv = isGV(gv) ? GvCV(gv) : (CV*)gv;
        assert(cv);
    }

gotcv:
    if (LIKELY(CvXSUB(cv) == (XSUBADDR_t)&CAIXS_entersub_wrapper<type>)) {
        assert(CvISXSUB(cv));

        if (optype == OP_METHOD) {--SP; PUTBACK; }

        CAIXS_accessor<type>(aTHX_ SP, cv, stash);

        return PL_op->op_next->op_next;

    } else {
        /*
            we could also lift off CAIXS_entersub optimization here, but that's a one-time action,
            so let it fail on it's own
        */
        OP_UNSTEAL(optype);
    }
}

#endif /* OPTIMIZE_OPMETHOD */

template <AccessorTypes type> static
OP *
CAIXS_entersub(pTHX) {
    dSP;

    CV* sv = (CV*)TOPs;

    if (LIKELY(sv != NULL)) {
        if (UNLIKELY(SvTYPE(sv) != SVt_PVCV)) {
            /* can('acc')->() or (\&acc)->()  */

            if (LIKELY(SvROK(sv))) sv = (CV*)SvRV(sv);
            if (UNLIKELY(SvTYPE(sv) != SVt_PVCV)) OP_UNSTEAL(OP_ENTERSUB);
        }

        /* some older gcc's can't deduce correct function - have to add explicit cast  */
        if (LIKELY(CvXSUB(sv) == (XSUBADDR_t)&CAIXS_entersub_wrapper<type>)) {
            /*
                Assert against future XPVCV layout change - as for now, xcv_xsub shares space with xcv_root
                which are both pointers, so address check is enough, and there's no need to look into op_flags for CvISXSUB.
            */
            assert(CvISXSUB(sv));

            POPs; PUTBACK;
            CAIXS_accessor<type>(aTHX_ SP, sv, NULL);

            return NORMAL;
        }

    }

    OP_UNSTEAL(OP_ENTERSUB);
}

template <AccessorTypes type> inline
void
CAIXS_install_entersub(pTHX) {
    /*
        Check whether we can replace opcode executor with our own variant. Unfortunatelly, this guards
        only against local changes, not when someone steals PL_ppaddr[OP_ENTERSUB] globally.
        Sorry, Devel::NYTProf.
    */

    OP* op = PL_op;

    if ((op->op_spare & 1) != 1 && op->op_ppaddr == PL_ppaddr[OP_ENTERSUB] && optimize_entersub) {
        op->op_spare |= 1;
        op->op_ppaddr = &CAIXS_entersub<type>;

#ifdef OPTIMIZE_OPMETHOD
        OP* methop = cUNOPx(op)->op_first;
        if (LIKELY(methop != NULL)) {   /* such op can be created by call_sv(G_METHOD_NAMED) */
            while (methop->op_sibling) { methop = methop->op_sibling; }

            if (methop->op_next == op) {
                if (methop->op_type == OP_METHOD_NAMED && methop->op_ppaddr == PL_ppaddr[OP_METHOD_NAMED]) {
                    methop->op_ppaddr = &CAIXS_opmethod_wrapper<type, OP_METHOD_NAMED>;
                } else if (methop->op_type == OP_METHOD && methop->op_ppaddr == PL_ppaddr[OP_METHOD]) {
                    methop->op_ppaddr = &CAIXS_opmethod_wrapper<type, OP_METHOD>;
                }
            }
        }
#endif /* OPTIMIZE_OPMETHOD */
    }
}

inline shared_keys*
CAIXS_find_keys(CV* cv) {
    shared_keys* keys;

#ifndef MULTIPLICITY
    /* Blessed are ye and get a fastpath */
    keys = (shared_keys*)(CvXSUBANY(cv).any_ptr);
    if (!keys) croak("Can't find hash key information");
#else
    /*
        We can't look into CvXSUBANY under threads, as it could have been written in the parent thread
        and had gone away at any time without prior notice. So, instead, we have to scan our magical
        refcnt storage - there's always a proper thread-local SV*, cloned for us by perl itself.
    */
    MAGIC* mg = mg_findext((SV*)cv, PERL_MAGIC_ext, &sv_payload_marker);
    if (!mg) croak("Can't find hash key information");

    keys = (shared_keys*)AvARRAY((AV*)(mg->mg_obj));
#endif

    return keys;
}

template <> inline
void
CAIXS_accessor<PrivateClass>(pTHX_ SV** SP, CV* cv, HV* stash) {
    dAXMARK; dITEMS;

    if (!items) croak("Usage: $obj->accessor or __PACKAGE__->accessor");

    CAIXS_install_entersub<PrivateClass>(aTHX);
    shared_keys* keys = (shared_keys*)CAIXS_find_keys(cv);

    if (items > 1) {
        SP -= items; /* no need in the 'items == 1' case */

        sv_setsv(keys->storage, *(SP+2));
        PUSHs(keys->storage);
        PUTBACK;
        return;

    } else {
        *SP = keys->storage;
        return;
    }
}

template <AccessorTypes type> inline
void
CAIXS_accessor(pTHX_ SV** SP, CV* cv, HV* stash) {
    dAXMARK; dITEMS;
    SP -= items;

    if (UNLIKELY(!items)) croak("Usage: $obj->accessor or __PACKAGE__->accessor");

    CAIXS_install_entersub<type>(aTHX);
    shared_keys* keys = CAIXS_find_keys(cv);

    SV* self = *(SP+1);
    if (SvROK(self)) {
        HV* obj = (HV*)SvRV(self);
        if (SvTYPE((SV*)obj) != SVt_PVHV) {
            croak("Inherited accessors work only with hash-based objects");
        }

        if (items > 1) {
            SV* new_value;
            CALL_WRITE_CB(new_value, keys->write_cb, 1);
            if (!hv_store_ent(obj, keys->hash_key, new_value, 0)) {
                SvREFCNT_dec_NN(new_value);
                croak("Can't store new hash value");
            }
            return;
                    
        } else {
            HE* hent = hv_fetch_ent(obj, keys->hash_key, 0, 0);
            if (hent) {
                CALL_READ_CB(HeVAL(hent), keys->read_cb);
                return;
            }
        }
    }

    /* Couldn't find value in object, so initiate a package lookup. */

#ifdef OPTIMIZE_OPMETHOD
    if (!stash) {
#endif
    if (SvROK(self)) {
        stash = SvSTASH(SvRV(self));

    } else {
        GV* acc_gv = CvGV(cv);
        if (!acc_gv) croak("Can't have package accessor in anon sub");
        stash = GvSTASH(acc_gv);

        const char* stash_name = HvNAME(stash);
        const char* self_name = SvPV_nolen(self);
        if (strcmp(stash_name, self_name) != 0) {
            stash = gv_stashsv(self, GV_ADD);
            if (!stash) croak("Couldn't get required stash");
        }
    }
#ifdef OPTIMIZE_OPMETHOD
    }
#endif

    HE* hent;
    if (items > 1) {
        hent = hv_fetch_ent(stash, keys->pkg_key, 0, 0);
        GV* glob = hent ? (GV*)HeVAL(hent) : NULL;
        if (!glob || !isGV(glob) || SvFAKE(glob)) {
            if (!glob) glob = (GV*)newSV(0);

            gv_init_sv(glob, stash, keys->pkg_key, 0);

            if (hent) {
                /* there was just a stub instead of a full glob */
                SvREFCNT_inc_simple_void_NN((SV*)glob);
                SvREFCNT_dec_NN(HeVAL(hent));
                HeVAL(hent) = (SV*)glob;

            } else {
                if (!hv_store_ent(stash, keys->pkg_key, (SV*)glob, 0)) {
                    SvREFCNT_dec_NN(glob);
                    croak("Couldn't add a glob to package");
                }
            }
        }

        SV* new_value = GvSVn(glob);
        CALL_WRITE_CB(new_value, keys->write_cb, 0);

        return;
    }
    
    #define TRY_FETCH_PKG_VALUE(stash, keys, hent)                      \
    if (stash && (hent = hv_fetch_ent(stash, keys->pkg_key, 0, 0))) {   \
        SV* sv = GvSV(HeVAL(hent));                                     \
        if (sv && SvOK(sv)) {                                           \
            CALL_READ_CB(sv, keys->read_cb);                            \
            return;                                                     \
        }                                                               \
    }

    TRY_FETCH_PKG_VALUE(stash, keys, hent);

    AV* supers = mro_get_linear_isa(stash);
    /*
        First entry in the 'mro_get_linear_isa' list is the 'stash' itself.
        It's already been tested, so ajust both counter and iterator to skip over it.
    */
    SSize_t fill     = AvFILLp(supers);
    SV** supers_list = AvARRAY(supers);

    SV* elem;
    while (--fill >= 0) {
        elem = *(++supers_list);

        if (elem) {
            stash = gv_stashsv(elem, 0);
            TRY_FETCH_PKG_VALUE(stash, keys, hent);
        }
    }

    /* XSRETURN_UNDEF */
    CALL_READ_CB(&PL_sv_undef, keys->read_cb);
    return;
}

#endif /* __INHERITED_XS_IMPL_H_ */
