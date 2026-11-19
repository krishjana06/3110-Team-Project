const roomMap = document.querySelector("#room-map");
const characterList = document.querySelector("#character-list");
const roomTitle = document.querySelector("#room-title");
const roomDescription = document.querySelector("#room-description");
const interviewContent = document.querySelector("#interview-content");
const evidenceList = document.querySelector("#evidence-list");
const notice = document.querySelector("#notice");

let selectedRoom = "study";
let selectedCharacter = null;
let currentState = null;
let busy = false;
let pendingFocus = null;
let inspectorMode = "room";
let activeView = "house";
let dossierMode = "evidence";
let lastInspectedObject = null;
let noticeTimer;
const roomObjects = document.querySelector("#room-objects");
const evidenceFilter = document.querySelector("#evidence-filter");

async function getJson(path, params = {}) {
  const query = new URLSearchParams(params);
  const response = await fetch(`${path}?${query}`, { headers: { Accept: "application/json" } });
  if (!response.ok) throw new Error(`Request failed (${response.status})`);
  return response.json();
}

const characterLooks = {
  scarlet: { role: "The art dealer", x: "0%", y: "0%", description: "Finger-wave black hair, ruby earrings, and a scarlet silk evening dress." },
  mustard: { role: "The veteran", x: "50%", y: "0%", description: "Silver hair and moustache, a violet wool jacket, and an ochre waistcoat." },
  white: { role: "The housekeeper", x: "100%", y: "0%", description: "Silver hair, an ivory lace collar, a charcoal dress, and an antique brooch." },
  green: { role: "The businessman", x: "0%", y: "100%", description: "Wavy dark hair, an emerald dinner jacket, and an undone bow tie." },
  peacock: { role: "The benefactor", x: "50%", y: "100%", description: "Auburn curls, a sapphire velvet dress, pearls, and a feather hair ornament." },
  plum: { role: "The scholar", x: "100%", y: "100%", description: "Round brass glasses, a neatly trimmed beard, and a deep plum suit." },
};

const roomViews = {
  study: { x: 6.7, y: 6.6, width: 25.8, height: 23.5 },
  hall: { x: 37, y: 6.6, width: 26, height: 23.5 },
  lounge: { x: 67.7, y: 6.6, width: 25.6, height: 23.5 },
  library: { x: 6.7, y: 38.2, width: 25.8, height: 23.5 },
  billiard: { x: 37, y: 38.2, width: 26, height: 23.5 },
  dining: { x: 67.7, y: 38.2, width: 25.6, height: 23.5 },
  conservatory: { x: 6.7, y: 69.9, width: 25.8, height: 23.5 },
  ballroom: { x: 37, y: 69.9, width: 26, height: 23.5 },
  kitchen: { x: 67.7, y: 69.9, width: 25.6, height: 23.5 },
};

