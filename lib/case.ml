open Yojson.Basic.Util

type clue = { id : string; title : string; kind : string; source : string; description : string }
type object_ = { id : string; name : string; description : string; clue : string; requires : string list }
type room = { id : string; name : string; description : string; row : int; col : int; objects : object_ list }
type weapon = { id : string; name : string }
type hallway = { id : string; name : string; rooms : string list }
type passage = { id : string; name : string; between : string * string; requires : string list; description : string }
type event = { id : string; room : string; name : string; text : string; clue : string option; requires : string list }
type t = { title : string; intro : string; objective : string; rooms : room list; clues : clue list; weapons : weapon list;
  hallways : hallway list; passages : passage list; events : event list;
  suspects : Yojson.Basic.t list; solution : Yojson.Basic.t }

let string key json = json |> member key |> to_string
let strings key json = json |> member key |> to_list |> List.map to_string
let parse_clue json : clue =
  { id = string "id" json; title = string "title" json; kind = string "kind" json;
    source = string "source" json; description = string "description" json }
let parse_object json : object_ =
  { id = string "id" json; name = string "name" json; description = string "description" json;
    clue = string "clue" json; requires = strings "requires" json }
let parse_room json : room =
  { id = string "id" json; name = string "name" json; description = string "description" json;
    row = json |> member "row" |> to_int; col = json |> member "col" |> to_int;
    objects = json |> member "objects" |> to_list |> List.map parse_object }
let parse_weapon json : weapon = { id = string "id" json; name = string "name" json }
let parse_hallway json : hallway =
  { id = string "id" json; name = string "name" json; rooms = strings "rooms" json }
let parse_passage json : passage =
  let between = match strings "between" json with
    | [ a; b ] -> (a, b)
    | _ -> failwith ("Passage " ^ string "id" json ^ " must connect exactly two rooms") in
  { id = string "id" json; name = string "name" json; between;
    requires = strings "requires" json; description = string "description" json }
let parse_event json : event =
  { id = string "id" json; room = string "room" json; name = string "name" json; text = string "text" json;
    clue = (match member "clue" json with `Null -> None | value -> Some (to_string value));
    requires = strings "requires" json }

(* Hallways, passages, and events were added after the first case files were
   written, so a case without them is still a valid (if unhaunted) case. *)
let optional_list key parse json =
  match member key json with `Null -> [] | value -> value |> to_list |> List.map parse

let validate data =
  let unique label ids =
    let rec check seen = function
      | [] -> ()
      | id :: rest ->
          if List.mem id seen then failwith ("Duplicate " ^ label ^ " ID: " ^ id);
          check (id :: seen) rest
    in check [] ids
  in
  let clue_ids = List.map (fun (c : clue) -> c.id) data.clues in
  let check_clue id =
    if not (List.mem id clue_ids) then failwith ("Unknown clue ID: " ^ id)
  in
  unique "clue" clue_ids;
  unique "room" (List.map (fun (r : room) -> r.id) data.rooms);
  unique "weapon" (List.map (fun (w : weapon) -> w.id) data.weapons);
  unique "suspect" (List.map (string "id") data.suspects);
  List.iter (fun (r : room) ->
    unique (r.id ^ " object") (List.map (fun (o : object_) -> o.id) r.objects);
    List.iter (fun (o : object_) -> check_clue o.clue; List.iter check_clue o.requires) r.objects) data.rooms;
  List.iter (fun suspect ->
    let topics = suspect |> member "topics" |> to_list in
    unique "topic" (List.map (string "id") topics);
    List.iter (fun topic ->
      (match member "clue" topic with `Null -> () | value -> check_clue (to_string value));
      List.iter check_clue (strings "requires" topic)) topics) data.suspects;
  let room_ids = List.map (fun (r : room) -> r.id) data.rooms in
  let check_room label id =
    if not (List.mem id room_ids) then failwith ("Unknown " ^ label ^ " room: " ^ id)
  in
  unique "hallway" (List.map (fun (h : hallway) -> h.id) data.hallways);
  List.iter (fun (h : hallway) -> List.iter (check_room "hallway") h.rooms) data.hallways;
  unique "passage" (List.map (fun (p : passage) -> p.id) data.passages);
  List.iter (fun (p : passage) ->
    check_room "passage" (fst p.between); check_room "passage" (snd p.between);
    List.iter check_clue p.requires) data.passages;
  unique "event" (List.map (fun (e : event) -> e.id) data.events);
  List.iter (fun (e : event) ->
    check_room "event" e.room; Option.iter check_clue e.clue; List.iter check_clue e.requires) data.events;
  List.iter (fun (key, ids) ->
    if not (List.mem (string key data.solution) ids) then
      failwith ("Unknown solution " ^ key))
    [ "suspect", List.map (string "id") data.suspects;
      "weapon", List.map (fun (w : weapon) -> w.id) data.weapons;
      "room", List.map (fun (r : room) -> r.id) data.rooms ]

let load path =
  let json = Yojson.Basic.from_file path in
  let data = {
    title = string "title" json; intro = string "intro" json; objective = string "objective" json;
    rooms = json |> member "rooms" |> to_list |> List.map parse_room;
    clues = json |> member "clues" |> to_list |> List.map parse_clue;
    weapons = json |> member "weapons" |> to_list |> List.map parse_weapon;
    hallways = optional_list "hallways" parse_hallway json;
    passages = optional_list "passages" parse_passage json;
    events = optional_list "events" parse_event json;
    suspects = json |> member "suspects" |> to_list; solution = member "solution" json;
  } in
  validate data; data

let rec find_path directory =
  let path = Filename.concat directory "data/case.json" in
  if Sys.file_exists path then path
  else let parent = Filename.dirname directory in
    if parent = directory then failwith "Cannot find data/case.json. Run from the project directory."
    else find_path parent

let data = load (find_path (Sys.getcwd ()))
let find_clue id = List.find_opt (fun (c : clue) -> c.id = id) data.clues
let find_room id = List.find_opt (fun (r : room) -> r.id = id) data.rooms
let find_object (room : room) id = List.find_opt (fun (o : object_) -> o.id = id) room.objects
let unlocked clues (object_ : object_) = List.for_all (fun id -> List.mem id clues) object_.requires
let correct_accusation ~suspect ~weapon ~room =
  string "suspect" data.solution = suspect && string "weapon" data.solution = weapon
  && string "room" data.solution = room
