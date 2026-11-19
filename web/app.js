const roomMap = document.querySelector("#room-map");
const characterList = document.querySelector("#character-list");
const roomTitle = document.querySelector("#room-title");
const roomDescription = document.querySelector("#room-description");
const interviewContent = document.querySelector("#interview-content");
const evidenceList = document.querySelector("#evidence-list");
const notice = document.querySelector("#notice");

let selectedRoom = "study";
let selectedCharacter = null;

async function getJson(path, params = {}) {
  const query = new URLSearchParams(params);
  const response = await fetch(`${path}?${query}`, { headers: { Accept: "application/json" } });
  if (!response.ok) throw new Error(`Request failed (${response.status})`);
  return response.json();
}

function makeToken(characterId) {
  const token = document.createElement("span");
  token.className = `token token-${characterId}`;
  token.setAttribute("aria-hidden", "true");
  return token;
}

function renderRoomMap(rooms) {
  roomMap.replaceChildren();
  for (let row = 1; row <= 5; row += 1) {
    for (let col = 1; col <= 5; col += 1) {
      const room = rooms.find((item) => item.row === row && item.col === col);
      if (!room) {
        const corridor = document.createElement("div");
        corridor.className = "corridor";
        corridor.setAttribute("aria-hidden", "true");
        roomMap.append(corridor);
        continue;
      }

      const button = document.createElement("button");
      button.type = "button";
      button.className = `room${room.id === selectedRoom ? " selected" : ""}`;
      button.style.gridRow = String(room.row);
      button.style.gridColumn = String(room.col);
      button.setAttribute("aria-pressed", String(room.id === selectedRoom));

      const index = document.createElement("span");
      index.className = "room-index";
      index.textContent = `ROOM ${String(rooms.indexOf(room) + 1).padStart(2, "0")}`;
      const name = document.createElement("strong");
      name.textContent = room.name;
      const hint = document.createElement("span");
      hint.className = "room-hint";
      hint.textContent = "Inspect room";
      button.append(index, name, hint);
      button.addEventListener("click", () => loadState(room.id, selectedCharacter));
      roomMap.append(button);
    }
  }
}

function renderCharacters(characters) {
  characterList.replaceChildren();
  for (const character of characters) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `character-card${character.id === selectedCharacter ? " selected" : ""}`;
    button.setAttribute("aria-pressed", String(character.id === selectedCharacter));
    const label = document.createElement("span");
    const name = document.createElement("strong");
    name.textContent = character.name;
    const role = document.createElement("small");
    role.textContent = "Interview";
    label.append(name, role);
    button.append(makeToken(character.id), label);
    button.addEventListener("click", () => loadState(selectedRoom, character.id));
    characterList.append(button);
  }
}

function renderInterview(character) {
  interviewContent.replaceChildren();
  if (!character) {
    interviewContent.textContent = "Choose one of the six characters to begin an interview.";
    return;
  }

  const heading = document.createElement("div");
  heading.className = "interview-heading";
  const label = document.createElement("div");
  const name = document.createElement("h3");
  name.textContent = character.name;
  const greeting = document.createElement("p");
  greeting.textContent = character.greeting;
  label.append(name, greeting);
  heading.append(makeToken(character.id), label);
  interviewContent.append(heading);

  const title = document.createElement("h4");
  title.textContent = "Ask a question";
  interviewContent.append(title);
  if (character.questions.length === 0) {
    const empty = document.createElement("p");
    empty.className = "muted";
    empty.textContent = "No questions are available right now.";
    interviewContent.append(empty);
    return;
  }

  const questions = document.createElement("div");
  questions.className = "question-list";
  for (const question of character.questions) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "question";
    button.textContent = question.prompt;
    button.addEventListener("click", () => askQuestion(question.id));
    questions.append(button);
  }
  interviewContent.append(questions);
}

function renderEvidence(clues) {
  evidenceList.replaceChildren();
  if (clues.length === 0) {
    evidenceList.className = "muted";
    evidenceList.textContent = "No evidence collected yet.";
    return;
  }
  evidenceList.className = "";
  const list = document.createElement("ul");
  list.className = "clue-list";
  for (const clue of clues) {
    const item = document.createElement("li");
    item.textContent = clue;
    list.append(item);
  }
  evidenceList.append(list);
}

function renderNotice(message) {
  notice.textContent = message || "";
  notice.hidden = !message;
}

function render(state) {
  selectedRoom = state.selectedRoom.id;
  selectedCharacter = state.selectedCharacter?.id ?? null;
  renderRoomMap(state.rooms);
  renderCharacters(state.characters);
  roomTitle.textContent = state.selectedRoom.name;
  roomDescription.textContent = state.selectedRoom.description;
  renderInterview(state.selectedCharacter);
  renderEvidence(state.clues);
  renderNotice(state.notice);
}

async function loadState(room = selectedRoom, character = selectedCharacter) {
  try {
    const params = { room };
    if (character) params.suspect = character;
    render(await getJson("/api/state", params));
  } catch (error) {
    renderNotice(`Could not load the case: ${error.message}`);
  }
}

async function askQuestion(topic) {
  try {
    render(await getJson("/api/ask", {
      room: selectedRoom,
      suspect: selectedCharacter,
      topic,
    }));
  } catch (error) {
    renderNotice(`Could not ask that question: ${error.message}`);
  }
}

loadState();