function makeIcon(name = "search") {
  const paths = {
    search: "M10.5 3a7.5 7.5 0 1 0 0 15 7.5 7.5 0 0 0 0-15ZM16 16l5 5",
    lock: "M6 10h12v11H6zM8 10V6a4 4 0 0 1 8 0v4M12 14v3",
    check: "m5 12 4 4L19 6",
    clue: "M4 4h16v16H4zM8 8h8M8 12h5M8 16h7",
    Document: "M6 2h8l5 5v15H6zM14 2v6h5M9 12h7M9 16h7",
    Timeline: "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18ZM12 7v5l4 2",
    Testimony: "M3 4h18v13h-8l-5 4v-4H3zM7 9h10M7 13h6",
    Trace: "M8 4c8-4 15 9 8 17M5 8c-1 4 2 6 1 10M9 8c-3 4 6 6 2 14M13 8c4 3 5 7 2 11M2 12l1 4",
    Discovery: "M8 3a5 5 0 1 0 0 10 5 5 0 0 0 0-10ZM12 12l9 9M17 17l3-3M14 14l3-3M7 6h1",
    candlestick: "M9 2h6v9H9zM12 11v8M6 21h12M8 19h8M12 2V0",
    dagger: "m17 2 4 1-8 13-3-2zM7 13l8 5M10 17l-5 5-2-2 5-5",
    lead_pipe: "M5 20V8a5 5 0 0 1 5-5h9v5h-8a1 1 0 0 0-1 1v11z",
    revolver: "M2 7h17v5H9l-2 9H3l2-10M19 7h3v4h-3M10 12v4h5v-4",
    rope: "M7 19c-8-8-3-17 4-16 12 2 10 15 0 14-9-1-6-11 0-10 8 2 4 13 8 14",
    wrench: "M21 3a6 6 0 0 1-7 8L5 21l-3-3 10-9a6 6 0 0 1 8-7l-5 4 3 3z",
  };
  const icon = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  icon.classList.add("ui-icon");
  icon.setAttribute("viewBox", "0 0 24 24");
  icon.setAttribute("fill", "none");
  icon.setAttribute("stroke", "currentColor");
  icon.setAttribute("stroke-width", "1.4");
  icon.setAttribute("stroke-linecap", "round");
  icon.setAttribute("stroke-linejoin", "round");
  icon.setAttribute("aria-hidden", "true");
  const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
  path.setAttribute("d", paths[name] || paths.clue);
  icon.append(path);
  return icon;
}

function makePortrait(characterId, decorative = true) {
  const look = characterLooks[characterId];
  const portrait = document.createElement("span");
  portrait.className = "portrait";
  portrait.style.setProperty("--portrait-x", look.x);
  portrait.style.setProperty("--portrait-y", look.y);
  if (decorative) portrait.setAttribute("aria-hidden", "true");
  else {
    portrait.setAttribute("role", "img");
    portrait.setAttribute("aria-label", look.description);
  }
  const art = document.createElement("span");
  art.className = "portrait-art";
  portrait.append(art);
  return portrait;
}

function animatePane(pane) {
  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches || !pane.animate) return;
  pane.getAnimations().forEach((animation) => animation.cancel());
  pane.animate([{ opacity: .35, transform: "translateY(6px)" }, { opacity: 1, transform: "translateY(0)" }], {
    duration: 180, easing: "ease-out",
  });
}

function selectWorkspace(view, updateHash = true) {
  if (!["house", "evidence", "accusation"].includes(view)) view = "house";
  const changed = activeView !== view;
  activeView = view;
  document.querySelectorAll("[data-view]").forEach((tab) => {
    const selected = tab.dataset.view === view;
    tab.setAttribute("aria-selected", String(selected));
    tab.tabIndex = selected ? 0 : -1;
  });
  document.querySelectorAll(".workspace-view").forEach((pane) => { pane.hidden = pane.id !== `view-${view}`; });
  if (changed) animatePane(document.querySelector(`#view-${view}`));
  if (updateHash && window.location.hash !== `#${view}`) window.history.replaceState(null, "", `#${view}`);
}

function updateInspector() {
  const interviewTab = document.querySelector("#inspector-interview-tab");
  interviewTab.disabled = !selectedCharacter;
  document.querySelectorAll("[data-inspector]").forEach((tab) => {
    const selected = tab.dataset.inspector === inspectorMode;
    tab.setAttribute("aria-selected", String(selected));
    tab.tabIndex = selected ? 0 : -1;
  });
  document.querySelector("#inspector-room").hidden = inspectorMode !== "room";
  document.querySelector("#inspector-interview").hidden = inspectorMode !== "interview";
}

function selectInspector(mode) {
  const focusId = document.activeElement?.id;
  if (mode === "interview" && !selectedCharacter) return;
  const changed = inspectorMode !== mode;
  inspectorMode = mode;
  updateInspector();
  if (currentState) renderCharacters(currentState.characters);
  if (focusId) document.getElementById(focusId)?.focus({ preventScroll: true });
  if (changed) {
    document.querySelector("#inspector-scroll").scrollTop = 0;
    animatePane(document.querySelector(`#inspector-${mode}`));
  }
}

