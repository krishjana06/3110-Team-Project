(** Automated checks for exploring the house: hallways, the hidden passage,
    haunted events, and the validation of all three in a case file.

    How these tests were designed. As in [case_suite.ml], expected answers come
    from hand-written case files and the rules, never from recording program
    output. [fixtures/house.json] is a correct four-room case drawn so that
    each rule has exactly one place it shows up:

    - The foyer and parlour share the main hall; the parlour and cellar share
      the back stairs. So the foyer reaches the parlour, the parlour reaches
      both, and the cellar reaches only the parlour by hallway.
    - The attic is on no hallway. The only way in is the ladder from the foyer,
      which needs the [key] from the foyer mirror.
    - The dumbwaiter joins the cellar and foyer and also needs the [key], so
      with it the cellar and foyer are one move apart.
    - The service door joins the foyer and parlour, which the main hall already
      joins, so it should never be reported as the route between them.
    - Events: [creak] in the foyer needs nothing; [whisper] in the parlour
      needs nothing and yields [chill]; [slam] in the parlour needs [chill],
      so it fires right after [whisper]; [groan] in the cellar needs [key].

    The [*_hallway], [*_passage], and [*_event] fixtures are [house.json] with
    exactly one fault planted, in the same style as the fixtures derived from
    [minimal.json]. *)

open OUnit2

let fixture name = Filename.concat "fixtures" name
let house_case () = Case.load (fixture "house.json")
let strings items = "[" ^ String.concat "; " items ^ "]"
let event_ids events = List.map (fun (e : Case.event) -> e.id) events

(** [describe route] is a route written as ["room"] for a hallway walk or
    ["room via passage"] for a passage, so that a failure prints readably. *)
let describe (r : House.route) =
  match r.passage with
  | None -> r.room
  | Some p -> r.room ^ " via " ^ p.id

let assert_routes ~msg expected case clues room =
  assert_equal ~msg ~printer:strings expected
    (List.map describe (House.routes case ~clues room))

(** [walk case clues house room] moves to [room], failing the test if the move
    is refused, and returns the new house and the events that fired. *)
let walk case clues house room =
  match House.move case ~clues house room with
  | house, House.Moved { events; _ } -> (house, events)
  | _ -> assert_failure ("expected to be able to walk to " ^ room)

(* ------------------------------------------------------------------ *)
(* Starting out                                                         *)
(* ------------------------------------------------------------------ *)

let test_start_in_the_first_room _ =
  let house = House.start (house_case ()) in
  assert_equal ~printer:Fun.id "foyer" (House.location house);
  assert_equal ~printer:strings [ "foyer" ] (House.visited house);
  assert_equal ~printer:strings [] (House.fired house);
  assert_equal ~printer:strings [] (House.passages_used house)

let test_starting_room_events_wait_for_haunt _ =
  let case = house_case () in
  let house = House.start case in
  assert_equal ~msg:"start fires nothing by itself" ~printer:strings []
    (House.fired house);
  let house, events = House.haunt case ~clues:[] house in
  assert_equal ~msg:"haunting the foyer fires the creak" ~printer:strings
    [ "creak" ] (event_ids events);
  let _, events = House.haunt case ~clues:[] house in
  assert_equal ~msg:"and a second haunt fires nothing" ~printer:strings []
    (event_ids events)

(* ------------------------------------------------------------------ *)
(* Hallways and passages                                                *)
(* ------------------------------------------------------------------ *)

let test_hallways_join_their_rooms _ =
  let case = house_case () in
  assert_routes ~msg:"the foyer opens only onto the main hall" [ "parlour" ]
    case [] "foyer";
  assert_routes ~msg:"the parlour is on both hallways"
    [ "foyer"; "cellar" ] case [] "parlour";
  assert_routes ~msg:"the cellar is only on the back stairs" [ "parlour" ]
    case [] "cellar";
  assert_routes ~msg:"the attic is on no hallway" [] case [] "attic"

let test_passages_open_with_their_clue _ =
  let case = house_case () in
  assert_routes ~msg:"with the key, the foyer reaches the attic and cellar"
    [ "parlour"; "cellar via dumbwaiter"; "attic via ladder" ]
    case [ "key" ] "foyer";
  assert_routes ~msg:"passages work in both directions"
    [ "foyer via dumbwaiter"; "parlour" ] case [ "key" ] "cellar";
  assert_routes ~msg:"and the attic is no longer a dead end"
    [ "foyer via ladder" ] case [ "key" ] "attic"

let test_a_hallway_is_preferred_to_a_passage _ =
  (* The service door needs nothing, so it is open, but the main hall already
     joins those rooms. Reporting it would tell the player they used a secret
     door to walk down an ordinary hall. *)
  let case = house_case () in
  assert_routes ~msg:"the service door is never the route" [ "parlour" ] case
    [] "foyer";
  let _, result = House.move case ~clues:[] (House.start case) "parlour" in
  match result with
  | House.Moved { passage = None; first_time_through = false; _ } -> ()
  | _ -> assert_failure "walking to the parlour should use the hallway"

