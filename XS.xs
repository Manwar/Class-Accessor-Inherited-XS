#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define NEED_mg_findext
#include "ppport.h"

#include "xs/compat.h"

#ifdef NDEBUG
#define debug(...)
#else
#define debug warn
#endif

#define dKEYS_FROM_AV(keys_av) shared_keys* keys = (shared_keys*)AvARRAY(keys_av);

static MGVTBL sv_payload_marker;
static bool optimize_entersub = 1;

typedef struct shared_keys {
    SV* hash_key;
    SV* pkg_key;
    HV* stash_cache;
} shared_keys;
#define SHARED_LAST_IDX 2

static int wipe_cache(pTHX_ SV* sv, MAGIC* mg);
static MGVTBL isa_changer_marker = {
    0, wipe_cache, 0, wipe_cache, 0, 0, 0, 0
};

static void
add_isa_hook(pTHX_ HV* stash, AV* keys_av) {
    dKEYS_FROM_AV(keys_av);

    SV** svp = hv_fetch(stash, "ISA", 3, 0);    /* static "ISA"-holding SV */
    if (!svp) {
        warn("No @ISA for stash %s", HvENAME(stash));
        return; /* assert for root stash */
    }

    GV* isa_gv = (GV*)*svp;
    assert(GvAV(isa_gv));   /* what of our parent, huh? */

    debug("add_ISA_hook: %s", HvENAME(stash));

    MAGIC* mg = sv_magicext((SV*)GvAV(isa_gv), (SV*)keys_av, PERL_MAGIC_ext, &isa_changer_marker, (const char*)stash, HEf_SVKEY);
    SvREFCNT_dec_NN((SV*)keys_av);
}

static GV*
init_storage_glob(pTHX_ HV* stash, shared_keys* keys) {
    HE* hent = hv_fetch_ent(stash, keys->pkg_key, 0, 0);
    GV* glob = hent ? (GV*)HeVAL(hent) : NULL;

    if (!glob || !isGV(glob) || SvFAKE(glob)) {
        if (!glob) glob = (GV*)newSV(0);

        gv_init_sv(glob, stash, keys->pkg_key, 0);

        if (hent) {
            /* Not sure when this can happen - remains untested */
            SvREFCNT_inc_NN((SV*)glob);
            SvREFCNT_dec_NN(HeVAL(hent));
            HeVAL(hent) = (SV*)glob;

        } else {
            if (!hv_store_ent(stash, keys->pkg_key, (SV*)glob, 0)) {
                SvREFCNT_dec_NN(glob);
                croak("Can't add a glob to package");
            }
        }
    }

    /* gv_SVadd + set magic here or in reset_stash_cache ? */

    if (!GvSV(glob)) gv_SVadd(glob);
    return glob;
}

static HE*
update_cache(pTHX_ SV* self, HV* cache, AV* keys_av) {
    HV* stash;
    if (SvROK(self)) {
        stash = SvSTASH(SvRV(self));
    } else {
        stash = gv_stashsv(self, GV_ADD);
    }

    assert(stash);
    debug("update_cache: %s", HvENAME(stash));

    AV* supers = mro_get_linear_isa(stash);
    /*
        First entry in 'mro_get_linear_isa' list is a 'stash' itself. It's already been tested
        (otherwise we won't be here), so ajust counter and iterator to skip over it.
    */
    SSize_t supers_fill = AvFILLp(supers);
    SSize_t processed   = supers_fill;
    SV** supers_list    = AvARRAY(supers);

    assert(supers_fill > 0); /* if it's zero, than we're in a base accessor class and glob got replaced with a placeholder */

    SV* cached_glob;
    HE* cached_hent;
    while (--processed >= 0) {
        SV* elem = *(++supers_list);

        if (elem) {
            cached_hent = hv_fetch_ent(cache, elem, 0, 0);

            if (!cached_hent) continue; /* added smth new into @ISA */

            cached_glob = HeVAL(cached_hent);
            if (cached_glob != &PL_sv_undef) {
                debug("update_cache: picked %s", SvPV_nolen(elem));
                break;
            }
        }
    }

    assert(cached_glob != &PL_sv_undef); /* eventually found smth, at least glob from the base accessor class */

    /*
        Now travel supers list back and write glob to cache, including first element (stash).
        But skip _current_ position, as it's just fetched from cache.
    */

    supers_fill -= processed;
    add_isa_hook(aTHX_ gv_stashsv(*supers_list, GV_ADD), keys_av);  /* if !exists */
    while (--supers_fill >= 0) {
        SV* elem = *(--supers_list);

        if (elem) {
            add_isa_hook(aTHX_ gv_stashsv(elem, GV_ADD), keys_av);  /* if !exists */
            hv_store_ent(cache, elem, cached_glob, 0);
            SvREFCNT_inc_NN(cached_glob);
        }
    }

    assert(supers_list == AvARRAY(supers));

    return cached_hent;
}

