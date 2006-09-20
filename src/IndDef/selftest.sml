open HolKernel Parse boolLib IndDefLib IndDefRules arithmeticTheory

fun die s = (print (s^"\n"); OS.Process.exit OS.Process.failure)

val _ = print "*** Testing inductive definitions - mutual recursion\n"

val (oe_rules, oe_ind, oe_cases) = Hol_reln`
  even 0 /\
  (!m. odd m /\ 1 <= m ==> even (m + 1)) /\
  (!m. even m ==> odd (m + 1))
`;

val strongoe = derive_strong_induction (oe_rules, oe_ind)

val _ = print "*** Testing inductive definitions - scheme variables\n"

val (rtc_rules, rtc_ind, rtc_cases) = Hol_reln`
  (!x. rtc r x x) /\
  (!x y z. rtc r x y /\ r y z ==> rtc r x z)
`;

val strongrtc = derive_strong_induction (rtc_rules, rtc_ind)

val _ = print "*** Testing inductive definitions - existential vars\n"

val (rtc'_rules, rtc'_ind, rtc'_cases) = Hol_reln`
  (!x. rtc' r x x) /\
  (!x y. r x y /\ (?z. rtc' r z y) ==> rtc' r x y)
`;

val strongrtc' = derive_strong_induction (rtc'_rules, rtc'_ind)

(* emulate the example in examples/opsemScript.sml *)
val _ = print "*** Testing opsem example\n"
val _ = new_type ("comm", 0)
val _ = new_constant("Skip", ``:comm``)
val _ = new_constant("::=", ``:num -> ((num -> num) -> num) -> comm``)
val _ = new_constant(";;", ``:comm -> comm -> comm``)
val _ = new_constant("If", ``:((num -> num) -> bool) -> comm -> comm -> comm``)
val _ = new_constant("While", ``:((num -> num) -> bool) -> comm -> comm``)
val _ = set_fixity "::=" (Infixr 400);
val _ = set_fixity ";;"  (Infixr 350);

val (rules,induction,ecases) = Hol_reln
     `(!s. EVAL Skip s s)
 /\   (!s V E. EVAL (V ::= E) s (\v. if v=V then E s else s v))
 /\   (!C1 C2 s1 s3.
        (?s2. EVAL C1 s1 s2 /\ EVAL C2 s2 s3) ==> EVAL (C1;;C2) s1 s3)
 /\   (!C1 C2 s1 s2 B. EVAL C1 s1 s2 /\  B s1 ==> EVAL (If B C1 C2) s1 s2)
 /\   (!C1 C2 s1 s2 B. EVAL C2 s1 s2 /\ ~B s1 ==> EVAL (If B C1 C2) s1 s2)
 /\   (!C s B.                           ~B s ==> EVAL (While B C) s s)
 /\   (!C s1 s3 B.
        (?s2. EVAL C s1 s2 /\
              EVAL (While B C) s2 s3 /\ B s1) ==> EVAL (While B C) s1 s3)`;

val _ = if null (hyp rules) then () else die "FAILED!"

val strongeval = save_thm("strongeval",
                          derive_strong_induction(rules, induction))

(* emulate the example in examples/monosetScript.sml *)
val _ = print "*** Testing monoset example\n"
val _ = new_type ("t", 0)
val _ = new_type ("list", 1)
val _ = new_constant ("v", ``:num -> t``)
val _ = new_constant ("app", ``:t list -> t``)
val _ = new_constant ("EVERY", ``:('a -> bool) -> 'a list -> bool``)
val _ = new_constant ("MEM", ``:'a -> 'a list -> bool``)
val _ = new_constant ("ZIP", ``:('a list # 'b list) -> ('a # 'b) list``)

val MONO_UNCURRY = mk_thm([],
  ``(!p:'a q:'b. P p q ==> Q p q) ==> (UNCURRY P x ==> UNCURRY Q x)``)
val MONO_EVERY = mk_thm([], ``(!x:'a. P x ==> Q x) ==>
                              (EVERY P l ==> EVERY Q l)``)
val _ = app add_mono_thm [MONO_UNCURRY, MONO_EVERY]

val (red_rules, red_ind, red_cases) = Hol_reln `
  (!n. red f (v n) (v (f n))) /\
  (!t0s ts. EVERY (\ (t0,t). red f t0 t) (ZIP (t0s, ts)) ==>
            red f (app t0s) (app ts))
`;
val _ = if null (hyp red_rules) then () else die "Hyps in rules - FAILED!\n"

val strongred = save_thm(
  "red_strong_ind",
  derive_strong_induction (red_rules, red_ind));

(* emulate Peter's example *)
val _ = print "*** Testing Peter's example\n"
val _ = new_constant ("nil", ``:'a list``)
val _ = new_constant ("cons", ``:'a -> 'a list -> 'a list``)
val _ = new_constant ("HD", ``:'a list -> 'a``)
val _ = new_constant ("TL", ``:'a list -> 'a list``)
val (ph_rules, ph_ind, ph_cases) = Hol_reln`
  (WF_CX nil) /\
  (!s ty cx. WF_CX cx /\ WF_TYPE cx ty ==> WF_CX (cons (s,ty) cx)) /\

  (!n cx. WF_CX cx ==> WF_TYPE cx (v n)) /\
  (!ts cx s. WF_CX cx /\ MEM (s, HD ts) cx /\ EVERY (\t. WF_TYPE cx t) ts /\
             red SUC (HD ts) (HD (TL ts)) ==>
             WF_TYPE cx (app ts))
`
val _ = if null (hyp ph_rules) then ()
        else die "Hyps in rules - FAILED\n"

val ph_strong = derive_strong_induction(ph_rules, ph_ind)
    handle HOL_ERR _ => die "Failed to prove strong induction"

val _ = OS.Process.exit OS.Process.success


