structure OmegaMLShadow =
struct

(* ----------------------------------------------------------------------
    Implementation of "shadow chasing" in ML.  This procedure can find
    a real shadow refutation without forcing all of the shadow to be
    computed in the logic; a path to false can be found that only
    involves a small proportion of the possible logical inferences.

    Alternatively, if the shadow is exact, then this procedure can
    also generate witnesses for the logic to exploit, again saving it
    from having to do a lot of calculation internally.
   ---------------------------------------------------------------------- *)

open HolKernel boolLib

open intSyntax

(* ----------------------------------------------------------------------
    The factoid datatype

    A factoid c[0..n] represents the term
       0 <= c[0] * v_0 + .. + c[n-1] * v_{n-1} + c[n] * 1
    The factoid "key" is the vector of variable coefficients, leaving
    out the constant part.
   ---------------------------------------------------------------------- *)

datatype factoid =
         ALT of Arbint.int Vector.vector

type factoid_key = Arbint.int Vector.vector

fun factoid_key f =
    case f of
      ALT av => Vector.extract(av, 0, SOME (Vector.length av - 1))
fun factoid_constant f =
    case f of
      ALT av => Vector.sub(av, Vector.length av - 1)

fun factoid_size f =
    case f of ALT av => Vector.length av

fun split_factoid f = (factoid_key f, factoid_constant f)

fun zero_var_factoid f =
    Vector.foldl (fn (ai, b) => b andalso ai = Arbint.zero) true
                 (factoid_key f)

val the_false_factoid = ALT (Vector.fromList [Arbint.fromInt ~1])
fun false_factoid f =
    zero_var_factoid f andalso Arbint.<(factoid_constant f, Arbint.zero)
fun true_factoid f =
    zero_var_factoid f andalso Arbint.<=(Arbint.zero, factoid_constant f)

fun eval_factoid_rhs vmap f = let
  val maxdex = factoid_size f - 1
  open Arbint Vector
  fun foldthis (i, ai, acc) =
      if ai = zero then acc
      else if i = maxdex then ai + acc
      else ai * PIntMap.find i vmap + acc
in
  case f of
    ALT fv => foldli foldthis zero (fv, 0, NONE)
end

fun eval_factoid_except vmap i f = let
  val maxdex = factoid_size f - 1
  open Arbint Vector
  fun foldthis (j, ai, acc) =
      if ai = zero orelse i = j then acc
      else if j = maxdex then ai + acc
      else ai * PIntMap.find j vmap + acc
in
  case f of
    ALT fv => foldli foldthis zero (fv, 0, NONE)
end

val negate_key = Vector.map Arbint.~

fun keyhash v =
    if Arbint.<=(Arbint.zero,Vector.sub(v, 0)) then Polyhash.hash v
    else ~(Polyhash.hash (Vector.map Arbint.~ v))


(* "prints" factoids *)
fun factoid_pairings vars f =
    case f of
      ALT av => Vector.foldri
                (fn (i, ai, list) =>
                    (Arbint.toString ai, List.nth(vars, i)) :: list)
                [] (av, 0, NONE)

(* ----------------------------------------------------------------------
    combine_real_factoids i f1 f2

    takes two factoids and produces a fresh one by "variable
    elimination" over the i'th variable in the vector.  It requires
    that the coefficient of v_i is strictly positive in f1, and
    strictly negative in f2.  The combination may produce a factoid where
    the coefficients can all be divided through by some number, but
    this factor won't be the gcd of the coefficients of v_i; this
    factor is eliminated from the outset.
   ---------------------------------------------------------------------- *)

fun combine_real_factoids i f1 f2 =
    case (f1, f2) of
      (ALT av1, ALT av2) => let
        open Arbint Vector CooperMath
        val c0 = sub(av1, i)
        val d0 = ~ (sub(av2, i))
        val l = lcm (c0, d0)
        val c = l div d0
        val d = l div c0
        fun gen j = c * sub(av2, j) + sub(av1, j) * d
      in
        ALT (tabulate(length av1, gen))
      end

