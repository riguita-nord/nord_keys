# nord_keys - Exports de Integracao

Documentacao oficial dos exports disponiveis no resource `nord_keys`.

## Client Exports

### GiveKeyByPlate(plate)
Entrega chave ao jogador local para a placa informada.

```lua
exports['nord_keys']:GiveKeyByPlate('ABC123')
```

Retorno:
- `true`: evento enviado ao servidor
- `false`: placa invalida

Observacao:
- Este export e assincrono (fire-and-forget). O retorno indica apenas validacao local/envio do evento.

### RemoveKeyByPlate(plate)
Remove chave do jogador local para a placa informada.

```lua
exports['nord_keys']:RemoveKeyByPlate('ABC123')
```

Retorno:
- `true`: evento enviado ao servidor
- `false`: placa invalida

### GiveVehicleKey(plate)
Alias de compatibilidade para `GiveKeyByPlate`.

```lua
exports['nord_keys']:GiveVehicleKey('ABC123')
```

### RemoveVehicleKey(plate)
Alias de compatibilidade para `RemoveKeyByPlate`.

```lua
exports['nord_keys']:RemoveVehicleKey('ABC123')
```

## Server Exports

### HasKey(source, plate)
Verifica se o jogador tem acesso ao veiculo.

```lua
local hasKey = exports['nord_keys']:HasKey(source, 'ABC123')
```

Retorno:
- `true` se tiver acesso (owner/master/DB/item fisico)
- `false` caso contrario

### HasVehicleAccess(source, plate)
Alias semantico de `HasKey`.

```lua
local allowed = exports['nord_keys']:HasVehicleAccess(source, 'ABC123')
```

### GetVehicleTheme(plate)
Retorna tema visual da chave (`audi` ou `bmw`).

```lua
local theme = exports['nord_keys']:GetVehicleTheme('ABC123')
```

### GiveVehicleKey(source, plate)
Cria vinculo no DB e adiciona item de chave ao jogador.

```lua
local ok = exports['nord_keys']:GiveVehicleKey(source, 'ABC123')
```

### RemoveVehicleKey(source, plate)
Remove vinculo no DB e tenta remover item fisico.

```lua
local ok = exports['nord_keys']:RemoveVehicleKey(source, 'ABC123')
```

### HasDBKey(source, plate)
Verifica apenas vinculo no banco (`nord_vehicle_keys`).

```lua
local hasDb = exports['nord_keys']:HasDBKey(source, 'ABC123')
```

### GiveKeyByPlate(source, plate)
Mesmo comportamento de `GiveVehicleKey` (nome legado/compatibilidade).

```lua
local ok = exports['nord_keys']:GiveKeyByPlate(source, 'ABC123')
```

### RemoveKeyByPlate(source, plate)
Mesmo comportamento de `RemoveVehicleKey` (nome legado/compatibilidade).

```lua
local ok = exports['nord_keys']:RemoveKeyByPlate(source, 'ABC123')
```

### HasKeyByPlate(source, plate)
Alias de compatibilidade para `HasKey`.

```lua
local hasKey = exports['nord_keys']:HasKeyByPlate(source, 'ABC123')
```

### RemoveKey(source, plate)
Alias de compatibilidade para `RemoveKeyByPlate`.

```lua
local ok = exports['nord_keys']:RemoveKey(source, 'ABC123')
```

### GiveKey(source, plate, toIdentifier, grantedBy)
Concede chave para um identificador especifico (fluxo administrativo/integracao avancada).

```lua
local ok = exports['nord_keys']:GiveKey(source, 'ABC123', 'license:xxxxxxxx', 'dealership')
```

### RevokeKey(source, plate, fromIdentifier)
Revoga chave de um identificador especifico.

```lua
local ok = exports['nord_keys']:RevokeKey(source, 'ABC123', 'license:xxxxxxxx')
```

### GiveTemporaryKey(source, plate, targetSource, minutes)
Concede chave temporaria para outro jogador.

```lua
local ok = exports['nord_keys']:GiveTemporaryKey(source, 'ABC123', targetSource, 30)
```

## Integracao recomendada

- Dealership/compra: use `GiveKeyByPlate` no client ou `GiveVehicleKey` no server.
- Garagem/venda/perda definitiva: use `RemoveKeyByPlate` no client ou `RemoveVehicleKey` no server.
- Validacao de acesso: use `HasKey` no server.

## Notas importantes

- A placa e normalizada automaticamente (uppercase, sem espacos).
- Exports de client nao retornam confirmacao de DB; apenas validacao local/envio de evento.
- Para operacoes criticas, prefira chamar exports server-side.

## Compatibilidade

- QBCore
- ESX (via bridge)
- ox_inventory
- oxmysql
