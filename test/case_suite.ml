(** Automated validation for the case loader, clue gating, interviews, and the
    accusation rule.

    How these tests were designed. The expected answers come from the rules of
    the game and from case files written by hand for the purpose, never from
    running the program and recording what it printed. The files in
    [test/fixtures/] are small enough to reason about completely:
    [minimal.json] is a correct two-room case whose every clue and question can
    be worked out on paper, and each of the other fixtures is that same case
    with exactly one fault introduced, so a test that rejects it has rejected
    that one fault and nothing else.

    Checks over the shipped case in [data/case.json] are written as properties
    rather than as assertions about particular prose — that every clue a
    question demands can actually be found, for instance, rather than that
    Mustard says a particular sentence. Story text changes as the case is
    written; the properties should hold for any case the game ships.

    Every test builds whatever it needs inside its own function. Sessions and
    cases are immutable here, but OUnit may run tests in any order, and a test
    that depended on another having run first would be a trap for whoever
    changes this file next. *)

open OUnit2

(* ------------------------------------------------------------------ *)
(* Helpers                                                              *)
(* ------------------------------------------------------------------ *)

(** [fixture name] is the path of a hand-written case file, relative to the
    directory dune runs the tests from. *)
let fixture name = Filename.concat "fixtures" name

(** [load_fixture name] is the case in fixture [name], loaded and validated. *)
let load_fixture name = Case.load (fixture name)

(** [assert_rejected name message] checks that loading fixture [name] fails
    validation with exactly [message]. Comparing the whole message, rather than
    merely checking that something was raised, is what establishes that the
    loader found the fault we planted and not some other one. *)
let assert_rejected name message _ =
  match Case.load (fixture name) with
  | exception Failure actual ->
      assert_equal ~msg:("rejecting " ^ name) ~printer:(fun s -> s) message
        actual
  | _ -> assert_failure (name ^ " should have been rejected by validation")

let string_list_printer items = "[" ^ String.concat "; " items ^ "]"

(** [suspect_named id] is the suspect of the shipped case with that id. *)
let suspect_named id =
  List.find (fun (s : Dialogue.suspect) -> s.id = id) Dialogue.suspects

(** [topic_is_open id session] is whether question [id] may be asked now. *)
let topic_is_open id session =
  List.exists
    (fun (t : Dialogue.topic) -> t.id = id)
    (Dialogue.available_topics session)

(** [every_topic ()] is every question of every suspect in the shipped case,
    paired with the suspect it belongs to. *)
let every_topic () =
  List.concat_map
    (fun (s : Dialogue.suspect) ->
      List.map (fun (t : Dialogue.topic) -> (s, t)) s.topics)
    Dialogue.suspects

(** [every_object ()] is every inspectable object of the shipped case, paired
    with the room it stands in. *)
let every_object () =
  List.concat_map
    (fun (r : Case.room) ->
      List.map (fun (o : Case.object_) -> (r, o)) r.objects)
    Case.data.rooms

(* ------------------------------------------------------------------ *)
(* Loading and validating a case file                                   *)
(* ------------------------------------------------------------------ *)

(* A correct case must survive the loader intact. If this fails, every
   rejection test below is meaningless, because they would be rejecting a file
   that was already broken for some other reason. *)
let test_minimal_case_loads _ =
  let case = load_fixture "minimal.json" in
  assert_equal ~msg:"title" ~printer:(fun s -> s) "A Small Case" case.title;
  assert_equal ~msg:"rooms" ~printer:string_of_int 2 (List.length case.rooms);
  assert_equal ~msg:"clues" ~printer:string_of_int 4 (List.length case.clues);
  assert_equal ~msg:"weapons" ~printer:string_of_int 2
    (List.length case.weapons);
  assert_equal ~msg:"suspects" ~printer:string_of_int 1
    (List.length case.suspects)

