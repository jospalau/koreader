local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local collection_file = DataStorage:getSettingsDir() .. "/collection.lua"

local ReadCollection = {
    coll = nil, -- hash table
    coll_settings = nil, -- hash table
    last_read_time = 0,
    default_collection_name = "favorites",
}

function ReadCollection:OpenRandomFav()
    local col_fav = self.coll["MBR Tier 2"]
    if not col_fav then return end

    local len = 0
    for entry in pairs(col_fav) do
        len= len + 1
    end


    if len == 0 then return end
    local util = require("util")
    local i = 1
    local file_name = nil
    local files = ""
    for i = 1, 3, 1 do
        local j = 1
        local random_fav = math.random(1, len)
        for _, fav in pairs(col_fav) do
            if j == random_fav then
                file_name = fav.file
                local filename = select(2, util.splitFilePathName(file_name))
                files = files .. "|" .. filename
                break
            end
            j = j + 1
        end
    end
    return files:sub(2, files:len())
end
-- read, write

local function buildEntry(file, order, attr)
    file = ffiUtil.realpath(file)
    if file then
        attr = attr or lfs.attributes(file)
        if attr and attr.mode == "file" then
            return {
                file  = file,
                text  = file:gsub(".*/", ""),
                order = order,
                attr  = attr,
            }
        end
    end
end

function ReadCollection:_read()
    local collection_file_modification_time = lfs.attributes(collection_file, "modification")
    if collection_file_modification_time then
        if collection_file_modification_time <= self.last_read_time then return end
        self.last_read_time = collection_file_modification_time
    end
    local collections = LuaSettings:open(collection_file)
    if collections:hasNot(self.default_collection_name) then
        collections:saveSetting(self.default_collection_name, {})
    end
    logger.dbg("ReadCollection: reading from collection file")
    self.coll = {}
    self.coll_settings = {}
    for coll_name, collection in pairs(collections.data) do
        local coll = {}
        for _, v in ipairs(collection) do
            local item = buildEntry(v.file, v.order)
            if item then -- exclude deleted files
                coll[item.file] = item
            end
        end
        self.coll[coll_name] = coll
        self.coll_settings[coll_name] = collection.settings or { order = 1 } -- favorites, first run
        self.coll_settings[coll_name]["number_files"] = util.tableSize(coll)
        self.coll_settings[coll_name]["series"] = (collection.settings and collection.settings.series) and collection.settings.series or nil
    end
end

function ReadCollection:write(updated_collections, no_flush)
    local collections = LuaSettings:open(collection_file)
    for coll_name in pairs(collections.data) do
        if not self.coll[coll_name] then
            collections:delSetting(coll_name)
        end
    end
    for coll_name, coll in pairs(self.coll) do
        if updated_collections == nil or updated_collections[1] or updated_collections[coll_name] then
            local is_manual_collate = not self.coll_settings[coll_name].collate or nil
            local data = { settings = self.coll_settings[coll_name] }
            for _, item in pairs(coll) do
                table.insert(data, { file = item.file, order = is_manual_collate and item.order })
            end
            collections:saveSetting(coll_name, data)
        end
    end
    logger.dbg("ReadCollection: writing to collection file")
    if not no_flush then
        collections:flush()
    end
end

function ReadCollection:updateLastBookTime(file)
    file = ffiUtil.realpath(file)
    if file then
        local now = os.time()
        for _, coll in pairs(self.coll) do
            if coll[file] then
                coll[file].attr.access = now
            end
        end
    end
end

-- info

function ReadCollection:isFileInCollection(file, collection_name)
    file = ffiUtil.realpath(file) or file
    return self.coll[collection_name][file] and true or false
end

function ReadCollection:isFileInCollections(file, ignore_show_mark_setting)
    if ignore_show_mark_setting or G_reader_settings:nilOrTrue("collection_show_mark") then
        file = ffiUtil.realpath(file) or file
        for _, coll in pairs(self.coll) do
            if coll[file] then
                return true
            end
        end
    end
    return false
end

function ReadCollection:isFileInCollectionsNotAll(file)
    file = ffiUtil.realpath(file) or file
    for collection, coll in pairs(self.coll) do
        if collection ~= "MBR Tier 2" and collection ~= "Short MBR" then goto continue end
        if coll[file] then
            return true
        end
        ::continue::

    end
    return false
end

function ReadCollection:getCollectionsWithFile(file)
    file = ffiUtil.realpath(file) or file
    local collections = {}
    for coll_name, coll in pairs(self.coll) do
        if coll[file] then
            collections[coll_name] = true
        end
    end
    return collections
end

function ReadCollection:getCollectionNextOrder(collection_name)
    local max_order = 0
    for _, item in pairs(self.coll[collection_name]) do
        if max_order < item.order then
            max_order = item.order
        end
    end
    return max_order + 1
end

-- manage items

function ReadCollection:addItem(file, collection_name)
    local item = buildEntry(file, self:getCollectionNextOrder(collection_name))
    self.coll[collection_name][item.file] = item
end

function ReadCollection:addRemoveItemMultiple(file, collections_to_add)
    file = ffiUtil.realpath(file) or file
    for coll_name, coll in pairs(self.coll) do
        if collections_to_add[coll_name] then
            if not coll[file] then
                coll[file] = buildEntry(file, self:getCollectionNextOrder(coll_name))
            end
        else
            if coll[file] then
                coll[file] = nil
            end
        end
    end