static GV*
reset_stash_cache(pTHX_ HV* stash, shared_keys* keys) {
    HV* cache = keys->stash_cache;

    /* why fetch&return it? we don't use it -> make it caller's responsibility? */
    /* maybe better return svp_base_cached, so it can be set easily ? */
    GV* base_glob = init_storage_glob(aTHX_ stash, keys);

    /* reset base cache entry first */
    SV** svp_base_cached = hv_fetchhek_lval(cache, HvENAME_HEK_NN(stash));
    SV* base_cached = *svp_base_cached;
    *svp_base_cached = &PL_sv_undef;

    if (base_cached == &PL_sv_undef) {
        debug("Useless reset_stash_cache %s", HvENAME(stash));
        return base_glob;
    }
    assert(base_cached != &PL_sv_undef); /* useless reset call that'd clear already clear state */

    /* and then clear cache for all our children that have no own info */
    HE* hent = hv_fetchhek_ent(PL_isarev, HvENAME_HEK_NN(stash));
    if (!hent) return base_glob;

    HV* isarev   = (HV*)HeVAL(hent);
    STRLEN hvmax = HvMAX(isarev);
    HE** hvarr   = HvARRAY(isarev);

    if (!hvarr) return base_glob;

    for (STRLEN i = 0; i <= hvmax; ++i) {
        HE* entry;
        for (entry = hvarr[i]; entry; entry = HeNEXT(entry)) {
            HEK* hek = HeKEY_hek(entry);
            HV* stash = gv_stashpvn(HEK_KEY(hek), HEK_LEN(hek), HEK_UTF8(hek) | GV_ADD);

            /* result is ignored, this call is just to set magic on GvSV, if it's not */
            init_storage_glob(aTHX_ stash, keys);

            SV** svp = hv_fetchhek_lval(cache, HvENAME_HEK_NN(stash));
            /*
                *svp can be one of the:
                  - NULL, empty slot created for us by LVAL - mark it as unused
                  - &PL_sv_undef, ignore
                  - glob == base cached glob, clear it
                  - glob != base cached glob, ignore
                base_cached can be NULL here, we don't care
            */
            if (*svp == NULL) {
                /* PL_sv_undef is a placeholder meaning 'walk up mro and recalculate cache' */
                *svp = &PL_sv_undef;

            } else if (*svp == base_cached) {
                SvREFCNT_dec_NN(*svp);
                *svp = &PL_sv_undef;
            }
        }
    }

    return base_glob;
}

static int
wipe_cache(pTHX_ SV* sv, MAGIC* mg) {
    dKEYS_FROM_AV((AV*)(mg->mg_obj));

    debug("C_wipe_cache: %s", HvENAME((HV*)(mg->mg_ptr)));
    assert(HvARRAY(keys->stash_cache)); /* no magic prior to 1st acc call */

    reset_stash_cache(aTHX_ (HV*)(mg->mg_ptr), keys);

    return 0;
}

XS(CAIXS_inherited_accessor);