let test_rooms_keep_file_order _ =
  let case = load_fixture "minimal.json" in
  assert_equal ~msg:"rooms are presented in the order the file lists them"
    ~printer:string_list_printer [ "study"; "hall" ]
    (List.map (fun (r : Case.room) -> r.id) case.rooms)

(* Each of these fixtures is minimal.json with one deliberate fault. The
   message is checked in full so that a test cannot pass because validation
   happened to object to something else. *)
let rejection_tests =
  [
    ("a repeated clue id", "duplicate_clue.json", "Duplicate clue ID: letter");
    ("a repeated room id", "duplicate_room.json", "Duplicate room ID: study");
    ( "a repeated object id within a room",
      "duplicate_object.json",
      "Duplicate study object ID: desk" );
    ( "an object yielding a clue that does not exist",
      "unknown_object_clue.json",
      "Unknown clue ID: phantom" );
    ( "an object requiring a clue that does not exist",
      "unknown_object_requires.json",
      "Unknown clue ID: phantom" );
    ( "a question yielding a clue that does not exist",
      "unknown_topic_clue.json",
      "Unknown clue ID: phantom" );
    ( "a question requiring a clue that does not exist",
      "unknown_topic_requires.json",
      "Unknown clue ID: phantom" );
    ( "a solution naming an absent suspect",
      "unknown_solution_suspect.json",
      "Unknown solution suspect" );
    ( "a solution naming an absent weapon",
      "unknown_solution_weapon.json",
      "Unknown solution weapon" );
    ( "a solution naming an absent room",
      "unknown_solution_room.json",
      "Unknown solution room" );
  ]

(* A file that is not JSON at all, and a file missing a whole field, fail
   before validation ever runs. They must still fail rather than load
   something half-built. *)
let test_malformed_json_is_refused _ =
  (* The exact wording belongs to Yojson and may change between versions, so
     this checks that the file is refused rather than pinning the message. *)
  match load_fixture "malformed.json" with
  | exception Yojson.Json_error _ -> ()
  | exception Yojson.Basic.Util.Type_error _ -> ()
  | _ -> assert_failure "a truncated file should not load as a case"

let test_missing_field_is_refused _ =
  match load_fixture "missing_field.json" with
  | exception Yojson.Basic.Util.Type_error _ -> ()
  | exception Failure _ -> ()
  | _ -> assert_failure "a case with no weapons list should not load"

let test_absent_file_is_refused _ =
  match Case.load (fixture "no_such_case.json") with
  | exception Sys_error _ -> ()
  | _ -> assert_failure "loading a file that does not exist should fail"

(* ------------------------------------------------------------------ *)
(* Clue gating on objects                                               *)
(* ------------------------------------------------------------------ *)

let test_object_with_no_requirement_is_always_open _ =
  let case = load_fixture "minimal.json" in
  let study = List.hd case.rooms in
  let desk = Option.get (Case.find_object study "desk") in
  assert_bool "a desk requiring nothing is open to a player with no clues"
    (Case.unlocked [] desk);
  assert_bool "and remains open to a player who holds unrelated clues"
    (Case.unlocked [ "fiber" ] desk)

let test_object_stays_locked_until_every_requirement_is_held _ =
  let case = load_fixture "minimal.json" in
  let study = List.hd case.rooms in
  let safe = Option.get (Case.find_object study "safe") in
  assert_bool "the safe is shut to a player with nothing"
    (not (Case.unlocked [] safe));
  assert_bool "and to a player holding only an unrelated clue"
    (not (Case.unlocked [ "fiber" ] safe));
  assert_bool "the letter opens it" (Case.unlocked [ "letter" ] safe);
  assert_bool "extra clues do not close it again"
    (Case.unlocked [ "fiber"; "letter"; "ledger" ] safe)

