Require Import String List.
Import ListNotations.
Open Scope string.

From MetaCoq.Template Require Import All.
Import MonadNotation.
From ASUB Require Import Monad Language AssocList Utils TemplateMonadUtils Quotes.

Record State := { st_names : list string; st_implicits : SFMap.t nat }.

Definition empty_state := {| st_names := []; st_implicits := SFMap.empty _ |}.
Definition initial_state (implicits: SFMap.t nat) := {| st_names := []; st_implicits := implicits |}.

Definition initial_env := SFMap.fromList [("nat", nat_q); ("option", option_q); ("S", S_q)].

Definition update_env (env env' : SFMap.t term) : SFMap.t term :=
  SFMap.union env env'.

Definition tm_update_env (names: list string) (env: SFMap.t term) : TemplateMonad (SFMap.t term) :=
  env_list' <- tm_mapM locate_name names;;
  let env' := SFMap.fromList env_list' in
  tmReturn (update_env env' env). 


Inductive scope_type := Unscoped | Wellscoped.
Definition is_wellscoped (s: scope_type) :=
  match s with
  | Wellscoped => true
  | Unscoped => false
  end.

Record Flags := { fl_scope_type : scope_type }.
Definition default_flags := {| fl_scope_type := Unscoped |}.

Record R' := { R_flags : Flags; R_sig: Signature; R_env : SFMap.t term }.

(* The RWSE monad that we use to generate the lemmas *)
Module GenMArgs.
  (* module parameters cannot be records yet. So define outside and put definition here *)
  Definition R := R'.
  Definition W := string.
  Definition S := State.
  Definition E := string.

  Definition append := String.append.
  Definition empty := ""%string.
End GenMArgs.

Module GenM.
  Module GenM := RWSE GenMArgs.
  Include GenM.

  Import Notations.

  Definition register_name (name: string) : t unit :=
    state <- get;;
    put {| st_names := name :: state.(st_names); st_implicits := state.(st_implicits) |}.

  Definition register_names (names': list string) : t unit :=
    state <- get;;
    put {| st_names := app names' state.(st_names); st_implicits := state.(st_implicits) |}.

  Definition register_implicits (name: string) (implicit_num: nat) : t unit :=
    state <- get;;
    put {| st_names := state.(st_names); st_implicits := SFMap.add name implicit_num state.(st_implicits) |}.

  Definition get_implicits (name: string) : t nat :=
    state <- get;;
    match SFMap.find name state.(st_implicits) with
    | None => pure 0
    | Some n => pure n
    end.
  
  (* Definition env_get (s: string) : t term := *)
  (*   env <- gets st_env;; *)
  (*   match SFMap.find env s with *)
  (*   | None => error (String.append "Not found: " s) *)
  (*   | Some t => pure t *)
  (*   end. *)

  Definition testrun {A} (mv: t A) :=
    run mv {| R_flags := {| fl_scope_type := Unscoped |};
              R_sig := Hsig_example.mySig;
              R_env := initial_env |} empty_state.

  (** * Additional functions used during code generation *)

  (** get the constructors of a sort *)
  Definition constructors (sort: tId) : t (list Constructor) :=
    spec <- asks (fun x => sigSpec x.(R_sig));;
    match SFMap.find spec sort with
    | Some cs => pure cs
    | None => error ("constructors called with unknown sort")
    end.

  (** get the arguments of a sort *)
  Definition getArguments (sort: tId) : t (list tId) :=
    args <- asks (fun x => sigArguments x.(R_sig));;
    match SFMap.find args sort with
    | Some sorts => pure sorts
    | None => error ("getArguments called with unknown sort")
    end.

  (** check if a sort has renamings *)
  Definition hasRenaming (sort: tId) : t bool :=
    rens <- asks (fun x => sigRenamings x.(R_sig));;
    pure (SSet.mem rens sort).

  (** return the substitution vector for a sort *)
  Definition substOf (sort: tId) : t (list tId) :=
    substs <- asks (fun x => sigSubstOf x.(R_sig));;
    match SFMap.find substs sort with
    | Some sorts => pure sorts
    | None => error ("substOf called with unknown sort")
    end.

  (** check if a sort is open (has a variable constructor) *)
  Definition isOpen (sort: tId) : t bool :=
    isOpen <- asks (fun x => sigIsOpen x.(R_sig));;
    pure (SSet.mem isOpen sort).

  (** A sort is definable if it has any constructor *)
  Definition isDefinable (sort: tId) : t bool :=
    b <- isOpen sort;;
    ctors <- constructors sort;;
    pure (orb b (negb (list_empty ctors))).

  (** Check if the arguments of the first sort of a component and the component itself overlaps
   ** We can only check the first element of the component because they all have the same
   ** substitution vector. *)
  Definition isRecursive (component: NEList.t tId) : t bool :=
    let '(sort, _) := component in
    args <- getArguments sort;;
    pure (negb (list_empty (list_intersection (NEList.to_list component) args))).

  Definition get_scope_type : t scope_type :=
    fl <- asks R_flags;;
    pure fl.(fl_scope_type).
End GenM.
