#ifndef __INHERITED_XS_COMPAT_H_
#define __INHERITED_XS_COMPAT_H_

#ifndef SvREFCNT_dec_NN
#define SvREFCNT_dec_NN SvREFCNT_dec
#endif

#ifdef dNOOP
#undef dNOOP
#define dNOOP
#endif

#ifndef gv_init_sv
#define gv_init_sv(gv, stash, sv, flags) gv_init(gv, stash, SvPVX(sv), SvLEN(sv), flags | SvUTF8(sv))
#endif

#if defined(_WIN32) || defined(WIN32) || (PERL_VERSION < 18)
#define av_extend_guts(hv, idx, max, alloc, array) av_extend(hv, idx)
#else
#define av_extend_guts(hv, idx, max, alloc, array) Perl_av_extend_guts(aTHX_ hv, idx, max, alloc, array)
#endif

#ifndef hv_storehek
#define hv_storehek(hv, hek, val) \
    hv_common((hv), NULL, HEK_KEY(hek), HEK_LEN(hek), HEK_UTF8(hek),    \
            HV_FETCH_ISSTORE|HV_FETCH_JUST_SV, (val), HEK_HASH(hek))
#endif

#define hv_fetchhek_ent(hv, hek) ((HE*) hv_fetchhek_flags(hv, hek, 0))

#define hv_fetchhek_flags(hv, hek, flags) \
    hv_common((hv), NULL, HEK_KEY(hek), HEK_LEN(hek), HEK_UTF8(hek), (flags), NULL, HEK_HASH(hek))

#endif /* __INHERITED_XS_COMPAT_H_ */
