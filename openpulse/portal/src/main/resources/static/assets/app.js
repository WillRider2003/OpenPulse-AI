"use strict";

const $ = (id) => document.getElementById(id);
const views = {inicio:"Resumen", voz:"Telefonía", talk:"Chat y video", nube:"Nube privada", asistente:"Asistente IA", operacion:"Operación y SLA"};
const state = {config:null, view:"inicio", folder:"", presence:{}, turns:[], room:null, savedPath:null, epoch:0, busy:false};
const statusRows = [
  ["nextcloud", "Nube privada", "Nextcloud · instalación y mantenimiento", "cloud"],
  ["sip", "Telefonía IP", "Asterisk · acceso al puerto SIP-TLS", "phone"],
  ["local", "IA local", "Ollama · modelo descargado", "spark"],
  ["whisper", "Transcripción", "Whisper · disponibilidad del motor", "mic"]
];
const presenceLabels = {online:["Disponible","ok"], away:["Ausente","away"], dnd:["No molestar","dnd"], offline:["Desconectado",""]};
let toastTimer;
let pollTimer;
let pendingLogin;

function make(tag, className, text) {
  const element = document.createElement(tag);
  if (className) element.className = className;
  if (text !== undefined) element.textContent = text;
  return element;
}

function icon(name) {
  const element = make("i");
  element.dataset.icon = name;
  paintIcon(element);
  return element;
}

function paintIcon(element) {
  const ns = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(ns, "svg");
  const use = document.createElementNS(ns, "use");
  svg.setAttribute("aria-hidden", "true");
  use.setAttribute("href", "/assets/icons.svg#" + element.dataset.icon);
  svg.append(use);
  element.setAttribute("aria-hidden", "true");
  element.replaceChildren(svg);
}

function button(label, iconName, action) {
  const result = make("button", "button");
  result.type = "button";
  if (iconName) result.append(icon(iconName));
  result.append(document.createTextNode(label));
  result.addEventListener("click", action);
  return result;
}

function link(label, href, iconName, external = false) {
  const result = make("a", "button");
  result.href = href;
  if (external) {
    result.target = "_blank";
    result.rel = "noopener";
  }
  if (iconName) result.append(icon(iconName));
  result.append(document.createTextNode(label));
  return result;
}

function rowText(title, description) {
  const result = make("div", "row-text");
  result.append(make("strong", "", title));
  if (description) result.append(make("small", "", description));
  return result;
}

function signal(label, type = "") {
  return make("span", "signal " + type, label);
}

function message(target, text, action, error = false) {
  const status = make("p", error ? "state error" : "state", text);
  if (action) status.append(action);
  target.replaceChildren(status);
}

function notify(text) {
  clearTimeout(toastTimer);
  $("toast").textContent = text;
  $("toast").hidden = false;
  toastTimer = setTimeout(() => $("toast").hidden = true, 6000);
}

async function request(path, options = {}) {
  const {method = "GET", body, raw = false} = options;
  const headers = {Accept:"application/json"};
  let payload = body;
  if (method !== "GET") headers["X-OpenPulse"] = "1";
  if (body && !(body instanceof FormData)) {
    headers["Content-Type"] = "application/json";
    payload = JSON.stringify(body);
  }
  let result;
  try {
    result = await fetch("/api" + path, {method, headers, body:payload, cache:"no-store"});
  } catch {
    throw new Error("No hay conexión con el portal. Vuelve a intentar.");
  }
  if (!result.ok && !(raw && result.status === 410)) {
    const data = await result.json().catch(() => ({}));
    const error = new Error(data.message || "No se pudo completar la operación.");
    error.status = result.status;
    throw error;
  }
  if (raw) return result;
  return result.status === 204 || result.status === 201 ? null : result.json();
}

function signedIn() {
  if (state.config?.user) return true;
  showSession();
  return false;
}

