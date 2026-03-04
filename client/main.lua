local function dbg(...)
  if Config.Debug then
    print("^3[nord_keys:cl]^7", ...)
  end
end

local function normPlate(plate)
  plate = tostring(plate or ''):upper()
  plate = plate:gsub('%s+', '')
  return plate
end

local function notify(t, msg)
  lib.notify({ type = t or 'inform', description = msg })
end

--===============================
-- Vehicle Helpers
--===============================
local function getClosestVehicle()
  local ped = PlayerPedId()
  local coords = GetEntityCoords(ped)

  local veh = GetVehiclePedIsIn(ped, false)
  if veh ~= 0 then return veh end

  veh = GetClosestVehicle(coords.x, coords.y, coords.z, Config.VehicleSearchRadius or 6.0, 0, 71)
  if veh ~= 0 then return veh end

  return nil
end

--===============================
-- Anim + Sound (Key Fob)
--===============================
local function playKeyAnim()
  local ped = PlayerPedId()
  if IsPedInAnyVehicle(ped, false) then return end

  local dict = 'anim@mp_player_intmenu@key_fob@'
  RequestAnimDict(dict)
  while not HasAnimDictLoaded(dict) do Wait(0) end

  TaskPlayAnim(ped, dict, 'fob_click', 8.0, -8.0, 1000, 48, 0, false, false, false)
end

local function playLockSound(veh, locked)
  if not DoesEntityExist(veh) then return end
  if locked then
    PlaySoundFromEntity(-1, 'Remote_Control_Close', veh, 'PI_Menu_Sounds', true, 0)
  else
    PlaySoundFromEntity(-1, 'Remote_Control_Open', veh, 'PI_Menu_Sounds', true, 0)
  end
end

local function flashLights(veh, times)
  if not DoesEntityExist(veh) then return end

  CreateThread(function()
    for _ = 1, (times or 1) do
      SetVehicleLights(veh, 2)
      Wait(150)
      SetVehicleLights(veh, 0)
      Wait(150)
    end
  end)
end

--===============================
-- Temp Access (Lockpick / Carjack)
--===============================
local tempAccess = {} -- [plate]=expireGameTimer

local function hasTempAccess(plate)
  plate = normPlate(plate)
  local exp = tempAccess[plate]
  if not exp then return false end

  if GetGameTimer() > exp then
    tempAccess[plate] = nil
    return false
  end

  return true
end

local function grantTempAccess(plate, minutes)
  plate = normPlate(plate)
  local ms = (tonumber(minutes) or 1) * 60 * 1000
  tempAccess[plate] = GetGameTimer() + ms
end

--===============================
-- Access Check (Server)
--===============================
local function hasAccessAsync(plate, cb)
  plate = normPlate(plate)
  if plate == '' then return cb(false) end

  if hasTempAccess(plate) then
    return cb(true)
  end

  lib.callback('nord_keys:sv:hasAccess', false, function(ok)
    cb(ok and true or false)
  end, plate)
end

--===============================
-- Lock / Unlock (Keybind L)
--===============================
local function toggleLockOnVehicle(veh, plate)
  local status = GetVehicleDoorLockStatus(veh)
  local shouldLock = (status == 1 or status == 0)

  playKeyAnim()

  if shouldLock then
    SetVehicleDoorsLocked(veh, 2)
    SetVehicleDoorsLockedForAllPlayers(veh, true)
    flashLights(veh, 2)
    playLockSound(veh, true)
    notify('success', Config.Text.locked)
  else
    SetVehicleDoorsLocked(veh, 1)
    SetVehicleDoorsLockedForAllPlayers(veh, false)
    flashLights(veh, 1)
    playLockSound(veh, false)
    notify('success', Config.Text.unlocked)
  end
end

local function toggleLock()
  local veh = getClosestVehicle()
  if not veh then return end

  local plate = normPlate(GetVehicleNumberPlateText(veh))
  if plate == '' then return end

  -- 🔒 VERIFICA ITEM LOCAL PRIMEIRO
  local hasItem = exports.ox_inventory:Search('count', 'vehicle_key', { plate = plate }) or 0
  if hasItem <= 0 then
      notify('error', 'Não tens a chave deste veículo.')
      return
  end

  -- Depois valida no server (segurança extra)
  hasAccessAsync(plate, function(ok)
      if not ok then
          notify('error', 'Não tens a chave deste veículo.')
          return
      end

      toggleLockOnVehicle(veh, plate)
  end)
end

RegisterCommand('lock', toggleLock)
RegisterKeyMapping('lock', 'Trancar / Destrancar veículo', 'keyboard', Config.LockKey)

