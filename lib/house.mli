(** Moving through the house: where the player stands, which rooms they can
    reach from there, the hidden passage, and the haunted events.

    A value of type {!t} is the player's position and the history that
    matters for exploration. It is immutable: every operation that changes it
    returns a new value, and a refused move returns the old value unchanged,
    so a caller can never lose progress by trying something impossible.

    Every operation takes the {!Case.t} it should follow and the clues the
    player currently holds, rather than reading {!Case.data} or tracking clues
    itself. Clues belong to the whole investigation (rooms and interviews both
    grant them), so the caller owns them; passing the case in lets tests use a
    small hand-written house. *)

type t
(** The player's place in the house. *)

type route = {
  room : string;
  passage : Case.passage option;
}
(** One move the player can make: the room it leads to, and the passage it
    goes through, or [None] if it is an ordinary walk along a hallway. *)

type move_result =
  | Moved of {
      passage : Case.passage option;
      first_time_through : bool;
      events : Case.event list;
    }
      (** The player is now in the requested room. [passage] is the passage
          they came through, if any, and [first_time_through] is whether this
          was their first time through it. [events] are the haunted events that
          happened on arrival, in the order the case lists them. *)
  | Already_here  (** The player is already in that room. *)
  | Not_connected
      (** No hallway or passage joins the two rooms, so the player must go
          through another room first. *)
  | Passage_locked of Case.passage
      (** The only way there is a passage the player cannot open yet. *)
  | Unknown_room  (** The case has no room with that identifier. *)

val start : Case.t -> t
(** [start case] is a player standing in the first room of [case], having
    visited only that room, with no events fired and no passage used.
    No events fire here; call {!haunt} for events in the starting room.
    @raise Invalid_argument if [case] has no rooms. *)

val location : t -> string
(** [location house] is the identifier of the room the player is in. *)

val visited : t -> string list
(** [visited house] is every room the player has stood in, each once, in the
    order they first entered it. It always includes {!location}. *)

val fired : t -> string list
(** [fired house] is the identifier of every haunted event that has happened,
    in the order they happened. *)

val passages_used : t -> string list
(** [passages_used house] is the identifier of every passage the player has
    walked through at least once, in the order first used. *)

val passage_open : clues:string list -> Case.passage -> bool
(** [passage_open ~clues passage] is whether a player holding [clues] can use
    [passage], that is, whether every clue it requires is in [clues]. *)

val routes : Case.t -> clues:string list -> string -> route list
(** [routes case ~clues room] is every move a player holding [clues] can make
    from [room]: each room sharing a hallway with it, then each room joined to
    it by an open passage, with no room listed twice and never [room] itself.
    A room reached both ways is listed as a hallway walk. Rooms appear in the
    order of [case.rooms]. An unknown [room] has no routes. *)

val move : Case.t -> clues:string list -> t -> string -> t * move_result
(** [move case ~clues house room] tries to walk the player to [room]. On
    success the player is in [room], [room] is added to {!visited} if new, any
    passage used is added to {!passages_used}, and the events of {!haunt} for
    the new room have fired. On any other result the returned house is
    [house] itself. *)

val haunt : Case.t -> clues:string list -> t -> t * Case.event list
(** [haunt case ~clues house] fires every event of [case] that is set in the
    player's current room, has not fired before, and requires only clues the
    player holds. It returns the house with those events recorded in {!fired},
    and the events themselves in the order [case] lists them.

    A clue granted by an event counts as held for the rest of the same call, so
    an event that requires another event's clue fires in the same call as that
    event, provided it is listed after it. Calling [haunt] again immediately
    fires nothing. Call it whenever the player gains a clue, because an event
    may be waiting in their room for exactly that clue. *)