static void
CAIXS_install_accessor(pTHX_ SV* full_name, SV* hash_key, SV* pkg_key)
{
    STRLEN len;

    const char* full_name_buf = SvPV_nolen(full_name);
    CV* cv = newXS_flags(full_name_buf, CAIXS_inherited_accessor, __FILE__, NULL, SvUTF8(full_name));
    if (!cv) croak("Can't install XS accessor");

    const char* hash_key_buf = SvPV_const(hash_key, len);
    SV* s_hash_key = newSVpvn_share(hash_key_buf, SvUTF8(hash_key) ? -(I32)len : (I32)len, 0);

    const char* pkg_key_buf = SvPV_const(pkg_key, len);
    SV* s_pkg_key = newSVpvn_share(pkg_key_buf, SvUTF8(pkg_key) ? -(I32)len : (I32)len, 0);

    AV* keys_av = newAV();
    /*
        This is a pristine AV, so skip as much checks as possible on whichever perls we can grab it.
    */
    av_extend_guts(keys_av, SHARED_LAST_IDX, &AvMAX(keys_av), &AvALLOC(keys_av), &AvARRAY(keys_av));
    AvFILLp(keys_av) = SHARED_LAST_IDX;
    SV** keys_array = AvARRAY(keys_av);
    keys_array[0] = s_hash_key;
    keys_array[1] = s_pkg_key;
    keys_array[2] = (SV*)newHV();

#ifndef MULTIPLICITY
    CvXSUBANY(cv).any_ptr = (void*)keys_av;
#endif

    sv_magicext((SV*)cv, (SV*)keys_av, PERL_MAGIC_ext, &sv_payload_marker, NULL, 0);
    SvREFCNT_dec_NN((SV*)keys_av);
    SvRMAGICAL_off((SV*)cv);
}

OP *
CAIXS_entersub(pTHX) {
    dSP;

    CV* sv = (CV*)TOPs;
    if (sv && (SvTYPE(sv) == SVt_PVCV) && (CvXSUB(sv) == CAIXS_inherited_accessor)) {
        /*
            Assert against future XPVCV layout change - as for now, xcv_xsub shares space with xcv_root
            which are both pointers, so address check is enough, and there's no need to look into op_flags for CvISXSUB.
        */
        assert(CvISXSUB(sv));

        POPs; PUTBACK;
        CAIXS_inherited_accessor(aTHX_ sv);
        return NORMAL;
    } else {
        PL_op->op_ppaddr = PL_ppaddr[OP_ENTERSUB];
        return PL_ppaddr[OP_ENTERSUB](aTHX);
    }
}

