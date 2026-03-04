--========================================================--
-- NORD LAB • PRIVATE UPDATE CHECKER (PRODUCTION)
--========================================================--

local RESOURCE = GetCurrentResourceName()
local CURRENT_VERSION = GetResourceMetadata(RESOURCE, 'version', 0) or "0.0.0"
local LATEST_VERSION = CURRENT_VERSION
local UPDATE_AVAILABLE = false

local API_URL = "https://api.github.com/repos/riguita-nord/nord_keys/git/refs/tags"

-- evita correr 2x
if _G.__NORD_UPDATE_RUNNING then return end
_G.__NORD_UPDATE_RUNNING = true

--========================================================--
-- TOKEN
--========================================================--
local function loadKey()
    local key = LoadResourceFile(RESOURCE, "server/framework/license.key")
    if not key then return "unknown" end
    return key:gsub("%s+","")
end

local LICENSE = loadKey()

local function loadToken()
    local token = LoadResourceFile(RESOURCE, "server/framework/secret.token")
    if not token then return nil end

    token = token:gsub("%s+", "") -- remove espaços/linhas
    if token == "" then return nil end

    return token
end

local GITHUB_TOKEN = loadToken()

if not GITHUB_TOKEN then
    return
end

--========================================================--
-- PRINT
--========================================================--
local function header()
    print("^5====================================================^7")
    print("^5NORD LAB • "..RESOURCE:upper().."^7")
    print("^5Versão local: ^7"..CURRENT_VERSION)
    print("^5====================================================^7")
end

local function footer()
    print("^5====================================================^7")
end

local function fail(reason)
    print("^1✖ Falha ao verificar updates:^7 "..tostring(reason))
end

local function updated()
    print("^2✔ Script atualizado!^7")
end

local function outdated(remote)
    print("^3⬆ Nova atualização disponível!^7")
    print("^3Local:^7 "..CURRENT_VERSION)
    print("^3Nova:^7 "..remote)
end

--========================================================--
-- VERSION COMPARE
--========================================================--
local function split(v)
    local t = {}
    for n in v:gmatch("%d+") do
        t[#t+1] = tonumber(n)
    end
    return t
end

local function isOutdated(localV, remoteV)
    local l, r = split(localV), split(remoteV)

    for i=1, math.max(#l,#r) do
        local lv, rv = l[i] or 0, r[i] or 0
        if rv > lv then return true end
        if rv < lv then return false end
    end
    return false
end

--========================================================--
-- GET LATEST TAG
--========================================================--
local function getLatestTag(tags)
    local latest = nil

    local function greater(a, b)
        local ta, tb = split(a), split(b)
        for i=1, math.max(#ta,#tb) do
            local av, bv = ta[i] or 0, tb[i] or 0
            if av > bv then return true end
            if av < bv then return false end
        end
        return false
    end

    for _,tag in ipairs(tags or {}) do
        local name = tag.ref and tag.ref:match("refs/tags/v?(.*)")
        if name then
            if not latest or greater(name, latest) then
                latest = name
            end
        end
    end

    return latest
end

--========================================================--
-- CHECK
--**
--========================================================--
local function check()
    PerformHttpRequest(API_URL, function(status, body)

        header()

        if status ~= 200 then
            fail("HTTP "..tostring(status))
            footer()
            return
        end

        if not body or body == "" then
            fail("Resposta vazia")
            footer()
            return
        end

        local ok, data = pcall(json.decode, body)
        if not ok or type(data) ~= "table" then
            fail("JSON inválido")
            footer()
            return
        end

        local remoteVersion = getLatestTag(data)

        if not remoteVersion then
            fail("Nenhuma tag encontrada")
            footer()
            return
        end

        LATEST_VERSION = remoteVersion
        UPDATE_AVAILABLE = isOutdated(CURRENT_VERSION, remoteVersion)

        if UPDATE_AVAILABLE then
            outdated(remoteVersion)
        else
            updated()
        end

        footer()

    end, "GET", "", {
        ["Authorization"] = "Bearer "..GITHUB_TOKEN,
        ["User-Agent"] = "NordLab-Updater",
        ["Accept"] = "application/vnd.github+json"
    })
end

--========================================================--
-- SEND UPDATE STATUS TO CLIENT
--========================================================--
RegisterNetEvent("nord_crafting:requestUpdateStatus", function()
    local src = source

    TriggerClientEvent("nord_crafting:receiveUpdateStatus", src, {
        current = CURRENT_VERSION,
        latest = LATEST_VERSION,
        update = UPDATE_AVAILABLE
    })
end)

--========================================================--
-- RUN ONLY WHEN RESOURCE STARTS
--========================================================--
AddEventHandler("onResourceStart", function(res)
    if res ~= RESOURCE then return end
    SetTimeout(6000, check)
end)