end

function ReadCollection:addItemsMultiple(files, collections_to_add)
    local count = 0
    for file in pairs(files) do
        file = ffiUtil.realpath(file) or file
        for coll_name in pairs(collections_to_add) do
            local coll = self.coll[coll_name]
            if not coll[file] then
                coll[file] = buildEntry(file, self:getCollectionNextOrder(coll_name))
                count = count + 1
            end
        end
    end
    return count
end

function ReadCollection:removeItem(file, collection_name, no_write) -- FM: delete file; FMColl: remove file
    file = ffiUtil.realpath(file) or file
    if collection_name then
        if self.coll[collection_name][file] then
            self.coll[collection_name][file] = nil
            if not no_write then
                self:write({ collection_name = true })
            end
            return true
        end
    else
        local do_write
        for _, coll in pairs(self.coll) do
            if coll[file] then
                coll[file] = nil
                do_write = true
            end
        end
        if do_write then
            if not no_write then
                self:write()
            end
            return true
        end
    end
end

function ReadCollection:removeItems(files) -- FM: delete files
    local do_write
    for file in pairs(files) do
        if self:removeItem(file, nil, true) then
            do_write = true
        end
    end
    if do_write then
        self:write()
    end
end

function ReadCollection:removeItemsByPath(path) -- FM: delete folder
    local do_write
    for coll_name, coll in pairs(self.coll) do
        for file_name in pairs(coll) do
            if util.stringStartsWith(file_name, path) then
                coll[file_name] = nil
                do_write = true
            end
        end
    end
    if do_write then
        self:write()
    end
end

-- Remove all items in a given collection
function ReadCollection:RemoveAllFavoritesAll()
    for file in pairs(self.coll["favorites"]) do
        self.coll["favorites"][file] = nil
    end
    self:write()
    return true
end

-- Remove all items in a given collection
function ReadCollection:RemoveAllCollection(collection, no_flush)
    for file in pairs(self.coll[collection]) do
        self.coll[collection][file] = nil
    end
    self:write(nil, no_flush)
    return true
end


function ReadCollection:_updateItem(coll_name, file_name, new_filepath, new_path)
    local coll = self.coll[coll_name]
    local item_old = coll[file_name]
    new_filepath = new_filepath or new_path .. "/" .. item_old.text
    local item = buildEntry(new_filepath, item_old.order, item_old.attr) -- no lfs call
    coll[item.file] = item
    coll[file_name] = nil
end

function ReadCollection:updateItem(file, new_filepath) -- FM: rename file, move file
    file = ffiUtil.realpath(file) or file
    local do_write
    for coll_name, coll in pairs(self.coll) do
        if coll[file] then
            self:_updateItem(coll_name, file, new_filepath)
            do_write = true
        end
    end
    if do_write then
        self:write()
    end
end

function ReadCollection:updateItems(files, new_path) -- FM: move files
    local do_write
    for file in pairs(files) do
        file = ffiUtil.realpath(file) or file
        for coll_name, coll in pairs(self.coll) do
            if coll[file] then
                self:_updateItem(coll_name, file, nil, new_path)
                do_write = true
            end
        end
    end
    if do_write then
        self:write()
    end
end

function ReadCollection:updateItemsByPath(path, new_path) -- FM: rename folder, move folder
    local len = #path
    local do_write
    for coll_name, coll in pairs(self.coll) do
        for file_name in pairs(coll) do
            if file_name:sub(1, len) == path then
                self:_updateItem(coll_name, file_name, new_path .. file_name:sub(len + 1))
                do_write = true
            end
        end
    end
    if do_write then
        self:write()
    end
end

function ReadCollection:getOrderedCollection(collection_name)
    local ordered_coll = {}
    for _, item in pairs(self.coll[collection_name]) do
        table.insert(ordered_coll, item)
    end
    table.sort(ordered_coll, function(v1, v2) return v1.order < v2.order end)
    return ordered_coll
end


function ReadCollection:getOrderedCollectionName(collection_name)
    local ordered_coll = {}
    for _, item in pairs(self.coll[collection_name]) do
        table.insert(ordered_coll, item)
    end
    table.sort(ordered_coll, function(v1, v2) return v1.text < v2.text end)
    return ordered_coll
end

function ReadCollection:updateCollectionOrder(collection_name, ordered_coll)
    local coll = self.coll[collection_name]
    for i, item in ipairs(ordered_coll) do
        coll[item.file].order = i
    end
    self:write()
end

-- manage collections

function ReadCollection:addCollection(coll_name)
    local max_order = 0
    for _, settings in pairs(self.coll_settings) do
        if max_order < settings.order then
            max_order = settings.order
        end
    end
    self.coll_settings[coll_name] = { order = max_order + 1 }
    self.coll[coll_name] = {}
end

function ReadCollection:renameCollection(coll_name, new_name)
    self.coll_settings[new_name] = self.coll_settings[coll_name]
    self.coll[new_name] = self.coll[coll_name]
    self.coll_settings[coll_name] = nil
    self.coll[coll_name] = nil
end

function ReadCollection:removeCollection(coll_name)
    self.coll_settings[coll_name] = nil
    self.coll[coll_name] = nil
end

function ReadCollection:updateCollectionListOrder(ordered_coll)
    for i, item in ipairs(ordered_coll) do
        self.coll_settings[item.name].order = i
    end
end

ReadCollection:_read()

return ReadCollection