function selectDossier(mode) {
  dossierMode = mode;
  document.querySelectorAll("[data-dossier]").forEach((tab) => {
    const selected = tab.dataset.dossier === mode;
    tab.setAttribute("aria-selected", String(selected));
    tab.tabIndex = selected ? 0 : -1;
  });
  document.querySelector("#dossier-evidence").hidden = mode !== "evidence";
  document.querySelector("#dossier-journal").hidden = mode !== "journal";
  document.querySelector("#filter-label").hidden = mode !== "evidence";
  animatePane(document.querySelector(`#dossier-${mode}`));
}

function wireTabs(selector, activate, key) {
  const tabs = [...document.querySelectorAll(selector)];
  tabs.forEach((tab) => {
    tab.addEventListener("click", () => activate(tab.dataset[key]));
    tab.addEventListener("keydown", (event) => {
      if (!["ArrowRight", "ArrowLeft", "Home", "End"].includes(event.key)) return;
      event.preventDefault();
      const enabled = tabs.filter((item) => !item.disabled);
      const index = enabled.indexOf(tab);
      const nextIndex = event.key === "Home" ? 0 : event.key === "End" ? enabled.length - 1
        : (index + (event.key === "ArrowRight" ? 1 : -1) + enabled.length) % enabled.length;
      const next = enabled[nextIndex];
      activate(next.dataset[key]);
      next.focus();
    });
  });
}

function renderRoomMap(rooms) {
  roomMap.replaceChildren();
  for (const room of rooms) {
    const view = roomViews[room.id];
    const searched = room.objects.filter((object) => object.inspected).length;
    const button = document.createElement("button");
    button.type = "button";
    button.id = `room-${room.id}`;
    button.className = `room${room.id === selectedRoom ? " selected" : ""}`;
    button.style.left = `${view.x}%`;
    button.style.top = `${view.y}%`;
    button.style.width = `${view.width}%`;
    button.style.height = `${view.height}%`;
    button.setAttribute("aria-pressed", String(room.id === selectedRoom));
    button.setAttribute("aria-label", `${room.name}, ${searched} of ${room.objects.length} objects searched. Enter room.`);
    const label = document.createElement("span");
    label.className = "room-label";
    const name = document.createElement("strong");
    name.textContent = room.name;
    const hint = document.createElement("span");
    hint.className = "room-hint";
    hint.textContent = searched === room.objects.length ? "Search complete" : `${room.objects.length - searched} things to inspect`;
    label.append(name, hint);
    button.append(label);
    button.addEventListener("click", async () => {
      const state = await loadState(room.id, selectedCharacter);
      if (!state) return;
      selectInspector("room");
      document.querySelector("#inspector-scroll").scrollTop = 0;
      animatePane(document.querySelector("#inspector-room"));
    });
    roomMap.append(button);
  }
  const complete = rooms.filter((room) => room.objects.every((object) => object.inspected)).length;
  document.querySelector("#search-progress").textContent = `${complete} of ${rooms.length} rooms searched`;
}

function renderCharacters(characters) {
  characterList.replaceChildren();
  for (const character of characters) {
    const button = document.createElement("button");
    button.type = "button";
    button.id = `suspect-${character.id}`;
    const active = character.id === selectedCharacter && inspectorMode === "interview";
    const interviewed = currentState.history.some((entry) => entry.speaker === character.name);
    button.className = `character-card${active ? " selected" : ""}`;
    button.setAttribute("aria-pressed", String(active));
    button.setAttribute("aria-label", `Interview ${character.name}, ${characterLooks[character.id].role.toLowerCase()}`);
    const label = document.createElement("span");
    label.className = "character-label";
    const name = document.createElement("strong");
    name.textContent = character.name;
    const role = document.createElement("small");
    role.textContent = characterLooks[character.id].role;
    const status = document.createElement("span");
    status.className = "character-status";
    status.textContent = active ? "Interview active" : interviewed ? "Interviewed" : "Not questioned";
    label.append(name, role, status);
    button.append(makePortrait(character.id), label);
    button.addEventListener("click", async () => {
      if (busy) return;
      selectWorkspace("house");
      const state = await loadState(selectedRoom, character.id);
      if (!state) return;
      selectInspector("interview");
      document.querySelector("#inspector-scroll").scrollTop = 0;
      animatePane(document.querySelector("#inspector-interview"));
    });
    characterList.append(button);
  }
}

