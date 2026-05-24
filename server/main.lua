local QBCore = exports['qb-core']:GetCoreObject()
local bank = exports['Renewed-Banking']
lib.locale()
lib.versionCheck('gabovrs/vrs_garage')

lib.callback.register('vrs_garage:checkOwner', function(source, plate)
    local plate = string.gsub(plate, ' ', '')
    local result = CustomSQL('query', 'SELECT citizenid FROM player_vehicles WHERE REPLACE(plate, " ", "") = ?', {plate})
    if #result > 0 then
        return result[1].citizenid
    end
end)

lib.callback.register('vrs_garage:getVehicles', function(source, job)
    local player = QBCore.Functions.GetPlayer(source)
    if not player then return {} end
    
    local citizenId = player.PlayerData.citizenid
    local result

    if job then
        result = CustomSQL('query', "SELECT plate, state, garage, impound, JSON_MERGE_PATCH(JSON_OBJECT('model', vehicle, 'fuelLevel', fuel, 'engineHealth', engine, 'bodyHealth', body), mods) as data FROM player_vehicles WHERE citizenid = ? AND job = ? ORDER BY state DESC", {citizenId, job})
    else
        result = CustomSQL("query", "SELECT plate, state, garage, impound, JSON_MERGE_PATCH(JSON_OBJECT('model', vehicle, 'fuelLevel', fuel, 'engineHealth', engine, 'bodyHealth', body), mods) as data FROM player_vehicles WHERE citizenid = ? ORDER BY state DESC", {citizenId})
    end

    if not result or #result == 0 then 
        return {} 
    end

    for i = 1, #result do
        if result[i] and result[i].data then
            -- Decodifica la stringa JSON inviata da SQL in tabella Lua
            result[i].data = json.decode(result[i].data)
        else
            result[i].data = {}
        end
    end

    return result
end)

lib.callback.register('vrs_garage:getImpoundedVehicles', function(source)
    local player = QBCore.Functions.GetPlayer(source)
    if not player then return {} end -- Sicurezza: se il player non è caricato
    
    local citizenId = player.PlayerData.citizenid
    
    local result = CustomSQL('query', "SELECT plate, state, garage, impound, JSON_MERGE_PATCH(JSON_OBJECT('model', vehicle, 'fuelLevel', fuel, 'engineHealth', engine, 'bodyHealth', body), mods) as data FROM player_vehicles WHERE citizenid = ? AND impound = 1", {citizenId})

    -- Se result è nil o la tabella è vuota, ritorna subito una tabella vuota
    if not result or #result == 0 then 
        return {} 
    end

    for i = 1, #result do
        -- Verifichiamo che la riga i esista e che contenga il campo data
        if result[i] and result[i].data then
            result[i].data = json.decode(result[i].data)
        else
            -- Se data è mancante per qualche riga, inizializziamo a tabella vuota
            if result[i] then result[i].data = {} end
        end
    end

    return result
end)

lib.callback.register('vrs_garage:canPay', function(source, amount)
    local player = QBCore.Functions.GetPlayer(source)
    if not player then return false end

    -- DEBUG: Vediamo quanto costa e chi paga
    print(string.format("^3[DEBUG]^7 Tentativo di pagamento: Source [%s], Importo [%s]", source, amount))

    local itemCount = exports.ox_inventory:Search(source, 'count', 'money')
    
    -- DEBUG: Vediamo quanti soldi trova ox_inventory
    print(string.format("^3[DEBUG]^7 Soldi trovati in inventario: %s", itemCount))

    if itemCount >= amount then
        -- 2. Tentativo di rimozione
        local removed = exports.ox_inventory:RemoveItem(source, 'cash', amount)
        
        if removed then
            print("^2[DEBUG]^7 Pagamento completato con successo.")
            return true
        else
            print("^1[DEBUG]^7 Errore durante RemoveItem (forse l'item è bloccato o insufficiente?)")
        end
    else
        print("^1[DEBUG]^7 Soldi insufficienti.")
    end

    return false
end)

lib.callback.register('vrs_garage:getVehicle', function(source, plate)
    local cleanPlate = string.gsub(plate, ' ', '')
    local player = QBCore.Functions.GetPlayer(source)
    if not player then return nil end
    
    local citizenId = player.PlayerData.citizenid

    local result = CustomSQL('query', "SELECT plate, state, garage, impound, job, JSON_MERGE_PATCH(JSON_OBJECT('model', vehicle, 'fuelLevel', fuel, 'engineHealth', engine, 'bodyHealth', body), mods) as data FROM player_vehicles WHERE REPLACE(plate, ' ', '') = ? AND citizenid = ?", {cleanPlate, citizenId})

    if result and result[1] then
        local vehicleData = result[1]
        
        if vehicleData.data then
            vehicleData.data = json.decode(vehicleData.data)
        else
            vehicleData.data = {}
        end
        
        return vehicleData
    end

    return nil
end)

