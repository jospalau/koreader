-- patches/2-bookshelf-overlay.lua
--
-- 1) East North -> "Bookshelf (aparcar, nunca cerrar)": toggle que aparca
--    el libro y muestra Bookshelf, o vuelve al libro si ya estaba aparcado.
--
-- 2) West South NO se reasigna: sigue siendo la acción nativa "File
--    browser" (event Home). Cuando el libro está aparcado, SIEMPRE
--    vuelve a él en vez de cerrarlo. Cuando NO está aparcado, se reusa el
--    ReaderUI:onHome original (el que muestra el MultiConfirmBox de
--    guardar progreso / TBR / salir).
--
-- IMPORTANTE (descubierto por logs): cuando el plugin Bookshelf ya se ha
-- instanciado en la sesión (self.bookshelf existe), el evento "Home" NO
-- llega directo a ReaderUI:onHome — llega primero a BookshelfClass:onHome
-- (main.lua de bookshelf.koplugin). El onHome nativo de Bookshelf usa
-- _isShowing()/_safeShow() y, estando el shelf no visible, no hace nada
-- útil: simplemente "traga" el evento devolviendo true sin mostrar el
-- MultiConfirmBox ni cerrar nada correctamente. Por eso, en la rama
-- NOT PARKED de BookshelfClass:onHome, delegamos explícitamente en el
-- onHome REAL de ReaderUI (capturado a nivel de módulo), usando
-- self.ui (la instancia de ReaderUI, ver main.lua: self.ui.document)
-- en vez de llamar al onHome nativo de Bookshelf.
--
-- El override de ReaderUI:onHome se deja como red de seguridad por si en
-- algún flujo el evento SÍ llega directo a ReaderUI sin pasar por
-- Bookshelf (p.ej. libro abierto sin que el plugin Bookshelf se haya
-- instanciado todavía en la sesión).
--
-- VERSION CON LOGS: cada paso clave escribe una línea "[bookshelf-overlay]"
-- en el log de depuración. Búscalas en:
--   ☰ -> Ayuda -> Ver registro de depuración
-- o en el archivo crash.log de la carpeta de KOReader.

local Dispatcher = require("dispatcher")
local ReaderUI = require("apps/reader/readerui")
local logger = require("logger")
local _ = require("gettext")

logger.warn("[bookshelf-overlay] patch file loaded")

-- ---------------------------------------------------------------------------
-- Debounce: el multiswipe a veces dispara el mismo gesto 2-3 veces seguidas
-- (rebote), lo que descuadra el estado de "aparcado" antes de que el
-- siguiente gesto llegue. Ignoramos re-disparos del MISMO evento si llegan
-- en menos de DEBOUNCE_S segundos.
-- ---------------------------------------------------------------------------
local ok_time, socket = pcall(require, "socket")
local gettime = (ok_time and socket and socket.gettime) or os.time

local DEBOUNCE_S = 0.7
local _last_trigger = {} -- { [event_name] = timestamp }

local function isDebounced(event_name)
    local now = gettime()
    local last = _last_trigger[event_name]
    _last_trigger[event_name] = now
    if last and (now - last) < DEBOUNCE_S then
        logger.warn("[bookshelf-overlay] DEBOUNCED:", event_name,
            "(", tostring(now - last), "s desde el anterior)")
        return true
    end
    return false
end

Dispatcher:registerAction("show_bookshelf_overlay", {
    category = "none",
    event    = "ParkAndShowBookshelf",
    title    = _("Bookshelf (aparcar, nunca cerrar)"),
    general  = true,
})

logger.warn("[bookshelf-overlay] action 'show_bookshelf_overlay' registrada")

-- ---------------------------------------------------------------------------
-- Capturamos el onHome ORIGINAL de ReaderUI (el que trae el MultiConfirmBox
-- de guardar progreso / TBR / salir, Documento 1) a nivel de módulo, antes
-- de que nada más lo toque. Se reusa tanto desde BookshelfClass:onHome
-- (caso principal, ver logs) como desde el override de ReaderUI:onHome
-- (red de seguridad).
-- ---------------------------------------------------------------------------
local original_readerui_onHome = ReaderUI.onHome
logger.warn("[bookshelf-overlay] original_readerui_onHome capturado:", tostring(original_readerui_onHome))