XS(CAIXS_inherited_accessor)
{
    dXSARGS;
    SP -= items;

    if (!items) croak("Usage: $obj->accessor or __PACKAGE__->accessor");

    /*
        Check whether we can replace opcode executor with our own variant. Unfortunatelly, this guards
        only against local changes, not when someone steals PL_ppaddr[OP_ENTERSUB] globally.
        Sorry, Devel::NYTProf.
    */
    OP* op = PL_op;
    if ((op->op_spare & 1) != 1 && op->op_ppaddr == PL_ppaddr[OP_ENTERSUB] && optimize_entersub) {
        op->op_spare |= 1;
        op->op_ppaddr = CAIXS_entersub;
    }

    AV* keys_av;
#ifndef MULTIPLICITY
    /* Blessed are ye and get a fastpath */
    keys_av = (AV*)(CvXSUBANY(cv).any_ptr);
    if (!keys_av) croak("Can't find hash key information");
#else
    /*
        We can't look into CvXSUBANY under threads, as it would have been written in the parent thread
        and might go away at any time without prior notice. So, instead, we have to scan our magical 
        refcnt storage - there's always a proper thread-local SV*, cloned for us by perl itself.
    */
    MAGIC* mg = mg_findext((SV*)cv, PERL_MAGIC_ext, &sv_payload_marker);
    if (!mg) croak("Can't find hash key information");

    keys_av = (AV*)(mg->mg_obj);
#endif
    dKEYS_FROM_AV(keys_av);

    SV* self = ST(0);
    if (SvROK(self)) {
        HV* obj = (HV*)SvRV(self);
        if (SvTYPE((SV*)obj) != SVt_PVHV) {
            croak("Inherited accessors can only work with object instances that is hash-based");
        }

        if (items > 1) {
            SV* new_value  = newSVsv(ST(1));
            if (!hv_store_ent(obj, keys->hash_key, new_value, 0)) {
                SvREFCNT_dec_NN(new_value);
                croak("Can't store new hash value");
            }
            PUSHs(new_value);
            XSRETURN(1);
                    
        } else {
            HE* hent = hv_fetch_ent(obj, keys->hash_key, 0, 0);
            if (hent) {
                PUSHs(HeVAL(hent));
                XSRETURN(1);
            }
        }
    }

    /* Couldn't find value in object, so initiate a package lookup. */

    #define dROOTSTASH                                          \
    GV* acc_gv = CvGV(cv);                                      \
    if (!acc_gv) croak("Can't have pkg accessor in anon sub");  \
    HV* root_stash = GvSTASH(acc_gv);

    HV* cache = keys->stash_cache;
    if (!HvARRAY(cache)) {
        dROOTSTASH;
        GV* base_glob = reset_stash_cache(aTHX_ root_stash, keys);
        SvREFCNT_inc_NN(base_glob);
        hv_storehek(cache, HvENAME_HEK_NN(root_stash), (SV*)base_glob);

        add_isa_hook(aTHX_ root_stash, keys_av); /* assert !exists */
    }

    assert(SvROK(self) || SvPOK(self));

    /* must ensure that the glob hasn't been stolen and replaced with something new */

    HE* hent;
    if (SvROK(self)) {
        HV* stash = SvSTASH(SvRV(self));
        hent = hv_fetchhek_ent(cache, HvENAME_HEK_NN(stash));

    } else {
        hent = hv_fetch_ent(cache, self, 0, 0);
    }

    if (!hent) {
        debug("no hent, perform update_cache");
        /* new element in inheritance chain? */
        hent = update_cache(aTHX_ self, cache, keys_av);
        if (!hent) croak("Tried to call inherited accessor outside of root inheritance chain");
    }

    GV* glob_or_fake = (GV*)HeVAL(hent);

    if (items == 1) {
        if (glob_or_fake == (GV*)&PL_sv_undef) {
            hent = update_cache(aTHX_ self, cache, keys_av);
            glob_or_fake = (GV*)HeVAL(hent);
        }

        assert(GvSV(glob_or_fake));
        PUSHs(GvSV(glob_or_fake));
        XSRETURN(1);
    }

    /* set logic */
    HV* stash = SvROK(self) ? SvSTASH(SvRV(self)) : gv_stashsv(self, GV_ADD);
    SV* value = ST(1);

    /* all those checks are to reduce number of 'reset_stash_cache' calls */

    if (SvOK(value)) {
        #define SET_CACHE_ENTRY             \
        SvREFCNT_inc_NN((SV*)glob_or_fake); \
        HeVAL(hent) = (SV*)glob_or_fake;

        if (glob_or_fake != (GV*)&PL_sv_undef) {
            if (GvSTASH(glob_or_fake) != stash) {
                glob_or_fake = reset_stash_cache(aTHX_ stash, keys);

                SvREFCNT_dec_NN(HeVAL(hent));
                SET_CACHE_ENTRY;
            }
        } else {
            glob_or_fake = init_storage_glob(aTHX_ stash, keys);
            SET_CACHE_ENTRY;
        }

        assert(GvSV(glob_or_fake));
        SV* new_value = GvSV(glob_or_fake);

        sv_setsv(new_value, value);
        PUSHs(new_value);
        XSRETURN(1);

    } else {
        if (glob_or_fake != (GV*)&PL_sv_undef /* && SvOK(GvSV(glob_or_fake)) */ ) {
            dROOTSTASH;
            glob_or_fake = reset_stash_cache(aTHX_ stash, keys);
            sv_setsv(GvSV(glob_or_fake), &PL_sv_undef);

            /* cache for root must always be valid */
            if (GvSTASH(glob_or_fake) == root_stash) {
                SET_CACHE_ENTRY;
            }
        }

        XSRETURN_UNDEF;
    }
}

MODULE = Class::Accessor::Inherited::XS		PACKAGE = Class::Accessor::Inherited::XS
PROTOTYPES: DISABLE

BOOT:
{
    SV** check_env = hv_fetch(GvHV(PL_envgv), "CAIXS_DISABLE_ENTERSUB", 22, 0);
    if (check_env && SvTRUE(*check_env)) optimize_entersub = 0;
}

void
install_inherited_accessor(SV* full_name, SV* hash_key, SV* pkg_key)
PPCODE: 
{
    CAIXS_install_accessor(aTHX_ full_name, hash_key, pkg_key);
    XSRETURN_UNDEF;
}

