(function () {
  "use strict";
  var STORY_W = 1080, STORY_H = 1920, SCALE = 1.8, MARGIN = 240;
  var VIEW_TOP = -MARGIN / SCALE, VIEW_H = STORY_H / SCALE;
  var SVG = "http://www.w3.org/2000/svg";
  var THEMES = ["vibrant", "eink", "gray"];
  // The address works with or without the final slash.
  var base = location.pathname.match(/^\/[^\/]+/)[0] + "/";
  var app = document.getElementById("app");
  var decks = {};
  var theme = "vibrant";
  var index = 0;
  var busy = false;
  var ui = {};

  function el(tag, cls, text) {
    var node = document.createElement(tag);
    if (cls) { node.className = cls; }
    if (text !== undefined) { node.textContent = text; }
    return node;
  }

  function layerUrl(themeName, position, size) {
    return base + "layer/" + themeName + "/" + (position + 1) + "/" + size;
  }

  function loadDeck(name) {
    if (decks[name]) { return Promise.resolve(decks[name]); }
    return fetch(base + "deck/" + name).then(function (res) {
      if (!res.ok) { throw new Error("deck"); }
      return res.json();
    }).then(function (data) {
      decks[name] = data;
      return data;
    });
  }

  function loadImage(url) {
    return new Promise(function (resolve, reject) {
      var image = new Image();
      image.onload = function () { resolve(image); };
      image.onerror = reject;
      image.src = url;
    });
  }

  // Rows of dots that continue the halftone of a card above and below it.
  function eachDot(shape, callback) {
    var spacing = shape[3];
    for (var row = shape[1]; row <= shape[2]; row += 1) {
      var y = row * spacing * 0.87;
      for (var x = row % 2 === 0 ? 0 : spacing / 2; x <= 600; x += spacing) { callback(x, y); }
    }
  }

  function svgCircle(x, y, r, color) {
    var node = document.createElementNS(SVG, "circle");
    node.setAttribute("cx", x); node.setAttribute("cy", y); node.setAttribute("r", r);
    node.setAttribute("fill", color);
    return node;
  }

  function appendShape(group, shape) {
    var node;
    if (shape[0] === "c") {
      group.appendChild(svgCircle(shape[1], shape[2], shape[3], shape[4]));
    } else if (shape[0] === "d") {
      eachDot(shape, function (x, y) { group.appendChild(svgCircle(x, y, shape[4], shape[5])); });
    } else if (shape[0] === "r") {
      node = document.createElementNS(SVG, "rect");
      node.setAttribute("x", shape[1]); node.setAttribute("y", shape[2]);
      node.setAttribute("width", shape[3]); node.setAttribute("height", shape[4]);
      node.setAttribute("fill", shape[5]);
      group.appendChild(node);
    } else {
      node = document.createElementNS(SVG, "polygon");
      node.setAttribute("points", shape[1].join(" "));
      node.setAttribute("fill", shape[2]);
      group.appendChild(node);
    }
  }

  function sceneSvg(card) {
    var svg = document.createElementNS(SVG, "svg");
    svg.setAttribute("viewBox", "0 " + VIEW_TOP + " 600 " + VIEW_H);
    svg.setAttribute("aria-hidden", "true");
    card.layers.forEach(function (layer) {
      var group = document.createElementNS(SVG, "g");
      group.setAttribute("class", "m-" + layer.anim);
      group.style.animationDuration = layer.dur + "s";
      group.style.animationDelay = layer.delay + "s";
      if (layer.origin) {
        group.style.transformOrigin = layer.origin[0] + "px " + layer.origin[1] + "px";
      }
      layer.shapes.forEach(function (shape) { appendShape(group, shape); });
      svg.appendChild(group);
    });
    return svg;
  }

  function paintScene(ctx, card) {
    ctx.save();
    ctx.fillStyle = card.bg;
    ctx.fillRect(0, 0, STORY_W, STORY_H);
    ctx.translate(0, MARGIN);
    ctx.scale(SCALE, SCALE);
    function disc(x, y, r, color) {
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.arc(x, y, r, 0, Math.PI * 2);
      ctx.fill();
    }
    card.layers.forEach(function (layer) {
      layer.shapes.forEach(function (shape) {
        if (shape[0] === "c") {
          disc(shape[1], shape[2], shape[3], shape[4]);
        } else if (shape[0] === "d") {
          eachDot(shape, function (x, y) { disc(x, y, shape[4], shape[5]); });
        } else if (shape[0] === "r") {
          ctx.fillStyle = shape[5];
          ctx.fillRect(shape[1], shape[2], shape[3], shape[4]);
        } else {
          var points = shape[1];
          ctx.fillStyle = shape[2];
          ctx.beginPath();
          ctx.moveTo(points[0], points[1]);
          for (var i = 2; i < points.length; i += 2) { ctx.lineTo(points[i], points[i + 1]); }
          ctx.closePath();
          ctx.fill();
        }
      });
    });
    ctx.restore();
  }

  function storyBlob(deck, position) {
    return loadImage(layerUrl(deck.theme, position, "story")).then(function (image) {
      var canvas = document.createElement("canvas");
      canvas.width = STORY_W;
      canvas.height = STORY_H;
      var ctx = canvas.getContext("2d");
      paintScene(ctx, deck.cards[position]);
      ctx.drawImage(image, 0, MARGIN, STORY_W, STORY_H - 2 * MARGIN);
      return new Promise(function (resolve, reject) {
        canvas.toBlob(function (blob) {
          // Safari holds on to the memory of a canvas until it is emptied, which adds up over a whole deck.
          canvas.width = canvas.height = 0;
          if (blob) { resolve(blob); } else { reject(new Error("blob")); }
        }, "image/png");
      });
    });
  }

  var CRC_TABLE = (function () {
    var table = new Uint32Array(256);
    for (var n = 0; n < 256; n += 1) {
      var c = n;
      for (var k = 0; k < 8; k += 1) { c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; }
      table[n] = c >>> 0;
    }
    return table;
  })();

  function crc32(bytes) {
    var c = 0xffffffff;
    for (var i = 0; i < bytes.length; i += 1) { c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8); }
    return (c ^ 0xffffffff) >>> 0;
  }

  // The fields a local header and a central directory entry have in common. No compression: PNG already is.
  function zipFields(file, stamp) {
    var view = new DataView(new ArrayBuffer(26));
    view.setUint16(0, 20, true);
    view.setUint16(4, 0, true);
    view.setUint16(6, stamp.time, true);
    view.setUint16(8, stamp.date, true);
    view.setUint32(10, file.crc, true);
    view.setUint32(14, file.blob.size, true);
    view.setUint32(18, file.blob.size, true);
    view.setUint16(22, file.name.length, true);
    return view.buffer;
  }

  function zipRecord(signature, length) {
    var view = new DataView(new ArrayBuffer(length));
    view.setUint32(0, signature, true);
    return view;
  }

  // files: { name (ASCII), blob, crc }. The images stay blobs, so the browser does not need them all in memory.
  function zipBlob(files) {
    var now = new Date();
    var stamp = {
      time: now.getHours() << 11 | now.getMinutes() << 5 | now.getSeconds() >> 1,
      date: (now.getFullYear() - 1980) << 9 | (now.getMonth() + 1) << 5 | now.getDate(),
    };
    var encoder = new TextEncoder();
    var body = [], directory = [], offset = 0, directorySize = 0;
    files.forEach(function (file) {
      var name = encoder.encode(file.name), fields = zipFields(file, stamp);
      body.push(zipRecord(0x04034b50, 4), fields, name, file.blob);
      var entry = zipRecord(0x02014b50, 6);
      entry.setUint16(4, 20, true);
      var tail = new DataView(new ArrayBuffer(14));
      tail.setUint32(10, offset, true);
      directory.push(entry, fields, tail, name);
      offset += 30 + name.length + file.blob.size;
      directorySize += 46 + name.length;
    });
    var end = zipRecord(0x06054b50, 22);
    end.setUint16(8, files.length, true);
    end.setUint16(10, files.length, true);
    end.setUint32(12, directorySize, true);
    end.setUint32(16, offset, true);
    return new Blob(body.concat(directory, [end]), { type: "application/zip" });
  }

  function download(blob, name) {
    var url = URL.createObjectURL(blob);
    var link = document.createElement("a");
    link.href = url;
    link.download = name;
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 60000);
  }

  function pad(value) { return value < 10 ? "0" + value : String(value); }

  function imageName(deck, position) {
    return "book_rewind_" + deck.year + "_" + pad(position + 1) + "_" + deck.theme + ".png";
  }

  function text() { return decks[theme].text; }

  var statusTimer = null;
  function setStatus(message, brief) {
    clearTimeout(statusTimer);
    ui.status.textContent = message;
    if (brief) {
      statusTimer = setTimeout(function () { ui.status.textContent = ""; }, 2000);
    }
  }

  function setBusy(on) {
    busy = on;
    ui.save.disabled = ui.saveAll.disabled = on;
    Array.prototype.forEach.call(ui.seg.children, function (button) { button.disabled = on; });
  }

  function saving(task) {
    if (busy) { return; }
    setBusy(true);
    task().then(function () {
      setStatus(text().saved, true);
    }).catch(function () {
      setStatus(text().failed, true);
    }).then(function () {
      setBusy(false);
    });
  }

  function save() {
    var deck = decks[theme], position = index;
    saving(function () {
      setStatus(text().loading);
      return storyBlob(deck, position).then(function (blob) {
        download(blob, imageName(deck, position));
      });
    });
  }

  // One at a time, because the device draws each image when asked. What it already drew comes back at once,
  // so trying again after a failure continues where it stopped.
  function saveAll() {
    var deck = decks[theme], total = deck.cards.length, files = [];
    function collect(position) {
      if (position === total) { return Promise.resolve(); }
      setStatus(text().loading_all.replace("{done}", position + 1).replace("{total}", total));
      return storyBlob(deck, position).then(function (blob) {
        return blob.arrayBuffer().then(function (buffer) {
          files.push({ name: imageName(deck, position), blob: blob, crc: crc32(new Uint8Array(buffer)) });
          return collect(position + 1);
        });
      });
    }
    saving(function () {
      return collect(0).then(function () {
        download(zipBlob(files), "book_rewind_" + deck.year + "_" + deck.theme + ".zip");
      });
    });
  }

  function renderBars(deck) {
    ui.bars.textContent = "";
    deck.cards.forEach(function (_, i) {
      ui.bars.appendChild(el("span", i <= index ? "on" : ""));
    });
  }

  function renderThemeButtons() {
    ui.seg.textContent = "";
    THEMES.forEach(function (name) {
      var button = el("button", "", text()["theme_" + name]);
      button.type = "button";
      button.setAttribute("aria-pressed", String(name === theme));
      button.addEventListener("click", function () { selectTheme(name); });
      ui.seg.appendChild(button);
    });
  }

  var showToken = 0;
  function show() {
    var deck = decks[theme], card = deck.cards[index], token = showToken += 1;
    ui.stage.style.backgroundColor = card.bg;
    ui.scene.textContent = "";
    ui.scene.appendChild(sceneSvg(card));
    ui.image.removeAttribute("src");
    // While saving, the status belongs to the progress, and the card can still be flipped through.
    if (!busy) { setStatus(text().loading); }
    var position = index, shown = theme;
    loadImage(layerUrl(shown, position, "preview")).then(function (image) {
      if (token !== showToken) { return; }
      ui.image.src = image.src;
      if (!busy) { setStatus(""); }
      // One at a time ahead of the reader, because the device draws them when asked.
      if (position + 1 < deck.cards.length) { loadImage(layerUrl(shown, position + 1, "preview")).catch(function () {}); }
    }).catch(function () {
      if (token === showToken && !busy) { setStatus(text().failed); }
    });
    renderBars(deck);
  }

  function go(delta) {
    var total = decks[theme].cards.length, target = index + delta;
    if (target >= 0 && target < total) {
      index = target;
      show();
    }
  }

  function selectTheme(name) {
    if (name === theme || busy) { return; }
    loadDeck(name).then(function () {
      theme = name;
      renderThemeButtons();
      show();
    }).catch(function () {
      setStatus(text().lost);
    });
  }

  function build() {
    var t = text();
    document.title = t.title;
    ui.stage = el("div", "stage");
    ui.frame = el("div", "frame");
    ui.scene = el("div", "scene");
    ui.image = el("img");
    ui.image.alt = "";
    ui.frame.append(ui.scene, ui.image);
    ui.bars = el("div", "bars");
    ui.status = el("div", "status");
    ui.status.setAttribute("role", "status");
    var left = el("button", "hit left"), right = el("button", "hit right");
    left.type = right.type = "button";
    left.setAttribute("aria-label", t.previous);
    right.setAttribute("aria-label", t.next);
    left.addEventListener("click", function () { go(-1); });
    right.addEventListener("click", function () { go(1); });
    ui.stage.append(ui.frame, left, right, ui.bars, ui.status);
    var startX = null;
    ui.stage.addEventListener("touchstart", function (e) { startX = e.touches[0].clientX; }, { passive: true });
    ui.stage.addEventListener("touchend", function (e) {
      if (startX === null) { return; }
      var moved = e.changedTouches[0].clientX - startX;
      startX = null;
      if (Math.abs(moved) > 50) {
        e.preventDefault();
        go(moved < 0 ? 1 : -1);
      }
    });
    var controls = el("div", "controls");
    ui.seg = el("div", "seg");
    ui.seg.setAttribute("role", "group");
    ui.seg.setAttribute("aria-label", t.theme_label);
    ui.save = el("button", "save", t.save);
    ui.save.type = "button";
    ui.save.addEventListener("click", save);
    ui.saveAll = el("button", "save", t.save_all);
    ui.saveAll.type = "button";
    ui.saveAll.addEventListener("click", saveAll);
    controls.append(ui.seg, ui.save, ui.saveAll);
    app.append(ui.stage, controls);
    document.addEventListener("keydown", function (e) {
      if (e.key === "ArrowRight") { go(1); }
      if (e.key === "ArrowLeft") { go(-1); }
    });
    renderThemeButtons();
    show();
  }

  loadDeck(theme).then(build).catch(function () {
    app.textContent = "";
    app.appendChild(el("p", "failure", "Book Rewind"));
  });
})();
