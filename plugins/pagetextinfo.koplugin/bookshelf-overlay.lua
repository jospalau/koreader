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