let test_unlocking_ignores_order_and_repetition _ =
  let case = load_fixture "minimal.json" in
  let study = List.hd case.rooms in
  let safe = Option.get (Case.find_object study "safe") in
  assert_bool "duplicates in the player's clues change nothing"
    (Case.unlocked [ "letter"; "letter" ] safe);
  assert_bool "neither does the order they were found in"
    (Case.unlocked [ "ledger"; "letter" ] safe)

let test_lookups_reject_unknown_identifiers _ =
  let study = Option.get (Case.find_room "study") in
  assert_bool "an absent room is reported, not invented"
    (Case.find_room "cellar" = None);
  assert_bool "an absent object is reported, not invented"
    (Case.find_object study "chandelier" = None);
  assert_bool "an absent clue is reported, not invented"
    (Case.find_clue "phantom" = None);
  assert_bool "a real room is still found"
    (Option.is_some (Case.find_room "study"))

(* ------------------------------------------------------------------ *)
(* Interviews                                                           *)
(* ------------------------------------------------------------------ *)

(* These use the shipped case, because {!Dialogue.suspects} is built from
   {!Case.data} when the module loads and cannot be pointed at a fixture. The
   expectations below were read off the case file by hand and reasoned about on
   paper, not taken from the program's output.

   Confronting Mustard about the passage is the deepest chain in the case. The
   question requires three clues, which come from three different kinds of
   source:

     passage_tracks  <- inspecting study/panel, itself gated behind
                        passage_latch, from inspecting hall/portrait
     boots           <- inspecting conservatory/boots, gated behind nothing
     mustard_account <- asking Mustard where he was, gated behind nothing

   So no amount of searching alone opens it: the player must also have
   interviewed Mustard once already. That is the property this test pins. *)
let test_question_opens_only_when_its_clues_are_held _ =
  let mustard = suspect_named "mustard" in
  let session = Dialogue.start mustard in
  assert_bool "his opening question needs nothing"
    (topic_is_open "whereabouts" session);
  assert_bool "the cufflink confrontation is shut at the start"
    (not (topic_is_open "cufflink" session));
  assert_bool "and so is the passage confrontation"
    (not (topic_is_open "passage" session));
  let session = Dialogue.add_clues session [ "cufflink" ] in
  assert_bool "finding the cufflink opens that one question"
    (topic_is_open "cufflink" session);
  assert_bool "but it does nothing for the passage"
    (not (topic_is_open "passage" session));
  let session = Dialogue.add_clues session [ "passage_tracks"; "boots" ] in
  assert_bool "physical evidence alone still is not enough for the passage"
    (not (topic_is_open "passage" session));
  let session, _ = Dialogue.ask session "whereabouts" in
  assert_bool "his own account is what completes it"
    (topic_is_open "passage" session)

let test_a_refused_question_changes_nothing _ =
  let mustard = suspect_named "mustard" in
  let session = Dialogue.start mustard in
  let after, result = Dialogue.ask session "cufflink" in
  (match result with
  | Dialogue.Locked clue ->
      assert_equal ~msg:"the player is told which clue is missing"
        ~printer:(fun s -> s) "cufflink" clue
  | _ -> assert_failure "a gated question should be reported as locked");
  assert_equal ~msg:"a locked question grants no clue"
    ~printer:string_list_printer [] (Dialogue.clues after);
  assert_bool "and does not count as having been asked"
    (not (topic_is_open "cufflink" after));
  let after, result = Dialogue.ask session "no_such_question" in
  assert_equal ~msg:"an unknown question is reported as such"
    Dialogue.Unknown_topic result;
  assert_equal ~msg:"and changes nothing" ~printer:string_list_printer []
    (Dialogue.clues after)

