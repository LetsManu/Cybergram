// Cybergram website (W20-WEB): live status, leaderboard and download
// buttons. Reads only this site's own JSON files (no third parties):
//   /data/snapshot.json  written by the game server's front every few seconds
//   /data/release.json   the latest GitHub release, fetched by the web server
// Refreshes every 30 s while the tab is visible. No cookies, no storage.
"use strict";

(function () {
  var REFRESH_MS = 30000;
  var STALE_S = 60; // an older snapshot means the front is not running
  var RELEASES = "https://github.com/LetsManu/Cybergram/releases/latest";

  function $(sel, root) { return (root || document).querySelector(sel); }
  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }
  function getJSON(url) {
    return fetch(url, { cache: "no-store", credentials: "omit" }).then(function (r) {
      if (!r.ok) throw new Error("HTTP " + r.status);
      return r.json();
    });
  }
  function nowS() { return Math.floor(Date.now() / 1000); }
  function ago(unix) {
    var s = Math.max(0, nowS() - unix);
    if (s < 5) return "just now";
    if (s < 120) return s + " s ago";
    if (s < 7200) return Math.round(s / 60) + " min ago";
    return Math.round(s / 3600) + " h ago";
  }
  function waitText(s) {
    s = Math.max(0, Math.round(s));
    if (s < 60) return "< 1 min";
    var m = Math.round(s / 60);
    return m < 60 ? "~" + m + " min" : "~" + Math.round(m / 60) + " h";
  }
  function fmtInt(n) { return Number(n || 0).toLocaleString("en"); }

  // Normalised server state: {state: up|draining|down, snap}.
  function serverState(snap) {
    if (!snap || typeof snap.updated !== "number") return { state: "down", snap: null };
    if (nowS() - snap.updated > STALE_S) return { state: "down", snap: snap };
    return { state: snap.status === "draining" ? "draining" : "up", snap: snap };
  }
  var STATE_TEXT = { up: "Online", draining: "Restarting soon", down: "Offline", loading: "Checking…" };

  // --- status page ---------------------------------------------------------------
  function renderStatus(root, st) {
    var s = st.snap;
    var stateEl = $("[data-state]", root);
    stateEl.setAttribute("data-state", st.state);
    $("[data-state-text]", root).textContent = STATE_TEXT[st.state];
    $("[data-updated]", root).textContent = s ? "Updated " + ago(s.updated) : "No data from the game server.";
    var live = st.state !== "down";
    $("[data-players]", root).textContent = live ? fmtInt(s.players_online) : "–";
    $("[data-matches]", root).textContent = live ? fmtInt(s.matches_running) : "–";
    $("[data-forming]", root).textContent = live ? fmtInt(s.matches_forming) : "–";
    var body = $("[data-queues]", root);
    body.textContent = "";
    var queues = live && Array.isArray(s.queues) ? s.queues : [];
    if (!queues.length) {
      var tr = el("tr");
      var td = el("td", "muted", live ? "No queues." : "Queues are unavailable while the server is offline.");
      td.colSpan = 3;
      tr.appendChild(td);
      body.appendChild(tr);
    }
    queues.forEach(function (q) {
      var tr = el("tr");
      tr.appendChild(el("td", "", String(q.name || q.id)));
      tr.appendChild(el("td", "num", fmtInt(q.players)));
      tr.appendChild(el("td", "num", waitText(q.estimated_wait_s)));
      body.appendChild(tr);
    });
  }

  // --- leaderboard ---------------------------------------------------------------
  var BANDS = ["iron", "bronze", "silver", "gold", "platinum", "diamond", "master"];
  function renderBoard(root, st) {
    var body = $("[data-board-rows]", root);
    body.textContent = "";
    var s = st.snap;
    var lb = s && s.leaderboard ? s.leaderboard : null;
    var rows = lb && Array.isArray(lb.entries) ? lb.entries : [];
    $("[data-board-updated]", root).textContent = lb && lb.updated
      ? "Updated " + ago(lb.updated) + (st.state === "down" ? " (the server is offline)" : "")
      : (st.state === "down" ? "The game server is offline." : "");
    if (!rows.length) {
      var tr = el("tr");
      var td = el("td", "muted", "Nobody is listed yet. Switch on “Show me on the public leaderboard” in the game under Ranks.");
      td.colSpan = 4;
      tr.appendChild(td);
      body.appendChild(tr);
      return;
    }
    rows.forEach(function (r) {
      var tr = el("tr");
      tr.appendChild(el("td", "num", String(r.rank)));
      tr.appendChild(el("td", "", String(r.name)));
      var band = String(r.band || "").toLowerCase();
      var td = el("td");
      td.appendChild(el("span", "medal m-" + (BANDS.indexOf(band) >= 0 ? band : "iron"), String(r.medal || r.band || "")));
      tr.appendChild(td);
      tr.appendChild(el("td", "num", fmtInt(r.rating)));
      body.appendChild(tr);
    });
  }

  // --- home: live line and downloads -----------------------------------------------
  function renderMini(root, st) {
    root.className = "live " + st.state;
    var t = $("[data-live-text]", root);
    if (st.state === "down") t.textContent = "Official server: offline";
    else t.textContent = "Official server: " + STATE_TEXT[st.state].toLowerCase() + " · " +
      fmtInt(st.snap.players_online) + " online · " + fmtInt(st.snap.matches_running) + " matches";
  }

  var PICKS = [
    { re: /^CybergramSetup-.*\.exe$/i, label: "Windows installer" },
    { re: /^Cybergram-.*-x86_64\.AppImage$/i, label: "Linux AppImage" },
    { re: /^CybergramInstaller-.*-linux-x86_64\.tar\.gz$/i, label: "Linux installer (.tar.gz)" }
  ];
  function safeGithub(url) {
    return typeof url === "string" && url.indexOf("https://github.com/LetsManu/Cybergram/") === 0 ? url : RELEASES;
  }
  function renderRelease(root, rel) {
    if (Array.isArray(rel)) rel = rel[0];  // /releases?per_page=1: newest first
    if (!rel || typeof rel.tag_name !== "string" || !Array.isArray(rel.assets)) return;
    var list = $("[data-release-buttons]", root);
    var found = [];
    PICKS.forEach(function (p, i) {
      rel.assets.forEach(function (a) {
        if (p.re.test(String(a.name)) && !found.some(function (f) { return f.p === p; })) found.push({ p: p, a: a, i: i });
      });
    });
    if (!found.length) return;
    list.textContent = "";
    found.forEach(function (f, n) {
      var li = el("li");
      var a = el("a", "btn" + (n === 0 ? " btn-primary" : ""));
      a.href = safeGithub(f.a.browser_download_url);
      a.rel = "noopener";
      a.appendChild(document.createTextNode(f.p.label));
      if (f.a.size) a.appendChild(el("small", "", Math.round(f.a.size / 1048576) + " MB"));
      li.appendChild(a);
      list.appendChild(li);
    });
    var li = el("li");
    var all = el("a", "btn", "All files");
    all.href = safeGithub(rel.html_url);
    all.rel = "noopener";
    li.appendChild(all);
    list.appendChild(li);
    var date = rel.published_at ? String(rel.published_at).slice(0, 10) : "";
    $("[data-release-line]", root).textContent = "Latest release: " + rel.tag_name + (date ? " · " + date : "") +
      (rel.prerelease ? " · pre-release" : "");
  }

  // --- wiring ------------------------------------------------------------------------
  var status = $("[data-status]");
  var board = $("[data-board]");
  var mini = $("[data-live-mini]");
  var release = $("[data-release]");

  function refresh() {
    if (!status && !board && !mini) return;
    getJSON("/data/snapshot.json").then(serverState, function () { return serverState(null); }).then(function (st) {
      if (status) renderStatus(status, st);
      if (board) renderBoard(board, st);
      if (mini) renderMini(mini, st);
    });
  }
  refresh();
  setInterval(function () { if (!document.hidden) refresh(); }, REFRESH_MS);
  document.addEventListener("visibilitychange", function () { if (!document.hidden) refresh(); });
  if (release) getJSON("/data/release.json").then(function (r) { renderRelease(release, r); }, function () {});
})();
