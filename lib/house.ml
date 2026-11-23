type t = {
  location : string;
  visited : string list;
  fired : string list;
  passages_used : string list;
}

type route = {
  room : string;
  passage : Case.passage option;
}

type move_result =
  | Moved of {
      passage : Case.passage option;
      first_time_through : bool;
      events : Case.event list;
    }
  | Already_here
  | Not_connected
  | Passage_locked of Case.passage
  | Unknown_room

let start (case : Case.t) =
  match case.rooms with
  | [] -> invalid_arg "House.start: the case has no rooms"
  | first :: _ ->
      { location = first.id; visited = [ first.id ]; fired = []; passages_used = [] }

let location house = house.location
let visited house = house.visited
let fired house = house.fired
let passages_used house = house.passages_used
let holds clues required = List.for_all (fun id -> List.mem id clues) required
let passage_open ~clues (passage : Case.passage) = holds clues passage.requires

(** [other_end passage room] is the room at the far end of [passage] from
    [room], or [None] if [passage] does not touch [room]. *)
let other_end (passage : Case.passage) room =
  match passage.between with
  | a, b when a = room -> Some b
  | a, b when b = room -> Some a
  | _ -> None

let by_hallway (case : Case.t) from destination =
  from <> destination
  && List.exists
       (fun (h : Case.hallway) -> List.mem from h.rooms && List.mem destination h.rooms)
       case.hallways

(** [passages_between case from destination] is every passage of [case]
    joining those two rooms, open or not, in file order. *)
let passages_between (case : Case.t) from destination =
  List.filter (fun p -> other_end p from = Some destination) case.passages

let routes (case : Case.t) ~clues from =
  List.filter_map
    (fun (r : Case.room) ->
      if by_hallway case from r.id then Some { room = r.id; passage = None }
      else
        match List.find_opt (passage_open ~clues) (passages_between case from r.id) with
        | Some p when r.id <> from -> Some { room = r.id; passage = Some p }
        | _ -> None)
    case.rooms

let haunt (case : Case.t) ~clues house =
  let house, clues, events =
    List.fold_left
      (fun (house, clues, events) (e : Case.event) ->
        if e.room = house.location && (not (List.mem e.id house.fired)) && holds clues e.requires
        then
          ( { house with fired = house.fired @ [ e.id ] },
            (match e.clue with Some c -> c :: clues | None -> clues),
            e :: events )
        else (house, clues, events))
      (house, clues, []) case.events
  in
  ignore clues;
  (house, List.rev events)

let arrive case ~clues house room passage =
  let first_time_through =
    match passage with
    | Some (p : Case.passage) -> not (List.mem p.id house.passages_used)
    | None -> false
  in
  let house =
    {
      house with
      location = room;
      visited = (if List.mem room house.visited then house.visited else house.visited @ [ room ]);
      passages_used =
        (match passage with
        | Some p when first_time_through -> house.passages_used @ [ p.id ]
        | _ -> house.passages_used);
    }
  in
  let house, events = haunt case ~clues house in
  (house, Moved { passage; first_time_through; events })

let move (case : Case.t) ~clues house destination =
  if not (List.exists (fun (r : Case.room) -> r.id = destination) case.rooms) then
    (house, Unknown_room)
  else if destination = house.location then (house, Already_here)
  else
    match List.find_opt (fun r -> r.room = destination) (routes case ~clues house.location) with
    | Some r -> arrive case ~clues house destination r.passage
    | None -> (
        match passages_between case house.location destination with
        | locked :: _ -> (house, Passage_locked locked)
        | [] -> (house, Not_connected))