let test_answering_records_the_question_and_its_clue _ =
  let mustard = suspect_named "mustard" in
  let session = Dialogue.add_clues (Dialogue.start mustard) [ "cufflink" ] in
  let after, result = Dialogue.ask session "cufflink" in
  (match result with
  | Dialogue.Replied { text; newly_found } ->
      assert_bool "the suspect actually says something"
        (String.length text > 0);
      assert_equal ~msg:"and his answer is itself recorded as testimony"
        ~printer:(function None -> "none" | Some c -> c)
        (Some "cufflink_response") newly_found
  | _ -> assert_failure "an open question should be answered");
  assert_bool "the question is now spent"
    (not (topic_is_open "cufflink" after));
  assert_bool "and his answer is in the notebook"
    (List.mem "cufflink_response" (Dialogue.clues after))

let test_the_same_question_is_not_answered_twice _ =
  let mustard = suspect_named "mustard" in
  let session = Dialogue.add_clues (Dialogue.start mustard) [ "cufflink" ] in
  let once, _ = Dialogue.ask session "cufflink" in
  let twice, result = Dialogue.ask once "cufflink" in
  (match result with
  | Dialogue.Already_asked message ->
      assert_bool "the player is told why" (String.length message > 0)
  | _ -> assert_failure "a repeated question should be refused");
  assert_equal ~msg:"and gains nothing a second time"
    ~printer:string_list_printer (Dialogue.clues once) (Dialogue.clues twice)

let test_clues_are_recorded_once_each _ =
  let mustard = suspect_named "mustard" in
  let session = Dialogue.start mustard in
  let session =
    Dialogue.add_clues session [ "cufflink"; "cufflink"; "boots" ]
  in
  assert_equal ~msg:"a clue found twice is held once"
    ~printer:string_list_printer
    [ "cufflink"; "boots" ]
    (Dialogue.clues session);
  let session = Dialogue.add_clues session [ "boots"; "ledger" ] in
  assert_equal ~msg:"later discoveries append in the order they arrive"
    ~printer:string_list_printer
    [ "cufflink"; "boots"; "ledger" ]
    (Dialogue.clues session)

let test_a_session_is_not_altered_by_asking _ =
  let mustard = suspect_named "mustard" in
  let before = Dialogue.add_clues (Dialogue.start mustard) [ "cufflink" ] in
  let open_before = List.length (Dialogue.available_topics before) in
  let _ = Dialogue.ask before "cufflink" in
  assert_equal ~msg:"the session passed in is left as it was"
    ~printer:string_of_int open_before
    (List.length (Dialogue.available_topics before));
  assert_bool "including which questions it considers open"
    (topic_is_open "cufflink" before)

(* The only gated object in the shipped case. The hidden passage is the hinge
   of the mystery, so it is worth pinning that searching the study cannot
   stumble onto it. *)
let test_the_hidden_passage_stays_shut_until_the_portrait_is_examined _ =
  let study = Option.get (Case.find_room "study") in
  let panel = Option.get (Case.find_object study "panel") in
  assert_bool "the panel is shut to a player who has found nothing"
    (not (Case.unlocked [] panel));
  assert_bool "and to one carrying unrelated evidence"
    (not (Case.unlocked [ "cufflink"; "ledger"; "boots" ] panel));
  assert_bool "the latch behind the portrait opens it"
    (Case.unlocked [ "passage_latch" ] panel);
  assert_equal ~msg:"and inspecting it yields the tracks"
    ~printer:(fun s -> s) "passage_tracks" panel.clue

(* ------------------------------------------------------------------ *)
(* The accusation                                                       *)
(* ------------------------------------------------------------------ *)

(* Read from the solution of the shipped case rather than written in, so that
   rewriting the mystery does not make these tests wrong. *)
let solution_part key = Case.string key Case.data.solution

let test_the_intended_solution_is_accepted _ =
  assert_bool "the case's own answer solves it"
    (Case.correct_accusation ~suspect:(solution_part "suspect")
       ~weapon:(solution_part "weapon") ~room:(solution_part "room"))