-- ---------------------------------------------------------------------------
-- Parchea la CLASE Bookshelf (compartida por todas las instancias, presentes
-- y futuras) UNA sola vez por arranque de KOReader. Parchear la instancia
-- (como hacíamos antes) solo arreglaba la sesión de lectura actual: cada
-- libro nuevo crea una instancia nueva del plugin, sin parchear.
-- ---------------------------------------------------------------------------
local bookshelf_patched = false
local function patchBookshelfOnce(plugin)
    if bookshelf_patched then
        return
    end

    local BookshelfClass = getmetatable(plugin)
    if not BookshelfClass then
        logger.warn("[bookshelf-overlay] no se pudo obtener la clase via getmetatable(plugin)")
        return
    end
    logger.warn("[bookshelf-overlay] patchBookshelfOnce: parcheando la CLASE Bookshelf.onHome:", tostring(BookshelfClass))

    local original_onHome = BookshelfClass.onHome
    logger.warn("[bookshelf-overlay] original_onHome (Bookshelf nativo) capturado:", tostring(original_onHome))

    function BookshelfClass:onHome()
        logger.warn("[bookshelf-overlay] onHome() DISPARADO")

        if isDebounced("onHome") then
            return true -- ignoramos el rebote, no tocamos nada
        end

        local ok_req, Park = pcall(require, "lib/bookshelf_reader_park")
        logger.warn("[bookshelf-overlay] onHome: require Park ok=", tostring(ok_req))

        local parked = ok_req and Park and Park.isParked()
        logger.warn("[bookshelf-overlay] onHome: Park.isParked()=", tostring(parked))

        if parked then
            logger.warn("[bookshelf-overlay] onHome: rama PARKED -> Park.unpark()")
            local unpark_ok, unpark_err = pcall(function()
                Park.unpark(self._widget)
            end)
            logger.warn("[bookshelf-overlay] onHome: unpark_ok=", tostring(unpark_ok),
                "unpark_err=", tostring(unpark_err))
            return true
        end

        -- NOT PARKED: el evento Home llegó al widget de Bookshelf (no a
        -- ReaderUI directamente). El onHome nativo de Bookshelf
        -- (original_onHome) usa _isShowing()/_safeShow() y aquí no hace
        -- nada útil (el shelf no está visible), así que NO lo llamamos.
        -- En su lugar delegamos en el onHome REAL de ReaderUI (el del
        -- MultiConfirmBox), usando self.ui, que es la instancia de
        -- ReaderUI (ver main.lua: self.ui.document).
        logger.warn("[bookshelf-overlay] onHome: rama NOT PARKED -> delegando en ReaderUI:onHome real (self.ui)")
        local reader_ui = self.ui
        logger.warn("[bookshelf-overlay] onHome: reader_ui=", tostring(reader_ui))

        if original_readerui_onHome and reader_ui then
            local ret = original_readerui_onHome(reader_ui)
            logger.warn("[bookshelf-overlay] onHome: original_readerui_onHome devolvió=", tostring(ret))
            return ret
        end

        logger.warn("[bookshelf-overlay] onHome: no se pudo delegar (original_readerui_onHome=",
            tostring(original_readerui_onHome), " reader_ui=", tostring(reader_ui), ") -> fallback original_onHome nativo")
        if original_onHome then
            local ret = original_onHome(self)
            logger.warn("[bookshelf-overlay] onHome: original_onHome (fallback) devolvió=", tostring(ret))
            return ret
        end
    end

    bookshelf_patched = true
    logger.warn("[bookshelf-overlay] patchBookshelfOnce: parcheado OK (clase, permanente)")
end

