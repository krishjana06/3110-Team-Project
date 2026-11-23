open Lwt.Infix

let sessions : (string * Dialogue.session) list ref = ref []
let shared_clues : string list ref = ref []
let history : Yojson.Basic.t list ref = ref []
let ending : string option ref = ref None
let house : House.t ref = ref (House.start Case.data)

let record_history speaker prompt text =
  history := !history @ [ `Assoc [ "speaker", `String speaker;
    "prompt", `String prompt; "text", `String text ] ]

let add_clue clue =
  if List.mem clue !shared_clues then false
  else (
    shared_clues := !shared_clues @ [ clue ];
    sessions := List.map (fun (id, state) ->
      (id, Dialogue.add_clues state !shared_clues)) !sessions;
    true)

let hex_value = function
  | '0' .. '9' as c -> Char.code c - Char.code '0'
  | 'a' .. 'f' as c -> Char.code c - Char.code 'a' + 10
  | 'A' .. 'F' as c -> Char.code c - Char.code 'A' + 10
  | _ -> 0

let url_decode value =
  let buffer = Buffer.create (String.length value) in
  let rec loop i =
    if i < String.length value then
      match value.[i] with
      | '+' -> Buffer.add_char buffer ' '; loop (i + 1)
      | '%' when i + 2 < String.length value ->
          let c = (hex_value value.[i + 1] * 16) + hex_value value.[i + 2] in
          Buffer.add_char buffer (Char.chr c);
          loop (i + 3)
      | c -> Buffer.add_char buffer c; loop (i + 1)
  in
  loop 0;
  Buffer.contents buffer

let query_params target =
  match String.split_on_char '?' target with
  | _ :: query :: _ ->
      String.split_on_char '&' query
      |> List.filter_map (fun pair ->
             match String.split_on_char '=' pair with
             | key :: value :: _ -> Some (url_decode key, url_decode value)
             | _ -> None)
  | _ -> []

let param name params = List.assoc_opt name params

let session_for suspect =
  match List.assoc_opt suspect.Dialogue.id !sessions with
  | Some session -> session
  | None ->
      let session = Dialogue.start ~clues:!shared_clues suspect in
      sessions := (suspect.id, session) :: !sessions;
      session

let save_session suspect session =
  let session = Dialogue.add_clues session !shared_clues in
  sessions :=
    (suspect.Dialogue.id, session)
    :: List.remove_assoc suspect.id !sessions

let share_new_clues session =
  List.iter
    (fun clue ->
      if not (List.mem clue !shared_clues) then shared_clues := !shared_clues @ [ clue ])
    (Dialogue.clues session);
  sessions :=
    List.map (fun (id, state) -> (id, Dialogue.add_clues state !shared_clues)) !sessions

(** [record_events events] writes each haunted event in [events] to the
    journal and adds any clue it yields. It returns [events] with the clues
    that were new. [haunt ()] fires whatever is now due in the player's room
    and records it the same way; call it after anything that gives the player
    a clue, because an event may be waiting for exactly that clue. *)
let record_events events =
  let found =
    List.filter_map
      (fun (event : Case.event) ->
        record_history "The house" event.name event.text;
        match event.clue with
        | Some clue when add_clue clue -> Some clue
        | _ -> None)
      events
  in
  (events, found)

let haunt () =
  let next, events = House.haunt Case.data ~clues:!shared_clues !house in
  house := next;
  record_events events

let rooms = Case.data.rooms
let find_room = Case.find_room
let find_character id = List.find_opt (fun character -> character.Dialogue.id = id) Dialogue.suspects

let json_string value = `String value
let json_int value = `Int value
let json_assoc fields = `Assoc fields

let room_name id = match Case.find_room id with Some room -> room.name | None -> id

(** [hallway_between a b] is the name of a hallway joining rooms [a] and [b]. *)
let hallway_between a b =
  List.find_map
    (fun (h : Case.hallway) ->
      if List.mem a h.rooms && List.mem b h.rooms then Some h.name else None)
    Case.data.hallways

let current_routes () = House.routes Case.data ~clues:!shared_clues (House.location !house)

let route_json (route : House.route) =
  json_assoc
    [
      ("id", json_string route.room);
      ("name", json_string (room_name route.room));
      ("passage", match route.passage with None -> `Null | Some p -> json_string p.name);
      ("hallway",
       match hallway_between (House.location !house) route.room with
       | Some name when route.passage = None -> json_string name
       | _ -> `Null);
    ]

let passage_json (passage : Case.passage) =
  json_assoc
    [
      ("id", json_string passage.id);
      ("name", json_string passage.name);
      ("between", `List [ json_string (fst passage.between); json_string (snd passage.between) ]);
      ("open", `Bool (House.passage_open ~clues:!shared_clues passage));
      ("used", `Bool (List.mem passage.id (House.passages_used !house)));
    ]