async function config() {
  state.config = await request("/config");
  $("session-button").querySelector("span").textContent = state.config.user?.name || "Conectar cuenta";
  document.querySelectorAll("[data-link]").forEach((item) => { item.href = state.config[item.dataset.link]; });
  $("sip-host").textContent = state.config.sipHost;
  $("echo").href = state.config.echo;
  $("echo").removeAttribute("aria-disabled");
  $("engine").querySelector('[value="gemini"]').disabled = !state.config.gemini;
  if (!state.config.gemini) $("engine").value = "local";
  showEngine();
  renderTeam();
}

function showSession() {
  const active = Boolean(state.config?.user);
  $("session-title").textContent = active ? state.config.user.name : "Conecta tu cuenta";
  $("session-note").textContent = active ? "Tu sesión de Nextcloud está conectada al portal."
    : "Autoriza el portal en Nextcloud para usar tus archivos, salas y el asistente.";
  $("start-session").hidden = active || Boolean(pendingLogin);
  $("authorize-session").hidden = active || !pendingLogin;
  $("logout").hidden = !active;
  if (pendingLogin && !active) {
    $("session-note").textContent = "Autoriza OpenPulse en la otra pestaña. La sesión se actualizará aquí.";
  }
  if (!$("session-dialog").open) $("session-dialog").showModal();
}

async function beginSession() {
  const control = $("start-session");
  control.disabled = true;
  try {
    pendingLogin = await request("/session/start", {method:"POST"});
    $("authorize-session").href = pendingLogin.url;
    showSession();
    $("authorize-session").focus();
    schedulePoll();
  } catch (error) {
    $("session-note").textContent = error.message;
  } finally {
    control.disabled = false;
  }
}

function schedulePoll() {
  clearTimeout(pollTimer);
  pollTimer = setTimeout(pollSession, 3500);
}

async function pollSession() {
  if (!pendingLogin) return;
  try {
    const response = await request("/session/poll", {method:"POST", raw:true});
    if (response.status === 202 && Date.now() < Date.parse(pendingLogin.expires)) {
      schedulePoll();
      return;
    }
    pendingLogin = null;
    if (response.status === 204) {
      await config();
      $("session-dialog").close();
      updateView();
      notify("Cuenta de Nextcloud conectada.");
    } else if ($("session-dialog").open) {
      showSession();
      $("session-note").textContent = "La autorización expiró. Prepara una nueva conexión.";
    }
  } catch (error) {
    pendingLogin = null;
    if ($("session-dialog").open) {
      showSession();
      $("session-note").textContent = error.message;
    } else {
      notify(error.message);
    }
  }
}

async function logout() {
  const control = $("logout");
  control.disabled = true;
  try {
    await request("/session", {method:"DELETE"});
    state.epoch++;
    state.folder = "";
    state.presence = {};
    state.room = null;
    state.savedPath = null;
    $("talk-thread").hidden = true;
    $("thread-message").value = "";
    $("thread-log").replaceChildren();
    $("share-acta").hidden = true;
    resetChat();
    $("notes").value = "";
    $("audio-note").textContent = "Hasta 24 MB";
    $("acta-text").value = "";
    $("acta-name").value = "";
    $("acta-panel").hidden = true;
    $("consent").checked = false;
    $("session-dialog").close();
    await config();
    updateView();
    notify("Sesión del portal cerrada.");
  } catch (error) {
    $("session-note").textContent = error.message;
  } finally {
    control.disabled = false;
  }
}

