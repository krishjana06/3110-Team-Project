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

(* Replace these sample entries with the names, topics, and clues from the
   game design. Clue IDs are shared across suspects to support cross-talk. *)
let suspects =
  [
    {
      id = "scarlet";
      name = "Miss Scarlet";
      greeting = "[Placeholder greeting. Replace with Miss Scarlet's dialogue.]";
      topics =
        [
          { id = "whereabouts"; prompt = "Where were you at the time of the murder?";
            reply = "[Placeholder answer about whereabouts.]"; clue = Some "timeline"; requires = [] };
          { id = "victim"; prompt = "What was your relationship with the victim?";
            reply = "[Placeholder answer about the victim.]"; clue = None; requires = [] };
          { id = "scarlet_placeholder_1"; prompt = "[Placeholder question]";
            reply = ""; clue = None; requires = [] };
          { id = "scarlet_placeholder_2"; prompt = "[Placeholder question]";
            reply = ""; clue = None; requires = [] };
        ];
    };
    {
      id = "mustard";
      name = "Colonel Mustard";
      greeting = "[Placeholder greeting. Replace with Colonel Mustard's dialogue.]";
      topics =
        [
          { id = "whereabouts"; prompt = "Where were you at the time of the murder?";
            reply = "[Placeholder response about Colonel Mustard's whereabouts.]";
            clue = Some "mustard_alibi"; requires = [] };
          { id = "argument"; prompt = "Did you argue with the victim?";
            reply = "[Placeholder answer about an argument.]"; clue = Some "motive"; requires = [] };
          { id = "timeline_followup"; prompt = "Can anyone confirm your timeline?";
            reply = "[Placeholder answer that connects the timelines.]"; clue = Some "witness_account";
            requires = [ "timeline" ] };
          { id = "mustard_placeholder_1"; prompt = "[Placeholder question]";
            reply = ""; clue = None; requires = [] };
          { id = "mustard_placeholder_2"; prompt = "[Placeholder question]";
            reply = ""; clue = None; requires = [] };
        ];
    };
    {
      id = "white";
      name = "Mrs. White";
      greeting = "[Placeholder greeting. Replace with Mrs. White's dialogue.]";
      topics =
        [
          { id = "whereabouts"; prompt = "Where were you at the time of the murder?";
            reply = "[Placeholder response about Mrs. White's whereabouts.]";
            clue = Some "white_alibi"; requires = [] };
          { id = "victim"; prompt = "What was your relationship with the victim?";
            reply = "[Placeholder answer about Mrs. White's connection to the victim.]";
            clue = None; requires = [] };
          { id = "evidence"; prompt = "Do you recognize this evidence?";
            reply = "[Placeholder reaction to evidence.]"; clue = Some "evidence_link";
            requires = [ "motive" ] };
          { id = "white_placeholder_1"; prompt = "[Placeholder question]";
            reply = ""; clue = None; requires = [] };
          { id = "white_placeholder_2"; prompt = "[Placeholder question]";
            reply = ""; clue = None; requires = [] };
        ];
    };
    {
      id = "green";
      name = "Mr. Green";
      greeting = "[Placeholder greeting. Replace with Mr. Green's dialogue.]";
      topics =
        [
          { id = "whereabouts"; prompt = "Where were you at the time of the murder?";
            reply = "[Placeholder response about Mr. Green's whereabouts.]";
            clue = Some "green_alibi"; requires = [] };
          { id = "alibi"; prompt = "Who can confirm your alibi?";
            reply = "[Placeholder answer about the alibi.]"; clue = None; requires = [] };
          { id = "room_visit"; prompt = "Which rooms did you visit?";
            reply = "[Placeholder answer about the rooms visited.]"; clue = None; requires = [] };
          { id = "green_placeholder_1"; prompt = "[Placeholder question]";
            reply = ""; clue = None; requires = [] };
          { id = "green_placeholder_2"; prompt = "[Placeholder question]";
            reply = ""; clue = None; requires = [] };
        ];
    };
    {
      id = "peacock";
      name = "Mrs. Peacock";
      greeting = "[Placeholder greeting. Replace with Mrs. Peacock's dialogue.]";
      topics =
        [
          { id = "whereabouts"; prompt = "Where were you at the time of the murder?";
            reply = "[Placeholder response about Mrs. Peacock's whereabouts.]";
            clue = Some "peacock_alibi"; requires = [] };
          { id = "evening"; prompt = "What do you remember about the evening?";
            reply = "[Placeholder recollection of the evening.]"; clue = None; requires = [] };
          { id = "discovery"; prompt = "Did you notice anything unusual?";
            reply = "[Placeholder observation.]"; clue = None; requires = [] };
          { id = "peacock_placeholder_1"; prompt = "[Placeholder question]";
            reply = ""; clue = None; requires = [] };
          { id = "peacock_placeholder_2"; prompt = "[Placeholder question]";
            reply = ""; clue = None; requires = [] };
        ];
    };
    {
      id = "plum";
      name = "Professor Plum";
      greeting = "[Placeholder greeting. Replace with Professor Plum's dialogue.]";
      topics =
        [
          { id = "whereabouts"; prompt = "Where were you at the time of the murder?";
            reply = "[Placeholder response about Professor Plum's whereabouts.]";
            clue = Some "plum_alibi"; requires = [] };
          { id = "research"; prompt = "What brought you to the house?";
            reply = "[Placeholder answer about the visit.]"; clue = None; requires = [] };
          { id = "witness"; prompt = "Did you see anyone leave a room?";
            reply = "[Placeholder answer about a possible witness.]"; clue = None; requires = [] };
          { id = "plum_placeholder_1"; prompt = "[Placeholder question]";
            reply = ""; clue = None; requires = [] };
          { id = "plum_placeholder_2"; prompt = "[Placeholder question]";
            reply = ""; clue = None; requires = [] };
        ];
    };
  ]

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
