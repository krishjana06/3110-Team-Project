(** Questioning a suspect: which questions are open, what the answer is, and
    what the answer reveals.

    Interviewing is where evidence turns into testimony. A question may be
    gated behind clues the player has not yet found, so the questions a suspect
    will entertain grow as the investigation does. Asking an open question
    returns the suspect's reply and may add a clue of its own, which in turn
    can open questions for a different suspect.

    A {!session} is one player's standing with one suspect. Sessions are
    immutable: every operation that changes anything returns a new session, and
    the one passed in is left as it was. That makes a session safe to hold on
    to, and it means a refused question cannot quietly alter the player's
    progress. The caller decides which session to keep. *)

type topic = {
  id : string;
  prompt : string;
  reply : string;
  clue : string option;
  requires : string list;
}
(** One question that may be put to a suspect. [prompt] is the question as the
    player sees it and [reply] is the answer. [clue] is the clue asking it
    yields, or [None] for a question that reveals nothing new. [requires] lists
    the clues the player must already hold before the question is open at all,
    which is how a contradiction stays hidden until the evidence that exposes
    it has been found. *)

type suspect = {
  id : string;
  name : string;
  greeting : string;
  topics : topic list;
}
(** A person who can be questioned. [greeting] is what they say when the
    interview opens, before any question is asked. [topics] is every question
    they could ever answer, including those still gated. *)

type session
(** One player's interview with one suspect: which of that suspect's questions
    have already been asked, and which clues the player holds. The
    representation is hidden so that callers cannot mark a question as asked,
    or grant the player a clue, except through the operations below. *)

type result =
  | Replied of {
      text : string;
      newly_found : string option;
    }
      (** The suspect answered. [text] is the reply, and [newly_found] is the
          clue the answer revealed, or [None] if the player already held it or
          the question yields none. *)
  | Locked of string
      (** The question is gated and the player lacks at least one required
          clue. The argument is one such missing clue. *)
  | Already_asked of string
      (** This question has been put to this suspect before. The argument is a
          message for the player. *)
  | Unknown_topic
      (** No question with that identifier belongs to this suspect. *)
(** What came of asking a question. Only [Replied] changes the session. *)

val suspects : suspect list
(** [suspects] is every suspect of the running case, built from the ["suspects"]
    field of {!Case.data}. It is evaluated when the module is first used. *)

val start : ?clues:string list -> suspect -> session
(** [start ?clues suspect] is a fresh interview with [suspect] in which no
    question has yet been asked. [clues] is what the player already holds,
    which decides which questions are open from the outset; it defaults to the
    empty list, the standing of a player who has found nothing. *)

val available_topics : session -> topic list
(** [available_topics session] is the questions that may be asked right now:
    those not yet asked in [session] and whose required clues the player holds.
    They keep the order in which the case file lists them. The list shrinks as
    questions are asked and grows as clues are found, so it is exactly what an
    interface should offer the player. *)

val ask : session -> string -> session * result
(** [ask session topic_id] puts the question [topic_id] to the suspect, and is
    the resulting session together with what came of it.

    When the question is open, the result is [Replied], the question is
    recorded as asked, and any clue it yields is added. When the player lacks a
    required clue the result is [Locked]; when the question has already been
    asked it is [Already_asked]; when the suspect has no such question it is
    [Unknown_topic]. In all three of those cases the returned session is the
    one passed in, unchanged — a refused question costs the player nothing and
    reveals nothing. *)

val clues : session -> string list
(** [clues session] is the clues the player holds, in the order they were
    acquired, without duplicates. *)

val add_clues : session -> string list -> session
(** [add_clues session clues] is [session] with every clue of [clues] added to
    what the player holds. Clues already held are ignored rather than repeated,
    so the result never contains duplicates and applying the same list twice
    changes nothing the second time. This is how a discovery made elsewhere —
    inspecting an object, or questioning a different suspect — reaches this
    interview and opens the questions that depend on it. *)