function renderTeam() {
  if (!state.config) return;
  for (const [mode, target] of [["home","home-team"],["voice","voice-team"],["talk","talk-team"]]) {
    $(target).replaceChildren(...state.config.team.map((person, index) => {
      const row = make("div", "row");
      const presence = presenceLabels[state.presence[person.extension]];
      row.append(make("span", "avatar tone-" + index, person.initials),
        rowText(person.name + (person.self ? " · Tú" : ""), person.role));
      if (mode !== "talk") row.append(make("span", "extension", person.extension));
      if (mode !== "home") row.append(signal(presence?.[0] || "Sin estado", presence?.[1]));
      const actions = make("div", "contact-actions");
      if (mode === "home") {
        const dial = link("Llamar", person.dial, "phone");
        dial.setAttribute("aria-label", "Llamar a " + person.name + " en Linphone");
        if (!person.self) actions.append(dial);
      } else if (mode === "voice") {
        const dial = link("Llamar", person.dial, "phone");
        dial.setAttribute("aria-label", "Llamar a " + person.name + " en Linphone");
        if (!person.self) actions.append(dial);
        const copy = button("Copiar SIP", "copy", () => copySip(person.address));
        copy.setAttribute("aria-label", "Copiar dirección SIP de " + person.name);
        actions.append(copy);
      }
      if (mode !== "home" && !person.self) {
        const chat = button("Chat", "message", () => startChat(person, chat));
        chat.setAttribute("aria-label", "Abrir chat con " + person.name);
        actions.append(chat);
      }
      if (actions.childElementCount) row.append(actions);
      return row;
    }));
  }
}

async function copySip(address) {
  try {
    await navigator.clipboard.writeText(address);
    notify("Dirección SIP copiada.");
  } catch {
    notify(address);
  }
}

async function startChat(person, control) {
  if (!signedIn()) return;
  control.disabled = true;
  try {
    const room = await request("/talk/direct/" + person.extension, {method:"POST"});
    if (state.view !== "talk") location.hash = "talk";
    openThread(room);
    if (state.view === "talk") rooms();
  } catch (error) {
    notify(error.message);
  } finally {
    control.disabled = false;
  }
}

async function presence() {
  const epoch = state.epoch;
  if (!state.config?.user) return;
  try {
    const data = await request("/presence");
    if (epoch !== state.epoch) return;
    state.presence = data;
  } catch {
    if (epoch !== state.epoch) return;
    state.presence = {};
  }
  renderTeam();
}

async function refreshStatus() {
  const hosts = [$("home-status"), $("ops-status")];
  hosts.forEach((host) => message(host, "Consultando servicios…"));
  try {
    const states = await request("/status");
    for (const host of hosts) {
      host.replaceChildren(...statusRows.map(([key, title, detail, iconName]) => {
        const row = make("div", "row");
        const tile = make("span", "tile " + (key === "local" || key === "whisper" ? "amber" : "teal"));
        tile.append(icon(iconName));
        row.append(tile, rowText(title, detail), signal(states[key] ? "Disponible" : "Sin respuesta", states[key] ? "ok" : ""));
        return row;
      }));
    }
  } catch {
    hosts.forEach((host) => message(host, "No se pudieron consultar los servicios.", button("Reintentar", "refresh", refreshStatus), true));
  }
}

async function rooms() {
  const target = $("room-list");
  const epoch = state.epoch;
  if (!state.config?.user) {
    message(target, "Conecta tu cuenta para ver tus conversaciones.", button("Conectar", "login", showSession));
    return;
  }
  message(target, "Consultando conversaciones…");
  try {
    const list = await request("/talk/rooms");
    if (epoch !== state.epoch) return;
    if (!list.length) {
      message(target, "Todavía no tienes conversaciones. Abre Talk o elige a alguien del directorio.");
      return;
    }
    target.replaceChildren(...list.map((room) => {
      const row = make("div", "row");
      row.append(icon("message"), rowText(room.name));
      if (room.unread > 0) row.append(make("span", "pill", room.unread + " sin leer"));
      row.append(button("Leer chat", "message", () => openThread(room)));
      return row;
    }));
  } catch (error) {
    if (epoch === state.epoch) message(target, error.message, button("Actualizar", "refresh", rooms), true);
  }
}

