# 🔐 Nord Keys -- Integration Exports

Este ficheiro documenta os exports necessários para integrar o
`nord_keys` com:

-   🚗 JG Dealerships (dar chave ao comprar veículo)
-   🏢 Sistemas de garagem (remover chave ao vender / guardar
    permanentemente)
-   🔎 Verificação de acesso

------------------------------------------------------------------------

# 🔑 1️⃣ Dar Chave (JG Dealerships)

## Uso (CLIENT)

``` lua
exports["nord_keys"]:GiveKeyByPlate(plate)
```

### Exemplo:

``` lua
exports["nord_keys"]:GiveKeyByPlate("ABC123")
```

### O que faz:

-   Cria registo na base de dados
-   Adiciona item `vehicle_key` ao inventário
-   Aplica automaticamente o tema correto

------------------------------------------------------------------------

# ❌ 2️⃣ Remover Chave (Garagens / Venda)

## Uso (CLIENT)

``` lua
exports["nord_keys"]:RemoveKeyByPlate(plate)
```

### Exemplo:

``` lua
exports["nord_keys"]:RemoveKeyByPlate("ABC123")
```

### O que faz:

-   Remove registo da base de dados
-   Remove item físico do inventário

------------------------------------------------------------------------

# 🔐 3️⃣ Verificar se Jogador Tem Chave

## Uso (SERVER)

``` lua
exports["nord_keys"]:HasKey(source, plate)
```

### Exemplo:

``` lua
local hasKey = exports["nord_keys"]:HasKey(source, "ABC123")

if hasKey then
    print("Jogador tem chave.")
end
```

### O que faz:

-   Verifica acesso via item físico
-   Verifica master key (se configurado)

------------------------------------------------------------------------

# 📌 Notas Importantes

-   Os exports `GiveKeyByPlate` e `RemoveKeyByPlate` devem ser chamados
    **no client**.
-   O export `HasKey` deve ser usado **no server**.
-   Nunca passes o player id manualmente no client.
-   A matrícula é sempre normalizada automaticamente.

------------------------------------------------------------------------

# ✅ Compatível com

-   JG Dealerships
-   OP Garages
-   QBCore
-   ESX (com bridge)
-   ox_inventory

------------------------------------------------------------------------

# 🚀 Pronto para produção

Sistema totalmente server-authoritative e seguro.