let room_json (room : Case.room) =
  let here = House.location !house in
  json_assoc
    [
      ("id", json_string room.id);
      ("current", `Bool (room.id = here));
      ("visited", `Bool (List.mem room.id (House.visited !house)));
      ("reachable", `Bool (List.exists (fun (r : House.route) -> r.room = room.id) (current_routes ())));
      ("name", json_string room.name);
      ("description", json_string room.description);
      ("row", json_int room.row);
      ("col", json_int room.col);
      ("objects", `List (List.map (fun (object_ : Case.object_) ->
        json_assoc [ "id", json_string object_.id; "name", json_string object_.name;
          "locked", `Bool (not (Case.unlocked !shared_clues object_));
          "inspected", `Bool (List.mem object_.clue !shared_clues) ]) room.objects));
    ]

let topic_json (topic : Dialogue.topic) =
  json_assoc [ ("id", json_string topic.Dialogue.id); ("prompt", json_string topic.prompt) ]

let character_json (character : Dialogue.suspect) =
  let questions =
    session_for character
    |> Dialogue.available_topics
    |> List.map topic_json
  in
  json_assoc
    [
      ("id", json_string character.Dialogue.id);
      ("name", json_string character.name);
      ("greeting", json_string character.greeting);
      ("questions", `List questions);
    ]

let current_room () =
  match find_room (House.location !house) with
  | Some room -> room
  | None -> List.hd rooms

let clue_json (clue : Case.clue) =
  json_assoc [ "id", json_string clue.id; "title", json_string clue.title;
    "kind", json_string clue.kind; "source", json_string clue.source;
    "description", json_string clue.description ]

let event_json (event : Case.event) =
  json_assoc [ "id", json_string event.id; "name", json_string event.name; "text", json_string event.text ]

let state_json ?(notice = "") ?(new_evidence = []) ?(haunting = []) character_id =
  let room = current_room () in
  let selected_character = Option.bind character_id find_character in
  json_assoc
    [
      ("story", json_assoc [ "title", json_string Case.data.title;
        "intro", json_string Case.data.intro; "objective", json_string Case.data.objective ]);
      ("weapons", `List (List.map (fun (weapon : Case.weapon) ->
        json_assoc [ "id", json_string weapon.id; "name", json_string weapon.name ]) Case.data.weapons));
      ("rooms", `List (List.map room_json rooms));
      ("characters",
       `List
         (List.map
            (fun character ->
              json_assoc
                [
                  ("id", json_string character.Dialogue.id);
                  ("name", json_string character.name);
                ])
            Dialogue.suspects));
      ("selectedRoom", room_json room);
      ("location", json_string room.id);
      ("routes", `List (List.map route_json (current_routes ())));
      ("passages", `List (List.map passage_json Case.data.passages));
      ("haunting", `List (List.map event_json haunting));
      ("selectedCharacter",
       (match selected_character with
       | None -> `Null
       | Some character -> character_json character));
      ("clues", `List (List.map json_string !shared_clues));
      ("evidence", `List (List.filter_map Case.find_clue !shared_clues |> List.map clue_json));
      ("newEvidence", `List (List.map json_string new_evidence));
      ("history", `List !history);
      ("ending", match !ending with None -> `Null | Some text -> json_string text);
      ("notice", json_string notice);
    ]

let json_response ?(notice = "") ?(new_evidence = []) ?(haunting = []) params =
  Yojson.Basic.to_string
    (state_json ~notice ~new_evidence ~haunting (param "suspect" params))

let ask_response params =
  let new_evidence = ref [] in
  let notice =
    match (param "suspect" params, param "topic" params) with
    | Some suspect_id, Some topic_id ->
        (match find_character suspect_id with
        | None -> "Unknown character."
        | Some suspect ->
            let session = session_for suspect in
            let next_session, result = Dialogue.ask session topic_id in
            save_session suspect next_session;
            share_new_clues next_session;
            (match result with
            | Dialogue.Replied { text; newly_found } ->
                let topic = List.find (fun (t : Dialogue.topic) -> t.id = topic_id) suspect.topics in
                record_history suspect.name topic.prompt text;
                new_evidence := Option.to_list newly_found;
                suspect.name ^ ": " ^ text
            | Dialogue.Locked _ -> "You do not have enough information for that question yet."
            | Dialogue.Already_asked message -> message
            | Dialogue.Unknown_topic -> "That question is unavailable."))
    | _ -> "Select a character and a question first."
  in
  let haunting, found = haunt () in
  json_response ~notice ~new_evidence:(!new_evidence @ found) ~haunting params

let inspect_response params =
  let new_evidence = ref [] in
  let here = current_room () in
  let notice =
    match param "room" params, param "object" params with
    | Some requested, Some _ when requested <> here.id ->
        Printf.sprintf "You are in the %s. Walk to the %s before searching it." here.name
          (room_name requested)
    | _, Some object_id ->
        let room = here in
        (match Case.find_object room object_id with
        | None -> "That object is not in this room."
        | Some object_ when not (Case.unlocked !shared_clues object_) ->
            "The panel is locked. Investigate the knocking in the hall to find a way in."
        | Some object_ ->
            if add_clue object_.clue then (
              new_evidence := [ object_.clue ];
              record_history room.name object_.name object_.description);
            object_.description)
    | _ -> "Select an object to inspect."
  in
  let haunting, found = haunt () in
  json_response ~notice ~new_evidence:(!new_evidence @ found) ~haunting params

(** [via_rooms destination] names the rooms the player can walk to now from
    which [destination] is one more step, as an English list such as
    ["the Library, the Billiard Room, or the Dining Room"]. *)
let via_rooms destination =
  let names =
    current_routes ()
    |> List.filter (fun (r : House.route) ->
           List.exists (fun (onward : House.route) -> onward.room = destination)
             (House.routes Case.data ~clues:!shared_clues r.room))
    |> List.map (fun (r : House.route) -> "the " ^ room_name r.room)
  in
  match List.rev names with
  | [] -> None
  | [ only ] -> Some only
  | last :: rest -> Some (String.concat ", " (List.rev rest) ^ ", or " ^ last)

let move_response params =
  let haunting = ref [] and new_evidence = ref [] in
  let notice =
    match param "room" params with
    | None -> "Choose a room to walk to."
    | Some requested -> (
        let from = House.location !house in
        let next, result = House.move Case.data ~clues:!shared_clues !house requested in
        house := next;
        let blocked reason =
          match via_rooms requested with
          | Some via -> Printf.sprintf "%s Try going through %s." reason via
          | None -> reason
        in
        match result with
        | House.Moved { passage; first_time_through; events } ->
            let walked =
              match passage with
              | Some p ->
                  (* Only the first trip through a passage is worth a journal entry. *)
                  if first_time_through then (
                    record_history p.name ("To the " ^ room_name requested) p.description;
                    p.description)
                  else
                    Printf.sprintf "You slip through %s to the %s."
                      (String.uncapitalize_ascii p.name) (room_name requested)
              | None -> (
                  match hallway_between from requested with
                  | Some hall ->
                      Printf.sprintf "You walk the %s to the %s."
                        (String.lowercase_ascii hall) (room_name requested)
                  | None -> "You walk to the " ^ room_name requested ^ ".")
            in
            (* The walk is journaled before whatever happens on arrival. *)
            let fired, found = record_events events in
            haunting := fired;
            new_evidence := found;
            walked
        | House.Already_here -> "You are already in the " ^ room_name requested ^ "."
        | House.Not_connected ->
            blocked
              (Printf.sprintf "No hallway joins the %s to the %s." (room_name from)
                 (room_name requested))
        | House.Passage_locked _ ->
            (* Hint that something is there without naming the passage. *)
            blocked
              (Printf.sprintf
                 "No hallway joins the %s to the %s, though a cold draft seems to come from inside the walls."
                 (room_name from) (room_name requested))
        | House.Unknown_room -> "There is no such room.")
  in
  json_response ~notice ~new_evidence:!new_evidence ~haunting:!haunting params

let accuse_response params =
  let notice =
    match param "accused" params, param "weapon" params, param "location" params with
    | Some suspect, Some weapon, Some room
      when Option.is_some (find_character suspect) && Option.is_some (find_room room)
        && List.exists (fun (w : Case.weapon) -> w.id = weapon) Case.data.weapons ->
        if Case.correct_accusation ~suspect ~weapon ~room then (
          ending := Some (Case.string "explanation" Case.data.solution);
          "Case solved. Your accusation accounts for the suspect, weapon, and room.")
        else "That combination does not fit the case. Review the physical evidence and witness accounts, then try again."
    | _ -> "Choose a suspect, a weapon, and a room before making an accusation."
  in
  json_response ~notice params

let read_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let rec find_project_root directory =
  if Sys.file_exists (Filename.concat directory "web/index.html") then directory
  else
    let parent = Filename.dirname directory in
    if parent = directory then failwith "Cannot find web/index.html from the current directory"
    else find_project_root parent

let project_root = find_project_root (Sys.getcwd ())
let asset name = read_file (Filename.concat (Filename.concat project_root "web") name)

let route target =
  let path = List.hd (String.split_on_char '?' target) in
  let params = query_params target in
  match path with
  | "/" | "/index.html" -> (200, "text/html; charset=utf-8", asset "index.html")
  | "/style.css" -> (200, "text/css; charset=utf-8", asset "style.css")
  | "/app.js" -> (200, "text/javascript; charset=utf-8", asset "app.js")
  | "/assets/estate-plan.svg" -> (200, "image/svg+xml; charset=utf-8", asset "assets/estate-plan.svg")
  | "/assets/suspect-portraits.png" -> (200, "image/png", asset "assets/suspect-portraits.png")
  | "/api/state" -> (200, "application/json; charset=utf-8", json_response params)
  | "/api/ask" -> (200, "application/json; charset=utf-8", ask_response params)
  | "/api/inspect" -> (200, "application/json; charset=utf-8", inspect_response params)
  | "/api/move" -> (200, "application/json; charset=utf-8", move_response params)
  | "/api/accuse" -> (200, "application/json; charset=utf-8", accuse_response params)
  | _ ->
      (404, "text/plain; charset=utf-8", "Not found")

let status_text = function 200 -> "200 OK" | 404 -> "404 Not Found" | _ -> "500 Internal Server Error"

let browser_launcher () =
  if Sys.os_type = "Win32" then ("cmd", [| "cmd"; "/c"; "start"; "" |])
  else if Sys.file_exists "/usr/bin/open" then ("/usr/bin/open", [| "/usr/bin/open" |])
  else ("xdg-open", [| "xdg-open" |])

let open_browser url =
  let command, args = browser_launcher () in
  let args = Array.append args [| url |] in
  Lwt.async (fun () ->
      Lwt.catch
        (fun () ->
          Lwt_process.exec (command, args) >|= function
          | Unix.WEXITED 0 -> ()
          | _ ->
              Printf.eprintf "Could not open a browser automatically. Open %s manually.\n%!" url)
        (fun _ ->
          Printf.eprintf "Could not open a browser automatically. Open %s manually.\n%!" url;
          Lwt.return_unit))

let handle_connection fd address =
  let input = Lwt_io.of_fd ~mode:Lwt_io.Input fd in
  let output = Lwt_io.of_fd ~mode:Lwt_io.Output fd in
  let rec read_headers () =
    Lwt_io.read_line_opt input >>= function
    | None | Some "" | Some "\r" -> Lwt.return_unit
    | Some _ -> read_headers ()
  in
  let request =
    Lwt_io.read_line_opt input >>= function
    | None -> Lwt.return (404, "text/plain; charset=utf-8", "Not found")
    | Some line ->
        read_headers () >|= fun () ->
        match String.split_on_char ' ' line with
        | "GET" :: target :: _ -> route target
        | _ -> (404, "text/plain; charset=utf-8", "Only GET is supported")
  in
  Lwt.catch
    (fun () ->
      request >>= fun (status, content_type, body) ->
      let headers =
        Printf.sprintf
          "HTTP/1.1 %s\r\nContent-Type: %s\r\nCache-Control: no-store\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"
          (status_text status) content_type (String.length body)
      in
      Lwt_io.write output (headers ^ body) >>= fun () ->
      Lwt_io.flush output >>= fun () ->
      Lwt_io.close input >>= fun () ->
      Lwt_io.close output >|= fun () ->
      ignore address)
    (fun _ ->
      Lwt.catch (fun () -> Lwt_io.close input) (fun _ -> Lwt.return_unit)
      >>= fun () ->
      Lwt.catch (fun () -> Lwt_io.close output) (fun _ -> Lwt.return_unit))

let serve port =
  (* A browser may cancel an image request when it navigates away. Let the
     connection handler catch EPIPE instead of terminating the whole game. *)
  Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
  let open Lwt_unix in
  let socket = socket PF_INET SOCK_STREAM 0 in
  setsockopt socket SO_REUSEADDR true;
  let rec accept_loop () =
    accept socket >>= fun (client, address) ->
    Lwt.async (fun () -> handle_connection client address);
    accept_loop ()
  in
  Lwt_main.run
    (bind socket (ADDR_INET (Unix.inet_addr_loopback, port)) >>= fun () ->
     listen socket 16;
     Printf.printf "Mystery game ready at http://127.0.0.1:%d\n%!" port;
     if Sys.getenv_opt "NO_BROWSER" <> Some "1" then
       open_browser (Printf.sprintf "http://127.0.0.1:%d" port);
     accept_loop ())

let () =
  let port =
    match Sys.getenv_opt "PORT" with
    | None -> 8080
    | Some value ->
        (match int_of_string_opt value with
        | Some port when port > 0 && port < 65536 -> port
        | _ -> failwith "PORT must be an integer between 1 and 65535")
  in
  serve port