function renderInterview(character) {
  interviewContent.replaceChildren();
  if (!character) {
    const empty = document.createElement("div");
    empty.className = "empty-interview";
    const copy = document.createElement("div");
    const title = document.createElement("strong");
    title.textContent = "Choose a suspect to start an interview.";
    const text = document.createElement("p");
    text.textContent = "Ask about their account, then return with evidence to ask follow-up questions.";
    copy.append(title, text);
    empty.append(makeIcon("Testimony"), copy);
    interviewContent.append(empty);
    return;
  }

  const heading = document.createElement("div");
  heading.className = "interview-heading";
  const label = document.createElement("div");
  const name = document.createElement("h3");
  name.textContent = character.name;
  const greeting = document.createElement("p");
  greeting.textContent = character.greeting;
  const role = document.createElement("p");
  role.className = "character-role";
  role.textContent = characterLooks[character.id].role;
  greeting.className = "greeting";
  label.append(role, name);
  heading.append(makePortrait(character.id, false), label, greeting);
  interviewContent.append(heading);

  const previousAnswer = [...currentState.history].reverse().find((entry) => entry.speaker === character.name);
  if (previousAnswer) {
    const answer = document.createElement("blockquote");
    answer.className = "interview-answer";
    answer.setAttribute("aria-live", "polite");
    const prompt = document.createElement("strong");
    prompt.textContent = previousAnswer.prompt;
    const text = document.createElement("p");
    text.textContent = previousAnswer.text;
    answer.append(prompt, text);
    interviewContent.append(answer);
  }

  const title = document.createElement("h4");
  title.textContent = "Ask a question";
  interviewContent.append(title);
  if (character.questions.length === 0) {
    const empty = document.createElement("p");
    empty.className = "muted";
    empty.textContent = "You have asked every question currently available. Search for more evidence to unlock follow-up questions.";
    interviewContent.append(empty);
    return;
  }

  const questions = document.createElement("div");
  questions.className = "question-list";
  for (const question of character.questions) {
    const button = document.createElement("button");
    button.type = "button";
    button.id = `topic-${question.id}`;
    button.className = "question";
    button.textContent = question.prompt;
    button.addEventListener("click", () => askQuestion(question.id));
    questions.append(button);
  }
  interviewContent.append(questions);
}

function renderObjects(room) {
  roomObjects.replaceChildren();
  for (const object of room.objects) {
    const button = document.createElement("button");
    button.type = "button";
    button.id = `object-${object.id}`;
    button.className = `question object-button${object.inspected ? " is-inspected" : ""}${object.id === lastInspectedObject && currentState.newEvidence.length ? " is-recent" : ""}`;
    button.disabled = object.locked;
    button.dataset.locked = String(object.locked);
    const label = document.createElement("span");
    label.textContent = object.name;
    const status = document.createElement("small");
    status.textContent = object.locked ? "Locked · investigate the hall" : object.inspected ? "Review" : "Inspect";
    button.append(makeIcon(object.locked ? "lock" : object.inspected ? "check" : "search"), label, status);
    button.addEventListener("click", () => inspectObject(object.id));
    roomObjects.append(button);
  }
}

