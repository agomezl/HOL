(* ========================================================================= *)
(* FILE          : psBigSteps.sml                                            *)
(* DESCRIPTION   : Succession of non-backtrackable moves chosen after one    *)
(*                 MCTS call for each step                                   *)
(* AUTHOR        : (c) Thibault Gauthier, Czech Technical University         *)
(* DATE          : 2019                                                      *)
(* ========================================================================= *)

structure psBigSteps :> psBigSteps =
struct

open HolKernel Abbrev boolLib aiLib psMCTS smlParallel

val ERR = mk_HOL_ERR "psBigSteps"

(* -------------------------------------------------------------------------
   Type for examples and distribution derived from a policy
   ------------------------------------------------------------------------- *)

type 'a rlex = ('a * real list) list

(* -------------------------------------------------------------------------
   Tree re-use
   ------------------------------------------------------------------------- *)

fun is_prefix l1 l2 = case (l1,l2) of
    ([],_) => true
  | (_,[]) => false
  | (a1 :: m1, a2 :: m2) => a1 = a2 andalso is_prefix m1 m2

fun is_suffix l1 l2 = is_prefix (rev l1) (rev l2)

fun rm_prefix l1 l2 = case (l1,l2) of
    ([],_) => l2
  | (_,[]) => raise ERR "rm_prefix" ""
  | (a1 :: m1, a2 :: m2) =>
    (if a1 = a2 then rm_prefix m1 m2 else raise ERR "rm_prefix" "")

fun rm_suffix l1 l2 = rev (rm_prefix (rev l1) (rev l2))

fun cut_tree id tree =
  let
    val l = filter (fn x => is_suffix id (fst x)) (dlist tree)
    fun change_node (x,{pol,value,board,sum,vis,status}) =
      (rm_suffix id x,
        {pol=map_snd (rm_suffix id) pol,
         board=board, value=value, sum=sum, vis=vis, status=status})
  in
    dnew id_compare (map change_node l)
  end

(* -------------------------------------------------------------------------
   Big steps and example extraction
   ------------------------------------------------------------------------- *)

fun mk_dis tree =
  let
    val pol = #pol (dfind [] tree)
    val _ = if null pol then raise ERR "mk_dis" "pol" else ()
    fun f (_,cid) = #vis (dfind cid tree) handle NotFound => 0.0
    val dis = map_assoc f pol
    val tot = sum_real (map snd dis)
    val _ = if tot < 0.5 then raise ERR "mk_dis" "tot" else ()
  in
    (dis,tot)
  end

fun debug_ep obj mctsobj dis root =
  if #verbose obj then
  let
    val {game,player,mctsparam} = mctsobj
    val old_eval = #value root
    val new_eval = #sum root / #vis root
    fun f1 (((move,r),_),_) = 
      pretty_real r  ^ ": " ^ #string_of_move game move 
    fun f2 (((move,_),_),r) = 
      pretty_real r  ^ ": " ^ #string_of_move game move
  in
    print_endline ("Old Eval: " ^ pretty_real old_eval);
    print_endline ("New Eval: " ^ pretty_real new_eval);
    print_endline ("Old Policy\n" ^ String.concatWith "\n" (map f1 dis));
    print_endline ("New Policy\n" ^ String.concatWith "\n" (map f2 dis))
  end
  else ()

fun select_bigstep obj mctsobj tree =
  let
    val (dis,_) = mk_dis tree
    val (_,cid) = if #temp_flag obj 
      then select_in_distrib dis 
      else best_in_distrib dis
    val _ = debug_ep obj mctsobj dis (dfind [] tree)
  in
    cid
  end

(* -------------------------------------------------------------------------
   Extracting root examples from bigsteps
   ------------------------------------------------------------------------- *)

fun add_rootex game tree rlex =
  let
    val root = dfind [] tree
    val board  = #board root
    val (dis,tot) = mk_dis tree
    val eval = #sum root / #vis root
    val poli = map (fn (_,r) => r / tot) dis
  in
    (board, eval :: poli) :: rlex
  end

(* -------------------------------------------------------------------------
   MCTS big steps. Ending the search when there is no move available.
   ------------------------------------------------------------------------- *)

type ('a,'b) bsobj =
  {
  verbose : bool,
  temp_flag : bool,
  player : ('a,'b) player,
  game : ('a,'b) game,
  mctsparam : mctsparam
  }

fun debug_board b game board =
  if b then 
  (
  print_endline "\nBoard";
  print_endline ((#string_of_board game) board)
  ) 
  else ()

(* rootl and rlex are reversed *)
fun loop_bigsteps cstatus bsobj mctsobj (rlex,rootl) tree =
  let
    val {mctsparam,game,player} = mctsobj
    val board = #board (dfind [] tree)
    val status = #status_of game board
    val _ = debug_board (#verbose bsobj) game board
  in
    if status <> Undecided
    then (status = Win, cstatus = Win, rlex, rootl) 
      else
    let
      val endtree = mcts mctsobj tree
      val root = dfind [] endtree
      val newcstatus = if cstatus = Win then Win else #status root
      val cid = select_bigstep bsobj mctsobj endtree
      val newtree = cut_tree cid endtree
      val newrlex = add_rootex game endtree rlex
      val newrootl = root :: rootl
    in
      loop_bigsteps newcstatus bsobj mctsobj (newrlex,newrootl) newtree
    end
  end

fun run_bigsteps bsobj target =
  let
    val mctsobj =
      {
      mctsparam = #mctsparam bsobj,
      game = #game bsobj,
      player = #player bsobj
      }
    val tree = starttree_of mctsobj target
  in
    loop_bigsteps Undecided bsobj mctsobj ([],[]) tree
  end

(* -------------------------------------------------------------------------
   Toy example (same as in psMCTS)
   ------------------------------------------------------------------------- *)

(*
load "aiLib"; open aiLib;
load "psMCTS"; open psMCTS;
load "psBigSteps"; open psBigSteps;

val mctsparam =
  {
  nsim = 1600,
  stopatwin_flag = false,
  decay = 1.0,
  explo_coeff = 2.0,
  noise_all = true, noise_root = false,
  noise_coeff = 0.25, noise_gen = gamma_noise_gen 0.2
  };

val bsobj : (toy_board,toy_move) bsobj =
  {
  verbose = true,
  temp_flag = false,
  player = uniform_player toy_game,
  game = toy_game,
  mctsparam = mctsparam
  };

val target = (0,10,100);
val (_,t) = add_time (run_bigsteps bsobj) target;
val (winb1,winb2,rlex,rootl) = run_bigsteps bsobj target;
*)

end (* struct *)
