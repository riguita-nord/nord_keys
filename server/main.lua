
local function dbg(...)
  if Config.Debug then
    print("^3[nord_keys:sv]^7", ...)
  end
end

local function normPlate(plate)
  plate = tostring(plate or ''):upper()
  plate = plate:gsub('%s+', '')
  return plate
end

local function normalizeTheme(input)
    input = tostring(input or ''):lower()

    -- 🎯 DETECÇÃO DIRETA POR MARCA
    if input == 'vapid' then
        return 'bmw'
    end

    -- 🎯 DETECÇÃO POR MODELO
    if input == 'adder' then
        return 'audi'
    end

    -- 🔎 Caso venha model completo tipo "adder" dentro de string
    if input:find('adder', 1, true) then
        return 'audi'
    end

    if input:find('vapid', 1, true) then
        return 'bmw'
    end

    -- 🎨 Se já vier theme válido
    if input == 'audi' or input == 'bmw' then
        return input
    end

    -- 🔒 Fallback seguro
    return 'bmw'
end

local function getThemeFromModel(modelOrMake)
  -- aceita "adder", "vapid", "vapid dominator", etc.
  return normalizeTheme(modelOrMake)
end

function getThemeForPlate(plate)
  plate = normPlate(plate)
  if plate == '' then return 'bmw' end

  -- Se tiveres função no NRKeysOwned que devolve modelo ou marca pelo plate, usa aqui
  if NRKeysOwned and NRKeysOwned.GetVehicleModelByPlate then
    local model = NRKeysOwned.GetVehicleModelByPlate(plate) -- ex: "adder" / "dominator"
    if model and model ~= '' then
      return getThemeFromModel(model)
    end
  end

  if NRKeysOwned and NRKeysOwned.GetVehicleMakeByPlate then
    local make = NRKeysOwned.GetVehicleMakeByPlate(plate) -- ex: "vapid"
    if make and make ~= '' then
      return getThemeFromModel(make)
    end
  end

  return 'bmw'
end

local function discordLog(msg)
  if not (Config.Discord and Config.Discord.enabled and Config.Discord.webhook and Config.Discord.webhook ~= '') then return end
  PerformHttpRequest(Config.Discord.webhook, function() end, 'POST',
    json.encode({ username = Config.Discord.username or 'nord_keys', content = msg }),
    { ['Content-Type'] = 'application/json' }
  )
end

local function addLog(action, plate, actor, target, details)
  plate = normPlate(plate)
  MySQL.insert.await([[
    INSERT INTO nord_vehicle_key_logs (action, plate, actor, target, details)
    VALUES (?, ?, ?, ?, ?)
  ]], { action, plate, actor, target, details })

  discordLog(('[%s] plate=%s actor=%s target=%s %s'):format(action, plate, actor or '-', target or '-', details or ''))
end

-- ============ Core checks ============

local function hasKeyInInventory(src, plate)
  plate = normPlate(plate)
  if plate == '' then return false end

  -- ox_inventory search metadata
  local count = exports.ox_inventory:Search(src, 'count', 'vehicle_key', { plate = plate })
  return (count or 0) > 0
end

local function hasDBKey(src, plate)
  plate = normPlate(plate)
  local identifier = Bridge.GetIdentifier(src)
  if not identifier then return false end

  local row = MySQL.single.await([[
    SELECT id FROM nord_vehicle_keys
    WHERE plate = ? AND holder = ?
    LIMIT 1
  ]], { plate, identifier })

  return row ~= nil
end

function ensureDBKey(holderIdentifier, plate, grantedBy)
  plate = normPlate(plate)
  if not holderIdentifier or holderIdentifier == '' or plate == '' then return false end

  local ok = MySQL.insert.await([[
    INSERT IGNORE INTO nord_vehicle_keys (plate, holder, granted_by)
    VALUES (?, ?, ?)
  ]], { plate, holderIdentifier, grantedBy })

  return ok ~= nil
end

function removeDBKey(holderIdentifier, plate)
  plate = normPlate(plate)
  if not holderIdentifier or holderIdentifier == '' or plate == '' then return false end

  local res = MySQL.update.await([[
    DELETE FROM nord_vehicle_keys
    WHERE plate = ? AND holder = ?
  ]], { plate, holderIdentifier })

  return (res or 0) > 0
end

local function hasAnyAccess(src, plate)

  -- 🔹 Se for ped NPC (não player), sempre permite
  if type(src) ~= "number" then
      return true
  end

  if not GetPlayerName(src) then
      return true
  end

  if Bridge.IsMasterKey(src) then
      return true
  end

  if hasKeyInInventory(src, plate) then
      return true
  end

  return false
