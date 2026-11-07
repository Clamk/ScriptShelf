/* Small dependency-free syntax highlighter for the languages on the shelf.
 * ShelfHighlight.highlight(code, ext) -> HTML string (input is escaped).
 * Each language is an ordered list of [class, regex]; the first rule that
 * matches at a position wins. "word" tokens become keywords, literals or
 * function names (when followed by "("). Unknown extensions get plain text.
 */
(function (global) {
  "use strict";

  var esc = function (s) {
    return s.replace(/[&<>]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]; });
  };
  var set = function (s) {
    var o = Object.create(null);
    s.split(/\s+/).forEach(function (w) { if (w) o[w] = true; });
    return o;
  };

  var NUM = /\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b/;
  var WORD = /[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*/;

  var LANGS = {
    ijm: {
      flags: "",
      rules: [
        ["com", /\/\/[^\n]*|\/\*[\s\S]*?\*\//],
        ["str", /"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'/],
        ["num", NUM],
        ["word", WORD]
      ],
      kw: set("var function macro if else for while do return break continue requires new import def class"),
      lit: set("true false NaN PI null")
    },
    powershell: {
      flags: "i",
      rules: [
        ["com", /<#[\s\S]*?#>|#[^\n]*/],
        ["str", /@"[\s\S]*?\n"@|@'[\s\S]*?\n'@|"(?:[^"`]|`[\s\S])*"|'(?:[^']|'')*'/],
        ["var", /\$(?:\{[^}\n]*\}|[A-Za-z_][A-Za-z0-9_]*(?::[A-Za-z0-9_]+)?|[_?$^])/],
        ["type", /\[[A-Za-z][A-Za-z0-9_.]*(?:\[\])?\]/],
        ["op", /-(?:eq|ne|gt|ge|lt|le|c?like|c?notlike|c?match|c?notmatch|contains|notcontains|in|notin|replace|split|join|and|or|not|xor|f|is|isnot|as)\b/],
        ["attr", /-[A-Za-z][A-Za-z0-9]*/],
        ["num", /\b\d+(?:\.\d+)?(?:[kmgtp]b)?\b/],
        ["word", /[A-Za-z_][A-Za-z0-9_]*(?:-[A-Za-z][A-Za-z0-9]*)?/]
      ],
      kw: set("if else elseif foreach for while do until switch function filter param return try catch finally throw trap break continue in begin process end exit dynamicparam class enum"),
      lit: set("true false null"),
      cmdlet: /^[A-Za-z]+-[A-Za-z]+$/
    },
    python: {
      flags: "",
      rules: [
        ["com", /#[^\n]*/],
        ["str", /(?:[rRbBuUfF]{1,2})?(?:"""[\s\S]*?"""|'''[\s\S]*?'''|"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*')/],
        ["attr", /@[A-Za-z_][A-Za-z0-9_.]*/],
        ["num", NUM],
        ["word", WORD]
      ],
      kw: set("and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield print"),
      lit: set("True False None")
    },
    vba: {
      flags: "i",
      rules: [
        ["com", /'[^\n]*|\bRem\b[^\n]*/],
        ["str", /"(?:[^"\n]|"")*"/],
        ["num", /&H[0-9A-F]+&?|\b\d+(?:\.\d+)?\b/],
        ["word", /[A-Za-z_][A-Za-z0-9_]*\$?/]
      ],
      kw: set("option explicit private public const as long integer string boolean variant object range worksheet workbook collection sub function property get let end if then else elseif for each to step next do while wend loop until exit select case set dim redim preserve new nothing is not and or xor mod on error goto resume byval byref optional with call double single date static type enum like typeof"),
      lit: set("true false empty null")
    },
    bat: {
      flags: "im",
      rules: [
        ["com", /^[ \t]*(?:rem\b|::)[^\n]*/],
        ["str", /"[^"\n]*"/],
        ["var", /%~?[A-Za-z0-9_]*%|%%?~?[A-Za-z0-9]|![A-Za-z0-9_]+!/],
        ["word", /[A-Za-z_][A-Za-z0-9_.-]*/]
      ],
      kw: set("echo set if else goto call exit pause for in do not exist defined errorlevel setlocal endlocal start cd pushd popd shift"),
      lit: set("on off nul")
    },
    r: {
      flags: "",
      rules: [
        ["com", /#[^\n]*/],
        ["str", /"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'/],
        ["num", NUM],
        ["word", /[A-Za-z.][A-Za-z0-9._]*/]
      ],
      kw: set("if else for while repeat function return next break in library require"),
      lit: set("TRUE FALSE NULL NA NaN Inf T F")
    }
  };

  var BY_EXT = {
    ".ijm": "ijm", ".js": "ijm", ".groovy": "ijm", ".java": "ijm", ".bsh": "ijm",
    ".ps1": "powershell", ".psm1": "powershell", ".psd1": "powershell",
    ".py": "python",
    ".bas": "vba", ".cls": "vba", ".frm": "vba", ".vba": "vba", ".vbs": "vba",
    ".bat": "bat", ".cmd": "bat",
    ".r": "r"
  };

  // compile once per language
  Object.keys(LANGS).forEach(function (k) {
    var L = LANGS[k];
    L.names = L.rules.map(function (r) { return r[0]; });
    L.re = new RegExp(L.rules.map(function (r) { return "(" + r[1].source + ")"; }).join("|"), "g" + L.flags);
  });

  function classify(L, word, code, end) {
    var w = L.flags.indexOf("i") >= 0 ? word.toLowerCase() : word;
    if (L.kw[w]) return "kw";
    if (L.lit[w]) return "lit";
    if (L.cmdlet && L.cmdlet.test(word)) return "fn";
    var i = end;
    while (i < code.length && (code[i] === " " || code[i] === "\t")) i++;
    return code[i] === "(" ? "fn" : null;
  }

  function highlight(code, ext) {
    var L = LANGS[BY_EXT[(ext || "").toLowerCase()]];
    if (!L) return esc(code);
    var out = "", last = 0, m;
    L.re.lastIndex = 0;
    while ((m = L.re.exec(code)) !== null) {
      if (m[0] === "") { L.re.lastIndex++; continue; }
      var g = 1;
      while (g < m.length && m[g] === undefined) g++;
      var name = L.names[g - 1];
      var end = m.index + m[0].length;
      if (name === "word") name = classify(L, m[0], code, end);
      out += esc(code.slice(last, m.index));
      out += name ? '<span class="sx-' + name + '">' + esc(m[0]) + "</span>" : esc(m[0]);
      last = end;
    }
    return out + esc(code.slice(last));
  }

  global.ShelfHighlight = { highlight: highlight, languageFor: function (ext) { return BY_EXT[(ext || "").toLowerCase()] || null; } };
})(window);