function openThread(room) {
  state.room = room;
  $("thread-title").textContent = room.name;
  $("thread-video").href = room.url;
  $("talk-thread").hidden = false;
  $("thread-message").value = "";
  $("thread-log").replaceChildren();
  loadThread(true);
}

async function loadThread(focus = false) {
  const room = state.room;
  if (!room || !state.config?.user) return;
  const log = $("thread-log");
  const epoch = state.epoch;
  if (!log.childElementCount) message(log, "Consultando mensajes…");
  try {
    const messages = await request("/talk/rooms/" + encodeURIComponent(room.token) + "/messages");
    if (state.room !== room || state.epoch !== epoch) return;
    log.replaceChildren();
    if (!messages.length) message(log, "Esta conversación aún no tiene mensajes.");
    const format = new Intl.DateTimeFormat("es-PE", {dateStyle:"short", timeStyle:"short"});
    for (const item of messages) {
      const row = make("div", "bubble" + (item.own ? " user" : ""));
      const who = item.own ? "Tú" : item.author;
      row.append(make("small", "", who + (item.timestamp ? " · " + format.format(new Date(item.timestamp * 1000)) : "")),
        document.createTextNode(item.text));
      log.append(row);
    }
    log.scrollTop = log.scrollHeight;
    if (focus && state.view === "talk") $("thread-message").focus({preventScroll:true});
  } catch (error) {
    if (state.room === room && state.epoch === epoch) message(log, error.message, null, true);
  }
}

async function sendToRoom(event) {
  event.preventDefault();
  if (!state.room || !signedIn()) return;
  const room = state.room;
  const field = $("thread-message");
  const text = field.value.trim();
  if (!text) return;
  $("thread-send").disabled = true;
  try {
    await request("/talk/rooms/" + encodeURIComponent(room.token) + "/messages", {method:"POST", body:{text}});
    if (state.room === room) {
      if (field.value.trim() === text) field.value = "";
      await loadThread();
    }
  } catch (error) {
    notify(error.message);
  } finally {
    $("thread-send").disabled = false;
  }
}

function size(bytes) {
  if (bytes < 1024) return bytes + " B";
  const units = bytes < 1048576 ? ["KB", 1024] : ["MB", 1048576];
  return new Intl.NumberFormat("es-PE", {maximumFractionDigits:1}).format(bytes / units[1]) + " " + units[0];
}

async function files(folder = state.folder) {
  const target = $("file-list");
  const epoch = state.epoch;
  state.folder = folder;
  $("cloud-path").textContent = folder ? "Mi unidad / " + folder : "Mi unidad";
  $("save-location").textContent = "Destino en Nextcloud: Mi unidad" + (folder ? " / " + folder : "");
  $("upload-button").disabled = !state.config?.user;
  if (!state.config?.user) {
    message(target, "Conecta tu cuenta para acceder a tu nube privada.", button("Conectar", "login", showSession));
    return;
  }
  message(target, "Consultando archivos…");
  try {
    const list = await request("/cloud?path=" + encodeURIComponent(folder));
    if (epoch !== state.epoch || folder !== state.folder) return;
    target.replaceChildren();
    if (folder) {
      const previous = make("div", "row");
      previous.append(button("Volver", "folder", () => files(folder.split("/").slice(0,-1).join("/"))));
      target.append(previous);
    }
    if (!list.length) target.append(make("p", "state", "La carpeta está vacía."));
    for (const file of list) {
      const row = make("div", "row");
      const detail = file.folder ? "Carpeta" : size(file.size)
        + (file.modified ? " · " + new Intl.DateTimeFormat("es-PE", {dateStyle:"medium"}).format(new Date(file.modified)) : "");
      row.append(icon(file.folder ? "folder" : "file"));
      if (file.folder) {
        const label = make("div", "row-text");
        const open = make("button", "file-link", file.name);
        open.type = "button";
        open.addEventListener("click", () => files(file.path));
        label.append(open, make("small", "", detail));
        row.append(label);
      } else {
        row.append(rowText(file.name, detail));
        if (file.officeId) row.append(button("Editar en Office", "external", () => openOffice(file.officeId)));
        else if (file.openUrl) row.append(link("Abrir", file.openUrl, "external", true));
        row.append(link("Descargar", "/api/cloud/download?path=" + encodeURIComponent(file.path), "download"));
      }
      target.append(row);
    }
  } catch (error) {
    if (epoch === state.epoch && folder === state.folder) {
      message(target, error.message, button("Volver a Mi unidad", "folder", () => files("")), true);
    }
  }
}

