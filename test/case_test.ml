let check message condition = if not condition then failwith message
let suspect id = List.find (fun (s : Dialogue.suspect) -> s.id = id) Dialogue.suspects
let has_topic id session = List.exists (fun (t : Dialogue.topic) -> t.id = id) (Dialogue.available_topics session)

let () =
  (* Expectations are derived from the written case: the physical cufflink
     unlocks a contradiction; the passage requires both a route and a heel. *)
  let mustard = Dialogue.start (suspect "mustard") in
  check "Cufflink contradiction must begin locked" (not (has_topic "cufflink" mustard));
  let unchanged, result = Dialogue.ask mustard "cufflink" in
  check "Locked topic must not change clues" (Dialogue.clues unchanged = []);
  (match result with Dialogue.Locked "cufflink" -> () | _ -> failwith "Expected missing cufflink");
  let mustard = Dialogue.add_clues mustard [ "cufflink"; "cufflink" ] in
  check "Evidence is deduplicated" (Dialogue.clues mustard = [ "cufflink" ]);
  check "Found cufflink unlocks question" (has_topic "cufflink" mustard);
  let mustard, result = Dialogue.ask mustard "cufflink" in
  (match result with
  | Dialogue.Replied { newly_found = Some "cufflink_response"; text } -> check "Real dialogue" (String.length text > 40)
  | _ -> failwith "Cufflink should produce an admission of ownership");
  let repeated, result = Dialogue.ask mustard "cufflink" in
  (match result with Dialogue.Already_asked _ -> () | _ -> failwith "Repeated question should be rejected");
  check "Repeated question adds nothing" (Dialogue.clues repeated = Dialogue.clues mustard);
  check "Asked topics disappear" (not (has_topic "cufflink" mustard));
  let mustard = Dialogue.add_clues mustard [ "passage_tracks"; "boots" ] in
  check "Passage confrontation also requires an earlier alibi" (not (has_topic "passage" mustard));
  let mustard, _ = Dialogue.ask mustard "whereabouts" in
  check "Physical evidence plus alibi unlocks confrontation" (has_topic "passage" mustard);
  let _, result = Dialogue.ask mustard "passage" in
  (match result with Dialogue.Replied { newly_found = Some "passage_admission"; _ } -> () | _ -> failwith "Expected changed account");
  let study = Option.get (Case.find_room "study") in
  let panel = Option.get (Case.find_object study "panel") in
  check "Passage starts locked" (not (Case.unlocked [] panel));
  check "Portrait unlocks passage" (Case.unlocked [ "passage_latch" ] panel);
  let plum = Dialogue.start ~clues:[ "candlestick" ] (suspect "plum") in
  check "Fiber comparison requires both pieces" (not (has_topic "fiber" plum));
  check "Both pieces unlock comparison" (has_topic "fiber" (Dialogue.add_clues plum [ "torn_sleeve" ]));
  check "Fixed solution" (Case.correct_accusation ~suspect:"mustard" ~weapon:"candlestick" ~room:"study");
  check "Wrong weapon fails" (not (Case.correct_accusation ~suspect:"mustard" ~weapon:"dagger" ~room:"study"));
  check "Wrong room fails" (not (Case.correct_accusation ~suspect:"mustard" ~weapon:"candlestick" ~room:"dining"));
  check "Wrong suspect fails" (not (Case.correct_accusation ~suspect:"plum" ~weapon:"candlestick" ~room:"study"));
  let bad = { Case.data with rooms = [{ study with objects = [{ panel with clue = "missing_clue" }] }] } in
  (match Case.validate bad with
   | exception Failure message -> check "Invalid IDs identify the missing clue" (message = "Unknown clue ID: missing_clue")
   | () -> failwith "Invalid clue IDs must fail validation");
  print_endline "Case and dialogue checks passed."
