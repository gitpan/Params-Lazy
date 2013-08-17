#define PERL_NO_GET_CONTEXT 1
#ifdef WIN32
#  define NO_XSLOCKS
#endif
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

#if (PERL_REVISION == 5 && PERL_VERSION < 14)
#include "callchecker0.h"
#endif

#if (PERL_REVISION == 5 && PERL_VERSION >= 10)
#  define GOT_CUR_TOP_ENV
#  ifndef PL_restartjmpenv
#    define PL_restartjmpenv    cxstack[cxstack_ix+1].blk_eval.cur_top_env
#  endif
#endif

#ifdef XopENTRY_set
#  define GOT_CUSTOM_OPS
#endif

#ifndef MUTABLE_AV
#  define MUTABLE_AV(p)   ((AV *)(void *)(p))
#endif

#ifndef save_op
#  define save_op()     save_pushptr((void *)(PL_op), SAVEt_OP)
#endif

#ifndef save_pushptr
#  define save_pushptr(a,b) THX_save_pushptr(aTHX_ a, b)
void
THX_save_pushptr(pTHX_ void *const ptr, const int type)
{
    dVAR;
    SSCHECK(2);
    SSPUSHPTR(ptr);
    SSPUSHINT(type);
}
#endif

#ifndef cxinc
#  define cxinc()       THX_cxinc(aTHX)
/* Taken from scope.c */
I32
THX_cxinc(pTHX)
{
    dVAR;
    const IV old_max = cxstack_max;
    cxstack_max = cxstack_max + 1;
    Renew(cxstack, cxstack_max + 1, PERL_CONTEXT);
    /* Without any kind of initialising deep enough recursion
     * will end up reading uninitialised PERL_CONTEXTs. */
    PoisonNew(cxstack + old_max + 1, cxstack_max - old_max, PERL_CONTEXT);
    return cxstack_ix + 1;
}
#endif

#ifndef LINKLIST
#    define LINKLIST(o) ((o)->op_next ? (o)->op_next : op_linklist((OP*)o))
#  ifndef op_linklist
#    define op_linklist(o) THX_linklist(aTHX_ o)
OP *
THX_linklist(pTHX_ OP *o)
{
    OP *first;

    if (o->op_next)
        return o->op_next;

    /* establish postfix order */
    first = cUNOPo->op_first;
    if (first) {
        OP *kid;
        o->op_next = LINKLIST(first);
        kid = first;
        for (;;) {
            if (kid->op_sibling) {
                kid->op_next = LINKLIST(kid->op_sibling);
                kid = kid->op_sibling;
            } else {
                kid->op_next = o;
                break;
            }
        }
    }
    else
        o->op_next = o;

    return o->op_next;
}
#  endif
#endif

#ifndef op_contextualize
#  define scalar(op) Perl_scalar(aTHX_ op)
#  define list(op) Perl_list(aTHX_ op)
#  define scalarvoid(op) Perl_scalarvoid(aTHX_ op)
# define op_contextualize(op, c) THX_op_contextualize(aTHX_ op, c)
OP *
THX_op_contextualize(pTHX_ OP *o, I32 context)
{
    switch (context) {
        case G_SCALAR: return scalar(o);
        case G_ARRAY:  return list(o);
        case G_VOID:   return scalarvoid(o);
        default:
            Perl_croak(aTHX_ "panic: op_contextualize bad context %ld",
                       (long) context);
            return o;
    }
}
#endif

typedef struct {
 OP *delayed;
 
 AV *comppad;
} delay_ctx;

static int magic_free(pTHX_ SV *sv, MAGIC *mg)
{
  delay_ctx *ctx = (void *)mg->mg_ptr;
 
  PERL_UNUSED_ARG(sv);
 
  op_free((OP*)ctx->delayed);
  Safefree(ctx);
 
  return 1;
}
 
static MGVTBL vtbl = {
  NULL, /* get */
  NULL, /* set */
  NULL, /* len */
  NULL, /* clear */
  &magic_free,
#ifdef MGf_COPY
  NULL, /* copy */
#endif
#ifdef MGf_DUP
  NULL, /* dup */
#endif
#ifdef MGf_LOCAL
  NULL /* local */
#endif
};

