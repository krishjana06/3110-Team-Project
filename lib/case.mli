(** The case file: the house, its evidence, the suspects, and the solution.

    A case is read once from a JSON file so that the story can be rewritten
    without touching the program. Everything the rest of the game needs about
    the mystery comes from here: which rooms exist, what can be inspected in
    them, which clue each object yields, which clues must already be held
    before an object can be inspected, and which combination of suspect,
    weapon, and room solves the case.

    The parsing helpers that turn JSON into these records are deliberately not
    exposed. Callers receive fully built values and never have to know the
    shape of the underlying JSON. *)

type clue = {
  id : string;
  title : string;
  kind : string;
  source : string;
  description : string;
}
(** One piece of evidence. [id] is how every other part of the game refers to
    it; [kind] groups it for the notebook's filter, such as ["Physical"] or
    ["Testimony"]; [source] names where it came from; [description] is the text
    shown to the player. *)

type object_ = {
  id : string;
  name : string;
  description : string;
  clue : string;
  requires : string list;
}
(** Something in a room the player can inspect. Inspecting it yields the clue
    named by [clue]. [requires] lists the clues the player must already hold
    before it may be inspected at all, which is how a locked passage stays shut
    until the player has found the way in. An empty [requires] means the object
    can be inspected from the start. *)

type room = {
  id : string;
  name : string;
  description : string;
  row : int;
  col : int;
  objects : object_ list;
}
(** A room of the house. [row] and [col] place it on the floor plan the
    interface draws; they are display coordinates and carry no game rules. *)

type weapon = {
  id : string;
  name : string;
}
(** A weapon the player may name in an accusation. *)

type t = {
  title : string;
  intro : string;
  objective : string;
  rooms : room list;
  clues : clue list;
  weapons : weapon list;
  suspects : Yojson.Basic.t list;
  solution : Yojson.Basic.t;
}
(** A whole case. [suspects] and [solution] are left as JSON because
    {!Dialogue} owns the suspect representation and reads them itself; keeping
    them unparsed here avoids two modules defining the same types. Use
    {!string} to read a field of [solution], whose keys are ["suspect"],
    ["weapon"], ["room"], and ["explanation"]. *)

val string : string -> Yojson.Basic.t -> string
(** [string key json] is the string stored at [key] in [json].
    @raise Yojson.Basic.Util.Type_error
      if [key] is absent or does not hold a string. *)

val strings : string -> Yojson.Basic.t -> string list
(** [strings key json] is the list of strings stored at [key] in [json].
    @raise Yojson.Basic.Util.Type_error
      if [key] is absent or does not hold a list of strings. *)

val validate : t -> unit
(** [validate case] checks that [case] is internally consistent, and does
    nothing if it is. It is called by {!load}, so a case obtained from [load]
    has already passed; it is exposed so that tests can check a case built by
    hand.

    It establishes that clue, room, weapon, suspect, and topic identifiers are
    unique, that object identifiers are unique within their room, that every
    clue identifier mentioned by an object or a dialogue topic — whether as the
    clue it yields or as one it requires — names a clue that exists, and that
    the solution names a suspect, a weapon, and a room that exist.

    @raise Failure
      with a message naming the offending identifier, such as
      ["Duplicate clue ID: cufflink"], ["Unknown clue ID: missing_clue"], or
      ["Unknown solution weapon"]. The check stops at the first problem it
      finds, so one call reports one problem. *)

val load : string -> t
(** [load path] is the case stored in the JSON file at [path], validated.
    @raise Sys_error if [path] cannot be opened.
    @raise Yojson.Json_error if the file is not well-formed JSON.
    @raise Yojson.Basic.Util.Type_error if a field is missing or has the wrong type.
    @raise Failure if the case is not internally consistent; see {!validate}. *)

val data : t
(** [data] is the case the running game uses, read from [data/case.json]. The
    file is located by searching the working directory and then its ancestors,
    so the game may be started from anywhere inside the project.

    This is evaluated when the module is first used, which means a missing or
    invalid case file reports its problem at startup rather than at the first
    call. Tests that need a different case should use {!load} instead of
    reaching for this value. *)

val find_clue : string -> clue option
(** [find_clue id] is the clue of [data] with identifier [id], or [None] if
    [data] has no such clue. *)

val find_room : string -> room option
(** [find_room id] is the room of [data] with identifier [id], or [None] if
    [data] has no such room. *)

val find_object : room -> string -> object_ option
(** [find_object room id] is the object of [room] with identifier [id], or
    [None] if that room holds no such object. *)

val unlocked : string list -> object_ -> bool
(** [unlocked clues object_] is whether a player holding [clues] may inspect
    [object_], that is, whether every clue in its [requires] is present in
    [clues]. An object that requires nothing is unlocked for any player,
    including one who holds no clues at all. Order and duplicates in [clues] do
    not matter. *)

val correct_accusation : suspect:string -> weapon:string -> room:string -> bool
(** [correct_accusation ~suspect ~weapon ~room] is whether those three
    identifiers together match the solution of {!data}. All three must be
    right; naming two correctly is not a partial success, and the caller is not
    told which part was wrong. *)