RegisterServerEvent('vrs_garage:updateVehicle', function(plate, vehicle, garage, stored)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid

    print('Updating vehicle for citizenid:', citizenid, 'plate:', plate, 'garage:', garage, 'stored:', stored)

    local cleanPlate = string.gsub(plate, '%s+', '')

    local fuel = math.ceil(vehicle.fuelLevel or 0)
    local engine = vehicle.engineHealth or 1000.0
    local body = vehicle.bodyHealth or 1000.0

    local mods = json.encode(vehicle)

    CustomSQL('update', [[
        UPDATE player_vehicles 
        SET garage = ?, fuel = ?, engine = ?, body = ?, mods = ?, state = ?
        WHERE REPLACE(plate, ' ', '') = ? AND citizenid = ?
    ]], {
        garage,
        fuel,
        engine,
        body,
        mods,
        stored,
        cleanPlate,
        citizenid
    })
end)

RegisterServerEvent('vrs_garage:buyVehicle', function(plate, vehicle, garage, job)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end


    local citizenid = Player.PlayerData.citizenid

    local vehicleType = job and Config.JobGarajes[job] and Config.JobGarajes[job].locations[garage] and Config.JobGarajes[job].locations[garage].type or Config.Garages[garage] and Config.Garages[garage].type or 'car'

    local cleanPlate = string.gsub(plate, '%s+', '')

    local props = json.encode(vehicle)

    CustomSQL('insert', [[
        INSERT INTO player_vehicles 
        (citizenid, vehicle, plate, mods, garage, state, fuel, engine, body, job)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        citizenid,
        vehicle.model,
        cleanPlate,
        props,
        garage,
        1, -- in garage
        vehicle.fuelLevel or 100,
        vehicle.engineHealth or 1000,
        vehicle.bodyHealth or 1000,
        job
    })
end)

RegisterServerEvent('vrs_garage:setVehicleOut', function(plate)
    local plate = string.gsub(plate, ' ', '')
    local player = QBCore.Functions.GetPlayer(source)
    local citizenId = player.PlayerData.citizenid
    CustomSQL('update',
        'UPDATE player_vehicles SET garage = NULL, impound = NULL, state = NULL WHERE REPLACE(plate, " ", "") = ? and citizenid = ?',
        {plate, citizenId})
end)

RegisterServerEvent('vrs_garage:setVehicleParking', function(plate, garage)
    local player = QBCore.Functions.GetPlayer(source)
    local citizenId = player.PlayerData.citizenid
    print(citizenId, plate, garage)
    CustomSQL('update', 'UPDATE player_vehicles SET garage = ?, state = 1 WHERE plate = ? and citizenid = ?',
        {garage, plate, citizenId})
end)

RegisterServerEvent('vrs_garage:setVehicleImpound', function(plate, impound)
    local player = QBCore.Functions.GetPlayer(source)
    local citizenId = player.PlayerData.citizenid
    CustomSQL('update', 'UPDATE player_vehicles SET impound = ?, state = 1 WHERE plate = ? and citizenid = ?',
        {impound, plate, citizenId})
end)

lib.callback.register('vrs_garage:setPlayerRoutingBucket', function(source, bucket)
    if not bucket then
        bucket = math.random(1000)
    end
    SetPlayerRoutingBucket(source, bucket)
    return true
end)

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    
end)

function CustomSQL(type, action, placeholder)
    local result = nil
    if Config.MySQL == 'oxmysql' then
        if type == 'query' then
            result = exports.oxmysql:query_async(action, placeholder)
        elseif type == 'update' then
            result = exports.oxmysql:update(action, placeholder)
        elseif type == 'insert' then
            result = exports.oxmysql:insert(action, placeholder)
        end
    elseif Config.MySQL == 'mysql-async' then
        if type == 'query' then
            result = MySQL.Sync.query(action, placeholder)
        elseif type == 'update' then
            result = MySQL.Async.execute(action, placeholder)
        elseif type == 'insert' then
            result = MySQL.Async.insert(action, placeholder)
        end
    elseif Config.MySQL == 'ghmattisql' then
        if type == 'query' then
            result = exports.ghmattimysql:executeSync(action, placeholder)
        elseif type == 'update' then
            result = exports.ghmattimysql:execute(action, placeholder)
        elseif type == 'insert' then
            result = exports.ghmattimysql:execute(action, placeholder)
        end
    end
    return result
