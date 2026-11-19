let rec choose_suspect clues =
  print_endline "\nChoose someone to question:";
  List.iteri (fun i suspect -> Printf.printf "  %d) %s\n" (i + 1) suspect.Dialogue.name)
    Dialogue.suspects;
  print_endline "  q) Quit";
  print_string "> ";
  match read_line () with
  | exception End_of_file -> ()
  | "q" | "Q" -> print_endline "Goodbye."
  | choice ->
      (match int_of_string_opt choice with
      | Some n when n > 0 && n <= List.length Dialogue.suspects ->
          let suspect = List.nth Dialogue.suspects (n - 1) in
          run_interview suspect (Dialogue.start ~clues suspect)
      | _ -> print_endline "Please enter a listed number or q."; choose_suspect clues)

and run_interview suspect session =
  Printf.printf "\n%s: %s\n" suspect.Dialogue.name suspect.Dialogue.greeting;
  let rec loop session =
    let topics = Dialogue.available_topics session in
    if topics = [] then (
      print_endline "There are no questions available right now.";
      print_endline "  b) Back to suspect list";
      print_string "> ";
      match read_line () with
      | exception End_of_file -> ()
      | _ -> choose_suspect (Dialogue.clues session))
    else (
      print_endline "\nAsk about:";
      List.iteri (fun i topic -> Printf.printf "  %d) %s\n" (i + 1) topic.Dialogue.prompt) topics;
      print_endline "  b) Back to suspect list";
      print_string "> ";
      match read_line () with
      | exception End_of_file -> ()
      | "b" | "B" -> choose_suspect (Dialogue.clues session)
      | choice ->
          (match int_of_string_opt choice with
          | Some n when n > 0 && n <= List.length topics ->
              let topic = List.nth topics (n - 1) in
              let session, result = Dialogue.ask session topic.Dialogue.id in
              (match result with
              | Dialogue.Replied { text; newly_found } ->
                  Printf.printf "\n%s: %s\n" suspect.Dialogue.name text;
                  (match newly_found with
                  | Some clue -> Printf.printf "[New information recorded: %s]\n" clue
                  | None -> ())
              | Dialogue.Locked _ -> print_endline "You do not have enough information to ask that yet."
              | Dialogue.Already_asked message -> print_endline message
              | Dialogue.Unknown_topic -> print_endline "That question is unavailable.");
              loop session
          | _ -> print_endline "Please enter a listed number or b."; loop session))
  in
  loop session

let () =
  print_endline "Murder Mystery - Dialogue Prototype";
  choose_suspect []