function renderEvidence(evidence, newEvidence = []) {
  evidenceList.replaceChildren();
  evidenceList.className = "evidence-grid";
  document.querySelector("#evidence-count").textContent = String(evidence.length);
  document.querySelector("#accusation-evidence-count").textContent = String(evidence.length);
  const visible = evidence.filter((clue) => evidenceFilter.value === "all" || clue.kind === evidenceFilter.value);
  if (!visible.length) {
    const empty = document.createElement("div");
    empty.className = "empty-evidence";
    const text = document.createElement("p");
    text.textContent = evidence.length ? "No evidence of this type collected." : "No evidence collected. Search a room or interview a suspect to begin.";
    empty.append(makeIcon("clue"), text);
    evidenceList.append(empty);
    return;
  }
  for (const clue of visible) {
    const card = document.createElement("article");
    card.className = `evidence-card${newEvidence.includes(clue.id) ? " is-new" : ""}`;
    const meta = document.createElement("div");
    meta.className = "evidence-meta";
    meta.append(makeIcon(clue.kind === "Weapon" ? clue.id : clue.kind), document.createTextNode(clue.kind));
    if (newEvidence.includes(clue.id)) {
      const badge = document.createElement("span");
      badge.textContent = "New";
      meta.append(badge);
    }
    const title = document.createElement("h3");
    title.textContent = clue.title;
    const description = document.createElement("p");
    description.textContent = clue.description;
    const source = document.createElement("p");
    source.className = "evidence-source";
    source.textContent = clue.source;
    card.append(meta, title, description, source);
    evidenceList.append(card);
  }
}

function renderJournal(history) {
  const list = document.querySelector("#journal-list");
  list.replaceChildren();
  document.querySelector("#journal-count").textContent = String(history.length);
  if (!history.length) {
    const empty = document.createElement("p");
    empty.className = "journal-empty";
    empty.textContent = "No entries yet. Search a room or interview a suspect to begin.";
    list.append(empty);
  }
  for (const entry of [...history].reverse()) {
    const item = document.createElement("article");
    item.className = "journal-entry";
    const title = document.createElement("h3");
    title.textContent = `${entry.speaker} · ${entry.prompt}`;
    const text = document.createElement("p");
    text.textContent = entry.text;
    item.append(title, text);
    list.append(item);
  }
}

function fillSelect(id, items) {
  const select = document.querySelector(`#${id}`);
  if (select.options.length > 1) return;
  for (const item of items) {
    const option = document.createElement("option");
    option.value = item.id;
    option.textContent = item.name;
    select.append(option);
  }
}

function renderNotice(message) {
  clearTimeout(noticeTimer);
  notice.textContent = message || "";
  notice.hidden = !message;
  if (message) noticeTimer = setTimeout(() => { notice.hidden = true; }, 6500);
}

function setBusy(value) {
  busy = value;
  document.querySelector("#inspector").setAttribute("aria-busy", String(value));
  document.querySelectorAll(".room, .character-card, .question").forEach((button) => {
    button.disabled = value || button.dataset.locked === "true";
  });
}

function render(state) {
  const focusId = pendingFocus || document.activeElement?.id;
  pendingFocus = null;
  currentState = state;
  document.querySelector("#story-title").textContent = state.story.title;
  document.querySelector("#story-intro").textContent = state.story.intro;
  document.querySelector("#story-objective").textContent = state.story.objective;
  selectedRoom = state.selectedRoom.id;
  selectedCharacter = state.selectedCharacter?.id ?? null;
  renderRoomMap(state.rooms);
  renderCharacters(state.characters);
  roomTitle.textContent = state.selectedRoom.name;
  roomDescription.textContent = state.selectedRoom.description;
  document.querySelector("#map-current-room").textContent = state.selectedRoom.name;
  const searched = state.selectedRoom.objects.filter((object) => object.inspected).length;
  document.querySelector("#room-search-count").textContent = `${searched} / ${state.selectedRoom.objects.length} searched`;
  const interviewed = state.characters.filter((character) => state.history.some((entry) => entry.speaker === character.name)).length;
  document.querySelector("#interview-progress").textContent = `${interviewed} of ${state.characters.length} interviewed`;
  renderInterview(state.selectedCharacter);
  renderObjects(state.selectedRoom);
  renderEvidence(state.evidence, state.newEvidence);
  renderJournal(state.history);
  fillSelect("accused", state.characters);
  fillSelect("weapon", state.weapons);
  fillSelect("location", state.rooms);
  const ending = document.querySelector("#ending");
  ending.hidden = !state.ending;
  ending.textContent = state.ending || "";
  document.querySelector(".workspace-footer > span:first-child").textContent = state.ending ? "Case solved" : "Investigation in progress";
  updateInspector();
  setBusy(busy);
  const focusTarget = focusId && document.getElementById(focusId);
  if (focusTarget && !focusTarget.disabled) focusTarget.focus({ preventScroll: true });
  else if (focusId?.startsWith("topic-")) document.querySelector("#interview-title").focus({ preventScroll: true });
  const newTitles = state.evidence.filter((clue) => state.newEvidence.includes(clue.id)).map((clue) => clue.title);
  renderNotice(newTitles.length ? `Recorded in evidence: ${newTitles.join(", ")}` : "");
}