end

-- ============ Public exports ============

exports('HasKey', function(src, plate)
  return hasAnyAccess(src, plate)
end)

exports('GiveKey', function(src, plate, toIdentifier, grantedBy)
  plate = normPlate(plate)
  if not toIdentifier or toIdentifier == '' or plate == '' then return false end
  ensureDBKey(toIdentifier, plate, grantedBy)
  return true
end)

exports('RevokeKey', function(src, plate, fromIdentifier)
  plate = normPlate(plate)
  if not fromIdentifier or fromIdentifier == '' or plate == '' then return false end
  return removeDBKey(fromIdentifier, plate)
end)

-- ============ Callbacks ============

lib.callback.register('nord_keys:sv:hasAccess', function(src, plate)
  plate = normPlate(plate)
  return hasAnyAccess(src, plate)
end)


-- ============ Events ============

RegisterNetEvent('nord_keys:sv:grantSelfOwner', function(plate)
  -- usado quando “compras/registas” um carro
  local src = source
  local identifier = Bridge.GetIdentifier(src)
  plate = normPlate(plate)

  if not identifier or plate == '' then return end

  ensureDBKey(identifier, plate, identifier)
  exports.ox_inventory:AddItem(src, 'vehicle_key', 1, { plate = plate })

  addLog('REGISTER_OWNER', plate, identifier, identifier, 'owner registered + item key added')
  Bridge.Notify(src, 'success', 'Chave criada para o teu veículo.')
end)

RegisterNetEvent('nord_keys:sv:transferKey', function(plate, targetSrc)
  local src = source
  local plateN = normPlate(plate)
  local identifier = Bridge.GetIdentifier(src)
  if not identifier or plateN == '' then return end

  targetSrc = tonumber(targetSrc)
  if not targetSrc then return end

  local targetId = Bridge.GetIdentifier(targetSrc)
  if not targetId then
    Bridge.Notify(src, 'error', Config.Text.invalidTarget)
    return
  end

  -- Só transfere se tiver acesso (masterkey também pode dar chaves)
  if not hasAnyAccess(src, plateN) then
    Bridge.Notify(src, 'error', Config.Text.noKey)
    return
  end

  ensureDBKey(targetId, plateN, identifier)

  -- Dá item físico também (opcional). Aqui damos sempre 1.
  exports.ox_inventory:AddItem(targetSrc, 'vehicle_key', 1, { plate = plateN })

  addLog('TRANSFER_KEY', plateN, identifier, targetId, 'gave db key + item key')
  Bridge.Notify(src, 'success', Config.Text.gaveKey)
  Bridge.Notify(targetSrc, 'success', Config.Text.receivedKey)
end)

RegisterNetEvent('nord_keys:sv:revokeKey', function(plate, targetIdentifier)
  local src = source
  local plateN = normPlate(plate)
  local identifier = Bridge.GetIdentifier(src)
  if not identifier or plateN == '' then return end

  -- Só masterkey pode revogar de outros, ou o próprio pode revogar a sua (UI)
  local isMaster = Bridge.IsMasterKey(src)
  if not isMaster and tostring(targetIdentifier) ~= tostring(identifier) then
    Bridge.Notify(src, 'error', 'Sem permissão.')
    return
  end

  local ok = removeDBKey(tostring(targetIdentifier), plateN)
  if ok then
    addLog('REVOKE_KEY', plateN, identifier, tostring(targetIdentifier), 'revoked db key')
    Bridge.Notify(src, 'success', Config.Text.keyRevoked)
  else
    Bridge.Notify(src, 'error', 'Nada para revogar.')
  end
end)

RegisterNetEvent('nord_keys:sv:lockpickSuccess', function(plate)
  local src = source
  local plateN = normPlate(plate)
  local identifier = Bridge.GetIdentifier(src)
  if not identifier or plateN == '' then return end

  -- dá “temp access” via statebag/flag (client controla), mas guardamos log
  addLog('LOCKPICK_SUCCESS', plateN, identifier, nil, 'temp access granted')
end)

RegisterNetEvent('nord_keys:sv:lockpickFail', function(plate)
  local src = source
  local plateN = normPlate(plate)
  local identifier = Bridge.GetIdentifier(src)
  if not identifier or plateN == '' then return end
  addLog('LOCKPICK_FAIL', plateN, identifier, nil, 'failed')
end)

