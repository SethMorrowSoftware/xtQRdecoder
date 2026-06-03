// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Seth Morrow
// Part of xtQRdecoder, an xTalk port of the ZXing QR decoder.
// ZXing is Apache-2.0; see the NOTICE file for full attribution.
// =====================================================================
// qr_demo.js -- the interactive client for the scanner page (qr_demo.lc).
//
// Progressive enhancement: the page works as a plain form without this script.
// With it, the form becomes a tabbed, drag-and-drop, paste- and camera-aware
// scanner that decodes asynchronously (POST ?api=1 -> JSON) so the page never
// reloads and shows a live loading state. The decoded payload is UNTRUSTED, so
// every value derived from it is inserted with textContent (never innerHTML) and
// link hrefs are restricted to a small scheme allow-list.
// =====================================================================
"use strict";

(function () {
  var doc = document;
  doc.documentElement.classList.remove("no-js");
  doc.documentElement.classList.add("js");

  // ---- element refs -------------------------------------------------------
  var $ = function (id) { return doc.getElementById(id); };
  var form = $("qform");
  if (!form) return; // library-missing page etc.

  var tabs = Array.prototype.slice.call(doc.querySelectorAll(".tab"));
  var panels = {
    upload: $("panel-upload"),
    camera: $("panel-camera"),
    url: $("panel-url")
  };
  var dropzone = $("dropzone");
  var fileInput = $("fileInput");
  var camInput = $("camInput");
  var urlInput = $("urlInput");
  var previewWrap = $("previewWrap");
  var previewImg = $("previewImg");
  var previewClear = $("previewClear");
  var decodeBtn = $("decodeBtn");
  var resetBtn = $("resetBtn");
  var spinner = decodeBtn.querySelector(".spinner");
  var resultZone = $("result");
  var historyEl = $("history");
  var toastEl = $("toast");

  // camera bits
  var camLive = $("camLive");
  var camVideo = $("camVideo");
  var camStartBtn = $("camStart");
  var camShotBtn = $("camShot");
  var camStopBtn = $("camStop");

  var state = { file: null, previewUrl: null, objectUrl: null, busy: false, stream: null, resultShown: false };
  var activeTab = "upload";
  var HKEY = "xtqr.history.v1";
  // the two-pane layout (sticky form + results column) kicks in on wide screens;
  // the results column then needs a resting state so it never looks empty.
  var mqWide = window.matchMedia("(min-width: 900px)");

  // ---- tiny helpers -------------------------------------------------------
  function setHidden(elm, hide) { if (elm) elm.hidden = !!hide; }

  function toast(msg) {
    if (!toastEl) return;
    toastEl.textContent = msg;
    toastEl.hidden = false;
    // force reflow so the transition runs each time
    void toastEl.offsetWidth;
    toastEl.classList.add("show");
    clearTimeout(toast._t);
    toast._t = setTimeout(function () {
      toastEl.classList.remove("show");
      setTimeout(function () { toastEl.hidden = true; }, 220);
    }, 1900);
  }

  function copyText(text) {
    var done = function () { toast("Copied to clipboard"); };
    var fail = function () { toast("Copy failed"); };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done, fail);
      return;
    }
    try {
      var ta = doc.createElement("textarea");
      ta.value = text;
      ta.setAttribute("readonly", "");
      ta.style.position = "absolute";
      ta.style.left = "-9999px";
      doc.body.appendChild(ta);
      ta.select();
      doc.execCommand("copy");
      doc.body.removeChild(ta);
      done();
    } catch (e) { fail(); }
  }

  // decode a base64(UTF-8) blob from the JSON API back to a JS string
  function b64utf8(b64) {
    if (!b64) return "";
    try {
      var bin = atob(b64);
      var bytes = new Uint8Array(bin.length);
      for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
      return new TextDecoder("utf-8").decode(bytes);
    } catch (e) { return ""; }
  }

  // build an element: el("div", {class:"x"}, child, "text", ...)
  function el(tag, attrs) {
    var n = doc.createElement(tag);
    if (attrs) {
      for (var k in attrs) {
        if (!Object.prototype.hasOwnProperty.call(attrs, k)) continue;
        if (k === "class") n.className = attrs[k];
        else if (k === "text") n.textContent = attrs[k];
        else if (k === "html") n.innerHTML = attrs[k]; // ONLY for our static icons
        else if (attrs[k] != null) n.setAttribute(k, attrs[k]);
      }
    }
    for (var i = 2; i < arguments.length; i++) {
      var c = arguments[i];
      if (c == null) continue;
      n.appendChild(typeof c === "string" ? doc.createTextNode(c) : c);
    }
    return n;
  }

  // ---- icons (static, safe to inline) ------------------------------------
  var I = {
    globe: "<circle cx='12' cy='12' r='9'/><path d='M3 12h18M12 3c2.5 2.6 2.5 15.4 0 18M12 3c-2.5 2.6-2.5 15.4 0 18'/>",
    wifi: "<path d='M2 8.5a16 16 0 0 1 20 0M5 12a11 11 0 0 1 14 0M8.5 15.5a6 6 0 0 1 7 0'/><circle cx='12' cy='19' r='1.1' fill='currentColor' stroke='none'/>",
    mail: "<rect x='3' y='5' width='18' height='14' rx='2'/><path d='M3.5 6.5 12 13l8.5-6.5'/>",
    phone: "<path d='M5 3h3l2 5-2.5 1.5a12 12 0 0 0 5 5L17 16l5 2v3a2 2 0 0 1-2 2A18 18 0 0 1 3 5a2 2 0 0 1 2-2Z'/>",
    chat: "<path d='M4 5h16a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H9l-5 4V7a2 2 0 0 1 2-2Z'/>",
    user: "<circle cx='12' cy='8' r='4'/><path d='M4 21a8 8 0 0 1 16 0'/>",
    cal: "<rect x='3' y='4.5' width='18' height='16' rx='2'/><path d='M3 9h18M8 2.5v4M16 2.5v4'/>",
    pin: "<path d='M12 22s7-6.2 7-12a7 7 0 1 0-14 0c0 5.8 7 12 7 12Z'/><circle cx='12' cy='10' r='2.6'/>",
    text: "<path d='M5 6h14M5 6V4.5h14V6M12 6v13M9.5 19h5'/>",
    open: "<path d='M14 4h6v6M20 4l-9 9'/><path d='M19 13v6a1.5 1.5 0 0 1-1.5 1.5H5.5A1.5 1.5 0 0 1 4 19V6.5A1.5 1.5 0 0 1 5.5 5H11'/>",
    copy: "<rect x='9' y='9' width='12' height='12' rx='2'/><path d='M5 15H4.5A1.5 1.5 0 0 1 3 13.5V4.5A1.5 1.5 0 0 1 4.5 3h9A1.5 1.5 0 0 1 15 4.5V5'/>",
    download: "<path d='M12 3v12m0 0 4.5-4.5M12 15l-4.5-4.5'/><path d='M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2'/>"
  };
  function icon(name) {
    var span = doc.createElement("span");
    span.className = "ico";
    span.innerHTML = "<svg viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='1.7' stroke-linecap='round' stroke-linejoin='round' width='100%' height='100%'>" + (I[name] || I.text) + "</svg>";
    return span;
  }

  // ---- url scheme allow-list ---------------------------------------------
  function safeHref(u, schemes) {
    var s = String(u).trim();
    var m = /^([a-z][a-z0-9+.\-]*):/i.exec(s);
    var scheme = m ? m[1].toLowerCase() : "";
    if (!m) return null;
    if (schemes.indexOf(scheme) === -1) return null;
    return s;
  }

  // ---- content classification --------------------------------------------
  // every parser returns { kind, title, icon, fields?, text?, actions? }
  function classify(text) {
    var t = String(text);
    var trimmed = t.trim();
    var low = trimmed.toLowerCase();

    if (/^https?:\/\//i.test(trimmed)) return cWebsite(trimmed, trimmed);
    if (/^www\.[^\s]+\.[^\s]{2,}/i.test(trimmed) && !/\s/.test(trimmed)) return cWebsite("https://" + trimmed, trimmed);
    if (low.indexOf("wifi:") === 0) return cWifi(trimmed);
    if (low.indexOf("mailto:") === 0) return cEmail(trimmed.slice(7).split("?")[0], trimmed);
    if (/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(trimmed)) return cEmail(trimmed, "mailto:" + trimmed);
    if (low.indexOf("tel:") === 0) return cPhone(trimmed.slice(4), trimmed);
    if (low.indexOf("smsto:") === 0 || low.indexOf("sms:") === 0) return cSms(trimmed);
    if (low.indexOf("mecard:") === 0) return cMeCard(trimmed);
    if (low.indexOf("begin:vcard") === 0) return cVCard(t);
    if (low.indexOf("begin:vevent") === 0 || low.indexOf("begin:vcalendar") === 0) return cEvent(t);
    if (low.indexOf("geo:") === 0) return cGeo(trimmed);
    if (/^[+]?[0-9][0-9\s().\-]{6,}[0-9]$/.test(trimmed)) return cPhone(trimmed, "tel:" + trimmed.replace(/[\s().\-]/g, ""));
    return cText(t);
  }

  function cWebsite(href, shown) {
    var host = shown;
    try { host = new URL(href).hostname.replace(/^www\./, ""); } catch (e) {}
    return {
      kind: "Website", title: host, icon: "globe",
      fields: [["Address", shown]],
      actions: [
        { label: "Open link", icon: "open", href: safeHref(href, ["http", "https"]), primary: true },
        { label: "Copy", icon: "copy", copy: shown }
      ]
    };
  }
  function cEmail(addr, href) {
    return {
      kind: "Email address", title: addr, icon: "mail",
      actions: [
        { label: "Send email", icon: "mail", href: safeHref(href, ["mailto"]), primary: true },
        { label: "Copy", icon: "copy", copy: addr }
      ]
    };
  }
  function cPhone(num, href) {
    return {
      kind: "Phone number", title: num, icon: "phone",
      actions: [
        { label: "Call", icon: "phone", href: safeHref(href, ["tel"]), primary: true },
        { label: "Copy", icon: "copy", copy: num }
      ]
    };
  }
  function cSms(raw) {
    var rest = raw.replace(/^smsto:/i, "").replace(/^sms:/i, "");
    var parts = rest.split(/[:;]/);
    var num = parts[0] || "";
    var msg = parts.slice(1).join(":");
    var href = "sms:" + num.replace(/[\s().\-]/g, "");
    var f = [["Number", num]];
    if (msg) f.push(["Message", msg]);
    return {
      kind: "Text message", title: num || "SMS", icon: "chat", fields: f,
      actions: [
        { label: "Send message", icon: "chat", href: safeHref(href, ["sms"]), primary: true },
        { label: "Copy number", icon: "copy", copy: num }
      ]
    };
  }
  function cGeo(raw) {
    var body = raw.slice(4).split("?")[0];
    var c = body.split(",");
    var lat = (c[0] || "").trim(), lng = (c[1] || "").trim();
    var maps = "https://www.google.com/maps/search/?api=1&query=" + encodeURIComponent(lat + "," + lng);
    return {
      kind: "Location", title: lat + ", " + lng, icon: "pin",
      fields: [["Latitude", lat], ["Longitude", lng]],
      actions: [
        { label: "Open in Maps", icon: "open", href: safeHref(maps, ["https"]), primary: true },
        { label: "Copy", icon: "copy", copy: raw }
      ]
    };
  }

  // WIFI:S:<ssid>;T:<WPA|WEP|nopass>;P:<pass>;H:<bool>;;  (with \ escapes)
  function cWifi(raw) {
    var body = raw.slice(5);
    var map = {};
    var i = 0, key = "", val = "", reading = "key";
    while (i < body.length) {
      var ch = body[i];
      if (ch === "\\" && i + 1 < body.length) { (reading === "key" ? key += body[i + 1] : val += body[i + 1]); i += 2; continue; }
      if (reading === "key" && ch === ":") { reading = "val"; i++; continue; }
      if (ch === ";") { if (key) map[key.toUpperCase()] = val; key = ""; val = ""; reading = "key"; i++; continue; }
      (reading === "key" ? key += ch : val += ch); i++;
    }
    if (key) map[key.toUpperCase()] = val;
    var ssid = map.S || "";
    var auth = (map.T || "nopass").toUpperCase();
    var pass = map.P || "";
    var sec = auth === "NOPASS" || auth === "" ? "Open (no password)" : auth;
    var f = [["Network", ssid], ["Security", sec]];
    if (map.H && /^true$/i.test(map.H)) f.push(["Hidden", "Yes"]);
    var actions = [];
    if (pass) actions.push({ label: "Copy password", icon: "copy", copy: pass, primary: true });
    actions.push({ label: "Copy network name", icon: "copy", copy: ssid });
    return { kind: "Wi-Fi network", title: ssid || "Wi-Fi", icon: "wifi", fields: f, secret: pass, actions: actions };
  }

  function unescField(s) { return String(s).replace(/\\([;,:\\nN])/g, function (m, c) { return (c === "n" || c === "N") ? "\n" : c; }); }

  // MECARD:N:Last,First;TEL:123;EMAIL:a@b.com;URL:...;;
  function cMeCard(raw) {
    var body = raw.slice(7);
    var segs = body.split(";");
    var get = function (k) {
      for (var i = 0; i < segs.length; i++) {
        var idx = segs[i].indexOf(":");
        if (idx > -1 && segs[i].slice(0, idx).toUpperCase() === k) return unescField(segs[i].slice(idx + 1));
      }
      return "";
    };
    var name = get("N").replace(/,/g, " ").trim();
    var tel = get("TEL"), email = get("EMAIL"), url = get("URL");
    return contactCard(name, tel, email, url, "", raw);
  }

  function cVCard(raw) {
    var lines = raw.replace(/\r\n[ \t]/g, "").replace(/\n[ \t]/g, "").split(/\r\n|\n|\r/);
    var props = {};
    for (var i = 0; i < lines.length; i++) {
      var idx = lines[i].indexOf(":");
      if (idx < 0) continue;
      var head = lines[i].slice(0, idx).split(";")[0].toUpperCase();
      var value = lines[i].slice(idx + 1).trim();
      if (value && !props[head]) props[head] = value;
    }
    var name = props.FN || (props.N ? props.N.replace(/;/g, " ").trim() : "");
    var org = props.ORG ? props.ORG.replace(/;/g, " ").trim() : "";
    return contactCard(name, props.TEL || "", props.EMAIL || "", props.URL || "", org, raw, props.TITLE || "");
  }

  function contactCard(name, tel, email, url, org, raw, title) {
    var f = [];
    if (org) f.push(["Organisation", org]);
    if (title) f.push(["Title", title]);
    if (tel) f.push(["Phone", tel]);
    if (email) f.push(["Email", email]);
    if (url) f.push(["Website", url]);
    var actions = [];
    var vcf = raw.toUpperCase().indexOf("BEGIN:VCARD") === 0 ? raw : buildVcf(name, tel, email, url, org);
    actions.push({ label: "Save contact", icon: "download", download: vcf, filename: (name || "contact").replace(/[^\w.\-]+/g, "_") + ".vcf", mime: "text/vcard", primary: true });
    if (tel) actions.push({ label: "Call", icon: "phone", href: safeHref("tel:" + tel.replace(/[\s().\-]/g, ""), ["tel"]) });
    if (email) actions.push({ label: "Email", icon: "mail", href: safeHref("mailto:" + email, ["mailto"]) });
    if (url) actions.push({ label: "Website", icon: "open", href: safeHref(/^https?:/i.test(url) ? url : "https://" + url, ["http", "https"]) });
    return { kind: "Contact", title: name || "Contact", icon: "user", fields: f, actions: actions };
  }
  function buildVcf(name, tel, email, url, org) {
    var v = ["BEGIN:VCARD", "VERSION:3.0", "FN:" + (name || "")];
    if (org) v.push("ORG:" + org);
    if (tel) v.push("TEL:" + tel);
    if (email) v.push("EMAIL:" + email);
    if (url) v.push("URL:" + url);
    v.push("END:VCARD");
    return v.join("\r\n");
  }

  function cEvent(raw) {
    var lines = raw.split(/\r\n|\n|\r/);
    var get = function (k) {
      for (var i = 0; i < lines.length; i++) {
        var idx = lines[i].indexOf(":");
        if (idx > -1 && lines[i].slice(0, idx).split(";")[0].toUpperCase() === k) return lines[i].slice(idx + 1).trim();
      }
      return "";
    };
    var sum = get("SUMMARY"), loc = get("LOCATION");
    var f = [];
    if (get("DTSTART")) f.push(["Starts", prettyDate(get("DTSTART"))]);
    if (get("DTEND")) f.push(["Ends", prettyDate(get("DTEND"))]);
    if (loc) f.push(["Location", loc]);
    var ics = raw.toUpperCase().indexOf("BEGIN:VCALENDAR") === 0 ? raw : "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n" + raw.trim() + "\r\nEND:VCALENDAR";
    return {
      kind: "Calendar event", title: sum || "Event", icon: "cal", fields: f,
      actions: [{ label: "Add to calendar", icon: "download", download: ics, filename: "event.ics", mime: "text/calendar", primary: true }]
    };
  }
  function prettyDate(s) {
    var m = /^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2}))?/.exec(s);
    if (!m) return s;
    var d = m[1] + "-" + m[2] + "-" + m[3];
    return m[4] ? d + " " + m[4] + ":" + m[5] : d;
  }
  function cText(t) {
    return { kind: "Text", title: "", icon: "text", text: t, actions: [{ label: "Copy text", icon: "copy", copy: t, primary: true }] };
  }

  // ---- render a classified result into a card -----------------------------
  function smartCard(info) {
    var card = el("div", { class: "smart" });
    var head = el("div", { class: "smart-head" });
    var ic = el("span", { class: "smart-ico", html: "<svg viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='1.7' stroke-linecap='round' stroke-linejoin='round'>" + (I[info.icon] || I.text) + "</svg>" });
    head.appendChild(ic);
    var meta = el("div", { class: "smart-meta", style: "min-width:0" });
    meta.appendChild(el("div", { class: "smart-kind", text: info.kind }));
    if (info.title) meta.appendChild(el("div", { class: "smart-title", text: info.title }));
    head.appendChild(meta);
    card.appendChild(head);

    var body = el("div", { class: "smart-body" });
    if (info.text != null) {
      body.appendChild(el("div", { class: "smart-text", text: info.text }));
    }
    if (info.fields && info.fields.length) {
      var fields = el("div", { class: "fields" });
      info.fields.forEach(function (kv) {
        var row = el("div", { class: "field" }, el("b", { text: kv[0] }));
        var isSecret = info.secret && kv[1] === info.secret;
        var val = el("span", { text: kv[1], class: isSecret ? "secret" : "" });
        if (isSecret) {
          var shown = false;
          val.textContent = "\u2022".repeat(Math.min(kv[1].length, 12)) || "\u2022\u2022\u2022";
          var btn = el("button", { type: "button", class: "reveal", text: "Show" });
          btn.addEventListener("click", function () {
            shown = !shown;
            val.textContent = shown ? kv[1] : ("\u2022".repeat(Math.min(kv[1].length, 12)) || "\u2022\u2022\u2022");
            btn.textContent = shown ? "Hide" : "Show";
          });
          row.appendChild(val);
          row.appendChild(btn);
        } else {
          row.appendChild(val);
        }
        fields.appendChild(row);
      });
      body.appendChild(fields);
    }
    card.appendChild(body);

    if (info.actions && info.actions.length) {
      var actions = el("div", { class: "smart-actions" });
      info.actions.forEach(function (a) {
        var cls = "btn" + (a.primary ? " primary" : "");
        var node;
        if (a.href) {
          node = el("a", { class: cls, href: a.href, rel: "noopener noreferrer", target: "_blank" });
        } else if (a.download != null) {
          var uri = "data:" + (a.mime || "application/octet-stream") + ";base64," + base64FromText(a.download);
          node = el("a", { class: cls, href: uri, download: a.filename || "download" });
        } else {
          node = el("button", { type: "button", class: cls });
          node.addEventListener("click", function () { copyText(a.copy); });
        }
        node.appendChild(icon(a.icon));
        node.appendChild(doc.createTextNode(a.label));
        actions.appendChild(node);
      });
      card.appendChild(actions);
    }
    return card;
  }

  function base64FromText(text) {
    try {
      var bytes = new TextEncoder().encode(text);
      var bin = "";
      for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
      return btoa(bin);
    } catch (e) { return btoa(unescape(encodeURIComponent(text))); }
  }

  function chip(label, value, accent) {
    // keep "0" — a data mask of 0 (and a 0-char/0-byte payload) is meaningful;
    // only null / undefined / "" should suppress a chip.
    if (value == null || value === "") return null;
    return el("span", { class: "chip" + (accent ? " accent" : "") }, el("b", { text: String(value) }), " " + label);
  }

  // ---- main result rendering ---------------------------------------------
  function renderResult(data) {
    clearChildren(resultZone);
    state.resultShown = true;

    if (!data || !data.ok) {
      renderError(b64utf8(data && data.error) || "No QR code found.");
      return;
    }

    var text = b64utf8(data.text);
    var card = el("div", { class: "app" });
    card.appendChild(el("div", { class: "banner ok" },
      el("span", { class: "banner-ico", text: "\u2713" }), "Decoded successfully"));

    if (data.binaryMode && data.hex) {
      var raw = el("div", { class: "result mono" },
        el("b", { class: "result-tag", text: "RAW BYTES (hex)" }), el("br"),
        el("code", { text: data.hex }));
      card.appendChild(raw);
      var ra = el("div", { class: "smart-actions" });
      var cb = el("button", { type: "button", class: "btn primary" });
      cb.appendChild(icon("copy")); cb.appendChild(doc.createTextNode("Copy hex"));
      cb.addEventListener("click", function () { copyText(data.hex); });
      ra.appendChild(cb);
      card.appendChild(ra);
    } else {
      card.appendChild(smartCard(classify(text)));
      saveHistory(text);
    }

    // metadata chips
    var meta = el("div", { class: "meta" });
    [
      chip("version", b64utf8(data.version), true),
      chip("EC level", b64utf8(data.ecLevel)),
      chip("mask", b64utf8(data.mask)),
      chip("chars", data.chars),
      chip("bytes", data.byteCount),
      chip("binarizer", b64utf8(data.strategy)),
      (data.procW && data.procH) ? el("span", { class: "chip" }, el("b", { text: data.procW + "\u00d7" + data.procH }), " px") : null,
      chip("ms", data.ms),
      data.mirrored ? el("span", { class: "chip" }, "mirrored") : null
    ].forEach(function (c) { if (c) meta.appendChild(c); });
    card.appendChild(meta);

    if (state.previewUrl) {
      card.appendChild(el("div", { class: "preview-wrap", style: "margin-top:14px" },
        el("img", { class: "preview", src: state.previewUrl, alt: "Scanned image" })));
    }

    resultZone.appendChild(card);
    setHidden(resetBtn, false);
    resultZone.setAttribute("tabindex", "-1");
    resultZone.focus({ preventScroll: false });
  }

  function renderError(msg) {
    clearChildren(resultZone);
    state.resultShown = true;
    var card = el("div", { class: "app" });
    card.appendChild(el("div", { class: "banner bad" },
      el("span", { class: "banner-ico", text: "\u2717" }), "No QR code found"));
    card.appendChild(el("div", { class: "result" }, el("code", { text: msg })));
    var tips = el("div", { class: "tips" }, el("b", { text: "Tips" }));
    var ul = el("ul");
    [
      "Make sure the whole code is in frame, with a little white margin around it.",
      "Avoid glare and heavy blur; hold the camera square to the code.",
      "If a JPEG will not decode, try a PNG (some servers lack a JPEG codec).",
      "Very dense codes: get closer so the squares stay crisp."
    ].forEach(function (s) { ul.appendChild(el("li", { text: s })); });
    tips.appendChild(ul);
    card.appendChild(tips);
    resultZone.appendChild(card);
    setHidden(resetBtn, false);
  }

  function showLoading() {
    clearChildren(resultZone);
    state.resultShown = true;
    resultZone.appendChild(el("div", { class: "loading" },
      el("span", { class: "spinner" }),
      el("div", null,
        el("b", { text: "Decoding\u2026" }),
        el("small", { text: "Large photos can take a few seconds." }))));
  }

  function clearChildren(n) { while (n.firstChild) n.removeChild(n.firstChild); }

  // resting state for the results column. On wide screens it shows a friendly
  // placeholder so the two-pane layout reads as intentional; on phones the
  // column simply collapses (CSS) so the form stays the focus.
  function showEmptyState() {
    clearChildren(resultZone);
    resultZone.removeAttribute("aria-busy");
    state.resultShown = false;
    if (!mqWide.matches) return;
    var ph = el("div", { class: "placeholder" });
    ph.appendChild(el("span", { class: "ph-ico", html: "<svg viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='1.6' stroke-linecap='round' stroke-linejoin='round'><path d='M4 8V6a2 2 0 0 1 2-2h2M16 4h2a2 2 0 0 1 2 2v2M20 16v2a2 2 0 0 1-2 2h-2M8 20H6a2 2 0 0 1-2-2v-2'/><path d='M4 12h16'/></svg>" }));
    ph.appendChild(el("h2", { text: "Ready to scan" }));
    ph.appendChild(el("p", { text: "Drop, choose, paste, or link a QR image — your decoded result appears here." }));
    resultZone.appendChild(ph);
  }

  // ---- decode -------------------------------------------------------------
  function hasImage() {
    return !!(state.file || (fileInput && fileInput.files && fileInput.files.length) ||
      (camInput && camInput.files && camInput.files.length));
  }

  function decode() {
    if (state.busy) return;
    var urlVal = urlInput ? urlInput.value.trim() : "";
    var useUrl = activeTab === "url" && urlVal;
    if (!hasImage() && !useUrl) {
      toast("Choose an image first");
      if (activeTab === "url" && urlInput) urlInput.focus();
      return;
    }

    var fd = new FormData(form);
    fd.set("api", "1");
    if (state.file) fd.set("qrimage", state.file, state.file.name || "image.png");
    if (!useUrl) fd.delete("imageurl");

    setBusy(true);
    showLoading();

    var ctrl = new AbortController();
    var timer = setTimeout(function () { ctrl.abort(); }, 60000);

    fetch(location.pathname + location.search, {
      method: "POST", body: fd, signal: ctrl.signal,
      headers: { "X-Requested-With": "fetch" }, credentials: "same-origin"
    }).then(function (res) {
      return res.text().then(function (txt) {
        var data;
        try { data = JSON.parse(txt); }
        catch (e) { throw new Error("Unexpected server response (status " + res.status + ")."); }
        return data;
      });
    }).then(function (data) {
      renderResult(data);
    }).catch(function (err) {
      renderError(err && err.name === "AbortError"
        ? "Timed out \u2014 the image may be too large. Try a smaller photo."
        : (err && err.message) || "Something went wrong while decoding.");
    }).then(function () {
      clearTimeout(timer);
      setBusy(false);
    });
  }

  function setBusy(b) {
    state.busy = b;
    decodeBtn.disabled = b;
    setHidden(spinner, !b);
    resultZone.setAttribute("aria-busy", b ? "true" : "false");
  }

  // ---- file / preview -----------------------------------------------------
  function setFile(file) {
    if (!file) return;
    if (!/^image\//i.test(file.type) && file.type !== "") {
      toast("That does not look like an image");
      return;
    }
    state.file = file;
    reflectToInput(file);
    if (camInput) camInput.value = "";
    showPreviewFromFile(file);
    decode();
  }

  function reflectToInput(file) {
    try {
      var dt = new DataTransfer();
      dt.items.add(file);
      fileInput.files = dt.files;
    } catch (e) { /* not supported; decode() uses state.file directly */ }
  }

  function showPreviewFromFile(file) {
    revokeObjectUrl();
    state.objectUrl = URL.createObjectURL(file);
    setPreview(state.objectUrl);
  }
  function setPreview(src) {
    state.previewUrl = src;
    previewImg.src = src;
    setHidden(previewWrap, false);
  }
  function revokeObjectUrl() {
    if (state.objectUrl) { try { URL.revokeObjectURL(state.objectUrl); } catch (e) {} state.objectUrl = null; }
  }

  function clearInput() {
    state.file = null;
    revokeObjectUrl();
    state.previewUrl = null;
    previewImg.removeAttribute("src");
    setHidden(previewWrap, true);
    if (fileInput) fileInput.value = "";
    if (camInput) camInput.value = "";
  }

  function reset() {
    showEmptyState();
    clearInput();
    setHidden(resetBtn, true);
    switchTab("upload");
    if (dropzone) dropzone.focus();
  }

  // ---- tabs ---------------------------------------------------------------
  function switchTab(name) {
    if (!panels[name]) return;
    activeTab = name;
    tabs.forEach(function (tb) {
      var on = tb.getAttribute("data-tab") === name;
      tb.classList.toggle("is-active", on);
      tb.setAttribute("aria-selected", on ? "true" : "false");
      tb.setAttribute("tabindex", on ? "0" : "-1");
    });
    for (var k in panels) {
      if (panels[k]) panels[k].classList.toggle("is-active", k === name);
    }
    if (name !== "camera") stopCamera();
  }

  // ---- camera -------------------------------------------------------------
  function cameraSupported() {
    return !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia && window.isSecureContext !== false);
  }
  function startCamera() {
    if (!cameraSupported()) { toast("Camera needs a secure (https) connection"); return; }
    navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" }, audio: false })
      .then(function (stream) {
        state.stream = stream;
        camVideo.srcObject = stream;
        setHidden(camStartBtn, true);
        setHidden(camShotBtn, false);
        setHidden(camStopBtn, false);
      }).catch(function () { toast("Could not access the camera"); });
  }
  function stopCamera() {
    if (state.stream) {
      state.stream.getTracks().forEach(function (t) { t.stop(); });
      state.stream = null;
    }
    if (camVideo) camVideo.srcObject = null;
    setHidden(camStartBtn, false);
    setHidden(camShotBtn, true);
    setHidden(camStopBtn, true);
  }
  function captureFrame() {
    if (!state.stream) return;
    var w = camVideo.videoWidth, h = camVideo.videoHeight;
    if (!w || !h) { toast("Camera still warming up\u2026"); return; }
    var canvas = doc.createElement("canvas");
    canvas.width = w; canvas.height = h;
    canvas.getContext("2d").drawImage(camVideo, 0, 0, w, h);
    var done = function (blob) {
      stopCamera();
      setFile(new File([blob], "capture.png", { type: "image/png" }));
    };
    if (canvas.toBlob) canvas.toBlob(done, "image/png");
    else done(dataUrlToBlob(canvas.toDataURL("image/png")));
  }
  function dataUrlToBlob(durl) {
    var parts = durl.split(","), bin = atob(parts[1]), arr = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
    return new Blob([arr], { type: "image/png" });
  }

  // ---- history (localStorage) --------------------------------------------
  function loadHistory() {
    try { return JSON.parse(localStorage.getItem(HKEY)) || []; } catch (e) { return []; }
  }
  function saveHistory(text) {
    if (!text) return;
    var info = classify(text);
    var list = loadHistory().filter(function (h) { return h.t !== text; });
    list.unshift({ t: text, k: info.kind, ic: info.icon, ts: Date.now() });
    list = list.slice(0, 12);
    try { localStorage.setItem(HKEY, JSON.stringify(list)); } catch (e) {}
    renderHistory();
  }
  function clearHistory() {
    try { localStorage.removeItem(HKEY); } catch (e) {}
    renderHistory();
  }
  function renderHistory() {
    if (!historyEl) return;
    var list = loadHistory();
    clearChildren(historyEl);
    if (!list.length) { setHidden(historyEl, true); return; }
    setHidden(historyEl, false);
    var head = el("div", { class: "history-head" }, el("h2", { text: "Recent scans" }));
    var clr = el("button", { type: "button", class: "history-clear", text: "Clear" });
    clr.addEventListener("click", clearHistory);
    head.appendChild(clr);
    historyEl.appendChild(head);
    var ul = el("div", { class: "history-list" });
    list.forEach(function (h) {
      var item = el("button", { type: "button", class: "hitem" });
      var ico = el("span", { class: "hico", html: "<svg viewBox='0 0 24 24' fill='none' stroke='currentColor' stroke-width='1.7' stroke-linecap='round' stroke-linejoin='round'>" + (I[h.ic] || I.text) + "</svg>" });
      var firstLine = h.t.split(/\r|\n/)[0];
      var txt = el("div", { class: "htext" },
        el("div", { class: "ht1", text: firstLine || h.t }),
        el("div", { class: "ht2", text: h.k }));
      item.appendChild(ico); item.appendChild(txt);
      item.addEventListener("click", function () { showFromHistory(h.t); });
      ul.appendChild(item);
    });
    historyEl.appendChild(ul);
  }
  function showFromHistory(text) {
    clearChildren(resultZone);
    state.resultShown = true;
    var card = el("div", { class: "app" });
    card.appendChild(el("div", { class: "banner ok" },
      el("span", { class: "banner-ico", text: "\u2713" }), "From your recent scans"));
    card.appendChild(smartCard(classify(text)));
    resultZone.appendChild(card);
    setHidden(resetBtn, false);
    resultZone.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  // ---- wire up ------------------------------------------------------------
  // tablist: click + WAI-ARIA keyboard navigation (arrows / Home / End) over a
  // roving tabindex, so only the active tab is in the tab order.
  function focusTab(idx) {
    if (idx < 0) idx = tabs.length - 1;
    else if (idx >= tabs.length) idx = 0;
    var tb = tabs[idx];
    switchTab(tb.getAttribute("data-tab"));
    tb.focus();
  }
  tabs.forEach(function (tb, i) {
    tb.setAttribute("tabindex", tb.classList.contains("is-active") ? "0" : "-1");
    tb.addEventListener("click", function () { switchTab(tb.getAttribute("data-tab")); });
    tb.addEventListener("keydown", function (e) {
      var k = e.key;
      if (k === "ArrowRight" || k === "ArrowDown") { e.preventDefault(); focusTab(i + 1); }
      else if (k === "ArrowLeft" || k === "ArrowUp") { e.preventDefault(); focusTab(i - 1); }
      else if (k === "Home") { e.preventDefault(); focusTab(0); }
      else if (k === "End") { e.preventDefault(); focusTab(tabs.length - 1); }
    });
  });

  form.addEventListener("submit", function (e) { e.preventDefault(); decode(); });

  if (fileInput) fileInput.addEventListener("change", function () {
    if (fileInput.files && fileInput.files[0]) setFile(fileInput.files[0]);
  });
  if (camInput) camInput.addEventListener("change", function () {
    if (camInput.files && camInput.files[0]) setFile(camInput.files[0]);
  });
  if (previewClear) previewClear.addEventListener("click", function (e) {
    e.preventDefault(); e.stopPropagation(); clearInput();
  });
  if (resetBtn) resetBtn.addEventListener("click", reset);

  // drag & drop
  if (dropzone) {
    ["dragenter", "dragover"].forEach(function (ev) {
      dropzone.addEventListener(ev, function (e) { e.preventDefault(); dropzone.classList.add("dragging"); });
    });
    ["dragleave", "dragend", "drop"].forEach(function (ev) {
      dropzone.addEventListener(ev, function (e) { e.preventDefault(); dropzone.classList.remove("dragging"); });
    });
    dropzone.addEventListener("drop", function (e) {
      var f = e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files[0];
      if (f) { switchTab("upload"); setFile(f); }
    });
  }
  // prevent the browser from navigating when a file is dropped outside the zone
  ["dragover", "drop"].forEach(function (ev) {
    window.addEventListener(ev, function (e) {
      if (dropzone && dropzone.contains(e.target)) return;
      e.preventDefault();
    });
  });

  // paste an image from the clipboard
  doc.addEventListener("paste", function (e) {
    if (!e.clipboardData) return;
    var items = e.clipboardData.items || [];
    for (var i = 0; i < items.length; i++) {
      if (items[i].type && items[i].type.indexOf("image") === 0) {
        var blob = items[i].getAsFile();
        if (blob) { e.preventDefault(); switchTab("upload"); setFile(blob); return; }
      }
    }
  });

  // camera buttons
  if (camStartBtn) camStartBtn.addEventListener("click", startCamera);
  if (camShotBtn) camShotBtn.addEventListener("click", captureFrame);
  if (camStopBtn) camStopBtn.addEventListener("click", stopCamera);
  if (cameraSupported()) setHidden(camLive, false);

  // Esc clears a shown result
  doc.addEventListener("keydown", function (e) {
    if (e.key === "Escape" && resetBtn && !resetBtn.hidden) reset();
  });

  window.addEventListener("pagehide", function () { revokeObjectUrl(); stopCamera(); });

  // keep the results column's resting placeholder in sync as the viewport
  // crosses the two-pane breakpoint (added/removed only when nothing is shown).
  function onWideChange() { if (!state.resultShown && !state.busy) showEmptyState(); }
  if (mqWide.addEventListener) mqWide.addEventListener("change", onWideChange);
  else if (mqWide.addListener) mqWide.addListener(onWideChange);

  // show the resting placeholder unless the server already rendered a result
  // into the column (no-JS form post that this script is now enhancing).
  if (!resultZone.querySelector("*")) showEmptyState();

  renderHistory();
})();
