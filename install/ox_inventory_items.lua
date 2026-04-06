-- Add this block to ox_inventory/data/items.lua
-- Then restart ox_inventory and nord_keys.

['vehicle_key'] = {
    label = 'Car Key',
    weight = 50,
    stack = false,
    close = true,
    description = 'Chave de veiculo',
    client = {
        image = 'car_key.png',
        event = 'nord_keys:client:useKeyFob'
    }
},
