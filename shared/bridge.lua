Bridge = {}

local function dbg(...)
  if Config.Debug then
    print("^3[nord_keys:bridge]^7", ...)
  end
end

local function GetQB()
  local ok, qb = pcall(function()
    return exports['qb-core']:GetCoreObject()
  end)
  if ok and qb then return qb end
  return nil
end

function Bridge.Notify(src, typ, msg, title)
  TriggerClientEvent('ox_lib:notify', src, {
    type = typ or 'inform',
    title = title,
    description = msg or ''
  })
end

function Bridge.GetIdentifier(src)
  if Config.Framework == 'qb' then
    local QBCore = GetQB()
    if not QBCore then return nil end
    local ply = QBCore.Functions.GetPlayer(src)
    return ply and ply.PlayerData and ply.PlayerData.citizenid or nil
  end

  if Config.Framework == 'esx' then
    local xPlayer = ESX.GetPlayerFromId(src)
    return xPlayer and xPlayer.identifier or nil
  end

  return nil
end

function Bridge.GetJobName(src)
  if Config.Framework == 'qb' then
    local QBCore = GetQB()
    if not QBCore then return nil end
    local ply = QBCore.Functions.GetPlayer(src)
    return ply and ply.PlayerData and ply.PlayerData.job and ply.PlayerData.job.name or nil
  end

  if Config.Framework == 'esx' then
    local xPlayer = ESX.GetPlayerFromId(src)
    local job = xPlayer and xPlayer.getJob and xPlayer.getJob() or nil
    return job and job.name or nil
  end

  return nil
end

function Bridge.IsMasterKey(src)
  local job = Bridge.GetJobName(src)
  if not job then return false end
  for _, j in ipairs(Config.MasterKeyJobs or {}) do
    if j == job then return true end
  end
  return false
end