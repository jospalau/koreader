-- set search path for 'require()'
package.path =
    "common/?.lua;frontend/?.lua;" ..
    package.path
package.cpath =
    "common/?.so;common/?.dll;/usr/lib/lua/?.so;" ..
    package.cpath

-- set search path for 'ffi.load()'
local ffi = require("ffi")
require("ffi/posix_h")
local C = ffi.C
if ffi.os == "Windows" then
    C._putenv("PATH=libs;common;")
end
local ffi_load = ffi.load
-- patch ffi.load for thirdparty luajit libraries
ffi.load = function(lib, global)
    io.write("ffi.load: ", lib, global and " (RTLD_GLOBAL)\n" or "\n")
    local loaded, re = pcall(ffi_load, lib)
    if loaded then return re end

    local lib_path = package.searchpath(lib, "./lib?.so;./libs/lib?.so;./libs/lib?.so.1")

    if not lib_path then
        io.write("ffi.load (warning): ", re, "\n")
        error("Not able to load dynamic library: " .. lib)
    else
        io.write("ffi.load (assisted searchpath): ", lib_path, "\n")
        return ffi_load(lib_path, global)
    end
end
