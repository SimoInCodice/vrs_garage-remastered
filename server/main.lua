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

lib.callback.register('vrs_garage:getVehicles', function(source, job, type)
    print('Callback getVehicles called with job:', job, 'and type:', type)
    QBCore.Debug(source, job, type)
    local player = QBCore.Functions.GetPlayer(source)
    QBCore.Debug(player)
    local citizenId = player.PlayerData.citizenid
    local result
    if job then
        result = CustomSQL('query', 'SELECT * FROM player_vehicles WHERE citizenid = ? and job = ? and type = ? ORDER BY stored DESC',
            {citizenId, job, type})
    else
        result = CustomSQL('query', 'SELECT * FROM player_vehicles WHERE citizenid = ? and type = ? ORDER BY stored DESC', {citizenId, type})
    end
    return result
end)

lib.callback.register('vrs_garage:getImpoundedVehicles', function(source, type)
    local player = QBCore.Functions.GetPlayer(source)
    local citizenId = player.PlayerData.citizenid
    local result = CustomSQL('query', 'SELECT * FROM player_vehicles WHERE citizenid = ? and impound = 1 and type = ?', {citizenId, type})
    return result
end)

lib.callback.register('vrs_garage:canPay', function(source, amount)
    local player = QBCore.Functions.GetPlayer(source)
    local citizenId = player.PlayerData.citizenid
    local playerMoney = bank:getAccountMoney(citizenId) -- Get the Current Player`s Balance.
    if playerMoney >= amount then -- check if the Player`s Money is more or equal to the cost.
        bank:removeAccountMoney(citizenId, amount) -- remove Cost from balance
        return true
    else
        return false
    end
end)

lib.callback.register('vrs_garage:getVehicle', function(source, plate)
    local plate = string.gsub(plate, ' ', '')
    local player = QBCore.Functions.GetPlayer(source)
    local citizenId = player.PlayerData.citizenid
    local result = CustomSQL('query', 'SELECT * FROM player_vehicles WHERE REPLACE(plate, " ", "") = ? and citizenid = ?', {plate, citizenId})
    return result[1]
end)

RegisterServerEvent('vrs_garage:updateVehicle', function(plate, vehicle, garage)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid

    -- pulizia targa
    local cleanPlate = string.gsub(plate, '%s+', '')

    -- dati veicolo
    local fuel = math.ceil(vehicle.fuelLevel or 0)
    local engine = vehicle.engineHealth or 1000.0
    local body = vehicle.bodyHealth or 1000.0

    -- 🔥 mods complete
    local mods = json.encode(vehicle)

    CustomSql('update', [[
        UPDATE player_vehicles 
        SET garage = ?, fuel = ?, engine = ?, body = ?, mods = ?
        WHERE REPLACE(plate, ' ', '') = ? AND citizenid = ?
    ]], {
        garage,
        fuel,
        engine,
        body,
        mods,
        cleanPlate,
        citizenid
    })
end)

RegisterServerEvent('vrs_garage:buyVehicle', function(plate, vehicle, garage, job)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    local citizenid = Player.PlayerData.citizenid

    local cleanPlate = string.gsub(plate, '%s+', '')

    local props = json.encode(vehicle)

    CustomSql('insert', [[
        INSERT INTO player_vehicles 
        (citizenid, vehicle, plate, mods, garage, state, fuel, engine, body)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        citizenid,
        vehicle.model,
        cleanPlate,
        props,
        garage,
        1, -- in garage
        vehicle.fuelLevel or 100,
        vehicle.engineHealth or 1000,
        vehicle.bodyHealth or 1000
    })
end)

RegisterServerEvent('vrs_garage:setVehicleOut', function(plate)
    local plate = string.gsub(plate, ' ', '')
    local player = QBCore.Functions.GetPlayer(source)
    local citizenId = player.PlayerData.citizenid
    CustomSQL('update',
        'UPDATE player_vehicles SET garage = NULL, impound = NULL WHERE REPLACE(plate, " ", "") = ? and citizenid = ?',
        {plate, citizenId})
end)

RegisterServerEvent('vrs_garage:setVehicleParking', function(plate, garage)
    local player = QBCore.Functions.GetPlayer(source)
    local citizenId = player.PlayerData.citizenid
    CustomSQL('update', 'UPDATE player_vehicles SET garage = ? WHERE plate = ? and citizenid = ?',
        {garage, plate, citizenId})
end)

RegisterServerEvent('vrs_garage:setVehicleImpound', function(plate, impound)
    local player = QBCore.Functions.GetPlayer(source)
    local citizenId = player.PlayerData.citizenid
    CustomSQL('update', 'UPDATE player_vehicles SET impound = ? WHERE plate = ? and citizenid = ?',
        {impound, plate, citizenId})
end)

lib.callback.register('vrs_garage:setPlayerRoutingBucket', function(source, bucket)
    if not bucket then
        bucket = math.random(1000)
    end
    SetPlayerRoutingBucket(source, bucket)
    return true
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