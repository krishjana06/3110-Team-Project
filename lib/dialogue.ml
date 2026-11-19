type topic = {
  id : string;
  prompt : string;
  reply : string;
  clue : string option;
  requires : string list;
}

type suspect = { id : string; name : string; greeting : string; topics : topic list }

type session = {
  suspect : suspect;
  asked : string list;
  found_clues : string list;
}

type result =
  | Replied of { text : string; newly_found : string option }
  | Locked of string
  | Already_asked of string
  | Unknown_topic

(* Story text and clue prerequisites live in data/case.json. *)
let suspects =
  let open Yojson.Basic.Util in
  List.map (fun json ->
    let topics = json |> member "topics" |> to_list |> List.map (fun topic ->
      { id = Case.string "id" topic; prompt = Case.string "prompt" topic;
        reply = Case.string "reply" topic;
        clue = (match member "clue" topic with `Null -> None | value -> Some (to_string value));
        requires = Case.strings "requires" topic }) in
    { id = Case.string "id" json; name = Case.string "name" json;
      greeting = Case.string "greeting" json; topics }) Case.data.suspects

let start ?(clues = []) suspect = { suspect; asked = []; found_clues = clues }
let clues session = session.found_clues

let add_clues session clues =
  let found_clues =
    List.fold_left
      (fun found clue -> if List.mem clue found then found else found @ [ clue ])
      session.found_clues clues
  in
  { session with found_clues }

let available_topics session =
  List.filter
    (fun (topic : topic) ->
      not (List.mem topic.id session.asked)
      && List.for_all (fun clue -> List.mem clue session.found_clues) topic.requires)
    session.suspect.topics

let ask session topic_id =
  match List.find_opt (fun (topic : topic) -> topic.id = topic_id) session.suspect.topics with
  | None -> (session, Unknown_topic)
  | Some topic when List.mem topic.id session.asked ->
      (session, Already_asked "You have already asked that question.")
  | Some topic ->
      let missing =
        List.filter (fun clue -> not (List.mem clue session.found_clues)) topic.requires
      in
      (match missing with
      | clue :: _ -> (session, Locked clue)
      | [] ->
          let found_clues =
            match topic.clue with
            | Some clue when not (List.mem clue session.found_clues) ->
                session.found_clues @ [ clue ]
            | _ -> session.found_clues
          in
          let newly_found =
            match topic.clue with
            | Some clue when not (List.mem clue session.found_clues) -> Some clue
            | _ -> None
          in
          ({ session with asked = topic.id :: session.asked; found_clues },
           Replied { text = topic.reply; newly_found }))
