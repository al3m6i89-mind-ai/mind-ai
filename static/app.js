(function () {
  "use strict";

  // ---------- helpers ----------
  var $ = function (id) { return document.getElementById(id); };
  var els = {
    sidebar: $("sidebar"), scrim: $("scrim"), convList: $("convList"), search: $("search"),
    newChat: $("newChat"), title: $("convTitle"), renameCurrent: $("renameCurrent"),
    messages: $("messages"), pending: $("pending"), composer: $("composer"), input: $("input"),
    send: $("send"), attachFile: $("attachFile"), attachImage: $("attachImage"),
    fileInput: $("fileInput"), imageInput: $("imageInput"), dropZone: $("dropZone"),
    dropOverlay: $("dropOverlay"), aiStatus: $("aiStatus"), themeToggle: $("themeToggle"),
    langToggle: $("langToggle"), toasts: $("toasts"),
  };

  function store(key, value) {
    try { if (value === undefined) return localStorage.getItem(key); localStorage.setItem(key, value); } catch (e) { return null; }
  }

  var lang = store("lang") === "en" ? "en" : "ar";
  function t(key, vars) {
    var s = (I18N[lang] && I18N[lang][key]) || I18N.ar[key] || key;
    if (vars) Object.keys(vars).forEach(function (k) { s = s.split("{" + k + "}").join(vars[k]); });
    return s;
  }

  function h(tag, attrs, children) {
    var el = document.createElement(tag);
    if (attrs) Object.keys(attrs).forEach(function (k) {
      if (k === "class") el.className = attrs[k];
      else if (k === "text") el.textContent = attrs[k];
      else if (k === "html") el.innerHTML = attrs[k];
      else if (k.slice(0, 2) === "on") el.addEventListener(k.slice(2), attrs[k]);
      else if (attrs[k] !== null && attrs[k] !== undefined && attrs[k] !== false) el.setAttribute(k, attrs[k]);
    });
    (children || []).forEach(function (c) { if (c) el.appendChild(typeof c === "string" ? document.createTextNode(c) : c); });
    return el;
  }

  var ICONS = {
    edit: '<svg viewBox="0 0 24 24"><path d="M4 20h4L19 9l-4-4L4 16v4z"/></svg>',
    trash: '<svg viewBox="0 0 24 24"><path d="M4 7h16M10 11v6M14 11v6M6 7l1 12a2 2 0 002 2h6a2 2 0 002-2l1-12M9 7V4h6v3"/></svg>',
    open: '<svg viewBox="0 0 24 24"><path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 01-1 1H5a1 1 0 01-1-1V7a1 1 0 011-1h5"/></svg>',
    x: '<svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6L6 18"/></svg>',
    bot: '<svg viewBox="0 0 24 24"><path d="M12 3l2.5 5.5L20 11l-5.5 2.5L12 19l-2.5-5.5L4 11l5.5-2.5z"/></svg>',
  };

  function formatSize(n) {
    if (n < 1024) return n + " B";
    if (n < 1024 * 1024) return (n / 1024).toFixed(n < 10240 ? 1 : 0) + " KB";
    return (n / 1024 / 1024).toFixed(1) + " MB";
  }

  function toast(msg, isError) {
    var el = h("div", { class: "toast" + (isError ? " error" : ""), text: msg, role: isError ? "alert" : "status" });
    els.toasts.appendChild(el);
    setTimeout(function () { el.remove(); }, isError ? 7000 : 3500);
  }

  function errorText(err, vars) {
    if (!err) return t("err_network");
    var key = "err_" + err.code;
    if (I18N.ar[key]) return t(key, vars || {});
    return t("err_generic", { message: err.message || err.code });
  }

  async function api(method, url, body) {
    var opts = { method: method, headers: {} };
    if (body !== undefined) { opts.headers["Content-Type"] = "application/json"; opts.body = JSON.stringify(body); }
    var res;
    try { res = await fetch(url, opts); } catch (e) { throw { code: "network", message: t("serverDown") }; }
    if (res.status === 204) return null;
    var data = null;
    try { data = await res.json(); } catch (e) { /* non-JSON */ }
    if (!res.ok) throw (data && data.error) || { code: "http_" + res.status, message: "HTTP " + res.status };
    return data;
  }

  // ---------- state ----------
  var state = {
    conversations: [],
    currentId: null,
    messages: [],
    pending: [],        // {localId, file, kind, progress, status: uploading|uploaded|failed, server, previewUrl}
    streaming: null,    // AbortController while a reply streams
    maxUploadMb: 50,
  };

  // ---------- i18n + theme ----------
  function applyLang() {
    document.documentElement.lang = lang;
    document.documentElement.dir = lang === "ar" ? "rtl" : "ltr";
    document.title = t("appName");
    document.querySelectorAll("[data-i18n]").forEach(function (el) { el.textContent = t(el.getAttribute("data-i18n")); });
    document.querySelectorAll("[data-i18n-attr]").forEach(function (el) {
      el.getAttribute("data-i18n-attr").split(";").forEach(function (pair) {
        var p = pair.split(":"); el.setAttribute(p[0], t(p[1]));
      });
    });
    els.langToggle.textContent = t("langSwitch");
    updateThemeLabel();
    renderTitle();
    renderConversations();
    renderMessages();
    renderPending();
    checkHealth();
  }

  function currentTheme() { var v = store("theme"); return v === "light" || v === "dark" ? v : "system"; }
  function updateThemeLabel() {
    var th = currentTheme();
    els.themeToggle.textContent = t(th === "light" ? "themeLight" : th === "dark" ? "themeDark" : "themeSystem");
  }
  els.themeToggle.addEventListener("click", function () {
    var next = { system: "light", light: "dark", dark: "system" }[currentTheme()];
    if (next === "system") { document.documentElement.removeAttribute("data-theme"); try { localStorage.removeItem("theme"); } catch (e) {} }
    else { document.documentElement.setAttribute("data-theme", next); store("theme", next); }
    updateThemeLabel();
  });
  els.langToggle.addEventListener("click", function () {
    lang = lang === "ar" ? "en" : "ar";
    store("lang", lang);
    applyLang();
  });

  // ---------- dialog ----------
  function ask(opts) {
    var dlg = $("dialog");
    $("dialogTitle").textContent = opts.title;
    $("dialogText").textContent = opts.text || "";
    $("dialogText").hidden = !opts.text;
    var input = $("dialogInput");
    input.hidden = opts.value === undefined;
    input.value = opts.value || "";
    $("dialogOk").textContent = opts.ok;
    $("dialogOk").className = "btn" + (opts.danger ? " danger" : "");
    $("dialogCancel").textContent = t("cancel");
    return new Promise(function (resolve) {
      dlg.addEventListener("close", function onClose() {
        dlg.removeEventListener("close", onClose);
        if (dlg.returnValue !== "ok") return resolve(null);
        resolve(opts.value === undefined ? true : input.value.trim() || null);
      });
      dlg.returnValue = "";
      dlg.showModal();
      if (!input.hidden) { input.focus(); input.select(); }
    });
  }

  // ---------- AI status ----------
  async function checkHealth() {
    els.aiStatus.className = "ai-status";
    els.aiStatus.innerHTML = '<span class="dot"></span><span>' + escapeHtml(t("aiChecking")) + "</span>";
    try {
      var data = await api("GET", "/api/health");
      state.maxUploadMb = data.max_upload_mb;
      var ai = data.ai, msg;
      if (ai.available) msg = escapeHtml(t("aiOk", { model: ai.model }));
      else if (ai.reason === "model_missing") msg = t("aiBadModel", { model: escapeHtml(ai.model) });
      else if (ai.reason === "missing_api_key") msg = escapeHtml(t("aiBadKey"));
      else msg = escapeHtml(t("aiBadOllama"));
      els.aiStatus.className = "ai-status " + (ai.available ? "ok" : "bad");
      els.aiStatus.innerHTML = '<span class="dot"></span><span>' + msg + "</span>";
    } catch (e) {
      els.aiStatus.className = "ai-status bad";
      els.aiStatus.innerHTML = '<span class="dot"></span><span>' + escapeHtml(t("serverDown")) + "</span>";
    }
  }

  // ---------- sidebar ----------
  function openSidebar(open) {
    els.sidebar.classList.toggle("open", open);
    els.scrim.hidden = !open;
  }
  $("openSidebar").addEventListener("click", function () { openSidebar(true); });
  $("closeSidebar").addEventListener("click", function () { openSidebar(false); });
  els.scrim.addEventListener("click", function () { openSidebar(false); });

  async function loadConversations() {
    var q = els.search.value.trim();
    try {
      state.conversations = await api("GET", "/api/conversations" + (q ? "?q=" + encodeURIComponent(q) : ""));
    } catch (e) { toast(errorText(e), true); }
    renderConversations();
  }

  var searchTimer = null;
  els.search.addEventListener("input", function () {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(loadConversations, 200);
  });

  function renderConversations() {
    els.convList.innerHTML = "";
    if (!state.conversations.length) {
      els.convList.appendChild(h("div", { class: "conv-empty", text: els.search.value.trim() ? t("noResults") : t("noConversations") }));
      return;
    }
    state.conversations.forEach(function (c) {
      var item = h("div", { class: "conv-item" + (c.id === state.currentId ? " active" : ""), "data-id": c.id }, [
        h("button", { class: "conv-open", type: "button", dir: "auto", text: c.title, title: c.title,
          onclick: function () { selectConversation(c.id); openSidebar(false); } }),
        h("div", { class: "conv-actions" }, [
          h("button", { type: "button", "aria-label": t("rename"), title: t("rename"), html: ICONS.edit,
            onclick: function () { renameConversation(c.id); } }),
          h("button", { type: "button", "aria-label": t("delete"), title: t("delete"), html: ICONS.trash,
            onclick: function () { deleteConversation(c.id); } }),
        ]),
      ]);
      els.convList.appendChild(item);
    });
  }

  function renderTitle() {
    var c = state.conversations.find(function (x) { return x.id === state.currentId; });
    els.title.textContent = c ? c.title : t("newChat");
    els.title.setAttribute("dir", "auto");
    els.renameCurrent.hidden = !c;
  }

  async function renameConversation(id) {
    var c = state.conversations.find(function (x) { return x.id === id; });
    if (!c) return;
    var title = await ask({ title: t("renameTitle"), value: c.title, ok: t("save") });
    if (!title || title === c.title) return;
    try {
      await api("PATCH", "/api/conversations/" + id, { title: title });
      c.title = title;
      renderConversations(); renderTitle();
    } catch (e) { toast(errorText(e), true); }
  }
  els.renameCurrent.addEventListener("click", function () { if (state.currentId) renameConversation(state.currentId); });

  async function deleteConversation(id) {
    var ok = await ask({ title: t("deleteConvTitle"), text: t("deleteConvText"), ok: t("confirmDelete"), danger: true });
    if (!ok) return;
    try {
      await api("DELETE", "/api/conversations/" + id);
      if (id === state.currentId) startNewChat();
      await loadConversations();
    } catch (e) { toast(errorText(e), true); }
  }

  function startNewChat() {
    if (state.streaming) state.streaming.abort();
    discardPending();
    state.currentId = null;
    state.messages = [];
    setRoute(null);
    renderTitle(); renderConversations(); renderMessages();
    els.input.focus();
  }
  els.newChat.addEventListener("click", function () { startNewChat(); openSidebar(false); });

  async function selectConversation(id) {
    if (state.streaming) state.streaming.abort();
    discardPending();
    state.currentId = id;
    setRoute(id);
    renderConversations(); renderTitle();
    try {
      var data = await api("GET", "/api/conversations/" + id + "/messages");
      state.messages = data.messages;
      // Files uploaded but never sent are restored as chips so they can be sent or removed.
      state.pending = data.pending_attachments.map(function (a) {
        return { localId: a.id, kind: a.kind, status: "uploaded", progress: 100, server: a, previewUrl: a.kind === "image" ? a.url : null };
      });
    } catch (e) {
      if (e.code === "not_found") { startNewChat(); return; }
      toast(errorText(e), true);
      state.messages = [];
    }
    renderMessages(); renderPending();
    scrollToBottom(true);
  }

  function setRoute(id) {
    var hash = id ? "#c=" + id : "";
    if (location.hash !== hash) history.replaceState(null, "", location.pathname + hash);
  }

  // Shared in-flight promise so a file and an image picked at the same moment land in ONE new conversation.
  var creating = null;
  function ensureConversation() {
    if (state.currentId) return Promise.resolve(state.currentId);
    if (!creating) {
      creating = api("POST", "/api/conversations", {}).then(function (c) {
        state.currentId = c.id;
        state.conversations.unshift(c);
        setRoute(c.id);
        renderConversations(); renderTitle();
        return c.id;
      }).finally(function () { creating = null; });
    }
    return creating;
  }

  // ---------- messages ----------
  function scrollToBottom(force) {
    var m = els.messages;
    var near = m.scrollHeight - m.scrollTop - m.clientHeight < 160;
    if (force || near) m.scrollTop = m.scrollHeight;
  }

  function fileIconClass(a) {
    var label = (a.type_label || "").toLowerCase();
    if (label === "pdf") return "pdf";
    if (label === "word" || label === "powerpoint" || label === "excel") return label;
    return "text";
  }

  function attachmentCard(a, opts) {
    opts = opts || {};
    var statusKey = a.status === "uploading" ? "statusUploading" : a.status === "failed" ? "statusFailed" : "statusUploaded";
    var visual = a.kind === "image" && (a.previewUrl || a.url)
      ? h("img", { class: "att-thumb", src: a.previewUrl || a.url, alt: "" })
      : h("div", { class: "att-icon " + fileIconClass(a), text: (a.ext || "").toUpperCase().slice(0, 4) });
    var actions = h("div", { class: "att-actions" });
    if (a.url) actions.appendChild(h("a", { href: a.url, target: "_blank", rel: "noopener", "aria-label": t("open"), title: t("open"), html: ICONS.open }));
    if (opts.onRemove) actions.appendChild(h("button", { type: "button", "aria-label": opts.removeLabel || t("remove"), title: opts.removeLabel || t("remove"),
      html: opts.removeIcon || ICONS.x, onclick: opts.onRemove }));
    var meta = h("div", { class: "att-meta" }, [
      h("span", { class: "att-name", dir: "auto", text: a.name, title: a.name }),
      h("span", { class: "att-sub", text: (a.type_label || a.ext.toUpperCase()) + " · " + formatSize(a.size) }),
      h("span", { class: "att-status " + a.status, text: t(statusKey, { p: a.progress || 0 }) }),
    ]);
    if (a.status === "uploading") {
      var bar = h("div", { class: "progress" }, [h("i", { style: "width:" + (a.progress || 0) + "%" })]);
      meta.appendChild(bar);
    }
    return h("div", { class: "att-card" }, [visual, meta, actions]);
  }

  function renderEmpty() {
    var sugs = ["sug1", "sug2", "sug3", "sug4"].map(function (k) {
      return h("button", { class: "suggestion", type: "button", dir: "auto", text: t(k),
        onclick: function () { els.input.value = t(k); autoGrow(); els.input.focus(); updateSend(); } });
    });
    return h("div", { class: "empty" }, [
      h("img", { src: "/static/icon.svg", alt: "" }),
      h("h2", { text: t("emptyTitle") }),
      h("p", { text: t("emptyText") }),
      h("div", { class: "suggestions" }, sugs),
    ]);
  }

  function messageNode(m) {
    var wrap = h("div", { class: "msg " + m.role, "data-id": m.id || "" });
    if (m.role === "assistant") {
      wrap.appendChild(h("div", { class: "msg-head" }, [
        h("span", { class: "avatar", html: ICONS.bot }), h("span", { text: t("assistant") }),
      ]));
    }
    if (m.attachments && m.attachments.length) {
      var list = h("div", { class: "att-list" });
      m.attachments.forEach(function (a) {
        list.appendChild(attachmentCard(a, { onRemove: function () { deleteSentAttachment(a); }, removeLabel: t("delete"), removeIcon: ICONS.trash }));
      });
      wrap.appendChild(list);
      wrap.appendChild(h("div", { class: "msg-note", text: t("uploadedNote") }));
    }
    if (m.role === "user") {
      if (m.content) wrap.appendChild(h("div", { class: "bubble", dir: "auto", text: m.content }));
    } else {
      var bubble = h("div", { class: "bubble", dir: "auto" });
      if (m.status === "streaming" && !m.content) bubble.innerHTML = '<span class="typing"><span></span><span></span><span></span></span>';
      else bubble.innerHTML = renderMarkdown(m.content);
      if (m.status === "streaming" && m.content) bubble.classList.add("cursor");
      wrap.appendChild(bubble);
      if (m.status === "error") {
        wrap.appendChild(h("div", { class: "msg-error", role: "alert" }, [
          h("span", { text: errorText(m.error) }),
          isLastMessage(m) ? h("button", { class: "btn small", type: "button", text: t("retry"), onclick: retry }) : null,
        ]));
      } else if (m.status === "stopped") {
        wrap.appendChild(h("div", { class: "msg-note" }, [
          t("stopped") + " ",
          isLastMessage(m) ? h("button", { class: "btn ghost small", type: "button", text: t("retry"), onclick: retry }) : null,
        ]));
      }
    }
    return wrap;
  }

  function isLastMessage(m) { return state.messages[state.messages.length - 1] === m && !state.streaming; }

  function renderMessages() {
    els.messages.innerHTML = "";
    if (!state.messages.length) { els.messages.appendChild(renderEmpty()); return; }
    var thread = h("div", { class: "thread" });
    state.messages.forEach(function (m) { thread.appendChild(messageNode(m)); });
    els.messages.appendChild(thread);
  }

  function updateMessageNode(m) {
    var old = els.messages.querySelector('.msg[data-id="' + m.id + '"]');
    if (old) old.replaceWith(messageNode(m)); else renderMessages();
  }

  async function deleteSentAttachment(a) {
    var ok = await ask({ title: t("deleteFileTitle"), text: t("deleteFileText", { name: a.name }), ok: t("confirmDelete"), danger: true });
    if (!ok) return;
    try {
      await api("DELETE", "/api/attachments/" + a.id);
      state.messages.forEach(function (m) {
        if (m.attachments) m.attachments = m.attachments.filter(function (x) { return x.id !== a.id; });
      });
      renderMessages();
    } catch (e) { toast(errorText(e), true); }
  }

  // ---------- attachments (pending) ----------
  function renderPending() {
    els.pending.innerHTML = "";
    els.pending.hidden = !state.pending.length;
    state.pending.forEach(function (p) {
      var a = p.server ? Object.assign({}, p.server, { status: p.status, progress: p.progress, previewUrl: p.previewUrl })
        : { name: p.file.name, ext: (p.file.name.split(".").pop() || "").toLowerCase(), size: p.file.size, kind: p.kind,
            status: p.status, progress: p.progress, previewUrl: p.previewUrl, type_label: null };
      els.pending.appendChild(attachmentCard(a, { onRemove: function () { removePending(p); } }));
    });
    updateSend();
  }

  async function removePending(p) {
    if (p.xhr) p.xhr.abort();
    state.pending = state.pending.filter(function (x) { return x !== p; });
    if (p.previewUrl && p.previewUrl.indexOf("blob:") === 0) URL.revokeObjectURL(p.previewUrl);
    renderPending();
    if (p.server) {
      try { await api("DELETE", "/api/attachments/" + p.server.id); } catch (e) { toast(errorText(e), true); }
    }
  }

  function discardPending() {
    // Leaving a chat keeps uploaded-but-unsent files on the server; they come back when the chat is reopened.
    state.pending.forEach(function (p) { if (p.xhr) p.xhr.abort(); });
    state.pending = [];
    renderPending();
  }

  var SUPPORTED_EXT = ["pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "txt", "csv", "md", "markdown", "jpg", "jpeg", "png", "webp"];
  var IMAGE_EXT = ["jpg", "jpeg", "png", "webp"];

  async function addFiles(fileList) {
    var files = Array.prototype.slice.call(fileList || []);
    if (!files.length) return;
    var accepted = [];
    files.forEach(function (f) {
      var ext = (f.name.indexOf(".") > -1 ? f.name.split(".").pop() : "").toLowerCase();
      if (SUPPORTED_EXT.indexOf(ext) === -1) toast(t("err_unsupported_type", { name: f.name }), true);
      else if (f.size > state.maxUploadMb * 1024 * 1024) toast(t("err_too_large", { name: f.name, max: state.maxUploadMb }), true);
      else if (f.size === 0) toast(t("err_empty_file", { name: f.name }), true);
      else accepted.push({ file: f, ext: ext });
    });
    if (!accepted.length) return;
    var cid;
    try { cid = await ensureConversation(); } catch (e) { toast(errorText(e), true); return; }
    accepted.forEach(function (x) {
      var isImage = IMAGE_EXT.indexOf(x.ext) > -1;
      var p = { localId: Math.random().toString(36).slice(2), file: x.file, kind: isImage ? "image" : "file",
        progress: 0, status: "uploading", server: null, previewUrl: isImage ? URL.createObjectURL(x.file) : null };
      state.pending.push(p);
      upload(cid, p);
    });
    renderPending();
  }

  function upload(cid, p) {
    var xhr = new XMLHttpRequest();
    p.xhr = xhr;
    var form = new FormData();
    form.append("file", p.file, p.file.name);
    xhr.upload.onprogress = function (e) {
      if (!e.lengthComputable) return;
      p.progress = Math.min(99, Math.round((e.loaded / e.total) * 100));
      renderPending();
    };
    xhr.onload = function () {
      p.xhr = null;
      var data = null;
      try { data = JSON.parse(xhr.responseText); } catch (e) {}
      if (xhr.status === 201 && data) {
        p.server = data; p.status = "uploaded"; p.progress = 100;
      } else {
        state.pending = state.pending.filter(function (x) { return x !== p; });
        toast(errorText(data && data.error, { name: p.file.name, max: state.maxUploadMb }), true);
      }
      renderPending();
    };
    xhr.onerror = function () {
      p.xhr = null;
      state.pending = state.pending.filter(function (x) { return x !== p; });
      toast(t("serverDown"), true);
      renderPending();
    };
    xhr.open("POST", "/api/conversations/" + cid + "/attachments");
    xhr.send(form);
  }

  els.attachFile.addEventListener("click", function () { els.fileInput.click(); });
  els.attachImage.addEventListener("click", function () { els.imageInput.click(); });
  els.fileInput.addEventListener("change", function () { addFiles(els.fileInput.files); els.fileInput.value = ""; });
  els.imageInput.addEventListener("change", function () { addFiles(els.imageInput.files); els.imageInput.value = ""; });

  var dragDepth = 0;
  document.addEventListener("dragenter", function (e) {
    if (!e.dataTransfer || Array.prototype.indexOf.call(e.dataTransfer.types, "Files") === -1) return;
    e.preventDefault(); dragDepth++; els.dropOverlay.hidden = false;
  });
  document.addEventListener("dragover", function (e) { if (!els.dropOverlay.hidden) e.preventDefault(); });
  document.addEventListener("dragleave", function () { dragDepth = Math.max(0, dragDepth - 1); if (!dragDepth) els.dropOverlay.hidden = true; });
  document.addEventListener("drop", function (e) {
    if (els.dropOverlay.hidden) return;
    e.preventDefault(); dragDepth = 0; els.dropOverlay.hidden = true;
    addFiles(e.dataTransfer.files);
  });
  els.input.addEventListener("paste", function (e) {
    var files = e.clipboardData && e.clipboardData.files;
    if (files && files.length) { e.preventDefault(); addFiles(files); }
  });

  // ---------- composer ----------
  function autoGrow() {
    els.input.style.height = "auto";
    els.input.style.height = Math.min(els.input.scrollHeight, 200) + "px";
  }

  function updateSend() {
    if (state.streaming) {
      els.send.disabled = false;
      els.send.classList.add("stop");
      els.send.setAttribute("aria-label", t("stop")); els.send.title = t("stop");
      return;
    }
    els.send.classList.remove("stop");
    els.send.setAttribute("aria-label", t("send")); els.send.title = t("send");
    var hasContent = els.input.value.trim() || state.pending.some(function (p) { return p.status === "uploaded"; });
    els.send.disabled = !hasContent;
  }

  els.input.addEventListener("input", function () { autoGrow(); updateSend(); });
  els.input.addEventListener("keydown", function (e) {
    if (e.key === "Enter" && !e.shiftKey && !e.isComposing) { e.preventDefault(); submit(); }
  });
  els.composer.addEventListener("submit", function (e) { e.preventDefault(); submit(); });

  async function submit() {
    if (state.streaming) { state.streaming.abort(); return; }
    var text = els.input.value.trim();
    if (state.pending.some(function (p) { return p.status === "uploading"; })) { toast(t("waitUploads")); return; }
    var ready = state.pending.filter(function (p) { return p.status === "uploaded"; });
    if (!text && !ready.length) return;
    var cid;
    try { cid = await ensureConversation(); } catch (e) { toast(errorText(e), true); return; }

    els.input.value = ""; autoGrow();
    var sentPending = state.pending;
    state.pending = [];
    renderPending();
    var ok = await streamFrom("/api/conversations/" + cid + "/messages",
      { content: text, attachment_ids: ready.map(function (p) { return p.server.id; }) });
    if (ok === "rejected") {
      // The server refused the message itself (nothing saved): give the text and files back.
      els.input.value = text; autoGrow();
      state.pending = sentPending; renderPending();
    }
  }

  async function retry() {
    if (!state.currentId || state.streaming) return;
    var last = state.messages[state.messages.length - 1];
    if (last && last.role === "assistant") state.messages.pop();
    renderMessages();
    await streamFrom("/api/conversations/" + state.currentId + "/regenerate", undefined);
  }

  async function streamFrom(url, body) {
    var controller = new AbortController();
    state.streaming = controller;
    updateSend();
    var placeholder = { id: "pending-" + Date.now(), role: "assistant", content: "", status: "streaming", attachments: [] };
    var res;
    try {
      res = await fetch(url, {
        method: "POST", signal: controller.signal,
        headers: body === undefined ? {} : { "Content-Type": "application/json" },
        body: body === undefined ? undefined : JSON.stringify(body),
      });
    } catch (e) {
      state.streaming = null; updateSend();
      toast(t("serverDown"), true);
      return "rejected";
    }
    if (!res.ok) {
      state.streaming = null; updateSend();
      var data = null; try { data = await res.json(); } catch (e) {}
      toast(errorText(data && data.error), true);
      return "rejected";
    }

    var reader = res.body.getReader();
    var decoder = new TextDecoder();
    var buffer = "", finished = false;
    var renderQueued = false;
    function queueRender() {
      if (renderQueued) return;
      renderQueued = true;
      requestAnimationFrame(function () { renderQueued = false; updateMessageNode(placeholder); scrollToBottom(); });
    }

    function handle(event, data) {
      if (event === "user") {
        state.messages.push(data.message);
        var c = state.conversations.find(function (x) { return x.id === state.currentId; });
        if (c) {
          c.title = data.title;
          state.conversations = [c].concat(state.conversations.filter(function (x) { return x !== c; }));
        }
        renderConversations(); renderTitle();
      } else if (event === "start") {
        placeholder.id = data.id;
        state.messages.push(placeholder);
        renderMessages(); scrollToBottom(true);
      } else if (event === "delta") {
        placeholder.content += data.text;
        queueRender();
      } else if (event === "done" || event === "error") {
        finished = true;
        Object.assign(placeholder, data);
      }
    }

    try {
      while (true) {
        var chunk = await reader.read();
        if (chunk.done) break;
        buffer += decoder.decode(chunk.value, { stream: true });
        var idx;
        while ((idx = buffer.indexOf("\n\n")) !== -1) {
          var raw = buffer.slice(0, idx); buffer = buffer.slice(idx + 2);
          var ev = "message", dataLines = [];
          raw.split("\n").forEach(function (line) {
            if (line.indexOf("event:") === 0) ev = line.slice(6).trim();
            else if (line.indexOf("data:") === 0) dataLines.push(line.slice(5).trim());
          });
          if (dataLines.length) handle(ev, JSON.parse(dataLines.join("\n")));
        }
      }
    } catch (e) {
      if (!finished) {
        placeholder.status = e.name === "AbortError" ? "stopped" : "error";
        if (placeholder.status === "error") placeholder.error = null;
      }
    }
    if (!finished && placeholder.status === "streaming") { placeholder.status = "error"; placeholder.error = null; }
    state.streaming = null;
    if (state.messages.indexOf(placeholder) === -1 && placeholder.status !== "streaming") state.messages.push(placeholder);
    renderMessages(); scrollToBottom();
    updateSend();
    return "sent";
  }

  // ---------- boot ----------
  async function boot() {
    applyLang();
    autoGrow();
    await loadConversations();
    var m = location.hash.match(/^#c=([0-9a-f]+)$/);
    if (m && state.conversations.some(function (c) { return c.id === m[1]; })) await selectConversation(m[1]);
    else renderMessages();
    els.input.focus();
  }
  boot();
})();
