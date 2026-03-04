NRKeysOwned = {}

-- Retorna owner identifier pelo plate (se a tua tabela existir)
function NRKeysOwned.GetOwnerIdentifierByPlate(plate)
  if not Config.OwnedVehicles or not Config.OwnedVehicles.enabled then return nil end
  if not plate or plate == '' then return nil end

  local mode = Config.OwnedVehicles.mode or 'auto'

  if Config.Framework == 'qb' then
    -- comum: player_vehicles (plate, citizenid)
    if mode == 'auto' or mode == 'qb_player_vehicles' then
      local row = MySQL.single.await('SELECT citizenid FROM player_vehicles WHERE plate = ? LIMIT 1', { plate })
      return row and row.citizenid or nil
    end
  end

  if Config.Framework == 'esx' then
    -- comum: owned_vehicles (plate, owner)
    if mode == 'auto' or mode == 'esx_owned_vehicles' then
      local row = MySQL.single.await('SELECT owner FROM owned_vehicles WHERE plate = ? LIMIT 1', { plate })
      return row and row.owner or nil
    end
  end

  return nil
end