(function () {
  "use strict";

  // ---- constants ----
  var NUTRIENTS = window.FEED_NUTRIENTS || [];
  var UNITS = window.FEED_UNITS || {};
  var REFERENCE = window.FEED_REFERENCE || [];
  var NAMES_ES = window.FEED_NAMES_ES || {};
  var CATEGORIES = window.FEED_CATEGORIES || {};
  var STORAGE_KEY = "feed_user_ingredients_v1";
  var FORM_NUTRIENTS = ["DM", "CP", "TDN", "ME", "Fat", "NDF", "Ca", "P"];
  var EDIT_FIELDS = ["Cost", "DM", "CP", "TDN", "ME", "Fat", "Ash", "NDF", "Starch", "Ca", "P", "Mg", "K", "Na", "S", "LYS", "MET"];
  var DM_BASIS = { "%DM": true, "% DM": true };

  // ---- state ----
  var userIngredients = loadUser();

  // ---- small utilities ----
  function num(v) {
    if (v === null || v === undefined || v === "") return 0;
    var x = Number(v);
    return isFinite(x) ? x : 0;
  }
  function fmt(n, d) {
    if (d === undefined) d = 2;
    if (n === null || n === undefined || !isFinite(n)) return "-";
    return n.toFixed(d);
  }
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function nowISO() { return new Date().toISOString().slice(0, 19).replace("T", " "); }
  function newId() { return "u" + Date.now() + Math.floor(Math.random() * 1e6); }
  function dName(name) { return NAMES_ES[name] || name; }
  function catOf(name) { return CATEGORIES[name] || ""; }

  // ---- persistence ----
  function loadUser() {
    try { return JSON.parse(localStorage.getItem(STORAGE_KEY)) || []; }
    catch (e) { return []; }
  }
  function saveUser() {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(userIngredients)); } catch (e) {}
  }

  function blankIngredient() {
    var o = { id: newId(), Feed: "", IFN: "", source: "user", created: nowISO(), updated: nowISO(), notes: "" };
    NUTRIENTS.forEach(function (n) { o[n] = null; });
    return o;
  }

  function toAsFed(feeds) {
    return feeds.map(function (f) {
      var o = Object.assign({}, f);
      var dm = num(o.DM);
      NUTRIENTS.forEach(function (n) {
        if (n === "Cost" || n === "Forage" || n === "DM") return;
        if (DM_BASIS[UNITS[n]]) o[n] = num(o[n]) * dm / 100;
      });
      return o;
    });
  }

  function catalog() {
    var names = {};
    userIngredients.forEach(function (f) { names[String(f.Feed).toLowerCase()] = true; });
    var ref = REFERENCE.filter(function (f) { return !names[String(f.Feed).toLowerCase()]; })
      .map(function (f, i) {
        var o = Object.assign({}, f, { id: "ref-" + i, IFN: f.IFN || "", source: "reference", created: "", updated: "", notes: "" });
        return o;
      });
    return ref.concat(userIngredients);
  }

  // ---- CSV (compatible con el paquete R 'feed') ----
  var CSV_COLS = ["id", "Feed", "IFN", "source", "created", "updated", "notes"].concat(NUTRIENTS);

  function toCSV(rows) {
    var esc2 = function (v) {
      v = (v === null || v === undefined) ? "" : String(v);
      if (/[",\n]/.test(v)) v = '"' + v.replace(/"/g, '""') + '"';
      return v;
    };
    var lines = [CSV_COLS.map(esc2).join(",")];
    rows.forEach(function (r) {
      lines.push(CSV_COLS.map(function (c) { return esc2(r[c]); }).join(","));
    });
    return lines.join("\r\n");
  }

  function parseCSV(text) {
    var rows = [], row = [], field = "", inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      var ch = text[i];
      if (inQuotes) {
        if (ch === '"') {
          if (text[i + 1] === '"') { field += '"'; i++; }
          else inQuotes = false;
        } else field += ch;
      } else if (ch === '"') { inQuotes = true; }
      else if (ch === ",") { row.push(field); field = ""; }
      else if (ch === "\n" || ch === "\r") {
        if (ch === "\r" && text[i + 1] === "\n") i++;
        row.push(field); field = "";
        if (row.length > 1 || row[0] !== "") rows.push(row);
        row = [];
      } else field += ch;
    }
    if (field !== "" || row.length) { row.push(field); if (row.length > 1 || row[0] !== "") rows.push(row); }
    return rows;
  }

  function exportCSV() {
    var csv = toCSV(userIngredients);
    var blob = new Blob(["\ufeff" + csv], { type: "text/csv;charset=utf-8" });
    var a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "feed-ingredients-" + new Date().toISOString().slice(0, 10) + ".csv";
    document.body.appendChild(a); a.click(); a.remove();
  }

  function importCSV(file) {
    var reader = new FileReader();
    reader.onload = function (e) {
      var rows = parseCSV(String(e.target.result));
      if (rows.length < 2) { toast("CSV vacío o inválido", true); return; }
      var header = rows[0];
      var idx = {};
      header.forEach(function (h, i) { idx[h.trim()] = i; });
      if (!("Feed" in idx)) { toast("El CSV no tiene columna 'Feed'", true); return; }
      var existing = {};
      userIngredients.forEach(function (f) { existing[f.id] = true; });
      var added = 0, skipped = 0;
      for (var r = 1; r < rows.length; r++) {
        var cells = rows[r];
        var f = blankIngredient();
        var gotFeed = false;
        CSV_COLS.forEach(function (c) {
          if (idx[c] !== undefined) {
            var v = cells[idx[c]];
            if (c === "Feed") { f.Feed = v || ""; if (v) gotFeed = true; }
            else if (c === "id") { f.id = v || newId(); }
            else if (c === "IFN") { f.IFN = v || ""; }
            else if (c === "source") { f.source = v || "user"; }
            else if (c === "created") { f.created = v || nowISO(); }
            else if (c === "updated") { f.updated = v || nowISO(); }
            else if (c === "notes") { f.notes = v || ""; }
            else if (NUTRIENTS.indexOf(c) >= 0) { f[c] = (v === "" || v === undefined) ? null : num(v); }
          }
        });
        if (!gotFeed) { skipped++; continue; }
        if (existing[f.id]) { skipped++; continue; }
        existing[f.id] = true;
        userIngredients.push(f);
        added++;
      }
      saveUser();
      renderIngredients();
      toast("Importados " + added + " ingredientes" + (skipped ? " (" + skipped + " omitidos)" : ""));
    };
    reader.readAsText(file);
  }

  // ---- navigation ----
  var tabs = document.querySelectorAll("nav.tabs button");
  tabs.forEach(function (btn) {
    btn.addEventListener("click", function () {
      tabs.forEach(function (b) { b.classList.remove("active"); });
      btn.classList.add("active");
      var t = btn.getAttribute("data-tab");
      ["ingredients", "calculator", "formulation", "suggest"].forEach(function (k) {
        document.getElementById("tab-" + k).hidden = (k !== t);
      });
      if (t === "ingredients") renderIngredients();
      if (t === "calculator") renderCalculator();
      if (t === "formulation") renderFormulation();
      if (t === "suggest") renderSuggest();
    });
  });

  function toast(msg, isErr) {
    var old = document.getElementById("toast");
    if (old) old.remove();
    var el = document.createElement("div");
    el.id = "toast";
    el.textContent = msg;
    el.style.cssText = "position:fixed;bottom:20px;left:50%;transform:translateX(-50%);background:" +
      (isErr ? "#b42318" : "#1d6f42") + ";color:#fff;padding:10px 16px;border-radius:8px;z-index:100;font-size:14px;box-shadow:0 4px 12px rgba(0,0,0,.2)";
    document.body.appendChild(el);
    setTimeout(function () { el.remove(); }, 3500);
  }

  function el(html) {
    var t = document.createElement("template");
    t.innerHTML = html.trim();
    return t.content.firstChild;
  }

  // ================= Ingredients =================
  function renderIngredients() {
    var sec = document.getElementById("tab-ingredients");
    sec.innerHTML = "";
    var grid = el('<div class="grid2"></div>');

    // reference (read-only)
    var refCard = el('<div class="card"></div>');
    refCard.appendChild(el('<h2>Datos de referencia (solo lectura)</h2>'));
    refCard.appendChild(el('<p class="hint">Selecciona un ingrediente y pulsa "Copiar" para editarlo en tu base sin tocar la referencia.</p>'));
    var search = el('<input type="text" id="ref-search" placeholder="Buscar ingrediente...">');
    refCard.appendChild(search);
    var refScroll = el('<div class="scroll" style="margin-top:8px"></div>');
    refCard.appendChild(refScroll);

    function renderRefTable(query) {
      query = (query || "").toLowerCase().trim();
      var list = REFERENCE.filter(function (f) {
        if (!query) return true;
        return f.Feed.toLowerCase().indexOf(query) >= 0 || dName(f.Feed).toLowerCase().indexOf(query) >= 0;
      });
      var html = '<table><thead><tr><th>Nombre</th><th>Categoría</th><th>Precio $/t</th><th>DM</th><th>CP</th><th>TDN</th><th></th></tr></thead><tbody>';
      var cap = list.slice(0, 200);
      cap.forEach(function (f) {
        var es = dName(f.Feed), extra = es !== f.Feed ? ' <span class="tag">(' + esc(f.Feed) + ")</span>" : "";
        html += "<tr><td>" + esc(es) + extra + "</td><td>" + esc(catOf(f.Feed)) + "</td><td>" + fmt(f.Cost, 0) + "</td><td>" + fmt(f.DM, 1) +
          "</td><td>" + fmt(f.CP, 1) + "</td><td>" + fmt(f.TDN, 1) +
          '</td><td><button class="small" data-copy="' + esc(f.Feed) + '">Copiar</button></td></tr>';
      });
      html += "</tbody></table>";
      if (list.length > 200) html += '<p class="muted">Mostrando 200 de ' + list.length + '; usa el buscador (español o inglés).</p>';
      if (cap.length === 0) html = '<p class="muted">Sin resultados.</p>';
      refScroll.innerHTML = html;
      refScroll.querySelectorAll("button[data-copy]").forEach(function (b) {
        b.addEventListener("click", function () { copyFromReference(b.getAttribute("data-copy")); });
      });
    }
    renderRefTable("");
    search.addEventListener("input", function () { renderRefTable(search.value); });

    // user (editable)
    var userCard = el('<div class="card"></div>');
    userCard.appendChild(el('<h2>Mi base de ingredientes (editable)</h2>'));
    userCard.appendChild(el('<p class="hint">Los cambios se guardan automáticamente en este navegador. Exporta el CSV para compartirlo o respaldarlo.</p>'));
    var actions = el('<div class="row" style="margin-bottom:8px"></div>');
    var btnAdd = el('<button id="btn-add">Añadir nuevo</button>');
    var btnExport = el('<button class="secondary">Exportar CSV</button>');
    var btnImport = el('<button class="secondary">Importar CSV</button>');
    var btnClear = el('<button class="secondary danger">Borrar todo</button>');
    var fileInput = el('<input type="file" accept=".csv" style="display:none">');
    actions.appendChild(btnAdd); actions.appendChild(btnExport); actions.appendChild(btnImport); actions.appendChild(btnClear); actions.appendChild(fileInput);
    userCard.appendChild(actions);
    var userScroll = el('<div class="scroll"></div>');
    userCard.appendChild(userScroll);

    btnAdd.addEventListener("click", function () { openModal(null); });
    btnExport.addEventListener("click", exportCSV);
    btnImport.addEventListener("click", function () { fileInput.click(); });
    fileInput.addEventListener("change", function () { if (fileInput.files[0]) importCSV(fileInput.files[0]); });
    btnClear.addEventListener("click", function () {
      if (confirm("¿Borrar todos tus ingredientes? (los de referencia no se tocan)")) {
        userIngredients = []; saveUser(); renderIngredients(); toast("Base vaciada");
      }
    });

    renderUserTable(userScroll);
    grid.appendChild(refCard); grid.appendChild(userCard);
    sec.appendChild(grid);
  }

  function renderUserTable(container) {
    if (userIngredients.length === 0) {
      container.innerHTML = '<p class="muted" style="padding:12px">Aún no tienes ingredientes propios. Copia uno de referencia o añade uno nuevo.</p>';
      return;
    }
    var html = '<table><thead><tr><th>Nombre</th><th>Precio $/t</th><th>DM</th><th>CP</th><th>TDN</th><th>ME</th><th></th></tr></thead><tbody>';
    userIngredients.forEach(function (f) {
      html += "<tr><td>" + esc(dName(f.Feed)) + "</td><td>" + fmt(f.Cost, 0) + "</td><td>" + fmt(f.DM, 1) +
        "</td><td>" + fmt(f.CP, 1) + "</td><td>" + fmt(f.TDN, 1) + "</td><td>" + fmt(f.ME, 2) +
        '</td><td><button class="small secondary" data-edit="' + esc(f.id) + '">Editar</button> ' +
        '<button class="small danger" data-del="' + esc(f.id) + '">Borrar</button></td></tr>';
    });
    html += "</tbody></table>";
    container.innerHTML = html;
    container.querySelectorAll("button[data-edit]").forEach(function (b) {
      b.addEventListener("click", function () { openModal(b.getAttribute("data-edit")); });
    });
    container.querySelectorAll("button[data-del]").forEach(function (b) {
      b.addEventListener("click", function () {
        var id = b.getAttribute("data-del");
        userIngredients = userIngredients.filter(function (f) { return f.id !== id; });
        saveUser(); renderIngredients(); toast("Ingrediente borrado", true);
      });
    });
  }

  function copyFromReference(name) {
    var ref = REFERENCE.find(function (f) { return f.Feed === name; });
    if (!ref) return;
    var o = blankIngredient();
    o.Feed = ref.Feed; o.IFN = ref.IFN || ""; o.source = "reference";
    o.notes = "Copiado de la referencia NRC beef";
    NUTRIENTS.forEach(function (n) { o[n] = (ref[n] === undefined || ref[n] === null) ? null : num(ref[n]); });
    userIngredients.push(o);
    saveUser(); renderIngredients();
    toast("Copiado a tu base: " + name);
  }

  function openModal(id) {
    var f = id ? userIngredients.find(function (x) { return x.id === id; }) : blankIngredient();
    if (!f) return;
    var overlay = el('<div class="overlay"></div>');
    var modal = el('<div class="modal"></div>');
    modal.appendChild(el("<h3>" + (id ? "Editar ingrediente" : "Nuevo ingrediente") + "</h3>"));

    var nameInput = el('<label>Nombre<br><input type="text" id="f-Feed" value="' + esc(f.Feed) + '"></label>');
    modal.appendChild(nameInput);

    var grid = el('<div class="grid3"></div>');
    EDIT_FIELDS.forEach(function (n) {
      var u = UNITS[n] ? " (" + UNITS[n] + ")" : "";
      var v = (f[n] === null || f[n] === undefined) ? "" : f[n];
      var field = el('<label>' + esc(n) + u + '<br><input type="number" step="any" id="f-' + n + '" value="' + esc(v) + '"></label>');
      grid.appendChild(field);
    });
    modal.appendChild(grid);

    var actions = el('<div class="modal-actions"></div>');
    var cancel = el('<button class="secondary">Cancelar</button>');
    var save = el('<button>Guardar</button>');
    actions.appendChild(cancel); actions.appendChild(save);
    modal.appendChild(actions);
    overlay.appendChild(modal);

    function close() { overlay.remove(); }

    cancel.addEventListener("click", close);
    overlay.addEventListener("click", function (e) { if (e.target === overlay) close(); });
    save.addEventListener("click", function () {
      var name = document.getElementById("f-Feed").value.trim();
      if (!name) { toast("Escribe un nombre", true); return; }
      var isNew = !id;
      var target = id ? userIngredients.find(function (x) { return x.id === id; }) : f;
      target.Feed = name;
      EDIT_FIELDS.forEach(function (n) {
        var v = document.getElementById("f-" + n).value;
        target[n] = (v === "") ? null : num(v);
      });
      target.updated = nowISO();
      if (isNew) userIngredients.push(target);
      saveUser(); close(); renderIngredients();
      toast(isNew ? "Ingrediente añadido" : "Cambios guardados");
    });

    document.getElementById("modal-root").appendChild(overlay);
    nameInput.querySelector("input").focus();
  }

  // ================= Calculator =================
  var calcState = { selected: [], amounts: {} };

  function renderCalculator() {
    var sec = document.getElementById("tab-calculator");
    sec.innerHTML = "";
    var grid = el('<div class="grid2"></div>');

    var left = el('<div class="card"></div>');
    left.appendChild(el('<h2>1. Selecciona ingredientes</h2>'));
    var cats = catalog();
    var check = el('<div class="checklist"></div>');
    cats.forEach(function (f) {
      var lab = el('<label><input type="checkbox" data-feed="' + esc(f.Feed) + '">' + esc(dName(f.Feed)) + ' <span class="badge ' + (f.source === "user" ? "user" : "ref") + '">' + (f.source === "user" ? "tuyo" : "ref") + "</span></label>");
      check.appendChild(lab);
    });
    left.appendChild(check);

    var amtWrap = el('<div style="margin-top:12px"></div>');
    left.appendChild(el('<h3>2. Cantidades (kg)</h3>'));
    amtWrap.id = "calc-amounts";
    left.appendChild(amtWrap);
    var btnCalc = el('<button style="width:100%;margin-top:8px">Calcular</button>');
    btnCalc.addEventListener("click", runCalculator);
    left.appendChild(btnCalc);

    var right = el('<div class="card"></div>');
    right.appendChild(el('<h2>Resultado</h2>'));
    right.id = "calc-result";
    right.appendChild(el('<p class="muted">Selecciona ingredientes y pulsa "Calcular".</p>'));

    grid.appendChild(left); grid.appendChild(right);
    sec.appendChild(grid);

    check.querySelectorAll("input[data-feed]").forEach(function (inp) {
      inp.checked = calcState.selected.indexOf(inp.getAttribute("data-feed")) >= 0;
      inp.addEventListener("change", function () {
        var name = inp.getAttribute("data-feed");
        if (inp.checked) { if (calcState.selected.indexOf(name) < 0) calcState.selected.push(name); }
        else calcState.selected = calcState.selected.filter(function (x) { return x !== name; });
        renderAmounts(amtWrap);
      });
    });
    renderAmounts(amtWrap);
  }

  function renderAmounts(container) {
    container.innerHTML = "";
    calcState.selected.forEach(function (name) {
      if (!(name in calcState.amounts)) calcState.amounts[name] = 0;
      var lab = el('<label>' + esc(name) + '<br><input type="number" step="any" min="0" value="' + calcState.amounts[name] + '" data-amt="' + esc(name) + '"></label>');
      container.appendChild(lab);
    });
    container.querySelectorAll("input[data-amt]").forEach(function (inp) {
      inp.addEventListener("input", function () { calcState.amounts[inp.getAttribute("data-amt")] = num(inp.value); });
    });
  }

  function runCalculator() {
    var cats = catalog();
    var sel = cats.filter(function (f) { return calcState.selected.indexOf(f.Feed) >= 0; });
    if (sel.length === 0) { toast("Selecciona al menos un ingrediente", true); return; }
    var amounts = sel.map(function (f) { return num(calcState.amounts[f.Feed]); });
    var totalW = amounts.reduce(function (s, x) { return s + x; }, 0);
    if (totalW <= 0) { toast("La cantidad total debe ser mayor que 0", true); return; }
    var asFed = toAsFed(sel);
    var cost = 0;
    sel.forEach(function (f, i) { cost += amounts[i] * num(f.Cost) / 1000; });

    var nutrients = {};
    NUTRIENTS.forEach(function (n) {
      if (n === "Cost" || n === "Forage") return;
      var acc = 0, has = false;
      asFed.forEach(function (f, i) { if (f[n] !== null && f[n] !== undefined) { acc += amounts[i] * num(f[n]); has = true; } });
      nutrients[n] = has ? acc / totalW : null;
    });

    var right = document.getElementById("calc-result");
    var html = '<div class="result-box">';
    html += "<p><strong>Peso total:</strong> " + fmt(totalW) + " kg</p>";
    html += "<p><strong>Costo total:</strong> $" + fmt(cost) + "</p>";
    html += "<p><strong>Costo por kg:</strong> $" + fmt(cost / totalW, 4) + "</p></div>";
    html += '<h3>Aporte por nutriente (base tal cual / as-fed)</h3><div class="scroll"><table><thead><tr><th>Nutriente</th><th>Valor</th><th>Unidad</th></tr></thead><tbody>';
    NUTRIENTS.forEach(function (n) {
      if (n === "Cost" || n === "Forage") return;
      var v = nutrients[n];
      if (v === null) return;
      html += "<tr><td>" + esc(n) + "</td><td>" + fmt(v, 4) + "</td><td>" + esc(UNITS[n] || "") + "</td></tr>";
    });
    html += "</tbody></table></div>";
    right.innerHTML = html;
  }

  // ================= Formulation =================
  var formState = { selected: [] };

  function renderFormulation() {
    var sec = document.getElementById("tab-formulation");
    sec.innerHTML = "";
    var grid = el('<div class="grid2"></div>');

    var left = el('<div class="card"></div>');
    left.appendChild(el('<h2>1. Ingredientes disponibles</h2>'));
    var cats = catalog();
    var check = el('<div class="checklist"></div>');
    cats.forEach(function (f) {
      var lab = el('<label><input type="checkbox" data-feed="' + esc(f.Feed) + '">' + esc(dName(f.Feed)) + '</label>');
      check.appendChild(lab);
    });
    left.appendChild(check);

    left.appendChild(el('<h3>Peso total (kg)</h3>'));
    var totalInput = el('<input type="number" id="form-total" value="100" min="1" style="max-width:140px">');
    left.appendChild(totalInput);

    left.appendChild(el('<h3>2. Requerimientos (deja vacío = sin límite)</h3>'));
    var cons = el('<div class="grid3"></div>');
    FORM_NUTRIENTS.forEach(function (n) {
      var u = UNITS[n] ? " (" + UNITS[n] + ")" : "";
      var box = el('<div></div>');
      box.appendChild(el('<label>' + esc(n) + u + '<br>Mín <input type="number" step="any" id="min-' + n + '"></label>'));
      box.appendChild(el('<label>Máx <input type="number" step="any" id="max-' + n + '"></label>'));
      cons.appendChild(box);
    });
    left.appendChild(cons);

    var btnForm = el('<button style="width:100%;margin-top:12px">Formular (mínimo costo)</button>');
    btnForm.addEventListener("click", runFormulation);
    left.appendChild(btnForm);

    var right = el('<div class="card"></div>');
    right.appendChild(el('<h2>Mezcla óptima</h2>'));
    right.id = "form-result";
    right.appendChild(el('<p class="muted">Selecciona ingredientes, define al menos un requerimiento y pulsa "Formular".</p>'));

    grid.appendChild(left); grid.appendChild(right);
    sec.appendChild(grid);

    check.querySelectorAll("input[data-feed]").forEach(function (inp) {
      inp.checked = formState.selected.indexOf(inp.getAttribute("data-feed")) >= 0;
      inp.addEventListener("change", function () {
        var name = inp.getAttribute("data-feed");
        if (inp.checked) { if (formState.selected.indexOf(name) < 0) formState.selected.push(name); }
        else formState.selected = formState.selected.filter(function (x) { return x !== name; });
      });
    });
  }

  function runFormulation() {
    var cats = catalog();
    var sel = cats.filter(function (f) { return formState.selected.indexOf(f.Feed) >= 0; });
    if (sel.length === 0) { toast("Selecciona ingredientes", true); return; }
    var totalW = num(document.getElementById("form-total").value);
    if (totalW <= 0) { toast("Peso total inválido", true); return; }

    var cons = [];
    FORM_NUTRIENTS.forEach(function (n) {
      var mn = document.getElementById("min-" + n).value;
      var mx = document.getElementById("max-" + n).value;
      var minV = mn === "" ? null : num(mn);
      var maxV = mx === "" ? null : num(mx);
      if (minV !== null || maxV !== null) cons.push({ n: n, min: minV, max: maxV });
    });
    if (cons.length === 0) { toast("Define al menos un requerimiento (mínimo o máximo)", true); return; }

    var asFed = toAsFed(sel);
    var model = { optimize: "cost", opType: "min", constraints: {}, variables: {}, ints: {} };
    model.constraints.total = { equal: totalW };
    sel.forEach(function (f, i) {
      model.variables["v" + i] = { cost: num(f.Cost) / 1000, total: 1 };
    });
    cons.forEach(function (c, k) {
      var cMin = "c" + k + "min", cMax = "c" + k + "max";
      sel.forEach(function (f, i) {
        var v = num(asFed[i][c.n]);
        if (c.min !== null) model.variables["v" + i][cMin] = v;
        if (c.max !== null) model.variables["v" + i][cMax] = v;
      });
      if (c.min !== null) model.constraints[cMin] = { min: c.min * totalW };
      if (c.max !== null) model.constraints[cMax] = { max: c.max * totalW };
    });

    var r;
    try { r = solver.Solve(model); } catch (e) { r = { feasible: false }; }

    var right = document.getElementById("form-result");
    if (!r || !r.feasible) {
      right.innerHTML = '<p class="error">No hay solución factible con estos límites. Ajusta los requerimientos o añade ingredientes.</p>';
      return;
    }

    var html = '<div class="result-box"><p><strong>Costo total:</strong> $' + fmt(r.result) + "</p></div>";
    html += '<div class="scroll"><table><thead><tr><th>Ingrediente</th><th>kg</th><th>%</th></tr></thead><tbody>';
    var achieved = {};
    NUTRIENTS.forEach(function (n) { achieved[n] = 0; });
    var totalCost = 0;
    sel.forEach(function (f, i) {
      var x = num(r["v" + i]);
      if (x > 1e-6) {
        html += "<tr><td>" + esc(dName(f.Feed)) + "</td><td>" + fmt(x, 3) + "</td><td>" + fmt(x / totalW * 100, 1) + "%</td></tr>";
      }
      totalCost += x * num(f.Cost) / 1000;
      NUTRIENTS.forEach(function (n) { if (asFed[i][n] != null) achieved[n] += x * num(asFed[i][n]); });
    });
    html += "</tbody></table></div>";
    html += '<h3>Nutrientes logrados</h3><div class="scroll"><table><thead><tr><th>Nutriente</th><th>Valor</th></tr></thead><tbody>';
    NUTRIENTS.forEach(function (n) {
      if (n === "Cost" || n === "Forage") return;
      var v = achieved[n] / totalW;
      html += "<tr><td>" + esc(n) + "</td><td>" + fmt(v, 3) + " " + esc(UNITS[n] || "") + "</td></tr>";
    });
    html += "</tbody></table></div>";
    html += '<p class="muted">Costo calculado: $' + fmt(totalCost) + "</p>";
    right.innerHTML = html;
  }

  // ================= Suggestions =================
  var suggState = { ingredient: "", nutrients: ["CP", "TDN", "ME", "Ca", "P"], top: 5 };

  function renderSuggest() {
    var sec = document.getElementById("tab-suggest");
    sec.innerHTML = "";
    var grid = el('<div class="grid2"></div>');

    var left = el('<div class="card"></div>');
    left.appendChild(el('<h2>Ingrediente de referencia</h2>'));
    var cats = catalog();
    var sel = el('<select id="sugg-ing"></select>');
    sel.appendChild(el('<option value="">— selecciona —</option>'));
    cats.forEach(function (f) {
      var o = el('<option value="' + esc(f.Feed) + '">' + esc(dName(f.Feed)) + "</option>");
      if (f.Feed === suggState.ingredient) o.selected = true;
      sel.appendChild(o);
    });
    left.appendChild(sel);

    left.appendChild(el('<h3>Nutrientes a comparar</h3>'));
    var nc = el('<div class="checklist" style="max-height:220px"></div>');
    ["DM", "CP", "TDN", "ME", "Fat", "Ash", "NDF", "Starch", "Ca", "P", "Mg", "K", "LYS", "MET"].forEach(function (n) {
      var lab = el('<label><input type="checkbox" data-n="' + n + '"' + (suggState.nutrients.indexOf(n) >= 0 ? " checked" : "") + ">" + esc(n) + "</label>");
      nc.appendChild(lab);
    });
    left.appendChild(nc);

    left.appendChild(el('<h3>Número de sugerencias</h3>'));
    var topInput = el('<input type="number" id="sugg-top" value="' + suggState.top + '" min="1" max="50" style="max-width:120px">');
    left.appendChild(topInput);

    var btn = el('<button style="width:100%;margin-top:12px">Sugerir</button>');
    btn.addEventListener("click", runSuggest);
    left.appendChild(btn);

    var right = el('<div class="card"></div>');
    right.appendChild(el('<h2>Alternativas similares (y su precio)</h2>'));
    right.id = "sugg-result";
    right.appendChild(el('<p class="muted">Elige un ingrediente y pulsa "Sugerir".</p>'));

    grid.appendChild(left); grid.appendChild(right);
    sec.appendChild(grid);

    nc.querySelectorAll("input[data-n]").forEach(function (inp) {
      inp.addEventListener("change", function () {
        var n = inp.getAttribute("data-n");
        if (inp.checked) { if (suggState.nutrients.indexOf(n) < 0) suggState.nutrients.push(n); }
        else suggState.nutrients = suggState.nutrients.filter(function (x) { return x !== n; });
      });
    });
    sel.addEventListener("change", function () { suggState.ingredient = sel.value; });
    topInput.addEventListener("input", function () { suggState.top = Math.max(1, Math.min(50, num(topInput.value))); });
  }

  function runSuggest() {
    var name = document.getElementById("sugg-ing").value;
    if (!name) { toast("Selecciona un ingrediente", true); return; }
    var cats = catalog();
    var target = cats.find(function (f) { return f.Feed === name; });
    if (!target) { toast("Ingrediente no encontrado", true); return; }

    var nutrients = suggState.nutrients.filter(function (n) { return NUTRIENTS.indexOf(n) >= 0; });
    if (nutrients.length === 0) { toast("Selecciona al menos un nutriente", true); return; }

    var asFed = toAsFed(cats);

    function scale(vals) {
      var mean = 0, sd = 1, cnt = 0;
      vals.forEach(function (v) { if (v != null && isFinite(v)) { mean += v; cnt++; } });
      if (cnt > 0) mean /= cnt;
      var s = 0;
      vals.forEach(function (v) { if (v != null && isFinite(v)) s += (v - mean) * (v - mean); });
      if (cnt > 1) sd = Math.sqrt(s / (cnt - 1));
      if (sd === 0) sd = 1;
      return { mean: mean, sd: sd };
    }

    var sc = {};
    nutrients.forEach(function (n) {
      var vals = asFed.map(function (f) { return f[n]; });
      sc[n] = scale(vals);
    });

    var tIdx = cats.indexOf(target);
    var results = [];
    cats.forEach(function (f, i) {
      if (i === tIdx) return;
      var d2 = 0, cnt = 0;
      nutrients.forEach(function (n) {
        var a = asFed[tIdx][n], b = asFed[i][n];
        if (a == null || b == null) return;
        var z = ((num(a) - sc[n].mean) / sc[n].sd) - ((num(b) - sc[n].mean) / sc[n].sd);
        d2 += z * z; cnt++;
      });
      if (cnt === 0) return;
      results.push({ feed: f, distance: Math.sqrt(d2 / cnt) });
    });
    results.sort(function (a, b) { return a.distance - b.distance; });
    results = results.slice(0, suggState.top);

    var right = document.getElementById("sugg-result");
    var html = '<div class="scroll"><table><thead><tr><th>Ingrediente</th><th>Origen</th><th>Precio $/t</th><th>Similitud</th><th></th></tr></thead><tbody>';
    results.forEach(function (r) {
      var cheaper = num(r.feed.Cost) > 0 && num(target.Cost) > 0 && num(r.feed.Cost) < num(target.Cost);
      html += "<tr><td>" + esc(dName(r.feed.Feed)) + "</td><td>" + (r.feed.source === "user" ? "tuyo" : "ref") +
        "</td><td>" + fmt(r.feed.Cost, 0) + "</td><td>" + fmt(r.distance, 3) + "</td><td>" +
        (cheaper ? '<span class="badge cheap">más barato</span>' : "") + "</td></tr>";
    });
    html += "</tbody></table></div>";
    right.innerHTML = html;
  }

  // ---- initial render ----
  renderIngredients();
})();
