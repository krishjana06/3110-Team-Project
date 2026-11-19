type topic = {
  id : string;
  prompt : string;
  reply : string;
  clue : string option;
  requires : string list;
}

type suspect = { id : string; name : string; greeting : string; topics : topic list }
type session

type result =
  | Replied of { text : string; newly_found : string option }
  | Locked of string
  | Already_asked of string
  | Unknown_topic

val suspects : suspect list
val start : ?clues:string list -> suspect -> session
val available_topics : session -> topic list
val ask : session -> string -> session * result
val clues : session -> string list
val add_clues : session -> string list -> session