--===============================
-- Engine Lock (no goto)
--===============================
CreateThread(function()
  if not (Config.EngineLock and Config.EngineLock.enabled) then return end

  while true do
    Wait(Config.EngineLock.checkIntervalMs or 350)

    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)

    if veh == 0 then    else
      -- Se allowPassengers = true e não és condutor, ignora
      if not (Config.EngineLock.allowPassengers and GetPedInVehicleSeat(veh, -1) ~= ped) then
        local plate = normPlate(GetVehicleNumberPlateText(veh))
        if plate ~= "" then
          hasAccessAsync(plate, function(ok)
            if ok then return end
            if Config.EngineLock.blockStartIfNoKey then
              SetVehicleEngineOn(veh, false, true, true)
              SetVehicleUndriveable(veh, true)
              notify("error", Config.Text.engineBlocked)
              Wait(1200)
              SetVehicleUndriveable(veh, false)
            end
          end)
        end
      end
    end
  end
end)

--===============================

-- ===============================
-- Block entering/driving vehicles without key
-- ===============================
do
  local accessCache = {} -- [plate] = { ok=bool, t=gameTimer }

  local function checkAccessCached(plate, cb)
    plate = normPlate(plate)
    if plate == '' then return cb(false) end

    if hasTempAccess(plate) then
      return cb(true)
    end

    local now = GetGameTimer()
    local cached = accessCache[plate]
    if cached and (now - cached.t) < 1200 then
      return cb(cached.ok)
    end

    lib.callback('nord_keys:sv:hasAccess', false, function(ok)
      accessCache[plate] = { ok = ok and true or false, t = GetGameTimer() }
      cb(ok and true or false)
    end, plate)
  end

  CreateThread(function()
    while true do
      Wait(0)

      local ped = PlayerPedId()

      -- Se estiver a tentar entrar num veículo (F)
      local tryingVeh = GetVehiclePedIsTryingToEnter(ped)
      if tryingVeh and tryingVeh ~= 0 then
        local plate = normPlate(GetVehicleNumberPlateText(tryingVeh))
        if plate ~= '' then
          checkAccessCached(plate, function(ok)
            if not ok then
              ClearPedTasksImmediately(ped)
              notify('error', Config.Text.noKey)
            end
          end)
          Wait(500) -- debounce para não spammar
        end
      end

      -- Se por alguma razão entrou no banco do condutor sem chave
      local veh = GetVehiclePedIsIn(ped, false)
      if veh and veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
        local plate2 = normPlate(GetVehicleNumberPlateText(veh))
        if plate2 ~= '' then
          checkAccessCached(plate2, function(ok)
            if not ok then
              notify('error', Config.Text.engineBlocked or Config.Text.noKey)
              TaskLeaveVehicle(ped, veh, 16)
            end
          end)
          Wait(500)
        end
      end
    end
  end)
end

RegisterNUICallback('closeFob', function(_, cb)
  SetNuiFocus(false, false)
  cb(true)
end)

local function getVehicleByPlate(plate)
  local vehicles = GetGamePool('CVehicle')
  for _, veh in ipairs(vehicles) do
    if normPlate(GetVehicleNumberPlateText(veh)) == plate then
      return veh
    end
  end
  return nil
end

local function trunkToggle(veh)
    if not DoesEntityExist(veh) then return end

    NetworkRequestControlOfEntity(veh)
    local timeout = GetGameTimer() + 1000
    while not NetworkHasControlOfEntity(veh) and GetGameTimer() < timeout do
        Wait(0)
    end

    -- Testa porta 5 (traseira)
    local trunkDoor = 5
    if not DoesVehicleHaveDoor(veh, 5) then
        -- Se não tiver 5, tenta porta 4 (frente)
        if DoesVehicleHaveDoor(veh, 4) then
            trunkDoor = 4
        else
            notify('error', 'Este veículo não tem mala.')
            return
        end
    end

    -- Desbloqueia temporariamente
    SetVehicleDoorsLocked(veh, 1)
    SetVehicleDoorsLockedForAllPlayers(veh, false)

    if GetVehicleDoorAngleRatio(veh, trunkDoor) > 0.1 then
        SetVehicleDoorShut(veh, trunkDoor, false)
    else
        SetVehicleDoorOpen(veh, trunkDoor, false, false)
    end
end

-- =========================================
-- LOCK ALL NPC VEHICLES
-- =========================================
local lockedVehicles = {}

