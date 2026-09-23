const PIPED = [
  "https://pipedapi.kavin.rocks",
  "https://pipedapi.tokhmi.xyz",
  "https://pipedapi.moomoo.me",
  "https://pipedapi.syncpundit.io",
  "https://api-piped.mha.fi",
  "https://piped-api.garudalinux.org",
  "https://pipedapi.rivo.lol",
  "https://pipedapi.aeong.one",
  "https://pipedapi.daviteusz.eu"
];

const state = { results: [], queue: [], index: -1, favorites: loadFavorites() };
const audio = document.querySelector("#audio");

const $ = (s) => document.querySelector(s);
const esc = (v) => String(v ?? "").replace(/[&<>"']/g, c => ({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;" }[c]));
const durationText = (n) => {
  n = Number(n || 0); if (!n) return "";
  return Math.floor(n/60) + ":" + String(Math.floor(n%60)).padStart(2,"0");
};

async function api(path, options = {}) {
  let last;
  for (const base of PIPED) {
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), options.timeout || 12000);
      const res = await fetch(base + path, { ...options, signal: controller.signal });
      clearTimeout(timer);
      if (!res.ok) throw new Error("server");
      return await res.json();
    } catch (e) { last = e; }
  }
  throw last || new Error("Music servers unavailable.");
}

async function search(q) {
  renderStatus("Searching…");
  try {
    const data = await api("/search?q=" + encodeURIComponent(q) + "&filter=music");
    state.results = (Array.isArray(data) ? data : data.items || []).filter(x => x.id || x.url);
    renderResults();
  } catch (e) {
    renderStatus("Couldn't search right now. Try again in a moment.");
  }
}

function normalize(v) {
  let id = v.id;
  if (!id && v.url) { try { id = new URL(v.url, location.origin).searchParams.get("v") || v.url.split("/").pop(); } catch {} }
  return {
    id, title:v.title || "Unknown", uploader:v.uploaderName || v.uploader || "YouTube Music",
    thumbnail:v.thumbnail || "", duration:v.duration || 0
  };
}

function renderResults() {
  const list = $("#results");
  const items = state.results.map(normalize).filter(x => x.id && x.title);
  if (!items.length) return renderStatus("No results.");
  list.innerHTML = items.map((v,i) => `
    <article class="song">
      <img class="song-art" src="${esc(v.thumbnail)}" alt="">
      <div><div class="song-title">${esc(v.title)}</div><div class="song-subtitle">${esc(v.uploader)}${v.duration ? " · "+durationText(v.duration) : ""}</div></div>
      <button class="song-action" data-play="${i}" aria-label="Play">▶</button>
    </article>`).join("");
  list.querySelectorAll("[data-play]").forEach(b => b.onclick = () => {
    const items = state.results.map(normalize).filter(x => x.id && x.title);
    play(items[Number(b.dataset.play)], items);
  });
}

function renderStatus(text) { $("#results").innerHTML = `<div class="status">${esc(text)}</div>`; }

async function play(video, queue = state.queue) {
  video = normalize(video); state.queue = queue.map(normalize); state.index = state.queue.findIndex(v => v.id === video.id);
  updatePlayer(video, true);
  try {
    const data = await api("/streams/" + encodeURIComponent(video.id), { timeout: 15000 });
    const streams = (data.audioStreams || []).filter(s => s.url).sort((a,b) => (b.bitrate||0)-(a.bitrate||0));
    if (!streams.length) throw new Error("No playable audio was returned.");
    audio.src = streams[0].url;
    await audio.play();
  } catch (e) {
    $("#playerSubtitle").textContent = "Playback unavailable";
  }
}

function updatePlayer(v, loading = false) {
  $("#nowPlaying").classList.remove("hidden");
  $("#playerArt").src = v.thumbnail || "./icon.svg";
  $("#fullArt").src = v.thumbnail || "./icon.svg";
  $("#playerTitle").textContent = v.title;
  $("#playerSubtitle").textContent = loading ? "Loading…" : v.uploader;
  $("#fullTitle").textContent = v.title;
  $("#fullSubtitle").textContent = v.uploader;
}

function next() { if (state.index + 1 < state.queue.length) play(state.queue[++state.index], state.queue); }
function previous() { if (audio.currentTime > 5) audio.currentTime = 0; else if (state.index > 0) play(state.queue[--state.index], state.queue); }

function loadFavorites() { try { return JSON.parse(localStorage.getItem("zemer-favorites") || "[]"); } catch { return []; } }
function saveFavorites() { localStorage.setItem("zemer-favorites", JSON.stringify(state.favorites)); }
function renderLibrary() {
  const list = $("#libraryList");
  if (!state.favorites.length) return list.innerHTML = '<div class="status">Songs you save will appear here.</div>';
  list.innerHTML = state.favorites.map((v,i) => `
    <article class="song"><img class="song-art" src="${esc(v.thumbnail)}" alt="">
      <div><div class="song-title">${esc(v.title)}</div><div class="song-subtitle">${esc(v.uploader)}</div></div>
      <button class="song-action" data-lib-play="${i}">▶</button>
    </article>`).join("");
  list.querySelectorAll("[data-lib-play]").forEach(b => b.onclick = () => play(state.favorites[Number(b.dataset.libPlay)], state.favorites));
}

$("#searchForm").onsubmit = e => { e.preventDefault(); const q=$("#searchInput").value.trim(); if(q) search(q); };
$("#searchButton").onclick = () => $("#searchInput").focus();
$("#playButton").onclick = () => audio.paused ? audio.play() : audio.pause();
$("#fullPlay").onclick = () => audio.paused ? audio.play() : audio.pause();
$("#nextButton").onclick = next; $("#fullNext").onclick = next;
$("#prevButton").onclick = previous; $("#fullPrev").onclick = previous;
$("#expandButton").onclick = () => $("#fullPlayer").classList.remove("hidden");
$("#closePlayer").onclick = () => $("#fullPlayer").classList.add("hidden");
audio.onplay = () => { $("#playButton").textContent="Ⅱ"; $("#fullPlay").textContent="Ⅱ"; };
audio.onpause = () => { $("#playButton").textContent="▶"; $("#fullPlay").textContent="▶"; };
audio.onended = next;
audio.ontimeupdate = () => {
  const p = audio.duration ? audio.currentTime/audio.duration*100 : 0;
  $("#progress").value = p; $("#elapsed").textContent=durationText(audio.currentTime); $("#duration").textContent=durationText(audio.duration);
};
$("#progress").oninput = e => { if (audio.duration) audio.currentTime = Number(e.target.value)/100*audio.duration; };

document.querySelectorAll(".nav-button").forEach(b => b.onclick = () => {
  document.querySelectorAll(".nav-button").forEach(x=>x.classList.toggle("active", x===b));
  document.querySelectorAll(".view").forEach(v=>v.classList.toggle("active", v.id===b.dataset.view));
  if (b.dataset.view === "libraryView") renderLibrary();
});

if ("serviceWorker" in navigator) navigator.serviceWorker.register("./sw.js").catch(()=>{});
renderLibrary();
