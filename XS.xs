#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define NEED_mg_findext
#include "ppport.h"

#include "xs/compat.h"

static MGVTBL sv_payload_marker;
static bool optimize_entersub = 1;

typedef struct shared_keys {
    SV* hash_key;
    SV* pkg_key;
    HV* stash_cache;
} shared_keys;
#define SHARED_LAST_IDX 2

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

    return glob;
}

static GV*
update_cache(pTHX_ SV* self, HV* cache) {
    HV* stash;
    if (SvROK(self)) {
        stash = SvSTASH(SvRV(self));
    } else {
        stash = gv_stashsv(self, GV_ADD);
    }

    assert(stash);
    AV* supers = mro_get_linear_isa(stash);
    /*
        First entry in 'mro_get_linear_isa' list is a 'stash' itself. It's already been tested
        (otherwise we won't be here), so ajust counter and iterator to skip over it.
    */
    SSize_t supers_fill = AvFILLp(supers);
    SSize_t processed   = supers_fill;
    SV** supers_list    = AvARRAY(supers);

    assert(supers_fill > 0); /* if it's zero, than we're in a base accessor class and glob got replaced with placeholder */

    SV* cached_glob;
    while (--processed >= 0) {
        SV* elem = *(++supers_list);

        if (elem) {
            HE* hent = hv_fetch_ent(cache, elem, 0, 0);
            assert(hent); /* cache is correctly filled */

            cached_glob = HeVAL(hent);
            if (cached_glob != &PL_sv_undef) break;
        }
    }

    assert(cached_glob != &PL_sv_undef); /* eventually found smth, at least glob in a base accessor class */

    /*
        Now travel supers list back and write glob to cache, including first (stash) element.
        But skip _current_ position, as it's just fetched from cache.
    */

    supers_fill -= processed;
    while (--supers_fill >= 0) {
        SV* elem = *(--supers_list);

        if (elem) {
            hv_store_ent(cache, elem, cached_glob, 0);
            SvREFCNT_inc_NN(cached_glob);
        }
    }

    assert(supers_list == AvARRAY(supers));

    return (GV*)cached_glob;
}

static GV*
reset_stash_cache(pTHX_ HV* stash, shared_keys* keys) {
    HV* cache = keys->stash_cache;

    GV* base_glob = init_storage_glob(aTHX_ stash, keys);
    if (!GvSV(base_glob)) gv_SVadd(base_glob); /* it also needs magic */

    HE* hent = hv_fetchhek_ent(PL_isarev, HvENAME_HEK_NN(stash));
    if (!hent) return base_glob;

    HV* isarev   = (HV*)HeVAL(hent);
    STRLEN hvmax = HvMAX(isarev);
    HE** hvarr   = HvARRAY(isarev);

    if (!hvarr) return base_glob;

    SV** base_cached = (SV**)hv_fetchhek_flags(cache, HvENAME_HEK_NN(stash), HV_FETCH_JUST_SV);
    /* it may be null, but in such cases we never get to *svp == *base_cached comparison */
    /* is that true? */

    for (STRLEN i = 0; i <= hvmax; ++i) {
        HE* entry;
        for (entry = hvarr[i]; entry; entry = HeNEXT(entry)) {
            HEK* hek = HeKEY_hek(entry);
            HV* stash = gv_stashpvn(HEK_KEY(hek), HEK_LEN(hek), HEK_UTF8(hek) | GV_ADD);

            /* result is ignored, this call is just to set magic on GvSV, if it's not */
            GV* glob = init_storage_glob(aTHX_ stash, keys);

            /* PL_sv_undef is a placeholder meaning 'walk up mro and recalculate cache' */
            SV** svp = (SV**)hv_fetchhek_flags(cache, HvENAME_HEK_NN(stash), HV_FETCH_LVALUE | HV_FETCH_EMPTY_HE | HV_FETCH_JUST_SV);
            if (*svp == NULL) {
                *svp = &PL_sv_undef;

            } else if (*svp == *base_cached) {
                SvREFCNT_dec_NN(*svp);
                *svp = &PL_sv_undef;
            }
        }
    }

    return base_glob;
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
    CvXSUBANY(cv).any_ptr = (void*)keys_array;
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

    shared_keys* keys;
#ifndef MULTIPLICITY
    /* Blessed are ye and get a fastpath */
    keys = (shared_keys*)(CvXSUBANY(cv).any_ptr);
    if (!keys) croak("Can't find hash key information");
#else
    /*
        We can't look into CvXSUBANY under threads, as it would have been written in the parent thread
        and might go away at any time without prior notice. So, instead, we have to scan our magical 
        refcnt storage - there's always a proper thread-local SV*, cloned for us by perl itself.
    */
    MAGIC* mg = mg_findext((SV*)cv, PERL_MAGIC_ext, &sv_payload_marker);
    if (!mg) croak("Can't find hash key information");

    keys = (shared_keys*)AvARRAY((AV*)(mg->mg_obj));
#endif

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

    HV* cache = keys->stash_cache;
    if (!HvARRAY(cache)) {
        GV* acc_gv = CvGV(cv);
        if (!acc_gv) croak("Can't have pkg accessor in anon sub");
        HV* stash = GvSTASH(acc_gv);

        GV* base_glob = reset_stash_cache(aTHX_ stash, keys);
        SvREFCNT_inc_NN(base_glob);
        hv_storehek(cache, HvENAME_HEK_NN(stash), (SV*)base_glob);
    }

    assert(SvROK(self) || SvPOK(self));

    if (items == 1) {
        /* must ensure that the glob hasn't been stolen and replaced with something new */

        HE* hent;
        if (SvROK(self)) {
            HV* stash = SvSTASH(SvRV(self));
            hent = hv_fetchhek_ent(cache, HvENAME_HEK_NN(stash));

        } else {
            hent = hv_fetch_ent(cache, self, 0, 0);
        }

        assert(hent);
        GV* glob_or_fake = (GV*)HeVAL(hent);

        if (glob_or_fake == (GV*)&PL_sv_undef) {
            glob_or_fake = update_cache(aTHX_ self, cache);
        }

        assert(GvSV(glob_or_fake));
        SV* new_value = GvSV(glob_or_fake);

        /* use ST(0) instead of all PUSHs ? */
        PUSHs(new_value);
        XSRETURN(1);
    }

    /* set logic */
    HV* stash = SvROK(self) ? SvSTASH(SvRV(self)) : gv_stashsv(self, GV_ADD);

    GV* glob = reset_stash_cache(aTHX_ stash, keys);
    SV* value = ST(1);

    if (!SvOK(value)) {
        PUSHs(value);
        /* but if it's root stash - should update cache */
        /* always update underlying glob */
        /* and no need to reset cache, if new == old ? at least, for undefs ? */

    } else {
        hv_storehek(cache, HvENAME_HEK_NN(stash), (SV*)glob);
        SvREFCNT_inc_NN(glob);

        /* use just GvSV, as it'd be prepared for us by init_storage_glob */
        SV* new_value = GvSVn(glob);
        sv_setsv(new_value, value);
        PUSHs(new_value);
    }

    XSRETURN(1);
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

