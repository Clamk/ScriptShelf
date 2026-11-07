/* Script Shelf: catalogue front end.
 * Reads catalogue/scripts.json and the script files themselves (relative paths,
 * so it works under a GitHub Pages project path and on a local server).
 * Routes (hash based, so refresh and direct links work on static hosting):
 *   #/                         catalogue (optional ?q=..&c=..&t=tag1,tag2)
 *   #/script/<id>              one script
 */
(function () {
  "use strict";

  var CATALOGUE_URL = "catalogue/scripts.json";
  var RECENT_COUNT = 4;
  var TAG_LIMIT = 14;

  var app = document.getElementById("app");
  var data = null;            // parsed catalogue
  var scripts = [];           // catalogue entries + derived fields
  var byId = Object.create(null);
  var catById = Object.create(null);
  var fileCache = Object.create(null);  // path -> Promise<string>
  var filters = { q: "", cat: "", tags: [] };
  var lastHomeHash = "#/";
  var homeScroll = 0;
  var tagsExpanded = false;

  // ---------- helpers ----------
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function norm(s) {
    return String(s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
  }
  // `code` spans for things that look like commands, paths or switches inside documented text
  function inline(s) {
    return esc(s).replace(/(^|[\s(])((?:\.\\|[A-Za-z]:\\|-[A-Za-z]|\$[A-Za-z_]|&lt;)[^\s,;)]*)/g, function (m, pre, tok) {
      var tail = (tok.match(/[.:]+$/) || [""])[0];   // sentence punctuation stays outside
      return pre + "<code>" + tok.slice(0, tok.length - tail.length) + "</code>" + tail;
    });
  }
  function fileName(p) { return p.split("/").pop(); }
  function catLabel(id) { return catById[id] ? catById[id].label : id; }
  function catColor(id) { return "var(--cat-" + (/^[a-z0-9-]+$/.test(id) ? id : "other") + ", var(--cat-other))"; }
  function githubUrl(path, kind) {
    var r = data.repository;
    var base = "https://github.com/" + encodeURIComponent(r.owner) + "/" + encodeURIComponent(r.name);
    if (!path) return base;
    return base + "/" + (kind || "blob") + "/" + encodeURIComponent(r.branch) + "/" + path.split("/").map(encodeURIComponent).join("/");
  }
  function fmtDate(iso) {
    if (!iso) return "";
    var d = new Date(iso + "T00:00:00");
    return isNaN(d) ? iso : d.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" });
  }
  function plural(n, one, many) { return n + " " + (n === 1 ? one : (many || one + "s")); }
  function loadFile(path) {
    if (!fileCache[path]) {
      fileCache[path] = fetch(path, { cache: "no-cache" }).then(function (r) {
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.text();
      });
      fileCache[path].catch(function () { delete fileCache[path]; });
    }
    return fileCache[path];
  }
  var ICON = {
    search: '<svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" d="M11 18a7 7 0 1 1 0-14 7 7 0 0 1 0 14Zm9 3-4.35-4.35"/></svg>',
    copy: '<svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" d="M9 9h10v11H9zM5 15V4h10"/></svg>',
    download: '<svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true"><path fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" d="M12 4v11m-5-5 5 5 5-5M5 20h14"/></svg>',
    gh: '<svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><path fill="currentColor" d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/></svg>'
  };

  // ---------- routing ----------
  function parseHash() {
    var h = location.hash.replace(/^#/, "") || "/";
    var qi = h.indexOf("?");
    var path = qi >= 0 ? h.slice(0, qi) : h;
    var params = new URLSearchParams(qi >= 0 ? h.slice(qi + 1) : "");
    var m = path.match(/^\/script\/([^/?#]+)\/?$/);
    if (m) return { view: "script", id: decodeURIComponent(m[1]) };
    return {
      view: "home",
      q: params.get("q") || "",
      cat: params.get("c") || "",
      tags: (params.get("t") || "").split(",").map(function (t) { return t.trim(); }).filter(Boolean)
    };
  }
  function homeHash(f) {
    var p = new URLSearchParams();
    if (f.q) p.set("q", f.q);
    if (f.cat) p.set("c", f.cat);
    if (f.tags.length) p.set("t", f.tags.join(","));
    var s = p.toString();
    return "#/" + (s ? "?" + s : "");
  }
  function syncHash() {       // update the address without re-rendering the page
    var h = homeHash(filters);
    lastHomeHash = h;
    if (location.hash !== h && !(h === "#/" && !location.hash)) history.replaceState(null, "", h);
  }
  function route() {
    if (!data) return;
    var r = parseHash();
    if (r.view === "script") {
      if (document.querySelector(".home")) homeScroll = window.scrollY;
      renderScript(r.id);
    } else {
      filters = { q: r.q, cat: catById[r.cat] ? r.cat : "", tags: r.tags };
      lastHomeHash = homeHash(filters);
      renderHome();
    }
  }

  // ---------- search ----------
  function matches(s, f, ignoreTags) {
    if (f.cat && s.category !== f.cat) return false;
    if (!ignoreTags && f.tags.length && !f.tags.every(function (t) { return s.tags.indexOf(t) >= 0; })) return false;
    if (f.q) {
      var words = norm(f.q).split(/\s+/).filter(Boolean);
      for (var i = 0; i < words.length; i++) if (s._hay.indexOf(words[i]) < 0) return false;
    }
    return true;
  }
  function score(s, q) {
    if (!q) return 0;
    var words = norm(q).split(/\s+/).filter(Boolean);
    var name = norm(s.name), tags = norm(s.tags.join(" "));
    var sc = 0;
    words.forEach(function (w) { if (name.indexOf(w) >= 0) sc += 3; else if (tags.indexOf(w) >= 0) sc += 2; else if (norm(s.summary).indexOf(w) >= 0) sc += 1; });
    return sc;
  }
  function filtersActive() { return !!(filters.q || filters.cat || filters.tags.length); }

  // ---------- home ----------
  function renderHome() {
    document.title = data.title;
    var cats = data.categories.filter(function (c) { return scripts.some(function (s) { return s.category === c.id; }); });
    app.innerHTML =
      '<div class="home">' +
      '<section class="hero">' +
      '<span class="hero__kicker">~/scripts</span>' +
      "<h1>" + esc(data.title) + "</h1>" +
      (data.description ? "<p>" + esc(data.description) + "</p>" : "") +
      '<div class="stats"><span><b>' + scripts.length + "</b> " + (scripts.length === 1 ? "script" : "scripts") + "</span>" +
      "<span><b>" + cats.length + "</b> " + (cats.length === 1 ? "category" : "categories") + "</span></div>" +
      "</section>" +
      '<div class="search" role="search">' + ICON.search +
      '<input id="q" type="search" autocomplete="off" spellcheck="false" placeholder="Search names, descriptions, tags, usage…" aria-label="Search scripts">' +
      '<kbd aria-hidden="true">/</kbd></div>' +
      '<div class="filters">' +
      '<div class="chip-row" id="catChips" role="group" aria-label="Filter by category"></div>' +
      '<div class="chip-row" id="tagChips" role="group" aria-label="Filter by tag"></div>' +
      "</div>" +
      '<section class="section" id="recentSection" aria-labelledby="recentTitle">' +
      '<div class="section-head"><h2 id="recentTitle">Recently added</h2></div>' +
      '<div class="recent" id="recent"></div></section>' +
      '<section class="section" aria-labelledby="allTitle">' +
      '<div class="section-head"><h2 id="allTitle">Catalogue</h2><span class="meta" id="resultCount" aria-live="polite"></span></div>' +
      '<div class="grid" id="grid"></div></section>' +
      "</div>";

    var q = document.getElementById("q");
    q.value = filters.q;
    q.addEventListener("input", function () { filters.q = q.value; syncHash(); updateHome(); });
    q.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && q.value) { q.value = ""; filters.q = ""; syncHash(); updateHome(); }
    });
    renderCategoryChips(cats);
    renderRecent();
    updateHome();
    window.scrollTo(0, homeScroll);
    homeScroll = 0;
  }

  function renderCategoryChips(cats) {
    var html = '<span class="chip-row__label">Category</span>' +
      '<button type="button" class="chip" data-cat="" aria-pressed="' + (!filters.cat) + '">All <span class="n">' + scripts.length + "</span></button>";
    cats.forEach(function (c) {
      var n = scripts.filter(function (s) { return s.category === c.id; }).length;
      html += '<button type="button" class="chip" data-cat="' + esc(c.id) + '" aria-pressed="' + (filters.cat === c.id) + '">' +
        '<span class="dot" style="--c:' + catColor(c.id) + '"></span>' + esc(c.label) + ' <span class="n">' + n + "</span></button>";
    });
    var row = document.getElementById("catChips");
    row.innerHTML = html;
    row.onclick = function (e) {
      var b = e.target.closest("[data-cat]");
      if (!b) return;
      filters.cat = b.getAttribute("data-cat");
      filters.tags = [];          // tags depend on the category: start fresh
      row.querySelectorAll(".chip").forEach(function (x) { x.setAttribute("aria-pressed", String(x === b)); });
      syncHash();
      updateHome();
    };
  }

  function renderTagChips() {
    var counts = Object.create(null);
    scripts.forEach(function (s) {
      if (!matches(s, filters, true)) return;
      s.tags.forEach(function (t) { counts[t] = (counts[t] || 0) + 1; });
    });
    filters.tags.forEach(function (t) { if (!counts[t]) counts[t] = 0; });
    var tags = Object.keys(counts).sort(function (a, b) {
      var sa = filters.tags.indexOf(a) >= 0, sb = filters.tags.indexOf(b) >= 0;
      if (sa !== sb) return sa ? -1 : 1;
      return counts[b] - counts[a] || a.localeCompare(b);
    });
    var row = document.getElementById("tagChips");
    if (!tags.length) { row.innerHTML = ""; return; }
    var shown = tagsExpanded ? tags : tags.slice(0, TAG_LIMIT);
    var html = '<span class="chip-row__label">Tags</span>';
    shown.forEach(function (t) {
      html += '<button type="button" class="chip chip--tag" data-tag="' + esc(t) + '" aria-pressed="' + (filters.tags.indexOf(t) >= 0) + '">' +
        esc(t) + ' <span class="n">' + counts[t] + "</span></button>";
    });
    if (tags.length > TAG_LIMIT) {
      html += '<button type="button" class="link-btn" data-more>' + (tagsExpanded ? "fewer" : "+" + (tags.length - TAG_LIMIT) + " more") + "</button>";
    }
    row.innerHTML = html;
    row.onclick = function (e) {
      if (e.target.closest("[data-more]")) { tagsExpanded = !tagsExpanded; renderTagChips(); return; }
      var b = e.target.closest("[data-tag]");
      if (!b) return;
      var t = b.getAttribute("data-tag");
      var i = filters.tags.indexOf(t);
      if (i >= 0) filters.tags.splice(i, 1); else filters.tags.push(t);
      syncHash();
      updateHome();
    };
  }

  function renderRecent() {
    var list = scripts.slice().sort(function (a, b) {
      return (b.added || "").localeCompare(a.added || "") || (b.created || "").localeCompare(a.created || "") || a.name.localeCompare(b.name);
    }).slice(0, RECENT_COUNT);
    document.getElementById("recent").innerHTML = list.map(function (s) {
      return '<a href="#/script/' + encodeURIComponent(s.id) + '">' +
        '<span class="when">added ' + esc(fmtDate(s.added)) + "</span>" +
        '<span class="title">' + esc(s.name) + "</span>" +
        '<span class="cat"><span class="dot" style="--c:' + catColor(s.category) + '"></span>' + esc(catLabel(s.category)) + "</span></a>";
    }).join("");
  }

  function cardHtml(s) {
    var badge = s.example ? '<span class="badge badge--example">Example</span>' : (!s.tested_on ? '<span class="badge badge--untested">Untested</span>' : "");
    return '<a class="card" href="#/script/' + encodeURIComponent(s.id) + '">' +
      '<div class="card__top"><span class="card__cat"><span class="dot" style="--c:' + catColor(s.category) + '"></span>' + esc(catLabel(s.category)) + "</span>" + badge + "</div>" +
      "<h3>" + esc(s.name) + "</h3>" +
      "<p>" + esc(s.summary) + "</p>" +
      (s.tags.length ? '<div class="card__tags">' + s.tags.slice(0, 5).map(function (t) { return '<span class="tag">' + esc(t) + "</span>"; }).join("") + "</div>" : "") +
      '<div class="card__foot"><span>' + esc(fileName(s.path)) + "</span><span>" + esc(s.language) + "</span></div>" +
      "</a>";
  }

  function updateHome() {
    renderTagChips();
    var active = filtersActive();
    document.getElementById("recentSection").hidden = active;
    var list = scripts.filter(function (s) { return matches(s, filters); });
    list.sort(function (a, b) { return score(b, filters.q) - score(a, filters.q) || a.name.localeCompare(b.name); });
    document.getElementById("resultCount").innerHTML = active
      ? esc(list.length + " of " + plural(scripts.length, "script")) + ' · <button type="button" class="link-btn" id="clearAll">clear filters</button>'
      : esc(plural(scripts.length, "script"));
    var grid = document.getElementById("grid");
    if (!list.length) {
      grid.innerHTML = '<div class="empty" style="grid-column:1/-1"><h2>No script matches</h2>' +
        "<p>Try fewer or different words, or remove a category or tag filter.</p>" +
        '<button type="button" class="btn" data-clear>Clear search and filters</button></div>';
    } else {
      grid.innerHTML = list.map(cardHtml).join("");
    }
    var clear = function () {
      filters = { q: "", cat: "", tags: [] };
      document.getElementById("q").value = "";
      document.querySelectorAll("#catChips .chip").forEach(function (x) { x.setAttribute("aria-pressed", String(x.getAttribute("data-cat") === "")); });
      syncHash();
      updateHome();
    };
    var c1 = document.getElementById("clearAll"); if (c1) c1.onclick = clear;
    var c2 = grid.querySelector("[data-clear]"); if (c2) c2.onclick = clear;
  }

  // ---------- script view ----------
  function listPanel(title, items, ordered, extraClass) {
    var body = items && items.length
      ? "<" + (ordered ? "ol" : "ul") + ">" + items.map(function (x) { return "<li>" + inline(x) + "</li>"; }).join("") + "</" + (ordered ? "ol" : "ul") + ">"
      : '<p class="none">Not documented yet.</p>';
    return '<section class="panel' + (extraClass ? " " + extraClass : "") + '"><h2>' + esc(title) + "</h2>" + body + "</section>";
  }

  function renderScript(id) {
    var s = byId[id];
    if (!s) {
      document.title = "Not found · " + data.title;
      app.innerHTML = '<a class="back" href="' + esc(lastHomeHash) + '">← All scripts</a>' +
        '<div class="empty"><h2>Script not found</h2><p>There is no script with the id <code>' + esc(id) +
        "</code>. It may have been renamed or removed.</p><a class=\"btn\" href=\"#/\">Browse the catalogue</a></div>";
      window.scrollTo(0, 0);
      return;
    }
    document.title = s.name + " · " + data.title;
    var file = fileName(s.path);
    // every file of the script: main, supporting files, older/other versions
    var files = [{ path: s.path, label: "Main", kind: "main" }]
      .concat(s.supporting_files.map(function (f) { return { path: f.path, label: f.label, kind: "support" }; }))
      .concat((s.versions || []).map(function (f) { return { path: f.path, label: f.label, kind: "version", date: f.date, note: f.note }; }));
    var tabs = files.length > 1
      ? '<div class="file-tabs" role="tablist" aria-label="Files of this script">' + files.map(function (f, i) {
          return '<button type="button" role="tab" class="file-tab' + (f.kind === "version" ? " file-tab--version" : "") + '" data-file="' + i + '" aria-selected="' + (i === 0) + '">' +
            '<span class="file-tab__name">' + esc(fileName(f.path)) + "</span>" +
            '<span class="file-tab__label">' + esc(f.kind === "version" ? "version · " + f.label : f.label) + "</span></button>";
        }).join("") + "</div>"
      : "";
    var badge = s.example ? '<span class="badge badge--example">Example</span>' : (!s.tested_on ? '<span class="badge badge--untested">Untested</span>' : "");
    var facts = [
      ["Language", esc(s.language)],
      ["File", "<code>" + esc(file) + "</code>"],
      ["Path", '<a href="' + esc(githubUrl(s.path)) + '" target="_blank" rel="noopener"><code>' + esc(s.path) + "</code></a>"],
      ["Added", s.added ? esc(fmtDate(s.added)) : null],
      ["Written", s.created ? esc(fmtDate(s.created)) : null],
      ["Tested on", s.tested_on ? esc(s.tested_on) : null]
    ].map(function (f) {
      return "<dt>" + f[0] + "</dt>" + (f[1] === null ? '<dd class="none">not documented</dd>' : "<dd>" + f[1] + "</dd>");
    }).join("");
    var support = files.length > 1
      ? '<section class="panel"><h2>Files</h2><ul class="files">' + files.map(function (f) {
          var label = f.kind === "version" ? "Version: " + f.label : f.label;
          return '<li><a href="' + esc(githubUrl(f.path)) + '" target="_blank" rel="noopener">' + esc(fileName(f.path)) + "</a>" +
            '<span class="files__label"> · ' + esc(label) + "</span>" +
            (f.note ? '<div class="files__note">' + esc(f.note) + "</div>" : "") + "</li>";
        }).join("") + "</ul></section>"
      : "";

    app.innerHTML =
      '<a class="back" href="' + esc(lastHomeHash) + '">← All scripts</a>' +
      '<header class="detail-head">' +
      '<div class="detail-head__meta"><span class="card__cat"><span class="dot" style="--c:' + catColor(s.category) + '"></span>' +
      '<a href="#/?c=' + encodeURIComponent(s.category) + '" style="text-decoration:none">' + esc(catLabel(s.category)) + "</a></span>" + badge +
      (s.tags.length ? s.tags.map(function (t) { return '<a class="tag" style="text-decoration:none" href="#/?t=' + encodeURIComponent(t) + '">' + esc(t) + "</a>"; }).join("") : "") +
      "</div>" +
      "<h1>" + esc(s.name) + "</h1>" +
      '<p class="lede">' + esc(s.summary) + "</p>" +
      '<div class="actions">' +
      '<button type="button" class="btn btn--primary" id="copyBtn">' + ICON.copy + "<span>Copy code</span></button>" +
      '<a class="btn" id="dlBtn" href="' + esc(s.path) + '" download="' + esc(file) + '">' + ICON.download + '<span id="dlLabel">Download ' + esc(file) + "</span></a>" +
      '<a class="btn" id="ghBtn" href="' + esc(githubUrl(s.path)) + '" target="_blank" rel="noopener">' + ICON.gh + "<span>View on GitHub</span></a>" +
      "</div></header>" +
      '<div class="detail-body"><div>' +
      '<section class="panel"><h2>Description</h2><p>' + esc(s.description) + "</p></section>" +
      listPanel("Usage", s.usage, true) +
      listPanel("Inputs", s.inputs) +
      listPanel("Outputs", s.outputs) +
      "</div><aside>" +
      '<section class="panel"><h2>Details</h2><dl class="facts">' + facts + "</dl></section>" +
      listPanel("Requirements", s.requirements) +
      (s.warnings.length ? listPanel("Warnings and limitations", s.warnings, false, "panel--warn") : listPanel("Warnings and limitations", [])) +
      support +
      "</aside></div>" +
      '<section class="code" aria-label="Source code">' + tabs +
      '<div class="code__bar"><span class="code__file" id="codeFile">' + esc(file) + '</span><span class="code__info" id="codeInfo">loading…</span></div>' +
      '<div class="code__note" id="codeNote" hidden></div>' +
      '<div class="code__scroll" id="codeScroll"><div class="code__msg">Loading source…</div></div>' +
      "</section>";
    window.scrollTo(0, 0);

    var current = files[0];
    var copyBtn = document.getElementById("copyBtn");
    copyBtn.addEventListener("click", function () { copyCode(current.path, copyBtn); });

    function showFile(f) {
      current = f;
      var name = fileName(f.path);
      var ext = (name.match(/\.[^.]+$/) || [""])[0];
      document.getElementById("codeFile").textContent = name;
      document.getElementById("dlBtn").setAttribute("href", f.path);
      document.getElementById("dlBtn").setAttribute("download", name);
      document.getElementById("dlLabel").textContent = "Download " + name;
      document.getElementById("ghBtn").setAttribute("href", githubUrl(f.path));
      var note = document.getElementById("codeNote");
      note.hidden = f.kind !== "version";
      note.textContent = f.kind === "version" ? "Version: " + f.label + (f.date ? " (" + fmtDate(f.date) + ")" : "") + (f.note ? ". " + f.note : "") : "";
      document.getElementById("codeInfo").textContent = "loading…";
      loadFile(f.path).then(function (text) {
        if (!document.getElementById("codeScroll") || parseHash().id !== s.id || current !== f) return;
        var lines = text.split("\n").length - (text.endsWith("\n") ? 1 : 0);
        var bytes = new TextEncoder().encode(text).length;
        var nums = [];
        for (var i = 1; i <= Math.max(lines, 1); i++) nums.push(i);
        var lang = window.ShelfHighlight ? window.ShelfHighlight.highlight(text, ext) : esc(text);
        document.getElementById("codeInfo").textContent = plural(lines, "line") + " · " + (bytes < 1024 ? bytes + " B" : (bytes / 1024).toFixed(1) + " KB");
        document.getElementById("codeScroll").innerHTML =
          '<div class="code__grid"><pre class="code__gutter" aria-hidden="true">' + nums.join("\n") + "</pre>" +
          '<pre class="code__src" tabindex="0"><code id="codeText">' + lang + "</code></pre></div>";
      }).catch(function (e) {
        if (!document.getElementById("codeScroll") || current !== f) return;
        document.getElementById("codeInfo").textContent = "not loaded";
        document.getElementById("codeScroll").innerHTML = '<div class="code__msg">Could not load <code>' + esc(f.path) + "</code> (" + esc(e.message) +
          '). Try <a href="' + esc(githubUrl(f.path)) + '" target="_blank" rel="noopener">the file on GitHub</a>.</div>';
      });
    }

    var tabRow = document.querySelector(".file-tabs");
    if (tabRow) tabRow.addEventListener("click", function (e) {
      var b = e.target.closest("[data-file]");
      if (!b) return;
      tabRow.querySelectorAll(".file-tab").forEach(function (x) { x.setAttribute("aria-selected", String(x === b)); });
      showFile(files[+b.getAttribute("data-file")]);
    });
    showFile(current);
  }

  function copyCode(path, btn) {
    var label = btn.querySelector("span");
    var reset = function () { setTimeout(function () { label.textContent = "Copy code"; btn.classList.remove("is-done"); }, 1800); };
    loadFile(path).then(function (text) {
      if (navigator.clipboard && window.isSecureContext) return navigator.clipboard.writeText(text);
      throw new Error("clipboard unavailable");
    }).then(function () {
      label.textContent = "Copied";
      btn.classList.add("is-done");
      reset();
    }).catch(function () {
      var code = document.getElementById("codeText");
      if (code) {
        var r = document.createRange();
        r.selectNodeContents(code);
        var sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(r);
        label.textContent = "Selected: press Ctrl+C";
      } else {
        label.textContent = "Copy failed";
      }
      reset();
    });
  }

  // ---------- boot ----------
  function showError(title, html) {
    app.innerHTML = '<div class="notice notice--error"><h2>' + esc(title) + "</h2>" + html + "</div>";
  }

  function prepare(d) {
    data = d;
    (d.categories || []).forEach(function (c) { catById[c.id] = c; });
    scripts = (d.scripts || []).map(function (s) {
      var x = Object.assign({ tags: [], usage: [], inputs: [], outputs: [], warnings: [], requirements: [], supporting_files: [], versions: [] }, s);
      x._hay = norm([x.name, x.id, x.summary, x.description, catLabel(x.category), x.language, x.tags.join(" "),
        x.usage.join(" "), x.requirements.join(" "), x.inputs.join(" "), x.outputs.join(" "), fileName(x.path)].join("\n"));
      byId[x.id] = x;
      return x;
    });
    var repo = document.getElementById("repoLink");
    repo.href = githubUrl();
    repo.hidden = false;
    document.getElementById("footerRepo").innerHTML = 'Source: <a href="' + esc(githubUrl()) + '">' + esc(d.repository.owner + "/" + d.repository.name) + "</a>";
  }

  document.addEventListener("keydown", function (e) {
    var t = e.target;
    if (e.key === "/" && !/^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName) && !t.isContentEditable) {
      var q = document.getElementById("q");
      if (q) { e.preventDefault(); q.focus(); q.select(); }
    }
  });
  window.addEventListener("hashchange", route);

  if (location.protocol === "file:") {
    showError("Open this site through a web server",
      "<p>Browsers block loading the catalogue from a file opened directly. From the repository folder run:</p>" +
      "<p><code>python tools/build_site.py</code> then <code>python -m http.server -d _site 8000</code></p>" +
      "<p>and open <code>http://localhost:8000</code>.</p>");
    return;
  }

  fetch(CATALOGUE_URL, { cache: "no-cache" }).then(function (r) {
    if (!r.ok) throw new Error("HTTP " + r.status);
    return r.json();
  }).then(function (d) {
    prepare(d);
    route();
  }).catch(function (e) {
    showError("The catalogue could not be loaded",
      "<p><code>" + esc(CATALOGUE_URL) + "</code> did not load (" + esc(e.message) + "). Reload the page; if it persists, check that the file exists and is valid JSON.</p>");
  });
})();