STATIC OP *
replace_with_delayed(pTHX_ OP* aop) {
    OP* new_op;
    OP* const kid = aop;
    OP* const sib = kid->op_sibling;
    SV* magic_sv  = newSVpvs("STATEMENT");
    OP *listop;
    delay_ctx *ctx;

    Newx(ctx, 1, delay_ctx);

    /* Disconnect the op we're delaying, then wrap it in
     * a OP_LIST
     */
    kid->op_sibling = 0;

    /* Make GIMME in the deferred op be OPf_WANT_LIST */
    op_contextualize(kid, G_ARRAY);
    
    listop = newLISTOP(OP_LIST, 0, kid, (OP*)NULL);
    LINKLIST(listop);

    /* Stop it from looping */
    cUNOPx(kid)->op_next = (OP*)NULL;

    /* XXX TODO: Calling this twice, once before the LINKLIST
     * and once after, solves a bug; namely, that "delay 1..10"
     * would fail an assertion, because calling list() on an
     * OP_LIST would call lintkids(), which in turn calls
     * gen_constant_list for this sort of expression, and
     * without the first list(), it confuses the range
     * with a flip-flop.
     * Obviously this is suboptimal and probably works by sheer
     * luck, so, FIXME
     */
    op_contextualize(listop, G_ARRAY);
    
    ctx->delayed = (OP*)listop;

    /* We use this to restore the context the ops were
     * originally running in */
    ctx->comppad = PL_comppad;

    /* Magicalize the scalar, */
    sv_magicext(magic_sv, (SV*)NULL, PERL_MAGIC_ext, &vtbl, (const char *)ctx, 0);

    /* Then put that in place of the OPs we removed, but wrap
     * as a ref.
     */
    new_op = (OP*)newSVOP(OP_CONST, 0, newRV_noinc(magic_sv));
    new_op->op_sibling = sib;
    return new_op;
}

STATIC OP *
THX_ck_entersub_args_delay(pTHX_ OP *entersubop, GV *namegv, SV *ckobj)
{
    SV *proto            = newSVsv(ckobj);
    STRLEN protolen, len = 0;
    char * protopv       = SvPV(proto, protolen);
    OP *aop, *prev;
    
    PERL_UNUSED_ARG(namegv);
    
    aop = cUNOPx(entersubop)->op_first;
    
    if (!aop->op_sibling)
        aop = cUNOPx(aop)->op_first;
    
    prev = aop;
    
    for (aop = aop->op_sibling; aop->op_sibling; aop = aop->op_sibling) {
        if ( len < protolen ) {
            switch ( protopv[len] ) {
                case ':':
                    if ( aop->op_type == OP_REFGEN ) {
                        protopv[len] = '&';
                        break;
                    }
                    /* Fallthrough */
                case '^':
                {
                    aop = replace_with_delayed(aTHX_ aop);
                    prev->op_sibling = aop;
                    protopv[len] = '$';
                    break;
                }
            }
        }
        prev = aop;
        len++;
    }
    
    return ck_entersub_args_proto(entersubop, namegv, proto);
}

#ifdef CXp_MULTICALL
#  define CX_BLOCK_FLAG CXp_MULTICALL
#else
#  define CX_BLOCK_FLAG CXp_TRYBLOCK
#endif