async function openOffice(fileId) {
  if (!signedIn()) return;
  const tab = window.open("about:blank", "_blank");
  if (tab) tab.opener = null;
  try {
    const data = await request("/cloud/office/" + encodeURIComponent(fileId), {method:"POST"});
    if (tab) tab.location.replace(data.url);
    else location.assign(data.url);
  } catch (error) {
    tab?.close();
    notify(error.message);
  }
}

async function uploadFile(file) {
  if (!file || !signedIn()) return;
  if (file.size > 24 * 1024 * 1024) {
    notify("El límite por archivo es 24 MB.");
    return;
  }
  const folder = state.folder;
  const form = new FormData();
  form.append("file", file);
  form.append("folder", folder);
  $("upload-button").disabled = true;
  try {
    await request("/cloud/upload", {method:"POST", body:form});
    notify("Archivo guardado en Nextcloud.");
    if (folder === state.folder) await files();
  } catch (error) {
    notify(error.message);
  } finally {
    $("upload-button").disabled = !state.config?.user;
  }
}

function showEngine() {
  const isGemini = $("engine").value === "gemini";
  $("engine-label").textContent = isGemini ? "Procesamiento externo con Gemini" : "Procesamiento local con Ollama";
  $("consent-label").hidden = !isGemini;
  $("consent").checked = false;
}

function resetChat() {
  state.turns = [];
  $("prompt").value = "";
  $("chat-log").querySelectorAll(".bubble").forEach((item) => item.remove());
  $("chat-log").querySelector(".chat-welcome").hidden = false;
}

function bubble(turn, label) {
  const row = make("div", "bubble " + turn.role);
  row.append(make("small", "", label), document.createTextNode(turn.text));
  $("chat-log").querySelector(".chat-welcome").hidden = true;
  $("chat-log").append(row);
  $("chat-log").scrollTop = $("chat-log").scrollHeight;
  return row;
}

async function generate(turns) {
  const engine = $("engine").value;
  const externalConsent = $("consent").checked;
  $("consent").checked = false;
  state.busy = true;
  for (const id of ["send","clear-chat","draft","engine"]) $(id).disabled = true;
  try {
    return await request("/assistant/reply", {method:"POST", body:{engine, turns, externalConsent}});
  } finally {
    state.busy = false;
    for (const id of ["send","clear-chat","draft","engine"]) $(id).disabled = false;
  }
}

function readyForGeneration() {
  if (state.busy || !signedIn()) return false;
  if ($("engine").value === "gemini" && !$("consent").checked) {
    $("consent").focus();
    notify("Confirma el envío del texto a Gemini.");
    return false;
  }
  return true;
}

async function sendChat(event) {
  event.preventDefault();
  const text = $("prompt").value.trim();
  if (!text || !readyForGeneration()) return;
  const epoch = state.epoch;
  const turn = {role:"user", text};
  const provisional = bubble(turn, "Tú");
  $("prompt").value = "";
  const history = state.turns.slice(-10);
  while (history.length && history.reduce((total, item) => total + item.text.length, text.length) > 30000) history.splice(0, 2);
  const progress = bubble({role:"assistant", text:"Generando respuesta…"}, "OpenPulse");
  try {
    const reply = await generate([...history, turn]);
    if (epoch !== state.epoch) return;
    const answer = {role:"assistant", text:reply.text};
    progress.remove();
    state.turns = [...history, turn, answer].slice(-10);
    bubble(answer, reply.engine + " · " + reply.model);
  } catch (error) {
    if (epoch !== state.epoch) return;
    progress.remove();
    provisional.remove();
    if (!state.turns.length) $("chat-log").querySelector(".chat-welcome").hidden = false;
    $("prompt").value = text;
    notify(error.message);
  }
}