let test_every_part_of_an_accusation_must_be_right _ =
  let suspect = solution_part "suspect"
  and weapon = solution_part "weapon"
  and room = solution_part "room" in
  let other_suspect =
    (List.find
       (fun (s : Dialogue.suspect) -> s.id <> suspect)
       Dialogue.suspects)
      .id
  in
  let other_weapon =
    (List.find (fun (w : Case.weapon) -> w.id <> weapon) Case.data.weapons).id
  in
  let other_room =
    (List.find (fun (r : Case.room) -> r.id <> room) Case.data.rooms).id
  in
  assert_bool "naming the wrong person fails"
    (not
       (Case.correct_accusation ~suspect:other_suspect ~weapon ~room));
  assert_bool "naming the wrong weapon fails"
    (not (Case.correct_accusation ~suspect ~weapon:other_weapon ~room));
  assert_bool "naming the wrong room fails"
    (not (Case.correct_accusation ~suspect ~weapon ~room:other_room));
  assert_bool "an identifier that names nothing fails"
    (not (Case.correct_accusation ~suspect:"nobody" ~weapon ~room))

(* ------------------------------------------------------------------ *)
(* Properties the shipped case must satisfy                             *)
(* ------------------------------------------------------------------ *)

(** [grants ()] is every way the player can obtain a clue in the shipped case,
    as a triple of the clues required first, the clue obtained, and a
    description of where it comes from, for use in failure messages. *)
let grants () =
  List.map
    (fun ((r : Case.room), (o : Case.object_)) ->
      (o.requires, o.clue, Printf.sprintf "object %s/%s" r.id o.id))
    (every_object ())
  @ List.filter_map
      (fun ((s : Dialogue.suspect), (t : Dialogue.topic)) ->
        Option.map
          (fun clue ->
            (t.requires, clue, Printf.sprintf "question %s/%s" s.id t.id))
          t.clue)
      (every_topic ())
  @ List.filter_map
      (fun (e : Case.event) ->
        Option.map
          (fun clue -> (e.requires, clue, Printf.sprintf "event %s" e.id))
          e.clue)
      Case.data.events

(* A clue nobody can find is a dead end in the story: some question or object
   demands it, and the player has no way to satisfy that demand. The loader's
   validation only checks that referenced clues exist, not that they can be
   reached, so this is a genuinely separate check. *)
let test_every_clue_in_the_case_can_be_found _ =
  let obtainable = List.map (fun (_, clue, _) -> clue) (grants ()) in
  let orphans =
    List.filter
      (fun (c : Case.clue) -> not (List.mem c.id obtainable))
      Case.data.clues
  in
  assert_equal
    ~msg:"every catalogued clue is yielded by some object, question, or event"
    ~printer:string_list_printer []
    (List.map (fun (c : Case.clue) -> c.id) orphans)

(* The stronger version of the same worry: a clue might be yielded only by
   something that itself requires that clue, directly or in a cycle, so that
   nobody starting from nothing could ever reach it. This walks the
   dependencies forward from an empty notebook until nothing more opens. *)
let test_the_case_can_be_solved_starting_from_nothing _ =
  let all = grants () in
  let rec settle held =
    let next =
      List.fold_left
        (fun held (requires, clue, _) ->
          if (not (List.mem clue held))
             && List.for_all (fun r -> List.mem r held) requires
          then clue :: held
          else held)
        held all
    in
    if List.length next = List.length held then held else settle next
  in
  let reachable = settle [] in
  let stuck =
    List.filter
      (fun (c : Case.clue) -> not (List.mem c.id reachable))
      Case.data.clues
  in
  assert_equal
    ~msg:"a player who starts with nothing can reach every clue in some order"
    ~printer:string_list_printer []
    (List.map (fun (c : Case.clue) -> c.id) stuck)

(* Validation already rejects a requirement naming a clue that does not exist.
   This checks the weaker-looking but distinct property that the requirement
   can actually be met. *)