(* ----------------------------------------------------------------------
    combine_dark_factoids i lower upper

    takes two factoids and combines them to produce a new, "dark shadow"
    factoid.  As above, the first one must have a positive coefficient of
    i, and the second a negative coefficient.
   ---------------------------------------------------------------------- *)

fun combine_dark_factoids i low up =
    case (low, up) of
      (ALT L, ALT U) => let
        open Arbint Vector
        (* have ~L <= ax /\ bx <= U *)
        val a = sub(L, i)
        val b = ~(sub(U, i))
        val maxdex = Int.-(length L, 1)
        fun gen j = let
          val base =  a * sub(U, j) + b * sub(L, j)
        in
          if j = maxdex then base - ((a - one) * (b - one))
          else base
        end
      in
        ALT (tabulate(Int.+(maxdex, 1), gen))
      end


(* ----------------------------------------------------------------------
    factoid_gcd f

    eliminates common factors in the variable coefficients of a factoid,
    or raises the exception no_gcd, if there is no common factor.
   ---------------------------------------------------------------------- *)

exception no_gcd
fun factoid_gcd f =
    case f of
      ALT av => let
        open Vector CooperMath
        val g = foldli (fn (_, c, g0) => gcd (Arbint.abs c, g0))
                       Arbint.zero
                       (av, 0, SOME (length av - 1))
      in
        if g = Arbint.one then raise no_gcd
        else ALT (map (fn c => Arbint.div(c, g)) av)
      end

(* ----------------------------------------------------------------------
    term_to_factoid tm

    returns the factoid corresponding to tm.  tm is thus of the form
      0 <= c1 * v1 + ... + cn * vn + num
    Assumes that the variables are in the "correct" order.
   ---------------------------------------------------------------------- *)

