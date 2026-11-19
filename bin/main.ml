open Lwt.Infix

let sessions : (string * Dialogue.session) list ref = ref []
let shared_clues : string list ref = ref []

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

type room = { id : string; name : string; description : string; row : int; col : int }

let rooms =
  [
    { id = "study"; name = "Study"; description = "A quiet study, disturbed in the night."; row = 1; col = 1 };
    { id = "hall"; name = "Hall"; description = "The hall connects the estate's main rooms."; row = 1; col = 3 };
    { id = "lounge"; name = "Lounge"; description = "A lounge with a fire gone cold."; row = 1; col = 5 };
    { id = "library"; name = "Library"; description = "Books and papers line the library walls."; row = 3; col = 1 };
    { id = "billiard"; name = "Billiard Room"; description = "A billiard table sits beneath a green-shaded lamp."; row = 3; col = 3 };
    { id = "dining"; name = "Dining Room"; description = "Dinner was left unfinished in the dining room."; row = 3; col = 5 };
    { id = "conservatory"; name = "Conservatory"; description = "Rain taps against the conservatory glass."; row = 5; col = 1 };
    { id = "ballroom"; name = "Ballroom"; description = "The ballroom is silent beneath its chandeliers."; row = 5; col = 3 };
    { id = "kitchen"; name = "Kitchen"; description = "The kitchen is dark except for a single lamp."; row = 5; col = 5 };
  ]

let find_room id = List.find_opt (fun room -> room.id = id) rooms
let find_character id = List.find_opt (fun character -> character.Dialogue.id = id) Dialogue.suspects

let json_string value = `String value
let json_int value = `Int value
let json_assoc fields = `Assoc fields

let room_json room =
  json_assoc
    [
      ("id", json_string room.id);
      ("name", json_string room.name);
      ("description", json_string room.description);
      ("row", json_int room.row);
      ("col", json_int room.col);
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

let valid_room requested =
  match Option.bind requested find_room with
  | Some room -> room
  | None -> List.hd rooms

let state_json ?(notice = "") room_id character_id =
  let room = valid_room room_id in
  let selected_character = Option.bind character_id find_character in
  json_assoc
    [
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
      ("selectedCharacter",
       (match selected_character with
       | None -> `Null
       | Some character -> character_json character));
      ("clues", `List (List.map json_string !shared_clues));
      ("notice", json_string notice);
    ]

let json_response ?(notice = "") params =
  Yojson.Basic.to_string
    (state_json ~notice (param "room" params) (param "suspect" params))

let ask_response params =
  let suspect_id = param "suspect" params in
  let notice =
    match (suspect_id, param "topic" params) with
    | Some suspect_id, Some topic_id ->
        (match find_character suspect_id with
        | None -> "Unknown character."
        | Some suspect ->
            let session = session_for suspect in
            let next_session, result = Dialogue.ask session topic_id in
            save_session suspect next_session;
            share_new_clues next_session;
            (match result with
            | Dialogue.Replied { text; newly_found = Some clue } ->
                text ^ " New information recorded: " ^ clue
            | Dialogue.Replied { text; newly_found = None } -> text
            | Dialogue.Locked _ -> "You do not have enough information for that question yet."
            | Dialogue.Already_asked message -> message
            | Dialogue.Unknown_topic -> "That question is unavailable."))
    | _ -> "Select a character and a question first."
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
  | "/api/state" -> (200, "application/json; charset=utf-8", json_response params)
  | "/api/ask" -> (200, "application/json; charset=utf-8", ask_response params)
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
     Printf.printf "Dialogue server ready at http://127.0.0.1:%d\n%!" port;
     open_browser (Printf.sprintf "http://127.0.0.1:%d" port);
     accept_loop ())

let () = serve 8080