async function transcribe(file) {
  if (!file || !signedIn()) return;
  if (file.size > 24 * 1024 * 1024) {
    notify("El límite por grabación es 24 MB.");
    return;
  }
  const form = new FormData();
  const epoch = state.epoch;
  form.append("file", file);
  $("audio-note").textContent = "Transcribiendo " + file.name + "…";
  $("audio-button").disabled = true;
  try {
    const transcript = await request("/assistant/transcribe", {method:"POST", body:form});
    if (epoch !== state.epoch) return;
    $("notes").value = transcript.text;
    $("audio-note").textContent = "Grabación transcrita con Whisper. Revisa el texto y genera el acta.";
  } catch (error) {
    if (epoch !== state.epoch) return;
    $("audio-note").textContent = "Hasta 24 MB";
    notify(error.message);
  } finally {
    $("audio-button").disabled = false;
  }
}

async function draft() {
  const notes = $("notes").value.trim();
  if (!notes) {
    $("notes").focus();
    notify("Agrega notas o transcribe una grabación.");
    return;
  }
  if (!readyForGeneration()) return;
  const epoch = state.epoch;
  $("draft").lastChild.textContent = "Generando…";
  try {
    const prompt = "Redacta un acta en Markdown según las notas que siguen. Incluye título, temas, acuerdos y próximos pasos.\n\n" + notes;
    const reply = await generate([{role:"user", text:prompt}]);
    if (epoch !== state.epoch) return;
    $("acta-text").value = reply.text;
    const stamp = new Intl.DateTimeFormat("sv-SE", {dateStyle:"short", timeStyle:"medium", timeZone:"America/Lima"}).format(new Date());
    $("acta-name").value = "Acta-OpenPulse-" + stamp.replaceAll(":", "").replace(" ", "-") + ".md";
    $("open-saved").hidden = true;
    $("share-acta").hidden = true;
    state.savedPath = null;
    $("acta-panel").hidden = false;
    $("acta-text").focus();
  } catch (error) {
    if (epoch === state.epoch) notify(error.message);
  } finally {
    $("draft").lastChild.textContent = "Generar borrador";
  }
}

async function saveActa(event) {
  event.preventDefault();
  if (!signedIn()) return;
  const folder = state.folder;
  const filename = $("acta-name").value.trim();
  const text = $("acta-text").value.trim();
  const control = $("save-acta");
  const epoch = state.epoch;
  control.disabled = true;
  try {
    await request("/assistant/save", {method:"POST", body:{filename, text, folder}});
    if (epoch !== state.epoch) return;
    $("open-saved").href = "#nube";
    $("open-saved").hidden = false;
    state.savedPath = folder ? folder + "/" + filename : filename;
    notify("Acta guardada en Nextcloud.");
    fillShareRooms(state.savedPath, epoch);
  } catch (error) {
    if (epoch === state.epoch) notify(error.message);
  } finally {
    control.disabled = false;
  }
}

async function fillShareRooms(path, epoch) {
  try {
    const list = await request("/talk/rooms");
    if (state.epoch !== epoch || state.savedPath !== path || !list.length) return;
    const blank = new Option("Elige una sala", "", true, true);
    blank.disabled = true;
    $("share-room").replaceChildren(blank, ...list.map((room) => new Option(room.name, room.token)));
    $("share-acta").hidden = false;
  } catch {
    $("share-acta").hidden = true;
  }
}