CreateThread(function()
    while true do
        Wait(1000)

        local vehicles = GetGamePool("CVehicle")

        for _, veh in ipairs(vehicles) do
            local driver = GetPedInVehicleSeat(veh, -1)

            if driver ~= 0 and not IsPedAPlayer(driver) then

                -- Impede comportamento de fuga
                SetPedFleeAttributes(driver, 0, false)
                SetPedCombatAttributes(driver, 3, false)

                -- Impede sair do veículo
                SetPedCanBeDraggedOut(driver, false)
                SetPedStayInVehicleWhenJacked(driver, true)

                -- Garante que mantém task de condução
                if not IsPedInAnyVehicle(driver, false) then
                    TaskEnterVehicle(driver, veh, -1, -1, 1.0, 1, 0)
                end
            end
        end
    end
end)

--===============================
-- Lockpick
--===============================

CreateThread(function()
    exports.ox_target:addGlobalVehicle({
        {
            name = 'nord_lockpick_vehicle',
            icon = 'fa-solid fa-screwdriver',
            label = 'Arrombar veículo',
            distance = 2.5,

            canInteract = function(entity, distance, coords, name)
                if not entity or not DoesEntityExist(entity) then return false end

                local plate = normPlate(GetVehicleNumberPlateText(entity))
                if plate == '' then return false end

                -- Se for carro de player (tem chave no inventário), não mostra
                local hasKey = exports.ox_inventory:Search('count', 'vehicle_key', { plate = plate }) or 0
                if hasKey > 0 then
                    return false
                end

                -- Se já estiver destrancado, não mostra
                if GetVehicleDoorLockStatus(entity) ~= 2 then
                    return false
                end

                return true
            end,

            onSelect = function(data)
                local veh = data.entity
                if not veh then return end

                local plate = normPlate(GetVehicleNumberPlateText(veh))
                if plate == '' then return end

                local hasItem = exports.ox_inventory:Search('count', Config.Lockpick.item) or 0
                if hasItem <= 0 then
                    notify('error', 'Precisas de um lockpick.')
                    return
                end

                lib.progressBar({
                    duration = 6000,
                    label = 'A arrombar fechadura...',
                    useWhileDead = false,
                    canCancel = false,
                    disable = { move = true, car = true, combat = true }
                })

                local success = lib.skillCheck({'easy','easy'})

                if success then
                    notify('success', 'Porta arrombada.')

                    SetVehicleDoorsLocked(veh, 1)
                    SetVehicleDoorsLockedForAllPlayers(veh, false)

                    flashLights(veh, 2)

                    if math.random(1,100) <= 40 then
                        StartVehicleAlarm(veh)
                        notify('error', 'Alarme disparado!')
                        TriggerServerEvent('nord_keys:sv:policeAlert', GetEntityCoords(veh))
                    end

                    if math.random(1,100) <= 50 then
                        TriggerServerEvent('nord_keys:sv:consumeLockpick')
                        notify('error', 'O lockpick partiu.')
                    end

                    TriggerServerEvent('nord_keys:sv:lockpickSuccess', plate)

                else
                    notify('error', 'Falhaste ao arrombar.')

                    if math.random(1,100) <= 70 then
                        TriggerServerEvent('nord_keys:sv:consumeLockpick')
                    end

                    TriggerServerEvent('nord_keys:sv:lockpickFail', plate)
                end
            end
        }
    })
end)

--===============================
-- Carjack (G)
--===============================
CreateThread(function()
    while true do
        Wait(0)

        local ped = PlayerPedId()

        if IsPedArmed(ped, 6) then
            local veh = GetClosestVehicle(GetEntityCoords(ped), 5.0, 0, 70)

            if veh ~= 0 then
                local driver = GetPedInVehicleSeat(veh, -1)

                if driver ~= 0 and not IsPedAPlayer(driver) then

                    if IsPlayerFreeAiming(PlayerId()) then
                        local aimed, target = GetEntityPlayerIsFreeAimingAt(PlayerId())

                        if aimed and target == driver then

                            -- NPC entra em pânico
                            TaskLeaveVehicle(driver, veh, 256)
                            SetVehicleDoorsLocked(veh, 1)
                            SetVehicleEngineOn(veh, true, true, false)

                            -- Dar acesso temporário
                            local plate = GetVehicleNumberPlateText(veh)
                            TriggerServerEvent("nord_keys:sv:lockpickSuccess", plate)

                            Wait(3000)
                        end
                    end
                end
            end
        end
    end
end)

--===============================
-- PED: Chaves Perdidas
--===============================
local keyLossPed