-- Consumo lockpick (server authority)
RegisterNetEvent('nord_keys:sv:consumeLockpick', function(mode)
  local src = source
  if not Config.Lockpick.enabled then return end
  local item = Config.Lockpick.item
  if not item then return end

  -- remove 1 lockpick
  exports.ox_inventory:RemoveItem(src, item, 1)
  addLog('LOCKPICK_CONSUME', 'N/A', Bridge.GetIdentifier(src), nil, tostring(mode or 'unknown'))
end)

RegisterNetEvent('nord_keys:sv:openKeyFobFromSlot', function(slot)
    local src = source
    if not slot then return end

    local item = exports.ox_inventory:GetSlot(src, slot)
    if not item then
        print("^1[nord_keys] SLOT NOT FOUND^7")
        return
    end

    if item.name ~= 'vehicle_key' then
        print("^1[nord_keys] INVALID ITEM^7")
        return
    end
    
    local metadata = item.metadata or {}
    print(json.encode(metadata))
    if not metadata.plate then
        TriggerClientEvent('ox_lib:notify', src, {
            type = 'error',
            description = 'Esta chave não está associada a nenhum veículo.'
        })
        return
    end

    local plate = normPlate(metadata.plate)
    local battery = tonumber(metadata.battery) or 100
    local theme = normalizeTheme(metadata.theme)

    -- garantir defaults persistidos
    local changed = false
    if metadata.battery == nil then metadata.battery = battery changed = true end
    if metadata.theme == nil then metadata.theme = theme changed = true end
    if changed then
        exports.ox_inventory:SetMetadata(src, slot, metadata)
    end

    TriggerClientEvent('nord_keys:client:openKeyFob', src, plate, battery, theme)
end)

RegisterNetEvent('nord_keys:sv:recoverLostKey', function(plate)
    local src = source
    plate = normPlate(plate)
    if plate == '' then return end

    local identifier = Bridge.GetIdentifier(src)
    if not identifier then return end

    -- 🔎 VERIFICA SE JÁ TEM O ITEM FÍSICO (mais seguro: Search slots)
    do
        local slots = exports.ox_inventory:Search(src, 'slots', 'vehicle_key')
        if slots then
            for _, it in pairs(slots) do
                local m = it.metadata or {}
                local foundPlate = m.plate

                -- compatibilidade antiga: metadata.type pode ter JSON
                if (not foundPlate or foundPlate == '') and m.type then
                    local ok, decoded = pcall(json.decode, m.type)
                    if ok and decoded and decoded.plate then
                        foundPlate = decoded.plate
                    end
                end

                if foundPlate and normPlate(foundPlate) == plate then
                    Bridge.Notify(src, 'inform', 'Já tens a chave desse carro.')
                    return
                end
            end
        end
    end

    -- 🔐 Confirma dono via owned vehicles
    if not (Config.OwnedVehicles and Config.OwnedVehicles.enabled) then
        Bridge.Notify(src, 'error', 'Sistema de veículos próprios não está ativo.')
        return
    end

    local ownerId = NRKeysOwned and NRKeysOwned.GetOwnerIdentifierByPlate and NRKeysOwned.GetOwnerIdentifierByPlate(plate)
    if not ownerId or tostring(ownerId) ~= tostring(identifier) then
        Bridge.Notify(src, 'error', 'Não és o proprietário deste veículo.')
        return
    end

    -- 🎨 Tema: vem do sistema owned (se existir) ou fallback
    local theme = getThemeFromModel(modelOrMake)

    local row = MySQL.single.await(
        "SELECT vehicle FROM player_vehicles WHERE plate = ? LIMIT 1",
        { plate }
    )

    if row and row.vehicle then
        local ok, props = pcall(json.decode, row.vehicle)
        if ok and props and props.model then

            local modelHash = tonumber(props.model)
            if modelHash then

                local make = GetMakeNameFromVehicleModel(modelHash)
                make = tostring(make or ''):lower()

                if make == 'adder' then
                    theme = 'audi'
                elseif make == 'vapid' then
                    theme = 'bmw'
                end

            end
        end
    end

    -- 💾 Garante registo DB (caso não exista)
    MySQL.insert.await([[
        INSERT IGNORE INTO nord_vehicle_keys (plate, holder, granted_by)
        VALUES (?, ?, ?)
    ]], { plate, identifier, 'keyloss_npc' })

    -- 🔑 Dá o item com metadata correta (server define theme)
    exports.ox_inventory:AddItem(src, 'vehicle_key', 1, {
        plate = plate,
        theme = theme,
        battery = 100
    })

    -- 📝 Log opcional
    if addLog then
        addLog('RECOVER_LOST_KEY', plate, identifier, identifier, 'npc issued duplicate key')
    end

    Bridge.Notify(src, 'success', ('Chave recuperada (%s).'):format(plate))
end)