async function shareActa(event) {
  event.preventDefault();
  if (!state.savedPath || !signedIn()) return;
  const token = $("share-room").value;
  if (!token) return;
  $("share-button").disabled = true;
  try {
    await request("/talk/share", {method:"POST", body:{token, path:state.savedPath}});
    notify("Acta compartida en la sala de Talk.");
    $("share-room").selectedIndex = 0;
  } catch (error) {
    notify(error.message);
  } finally {
    $("share-button").disabled = false;
  }
}

function toggleMenu(open) {
  document.body.classList.toggle("nav-open", open);
  $("menu").setAttribute("aria-expanded", String(open));
  $("scrim").hidden = !open;
  if (open) document.querySelector(".nav [aria-current]").focus();
}

function updateView() {
  if (state.view === "nube") files();
  if (state.view === "talk") { rooms(); loadThread(); }
  if (["voz","talk"].includes(state.view)) presence();
}

function navigate(moveFocus = false) {
  const wanted = location.hash.slice(1);
  if (wanted === "main") return;
  const view = Object.hasOwn(views, wanted) ? wanted : "inicio";
  const changed = state.view !== view;
  state.view = view;
  for (const key of Object.keys(views)) $("view-" + key).hidden = key !== view;
  document.querySelectorAll("[data-view]").forEach((item) => {
    if (item.dataset.view === view) item.setAttribute("aria-current", "page");
    else item.removeAttribute("aria-current");
  });
  $("crumb").textContent = views[view];
  document.title = views[view] + " · OpenPulse AI";
  toggleMenu(false);
  if (changed) {
    window.scrollTo(0, 0);
    if (moveFocus) $("main").focus({preventScroll:true});
  }
  updateView();
}

document.querySelectorAll("[data-icon]").forEach(paintIcon);
document.querySelectorAll(".status-refresh").forEach((item) => item.addEventListener("click", refreshStatus));
document.querySelectorAll(".presence-refresh").forEach((item) => item.addEventListener("click", () => {
  if (signedIn()) presence();
}));
$("menu").addEventListener("click", () => toggleMenu(!document.body.classList.contains("nav-open")));
$("scrim").addEventListener("click", () => { toggleMenu(false); $("menu").focus(); });
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && document.body.classList.contains("nav-open")) {
    toggleMenu(false);
    $("menu").focus();
  }
});
$("session-button").addEventListener("click", showSession);
$("close-session").addEventListener("click", () => $("session-dialog").close());
$("start-session").addEventListener("click", beginSession);
$("logout").addEventListener("click", logout);
$("upload-button").addEventListener("click", () => $("upload-file").click());
$("upload-file").addEventListener("change", () => { uploadFile($("upload-file").files[0]); $("upload-file").value = ""; });
$("engine").addEventListener("change", showEngine);
$("clear-chat").addEventListener("click", resetChat);
$("assistant-form").addEventListener("submit", sendChat);
$("prompt-voice").addEventListener("click", () => { $("prompt").value = "¿Cómo configuro Linphone para llamar a mi equipo?"; $("prompt").focus(); });
$("audio-button").addEventListener("click", () => { if (signedIn()) $("audio").click(); });
$("audio").addEventListener("change", () => { transcribe($("audio").files[0]); $("audio").value = ""; });
$("draft").addEventListener("click", draft);
$("save-form").addEventListener("submit", saveActa);
$("share-acta").addEventListener("submit", shareActa);
$("thread-form").addEventListener("submit", sendToRoom);
$("thread-refresh").addEventListener("click", () => loadThread());
setInterval(() => { if (state.view === "talk" && state.room && !document.hidden) loadThread(); }, 15000);
window.addEventListener("hashchange", () => navigate(true));
navigate();
config().then(updateView).catch((error) => {
  message($("home-team"), error.message, null, true);
  notify(error.message);
});
refreshStatus();