STATIC void
S_do_force(pTHX)
{
    dSP;
    dJMPENV;
    SV *sv = POPs;
    delay_ctx *ctx;
    const I32 gimme = GIMME_V;
    I32 i, oldscope;
    U32 cx_type_flag = CX_BLOCK_FLAG;
    PERL_CONTEXT *cx;
#ifndef GOT_CUR_TOP_ENV
    JMPENV *cur_top_env;
#endif
    IV retvals, before;
    int ret = 0;
    /* PL_curstack and PL_stack_sp in the delayed OPs */
    AV *delayed_curstack;
    SV **delayed_sp;

    if ( SvROK(sv) && SvMAGICAL(SvRV(sv)) ) {
        ctx  = (void *)SvMAGIC(SvRV(sv))->mg_ptr;
    }
    else {
        croak("force() requires a delayed argument");
    }

    SAVEOP();
    SAVECOMPPAD();

#if (PERL_REVISION == 5 && PERL_VERSION >= 10)
    PUSHSTACKi(PERLSI_SORT);
#else
    PUSHSTACK;
#endif

    /* The SAVECOMPPAD and SAVEOP will restore these */
    PL_curpad  = AvARRAY(ctx->comppad);
    PL_comppad = ctx->comppad;
    PL_op      = ctx->delayed;
    
    PUSHMARK(PL_stack_sp);
    
    before      = (IV)(PL_stack_sp-PL_stack_base);    

    oldscope    = PL_scopestack_ix;
#ifndef GOT_CUR_TOP_ENV
    cur_top_env = PL_top_env;
#endif

    /* Disallow "delay goto &sub" and similar by pretending
     * to be a MULTICALL sub, or an eval block on 5.8.
     * This is required because of a possible regression in
     * perls 5.18 and newer, which caused it to segfault
     * because it wouldn't recognize us as outside of a sub.
     * "Possible" because it's more likely that it was never
     * supposed to work.
     */
    PUSHBLOCK(cx, cx_type_flag, PL_stack_sp);

    /* Call the deferred ops */
    /* Unfortunately we can't just do a CALLRUNOPS, since we must
     * handle the case of the delayed op being an eval, or a
     * pseudo-block with an eval inside, and that eval dying.
     */

    JMPENV_PUSH(ret);

    switch (ret) {
        case 0:
            redo_body:
            CALLRUNOPS(aTHX);
            break;
        case 3:
            /* If there's a PL_restartop, then this eval can handle
             * things on their own.
             */
            if (PL_restartop &&
#ifdef GOT_CUR_TOP_ENV
                PL_restartjmpenv == PL_top_env
#else
                cur_top_env      == PL_top_env
#endif
            ) {
#ifdef GOT_CUR_TOP_ENV
                PL_restartjmpenv = NULL;
#endif
                PL_op = PL_restartop;
                PL_restartop = 0;
                goto redo_body;
            }
            /* if there isn't, and the scopestack is out of sync,
             * then we need to intervene.
             */
            if ( PL_scopestack_ix >= oldscope ) {
                /* lazy eval { die }, lazy do { eval { die } } */
                /* Leave the eval */
                /* XXX TODO this doesn't quite work on 5.8 */
                LEAVE;
                break;
            }
            /* Fallthrough */
        default:
            /* Default behavior */
            JMPENV_POP;
            JMPENV_JUMP(ret);
    }
    JMPENV_POP;

    retvals = (IV)(PL_stack_sp-PL_stack_base);

    /* Keep a pointer to PL_curstack, and increase the
     * refcount so that it doesn't get freed in the
     * POPSTACK below.
     * Also keep a pointer to PL_stack_sp so we can copy
     * the values at the end.
     */
    if ( retvals && gimme != G_VOID ) {
        delayed_curstack = MUTABLE_AV(SvREFCNT_inc_simple_NN(PL_curstack));
        delayed_sp = PL_stack_sp;

        /* This has two uses.  First, it stops these from
         * being freed early after the FREETMPS/POPSTACK;
         * second, this is the ref we mortalize later,
         * with the mPUSHs
         */
        for (i = retvals; i > before; i--) {
            SvREFCNT_inc_simple_void_NN(*(PL_stack_sp-i+1));
        }
    }

    /* Lightweight POPBLOCK */
    cxstack_ix--;
    
    (void)POPMARK;
    POPSTACK;
    
    if ( retvals && gimme != G_VOID ) {
        EXTEND(PL_stack_sp, retvals);
        
        for (i = retvals; i-- > before;) {
            *++PL_stack_sp = sv_2mortal(*(delayed_sp-i));
        }
        SvREFCNT_dec(delayed_curstack);
    }
    
}

#ifdef GOT_CUSTOM_OPS
static OP*
S_pp_force(pTHX)
{
    PL_stack_sp--;
    ENTER;
    S_do_force(aTHX);
    LEAVE;
    return NORMAL;
}

static OP *
S_ck_force(pTHX_ OP *entersubop, GV *namegv, SV *cv)
{
    OP *aop, *prev, *first = NULL;
    UNOP *newop;

    ck_entersub_args_proto(entersubop, namegv, cv);

    aop = cUNOPx(entersubop)->op_first;
    if (!aop->op_sibling)
       aop = cUNOPx(aop)->op_first;
    prev = aop;
    aop = aop->op_sibling;
    first = aop;
    prev->op_sibling = first->op_sibling;
    first->op_flags &= ~OPf_MOD;
    aop = aop->op_sibling;
    /* aop now points to the cvop */
    prev->op_sibling = aop->op_sibling;
    aop->op_sibling = NULL;
    first->op_sibling = aop;

    NewOp(1234, newop, 1, UNOP);
    newop->op_type    = OP_CUSTOM;
    newop->op_ppaddr  = S_pp_force;
    newop->op_first   = first;
    newop->op_private = 1;
    newop->op_flags   = entersubop->op_flags;

    op_free(entersubop);

    return (OP *)newop;
}

static XOP my_xop;
#endif /* GOT_CUSTOM_OPS */

MODULE = Params::Lazy		PACKAGE = Params::Lazy		

PROTOTYPES: ENABLE

void
cv_set_call_checker_delay(CV *cv, SV *proto)
CODE:
    cv_set_call_checker(cv, THX_ck_entersub_args_delay, proto);

void
force(sv)
PROTOTYPE: $
PPCODE:
    S_do_force(aTHX);
    SP = PL_stack_sp;

BOOT:
{
#ifdef GOT_CUSTOM_OPS
    CV * const cv = get_cvn_flags("Params::Lazy::force", 19, 0);
    cv_set_call_checker(cv, S_ck_force, (SV *)cv);

    XopENTRY_set(&my_xop, xop_name, "force");
    XopENTRY_set(&my_xop, xop_desc, "force");
    XopENTRY_set(&my_xop, xop_class, OA_UNOP);
    Perl_custom_op_register(aTHX_ S_pp_force, &my_xop);
#endif
}
