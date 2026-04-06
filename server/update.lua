local RESOURCE = GetCurrentResourceName()
local CURRENT_VERSION = GetResourceMetadata(RESOURCE, 'version', 0) or '0.0.0'
local REPO = 'riguita-nord/nord_keys'

local LATEST_VERSION = CURRENT_VERSION
local UPDATE_AVAILABLE = false
local LAST_ERROR = nil

local RELEASES_URL = ('https://api.github.com/repos/%s/releases/latest'):format(REPO)
local TAGS_URL = ('https://api.github.com/repos/%s/tags'):format(REPO)

if _G.__NORD_KEYS_UPDATE_RUNNING then
    return
end
_G.__NORD_KEYS_UPDATE_RUNNING = true

local function printHeader()
    print('^5====================================================^7')
    print(('^5NORD KEYS UPDATE CHECKER (%s)^7'):format(REPO))
    print(('^5Versao local:^7 %s'):format(CURRENT_VERSION))
    print('^5====================================================^7')
end

local function printFooter()
    print('^5====================================================^7')
end

local function printError(reason)
    LAST_ERROR = tostring(reason or 'unknown error')
    print(('^1[nord_keys] Falha ao verificar updates:^7 %s'):format(LAST_ERROR))
end

local function printUpToDate()
    print(('^2[nord_keys] Sem updates.^7 Versao atual: %s'):format(CURRENT_VERSION))
end

local function printOutdated(remoteVersion)
    print('^3[nord_keys] Nova atualizacao disponivel.^7')
    print(('^3Local:^7 %s'):format(CURRENT_VERSION))
    print(('^3Remota:^7 %s'):format(remoteVersion))
end

local function normalizeVersion(version)
    version = tostring(version or '')
    version = version:gsub('^refs/tags/', '')
    version = version:gsub('^v', '')
    version = version:gsub('%s+', '')
    return version
end

local function splitVersion(version)
    local parts = {}
    for n in normalizeVersion(version):gmatch('%d+') do
        parts[#parts + 1] = tonumber(n)
    end
    return parts
end

local function isOutdated(localVersion, remoteVersion)
    local localParts = splitVersion(localVersion)
    local remoteParts = splitVersion(remoteVersion)

    for i = 1, math.max(#localParts, #remoteParts) do
        local lv = localParts[i] or 0
        local rv = remoteParts[i] or 0
        if rv > lv then
            return true
        end
        if rv < lv then
            return false
        end
    end

    return false
end

local function getHigherVersion(a, b)
    if not a or a == '' then
        return b
    end
    if not b or b == '' then
        return a
    end

    if isOutdated(a, b) then
        return b
    end

    return a
end

local function getLatestVersionFromTags(data)
    if type(data) ~= 'table' then
        return nil
    end

    local latest = nil

    for _, tag in ipairs(data) do
        local version = normalizeVersion(tag.name or tag.ref)
        if version ~= '' then
            latest = getHigherVersion(latest, version)
        end
    end

    return latest
end

local function decodeJson(body)
    if not body or body == '' then
        return nil, 'Resposta vazia'
    end

    local ok, data = pcall(json.decode, body)
    if not ok or type(data) ~= 'table' then
        return nil, 'JSON invalido'
    end

    return data, nil
end

local function requestJson(url, cb)
    PerformHttpRequest(url, function(status, body)
        if status ~= 200 then
            cb(nil, ('HTTP %s'):format(tostring(status)))
            return
        end

        local data, err = decodeJson(body)
        if not data then
            cb(nil, err)
            return
        end

        cb(data, nil)
    end, 'GET', '', {
        ['User-Agent'] = 'nord_keys-update-checker',
        ['Accept'] = 'application/vnd.github+json'
    })
end

local function setUpdateState(remoteVersion)
    remoteVersion = normalizeVersion(remoteVersion)
    if remoteVersion == '' then
        printError('Nenhuma versao remota valida encontrada')
        return
    end

    LAST_ERROR = nil
    LATEST_VERSION = remoteVersion
    UPDATE_AVAILABLE = isOutdated(CURRENT_VERSION, remoteVersion)

    if UPDATE_AVAILABLE then
        printOutdated(remoteVersion)
    else
        printUpToDate()
    end
end

local function checkTags()
    requestJson(TAGS_URL, function(data, err)
        printHeader()

        if err then
            printError(err)
            printFooter()
            return
        end

        local remoteVersion = getLatestVersionFromTags(data)
        if not remoteVersion then
            printError('Nenhuma tag encontrada')
            printFooter()
            return
        end

        setUpdateState(remoteVersion)
        printFooter()
    end)
end

local function check()
    requestJson(RELEASES_URL, function(data, err)
        if err then
            checkTags()
            return
        end

        printHeader()

        local remoteVersion = normalizeVersion(data.tag_name or data.name)
        if remoteVersion == '' then
            printFooter()
            checkTags()
            return
        end

        setUpdateState(remoteVersion)
        printFooter()
    end)
end

RegisterNetEvent('nord_keys:requestUpdateStatus', function()
    local src = source

    TriggerClientEvent('nord_keys:receiveUpdateStatus', src, {
        current = CURRENT_VERSION,
        latest = LATEST_VERSION,
        update = UPDATE_AVAILABLE,
        error = LAST_ERROR,
        repo = REPO,
    })
end)

exports('GetUpdateStatus', function()
    return {
        current = CURRENT_VERSION,
        latest = LATEST_VERSION,
        update = UPDATE_AVAILABLE,
        error = LAST_ERROR,
        repo = REPO,
    }
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= RESOURCE then
        return
    end

    SetTimeout(6000, check)
end)