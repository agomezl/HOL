signature hhsExec =
sig

  include Abbrev
  
  val hhs_bool_glob    : bool ref
  val hhs_tacticl_glob : tactic list ref
  val hhs_string_glob  : string ref
  val hhs_goal_glob    : goal ref
  val hhs_hh_glob      : (int -> term -> unit) ref
   
  
  val exec_sml         : string -> string -> bool
  
  val is_thm           : string -> bool
  val is_tactic        : string -> bool
  val is_pointer_eq    : string -> string -> bool
  
  val hhs_invalid_flag : bool ref
  val tactic_of_sml    : string -> tactic
  val tacticl_of_sml   : string list -> tactic list
  val string_of_sml    : string -> string
  val goal_of_sml      : string -> goal
  val hh_of_sml        : unit -> (int -> term -> unit)
  
  val app_tac    : real -> tactic -> goal -> goal list option
  val rec_stac   : string -> goal -> goal list option
  val rec_sproof : string -> goal -> goal list option
  
  val type_of_sml      : string -> string option

end
