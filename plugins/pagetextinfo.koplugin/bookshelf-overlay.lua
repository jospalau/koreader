-- patches/2-bookshelf-overlay.lua
--
-- 1) East North -> "Bookshelf (aparcar, nunca cerrar)": toggle que aparca
--    el libro y muestra Bookshelf, o vuelve al libro si ya estaba aparcado.
--
-- 2) West South NO se reasigna: sigue siendo la acción nativa "File
--    browser" (event Home). Cuando el libro está aparcado, SIEMPRE
--    vuelve a él en vez de cerrarlo.
--
-- VERSION CON LOGS: cada paso clave escribe una línea "[bookshelf-overlay]"
-- en el log de depuración, para diagnosticar por qué el segundo ciclo
-- entra/sale falla. Busca esas líneas en:
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
    logger.warn("[bookshelf-overlay] original_onHome capturado:", tostring(original_onHome))

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

        logger.warn("[bookshelf-overlay] onHome: rama NOT PARKED -> original_onHome")
        if original_onHome then
            local ret = original_onHome(self)
            logger.warn("[bookshelf-overlay] onHome: original_onHome devolvió=", tostring(ret))
            return ret
        end
        logger.warn("[bookshelf-overlay] onHome: no había original_onHome que llamar")
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

