(* ===================================================================== *)
(* FILE          : Drule.sml                                             *)
(* DESCRIPTION   : Derived theorems and rules. (Proper derivations are 	 *)
(*		   given as comments.) Largely translated from hol88.    *)
(*                                                                       *)
(* AUTHORS       : (c) Mike Gordon and                                   *)
(*                     Tom Melham, University of Cambridge, for hol88    *)
(* TRANSLATOR    : Konrad Slind, University of Calgary                   *)
(* DATE          : September 11, 1991                                    *)
(* ===================================================================== *)


structure Drule :> Drule =
struct

open Feedback HolKernel Parse boolTheory boolSyntax Abbrev;

val ERR = mk_HOL_ERR "Drule";


(*---------------------------------------------------------------------------*
 *  Add an assumption                                                        *
 *                                                                           *
 *      A |- t'                                                              *
 *   -----------                                                             *
 *    A,t |- t'                                                              *
 *---------------------------------------------------------------------------*)

fun ADD_ASSUM t th = MP (DISCH t th) (ASSUME t);


(*---------------------------------------------------------------------------
 * Transitivity of ==>
 *
 *   A1 |- t1 ==> t2            A2 |- t2 ==> t3
 * ---------------------------------------------
 *           A1 u A2 |- t1 ==> t3
 *
 * fun IMP_TRANS th1 th2 =
 *    let val {ant, conseq} = dest_imp (concl th1)
 *        val {ant=ant', conseq=conseq'} = dest_imp (concl th2)
 *        val _ = thm_assert (aconv conseq ant') "" ""
 *    in
 *   make_thm Count.ImpTrans (Tag.merge (tag th1) (tag th2),
 *                 union (hyp th1) (hyp th2),
 *                 mk_imp{ant=ant, conseq=conseq'})
 *    end
 *   handle _ => THM_ERR "IMP_TRANS" "";
 *
 *
 *  Modified: TFM 88.10.08 to use "union A1 A1" instead of A1 @ A2
 *---------------------------------------------------------------------------*)

fun IMP_TRANS th1 th2 =
   let val (ant,conseq) = dest_imp(concl th1)
   in DISCH ant (MP th2 (MP th1 (ASSUME ant)))
   end
   handle HOL_ERR _ => raise ERR "IMP_TRANS" "";


(*---------------------------------------------------------------------------
 *
 *   A1 |- t1 ==> t2         A2 |- t2 ==> t1
 *  -----------------------------------------
 *            A1 u A2 |- t1 = t2
 *
 * fun IMP_ANTISYM_RULE th1 th2 =
 *   let val {ant=ant1, conseq=conseq1} = dest_imp(concl th1)
 *      and {ant=ant2, conseq=conseq2} = dest_imp(concl th2)
 *     val _ = thm_assert (aconv ant1 conseq2 andalso aconv ant2 conseq1) "" ""
 *   in
 *    make_thm Count.ImpAntisymRule(Tag.merge (tag th1) (tag th2),
 *                 union (hyp th1) (hyp th2),
 *                 mk_eq{lhs=ant1, rhs=conseq1})
 *  end
 *  handle _ => THM_ERR "IMP_ANTISYM_RULE" "";
 *  Modified: TFM 88.10.08 to use "union A1 A2" instead of A1 @ A2
 *---------------------------------------------------------------------------*)

 fun IMP_ANTISYM_RULE th1 th2 =
    let val (ant,conseq) = dest_imp(concl th1)
    in MP (MP (SPEC conseq (SPEC ant IMP_ANTISYM_AX)) th1) th2
    end
    handle HOL_ERR _ => raise ERR"IMP_ANTISYM_RULE" "";


(*---------------------------------------------------------------------------*
 * Introduce  =T                                                             *
 *                                                                           *
 *     A |- t                                                                *
 *   ------------                                                            *
 *     A |- t=T                                                              *
 *                                                                           *
 *  local val truth = mk_const{Name="T", Ty = Type.bool}                     *
 *  in                                                                       *
 *  fun EQT_INTRO th =                                                       *
 *    let val t = concl th                                                   *
 *    in                                                                     *
 *      MP (MP (SPEC truth (SPEC t IMP_ANTISYM_AX))                          *
 *             (DISCH t TRUTH))                                              *
 *         (DISCH truth th)                                                  *
 *    end                                                                    *
 *  end;                                                                     *
 *                                                                           *
 *---------------------------------------------------------------------------*)

local val eq_thm =
        let val (Bvar,_) = dest_forall (concl boolTheory.EQ_CLAUSES)
            val thm = CONJUNCT1(CONJUNCT2 (SPEC Bvar boolTheory.EQ_CLAUSES))
        in GEN Bvar (SYM thm)
        end
in
fun EQT_INTRO th = EQ_MP (SPEC (concl th) eq_thm) th
                   handle HOL_ERR _ => raise ERR "EQT_INTRO" ""
end;

(*---------------------------------------------------------------------------
 *  |- !x. t    ---->    x', |- t[x'/x]
 *---------------------------------------------------------------------------*)

fun SPEC_VAR th =
   let val (Bvar,_) = dest_forall (concl th)
       val bv' = prim_variant (HOLset.listItems (hyp_frees th)) Bvar
   in (bv', SPEC bv' th)
   end;

(*---------------------------------------------------------------------------
 *  |- !:a. t    ---->    a', |- t[a'/a]
 *---------------------------------------------------------------------------*)

fun SPEC_TYVAR th =
   let val (Bvar,_) = dest_tyforall (concl th)
       val bv' = prim_variant_type (HOLset.listItems (hyp_tyvars th)) Bvar
   in (bv', TY_SPEC bv' th)
   end;

(*---------------------------------------------------------------------------
 *
 *       A |-  (!x. t1 = t2)
 *   ---------------------------
 *    A |- (?x.t1)  =  (?x.t2)
 *
 * fun MK_EXISTS bodyth =
 *    let val {Bvar,Body} = dest_forall (concl bodyth)
 *        val {lhs,rhs} = dest_eq Body
 *    in
 *    make_thm Count.MkExists (tag bodyth, hyp bodyth,
 *                  mk_eq{lhs=mk_exists{Bvar=Bvar, Body=lhs},
 *                        rhs=mk_exists{Bvar=Bvar, Body=rhs}})
 *    end
 *    handle _ => THM_ERR "MK_EXISTS" "";
 *---------------------------------------------------------------------------*)

fun MK_EXISTS bodyth =
 let val (x, sth) = SPEC_VAR bodyth
     val (a,b) = dest_eq (concl sth)
     val (abimp,baimp) = EQ_IMP_RULE sth
     fun HALF (p,q) pqimp =
       let val xp = mk_exists(x,p)
           and xq = mk_exists(x,q)
       in DISCH xp (CHOOSE (x,ASSUME xp) (EXISTS (xq,x) (MP pqimp (ASSUME p))))
       end
 in
    IMP_ANTISYM_RULE (HALF (a,b) abimp) (HALF (b,a) baimp)
 end
 handle HOL_ERR _ => raise ERR "MK_EXISTS" "";

(*---------------------------------------------------------------------------
 *
 *       A |-  (!:a. t1 = t2)
 *   ---------------------------
 *    A |- (?:a.t1)  =  (?:a.t2)
 *
 * fun MK_TY_EXISTS bodyth =
 *    let val {Bvar,Body} = dest_tyforall (concl bodyth)
 *        val {lhs,rhs} = dest_eq Body
 *    in
 *    make_thm Count.MkTyExists (tag bodyth, hyp bodyth,
 *                  mk_eq{lhs=mk_tyexists{Bvar=Bvar, Body=lhs},
 *                        rhs=mk_tyexists{Bvar=Bvar, Body=rhs}})
 *    end
 *    handle _ => THM_ERR "MK_TY_EXISTS" "";
 *---------------------------------------------------------------------------*)

fun MK_TY_EXISTS bodyth =
 let val (x, sth) = SPEC_TYVAR bodyth
     val (a,b) = dest_eq (concl sth)
     val (abimp,baimp) = EQ_IMP_RULE sth
     fun HALF (p,q) pqimp =
       let val xp = mk_tyexists(x,p)
           and xq = mk_tyexists(x,q)
       in DISCH xp (TY_CHOOSE (x,ASSUME xp) (TY_EXISTS (xq,x) (MP pqimp (ASSUME p))))
       end
 in
    IMP_ANTISYM_RULE (HALF (a,b) abimp) (HALF (b,a) baimp)
 end
 handle HOL_ERR _ => raise ERR "MK_TY_EXISTS" "";


(*---------------------------------------------------------------------------
 *               A |-  t1 = t2
 *   ------------------------------------------- (xi not free in A)
 *    A |- (?x1 ... xn. t1)  =  (?x1 ... xn. t2)
 *---------------------------------------------------------------------------*)

fun LIST_MK_EXISTS l th = itlist (fn x => fn th => MK_EXISTS(GEN x th)) l th;


(*---------------------------------------------------------------------------
 *               A |-  t1 = t2
 *   ------------------------------------------- (ai not free in A)
 *    A |- (?:a1 ... an. t1)  =  (?:a1 ... an. t2)
 *---------------------------------------------------------------------------*)

fun LIST_MK_TY_EXISTS l th = itlist (fn x => fn th => MK_TY_EXISTS(TY_GEN x th)) l th;


fun SIMPLE_EXISTS v th = EXISTS (mk_exists(v, concl th), v) th

fun SIMPLE_TY_EXISTS v th = TY_EXISTS (mk_tyexists(v, concl th), v) th

fun SIMPLE_CHOOSE v th =
  case HOLset.find (fn _ => true) (Thm.hypset th) of
    SOME h => CHOOSE(v, ASSUME (boolSyntax.mk_exists(v,h))) th
  | NONE => raise ERR "SIMPLE_CHOOSE" "";

fun SIMPLE_TY_CHOOSE v th =
  case HOLset.find (fn _ => true) (Thm.hypset th) of
    SOME h => TY_CHOOSE(v, ASSUME (boolSyntax.mk_tyexists(v,h))) th
  | NONE => raise ERR "SIMPLE_TY_CHOOSE" "";



(*---------------------------------------------------------------------------
 *
 *     A1 |- t1 = u1   ...   An |- tn = un       A |- t[ti]
 *    -------------------------------------------------------
 *               A1 u ... An u A |-  t[ui]
 *
 * fun GSUBS substfn ths th =
 *    let val (oracles,h',s) = itlist (fn th => fn (O,H,L) =>
 *             let val {lhs,rhs} = dest_eq (concl th)
 *             in (Tag.merge (tag th) O,
 *                 union (hyp th) H, (lhs |-> rhs)::L)
 *             end) ths (tag th, hyp th,[])
 *    in make_thm Count.Gsubs (oracles, h', substfn s (concl th))
 *    end
 *---------------------------------------------------------------------------*)

local fun combine [] [] = []
        | combine (v::rst1) (t::rst2) = (v |-> t) :: combine rst1 rst2
        | combine _ _ = raise ERR "GSUBS.combine" "Different length lists"
in
fun GSUBS substfn ths th =
   let val ls = map (lhs o concl) ths
       val vars = map (genvar o type_of) ls
       val w = substfn (combine ls vars) (concl th)
   in
     SUBST (combine vars ths) w th
   end
end;


fun SUBS ths th = GSUBS subst ths th handle HOL_ERR _ => raise ERR "SUBS" "";

fun SUBS_OCCS nlths th =
   let val (nll, ths) = unzip nlths
   in GSUBS (subst_occs nll) ths th
   end handle HOL_ERR _ => raise ERR "SUBS_OCCS" "";


(*---------------------------------------------------------------------------
 *       A |- ti == ui
 *    --------------------
 *     A |- t[ti] = t[ui]
 *
 * fun SUBST_CONV replacements template tm =
 *   let val (ltheta, rtheta, hyps,oracles) = itlist
 *              (fn {redex,residue} => fn (ltheta,rtheta,hyps,O) =>
 *                let val {lhs,rhs} = dest_eq (concl residue)
 *                in ((redex |-> lhs)::ltheta, (redex |-> rhs)::rtheta,
 *                    union (hyp residue) hyps,
 *                    Tag.merge (tag residue) O)
 *                end) replacements ([],[],[],std_tag)
 *       val _ = thm_assert (aconv (subst ltheta template) tm) "" ""
 *   in
 *     make_thm Count.SubstConv(oracles, hyps,
 *                              mk_eq{lhs=tm, rhs = subst rtheta template})
 *   end
 *   handle _ => THM_ERR "SUBST_CONV" "";
 *---------------------------------------------------------------------------*)

fun SUBST_CONV theta template tm =
  let fun retheta {redex,residue} = (redex |-> genvar(type_of redex))
      val theta0 = map retheta theta
      val theta1 = map (op |-> o (#residue ## #residue)) (zip theta0 theta)
  in
   SUBST theta1 (mk_eq(tm,subst theta0 template)) (REFL tm)
  end
  handle HOL_ERR _ => raise ERR "SUBST_CONV" "";


(*---------------------------------------------------------------------------
 * Extensionality
 *
 *     A |- !x. t1 x = t2 x
 *    ----------------------     (x not free in A, t1 or t2)
 *        A |- t1 = t2
 *
 * fun EXT th =
 *  let val {Bvar,Body} = dest_forall(concl th)
 *      val {lhs,rhs} = dest_eq Body
 *      val {Rator=Rator1, Rand=v1} = dest_comb lhs
 *      val {Rator=Rator2, Rand=v2} = dest_comb rhs
 *      val fv = union (free_vars Rator1) (free_vars Rator2)
 *      val _ = thm_assert (not(mem Bvar fv) andalso
 *                          (Bvar=v1) andalso (Bvar=v2))  "" ""
 *    in make_thm Count.Ext(tag th, hyp th, mk_eq{lhs=Rator1, rhs=Rator2})
 *    end
 *    handle _ => THM_ERR "EXT" "";
 *---------------------------------------------------------------------------*)

fun EXT th =
   let val (Bvar,_) = dest_forall(concl th)
       val th1 = SPEC Bvar th
       (* th1 = |- t1 x = t2 x *)
       val (t1x, t2x) = dest_eq(concl th1)
       val x = rand t1x
       val th2 = ABS x th1
       (* th2 = |- (\x. t1 x) = (\x. t2 x) *)
   in
   TRANS (TRANS(SYM(ETA_CONV (mk_abs(x, t1x)))) th2)
         (ETA_CONV (mk_abs(x,t2x)))
   end
   handle HOL_ERR _ => raise ERR "EXT" "";


(*---------------------------------------------------------------------------
 * Type extensionality
 *
 *     A |- !:a. t1 [:a:] = t2 [:a:]
 *    -------------------------------     (a not free in A, t1 or t2)
 *             A |- t1 = t2
 *
 * fun TY_EXT th =
 *  let val {Bvar,Body} = dest_tyforall(concl th)
 *      val {lhs,rhs} = dest_eq Body
 *      val {Rator=Rator1, Rand=v1} = dest_tycomb lhs
 *      val {Rator=Rator2, Rand=v2} = dest_tycomb rhs
 *      val fv = union (type_vars Rator1) (type_vars Rator2)
 *      val _ = thm_assert (not(mem Bvar fv) andalso
 *                          (Bvar=v1) andalso (Bvar=v2))  "" ""
 *    in make_thm Count.TyExt(tag th, hyp th, mk_eq{lhs=Rator1, rhs=Rator2})
 *    end
 *    handle _ => THM_ERR "TY_EXT" "";
 *---------------------------------------------------------------------------*)

fun TY_EXT th =
   let val (Bvar,_) = dest_tyforall(concl th)
       val th1 = TY_SPEC Bvar th
       (* th1 = |- t1 [:a:] = t2 [:a:] *)
       val (t1x, t2x) = dest_eq(concl th1)
       val x = snd(dest_tycomb t1x)
       val th2 = TY_ABS x th1
       (* th2 = |- (\:a. t1 [:a:]) = (\:a. t2 [:a:]) *)
   in
   TRANS (TRANS(SYM(TY_ETA_CONV (mk_tyabs(x, t1x)))) th2)
         (TY_ETA_CONV (mk_tyabs(x,t2x)))
   end
   handle HOL_ERR _ => raise ERR "TY_EXT" "";


(*---------------------------------------------------------------------------
 *       A |- !x. (t1 = t2)
 *     ----------------------
 *     A |- (\x.t1) = (\x.t2)
 *
 * fun MK_ABS th =
 *    let val {Bvar,Body} = dest_forall(concl th)
 *        val {lhs,rhs} = dest_eq Body
 *    in
 *    make_thm Count.MkAbs(tag th, hyp th,
 *                 mk_eq{lhs=mk_abs{Bvar=Bvar, Body=lhs},
 *                       rhs=mk_abs{Bvar=Bvar, Body=rhs}})
 *    end
 *    handle _ => THM_ERR"MK_ABS" "";
 *---------------------------------------------------------------------------*)

fun MK_ABS qth =
   let val (Bvar,Body) = dest_forall (concl qth)
       val ufun = mk_abs(Bvar, lhs Body)
       and vfun = mk_abs(Bvar, rhs Body)
       val gv = genvar (type_of Bvar)
   in
    EXT (GEN gv
     (TRANS (TRANS (BETA_CONV (mk_comb(ufun,gv))) (SPEC gv qth))
	    (SYM (BETA_CONV (mk_comb(vfun,gv))))))
   end
   handle HOL_ERR _ => raise ERR"MK_ABS" "";


(*---------------------------------------------------------------------------
 *        A |- !:a. (t1 = t2)
 *     ------------------------
 *     A |- (\:a.t1) = (\:a.t2)
 *
 * fun MK_TY_ABS th =
 *    let val {Bvar,Body} = dest_tyforall(concl th)
 *        val {lhs,rhs} = dest_eq Body
 *    in
 *    make_thm Count.MkTyAbs(tag th, hyp th,
 *                 mk_eq{lhs=mk_tyabs{Bvar=Bvar, Body=lhs},
 *                       rhs=mk_tyabs{Bvar=Bvar, Body=rhs}})
 *    end
 *    handle _ => THM_ERR"MK_TY_ABS" "";
 *---------------------------------------------------------------------------*)

fun MK_TY_ABS qth =
   let val (Bvar,Body) = dest_tyforall (concl qth)
       val ufun = mk_tyabs(Bvar, lhs Body)
       and vfun = mk_tyabs(Bvar, rhs Body)
       val gv = gen_tyopvar (kind_of Bvar, rank_of Bvar)
   in
    TY_EXT (TY_GEN gv
     (TRANS (TRANS (TY_BETA_CONV (mk_tycomb(ufun,gv))) (TY_SPEC gv qth))
	    (SYM (TY_BETA_CONV (mk_tycomb(vfun,gv))))))
   end
   handle HOL_ERR _ => raise ERR"MK_TY_ABS" "";


(*---------------------------------------------------------------------------
 *  Contradiction rule
 *
 *   A |- F
 *   ------
 *   A |- t
 *
 * fun CONTR w fth =
 *    (thm_assert ((type_of w = bool) andalso
 *                 (concl fth = mk_const{Name="F",Ty=bool})) "CONTR" "";
 *     make_thm Count.Contr(tag fth, hyp fth, w))
 *---------------------------------------------------------------------------*)

fun CONTR tm th =
  MP (SPEC tm FALSITY) th handle HOL_ERR _ => raise ERR "CONTR" "";

(*---------------------------------------------------------------------------
 *  Undischarging
 *
 *   A |- t1 ==> t2
 *   -------------
 *    A, t1 |- t2
 *---------------------------------------------------------------------------*)

fun UNDISCH th =
  MP th (ASSUME(fst(dest_imp(concl th))))
  handle HOL_ERR  _ => raise ERR "UNDISCH" "";

(*---------------------------------------------------------------------------
 * =T elimination
 *
 *   A |- t = T
 *  ------------
 *    A |- t
 *---------------------------------------------------------------------------*)

fun EQT_ELIM th =
  EQ_MP (SYM th) TRUTH handle HOL_ERR _ => raise ERR "EQT_ELIM" "";


(*---------------------------------------------------------------------------
 *
 *      |- !x1 ... xn. t[xi]
 *    --------------------------	SPECL [t1; ...; tn]
 *          |-  t[ti]
 *---------------------------------------------------------------------------*)

fun SPECL tml th =
  rev_itlist SPEC tml th handle HOL_ERR _ => raise ERR"SPECL" "";

(*---------------------------------------------------------------------------
 *
 *      |- !x1 ... xn. t[xi]
 *    --------------------------	TY_SPECL [t1; ...; tn]
 *          |-  t[ti]
 *---------------------------------------------------------------------------*)

fun TY_SPECL tyl th =
  rev_itlist TY_SPEC tyl th handle HOL_ERR _ => raise ERR "TY_SPECL" "";

(*---------------------------------------------------------------------------
 *
 *          |- t[xi]
 *    --------------------------	TY_GENL [t1; ...; tn]
 *      |-  !x1 ... xn. t[ti]
 *---------------------------------------------------------------------------*)

fun TY_GENL tyl th =
  itlist TY_SPEC tyl th handle HOL_ERR _ => raise ERR "TY_GENL" "";


(*---------------------------------------------------------------------------
 * SELECT introduction
 *
 *    A |- P t
 *  -----------------
 *   A |- P($@ P)
 *---------------------------------------------------------------------------*)

fun SELECT_INTRO th =
 let val (Rator, Rand) = dest_comb(concl th)
     val SELECT_AX' = INST_TYPE [alpha |-> type_of Rand] SELECT_AX
 in
   MP (SPEC Rand (SPEC Rator SELECT_AX')) th
 end
 handle HOL_ERR _ => raise ERR "SELECT_INTRO" ""



(* ----------------------------------------------------------------------
    SELECT elimination (cases)

     A1 |- P($@ P)          A2, "P v" |- t
    ------------------------------------------ (v occurs nowhere else in th2)
                A1 u A2 |- t

    In line with the documentation in REFERENCE, this function succeeds even
    if v occurs in t (giving a rather useless result).  It also succeeds no
    matter what the rand of the conclusion of th1 is.

   ---------------------------------------------------------------------- *)

fun SELECT_ELIM th1 (v,th2) =
  let val (Rator, Rand) = dest_comb(concl th1)
      val th3 = DISCH (mk_comb(Rator, v)) th2
      (* th3 = |- P v ==> t *)
  in
  MP (SPEC Rand (GEN v th3)) th1
  end
  handle HOL_ERR _ => raise ERR "SELECT_ELIM" "";


(*---------------------------------------------------------------------------
 * SELECT introduction
 *
 *    A |- ?x. t[x]
 *  -----------------
 *   A |- t[@x.t[x]]
 *---------------------------------------------------------------------------*)

fun SELECT_RULE th =
   let val (tm as (Bvar,Body)) = dest_exists(concl th)
       val v = genvar(type_of Bvar)
       val P = mk_abs (Bvar,Body)
       val SELECT_AX' = INST_TYPE [alpha |-> type_of Bvar] SELECT_AX
       val th1 = SPEC v (SPEC P SELECT_AX')
       val (ant,conseq) = dest_imp(concl th1)
       val th2 = BETA_CONV ant
       and th3 = BETA_CONV conseq
       val th4 = EQ_MP th3 (MP th1 (EQ_MP(SYM th2) (ASSUME (rhs(concl th2)))))
   in
     CHOOSE (v,th) th4
   end
   handle HOL_ERR _ => raise ERR "SELECT_RULE" ""


(*---------------------------------------------------------------------------
 * ! abstraction
 *
 *          A |- t1 = t2
 *     -----------------------
 *      A |- (!x.t1) = (!x.t2)
 *---------------------------------------------------------------------------*)

fun FORALL_EQ x =
  let val forall = AP_TERM (inst [alpha |-> type_of x] boolSyntax.universal)
  in fn th => forall (ABS x th)
  end
  handle HOL_ERR _ => raise ERR "FORALL_EQ" "";


(*---------------------------------------------------------------------------
 * !: abstraction
 *
 *           A |- t1 = t2
 *     --------------------------
 *      A |- (!:a.t1) = (!:a.t2)
 *---------------------------------------------------------------------------*)

fun TY_FORALL_EQ a =
  let val tyforall = AP_TERM boolSyntax.ty_universal
  in fn th => tyforall (TY_ABS a th)
  end
  handle HOL_ERR _ => raise ERR "TY_FORALL_EQ" "";


(*---------------------------------------------------------------------------
 * ? abstraction
 *
 *          A |- t1 = t2
 *     -----------------------
 *      A |- (?x.t1) = (?x.t2)
 *---------------------------------------------------------------------------*)

fun EXISTS_EQ x =
  let val exists = AP_TERM (inst [alpha |-> type_of x] boolSyntax.existential)
   in fn th => exists (ABS x th)
   end
   handle HOL_ERR _ => raise ERR "EXISTS_EQ" "";


(*---------------------------------------------------------------------------
 * ?: abstraction
 *
 *           A |- t1 = t2
 *     --------------------------
 *      A |- (?:a.t1) = (?:a.t2)
 *---------------------------------------------------------------------------*)

fun TY_EXISTS_EQ a =
  let val tyexists = AP_TERM boolSyntax.ty_existential
   in fn th => tyexists (TY_ABS a th)
   end
   handle HOL_ERR _ => raise ERR "TY_EXISTS_EQ" "";


(*---------------------------------------------------------------------------
 * @ abstraction
 *
 *          A |- t1 = t2
 *     -----------------------
 *      A |- (@x.t1) = (@x.t2)
 *---------------------------------------------------------------------------*)

fun SELECT_EQ x =
 let val ty = type_of x
     val choose = inst [alpha |-> ty] boolSyntax.select
 in fn th => AP_TERM choose (ABS x th)
 end
 handle HOL_ERR _ => raise ERR "SELECT_EQ" "";


(*---------------------------------------------------------------------------
 * Beta-conversion to the rhs of an equation
 *
 *   A |- t1 = (\x.t2)t3
 *  --------------------
 *   A |- t1 = t2[t3/x]
 *---------------------------------------------------------------------------*)

fun RIGHT_BETA th =
 TRANS th (BETA_CONV(rhs(concl th)))
 handle HOL_ERR _ => raise ERR "RIGHT_BETA" "";


(*---------------------------------------------------------------------------
 * Type beta-conversion to the rhs of an equation
 *
 *   A |- t1 = (\:a.t2) [:ty:]
 *  --------------------
 *   A |- t1 = t2[ty/a]
 *---------------------------------------------------------------------------*)

fun RIGHT_TY_BETA th =
 TRANS th (TY_BETA_CONV(rhs(concl th)))
 handle HOL_ERR _ => raise ERR "RIGHT_TY_BETA" "";

(*---------------------------------------------------------------------------
 *  "(\x1 ... xn.t)t1 ... tn" -->
 *    |- (\x1 ... xn.t)t1 ... tn = t[t1/x1] ... [tn/xn]
 *---------------------------------------------------------------------------*)

fun LIST_BETA_CONV tm =
   let val (Rator,Rand) = dest_comb tm
   in RIGHT_BETA (AP_THM (LIST_BETA_CONV Rator) Rand)
   end handle HOL_ERR _ => REFL tm;

(*---------------------------------------------------------------------------
 *  "(\:a1 ... an.t) [:ty1, ... tyn:]" -->
 *    |- (\:a1 ... an.t) [:ty1, ... tyn:] = t[ty1/a1] ... [tyn/an]
 *---------------------------------------------------------------------------*)

fun LIST_TY_BETA_CONV tm =
   let val (Rator,Rand) = dest_tycomb tm
   in RIGHT_TY_BETA (TY_COMB (LIST_TY_BETA_CONV Rator) Rand)
   end handle HOL_ERR _ => REFL tm;


fun RIGHT_LIST_BETA th = TRANS th (LIST_BETA_CONV(rhs(concl th)))

fun RIGHT_LIST_TY_BETA th = TRANS th (LIST_TY_BETA_CONV(rhs(concl th)))


(*---------------------------------------------------------------------------
 * let CONJUNCTS_CONV (t1,t2) =
 *  letrec CONJUNCTS th =
 *   (CONJUNCTS (CONJUNCT1 th) @ CONJUNCTS (CONJUNCT2 th)) ? [th]
 *  in
 *  letrec build_conj thl t =
 *   (let l,r = dest_conj t
 *    in  CONJ (build_conj thl l) (build_conj thl r)
 *   )
 *   ? find (\th. (concl th) = t) thl
 *  in
 *   (IMP_ANTISYM_RULE
 *     (DISCH t1 (build_conj (CONJUNCTS (ASSUME t1)) t2))
 *     (DISCH t2 (build_conj (CONJUNCTS (ASSUME t2)) t1))
 *   ) ? failwith `CONJUNCTS_CONV`;;
 *---------------------------------------------------------------------------*)

fun CONJUNCTS_CONV (t1,t2) =
   let fun CONJUNCTS th = (CONJUNCTS (CONJUNCT1 th) @ CONJUNCTS (CONJUNCT2 th))
             handle HOL_ERR _ => [th]
       fun build_conj thl t =
          let val (conj1,conj2) = dest_conj t
           in  CONJ (build_conj thl conj1) (build_conj thl conj2)
          end
          handle HOL_ERR _ => first (fn th => (concl th) = t) thl
   in
   IMP_ANTISYM_RULE (DISCH t1 (build_conj (CONJUNCTS (ASSUME t1)) t2))
                    (DISCH t2 (build_conj (CONJUNCTS (ASSUME t2)) t1))
   end
   handle HOL_ERR _ => raise ERR "CONJUNCTS_CONV" "";

(*---------------------------------------------------------------------------*
 * let CONJ_SET_CONV l1 l2 =                                                 *
 *  CONJUNCTS_CONV (list_mk_conj l1, list_mk_conj l2)                        *
 *  ? failwith `CONJ_SET_CONV`;;                                             *
 *---------------------------------------------------------------------------*)

fun CONJ_SET_CONV l1 l2 =
   CONJUNCTS_CONV (list_mk_conj l1, list_mk_conj l2)
   handle HOL_ERR _ => raise ERR "CONJ_SET_CONV" "";

(*---------------------------------------------------------------------------
 * let FRONT_CONJ_CONV tml t =
 *  letrec remove x l =
 *     if ((hd l) = x)
 *     then tl l
 *     else (hd l).(remove x (tl l))
 *  in
 *  (CONJ_SET_CONV tml (t.(remove t tml)))
 *  ? failwith `FRONT_CONJ_CONV`;;
 *---------------------------------------------------------------------------*)

fun FRONT_CONJ_CONV tml t =
   let fun remove x l = if (hd l = x) then tl l else (hd l::remove x (tl l))
   in CONJ_SET_CONV tml (t::remove t tml)
   end handle HOL_ERR _ => raise ERR "FRONT_CONJ_CONV" "";

(*---------------------------------------------------------------------------
 *   |- (t1 /\ ... /\ t /\ ... /\ tn) = (t /\ t1 /\ ... /\ tn)
 *
 * local
 * val APP_AND = AP_TERM(--`/\`--)
 * in
 * fun FRONT_CONJ_CONV tml t =
 *    if (t = hd tml)
 *    then REFL(list_mk_conj tml)
 *    else if ((null(tl(tl tml)) andalso (t = hd(tl tml))))
 *         then SPECL tml CONJ_SYM
 *         else let val th1 = APP_AND (FRONT_CONJ_CONV (tl tml) t)
 *                  val {conj1,conj2} = dest_conj(rhs(concl th1))
 *                  val {conj1 = c2, conj2 = c3} = dest_conj conj2
 *                  val th2 = AP_THM(APP_AND (SPECL[conj1,c2]CONJ_SYM)) c3
 *              in
 *              TRANS (TRANS (TRANS th1 (SPECL[conj1,c2,c3]CONJ_ASSOC)) th2)
 *                    (SYM(SPECL[c2,conj1,c3]CONJ_ASSOC))
 *              end
 *              handle _ => raise ERR{function = "FRONT_CONJ_CONV",
 *                                          message = ""}
 * end;
 *---------------------------------------------------------------------------*)

(*---------------------------------------------------------------------------
 * |- (t1 /\ ... /\ tn) = (t1' /\ ... /\ tn') where {t1,...,tn}={t1',...,tn'}
 *
 * The genuine derived rule below only works if its argument
 * lists are the same length.
 *
 * fun CONJ_SET_CONV l1 l2 =
 *    if (l1 = l2)
 *    then REFL(list_mk_conj l1)
 *   else if (hd l1 = hd l2)
 *        then AP_TERM (--`$/\ ^(hd l1)`--) (CONJ_SET_CONV(tl l1)(tl l2))
 *        else let val th1 = SYM(FRONT_CONJ_CONV l2 (hd l1))
 *                 val l2' = conjuncts(lhs(concl th1))
 *                 val th2 = AP_TERM (--`$/\ ^(hd l1)`--)
 *                                   (CONJ_SET_CONV(tl l1)(tl l2'))
 *             in
 *             TRANS th2 th1
 *             end
 *             handle _ => raise ERR{function = "CONJ_SET_CONV",
 * 		                        message = ""};
 *
 * fun CONJ_SET_CONV l1 l2 =
 *   (if (set_eq l1 l2)
 *    then mk_drule_thm([],mk_eq{lhs = list_mk_conj l1, rhs = list_mk_conj l2})
 *    else raise ERR{function = "CONJ_SET_CONV",message = ""})
 *    handle _ => raise ERR{function = "CONJ_SET_CONV",message = ""};
 *---------------------------------------------------------------------------*)


(*---------------------------------------------------------------------------
 * |- t1 = t2  if t1 and t2 are equivalent using idempotence, symmetry and
 *                associativity of /\. I have not (yet) coded a genuine
 *                derivation - it would be straightforward, but tedious.
 *
 * fun CONJUNCTS_CONV(t1,t2) =
 *    if (set_eq (strip_conj t1)(strip_conj t2))
 *    then mk_drule_thm([],mk_eq{lhs = t1, rhs = t2})
 *    else raise ERR{function = "CONJUNCTS_CONV",message = ""};
 *---------------------------------------------------------------------------*)

(*---------------------------------------------------------------------------
 *           A,t |- t1 = t2
 *    -----------------------------
 *      A |- (t /\ t1) = (t /\ t2)
 *---------------------------------------------------------------------------*)

fun CONJ_DISCH t th =
   let val (lhs,rhs) = dest_eq(concl th)
       and th1 = DISCH t th
       val left_t  = mk_conj(t,lhs)
       val right_t = mk_conj(t,rhs)
       val th2 = ASSUME left_t
       and th3 = ASSUME right_t
       val th4 = DISCH left_t
                       (CONJ (CONJUNCT1 th2)
                             (EQ_MP(MP th1 (CONJUNCT1 th2))
                                   (CONJUNCT2 th2)))
       and th5 = DISCH right_t
                       (CONJ (CONJUNCT1 th3)
                             (EQ_MP(SYM(MP th1 (CONJUNCT1 th3)))
                                   (CONJUNCT2 th3)))
   in
     IMP_ANTISYM_RULE th4 th5
   end;

(*---------------------------------------------------------------------------
 *                    A,t1,...,tn |- t = u
 *    --------------------------------------------------------
 *      A |- (t1 /\ ... /\ tn /\ t) = (t1 /\ ... /\ tn /\ u)
 *---------------------------------------------------------------------------*)

val CONJ_DISCHL = itlist CONJ_DISCH;


(*---------------------------------------------------------------------------
 *       A,t1 |- t2                A,t |- F
 *     --------------              --------
 *     A |- t1 ==> t2               A |- ~t
 *---------------------------------------------------------------------------*)

fun NEG_DISCH t th =
  (if concl th = boolSyntax.F
      then NOT_INTRO (DISCH t th) else DISCH t th)
  handle HOL_ERR _ => raise ERR "NEG_DISCH" ""


(*---------------------------------------------------------------------------
 *    A |- ~(t1 = t2)
 *   -----------------
 *    A |- ~(t2 = t1)
 *---------------------------------------------------------------------------*)

local fun flip (lhs,rhs) = (rhs, lhs)
in
fun NOT_EQ_SYM th =
   let val t = (mk_eq o flip o dest_eq o dest_neg o concl) th
   in MP (SPEC t IMP_F) (DISCH t (MP th (SYM(ASSUME t))))
   end
end;


(* ---------------------------------------------------------------------*)
(* EQF_INTRO: inference rule for introducing equality with "F".		*)
(*									*)
(* 	         ~tm							*)
(*	     -----------    EQF_INTRO					*)
(*	        tm = F							*)
(*									*)
(* [TFM 90.05.08]							*)
(* ---------------------------------------------------------------------*)

local val Fth = ASSUME F
in
fun EQF_INTRO th =
   IMP_ANTISYM_RULE (NOT_ELIM th)
                    (DISCH F (CONTR (dest_neg (concl th)) Fth))
   handle HOL_ERR _ => raise ERR "EQF_INTRO" ""
end;

(* ---------------------------------------------------------------------*)
(* EQF_ELIM: inference rule for eliminating equality with "F".		*)
(*									*)
(*	      |- tm = F							*)
(*	     -----------    EQF_ELIM					*)
(* 	       |- ~ tm							*)
(*									*)
(* [TFM 90.08.23]							*)
(* ---------------------------------------------------------------------*)

fun EQF_ELIM th =
   let val (lhs,rhs) = dest_eq(concl th)
       val _ = assert (equal boolSyntax.F) rhs
   in NOT_INTRO(DISCH lhs (EQ_MP th (ASSUME lhs)))
   end
   handle HOL_ERR _ => raise ERR "EQF_ELIM" ""



(* ---------------------------------------------------------------------*)
(* ISPEC: specialization, with type instantation if necessary.		*)
(*									*)
(*     A |- !x:ty.tm							*)
(*  -----------------------   ISPEC "t:ty'" 				*)
(*      A |- tm[t/x]							*)
(*									*)
(* (where t is free for x in tm, and ty' is an instance of ty)		*)
(* ---------------------------------------------------------------------*)

fun ISPEC t th =
   let val (Bvar,_) = dest_forall(concl th) handle HOL_ERR _
                      => raise ERR"ISPEC"
                           "input theorem not universally quantified"
       val (_,inst,kd_inst,rk) = kind_match_term Bvar t handle HOL_ERR _
                      => raise ERR "ISPEC"
                           "can't type-instantiate input theorem"
       val ith = INST_TYPE inst (INST_KIND kd_inst (INST_RANK rk th))
                    handle HOL_ERR {message,...}
                      => raise ERR "ISPEC"
                           ("failed to type-instantiate input theorem:\n" ^ message)
   in SPEC t ith handle HOL_ERR _
         => raise ERR "ISPEC" ": type variable free in assumptions"
   end;

(* ---------------------------------------------------------------------*)
(* ISPECL: iterated specialization, with type instantiation if necessary.*)
(*									*)
(*        A |- !x1...xn.tm						*)
(*  ---------------------------------   ISPECL ["t1",...,"tn"]		*)
(*      A |- tm[t1/x1,...,tn/xn]					*)
(*									*)
(* (where ti is free for xi in tm)					*)
(*                                                                      *)
(* Note: the following is simpler but it DOESN'T WORK.                  *)
(*                                                                      *)
(*  fun ISPECL tms th = rev_itlist ISPEC tms th                         *)
(*                                                                      *)
(* ---------------------------------------------------------------------*)

local fun strip [] _ = []     (* Returns a list of (pat,ob) pairs. *)
        | strip (tm::tml) M =
            let val (Bvar,Body) = dest_forall M
            in (type_of Bvar,type_of tm)::strip tml Body   end
      fun kd_merge [] theta = theta
        | kd_merge ((x as {redex,residue})::rst) theta =
          case subst_assoc (equal redex) theta
           of NONE      => x::kd_merge rst theta
            | SOME rdue => if residue=rdue then kd_merge rst theta
                           else raise ERR "ISPECL" ""
      fun merge [] theta = theta
        | merge ((x as {redex,residue})::rst) theta =
          case subst_assoc (equal redex) theta
           of NONE      => x::merge rst theta
            | SOME rdue => if abconv_ty residue rdue then merge rst theta
                           else raise ERR "ISPECL" ""
in
fun ISPECL [] = I
  | ISPECL [tm] = ISPEC tm
  | ISPECL tms = fn th =>
     let val pairs = strip tms (concl th) handle HOL_ERR _
                     => raise ERR "ISPECL" "list of terms too long for theorem"
         val (rk,kd_theta,ty_theta) =
             rev_itlist (fn (pat,ob) => fn (rk,kd_theta,ty_theta) =>
                      let val (rk',kd_theta',ty_theta') = Type.kind_match_type pat ob
                      in (Int.max(rk, rk'), kd_merge kd_theta' kd_theta, merge ty_theta' ty_theta)
                      end) pairs (0,[],[])
                      handle HOL_ERR _ => raise ERR "ISPECL"
                              "can't type-instantiate input theorem"
     in SPECL tms (INST_TYPE ty_theta (INST_KIND kd_theta (INST_RANK rk th))) handle HOL_ERR _
        => raise ERR "ISPECL" "type variable or kind variable free in assumptions"
     end
end;


(*---------------------------------------------------------------------------
 * Generalise a theorem over all variables free in conclusion but not in hyps
 *
 *         A |- t[x1,...,xn]
 *    ----------------------------
 *     A |- !x1...xn.t[x1,...,xn]
 *---------------------------------------------------------------------------*)

fun GEN_ALL th =
   HOLset.foldl (fn (v, th) => GEN v th)
       th
      (HOLset.difference (FVL [concl th] empty_tmset, hyp_frees th))


(*---------------------------------------------------------------------------
 * Generalise a theorem over all type variables free in conclusion but not in hyps
 *
 *         A |- t[a1,...,an]
 *    ----------------------------                 TY_GEN_ALL
 *     A |- !:a1...an.t[a1,...,an]
 *---------------------------------------------------------------------------*)

fun TY_GEN_ALL th =
   HOLset.foldl (fn (v, th) => TY_GEN v th)
       th
      (HOLset.difference (HOLset.addList(empty_tyset, type_vars_in_term(concl th)), hyp_tyvars th))


(*---------------------------------------------------------------------------
 *  Discharge all hypotheses
 *
 *       t1, ... , tn |- t
 *  -------------------------------
 *    |- t1 ==> ... ==> tn ==> t
 *
 * You can write a simpler version using "itlist DISCH (hyp th) th", but this
 * may discharge two equivalent (alpha-convertible) assumptions.
 *---------------------------------------------------------------------------*)

fun DISCH_ALL th =
    HOLset.foldl (fn (h, th) => DISCH h th) th (hypset th)

(*----------------------------------------------------------------------------
 *
 *    A |- t1 ==> ... ==> tn ==> t
 *  -------------------------------
 *       A, t1, ..., tn |- t
 *---------------------------------------------------------------------------*)

fun UNDISCH_ALL th = if is_imp(concl th) then UNDISCH_ALL (UNDISCH th) else th;


(* ---------------------------------------------------------------------*)
(* SPEC_ALL : thm -> thm						*)
(*									*)
(*     A |- !x1 ... xn. t[xi]						*)
(*    ------------------------   where the xi' are distinct 		*)
(*        A |- t[xi'/xi]	 and not free in the input theorem	*)
(*									*)
(* BUGFIX: added the "distinct" part and code to make the xi's not free *)
(* in the conclusion !x1...xn.t[xi].		        [TFM 90.10.04]	*)
(*									*)
(* OLD CODE:								*)
(* 									*)
(* let SPEC_ALL th =							*)
(*     let vars,() = strip_forall(concl th) in				*)
(*     SPECL (map (variant (freesl (hyp th))) vars) th;;		*)
(* ---------------------------------------------------------------------*)

local fun varyAcc v (V,l) =
       let val v' = prim_variant V v in (v'::V, v'::l) end
in
fun SPEC_ALL th =
    if is_forall (concl th) then let
        val (hvs,con) = (HOLset.listItems ## I) (hyp_frees th, concl th)
        val fvs = free_vars con
        val vars = fst(strip_forall con)
      in
        SPECL (snd(itlist varyAcc vars (hvs@fvs,[]))) th
      end
    else th
end;


(* ---------------------------------------------------------------------*)
(* TY_SPEC_ALL : thm -> thm						*)
(*									*)
(*     A |- !:a1 ... an. t[ai]						*)
(*    ------------------------   where the ai' are distinct typevars    *)
(*        A |- t[ai'/ai]	 and not free in the input theorem	*)
(*									*)
(* BUGFIX: added the "distinct" part and code to make the ai's not free *)
(* in the conclusion !a1...an.t[ai].		        [TFM 90.10.04]	*)
(* ---------------------------------------------------------------------*)

local fun varyAcc v (V,l) =
       let val v' = prim_variant_type V v in (v'::V, v'::l) end
in
fun TY_SPEC_ALL th =
    if is_tyforall (concl th) then let
        val (hvs,con) = (HOLset.listItems ## I) (hyp_tyvars th, concl th)
        val fvs = type_vars_in_term con
        val vars = fst(strip_tyforall con)
      in
        TY_SPECL (snd(itlist varyAcc vars (hvs@fvs,[]))) th
      end
    else th
end;


(*---------------------------------------------------------------------------
 * Use the conclusion of the first theorem to delete a hypothesis of
 *   the second theorem.
 *
 *    A |- t1 	B, t1 |- t2
 *    -----------------------
 *         A u B |- t2
 *---------------------------------------------------------------------------*)

fun PROVE_HYP ath bth =  MP (DISCH (concl ath) bth) ath;


(*---------------------------------------------------------------------------
 * A |- t1/\t2  ---> A |- t1, A |- t2
 *---------------------------------------------------------------------------*)

fun CONJ_PAIR th = (CONJUNCT1 th, CONJUNCT2 th)
                   handle HOL_ERR _ => raise ERR "CONJ_PAIR" "";


(*---------------------------------------------------------------------------
 * ["A1|-t1"; ...; "An|-tn"]  ---> "A1u...uAn|-t1 /\ ... /\ tn", where n>0
 *---------------------------------------------------------------------------*)

val LIST_CONJ = end_itlist CONJ ;


(*---------------------------------------------------------------------------
 * "A |- t1 /\ (...(... /\ tn)...)"
 *   --->
 *   [ "A|-t1"; ...; "A|-tn"],  where n>0
 *
 * Inverse of LIST_CONJ : flattens only right conjuncts.
 * You must specify n, since tn could itself be a conjunction
 *---------------------------------------------------------------------------*)

fun CONJ_LIST 1 th = [th]
  | CONJ_LIST n th =  CONJUNCT1 th :: CONJ_LIST (n-1) (CONJUNCT2 th)
      handle HOL_ERR _ => raise ERR "CONJ_LIST" "";


(*---------------------------------------------------------------------------
 * "A |- t1 /\ ... /\ tn"   --->  [ "A|-t1"; ...; "A|-tn"],  where n>0
 *
 * Flattens out all conjuncts, regardless of grouping
 *---------------------------------------------------------------------------*)

fun CONJUNCTS th = (CONJUNCTS (CONJUNCT1 th) @
                    CONJUNCTS(CONJUNCT2 th)) handle HOL_ERR _ => [th];

(*---------------------------------------------------------------------------
 * "|- !x. (t1 /\ ...) /\ ... (!y. ... /\ tn)"
 *   --->  [ "|-t1"; ...; "|-tn"],  where n>0
 *
 * Flattens out conjuncts even in bodies of forall's
 *---------------------------------------------------------------------------*)

fun BODY_CONJUNCTS th =
   if is_forall (concl th)
   then BODY_CONJUNCTS (SPEC_ALL th)
   else if is_conj (concl th)
        then (BODY_CONJUNCTS (CONJUNCT1 th) @ BODY_CONJUNCTS (CONJUNCT2 th))
        else [th];

(*---------------------------------------------------------------------------
 * Put a theorem
 *
 *       |- !x. t1 ==> !y. t2 ==> ... ==> tm ==>  t
 *
 * into canonical form by stripping out quantifiers and splitting
 * conjunctions apart.
 *
 * 	t1 /\ t2	--->		t1,   t2
 *      (t1/\t2)==>t	--->		t1==> (t2==>t)
 *      (t1\/t2)==>t	--->		t1==>t, t2==>t
 *      (?x.t1)==>t2	--->		t1[x'/x] ==> t2
 *      !x.t1		--->		t1[x'/x]
 *      (?x.t1)==>t2    --->            t1[x'/x] ==> t2)
 *---------------------------------------------------------------------------*)

fun IMP_CANON th =
 let val w = concl th
 in if is_forall w then IMP_CANON (SPEC_ALL th) else
    if is_conj w then IMP_CANON(CONJUNCT1 th) @ IMP_CANON(CONJUNCT2 th) else
    if is_imp w
    then let val (ant,_) = dest_imp w
         in if is_conj ant
            then let val (conj1,conj2) = dest_conj ant
                 in IMP_CANON (DISCH conj1 (DISCH conj2
                        (MP th (CONJ(ASSUME conj1)(ASSUME conj2)))))
                 end
            else
            if is_disj ant
            then let val (disj1,disj2) = dest_disj ant
                 in IMP_CANON(DISCH disj1 (MP th (DISJ1(ASSUME disj1) disj2)))
                    @
                    IMP_CANON(DISCH disj2 (MP th (DISJ2 disj1 (ASSUME disj2))))
                 end
            else
            if is_exists ant
            then let val (Bvar,Body) = dest_exists ant
                     val bv' = variant (thm_frees th) Bvar
                     val body' = subst [Bvar |-> bv'] Body
                 in IMP_CANON (DISCH body'
                        (MP th (EXISTS(ant, bv') (ASSUME body'))))
                 end
            else map (DISCH ant) (IMP_CANON (UNDISCH th))
         end
    else [th]
   end;


(*---------------------------------------------------------------------------
 *  A1 |- t1   ...   An |- tn      A |- t1==>...==>tn==>t
 *   -----------------------------------------------------
 *            A u A1 u ... u An |- t
 *---------------------------------------------------------------------------*)

val LIST_MP  = rev_itlist (fn x => fn y => MP y x) ;


(*---------------------------------------------------------------------------
 *      A |-t1 ==> t2
 *    -----------------
 *    A |-  ~t2 ==> ~t1
 *
 * Rewritten by MJCG to return "~t2 ==> ~t1" rather than "~t2 ==> t1 ==>F".
 *---------------------------------------------------------------------------*)

local val imp_th = GEN_ALL (el 5 (CONJUNCTS (SPEC_ALL IMP_CLAUSES)))
in
fun CONTRAPOS impth =
  let val (ant,conseq) = dest_imp (concl impth)
      val notb = mk_neg conseq
  in DISCH notb
      (EQ_MP (SPEC ant imp_th)
             (DISCH ant (MP (ASSUME notb)
                            (MP impth (ASSUME ant)))))
  end
  handle HOL_ERR _ => raise ERR "CONTRAPOS" ""
end;


(*---------------------------------------------------------------------------
 *      A |- t1 \/ t2
 *   --------------------
 *     A |-  ~ t1 ==> t2
 *
 *---------------------------------------------------------------------------*)

fun DISJ_IMP dth =
   let val (disj1,disj2) = dest_disj (concl dth)
       val nota = mk_neg disj1
   in DISCH nota
        (DISJ_CASES dth (CONTR disj2 (MP (ASSUME nota) (ASSUME disj1)))
                        (ASSUME disj2))
   end
   handle HOL_ERR _ => raise ERR "DISJ_IMP" "";


(*---------------------------------------------------------------------------
 *  A |- t1 ==> t2
 *  ---------------
 *   A |- ~t1 \/ t2
 *---------------------------------------------------------------------------*)

fun IMP_ELIM th =
   let val (ant,conseq) = dest_imp (concl th)
       val not_t1 = mk_neg ant
   in
   DISJ_CASES (SPEC ant EXCLUDED_MIDDLE)
              (DISJ2 not_t1 (MP th (ASSUME ant)))
              (DISJ1 (ASSUME not_t1) conseq)
   end
   handle HOL_ERR _ => raise ERR "IMP_ELIM" "";


(*---------------------------------------------------------------------------
 *  A |- t1 \/ t2     A1, t1 |- t3      A2, t2 |- t4
 *   ------------------------------------------------
 *                A u A1 u A2 |- t3 \/ t4
 *---------------------------------------------------------------------------*)

fun DISJ_CASES_UNION dth ath bth =
    DISJ_CASES dth (DISJ1 ath (concl bth)) (DISJ2 (concl ath) bth);


(*---------------------------------------------------------------------------
 *
 *       |- A1 \/ ... \/ An     [A1 |- M, ..., An |- M]
 *     ---------------------------------------------------
 *                           |- M
 *
 * The order of the theorems in the list doesn't matter: an operation akin
 * to sorting lines them up with the disjuncts in the theorem.
 *---------------------------------------------------------------------------*)

local 
 fun organize eq =    (* a bit slow - analogous to insertion sort *)
  let fun extract a alist =
       let fun ex(_,[]) = raise ERR "DISJ_CASESL.organize" "not a permutation.1"
             | ex(left,h::t) = if eq h a then (h,rev left@t) else ex(h::left,t)
       in ex ([],alist)
       end
       fun place [] [] = []
         | place (a::rst) alist =
             let val (item,next) = extract a alist
             in item::place rst next
             end
         | place _ _ = raise ERR "DISJ_CASESL.organize" "not a permutation.2"
  in place
  end
in
fun DISJ_CASESL disjth thl =
 let val (_,c) = dest_thm disjth
     fun eq th atm = HOLset.member(hypset th,  atm)
     val tml = strip_disj c
     fun DL th [] = raise ERR"DISJ_CASESL" "no cases"
       | DL th [th1] = PROVE_HYP th th1
       | DL th [th1,th2] = DISJ_CASES th th1 th2
       | DL th (th1::rst) = DISJ_CASES th th1
                               (DL(ASSUME(snd(dest_disj(concl th)))) rst)
 in DL disjth (organize eq tml thl)
end end;

(*---------------------------------------------------------------------------
 * Forward chain using an inference rule on top-level sub-parts of a theorem
 * Could be extended to handle other connectives
 * Commented out.
 *
 *fun SUB_CHAIN rule th =
 *   let val w = concl th
 *   in
 *   if (is_conj w)
 *   then CONJ (rule(CONJUNCT1 th)) (rule(CONJUNCT2 th))
 *   else if (is_disj w)
 *        then let val (a,b) = dest_disj w
 *             in
 *             DISJ_CASES_UNION th (rule (ASSUME a)) (rule (ASSUME b))
 *             end
 *        else if (is_imp w)
 *             then let val (a,b) = dest_imp w
 *                  in
 *                  DISCH a (rule (UNDISCH th))
 *                  end
 *             else if (is_forall w)
 *                  then let val (x', sth) = SPEC_VAR th in GEN x' (rule sth)
 *                       end
 *                  else th
 *   end;
 *
 *infix thenf orelsef;
 *fun f thenf g = fn x => g(f x);
 *fun f orelsef g = (fn x => (f x) handle _ => (g x));
 *
 *(* Repeatedly apply the rule (looping if it never fails) *)
 *fun REDEPTH_CHAIN rule x =
 *   (SUB_CHAIN (REDEPTH_CHAIN rule) thenf
 *    ((rule thenf (REDEPTH_CHAIN rule)) orelsef I))
 *   x;
 *
 *
 *(* Apply the rule no more than once in any one place *)
 *fun ONCE_DEPTH_CHAIN rule x =
 *   (rule  orelsef  SUB_CHAIN (ONCE_DEPTH_CHAIN rule))
 *   x;
 *
 *
 *(* "depth SPEC" : Specialize a theorem whose quantifiers are buried inside *)
 *fun DSPEC x = ONCE_DEPTH_CHAIN (SPEC x);
 *val DSPECL = rev_itlist DSPEC;
 *
 *val CLOSE_UP = GEN_ALL o DISCH_ALL;
 *---------------------------------------------------------------------------*)


(*---------------------------------------------------------------------------
 *     A |- !x. t1 x = t2
 *     ------------------
 *      A |-  t1 = \x.t2
 *
 * fun HALF_MK_ABS qth =
 *   let val {Bvar,Body} = dest_forall (concl qth)
 *       val t = rhs Body
 *       and gv = genvar (type_of Bvar)
 *       val tfun = mk_abs{Bvar = Bvar, Body = t}
 *   in
 *   EXT (GEN gv 		(* |- !gv. u gv =< (\x.t) gv  *)
 *	 (TRANS (SPEC gv qth)
 *                (SYM (BETA_CONV (mk_comb{Rator = tfun, Rand = gv})))))
 *   end
 *   handle _ => raise ERR{function = "HALF_MK_ABS",message = ""};
 *---------------------------------------------------------------------------*)


(*---------------------------------------------------------------------------
 * Rename the bound variable of a lambda-abstraction
 *
 *       "x"   "(\y.t)"   --->   |- "\y.t = \x. t[x/y]"
 *
 *---------------------------------------------------------------------------*)

fun ALPHA_CONV x t = let
  (* avoid calling dest_abs *)
  val (dty, _) = dom_rng (type_of t)
                 handle HOL_ERR _ =>
                        raise ERR "ALPHA_CONV" "Second term not an abstraction"
  val (xstr, xty) = with_exn dest_var x
                      (ERR "ALPHA_CONV" "First term not a variable")
  val _ = Type.compare(dty, xty) = EQUAL
          orelse raise ERR "ALPHA_CONV"
                           "Type of variable not compatible with abstraction"
  val t' = rename_bvar xstr t
in
  ALPHA t t'
end


(*---------------------------------------------------------------------------
 * Rename the bound variable of a lambda type-abstraction
 *
 *       "'a"   "(\:'b.t)"   --->   |- "\:'b.t = \:'a. t['a/'b]"
 *
 *---------------------------------------------------------------------------*)

fun TY_ALPHA_CONV x t = let
  (* avoid calling dest_tyabs *)
  val (dty, _) = dest_univ_type (type_of t)
                 handle HOL_ERR _ =>
                        raise ERR "TY_ALPHA_CONV" "Term is not a type abstraction"
  val (xstr, xkd, xrk) = with_exn dest_vartype_opr x
                      (ERR "TY_ALPHA_CONV" "Type is not a type variable")
  val _ = Kind.kind_compare(kind_of dty, xkd) = EQUAL
          orelse raise ERR "TY_ALPHA_CONV"
                           "Kind of type variable not compatible with type abstraction"
  val _ = rank_of dty = xrk
          orelse raise ERR "TY_ALPHA_CONV"
                           "Rank of type variable not compatible with type abstraction"
  val t' = rename_btyvar xstr t
in
  ALPHA t t'
end

(*----------------------------------------------------------------------------
 * Version of  ALPHA_CONV that renames "x" when necessary, but then it doesn't
 * meet the specification. Is that really a problem? Notice that this version
 * of ALPHA_CONV is more efficient.
 *
 *fun ALPHA_CONV x t =
 *  if Term.free_in x t
 *  then ALPHA_CONV (variant (free_vars t) x) t
 *  else ALPHA t (mk_abs{Bvar = x,
 *                       Body = Term.beta_conv(mk_comb{Rator = t,Rand = x})});
 *---------------------------------------------------------------------------*)

(*---------------------------------------------------------------------------
 * Rename bound variables
 *
 *       "x"   "(\y.t)"   --->    |- "\y.t  = \x. t[x/y]"
 *       "x"   "(!y.t)"   --->    |- "!y.t  = !x. t[x/y]"
 *       "x"   "(?y.t)"   --->    |- "?y.t  = ?x. t[x/y]"
 *       "x"   "(?!y.t)"  --->    |- "?!y.t = ?!x. t[x/y]"
 *       "x"   "(@y.t)"   --->    |- "@y.t  = @x. t[x/y]"
 *---------------------------------------------------------------------------*)

fun GEN_ALPHA_CONV x t =
   if is_abs t
   then ALPHA_CONV x t
   else let val (Rator, Rand) = dest_comb t
        in AP_TERM Rator (ALPHA_CONV x Rand)
        end
        handle HOL_ERR _ => raise ERR "GEN_ALPHA_CONV" "";

(*---------------------------------------------------------------------------
 * Rename bound variables
 *
 *       "a"   "(\:b.t)"   --->    |- "\:b.t  = \:a. t[a/b]"
 *       "a"   "(!:b.t)"   --->    |- "!:b.t  = !:a. t[a/b]"
 *       "a"   "(?:b.t)"   --->    |- "?:b.t  = ?:a. t[a/b]"
 *---------------------------------------------------------------------------*)

fun GEN_TY_ALPHA_CONV a t =
   if is_tyabs t
   then TY_ALPHA_CONV a t
   else let val (Rator, Rand) = dest_comb t
        in AP_TERM Rator (TY_ALPHA_CONV a Rand)
        end
        handle HOL_ERR _ => raise ERR "GEN_TY_ALPHA_CONV" "";



(* ---------------------------------------------------------------------*)
(* IMP_CONJ implements the following derived inference rule:		*)
(*									*)
(*  A1 |- P ==> Q    A2 |- R ==> S					*)
(* --------------------------------- IMP_CONJ				*)
(*   A1 u A2 |- P /\ R ==> Q /\ S					*)
(* ---------------------------------------------------------------------*)

fun IMP_CONJ th1 th2 =
    let val (A1,_) = dest_imp (concl th1)
        and (A2,_) = dest_imp (concl th2)
        val conj = mk_conj(A1,A2)
        val (a1,a2) = CONJ_PAIR (ASSUME conj)
    in
      DISCH conj (CONJ (MP th1 a1) (MP th2 a2))
    end;

(* ---------------------------------------------------------------------*)
(* EXISTS_IMP : existentially quantify the antecedent and conclusion 	*)
(* of an implication.							*)
(*									*)
(*        A |- P ==> Q							*)
(* -------------------------- EXISTS_IMP `x`				*)
(*   A |- (?x.P) ==> (?x.Q)						*)
(*									*)
(* ---------------------------------------------------------------------*)

fun EXISTS_IMP x th =
  if not (is_var x)
  then raise ERR "EXISTS_IMP" "first argument not a variable"
  else let val (ant,conseq) = dest_imp(concl th)
           val th1 = EXISTS (mk_exists(x,conseq),x) (UNDISCH th)
           val asm = mk_exists(x,ant)
       in DISCH asm (CHOOSE (x,ASSUME asm) th1)
       end
       handle HOL_ERR _ => raise ERR "EXISTS_IMP"
                            "variable free in assumptions";

(* ---------------------------------------------------------------------*)
(* TY_EXISTS_IMP : type existentially quantify the antecedent and 	*)
(* conclusion of an implication.					*)
(*									*)
(*        A |- P ==> Q							*)
(* ---------------------------- TY_EXISTS_IMP `:a`			*)
(*   A |- (?:a.P) ==> (?:a.Q)						*)
(*									*)
(* ---------------------------------------------------------------------*)

fun TY_EXISTS_IMP x th =
  if not (is_vartype x)
  then raise ERR "TY_EXISTS_IMP" "first argument not a type variable"
  else let val (ant,conseq) = dest_imp(concl th)
           val th1 = TY_EXISTS (mk_tyexists(x,conseq),x) (UNDISCH th)
           val asm = mk_tyexists(x,ant)
       in DISCH asm (TY_CHOOSE (x,ASSUME asm) th1)
       end
       handle HOL_ERR _ => raise ERR "TY_EXISTS_IMP"
                            "type variable free in assumptions";


(*---------------------------------------------------------------------------*
 * Instantiate terms and types of a theorem. This is pretty slow, because    *
 * it makes two full traversals of the theorem.                              *
 *---------------------------------------------------------------------------*)

fun INST_TY_TERM(Stm,Sty) th = INST Stm (INST_TYPE Sty th);


(*---------------------------------------------------------------------------*
 * Instantiate terms, types, kinds, and ranks of a theorem. This is pretty   *
 * slow, because it makes three full traversals of the theorem.              *
 *---------------------------------------------------------------------------*)

fun INST_RK_KD_TY_TERM(Stm,Sty,Skd,Srk) th =
    INST Stm (INST_TYPE Sty (INST_KIND Skd (INST_RANK Srk th)));


(*---------------------------------------------------------------------------*
 *   |- !x y z. w   --->  |- w[g1/x][g2/y][g3/z]                             *
 *---------------------------------------------------------------------------*)

fun GSPEC th =
  let val (_,w) = dest_thm th
  in if is_forall w
     then GSPEC (SPEC (genvar (type_of (fst (dest_forall w)))) th)
     else th
  end;


(*---------------------------------------------------------------------------*
 *   |- !x y z. w   --->  |- w[g1/x][g2/y][g3/z]                             *
 *---------------------------------------------------------------------------*)

fun TY_GSPEC th =
  let val (_,w) = dest_thm th
  in if is_tyforall w
     then let val v = fst (dest_tyforall w)
              val (_,kd,rk) = dest_vartype_opr v
          in TY_GSPEC (TY_SPEC (gen_tyopvar (kd,rk)) th)
          end
     else th
  end;


(*---------------------------------------------------------------------------*
 * Match a given part of "th" to a term, instantiating "th". The part        *
 * should be free in the theorem, except for outer bound variables.          *
 *---------------------------------------------------------------------------*)

fun PART_MATCH partfn th = let
  val th = SPEC_ALL (TY_SPEC_ALL th)
  val conclfvs = Term.FVL [concl th] empty_tmset
  val hypfvs = Thm.hyp_frees th
  val hyptyvars = HOLset.listItems (Thm.hyp_tyvars th)
  val hypkdvars = HOLset.listItems (Thm.hyp_kdvars th)
  val pat = partfn(concl th)
  val matchfn =
      kind_match_terml hypkdvars hyptyvars (HOLset.intersection(conclfvs, hypfvs)) pat
in
  (fn tm => INST_RK_KD_TY_TERM (matchfn tm) th)
end;


(* -------------------------------------------------------------------- *)
(* MATCH_MP: Matching Modus Ponens for implications.			*)
(*									*)
(*    |- !x1 ... xn. P ==> Q     |- P' 					*)
(* ---------------------------------------				*)
(*                |- Q'  						*)
(*									*)
(* Matches all types in conclusion except those mentioned in hypotheses.*)
(*									*)
(* Reimplemented with bug fix [TFM 91.06.17]. 				*)
(* OLD CODE:								*)
(*									*)
(* let MATCH_MP impth =							*)
(*  let match = PART_MATCH (fst o dest_imp) impth ? failwith `MATCH_MP` *)
(*     in								*)
(*     \th. MP (match (concl th)) th;;					*)
(*									*)
(*									*)
(* Pre - JRH version                                                    *)
(* fun MATCH_MP impth =                                                 *)
(*    let val (hy,c) = dest_thm impth                                   *)
(*        val (vs,imp) = strip_forall c                                 *)
(*        val pat = #ant(dest_imp imp)                                  *)
(*                  handle _ => raise CONV_ERR{function = "MATCH_MP",   *)
(*                                    message = "not an implication"}   *)
(*        val fvs = set_diff (free_vars pat) (free_varsl hy)            *)
(*        val gth = GSPEC (GENL fvs (SPECL vs impth))                   *)
(*        val matchfn = Match.match_term (#ant(dest_imp(concl gth)))    *)
(*    in                                                                *)
(*    fn th => MP (INST_TY_TERM (matchfn (concl th)) gth) th            *)
(*             handle _ => raise CONV_ERR{function = "MATCH_MP",        *)
(* 				       message = "does not match"}      *)
(*    end;                                                              *)
(* -------------------------------------------------------------------- *)

local fun variants (_,[]) = []
        | variants (av, h::rst) =
            let val vh = variant av h in vh::variants (vh::av, rst) end
      fun rassoc_total x theta =
         case subst_assoc (equal x) theta
          of SOME y => y
           | NONE => x
      fun req {redex,residue} = (redex=residue)
in
fun MATCH_MP ith =
 let val (ial,ibod) = strip_tyforall(concl ith)
     val ias = HOLset.addList(empty_tyset, ial)
     val bod = fst(dest_imp(snd(strip_forall ibod)))
     val hyptyvars = HOLset.listItems (HOLset.difference(hyp_tyvars ith, ias))
     val hypkdvars = HOLset.listItems (hyp_kdvars ith)
     val lconsts = HOLset.intersection
                     (FVL [concl ith] empty_tmset, hyp_frees ith)
 in fn th =>
   let val mfn = C (Term.kind_match_terml hypkdvars hyptyvars lconsts) (concl th)
       val (_,tyS,kdS,rkS) = mfn bod
       val (atyS,tyS) = partition (fn {redex,residue} => mem redex ial) tyS
       val tth0 = INST_TYPE tyS (INST_KIND kdS (INST_RANK rkS ith))
       val tth = TY_SPECL (map (type_subst atyS) ial) tth0
       val tbod = fst(dest_imp(snd(strip_forall(concl tth))))
       val tmin = #1(mfn tbod)
       val hy1 = HOLset.listItems (hyp_frees tth)
       and hy2 = HOLset.listItems (hyp_frees th)
       val (avs,(ant,conseq)) = (I ## dest_imp) (strip_forall (concl tth))
       val (rvs,fvs) = partition (C free_in ant) (free_vars conseq)
       val afvs = Lib.set_diff fvs (Lib.set_diff hy1 avs)
       val cvs = free_varsl (map (C rassoc_total tmin) rvs)
       val vfvs = map (op |->) (zip afvs (variants (cvs@hy1@hy2, afvs)))
       val atmin = (filter (op not o op req) vfvs)@tmin
       val (spl,ill) = partition (C mem avs o #redex) atmin
       val fspl = map (C rassoc_total spl) avs
       val mth = MP (SPECL fspl (INST ill tth)) th
       fun loop [] = []
         | loop (tm::rst) =
              case subst_assoc (equal tm) vfvs
                of NONE => loop rst
                 | SOME x => x::loop rst
   in
     GENL (loop avs) mth
   end
 end
end;


(*---------------------------------------------------------------------------*
 * Now higher-order versions of PART_MATCH and MATCH_MP                      *
 *---------------------------------------------------------------------------*)

(* IMPORTANT: See the bottom of this file for a longish discussion of some
              of the ways this implementation attempts to keep bound variable
              names sensible.
*)

(* ------------------------------------------------------------------------- *)
(* Attempt alpha conversion.                                                 *)
(* ------------------------------------------------------------------------- *)

fun tryalpha v tm =
 let val (Bvar,Body) = dest_abs tm
 in if v = Bvar then tm else
    if var_occurs v Body then tryalpha (variant (free_vars tm) v) tm
    else mk_abs(v, subst[Bvar |-> v] Body)
 end


(* ------------------------------------------------------------------------- *)
(* Match up bound variables names.                                           *)
(* ------------------------------------------------------------------------- *)

(* first argument is actual term, second is from theorem being matched *)
fun match_bvs t1 t2 acc =
 case (dest_term t1, dest_term t2)
  of (LAMB(v1,b1), LAMB(v2,b2))
      => let val n1 = fst(dest_var v1)
             val n2 = fst(dest_var v2)
             val newacc = if n1 = n2 then acc else insert(n1, n2) acc
         in
           match_bvs b1 b2 newacc
         end
  | (COMB(l1,r1), COMB(l2,r2)) => match_bvs l1 l2 (match_bvs r1 r2 acc)
  | otherwise => acc;

(* bindings come from match_bvs, telling us which bound variables are going
   to get renamed, and thmc is the conclusion of the pattern theorem.
   acc is a set of free variables that need to get instantiated away *)
fun look_for_avoids bindings thmc acc = let
  val lfa = look_for_avoids bindings
in
  case dest_term thmc of
    LAMB (v, b) => let
      val (thm_n, _) = dest_var v
    in
      case Lib.total (rev_assoc thm_n) bindings of
        SOME n => let
          val fvs = FVL [b] empty_tmset
          fun f (v, acc) =
              if #1 (dest_var v) = n then HOLset.add(acc, v)
              else acc
        in
          lfa b (HOLset.foldl f acc fvs)
        end
      | NONE => lfa b acc
    end
  | COMB (l,r) => lfa l (lfa r acc)
  | _ => acc
end


(* ------------------------------------------------------------------------- *)
(* Modify bound variable names at depth. (Not very efficient...)             *)
(* ------------------------------------------------------------------------- *)

fun deep_alpha [] tm = tm
  | deep_alpha env tm =
     case dest_term tm
      of LAMB(Bvar,Body) =>
          (let val (Name,Ty) = dest_var Bvar
               val ((vn',_),newenv) = Lib.pluck (fn (_,x) => x = Name) env
               val tm' = tryalpha (mk_var(vn', Ty)) tm
               val (iv,ib) = dest_abs tm'
           in mk_abs(iv, deep_alpha newenv ib)
           end
           handle HOL_ERR _ => mk_abs(Bvar,deep_alpha env Body))
       | COMB(Rator,Rand) => mk_comb(deep_alpha env Rator, deep_alpha env Rand)
       | otherwise => tm

(* -------------------------------------------------------------------------
 * BETA_VAR
 *
 * Set up beta-conversion for head instances of free variable v in tm.
 *
 * EXAMPLES
 *
 *   BETA_VAR (--`x:num`--) (--`(P:num->num->bool) x x`--);
 *   BETA_VAR (--`x:num`--) (--`x + 1`--);
 *
 * Note (kxs): I am defining this before Conv, so some conversion(al)s are
 * p(re)-defined here. Ugh.
 * -------------------------------------------------------------------------
 * -------------------------------------------------------------------------
 * PART_MATCH
 *
 * Match (higher-order) part of a theorem to a term.
 *
 * PART_MATCH (snd o strip_forall) BOOL_CASES_AX (--`(P = T) \/ (P = F)`--);
 * val f = PART_MATCH lhs;
 * profile2 f NOT_FORALL_THM (--`~!x. (P:num->num->bool) x y`--);
 * profile2 f NOT_EXISTS_THM (--`?x. ~(P:num->num->bool) x y`--);
 * profile2 f LEFT_AND_EXISTS_THM
 *             (--`(?x. (P:num->num->bool) x x) /\ Q (y:num)`--);
 * profile LEFT_AND_EXISTS_CONV
 *           (--`(?x. (P:num->num->bool) x x) /\ Q (x:num)`--);
 * profile2 f NOT_FORALL_THM (--`~!x. (P:num->num->bool) y x`--);
 * profile NOT_FORALL_CONV (--`~!x. (P:num->num->bool) y x`--);
 * val f = PART_MATCH (lhs o snd o strip_imp);
 * val CRW_THM = mk_thm([],(--`P x ==> Q x (y:num) ==> (x + 0 = x)`--));
 * f CRW_THM (--`y + 0`--);
 *
 * val beta_thm = prove(--`(\x:'a. P x) b = (P b:'b)`--)--,
 *                      BETA_TAC THEN REFL_TAC);
 * val f = profile PART_MATCH lhs beta_thm;
 * profile f (--`(\x. I x) 1`--);
 * profile f (--`(\x. x) 1`--);
 * profile f (--`(\x. P x x:num) 1`--);
 *
 * The current version attempts to keep variable names constant.  This
 * is courtesy of JRH.
 *
 * Non renaming version (also courtesy of JRH!!)
 *
 * fun PART_MATCH partfn th =
 *   let val sth = SPEC_ALL th
 *       val bod = concl sth
 *       val possbetas = mapfilter (fn v => (v,BETA_VAR v bod)) (free_vars bod)
 *       fun finish_fn tyin bvs =
 *         let val npossbetas = map (inst tyin ## I) possbetas
 *         in CONV_RULE (EVERY_CONV (mapfilter (C assoc npossbetas) bvs))
 *         end
 *       val pbod = partfn bod
 *   in fn tm =>
 *     let val (tmin,tyin,kdin,rkin) = kind_match_term pbod tm
 *         val th0 = INST_RK_KD_TY_TERM (tmin,tyin,kdin,rkin) sth
 *     in finish_fn tyin (map #redex tmin) th0
 *     end
 *   end;
 *
 * EXAMPLES:
 *
 * val CET = mk_thm([],(--`(!c. P ($COND c x y) c) = (P x T /\ P y F)`--));

 * PART_MATCH lhs FORALL_SIMP (--`!x. y + 1 = 2`--);
 * PART_MATCH lhs FORALL_SIMP (--`!x. x + 1 = 2`--); (* fails *)
 * PART_MATCH lhs CET (--`!b. ~(f (b => t | e))`--);
 * PART_MATCH lhs option_CASE_ELIM (--`!b. ~(P (option_CASE e f b))`--);
 * PART_MATCH lhs (MK_FORALL (--`c:bool`--) COND_ELIM_THM)
 *                (--`!b. ~(f (b => t | e))`--);
 * PART_MATCH lhs (MK_FORALL (--`c:bool`--) COND_ELIM_THM)
 *                 (--`!b. ~(f (b => t | e))`--);
 * ho_term_match [] (--`!c.  P ($COND c x y)`--)
 *
 * BUG FIXES & TEST CASES
 *
 * Variable Renaming:
 * PART_MATCH (lhs o snd o strip_forall) SKOLEM_THM (--`!p. ?GI. Q GI p`--);
 * Before renaming this produced: |- (!x. ?y. Q y x) = (?y. !x. Q (y x) x)
 * After renaming this produced: |- (!p. ?GI. Q GI p) = (?GI. !p. Q (GI p) p)
 *
 * Variable renaming problem (DRS, Feb 1996):
 * PART_MATCH lhs NOT_FORALL_THM (--`~!y. P x`--);
 * Before fix produced:  |- ~(!x'. P x) = (?x'. ~(P x)) : thm
 * After fix produced:  |- ~(!y. P x) = (?y. ~(P x))
 * Fix:
 *	val bvms = match_bvs tm (inst tyin pbod) []
 * Became:
 *      val bvms = match_bvs tm (partfn (concl th0)) []
 *
 * Variable renaming problem (DRS, Feb 1996):
 * PART_MATCH lhs NOT_FORALL_THM (--`~!x. (\y. t) T`--);
 * Before fix produced (--`?y. ~(\y. t) T`--);
 * After fix produced (--`?x. ~(\y. t) T`--);
 * Fix:
 *      Moved beta reduction to be before alpha renaming.  This makes
 * match_bvs more accurate.  This was not a problem before the previous
 * fix.
 *
 * Another bug (unfixed).  bvms =  [("x","y"),("E'","x")]
 *   PART_MATCH lhs SWAP_EXISTS_THM  (--`?E' x const'.
 *       ((s = s') /\
 *         (E = E') /\
 *       (val = Val_Constr (const',x)) /\
 *       (sym = const)) /\
 *      (a1 = NONE) /\
 *      ~(const = const')`--)
 * ------------------------------------------------------------------------- *)

nonfix THENC
local fun COMB_CONV2 c1 c2 M =
        let val (f,x) = dest_comb M in MK_COMB(c1 f, c2 x) end
      fun ABS_CONV c M =
        let val (Bvar,Body) = dest_abs M in ABS Bvar (c Body) end
      fun RAND_CONV c M =
        let val (Rator,Rand) = dest_comb M in AP_TERM Rator (c Rand) end
      fun RATOR_CONV c M =
        let val (Rator,Rand) = dest_comb M in AP_THM (c Rator) Rand end
      fun TRY_CONV c M = c M handle HOL_ERR _ => REFL M
      fun THENC c1 c2 M =
        let val th = c1 M in TRANS th (c2 (rhs (concl th))) end;
      fun EVERY_CONV convl = itlist THENC convl REFL
      fun CONV_RULE conv th = EQ_MP (conv(concl th)) th
      fun BETA_CONVS n =
        if n = 1 then TRY_CONV BETA_CONV
        else THENC (RATOR_CONV (BETA_CONVS (n-1))) (TRY_CONV BETA_CONV)
in
fun BETA_VAR v tm =
 if is_abs tm
 then let val (Bvar,Body) = dest_abs tm
      in if v=Bvar then failwith "BETA_VAR: UNCHANGED"
         else ABS_CONV(BETA_VAR v Body) end
 else
 case strip_comb tm
  of (_,[]) => failwith "BETA_VAR: UNCHANGED"
   | (oper,args) =>
      if oper = v then BETA_CONVS (length args)
      else let val (Rator,Rand) = dest_comb tm
           in let val lconv = BETA_VAR v Rator
              in let val rconv = BETA_VAR v Rand
                 in COMB_CONV2 lconv rconv
                 end handle HOL_ERR _ => RATOR_CONV lconv
              end handle HOL_ERR _ => RAND_CONV (BETA_VAR v Rand)
           end

structure Map = Redblackmap

(* count from zero to indicate last argument, up to #args - 1 to indicate
   first argument *)
fun arg_CONV 0 c t = RAND_CONV c t
  | arg_CONV n c t = RATOR_CONV (arg_CONV (n - 1) c) t

fun foldri f acc list = let
  fun foldthis (e, (acc, n)) = (f(n, e, acc), n + 1)
in
  #1 (foldr foldthis (acc,0) list)
end

fun munge_bvars absmap th = let
  fun recurse curposn bvarposns (donebvars, acc) t =
      case dest_term t of
        LAMB(bv, body) => let
          val newposnmap = Map.insert(bvarposns, bv, curposn)
          val (newdonemap, restore) =
              (HOLset.delete(donebvars, bv), (fn m => HOLset.add(m, bv)))
              handle HOLset.NotFound =>
                     (donebvars, (fn m => HOLset.delete(m, bv)
                                     handle HOLset.NotFound => m))
          val (dbvars, actions) =
              recurse (curposn o ABS_CONV) newposnmap (newdonemap, acc) body
        in
          (restore dbvars, actions)
        end
      | COMB _ => let
          val (f, args) = strip_comb t
          fun argfold (n, arg, A) =
              recurse (curposn o arg_CONV n) bvarposns A arg
        in
          case Map.peek(absmap, f) of
            NONE => foldri argfold (donebvars, acc) args
          | SOME abs_t => let
              val (abs_bvars, _) = strip_abs abs_t
              val paired_up = ListPair.zip (args, abs_bvars)
              fun foldthis ((arg, absv), acc as (dbvars, actionlist)) =
                  if HOLset.member(dbvars, arg) then acc
                  else case Map.peek(bvarposns, arg) of
                         NONE => acc
                       | SOME p =>
                         (HOLset.add(dbvars, arg),
                          p (ALPHA_CONV absv):: actionlist)
              val (A as (newdbvars, newacc)) =
                  List.foldl foldthis (donebvars, acc) paired_up
            in
              foldri argfold A args
            end
        end
      | _ => (donebvars, acc)
in
  recurse I (Map.mkDict Term.compare) (empty_tmset, []) (concl th)
end



(* Modified HO_PART_MATCH by PVH on Apr. 25, 2005: code was broken;
   repaired by tightening "foldthis" condition for entry to "bound_to_abs";
   see longish note at bottom for more details. *)

(* "bound_vars" returns set of bound variables within term t *)
(* "t" argument is actual term, "acc" is accumulating set, orig. empty *)
local
 fun bound_vars1 t acc =
  case dest_term t
   of LAMB(v,b)
       => bound_vars1 b (HOLset.add(acc, v))
   | COMB(l,r) => bound_vars1 l (bound_vars1 r acc)
   | otherwise => acc
in
fun bound_vars t = bound_vars1 t empty_tmset
end


fun HO_PART_MATCH partfn th =
 let val sth = SPEC_ALL (TY_SPEC_ALL th)
     val bod = concl sth
     val pbod = partfn bod
     val possbetas = mapfilter (fn v => (v,BETA_VAR v bod))
                               (filter (can dom_rng o type_of) (free_vars bod))
     fun finish_fn rkin kdin tyin ivs =
       let val npossbetas =
            if rkin = 0 andalso null kdin andalso null tyin then possbetas
               else map ((inst tyin o inst_rank_kind rkin kdin) ## I) possbetas
       in if null npossbetas then Lib.I
          else CONV_RULE (EVERY_CONV (mapfilter
                                        (TRY_CONV o C assoc npossbetas)
                                        ivs))
       end
     val lconsts = HOLset.intersection (FVL[pbod]empty_tmset, hyp_frees th)
     val lkdconsts = HOLset.listItems (hyp_kdvars th)
     val ltyconsts = HOLset.listItems (hyp_tyvars th)
 in fn tm =>
    let val (tmin,tyin,kdin,rkin) = ho_kind_match_term lkdconsts ltyconsts lconsts pbod tm
        val tmbvs = bound_vars tm
        fun foldthis ({redex,residue}, acc) =
            if is_abs residue andalso
               all (fn v => HOLset.member(tmbvs, v)) (fst (strip_abs residue))
            then Map.insert(acc, redex, residue) else acc
        val bound_to_abs = List.foldl foldthis (Map.mkDict Term.compare) tmin
        val sth0 = INST_TYPE tyin (INST_KIND kdin (INST_RANK rkin sth))
        val sth0c = concl sth0
        val (sth1, tmin') =
            case match_bvs tm (partfn sth0c) [] of
              [] => (sth0, tmin)
            | bvms => let
                val avoids = look_for_avoids bvms sth0c empty_tmset
                fun f (v, acc) = (v |-> genvar (type_of v)) :: acc
                val newinst = HOLset.foldl f [] avoids
                val newthm = INST newinst sth0
                val tmin' = map (fn {residue, redex} =>
                                    {residue = residue,
                                     redex = Term.subst newinst redex}) tmin
                val thmc = concl newthm
              in
                (EQ_MP (ALPHA thmc (deep_alpha bvms thmc)) newthm, tmin')
              end
        val sth2 =
            if Map.numItems bound_to_abs = 0 then sth1
            else
              CONV_RULE (EVERY_CONV (#2 (munge_bvars bound_to_abs sth1))) sth1
        val th0 = INST tmin' sth2
        val th1 = finish_fn rkin kdin tyin (map #redex tmin) th0
    in
      th1
    end
 end
end;


fun HO_MATCH_MP ith =
 let val sth =
       let val tm = concl ith
           val (atvs,tbod) = strip_tyforall tm
           val (avs,bod) = strip_forall tbod
           val (ant,_) = dest_imp_only bod
           val (ant_tvs,nant_tvs) = partition (C tyvar_occurs ant) atvs
       in case partition (C free_in ant) avs
           of (_,[]) => if null nant_tvs then ith else
              let val th1 = SPECL avs (TY_SPECL atvs (ASSUME tm))
                  val th2 = TY_GENL ant_tvs (GENL avs (DISCH ant (TY_GENL nant_tvs (UNDISCH th1))))
              in MP (DISCH tm th2) ith
              end
            | (svs,pvs) =>
              let val th1 = SPECL avs (TY_SPECL atvs (ASSUME tm))
                  val th2 = TY_GENL ant_tvs (GENL svs (DISCH ant (TY_GENL nant_tvs (GENL pvs (UNDISCH th1)))))
              in MP (DISCH tm th2) ith
              end
       end handle HOL_ERR _ => raise ERR "MATCH_MP" "Not an implication"
     val match_fun = HO_PART_MATCH (fst o dest_imp_only) sth
 in fn th =>
     MP (match_fun (concl th)) th
     handle HOL_ERR _ => raise ERR "MATCH_MP" "No match"
 end;




(* =====================================================================*)
(* The "resolution" tactics for HOL (outmoded technologoy, but          *)
(* sometimes useful) uses RES_CANON and SPEC_ALL 		        *)
(* =====================================================================*)
(*                                                                      *)
(* Put a theorem 							*)
(*									*)
(*	 |- !x. t1 ==> !y. t2 ==> ... ==> tm ==>  t 			*)
(*									*)
(* into canonical form for resolution by splitting conjunctions apart   *)
(* (like IMP_CANON but without the stripping out of quantifiers and only*)
(* outermost negations being converted to implications).		*)
(*									*)
(*   ~t            --->          t ==> F        (at outermost level)	*)
(*   t1 /\ t2	  --->		t1,   t2				*)
(*   (t1/\t2)==>t  --->		t1==> (t2==>t)				*)
(*   (t1\/t2)==>t  --->		t1==>t, t2==>t				*)
(*									*)
(*									*)
(* Modification provided by David Shepherd of Inmos to make resolution  *)
(* work with equalities as well as implications. HOL88.1.08,23 jun 1989.*)
(*									*)
(*   t1 = t2      --->          t1=t2, t1==>t2, t2==>t1			*)
(*									*)
(* Modification provided by T Melham to deal with the scope of 		*)
(* universal quantifiers. [TFM 90.04.24]				*)
(*									*)
(*   !x. t1 ==> t2  --->  t1 ==> !x.t2   (x not free in t1)		*)
(*									*)
(* The old code is given below:						*)
(* 									*)
(*    letrec RES_CANON_FUN th =						*)
(*     let w = concl th in						*)
(*     if is_conj w 							*)
(*     then RES_CANON_FUN(CONJUNCT1 th)@RES_CANON_FUN(CONJUNCT2 th)	*)
(*     else if is_imp w & not(is_neg w) then				*)
(* 	let ante,conc = dest_imp w in					*)
(* 	if is_conj ante then						*)
(* 	    let a,b = dest_conj ante in					*)
(* 	    RES_CANON_FUN 						*)
(* 	    (DISCH a (DISCH b (MP th (CONJ (ASSUME a) (ASSUME b)))))	*)
(* 	else if is_disj ante then					*)
(* 	    let a,b = dest_disj ante in					*)
(* 	    RES_CANON_FUN (DISCH a (MP th (DISJ1 (ASSUME a) b))) @	*)
(* 	    RES_CANON_FUN (DISCH b (MP th (DISJ2 a (ASSUME b))))	*)
(* 	else								*)
(* 	map (DISCH ante) (RES_CANON_FUN (UNDISCH th))			*)
(*     else [th];							*)
(* 									*)
(* This version deleted for HOL 1.12 (see below)	[TFM 91.01.17]  *)
(*									*)
(* let RES_CANON = 							*)
(*     letrec FN th = 							*)
(*       let w = concl th in						*)
(*       if (is_conj w) then FN(CONJUNCT1 th) @ FN(CONJUNCT2 th) else	*)
(*       if ((is_imp w) & not(is_neg w)) then				*)
(*       let ante,conc = dest_imp w in					*)
(*       if (is_conj ante) then						*)
(*          let a,b = dest_conj ante in					*)
(* 	    let ath = ASSUME a and bth = ASSUME b			*)
(*          in FN (DISCH a (DISCH b (MP th (CONJ ath bth)))) else       *)
(*       if is_disj ante then                                           *)
(*         let a,b = dest_disj ante in					*)
(*         let ath = ASSUME a and bth = ASSUME b 			*)
(* 	   in FN (DISCH a (MP th (DISJ1 ath b))) @			*)
(*            FN (DISCH b (MP th (DISJ2 a bth)))                        *)
(*       else map (GEN_ALL o (DISCH ante)) (FN (UNDISCH th))    	*)
(*       else if is_eq w then						*)
(*        let l,r = dest_eq w in					*)
(*            if (type_of l = ":bool")                                  *)
(*            then let (th1,th2) = EQ_IMP_RULE th                       *)
(*                 in (GEN_ALL th) . ((FN  th1) @ (FN  th2)) 		*)
(*            else [GEN_ALL th]                                         *)
(*        else [GEN_ALL th] in                                          *)
(*     \th. (let vars,w = strip_forall(concl th) in			*)
(*           let th1 = if (is_neg w)	 				*)
(* 	  		then NOT_ELIM(SPEC_ALL th) 			*)
(* 			else (SPEC_ALL th) in				*)
(*               map GEN_ALL (FN th1) ? failwith `RES_CANON`);		*)
(* ---------------------------------------------------------------------*)
(* ---------------------------------------------------------------------*)
(* New RES_CANON for version 1.12.			 [TFM 90.12.07] *)
(* 									*)
(* The complete list of transformations is now:				*)
(*									*)
(*   ~t              --->       t ==> F        (at outermost level)	*)
(*   t1 /\ t2	     --->	t1, t2	       (at outermost level)	*)
(*   (t1/\t2)==>t    --->	t1==>(t2==>t), t2==>(t1==>t)		*)
(*   (t1\/t2)==>t    --->	t1==>t, t2==>t				*)
(*   t1 = t2         --->       t1==>t2, t2==>t1			*)
(*   !x. t1 ==> t2   --->       t1 ==> !x.t2   (x not free in t1)	*)
(*   (?x.t1) ==> t2  --->	!x'. t1[x'/x] ==> t2			*)
(*									*)
(* The function now fails if no implications can be derived from the 	*)
(* input theorem.							*)
(* ---------------------------------------------------------------------*)


local fun not_elim th =
       if is_neg(concl th) then (true, NOT_ELIM th) else (false,th)
fun canon (fl,th) =
   let val w = concl th
   in
   if is_conj w
     then let val (th1,th2) = CONJ_PAIR th
          in (canon(fl,th1) @ canon(fl,th2))
          end else
   if is_imp w andalso not(is_neg w) then
     let val (ant,_) = dest_imp w
     in if is_conj ant
        then let val (conj1,conj2) = dest_conj ant
                 val cth = MP th (CONJ (ASSUME conj1) (ASSUME conj2))
                 val th1 = DISCH conj2 cth
                 and th2 = DISCH conj1 cth
             in
                canon(true,DISCH conj1 th1) @ canon(true,DISCH conj2 th2)
             end else
        if is_disj ant
        then let val (disj1,disj2) = dest_disj ant
                 val ath = DISJ1 (ASSUME disj1) disj2
                 and bth = DISJ2 disj1 (ASSUME disj2)
                 val th1 = DISCH disj1 (MP th ath)
                 and th2 = DISCH disj2 (MP th bth)
             in
                 canon(true,th1) @ canon(true,th2)
             end else
        if is_exists ant
        then let val (Bvar,Body) = dest_exists ant
                 val newv = variant(thm_frees th) Bvar
                 val newa = subst [Bvar |-> newv] Body
                 val th1  = MP th (EXISTS (ant,newv) (ASSUME newa))
             in
               canon(true,DISCH newa th1)
             end
        else map (GEN_ALL o (DISCH ant)) (canon (true,UNDISCH th))
     end else
   if is_eq w andalso (type_of (rand w) = Type.bool)
   then let val (th1,th2) = EQ_IMP_RULE th
        in (if fl then [GEN_ALL th] else [])@canon(true,th1)@canon(true,th2)
        end else
   if is_forall w then
     let val (vs,_) = strip_forall w
         val fvs = HOLset.listItems (FVL[concl th] (hyp_frees th))
         val nvs = itlist (fn v => fn nv => variant (nv @ fvs) v::nv) vs []
     in
        canon (fl, SPECL nvs th)
     end else
   if fl then [GEN_ALL th] else []
   end
in
fun RES_CANON th =
 let val conjlist = CONJUNCTS (SPEC_ALL th)
     fun operate th accum =
          accum @ map GEN_ALL (canon (not_elim (SPEC_ALL th)))
     val imps = Lib.rev_itlist operate conjlist []
 in Lib.assert (op not o null) imps
 end handle HOL_ERR _
 => raise ERR "RES_CANON" "No implication is derivable from input thm"
end;


(*======================================================================*)
(*       Routines supporting the definition of types                    *)
(*                                                                      *)
(* AUTHOR        : (c) Tom Melham, University of Cambridge              *)
(*                                                                      *)
(* NAME: define_new_type_bijections 					*)
(*									*)
(* DESCRIPTION: define isomorphism constants based on a type definition.*)
(*									*)
(* USAGE: define_new_type_bijections name ABS REP tyax                  *)
(*									*)
(* ARGUMENTS: tyax -- a type-defining axiom of the form returned by	*)
(*		     new_type_definition. For example:			*)
(*									*)
(* 			?rep. TYPE_DEFINITION P rep			*)
(*									*)
(*            ABS  --- the name of the required abstraction function    *)
(*									*)
(*            REP  --- the name of the required representation function *)
(*									*)
(*            name --- the name under which the definition is stored    *)
(*									*)
(* SIDE EFFECTS:    Introduces a definition for two constants `ABS` and *)
(*                  (--`REP`--) by the constant specification:          *)
(*									*)
(*  		   |- ?ABS REP. (!a. ABS(REP a) = a) /\                 *)
(*                              (!r. P r = (REP(ABS r) = r)             *)
(*									*)
(*                 The resulting constant specification is stored under *)
(*                 the name given as the first argument.                *)
(*									*)
(* FAILURE: if input theorem of wrong form.			        *)
(*									*)
(* RETURNS: The defining property of the representation and abstraction *)
(*          functions, given by:                                        *)
(*             								*)
(*           |- (!a. ABS(REP a) = a) /\ (!r. P r = (REP(ABS r) = r)   	*)
(* ---------------------------------------------------------------------*)

fun define_new_type_bijections{name,ABS,REP,tyax} =
  if not(HOLset.isEmpty (hypset tyax))
  then raise ERR "define_new_type_bijections"
                 "input theorem must have no assumptions"
  else
  let val (_,[P,rep]) = strip_comb(snd(dest_exists(concl tyax)))
      val (a,r) = Type.dom_rng (type_of rep)
  in Rsyntax.new_specification
      {name=name,
       sat_thm=MP(SPEC P (INST_TYPE[beta |-> a, alpha |-> r]ABS_REP_THM)) tyax,
       consts = [{const_name=REP, fixity=Prefix},
                 {const_name=ABS, fixity=Prefix}]}
  end
  handle e => raise (wrap_exn "Drule" "define_new_type_bijections" e)

(* ---------------------------------------------------------------------*)
(* NAME: prove_rep_fn_one_one	 					*)
(*									*)
(* DESCRIPTION: prove that a type representation function is one-to-one.*)
(*									*)
(* USAGE: if th is a theorem of the kind returned by the ML function	*)
(*        define_new_type_bijections:					*)
(*									*)
(*           |- (!a. ABS(REP a) = a) /\ (!r. P r = (REP(ABS r) = r)   	*)
(*									*)
(*	 then prove_rep_fn_one_one th will prove and return a theorem	*)
(*	 stating that the representation function REP is one-to-one:	*)
(*									*)
(*	    |- !a a'. (REP a = REP a') = (a = a')			*)
(*									*)
(* ---------------------------------------------------------------------*)

fun prove_rep_fn_one_one th =
   let val thm = CONJUNCT1 th
       val (_,Body) = dest_forall(concl thm)
       val (A, Rand) = dest_comb(lhs Body)
       val (R, _)= dest_comb Rand
       val (_,[aty,rty]) = Type.dest_type (type_of R)
       val a = mk_primed_var("a", aty)
       val a' = variant [a] a
       val a_eq_a' = mk_eq(a,a')
       and Ra_eq_Ra' = mk_eq(mk_comb(R,a), mk_comb(R, a'))
       val th1 = AP_TERM A (ASSUME Ra_eq_Ra')
       val ga1 = genvar aty
       and ga2 = genvar aty
       val th2 = SUBST [ga1 |-> SPEC a thm, ga2 |-> SPEC a' thm]
                       (mk_eq(ga1, ga2)) th1
       val th3 = DISCH a_eq_a' (AP_TERM R (ASSUME a_eq_a'))
   in
      GEN a (GEN a' (IMP_ANTISYM_RULE (DISCH Ra_eq_Ra' th2) th3))
   end
   handle HOL_ERR _ => raise ERR "prove_rep_fn_one_one"  ""
        | Bind => raise ERR "prove_rep_fn_one_one"
                            ("Theorem not of right form: must be\n "^
                             "|- (!a. to (from a) = a) /\\ "^
                             "(!r. P r = (from (to r) = r))")


(* --------------------------------------------------------------------- *)
(* NAME: prove_rep_fn_onto	 					*)
(*									*)
(* DESCRIPTION: prove that a type representation function is onto. 	*)
(*									*)
(* USAGE: if th is a theorem of the kind returned by the ML function	*)
(*        define_new_type_bijections:					*)
(*									*)
(*           |- (!a. ABS(REP a) = a) /\ (!r. P r = (REP(ABS r) = r)   	*)
(*									*)
(*	 then prove_rep_fn_onto th will prove and return a theorem	*)
(*	 stating that the representation function REP is onto:		*)
(*									*)
(*	    |- !r. P r = (?a. r = REP a)				*)
(*									*)
(* --------------------------------------------------------------------- *)

fun prove_rep_fn_onto th =
   let val [th1,th2] = CONJUNCTS th
       val (Bvar,Body) = dest_forall(concl th2)
       val (_,eq) = dest_eq Body
       val (RE, ar) = dest_comb(lhs eq)
       val a = mk_primed_var("a", type_of ar)
       val sra = mk_eq(Bvar, mk_comb(RE, a))
       val ex = mk_exists(a, sra)
       val imp1 = EXISTS (ex,ar) (SYM(ASSUME eq))
       val v = genvar (type_of Bvar)
       and A = rator ar
       and ass = AP_TERM RE (SPEC a th1)
       val th = SUBST[v |-> SYM(ASSUME sra)]
                 (mk_eq(mk_comb(RE,mk_comb(A, v)),v)) ass
       val imp2 = CHOOSE (a,ASSUME ex) th
       val swap = IMP_ANTISYM_RULE (DISCH eq imp1) (DISCH ex imp2)
   in
   GEN Bvar (TRANS (SPEC Bvar th2) swap)
   end
   handle HOL_ERR _ => raise ERR "prove_rep_fn_onto" ""
        | Bind => raise ERR "prove_rep_fn_onto"
                            ("Theorem not of right form: must be\n "^
                             "|- (!a. to (from a) = a) /\\ "^
                             "(!r. P r = (from (to r) = r))")

(* ---------------------------------------------------------------------*)
(* NAME: prove_abs_fn_onto	 					*)
(*									*)
(* DESCRIPTION: prove that a type abstraction function is onto. 	*)
(*									*)
(* USAGE: if th is a theorem of the kind returned by the ML function	*)
(*        define_new_type_bijections:					*)
(*									*)
(*           |- (!a. ABS(REP a) = a) /\ (!r. P r = (REP(ABS r) = r)   	*)
(*									*)
(*	 then prove_abs_fn_onto th will prove and return a theorem	*)
(*	 stating that the abstraction function ABS is onto:		*)
(*									*)
(*	    |- !a. ?r. (a = ABS r) /\ P r				*)
(*									*)
(* ---------------------------------------------------------------------*)

fun prove_abs_fn_onto th =
   let val [th1,th2] = CONJUNCTS th
       val (bv_th1,Body) = dest_forall(concl th1)
       val (A,Rand) = dest_comb(lhs Body)
       val R = rator Rand
       val rb = mk_comb(R, bv_th1)
       val bth1 = SPEC bv_th1 th1
       val thm1 = EQT_ELIM(TRANS (SPEC rb th2) (EQT_INTRO (AP_TERM R bth1)))
       val thm2 = SYM bth1
       val (r,Body) = dest_forall(concl th2)
       val P = rator(lhs Body)
       val ex = mk_exists(r,
                  mk_conj(mk_eq(bv_th1,mk_comb(A, r)), mk_comb(P, r)))
   in GEN bv_th1 (EXISTS(ex,rb) (CONJ thm2 thm1))
   end
   handle HOL_ERR _ => raise ERR "prove_abs_fn_onto" ""
        | Bind => raise ERR "prove_abs_fn_one_onto"
                            ("Theorem not of right form: must be\n "^
                             "|- (!a. to (from a) = a) /\\ "^
                             "(!r. P r = (from (to r) = r))")


(* ---------------------------------------------------------------------*)
(* NAME: prove_abs_fn_one_one	 					*)
(*									*)
(* DESCRIPTION: prove that a type abstraction function is one-to-one. 	*)
(*									*)
(* USAGE: if th is a theorem of the kind returned by the ML function	*)
(*        define_new_type_bijections:					*)
(*									*)
(*           |- (!a. ABS(REP a) = a) /\ (!r. P r = (REP(ABS r) = r)   	*)
(*									*)
(*	 then prove_abs_fn_one_one th will prove and return a theorem	*)
(*	 stating that the abstraction function ABS is one-to-one:	*)
(*									*)
(*	    |- !r r'. P r ==>						*)
(*		      P r' ==>						*)
(*		      (ABS r = ABS r') ==> (r = r')			*)
(*									*)
(* ---------------------------------------------------------------------*)

fun prove_abs_fn_one_one th =
   let val [th1,th2] = CONJUNCTS th
       val (r, Body) = dest_forall(concl th2)
       val P = rator(lhs Body)
       val (A, Rand) = dest_comb(lhs(snd(dest_forall(concl th1))))
       val R = rator Rand
       val r' = variant [r] r
       val r_eq_r' = mk_eq (r, r')
       val Pr = mk_comb(P, r)
       val Pr' = mk_comb(P, r')
       val as1 = ASSUME Pr
       and as2 = ASSUME Pr'
       val t1 = EQ_MP (SPEC r th2) as1
       and t2 = EQ_MP (SPEC r' th2) as2
       val eq = mk_eq(mk_comb(A, r), mk_comb(A, r'))
       val v1 = genvar(type_of r)
       and v2 = genvar(type_of r)
       val i1 = DISCH eq (SUBST [v1 |-> t1, v2 |-> t2]
                            (mk_eq(v1,v2)) (AP_TERM R (ASSUME eq)))
       val i2    = DISCH r_eq_r' (AP_TERM A (ASSUME r_eq_r'))
       val thm   = IMP_ANTISYM_RULE i1 i2
       val disch = DISCH Pr (DISCH Pr' thm)
   in
     GEN r (GEN r' disch)
   end
   handle HOL_ERR _ => raise ERR "prove_abs_fn_one_one"  ""
        | Bind => raise ERR "prove_abs_fn_one_one"
                            ("Theorem not of right form: must be\n "^
                             "|- (!a. to (from a) = a) /\\ "^
                             "(!r. P r = (from (to r) = r))")

(*---------------------------------------------------------------------------*)
(* Rules related to "semantic tags" for controlling rewriting                *)
(*---------------------------------------------------------------------------*)

fun MK_BOUNDED th n =
  if n<0 then raise ERR "MK_BOUNDED" "negative bound"
  else
    ADD_ASSUM (mk_comb(bounded_tm, mk_var(Int.toString n, bool))) th

fun DEST_BOUNDED th =
    case HOLset.find (aconv bounded_tm o rator) (hypset th) of
      SOME h => let
        val arg = rand h
      in
        (PROVE_HYP (EQ_MP (SYM (SPEC arg BOUNDED_THM)) TRUTH) th,
         valOf (Int.fromString (#1 (dest_var arg))))
      end
    | NONE => raise ERR "DEST_BOUNDED" "Theorem not bounded"

val Ntimes = MK_BOUNDED;
val Once = C Ntimes 1;

val is_comm = can (kind_match_term comm_tm);
val is_assoc = can (kind_match_term assoc_tm);

(*---------------------------------------------------------------------------*)
(* Classify a pair of theorems as one assoc. thm and one comm. thm. Then     *)
(* return pair (A,C) where A has the form |- f(x,f(y,z)) = f (f(x,y),z)      *)
(*---------------------------------------------------------------------------*)

fun regen th = GENL (free_vars_lr (concl th)) th;

fun norm_ac (th1,th2) =
 let val th1' = SPEC_ALL th1
     val th2' = SPEC_ALL th2
     val tm1 = concl th1'
     val tm2 = concl th2'
 in if is_comm tm2 then
      if is_assoc tm1 then (regen th1',regen th2')
      else
        let val th1a = SYM th1'
        in if is_assoc (concl th1a)
           then (regen th1a,regen th2')
           else (HOL_MESG "unable to AC-normalize input";
                 raise ERR "norm_ac" "failed")
        end
    else if is_comm tm1 then
      if is_assoc tm2 then (regen th2',regen th1')
      else
        let val th2a = SYM th2'
        in if is_assoc (concl th2a) then (regen th2a,regen th1')
           else (HOL_MESG "unable to AC-normalize input";
                 raise ERR "norm_ac" "failed")
        end
    else (HOL_MESG "unable to AC-normalize input";
          raise ERR "norm_ac" "failed")
 end;

(*---------------------------------------------------------------------------*)
(* Take an AC pair, normalize them, then prove left-commutativity            *)
(*---------------------------------------------------------------------------*)

fun MK_AC_LCOMM (th1,th2) =
   let val (a,c) = norm_ac(th1,th2)
       val lcomm = MATCH_MP (MATCH_MP LCOMM_THM a) c
   in
     (regen (SYM (SPEC_ALL a)), c, lcomm)
   end

end (* Drule *)

(* ----------------------------------------------------------------------
    HO_PART_MATCH and bound variables
   ----------------------------------------------------------------------

Given

  val th = GSYM RIGHT_EXISTS_AND_THM
         = |- P /\ (?x. Q x) = ?x. P /\ Q x

the old implementation would come back from

  HO_REWR_CONV th ``P x /\ ?y. Q y``

with

  (P x /\ ?y. Q y) = (?x'. P x /\ Q x')

This is because of the following: in HO_PART_MATCH, there is code that
attempts to rename bound variables from the rewrite theorem so that
they match the bound variables in the original term.

After performing the ho_match_term, and doing the instantiation, the
resulting theorem is

  (P x /\ ?x. Q x) = (?x'. P x /\ Q x')

The renaming on the rhs has to happen to avoid unsoundness, and
happens immediately in the name-carrying kernel, and will happen
whenever a dest_abs is done in the dB kernel.  Anyway, in the fixup
phase, the implementation first notices that ?x.Q x in the pattern
corresponds to ?y. Q y in the term.  It then passes over the term
replacing bound x's with y's.  (In the dB kernel, it can't see that
the bound variable on the right is actually still an x because
dest_abs will rename the x to x'.)

So, I thought I would fix this by doing the bound-variable fixup on
the pattern theorem before it was instantiated.  So, I look at

  P /\ ?x. Q x

compare it to P x /\ ?y. Q y, and see that bound x needs to be
replaced by y throughout the theorem, giving

  (P /\ ?y. Q y) = (?y. P /\ Q y)

Then the instantiation can be done, producing

  (P x /\ ?y. Q y) = (?y. P x /\ Q y)

and it's all lovely.  (This is also more efficient than the current
method because the traversal is only of the original theorem, not its
possibly much larger instantiation.)

Unfortunately, there are still problems.  Consider, this LHS

  p /\ ?P. FINITE P

when you do the bound variable fix to the rewrite theorem early, you
get

  (P /\ ?P. Q P) = (?P'. P /\ Q P')

The free variables in the theorem itself get in the way.  The fix is
to examine whether or not the new bound variable clashes with a named
variable in the body of the theorem.  If so, then the theorem has that
variable instantiated to a genvar.  (The instantiation returned by
ho_match_term also needs to be adjusted because it may be expecting to
instantiate some of the pattern theorem's free variables.)

So, the code in match_bvs figures out what renamings of bound
variables need to happen, and then a traversal of the *whole* thoerem
takes to see what free variables need to be instantiated into genvars.
Then, given the example, the main code in HO_PART_MATCH will produce

  (%gv /\ ?x. Q x) = (?x. %gv /\ Q x)

before then fixing the bound variables to produce

  (%gv /\ ?P. Q P) = (?P. %gv /\ Q P)

Finally, this theorem will be instantiated with bindings for Q and
%gv [%gv |-> p, Q |-> FINITE].

                    ------------------------------

Part 2.

Even with the above in place, the ho-part matcher can make a mess of
things like the congruence rule for RES_FORALL_CONG,

  |- (P = Q) ==> (!x. x IN Q ==> (f x = g x)) ==>
     (RES_FORALL P f = RES_FORALL Q g)

HO_PART_MATCH only gets called with its "partfn" being to look at the
LHS of the last equation.  Then, when the side conditions are looked
over, x gets picked as a bound variable, and any bound variable in f
gets ignored.

The code in munge_bvars gets around this failing by searching the
whole theorem for instances of variables that are going to be
instantiated with abstractions that are next to bound variables.  (In
the example, this search will find f applied to the bound x.)  If such
a situation is found, it specifies that the bound variable be renamed
to match the bound variable of the abstraction.

In this way

   !y::P. Q y

won't get rewritten to

   !x::P'. Q' x

                    ------------------------------

Part 3. (By Peter V. Homeier)

The above code was broken for higher order rewriting, such as

val th = ASSUME ``!f:'a->'b. A (\x:'c. B (f (C x)) :'d) = (\x. f x)``;
val tm = ``A (\rose:'c. B (g (C rose :'a) (C rose) :'b) :'d) : 'a->'b``;
HO_PART_MATCH lhs th tm;

produced

   A (\rose. B (g (C rose) (C rose))) = (\gvar. g gvar gvar)

where gvar was a freshly generated "genvar", instead of the correct

   A (\rose. B (g (C rose) (C rose))) = (\rose. g rose rose)

The reason the prior code did not work was that not only was the
match of f with (\y. Q y) recognized for the Part 2 example above,
but also the match of f with (\gvar. g gvar gvar) in the "rose" example.
The code then "munged" the result by trying to change instances of the
"rose" bound variable to "gvar".

This was fixed by tightening the condition for entrance to the set of
bound variables which are to be so "munged", by adding the condition
that the bound variables ("y" in the Part 2 example, "gvar" in this one)
must all be contained within the set of bound variables within the term
"tm".  If they are not, then the "munge" operation is not needed, since
that attempts to alter bound variable names to fit the given term,
and if the suggested new variable names did not come from the term,
there is no reason to change the old ones.

*)