fun term_to_factoid tm = let
  val summands = strip_plus (rand tm)
  fun sum2c t =
      int_of_term (#1 (dest_mult t))
      handle HOL_ERR _ => int_of_term t
in
  ALT (Vector.fromList (map sum2c summands))
end

(* ----------------------------------------------------------------------
    factoid_to_term vars f

    returns the term corresponding to f, interpreting f over the list of
    variables vars.
   ---------------------------------------------------------------------- *)

fun factoid_to_term vars f =
    case f of
      ALT av => let
        open Vector
        fun varcoeff (i, c, t0) =
            if c = Arbint.zero then t0
            else let
                val cv = mk_mult(term_of_int c, List.nth(vars, i))
              in
                case t0 of NONE => SOME cv | SOME t => SOME (mk_plus(t, cv))
              end
        val varpart = foldli varcoeff NONE (av, 0, SOME (length av - 1))
        val numpart = term_of_int (sub(av,length av - 1))
      in
        case varpart of
          NONE => numpart
        | SOME t => mk_plus(t, numpart)
      end

(* ----------------------------------------------------------------------
    The derivation datatype
   ---------------------------------------------------------------------- *)

(* a derivation represents a proof of a factoid *)
datatype derivation =
         ASM of term
       | REAL_COMBIN of int * derivation * derivation
       | GCD_CHECK of derivation
       | DIRECT_CONTR of derivation * derivation

datatype result = CONTR of derivation
                | SATISFIABLE of Arbint.int PIntMap.t
                | NO_CONCL

fun direct_contradiction(d1, d2) = CONTR (DIRECT_CONTR(d1, d2))

fun gcd_check_dfactoid (df as (f, d)) =
    (factoid_gcd f, GCD_CHECK d) handle no_gcd => df

fun split_dfactoid (f, d) = (factoid_key f, (factoid_constant f, d))
fun dfactoid_key (f, d) = factoid_key f
fun dfactoid_derivation (f, d) = d

fun term_to_dfactoid t = (term_to_factoid t, ASM t)

(* ----------------------------------------------------------------------
    The "elimination mode" datatype.

    This records what sort of shadow we're currently working on.
   ---------------------------------------------------------------------- *)

datatype elimmode = REAL | DARK | EXACT

fun inexactify EXACT = REAL
  | inexactify x = x

fun mode_result em result =
    case em of
      EXACT => result
    | REAL => (case result of SATISFIABLE _ => NO_CONCL | x => x)
    | DARK => (case result of CONTR _ => NO_CONCL | x => x)

fun combine_dfactoids em i ((f1, d1), (f2, d2)) =
    case em of
      DARK => (combine_dark_factoids i f1 f2, d1)
    | _ => (combine_real_factoids i f1 f2, REAL_COMBIN(i, d1, d2))


(* ----------------------------------------------------------------------
    The "ptree" datatype

    I'm using a Patricia tree to store my sets of constraints.  The keys
    are the hashes of the constraint keys.  The items are lists
    (buckets) of dfactoids.
   ---------------------------------------------------------------------- *)

fun fkassoc k alist =
    case List.find (fn (f, data) => k = factoid_key f) alist of
      NONE => raise PIntMap.NotFound
    | SOME x => x

fun lookup_fkey ptree fk =
  fkassoc fk (PIntMap.find (keyhash fk) ptree)

val dbempty = PIntMap.empty

fun dbfold (f : ((factoid * derivation) * 'a) -> 'a) (acc:'a) ptree =
    PIntMap.fold (fn (i,b,acc) => List.foldl f acc b) acc ptree

fun dbapp (f : factoid * derivation -> unit) ptree =
    PIntMap.app (fn (i,b) => List.app f b) ptree

fun dbinsert (df as (f,d)) ptree =
    #1 (PIntMap.addf (fn b => df :: b) (keyhash (factoid_key f)) [df] ptree)

fun dbchoose ptree = let
  val (_, (_, a_bucket)) = PIntMap.choose ptree
in
  hd a_bucket
end

fun dbwidth ptree = let
  val (f,d) = dbchoose ptree
in
  factoid_size f
end



(* ----------------------------------------------------------------------
    add_factoid ptree df

    Precondition: df is neither a trivially true nor false factoid.

    adds a dfactoid (i.e., a factoid along with its derivation) to a
    Patricia tree of accumulating factoids.  If the factoid is
    actually redundant, because there is already a factoid with the
    same constraint key in the tree with a less or equal constant,
    then the tree is returned unchanged.  The return value is the new
    tree coupled with a boolean which is true iff the tree changed.
   ---------------------------------------------------------------------- *)

fun add_factoid ptree (df as (f,d)) = let
  val fkc as (fk, fc) = split_factoid f
  exception Redundant
  fun merge alist = let
    val ((f',_), samehashes) =
        Lib.pluck (fn (f', _) => factoid_key f' = fk) alist
  in
    if Arbint.<(fc, factoid_constant f') then df :: samehashes
    else raise Redundant
  end handle HOL_ERR _ => df :: alist (* HOL_ERR might come from Lib.pluck *)
in
  (#1 (PIntMap.addf merge (keyhash fk) [df] ptree), true)
  handle Redundant => (ptree, false)
end

(* ----------------------------------------------------------------------
    add_check_factoid ptree df next kont

    Precondition: df is neither a trivially true nor false factoid.
    Types:
      next:     ptree -> (result -> 'a) -> 'a
      kont:     result -> 'a

   ---------------------------------------------------------------------- *)

fun add_check_factoid ptree0 (df as (f,d)) next kont = let
  val (ptree, changed) = add_factoid ptree0 df
in
  if not changed then next ptree kont
  else let
      val (fk,fc) = split_factoid f
      val (negdf as (negf, negd)) = lookup_fkey ptree (negate_key fk)
      val negc = factoid_constant negf
      open Arbint
    in
      if negc < ~fc then kont (direct_contradiction(d, negd))
      else next ptree kont
    end handle PIntMap.NotFound => next ptree kont
end

(* ----------------------------------------------------------------------
    has_one_var ptree

    returns true if all of ptree's factoids are over just one variable
    (and they're all the same variable)
   ---------------------------------------------------------------------- *)

fun has_one_var ptree = let
  exception return_false
  fun checkkey (i,c,acc) =
      if c = Arbint.zero then acc
      else
        case acc of
          NONE => SOME i
        | _ => raise return_false
  fun check ((f,d),a) = let
    val fk = factoid_key f
    val fk_single = valOf (Vector.foldli checkkey NONE (fk, 0, NONE))
  in
    case a of
      NONE => SOME fk_single
    | SOME i => if i = fk_single then a else raise return_false
  end
in
  (dbfold check NONE ptree; true) handle return_false => false
end


(* ----------------------------------------------------------------------
    one_var_analysis ptree em

    Precondition: the dfactoids in ptree have just one variable with a
    non-zero coefficient, and its everywhere the same variable.  Our aim
    is to either derive a contradiction, or to return a satisfying
    assignment.  Our gcd_checks will have ensured that our variable
    (call it x) will only have coefficients of one at this point, so
    we just need to check that the maximum of the lower bounds is less
    than or equal to the minimum of the lower bounds.  If it is then
    return either as a satisfying valuation for x.  Otherwise return
    false, combining the maximum lower and the minimum upper constraint.
   ---------------------------------------------------------------------- *)

fun one_var_analysis ptree em = let
  val (a_constraint, _) = dbchoose ptree
  fun find_var (i, ai, NONE) = if ai <> Arbint.zero then SOME i else NONE
    | find_var (_, _, v as SOME _) = v
  val x_var =
      valOf (Vector.foldli find_var NONE (factoid_key a_constraint, 0, NONE))
  open Arbint
  fun assign_factoid (df, acc as (upper, lower)) = let
    val (fk, (fc, d)) = split_dfactoid df
  in
    if Vector.sub(fk, x_var) < zero then
      case upper of
        NONE => (SOME (fc, d), lower)
      | SOME (c', d') => if fc < c' then (SOME (fc, d), lower) else acc
    else
      case lower of
        NONE => (upper, SOME (~fc, d))
      | SOME (c', d') => if ~fc > c' then (SOME (~fc,d), lower) else acc
  end
  val (upper, lower) =
      PIntMap.fold (fn (_,b,acc) => foldl assign_factoid acc b)
                   (NONE,NONE)
                   ptree
  open PIntMap
in
  case (upper, lower) of
    (NONE, NONE) => raise Fail "one_var_analysis: this can't happen"
  | (SOME (c, _), NONE) => if em = REAL then NO_CONCL
                           else SATISFIABLE (add x_var c empty)
  | (NONE, SOME (c, _)) => if em = REAL then NO_CONCL
                           else SATISFIABLE (add x_var c empty)
  | (SOME (u,du), SOME (l, dl)) =>
    if u < l then
      if em = DARK then NO_CONCL
      else direct_contradiction(du,dl)
    else
      if em = REAL then NO_CONCL
      else SATISFIABLE (PIntMap.add x_var u PIntMap.empty)
end

(* ----------------------------------------------------------------------
    throwaway_redundant_factoids ptree nextstage kont

    checks ptree for variables that are constrained only in one sense
    (i.e., with upper or lower bounds only).

    The function nextstage takes a ptree and a continuation; it is
    called when ptree has run out of constraints that can be thrown
    away.

    The continuation function kont is of type result -> 'a.
   ---------------------------------------------------------------------- *)

fun throwaway_redundant_factoids ptree nextstage kont = let
  val numvars = dbwidth ptree - 1
  val has_low = Array.array(numvars, false)
  val has_up = Array.array(numvars, false)

  fun assess fk = let
    fun appthis (i, ai) = let
      open Arbint
    in
      case compare(ai,zero) of
        LESS => Array.update(has_up, i, true)
      | EQUAL => ()
      | GREATER => Array.update(has_low, i, true)
    end
  in
    Vector.appi appthis (fk, 0, NONE)
  end
  val () = dbapp (fn (f,d) => assess (factoid_key f)) ptree

  fun find_redundant_var i =
      if i = numvars then NONE
      else if Array.sub(has_up, i) = Array.sub(has_low, i) then
        find_redundant_var (i + 1)
      else SOME (i, Array.sub(has_up, i))
in
  case find_redundant_var 0 of
    NONE => nextstage ptree kont
  | SOME(i, hasupper) => let
      fun partition (df as (f,d), (pt, elim)) = let
        open Arbint
      in
        if Vector.sub(factoid_key f, i) = zero then
          (dbinsert df pt, elim)
        else
          (pt, df :: elim)
      end
      val (newptree, elim) = dbfold partition (dbempty, []) ptree
      fun handle_result r =
          case r of
            SATISFIABLE vmap => let
              open Arbint
              fun mapthis (f,_) = (eval_factoid_except vmap i f) div
                                  abs (Vector.sub(factoid_key f, i))
              val evaluated = map mapthis elim
              val foldfn = if hasupper then Arbint.min else Arbint.max
            in
              SATISFIABLE (PIntMap.add i (foldl foldfn (hd evaluated)
                                                (tl evaluated))
                                       vmap)
            end
          | x => x
    in
      throwaway_redundant_factoids newptree nextstage (kont o handle_result)
    end
end

(* ----------------------------------------------------------------------
    exact_var ptree

    An exact var is one that has coefficients of one in either all of its
    upper bounds or all of its lower bounds.  This function returns
    SOME v if v is an exact var in ptree, or NONE if there is no exact
    var.
   ---------------------------------------------------------------------- *)

fun exact_var ptree = let
  val up_coeffs_unit = Array.array(dbwidth ptree - 1, true)
  val low_coeffs_unit = Array.array(dbwidth ptree - 1, true)
  fun appthis (f,d) = let
    open Arbint
    fun examine_key (i, ai) =
        case compare(ai,zero) of
          LESS => if abs ai <> one then Array.update(up_coeffs_unit, i, false)
                  else ()
        | EQUAL => ()
        | GREATER => if ai <> one then Array.update(low_coeffs_unit, i, false)
                     else ()
  in
    Vector.appi examine_key (factoid_key f, 0, NONE)
  end
  val () = dbapp appthis ptree
  fun check_index (i, b, acc) = if b then SOME i else acc
in
  case Array.foldli check_index NONE (low_coeffs_unit, 0, NONE) of
    NONE => Array.foldli check_index NONE (up_coeffs_unit, 0, NONE)
  | x => x
end

(* ----------------------------------------------------------------------
    least_coeff_var ptree

    Returns the variable whose coefficients' absolute values sum to the
    least amount.
   ---------------------------------------------------------------------- *)

fun least_coeff_var ptree = let
  val sums = Array.array(dbwidth ptree - 1, Arbint.zero)
  fun appthis df = let
    open Arbint
    fun add_in_c (i, ai) =
        Array.update(sums, i, Array.sub(sums, i) + abs ai)
  in
    Vector.appi add_in_c (dfactoid_key df, 0, NONE)
  end
  val () = dbapp appthis ptree
  fun find_min (i,ai,NONE) = SOME(i,ai)
    | find_min (i,ai, acc as SOME(mini, minai)) =
      if Arbint.<(ai, minai) then SOME(i,ai) else acc
in
  #1 (valOf (Array.foldli find_min NONE (sums, 0, NONE)))
end

(* ----------------------------------------------------------------------
    generate_row (pt0, em, i, up, lows, next, kont)

    Types:
      pt0       :ptree
      em        :elimmode
      i         :int  (a variable index)
      up        :dfactoid
      lows      :dfactoid list
      next      :ptree -> (result -> 'a) -> 'a
      kont      :result -> 'a

    "Resolves" dfactoid against all the factoids in lows, producing new
    factoids, which get added to the ptree.  If a factoid is directly
    contradictory, then return it immediately, using kont.  If a factoid
    is vacuous, drop it.
   ---------------------------------------------------------------------- *)

fun generate_row (pt0, em, i, up, lows, next, kont) =
    case lows of
      [] => next pt0 kont
    | low::lowtl => let
        val (df as (f,d)) =
            gcd_check_dfactoid (combine_dfactoids em i (low, up))
        fun after_add pt k = generate_row(pt, em, i, up, lowtl, next, k)
      in
        if true_factoid f then after_add pt0 kont
        else if false_factoid f then kont (CONTR d)
        else add_check_factoid pt0 df after_add kont
      end

(* ----------------------------------------------------------------------
    generate_crossproduct (pt0, em, i, ups, lows, next, kont)

    Types:
      pt0       :ptree
      em        :elimmode
      i         :integer (a variable index)
      ups       :dfactoid list
      lows      :dfactoid list
      next      :ptree -> (result -> 'a) -> 'a
      kont      :result -> 'a
   ---------------------------------------------------------------------- *)

fun generate_crossproduct (pt0, em, i, ups, lows, next, kont) =
    case ups of
      [] => next pt0 kont
    | u::us => let
        fun after pt k = generate_crossproduct(pt, em, i, us, lows, next, k)
      in
        generate_row(pt0, em, i, u, lows, after, kont)
      end

(* ----------------------------------------------------------------------
    extend_vmap ptree i vmap

    vmap provides values for all of the variables present in ptree's
    factoids except i.  Use it to evaluate all of the factoids, except
    at variable i and to then return vmap extended with a value for
    variable i that respects all of the factoids.

    Note definite parallels with code in one_var_analysis.
   ---------------------------------------------------------------------- *)

fun extend_vmap ptree i vmap = let
  fun categorise ((f, _), (acc as (lower, upper))) = let
    val c0 = eval_factoid_except vmap i f
    val fk = factoid_key f
    open Arbint
    val coeff = Vector.sub(fk, i)
  in
    if coeff <  zero then let (* upper *)
        val c = c0 div ~coeff
      in
        case upper of
          NONE => (lower, SOME c)
        | SOME c' => if c < c' then (lower, SOME c) else acc
      end
    else let (* lower *)
        val c = ~(c0 div coeff)
      in
        case lower of
          NONE => (SOME c, upper)
        | SOME c' => if c > c' then (SOME c, upper) else acc
      end
  end
  val (lower, upper) = dbfold categorise (NONE, NONE) ptree
  open Arbint
  val _ = valOf lower <= valOf upper orelse raise Fail "urk in extend map"
in
  PIntMap.add i (valOf lower) vmap
end




(* ----------------------------------------------------------------------
    one_step ptree em nextstage kont

    Types:
      em         :elimmode
      nextstage  :ptree -> elimmode -> (result -> 'a) -> 'a
      kont       :result -> 'a

    Assume that ptree doesn't contain anything directly contradictory,
    and that there aren't any redundant constraints around (these have
    been thrown away by throwaway_redundant_factoids).

    Perform one step of the shadow calculation algorithm:
      (a) if there is only one variable left in all of the constraints
          in ptree do one_var_analysis to return some sort of result,
          and pass this result to kont.
      (b) otherwise, decide on a variable to eliminate.  If there's a
          variable that allows for an exact shadow (has coefficients of
          one in all of its lower-bound or upper-bound occurrences),
          pick this.  Otherwise, take the variable whose coefficients'
          absolute values sum to the least amount.
      (c) the initial tree of the result contains all of those
          constraints from the original which do not mention the
          variable to be eliminated.
      (d) divide the constraints that do mention the variable to be
          eliminated into upper and lower bound sets.
    Then (in generate_crossproduct):
      (e) work through all of the possible combinations in
            upper x lower
          using combine_dfactoids.  Each new dfactoid has to be added
          to the accumulating tree.  This may produce a direct
          contradiction, in which case, stop and return this (again,
          using the kont function).  Otherwise keep going.
      (f) pass the completed new ptree to nextstage, with an augmented
          continuation that copes with satisfiable results (though
          satisfiable results won't come back if the mode is REAL
          of course).
   ---------------------------------------------------------------------- *)

fun one_step ptree em nextstage kont = let
  val (var_to_elim, mode) =
      case exact_var ptree of
        SOME i => (i, em)
      | NONE => (least_coeff_var ptree, inexactify em)
  fun categorise (df, (notmentioned, uppers, lowers)) = let
    open Arbint
  in
    case compare(Vector.sub(dfactoid_key df, var_to_elim), zero) of
      LESS => (notmentioned, df::uppers, lowers)
    | EQUAL => (dbinsert df notmentioned, uppers, lowers)
    | GREATER => (notmentioned, uppers, df::lowers)
  end
  val (newtree0, uppers, lowers) =
      dbfold categorise (dbempty, [], []) ptree
  fun newkont r =
      case (em, mode) of
        (EXACT, EXACT) => kont r
      | (EXACT, REAL) => let
        in
          case r of
            CONTR _ => kont r
          | _ => one_step ptree DARK nextstage kont
        end
      | (REAL, REAL) => kont r
      | (DARK, DARK) => let
        in
          case r of
            SATISFIABLE vmap =>
            kont (SATISFIABLE (extend_vmap ptree var_to_elim vmap))
          | CONTR _ => kont NO_CONCL
          | x => kont x
        end
      | _ => raise Fail "Can't happen - in newkont calculation"
  fun newnextstage pt k = nextstage pt mode k
in
  generate_crossproduct(newtree0, em, var_to_elim, uppers, lowers,
                        newnextstage, newkont)
end

(* ----------------------------------------------------------------------
    toplevel ptree em

   ---------------------------------------------------------------------- *)

fun toplevel ptree em kont = let
  fun after_throwaway pt k = one_step pt em toplevel k
in
  if has_one_var ptree then
    kont (mode_result em (one_var_analysis ptree em))
  else
    throwaway_redundant_factoids ptree after_throwaway kont
end


(* ----------------------------------------------------------------------
   simple tests

   fun fromList l = let
     open intSyntax
     val clist = map Arbint.fromInt l
     val lim = length clist - 1
     fun clist2term (x, (acc, n)) = let
       val c = intSyntax.term_of_int x
       val cx = if n = lim then c
                else mk_mult(c, mk_var("x"^Int.toString n, int_ty))
     in
       case acc of
         NONE => (SOME cx, n + 1)
       | SOME a => (SOME(mk_plus(a, cx)), n + 1)
     end
     val t = valOf (#1 (List.foldl clist2term (NONE, 0) clist))
   in
     (ALT (Vector.fromList clist), ASM (mk_leq(zero_tm, t)))
   end

   datatype prettyr = SAT of (string * Arbint.int) list
                    | PCONTR of derivation
                    | PNOCONC
   fun vmap2list vmap = PIntMap.fold(fn(k,v,acc) =>
                                       ("x"^Int.toString k, v)::acc)
                                    [] vmap
   fun display_result r =
       case r of
         SATISFIABLE v => SAT (vmap2list v)
       | CONTR x => PCONTR x
       | NO_CONCL => PNOCONC

   val gentree = List.foldl (fn (df,t) => dbinsert (fromList df) t) dbempty

   fun test l = toplevel (gentree l) EXACT display_result

   test [[2,3,6],[~1,~4,7]]  (* exact elimination *)
   test [[2,3,4],[~3,~4,7]]  (* dark shadow test *)
   test [[2,3,4],[~3,~4,7],[4,5,~10]]  (* another dark shadow *)
   test [[2,3,4],[~3,~4,7],[4,~5,~10]]  (* also satisfiable *)
   time test [[~3,~1,6],[2,1,~5],[3,~1,~3]]



   ---------------------------------------------------------------------- *)


end (* struct *)