let test_unknown_rooms_have_no_routes _ =
  assert_routes ~msg:"a room that does not exist leads nowhere" []
    (house_case ()) [ "key" ] "belfry"

(* ------------------------------------------------------------------ *)
(* Moving                                                               *)
(* ------------------------------------------------------------------ *)

let test_walking_changes_room_and_records_the_visit _ =
  let case = house_case () in
  let house, _ = walk case [] (House.start case) "parlour" in
  let house, _ = walk case [] house "cellar" in
  let house, _ = walk case [] house "parlour" in
  assert_equal ~printer:Fun.id "parlour" (House.location house);
  assert_equal ~msg:"each room is recorded once, in order of first visit"
    ~printer:strings
    [ "foyer"; "parlour"; "cellar" ]
    (House.visited house)

let test_refused_moves_change_nothing _ =
  let case = house_case () in
  let start = House.start case in
  let check room expected_label matches =
    let after, result = House.move case ~clues:[] start room in
    assert_bool ("moving to " ^ room ^ " should be " ^ expected_label)
      (matches result);
    assert_bool ("a refused move to " ^ room ^ " returns the same house")
      (after == start)
  in
  check "foyer" "already here" (( = ) House.Already_here);
  check "belfry" "an unknown room" (( = ) House.Unknown_room);
  check "attic" "blocked by the ladder" (function
    | House.Passage_locked p -> p.id = "ladder"
    | _ -> false);
  check "cellar" "blocked by the dumbwaiter" (function
    | House.Passage_locked p -> p.id = "dumbwaiter"
    | _ -> false);
  let parlour, _ = walk case [] start "parlour" in
  let after, result = House.move case ~clues:[ "key" ] parlour "attic" in
  assert_bool "the parlour has no route to the attic at all"
    (result = House.Not_connected);
  assert_bool "and the refusal leaves the player in the parlour"
    (after == parlour)

let test_a_passage_is_reported_new_only_once _ =
  let case = house_case () in
  let first_time house room =
    match House.move case ~clues:[ "key" ] house room with
    | house, House.Moved { passage = Some p; first_time_through; _ } ->
        assert_equal ~printer:Fun.id "ladder" p.id;
        (house, first_time_through)
    | _ -> assert_failure ("expected to climb the ladder to " ^ room)
  in
  let house, up = first_time (House.start case) "attic" in
  let house, down = first_time house "foyer" in
  assert_bool "the first climb is new" up;
  assert_bool "climbing back is not" (not down);
  assert_equal ~printer:strings [ "ladder" ] (House.passages_used house)

(* ------------------------------------------------------------------ *)
(* Haunted events                                                       *)
(* ------------------------------------------------------------------ *)

let test_arriving_fires_events_and_chains_their_clues _ =
  let case = house_case () in
  let house, events = walk case [] (House.start case) "parlour" in
  assert_equal
    ~msg:"the whisper grants chill, which lets the slam fire on the same visit"
    ~printer:strings [ "whisper"; "slam" ] (event_ids events);
  assert_equal ~printer:strings [ "whisper"; "slam" ] (House.fired house)

let test_an_event_fires_only_once _ =
  let case = house_case () in
  let house, _ = walk case [] (House.start case) "parlour" in
  let house, _ = walk case [] house "foyer" in
  let house, events = walk case [ "chill" ] house "parlour" in
  assert_equal ~msg:"returning to the parlour fires nothing new"
    ~printer:strings [] (event_ids events);
  assert_equal
    ~msg:"nothing is recorded twice (the creak fired on passing the foyer)"
    ~printer:strings
    [ "whisper"; "slam"; "creak" ]
    (House.fired house)

let test_an_event_waits_for_its_clue _ =
  let case = house_case () in
  let house, _ = walk case [] (House.start case) "parlour" in
  let house, events = walk case [] house "cellar" in
  assert_equal ~msg:"without the key, the cellar is quiet" ~printer:strings []
    (event_ids events);
  let house, events = House.haunt case ~clues:[ "key" ] house in
  assert_equal ~msg:"gaining the key while standing there fires the groan"
    ~printer:strings [ "groan" ] (event_ids events);
  let _, events = House.haunt case ~clues:[ "key" ] house in
  assert_equal ~msg:"once" ~printer:strings [] (event_ids events)

let test_events_stay_in_their_room _ =
  let case = house_case () in
  let _, events = House.haunt case ~clues:[ "key"; "chill" ] (House.start case) in
  assert_equal ~msg:"haunting the foyer never fires parlour or cellar events"
    ~printer:strings [ "creak" ] (event_ids events)

(* ------------------------------------------------------------------ *)
(* Validation of hallways, passages, and events                         *)
(* ------------------------------------------------------------------ *)

let assert_rejected (file, message) _ =
  match Case.load (fixture file) with
  | exception Failure actual ->
      assert_equal ~msg:("rejecting " ^ file) ~printer:Fun.id message actual
  | _ -> assert_failure (file ^ " should have been rejected")

