/* DOM integration checks against a fresh game server. See test/README.md. */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const { JSDOM } = require("jsdom");

async function main() {
  const root = path.resolve(__dirname, "..");
  const base = process.env.GAME_TEST_URL || "http://127.0.0.1:8080";
  const dom = new JSDOM(fs.readFileSync(path.join(root, "web/index.html"), "utf8"), {
    url: base, runScripts: "outside-only", pretendToBeVisual: true,
  });
  const { window } = dom;
  const document = window.document;
  const errors = [];
  window.addEventListener("error", (event) => errors.push(event.error));
  window.matchMedia = () => ({ matches: true }); // Exercise reduced-motion path.
  window.fetch = (url, options) => fetch(new URL(url, base), options);
  const dialog = document.querySelector("#briefing-dialog");
  // jsdom does not implement the browser's modal presentation/focus trap.
  dialog.showModal = () => dialog.setAttribute("open", "");
  dialog.close = () => dialog.removeAttribute("open");
  const $ = (selector) => {
    const element = document.querySelector(selector);
    assert.ok(element, `Missing element: ${selector}`);
    return element;
  };
  const waitFor = async (predicate, label) => {
    const deadline = Date.now() + 4000;
    while (!predicate() && Date.now() < deadline) await new Promise((resolve) => setTimeout(resolve, 10));
    assert.ok(predicate(), `${label}. Notice: ${$("#notice").textContent}`);
  };
  try {
    window.eval(fs.readFileSync(path.join(root, "web/app.js"), "utf8"));
    await waitFor(() => document.querySelectorAll(".room").length === 9, "Initial case loads");
    assert.equal($("#evidence-count").textContent, "0", "Use a fresh server for this test");
    assert.equal(document.title, "Haunted Murder | The last evening");
    assert.equal($("#view-house").hidden, false);
    assert.equal($("#view-evidence").hidden, true);
    assert.equal($("#view-accusation").hidden, true);
    assert.equal($("#inspector-interview-tab").disabled, true);

    $("#suspect-mustard").click();
    await waitFor(() => !$("#inspector-interview").hidden, "Portrait opens the inspector interview");
    assert.equal($("#inspector-room").hidden, true);
    assert.match($("#suspect-mustard .character-status").textContent, /active/);
    $("#topic-whereabouts").click();
    await waitFor(() => $("#evidence-count").textContent === "1", "Interview records evidence");
    assert.match($(".interview-answer").textContent, /never entered the study/);
    assert.match($("#interview-progress").textContent, /1 of 6/);

    $("#room-study").click();
    await waitFor(() => !$("#inspector-room").hidden, "Room selection replaces the interview in the same inspector");
    assert.match($("#suspect-mustard .character-status").textContent, /Interviewed/);
    $("#object-desk").click();
    await waitFor(() => $("#evidence-count").textContent === "2", "Room inspection records evidence");
    assert.match($("#object-desk").className, /is-inspected/);
    assert.match($("#object-desk").className, /is-recent/);
    $("#inspector-interview-tab").click();
    assert.equal($("#inspector-interview").hidden, false);
    assert.equal($("#topic-cufflink").disabled, false, "Room evidence unlocks the interview contradiction");
    $("#topic-cufflink").click();
    await waitFor(() => $("#evidence-count").textContent === "3", "Unlocked question records a statement");

    $("#tab-evidence").click();
    assert.equal($("#view-house").hidden, true);
    assert.equal($("#view-evidence").hidden, false);
    assert.equal(window.location.hash, "#evidence");
    assert.equal(document.querySelectorAll(".evidence-card").length, 3);
    $("#dossier-journal-tab").click();
    assert.equal($("#dossier-evidence").hidden, true);
    assert.equal($("#dossier-journal").hidden, false);
    assert.equal($("#filter-label").hidden, true);
    assert.equal(document.querySelectorAll(".journal-entry").length, 3);
    $("#dossier-evidence-tab").click();
    $("#evidence-filter").value = "Weapon";
    $("#evidence-filter").dispatchEvent(new window.Event("change"));
    assert.equal(document.querySelectorAll(".evidence-card").length, 0);
    assert.equal($("#evidence-count").textContent, "3", "Filtering never removes collected evidence");

    $("#tab-house").click();
    assert.equal($("#inspector-interview").hidden, false, "Returning to house preserves inspector context");
    $("#room-dining").click();
    await waitFor(() => $("#room-title").textContent === "Dining Room", "Switch to dining room");
    $("#object-candlestick").click();
    await waitFor(() => $("#evidence-count").textContent === "4", "Weapon is collected");
    $("#tab-evidence").click();
    assert.equal($("#evidence-filter").value, "Weapon", "Filter survives navigation and new discoveries");
    assert.equal(document.querySelectorAll(".evidence-card").length, 1);
    assert.match($(".evidence-card h3").textContent, /candlestick/i);

    // Movement: ways out, haunted events on arrival, and refused walks.
    $("#tab-house").click();
    assert.ok($("#exit-hall"), "The dining room lists the hall as a way out");
    assert.match($("#room-dining").className, /selected/, "The plan marks where the player stands");
    $("#exit-hall").click();
    await waitFor(() => $("#room-title").textContent === "Hall", "An exit button walks to the hall");
    assert.equal($("#haunting").hidden, false, "Entering the hall plays the knocking");
    assert.match($("#haunting").textContent, /Knocking in the walls/);
    assert.match($("#movement").textContent, /north corridor/);
    assert.match($("#room-kitchen").className, /is-far/, "The kitchen is not on the hall's corridor");
    assert.equal(document.querySelector("#exit-kitchen"), null, "and is not offered as a way out");
    $("#room-kitchen").click();
    await waitFor(() => /No hallway joins/.test($("#movement").textContent), "A far room explains the way round");
    assert.equal($("#room-title").textContent, "Hall", "A refused walk leaves the player in place");
    assert.equal($("#haunting").hidden, true, "The knocking does not repeat");

    // A delayed interview must not override a newer navigation choice.
    const originalFetch = window.fetch;
    let release;
    const gate = new Promise((resolve) => { release = resolve; });
    window.fetch = async (...args) => { await gate; return originalFetch(...args); };
    $("#suspect-scarlet").click();
    assert.equal($("#view-house").hidden, false);
    $("#tab-evidence").click();
    release();
    await waitFor(() => $("#inspector-interview h3").textContent === "Miss Scarlet", "Delayed interview finishes");
    assert.equal($("#view-evidence").hidden, false, "Latest tab choice wins over an in-flight request");
    window.fetch = originalFetch;

    $("#tab-house").click();
    $("#map-accusation").click();
    assert.equal($("#view-accusation").hidden, false, "Map action opens the accusation view");
    assert.equal($("#tab-accusation").getAttribute("aria-selected"), "true");
    assert.equal(document.activeElement.id, "accused", "Map action focuses the suspect field");
    $("#accused").value = "plum";
    $("#weapon").value = "wrench";
    $("#location").value = "lounge";
    $("#tab-house").click();
    $("#tab-accusation").click();
    assert.equal($("#accused").value, "plum");
    assert.equal($("#weapon").value, "wrench");
    assert.equal($("#location").value, "lounge");
    const submit = () => $("#accusation-form").dispatchEvent(new window.Event("submit", { bubbles: true, cancelable: true }));
    submit();
    await waitFor(() => !$("#accusation-feedback").hidden, "Wrong accusation gets inline feedback");
    assert.match($("#accusation-feedback").textContent, /does not fit/);
    assert.equal($(".accuse-button").disabled, false, "The accusation button remains usable");
    assert.equal($("#evidence-count").textContent, "4");

    $("#tab-house").click();
    $("#tab-house").dispatchEvent(new window.KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true }));
    assert.equal($("#tab-evidence").getAttribute("aria-selected"), "true");
    assert.equal(document.activeElement.id, "tab-evidence", "Arrow keys move tab focus");
    $("#tab-evidence").dispatchEvent(new window.KeyboardEvent("keydown", { key: "End", bubbles: true }));
    assert.equal($("#view-accusation").hidden, false);
    $("#briefing-open").click();
    assert.equal(dialog.hasAttribute("open"), true);
    $("#briefing-close").click();
    assert.equal(dialog.hasAttribute("open"), false);

    $("#accused").value = "mustard";
    $("#weapon").value = "candlestick";
    $("#location").value = "study";
    submit();
    await waitFor(() => !$("#ending").hidden, "Correct accusation displays the ending");
    assert.match($("#ending").textContent, /Colonel Mustard killed/);
    assert.match($(".workspace-footer").textContent, /Case solved/);
    assert.deepEqual(errors, [], "No script errors");
    console.log("Workspace DOM checks passed: tabs, keyboard navigation, contextual inspector, interview badges, clue unlocks, evidence/journal retention, filters, preserved accusation choices, and ending.");
  } finally {
    window.close();
  }
}
main().catch((error) => { console.error(error); process.exitCode = 1; });