local function spawnKeyLossPed()
  if not (Config.KeyLossNPC and Config.KeyLossNPC.enabled) then return end

  local hash = joaat(Config.KeyLossNPC.model)
  RequestModel(hash)
  while not HasModelLoaded(hash) do Wait(0) end

  local c = Config.KeyLossNPC.coords
  keyLossPed = CreatePed(0, hash, c.x, c.y, c.z - 1.0, c.w, false, true)

  SetEntityInvincible(keyLossPed, true)
  SetBlockingOfNonTemporaryEvents(keyLossPed, true)
  FreezeEntityPosition(keyLossPed, true)

  if Config.KeyLossNPC.scenario and Config.KeyLossNPC.scenario ~= '' then
    TaskStartScenarioInPlace(keyLossPed, Config.KeyLossNPC.scenario, 0, true)
  end

  if Config.KeyLossNPC.useOxTarget then
    exports.ox_target:addLocalEntity(keyLossPed, {
      {
        label = 'Recuperar chave (perdida)',
        icon = 'fa-solid fa-key',
        onSelect = function()
          TriggerEvent('nord_keys:cl:recoverLostKey')
        end
      }
    })
  end
end

CreateThread(function()
  Wait(1500)
  spawnKeyLossPed()
end)

RegisterNetEvent('nord_keys:cl:recoverLostKey', function()
  local veh = getClosestVehicle()

  if Config.KeyLossNPC.requireNearVehicle then
    if not veh then
      notify('error', 'Aproxima-te do veículo para recuperar a chave.')
      return
    end

    local ped = PlayerPedId()
    local dist = #(GetEntityCoords(ped) - GetEntityCoords(veh))
    if dist > (Config.KeyLossNPC.maxVehicleDist or 8.0) then
      notify('error', 'Estás demasiado longe do veículo.')
      return
    end
  end

  if not veh then
    notify('error', 'Nenhum veículo encontrado perto.')
    return
  end

  local plate = normPlate(GetVehicleNumberPlateText(veh))
  if plate == '' then return end

  lib.progressBar({
    duration = 2500,
    label = 'A verificar propriedade...',
    useWhileDead = false,
    canCancel = false,
    disable = { move = true, car = true, combat = true }
  })

  TriggerServerEvent('nord_keys:sv:recoverLostKey', plate)
end)

-- =========================================
-- OX INVENTORY ITEM EVENT (ABRIR KEY FOB)
-- =========================================

RegisterNetEvent('nord_keys:client:useKeyFob', function(item)
    if not item or not item.slot then return end

    -- pede ao server para validar e enviar plate
    TriggerServerEvent('nord_keys:sv:openKeyFobFromSlot', item.slot)
end)



-- Key Fob NUI (opens when using item)
--===============================
local currentPlate

local currentPlate = nil
local rangeThread = nil
local isOutOfRange = false

RegisterNetEvent('nord_keys:client:openKeyFob', function(plate, battery, theme)
    if not plate or plate == '' then
        notify('error', 'Chave inválida.')
        return
    end

    plate = normPlate(plate)
    currentPlate = plate

    isOutOfRange = false
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'openFob',
        plate = plate,
        battery = tonumber(battery) or 100,
        theme = theme or 'bmw' -- 👈 agora vem do server (metadata)
    })

    if rangeThread then return end

    rangeThread = CreateThread(function()
        while currentPlate do
            Wait(500)

            local v = getVehicleByPlate(currentPlate)
            local out = true

            if v and v ~= 0 then
                local ped = PlayerPedId()
                local dist = #(GetEntityCoords(ped) - GetEntityCoords(v))
                out = dist > 15.0
            end

            if out ~= isOutOfRange then
                isOutOfRange = out
                SendNUIMessage({ action = 'outOfRange', state = isOutOfRange })
            end
        end

        rangeThread = nil
    end)
end)

RegisterNUICallback('fobAction', function(data, cb)
    local action = data and data.action
    if not currentPlate or currentPlate == '' then cb(true) return end

    local hasItem = exports.ox_inventory:Search('count', 'vehicle_key', { plate = currentPlate }) or 0
    if hasItem <= 0 then
        notify('error', 'Não tens a chave deste veículo.')
        cb(true)
        return
    end

    hasAccessAsync(currentPlate, function(ok)
        if not ok then
            notify('error', 'Não tens a chave deste veículo.')
            return
        end

        local veh = getVehicleByPlate(currentPlate)
        if not veh then
            notify('error', 'Sem sinal do veículo.')
            return
        end

        playKeyAnim()

        if action == 'lock' then
            SetVehicleDoorsLocked(veh, 2)
            SetVehicleDoorsLockedForAllPlayers(veh, true)
            flashLights(veh, 2)
            notify('success', Config.Text.locked)

        elseif action == 'unlock' then
            SetVehicleDoorsLocked(veh, 1)
            SetVehicleDoorsLockedForAllPlayers(veh, false)
            flashLights(veh, 1)
            notify('success', Config.Text.unlocked)

        elseif action == 'trunk' then
            trunkToggle(veh)
        end
    end)

    cb(true)
end)