-- ---------------------------------------------------------------------------
-- East North: aparcar y mostrar / volver si ya aparcado (toggle)
-- ---------------------------------------------------------------------------
function ReaderUI:onParkAndShowBookshelf()
    logger.warn("[bookshelf-overlay] onParkAndShowBookshelf() DISPARADO")

    if isDebounced("onParkAndShowBookshelf") then
        return true -- ignoramos el rebote, no tocamos nada
    end

    local plugin = self.bookshelf
    if not plugin then
        logger.warn("[bookshelf-overlay] Bookshelf plugin NO está cargado (self.bookshelf es nil)")
        return true
    end
    logger.warn("[bookshelf-overlay] plugin encontrado:", tostring(plugin))

    patchBookshelfOnce(plugin)

    local ok_req, Park = pcall(require, "lib/bookshelf_reader_park")
    if not ok_req or not Park then
        logger.warn("[bookshelf-overlay] No se pudo cargar lib/bookshelf_reader_park, ok_req=", tostring(ok_req))
        return true
    end

    logger.warn("[bookshelf-overlay] isParked ANTES del toggle:", tostring(Park.isParked()))

    local original_enabled = Park.enabled
    Park.enabled = function() return true end
    logger.warn("[bookshelf-overlay] Park.enabled forzado a true (temporalmente)")

    local ok, err = pcall(function()
        local rui = plugin and plugin.ui
        -- pagemap_current_page_label (stable page numbers) only gets written
        -- by ReaderPageMap:onCloseDocument, which hot-parking deliberately
        -- never fires (that's the whole point of not closing). Without this,
        -- the hero's "page N of M" stays frozen at whatever it was on the
        -- last REAL close/open. Mirror onCloseDocument's own write here.
        pcall(function()
            local pm = rui.pagemap
            if pm and pm.has_pagemap and pm.use_page_labels then
                rui.doc_settings:saveSetting("pagemap_last_page_label", pm:getLastPageLabel(true))
                rui.doc_settings:saveSetting("pagemap_current_page_label",
                    select(1, pm:getCurrentPageLabel(true)))
            end
        end)
        if not plugin._widget then
            -- Libro abierto directo desde el File Manager real: el widget
            -- de Bookshelf no existe todavía en esta sesión, así que no hay
            -- nada sobre lo que "aparcar" (_raiseInPlace necesita el
            -- widget ya en el stack). Lo creamos/mostramos nosotros mismos
            -- (show() no toca el documento ni el lector, solo lo tapa
            -- encima) y luego registramos el park a mano.
            logger.warn("[bookshelf-overlay] plugin._widget es nil -> cold-create via plugin:show()")
            plugin:show()
            local park_ok = Park.park(plugin, plugin._widget)
            logger.warn("[bookshelf-overlay] Park.park manual tras cold-create =", tostring(park_ok))
        else
            -- -- For the hero card to be updated every time we show Bookshelf parked
            -- -- Other option is setting local HERO_MEMO_TTL_S = 0 in bookshelf_widget.lua
            if self._widget then
                self._widget._hero_current_memo = nil
            end
            plugin:onToggleBookshelf() -- abre y aparca / o vuelve al libro si ya estaba aparcado
        end
    end)

    Park.enabled = original_enabled
    logger.warn("[bookshelf-overlay] Park.enabled restaurado")

    logger.warn("[bookshelf-overlay] toggle pcall ok=", tostring(ok), "err=", tostring(err))
    logger.warn("[bookshelf-overlay] isParked DESPUÉS del toggle:", tostring(Park.isParked()))

    if not ok then
        logger.warn("[bookshelf-overlay] ERROR en toggle:", err)
    end
    return true
end

-- ---------------------------------------------------------------------------
-- ReaderUI:onHome -- RED DE SEGURIDAD. Según los logs, el caso normal (con
-- self.bookshelf ya instanciado) pasa por BookshelfClass:onHome de arriba,
-- no por aquí. Este override cubre el caso en que el evento Home llegue
-- directo a ReaderUI sin pasar por Bookshelf (p.ej. el plugin Bookshelf
-- aún no se ha instanciado en la sesión). Mismo criterio: parked ->
-- unpark; not parked -> onHome original (MultiConfirmBox).
-- ---------------------------------------------------------------------------
function ReaderUI:onHome()
    logger.warn("[bookshelf-overlay] ReaderUI:onHome() DISPARADO (red de seguridad)")

    if isDebounced("readerui_onHome") then
        return true -- ignoramos el rebote, no tocamos nada
    end

    local ok_req, Park = pcall(require, "lib/bookshelf_reader_park")
    logger.warn("[bookshelf-overlay] ReaderUI:onHome: require Park ok=", tostring(ok_req))

    local parked = ok_req and Park and Park.isParked()
    logger.warn("[bookshelf-overlay] ReaderUI:onHome: Park.isParked()=", tostring(parked))

    if parked then
        logger.warn("[bookshelf-overlay] ReaderUI:onHome: rama PARKED -> Park.unpark()")
        local plugin = self.bookshelf
        local widget = plugin and plugin._widget
        local unpark_ok, unpark_err = pcall(function()
            Park.unpark(widget)
        end)
        logger.warn("[bookshelf-overlay] ReaderUI:onHome: unpark_ok=", tostring(unpark_ok),
            "unpark_err=", tostring(unpark_err))
        return true
    end

    logger.warn("[bookshelf-overlay] ReaderUI:onHome: rama NOT PARKED -> original_readerui_onHome (MultiConfirmBox)")
    if original_readerui_onHome then
        local ret = original_readerui_onHome(self)
        logger.warn("[bookshelf-overlay] ReaderUI:onHome: original_readerui_onHome devolvió=", tostring(ret))
        return ret
    end
    logger.warn("[bookshelf-overlay] ReaderUI:onHome: no había original_readerui_onHome que llamar")
end

-- ---------------------------------------------------------------------------
-- FIX: patchBookshelfOnce solo se disparaba al hacer East North
-- (onParkAndShowBookshelf). Pero el plugin Bookshelf se auto-instancia en
-- cuanto se abre un libro (self.bookshelf ya existe desde el arranque del
-- lector). Si el usuario hace West South ANTES de haber aparcado nunca,
-- BookshelfClass:onHome sigue sin parchear -> usa el onHome nativo de
-- Bookshelf, que no muestra el MultiConfirmBox y traga el evento.
-- Parcheamos la clase justo tras ReaderUI:init(), que es donde todos los
-- plugins (incluido self.bookshelf) ya están instanciados, para cubrir
-- también el primer West South de la sesión sin haber aparcado antes.
-- ---------------------------------------------------------------------------
local original_readerui_init = ReaderUI.init
logger.warn("[bookshelf-overlay] original_readerui_init capturado:", tostring(original_readerui_init))

function ReaderUI:init(...)
    local ret
    if original_readerui_init then
        ret = original_readerui_init(self, ...)
    end

    if self.bookshelf then
        logger.warn("[bookshelf-overlay] ReaderUI:init: self.bookshelf existe -> patchBookshelfOnce eager")
        patchBookshelfOnce(self.bookshelf)
    else
        logger.warn("[bookshelf-overlay] ReaderUI:init: self.bookshelf todavía nil tras init")
    end

    return ret
end

-- ---------------------------------------------------------------------------
-- Mientras el libro está aparcado (Park.isParked() == true), se bloquean
-- solo los GESTOS TÁCTILES CRUDOS (tap/swipe/pan/hold/etc.) que lleguen a
-- ReaderUI, para evitar que un toque pensado para el shelf visible encima
-- (o un gesto "a ciegas") cambie de página/capítulo/brillo en un documento
-- que no se está mirando. Todo lo demás (SaveSettings, eventos que abren
-- widgets de los micromódulos como ShowCalendarView, etc.) pasa normal:
-- una whitelist por nombre exacto se queda corta cada vez que se añade un
-- micromódulo nuevo, así que filtramos por prefijo/substring de gesto en
-- vez de por lista cerrada de eventos permitidos.
-- ---------------------------------------------------------------------------
local GESTURE_HANDLER_PREFIXES = { "Tap", "Swipe", "Pan", "Hold", "Pinch", "Spread", "Multiswipe" }
-- Eventos que no encajan en ningún prefijo de gesto genérico pero que en la
-- práctica también mueven el documento parked (detectado con logging real:
-- GoBackLink navega tras un salto de enlace/nota, causando el mismo efecto
-- "a ciegas" que un swipe). Añadir aquí por nombre exacto según se detecten.
local EXTRA_BLOCKED_EVENTS = { GoBackLink = true }

local function isRawGestureEvent(event_name)
    if EXTRA_BLOCKED_EVENTS[event_name] then return true end
    for _, prefix in ipairs(GESTURE_HANDLER_PREFIXES) do
        if event_name:find(prefix, 1, true) then return true end
    end
    return false
end

local original_readerui_handleEvent = ReaderUI.handleEvent

function ReaderUI:handleEvent(event)
    local ok_req, Park = pcall(require, "lib/bookshelf_reader_park")
    local parked = ok_req and Park and Park.isParked()

    if parked and event and event.handler then
        local event_name = event.handler:gsub("^on", "")
        print("[bookshelf-overlay] DEBUG handleEvent PARKED, event_name=", event_name)
        if isRawGestureEvent(event_name) and event_name ~= "Home"
                and event_name ~= "ParkAndShowBookshelf" then
            logger.warn("[bookshelf-overlay] handleEvent: PARKED, bloqueando gesto crudo:", event_name)
            return true
        end
    end

    return original_readerui_handleEvent(self, event)
end