async function requestState(path, params, onSuccess) {
  if (busy) return null;
  pendingFocus = document.activeElement?.id;
  setBusy(true);
  try {
    const state = await getJson(path, params);
    setBusy(false);
    render(state);
    if (onSuccess) onSuccess(state);
    return state;
  } catch (error) {
    setBusy(false);
    if (currentState) render(currentState);
    renderNotice(`Could not update the case: ${error.message}`);
    return null;
  } finally {
    setBusy(false);
  }
}

function loadState(room = selectedRoom, character = selectedCharacter) {
  const params = { room };
  if (character) params.suspect = character;
  return requestState("/api/state", params, () => {
    document.querySelector("#discovery").hidden = true;
  });
}

function askQuestion(topic) {
  return requestState("/api/ask", { room: selectedRoom, suspect: selectedCharacter, topic });
}

function inspectObject(object) {
  if (busy) return;
  lastInspectedObject = object;
  return requestState("/api/inspect", {
    room: selectedRoom, suspect: selectedCharacter || "", object,
  }, (state) => {
    const discovery = document.querySelector("#discovery");
    discovery.textContent = `${state.newEvidence.length ? "Added to evidence collection. " : "Recorded earlier. "}${state.notice}`;
    discovery.hidden = false;
  });
}

evidenceFilter.addEventListener("change", () => {
  if (currentState) renderEvidence(currentState.evidence, currentState.newEvidence);
});

document.querySelector("#accusation-form").addEventListener("submit", (event) => {
  event.preventDefault();
  requestState("/api/accuse", {
    room: selectedRoom, suspect: selectedCharacter || "",
    accused: document.querySelector("#accused").value,
    weapon: document.querySelector("#weapon").value,
    location: document.querySelector("#location").value,
  }, (state) => {
    const feedback = document.querySelector("#accusation-feedback");
    feedback.textContent = state.notice;
    feedback.hidden = false;
  });
});

wireTabs("[data-view]", selectWorkspace, "view");
wireTabs("[data-inspector]", selectInspector, "inspector");
wireTabs("[data-dossier]", selectDossier, "dossier");
document.querySelector("#map-accusation").addEventListener("click", () => {
  selectWorkspace("accusation");
  document.querySelector("#accused").focus({ preventScroll: true });
});
document.querySelector("#review-evidence").addEventListener("click", () => {
  selectWorkspace("evidence");
  selectDossier("evidence");
  document.querySelector("#dossier-evidence-tab").focus();
});
const briefing = document.querySelector("#briefing-dialog");
document.querySelector("#briefing-open").addEventListener("click", () => briefing.showModal());
document.querySelector("#briefing-close").addEventListener("click", () => briefing.close());
briefing.addEventListener("click", (event) => {
  if (event.target !== briefing) return;
  const bounds = briefing.getBoundingClientRect();
  if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) briefing.close();
});
window.addEventListener("hashchange", () => selectWorkspace(window.location.hash.slice(1), false));
selectWorkspace(window.location.hash.slice(1) || "house", false);
loadState();