end

--[[
if Config.ImpoundCommandEnabled then
    ESX.RegisterCommand(Config.ImpoundCommand.command, 'user', function(xPlayer, args, showError)
        for k, job in pairs(Config.ImpoundCommand.jobs) do
            if xPlayer.getJob().name == job then
                xPlayer.triggerEvent('vrs_garage:impoundVehicle')
            end
        end
    end, false, {
        help = locale('command_impound')
    })    
end
]]

RegisterCommand('autogratis', function(source)
    local player = exports.qbx_core:GetPlayer(source)
    
    if player then
        local result = CustomSQL('query', [[
            SELECT * FROM player_vehicles WHERE citizenid = ? AND plate = ?]], {
            player.PlayerData.citizenid,
            player.PlayerData.citizenid
        })

        if result and #result > 0 then
            print("^1[DEBUG]^7 Il giocatore ha già un veicolo assegnato, non assegniamo un'auto gratuita.")
            exports.qbx_core:Notify(source, "Hai già ricevuto l'auto gratis", "error")
            return
        end

        -- Controlliamo il metadato 'isnew' (o 'newbie' a seconda della versione)
        -- Di default, alla creazione del personaggio è true
        --if player.PlayerData.metadata['isnew'] or player.PlayerData.metadata['newbie'] then
            
        print("^2[INFO]^7 Nuovo personaggio rilevato: " .. player.PlayerData.citizenid)
        
        local citizenid = player.PlayerData.citizenid -- Il CID del nuovo personaggio
        local vehicleModel = Config.FirstCar.model       -- Modello dell'auto (usa le backtick o GetHashKey)
        local plate = citizenid -- Genera una targa semplice
        
        print(string.format("^2[INFO]^7 Assegnando veicolo %s con targa %s a citizenid %s", vehicleModel, plate, citizenid))

        -- Definiamo le proprietà del veicolo (colore, modifiche, ecc.)
        -- Qbox usa solitamente qbx_vehiclekeys o script simili per le chiavi
        local vehicleProps = {
            model = vehicleModel,
            plate = plate,
        }
        -- Save vehicle in database
        CustomSQL('insert', [[
            INSERT INTO player_vehicles(license, citizenid, vehicle, hash, mods, plate, state)
            VALUES (?, ?, ?, ?, ?, ?, ?)]], {
            player.PlayerData.license,
            citizenid,
            Config.FirstCar.model, -- Nome del modello come stringa
            vehicleModel, -- Hash del modello
            json.encode(vehicleProps),
            plate,
            0
        })

        local coords = GetEntityCoords(GetPlayerPed(source))
        
        local vehicle = QBCore.Functions.SpawnVehicle(source, vehicleProps.model, coords, true, function (veh)
            SetEntityHeading(veh, coords.w) -- Set heading
            TaskWarpPedIntoVehicle(GetPlayerPed(source), veh, -1) -- Put player in seat
            TriggerClientEvent('qb-vehiclekeys:client:AddKeys', source, vehicleProps.plate)
            --TriggerServerEvent('qb-vehiclekeys:server:AcquireVehicleKeys', source, vehicleProps.plate)
            --TriggerEvent("qb-vehiclekeys:server:GiveVehicleKeys", source, vehicleProps.plate) -- Set keys
            SetVehicleEngineOn(veh, true, true)
        end)

        SetVehicleNumberPlateText(vehicle, vehicleProps.plate)
            
        Entity(vehicle).state.plate = vehicleProps.plate
        
        --[[
        Inseriamo l'auto nel database dei veicoli posseduti
        Nota: Assicurati che il nome della tabella sia 'player_vehicles' (default QB/QBX)
        ]]
        
        print("^2[Auto Iniziale]^7 Veicolo assegnato a " .. citizenid .. " con targa: " .. plate)
                
        -- Opzionale: Notifica il giocatore
        exports.qbx_core:Notify(source, "Hai ricevuto una " .. Config.FirstCar.model .. " come regalo di benvenuto! La trovi nel garage centrale.", "success")
        
        print("^2[INFO]^7 Metadati aggiornati, regalo consegnato.")
    end
end, false)