RegisterNetEvent('nord_keys:sv:policeAlert', function(coords)
    local players = GetPlayers()

    for _, id in ipairs(players) do
        local src = tonumber(id)
        if Bridge.IsPolice and Bridge.IsPolice(src) then
            TriggerClientEvent('ox_lib:notify', src, {
                type = 'error',
                title = 'Roubo de Veículo',
                description = 'Tentativa de arrombamento detectada.'
            })
        end
    end
end)

RegisterNetEvent('nord_keys:sv:consumeLockpick', function()
    local src = source
    exports.ox_inventory:RemoveItem(src, 'lockpick', 1)
end)

RegisterNetEvent("nord_keys:sv:exportGiveKey", function(plate)
    local src = source
    exports["nord_keys"]:GiveKeyByPlate(src, plate)
end)

RegisterNetEvent("nord_keys:sv:exportRemoveKey", function(plate)
    local src = source
    exports["nord_keys"]:RemoveKeyByPlate(src, plate)
end)

RegisterCommand('hotwire', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)

    if veh ~= 0 then
        local driver = GetPedInVehicleSeat(veh, -1)

        if driver ~= 0 and not IsPedAPlayer(driver) then
            return -- não aplicar engine lock
        end
    end

    if veh == 0 then
        notify('error', 'Tens de estar dentro do veículo.')
        return
    end

    if GetPedInVehicleSeat(veh, -1) ~= ped then
        notify('error', 'Tens de estar no banco do condutor.')
        return
    end

    local plate = normPlate(GetVehicleNumberPlateText(veh))

    -- Se tiver chave não precisa
    local hasKey = exports.ox_inventory:Search('count', 'vehicle_key', { plate = plate }) or 0
    if hasKey > 0 then
        notify('inform', 'Já tens a chave.')
        return
    end

    local hasPliers = exports.ox_inventory:Search('count', 'pliers') or 0
    if hasPliers <= 0 then
        notify('error', 'Precisas de um alicate.')
        return
    end

    lib.progressBar({
        duration = 8000,
        label = 'A fazer ligação direta...',
        useWhileDead = false,
        canCancel = false,
        disable = { move = true, car = true, combat = true }
    })

    local success = lib.skillCheck({'hard','hard','medium'})

    if success then
        notify('success', 'Ligação direta concluída.')

        SetVehicleEngineOn(veh, true, true, false)
        SetVehicleUndriveable(veh, false)

        grantTempAccess(plate, 15)
    else
        notify('error', 'Falhaste a ligação direta.')

        if math.random(1,100) <= 60 then
            exports.ox_inventory:RemoveItem('pliers', 1)
        end
    end
end)

RegisterNetEvent("nord_keys:sv:removePlayerKey", function(plate)
    local src = source
    plate = tostring(plate or ''):upper():gsub('%s+','')
    if plate == '' then return end

    local identifier = Bridge.GetIdentifier(src)
    if not identifier then return end

    -- remove da DB
    removeDBKey(identifier, plate)

    -- remove item físico
    local items = exports.ox_inventory:Search(src, 'slots', 'vehicle_key')

    if items then
        for _, item in pairs(items) do
            local metadata = item.metadata or {}
            if metadata.plate and metadata.plate:upper():gsub('%s+','') == plate then
                exports.ox_inventory:RemoveItem(src, 'vehicle_key', 1, item.slot)
                break
            end
        end
    end

    addLog("REMOVE_KEY", plate, identifier, identifier, "removed via integration")
end)

RegisterNetEvent('nord_keys:sv:useKeyBattery', function(plate, action)
    local src = source

    if not plate or not action then return end

    local items = exports.ox_inventory:Search(src, 'slots', 'vehicle_key')
    if not items then return end

    for _, item in pairs(items) do
        local metadata = item.metadata or {}

        if metadata.plate and metadata.plate:upper():gsub('%s+','') == plate then

            local battery = metadata.battery or 100

            if battery <= 0 then
                TriggerClientEvent('ox_lib:notify', src, {
                    type = 'error',
                    description = 'A bateria da chave está descarregada.'
                })
                return
            end

            -- consumir bateria
            battery = battery - 4
            if battery < 0 then battery = 0 end

            metadata.battery = battery
            exports.ox_inventory:SetMetadata(src, item.slot, metadata)

            -- 🔥 ESTE É O PASSO QUE TE FALTA
            TriggerClientEvent('nord_keys:client:executeAction', src, plate, action)

            -- atualizar NUI
            TriggerClientEvent('nord_keys:client:updateBattery', src, battery)

            return
        end
    end
end)