let test_every_requirement_can_be_satisfied _ =
  let obtainable = List.map (fun (_, clue, _) -> clue) (grants ()) in
  let demanded =
    List.concat_map (fun ((_ : Case.room), (o : Case.object_)) -> o.requires)
      (every_object ())
    @ List.concat_map
        (fun ((_ : Dialogue.suspect), (t : Dialogue.topic)) -> t.requires)
        (every_topic ())
    @ List.concat_map (fun (e : Case.event) -> e.requires) Case.data.events
    @ List.concat_map (fun (p : Case.passage) -> p.requires) Case.data.passages
  in
  let impossible =
    List.filter (fun id -> not (List.mem id obtainable)) demanded
  in
  assert_equal ~msg:"nothing is gated behind a clue that cannot be found"
    ~printer:string_list_printer [] (List.sort_uniq compare impossible)

let test_the_shipped_case_passes_its_own_validation _ =
  match Case.validate Case.data with
  | () -> ()
  | exception Failure message ->
      assert_failure ("the shipped case is inconsistent: " ^ message)

let test_every_suspect_can_be_asked_something_immediately _ =
  List.iter
    (fun (s : Dialogue.suspect) ->
      let session = Dialogue.start s in
      assert_bool
        (s.id ^ " has at least one question open to a player with no clues")
        (Dialogue.available_topics session <> []))
    Dialogue.suspects

(* ------------------------------------------------------------------ *)

(** One test per planted fault, built from [rejection_tests] so that adding a
    fixture is a one-line change. *)
let rejection_suite =
  List.map
    (fun (description, file, message) ->
      "validation rejects " ^ description >:: assert_rejected file message)
    rejection_tests

let suite =
  "mischievous murder mystery"
  >::: [
         (* Loading and validating a case file *)
         "a correct case file loads" >:: test_minimal_case_loads;
         "rooms keep the order of the file" >:: test_rooms_keep_file_order;
         "malformed json is refused" >:: test_malformed_json_is_refused;
         "a missing field is refused" >:: test_missing_field_is_refused;
         "an absent file is refused" >:: test_absent_file_is_refused;
       ]
       @ rejection_suite
       @ [
           (* Clue gating on objects *)
           "an object requiring nothing is always open"
           >:: test_object_with_no_requirement_is_always_open;
           "an object stays locked until every requirement is held"
           >:: test_object_stays_locked_until_every_requirement_is_held;
           "unlocking ignores order and repetition"
           >:: test_unlocking_ignores_order_and_repetition;
           "lookups reject unknown identifiers"
           >:: test_lookups_reject_unknown_identifiers;
           (* Interviews *)
           "a question opens only when its clues are held"
           >:: test_question_opens_only_when_its_clues_are_held;
           "a refused question changes nothing"
           >:: test_a_refused_question_changes_nothing;
           "answering records the question and its clue"
           >:: test_answering_records_the_question_and_its_clue;
           "the same question is not answered twice"
           >:: test_the_same_question_is_not_answered_twice;
           "clues are recorded once each" >:: test_clues_are_recorded_once_each;
           "a session is not altered by asking"
           >:: test_a_session_is_not_altered_by_asking;
           "the hidden passage stays shut until the portrait is examined"
           >:: test_the_hidden_passage_stays_shut_until_the_portrait_is_examined;
           (* The accusation *)
           "the intended solution is accepted"
           >:: test_the_intended_solution_is_accepted;
           "every part of an accusation must be right"
           >:: test_every_part_of_an_accusation_must_be_right;
           (* Properties of the shipped case *)
           "the shipped case passes its own validation"
           >:: test_the_shipped_case_passes_its_own_validation;
           "every clue in the case can be found"
           >:: test_every_clue_in_the_case_can_be_found;
           "the case can be solved starting from nothing"
           >:: test_the_case_can_be_solved_starting_from_nothing;
           "every requirement can be satisfied"
           >:: test_every_requirement_can_be_satisfied;
           "every suspect can be asked something immediately"
           >:: test_every_suspect_can_be_asked_something_immediately;
         ]

let () = run_test_tt_main suite