let rejection_tests =
  [
    ("a repeated hallway id", "duplicate_hallway.json", "Duplicate hallway ID: main_hall");
    ("a hallway naming an absent room", "unknown_hallway_room.json", "Unknown hallway room: belfry");
    ("a repeated passage id", "duplicate_passage.json", "Duplicate passage ID: ladder");
    ("a passage to an absent room", "unknown_passage_room.json", "Unknown passage room: belfry");
    ("a passage requiring an unknown clue", "unknown_passage_requires.json", "Unknown clue ID: phantom");
    ( "a passage with three ends",
      "passage_three_ends.json",
      "Passage ladder must connect exactly two rooms" );
    ("a repeated event id", "duplicate_event.json", "Duplicate event ID: whisper");
    ("an event in an absent room", "unknown_event_room.json", "Unknown event room: belfry");
    ("an event yielding an unknown clue", "unknown_event_clue.json", "Unknown clue ID: phantom");
    ("an event requiring an unknown clue", "unknown_event_requires.json", "Unknown clue ID: phantom");
  ]

let test_a_case_without_exploration_data_still_loads _ =
  let case = Case.load (fixture "minimal.json") in
  assert_equal ~msg:"hallways, passages, and events default to none" (0, 0, 0)
    (List.length case.hallways, List.length case.passages, List.length case.events)

(* ------------------------------------------------------------------ *)
(* Properties of the shipped house                                      *)
(* ------------------------------------------------------------------ *)

(** [reachable case clues] is every room a player holding [clues] can walk to
    from the first room, found by following routes until nothing new opens. *)
let reachable (case : Case.t) clues =
  let rec spread seen = function
    | [] -> seen
    | room :: rest ->
        let next =
          House.routes case ~clues room
          |> List.map (fun (r : House.route) -> r.room)
          |> List.filter (fun id -> not (List.mem id seen))
        in
        spread (seen @ next) (rest @ next)
  in
  let first = House.location (House.start case) in
  spread [ first ] [ first ]

let test_every_room_can_be_reached_without_clues _ =
  (* The passage is a shortcut, not the only way in: a player who never finds
     the portrait must still be able to search the conservatory. *)
  let case = Case.data in
  let missing =
    List.filter
      (fun (r : Case.room) -> not (List.mem r.id (reachable case [])))
      case.rooms
  in
  assert_equal ~msg:"every room is reachable by hallways alone" ~printer:strings []
    (List.map (fun (r : Case.room) -> r.id) missing)

let test_the_ghost_walk_opens_with_the_portrait_latch _ =
  let case = Case.data in
  let via_passage clues =
    List.exists
      (fun (r : House.route) -> r.room = "conservatory" && r.passage <> None)
      (House.routes case ~clues "study")
  in
  assert_bool "the study cannot reach the conservatory directly at first"
    (not (via_passage []));
  assert_bool "the portrait latch opens the ghost walk" (via_passage [ "passage_latch" ])

let test_every_event_is_in_a_room_that_can_be_reached _ =
  let rooms = reachable Case.data [] in
  List.iter
    (fun (e : Case.event) ->
      assert_bool (e.id ^ " is in a reachable room") (List.mem e.room rooms))
    Case.data.events

let suite =
  "house exploration"
  >::: [
         "the player starts in the first room" >:: test_start_in_the_first_room;
         "starting-room events wait for haunt" >:: test_starting_room_events_wait_for_haunt;
         "hallways join their rooms" >:: test_hallways_join_their_rooms;
         "passages open with their clue" >:: test_passages_open_with_their_clue;
         "a hallway is preferred to a passage" >:: test_a_hallway_is_preferred_to_a_passage;
         "unknown rooms have no routes" >:: test_unknown_rooms_have_no_routes;
         "walking changes room and records the visit"
         >:: test_walking_changes_room_and_records_the_visit;
         "refused moves change nothing" >:: test_refused_moves_change_nothing;
         "a passage is reported new only once" >:: test_a_passage_is_reported_new_only_once;
         "arriving fires events and chains their clues"
         >:: test_arriving_fires_events_and_chains_their_clues;
         "an event fires only once" >:: test_an_event_fires_only_once;
         "an event waits for its clue" >:: test_an_event_waits_for_its_clue;
         "events stay in their room" >:: test_events_stay_in_their_room;
         "a case without exploration data still loads"
         >:: test_a_case_without_exploration_data_still_loads;
         "every room can be reached without clues"
         >:: test_every_room_can_be_reached_without_clues;
         "the ghost walk opens with the portrait latch"
         >:: test_the_ghost_walk_opens_with_the_portrait_latch;
         "every event is in a room that can be reached"
         >:: test_every_event_is_in_a_room_that_can_be_reached;
       ]
       @ List.map
           (fun (description, file, message) ->
             "validation rejects " ^ description >:: assert_rejected (file, message))
           rejection_tests

let () = run_test_tt_main suite
