ESX = exports["es_extended"]:getSharedObject()

lib.locale()

local ox_inventory = exports.ox_inventory

local vehiculoCreado, vehiclesSpawned = {}, {}

function SP(plate)
    return string.gsub(plate, "^%s*(.-)%s*$", "%1")
end

function CrearVehiculo(model, coords, heading, props)
    local vehicle = CreateVehicleServerSetter(model, "automobile", coords.x, coords.y, coords.z, heading)

    while not DoesEntityExist(vehicle) do
        Wait(0)
    end
    vehiculoCreado[vehicle] = SP(props.plate)

    Entity(vehicle).state.CrearVehiculo = props

    Entity(vehicle).state.fuel = props.fuelLevel

    return vehicle
end

AddEventHandler('entityRemoved', function(entity)
    local tipo = GetEntityType(entity)
    if tipo == 2 then
        vehiculoCreado[entity] = nil
    end
end)

lib.callback.register('mono_garage:getOwnerVehicles', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)

    local identifier = xPlayer.identifier

    local vehicles = MySQL.query.await("SELECT * FROM owned_vehicles WHERE owner = ? OR amigos LIKE ?",
        { identifier, '%' .. identifier .. '%' })

    for i, result in ipairs(vehicles) do
        local amigos = json.decode(result.amigos)
        local isOwner = result.owner == identifier
        if not isOwner and amigos then
            for j, amigo in ipairs(amigos) do
                if amigo.identifier == identifier then
                    isOwner = false
                    break
                end
            end
        end
        result.isOwner = isOwner
    end

    return vehicles
end)


lib.callback.register('mono_garage:GetPlayerNamePlate', function(source, plate)
    local result = MySQL.query.await(
        "SELECT owner, firstname, lastname FROM owned_vehicles JOIN users ON owned_vehicles.owner = users.identifier WHERE plate = ?",
        { plate })
    if result and #result > 0 then
        local name = result[1].firstname .. ' ' .. result[1].lastname
        return name
    end
end)


lib.callback.register('mono_garage:ChangePlateOwner', function(source, plate)
    local xPlayer = ESX.GetPlayerFromId(source)
    local identifier = xPlayer.identifier

    local owner = MySQL.query.await(
        "SELECT * FROM owned_vehicles WHERE owner = @identifier", {
            ['@identifier'] = identifier,
        })

    for i, result in ipairs(owner) do
        if result.plate == plate then
            return true
        end
    end

    return false
end)

--[[lib.callback.register('mono_garage:GetTotalKm', function(source, plate)
    local totalkm = MySQL.query.await("SELECT * FROM owned_vehicles")
    for _, vehicle in ipairs(totalkm) do
        if plate == vehicle.plate then

            return vehicle.mileage
        else
            return 0
        end
    end
end)
]]

lib.callback.register('mono_garage:GetVehicleCoords', function(source, plate1)
    local vehicles = MySQL.query.await("SELECT * FROM owned_vehicles")
    for i = 1, #vehicles do
        local data = vehicles[i]
        if SP(data.plate) == plate1 then
            local pos = json.decode(data.lastposition)
            if pos == nil then
                local allVeh = GetAllVehicles()
                for i = 1, #allVeh do
                    local plate = GetVehicleNumberPlateText(allVeh[i])
                    if SP(plate) == plate1 then
                        return GetEntityCoords(allVeh[i])
                    end
                end
            end
            return vec3(pos.x, pos.y, pos.z)
        end
    end
end)


lib.callback.register('mono_garage:getBankMoney', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    local bank = xPlayer.getAccount("bank")
    local money = xPlayer.getMoney()
    local job = xPlayer.getJob().name
    return { bank = bank.money, money = money, job = job }
end)



RegisterServerEvent('mono_garage:EliminarAmigo', function(Amigo, plate)
    if Garage.Debug.Prints then
        print('mono_garage:EliminarAmigo ' .. Amigo, plate)
    end
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    local xIndidentifier = xPlayer.identifier
    MySQL.query("SELECT amigos FROM owned_vehicles WHERE owner = ? AND plate = ?", { xIndidentifier, plate },
        function(result)
            if result[1] ~= nil then
                local amigosTable = {}
                if result[1].amigos ~= nil and result[1].amigos ~= '' then
                    amigosTable = json.decode(result[1].amigos)
                end
                local found = false
                for i, amigo in ipairs(amigosTable) do
                    if amigo.name == Amigo then
                        table.remove(amigosTable, i)
                        found = true
                        break
                    end
                end
                if found then
                    local amigosStr = json.encode(amigosTable)
                    if #amigosTable == 0 then
                        amigosStr = nil
                    end
                    MySQL.update("UPDATE owned_vehicles SET amigos = ? WHERE owner = ? AND plate = ?",
                        { amigosStr, xIndidentifier, plate },
                        function(rowsChanged)
                            if rowsChanged > 0 then
                                TriggerClientEvent('mono_garage:Notification', source,
                                    locale('AmigosLista1', Amigo, plate))
                            else
                                TriggerClientEvent('mono_garage:Notification', source,
                                    locale('AmigosLista2', Amigo, plate))
                            end
                        end)
                end
            end
        end)
end)

RegisterServerEvent('mono_garage:CompartirAmigo', function(Amigo, Name, plate)
    if Garage.Debug.Prints then
        print('mono_garage:CompartirAmigo ' .. Amigo, Name, plate)
    end
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    local xIndidentifier = xPlayer.identifier
    local xAmigo = ESX.GetPlayerFromId(Amigo)
    local identifier = xAmigo.identifier

    if identifier == xIndidentifier then
        return TriggerClientEvent('mono_garage:Notification', source, locale('noatimismo'))
    end

    MySQL.query("SELECT amigos FROM owned_vehicles WHERE owner = ? AND plate = ?", { xIndidentifier, plate },
        function(result)
            if result[1] ~= nil then
                local amigosTable = {}
                if result[1].amigos ~= nil and result[1].amigos ~= '' then
                    amigosTable = json.decode(result[1].amigos)
                end
                local amigoData = { name = Name, identifier = identifier }
                amigosTable[#amigosTable + 1] = amigoData
                local amigosStr = json.encode(amigosTable)
                MySQL.update("UPDATE owned_vehicles SET amigos = ? WHERE owner = ? AND plate = ?",
                    { amigosStr, xIndidentifier, plate },
                    function(rowsChanged)
                        if rowsChanged > 0 then
                            TriggerClientEvent('mono_garage:Notification', source,
                                locale('AmigosLista3', plate, xAmigo.getName()))
                            TriggerClientEvent('mono_garage:Notification', xAmigo.source, locale('AmigosLista4', plate))
                        else
                            TriggerClientEvent('mono_garage:Notification', source,
                                locale('AmigosLista5', xAmigo.getName()))
                        end
                    end)
            else
                if Garage.Debug.Prints then
                    print('No se pudo encontrar el vehículo con la matricula ' .. plate)
                end
            end
        end)
end)

RegisterServerEvent('mono_garage:GuardarVehiculo', function(plate, vehicleData, garageName, vehicle)
    if Garage.Debug.Prints then
        print('mono_garage:GuardarVehiculo ' .. plate, vehicleData, garageName, vehicle)
    end
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    local identifier = xPlayer.identifier
    local encontrado = false
    local vehicles = MySQL.query.await("SELECT * FROM owned_vehicles WHERE owner = ? OR amigos LIKE ?",
        { identifier, '%' .. identifier .. '%' })

    for i, result in ipairs(vehicles) do
        local amigos = json.decode(result.amigos)
        local isOwner = result.owner == identifier
        local cleanedPlate = SP(result.plate)

        if cleanedPlate == plate then
            encontrado = true
            if not isOwner and amigos then
                for j, amigo in ipairs(amigos) do
                    if amigo.identifier == identifier then
                        result.owner = amigo.identifier
                        break
                    end
                end
            end

            MySQL.update(
                "UPDATE owned_vehicles SET calle = 0, vehicle = ?, stored = 1, pound = NULL,  parking = ? WHERE  plate = ?",
                { json.encode(vehicleData), garageName, plate, },
                function(rowsChanged)
                    if rowsChanged > 0 then
                        local entity = NetworkGetEntityFromNetworkId(vehicle)
                        while true do
                            if GetPedInVehicleSeat(entity, -1) > 0 then
                                TaskLeaveVehicle(source, entity, 1)
                            else
                                break
                            end
                            Wait(0)
                        end
                        TriggerClientEvent('mono_garage:Notification', source, locale('SERVER_VehiculoGuardado'))
                        if Garage.CarKeys then
                            ox_inventory:RemoveItem(source, Keys.ItemName, 1,
                                { plate = plate, description = locale('key_description', plate) })
                        end
                        TriggerClientEvent('mono_garage:FadeOut', source, vehicle)
                        Wait(1500)
                        DeleteEntity(entity)
                        --vehiculoCreado[entity] = nil
                    else
                        TriggerClientEvent('mono_garage:Notification', source, locale('SERVER_ErrorGuardad'))
                    end
                end)
        end
    end
    if not encontrado then
        TriggerClientEvent('mono_garage:Notification', source, locale('NoEsTuyo'))
    end
end)


RegisterServerEvent('mono_garage:RetirarVehiculo', function(plateP, lastparking, pos, hea, model, intocar)
    if Garage.Debug.Prints then
        print('mono_garage:RetirarVehiculo ' .. plateP, lastparking, pos, hea, model, intocar)
    end
    local plate = SP(plateP)
    local source = source
    MySQL.query("SELECT vehicle FROM owned_vehicles WHERE plate = ?",
        { plate },
        function(result)
            if result and #result > 0 then
                local vehicleProps = json.decode(result[1].vehicle)
                MySQL.update(
                    "UPDATE owned_vehicles SET stored = 0, lastparking = ?, calle = 1 WHERE plate = ?",
                    { lastparking, plate, },
                    function(rowsChanged)
                        if rowsChanged > 0 then
                            local vehicle = CrearVehiculo(model, pos, hea, vehicleProps)
                            if Garage.CarKeys then
                                ox_inventory:AddItem(source, Keys.ItemName, 1,
                                    {
                                        plate = plate,
                                        description = locale('key_description', plate)
                                    })
                            end
                            if intocar then
                                while true do
                                    Wait(0)
                                    TaskWarpPedIntoVehicle(source, vehicle, -1)
                                    if GetPedInVehicleSeat(vehicle, -1) > 0 then
                                        break
                                    end
                                end
                            end
                            TriggerClientEvent('mono_garage:Notification', source, locale('SERVER_retirar'))
                        else
                            TriggerClientEvent('mono_garage:Notification', source, locale('SERVER_ErrorRetirar'))
                        end
                    end)
            else
                TriggerClientEvent('mono_garage:Notification', source, locale('SERVER_ErrorRetirar'))
            end
        end)
end)

RegisterServerEvent('mono_garage:RetirarVehiculoImpound', function(plate, money, price, pos, hea, intocar, society)
    if Garage.Debug.Prints then
        print('mono_garage:RetirarVehiculoImpound ' .. plate, money, price, pos, hea, intocar)
    end
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    local identifier = xPlayer.identifier
    local bank = xPlayer.getAccount("bank")
    local price = price
    local function RetirarVehiculo(dinero)
        MySQL.query("SELECT * FROM owned_vehicles WHERE plate = ?",
            { plate },
            function(result)
                if result and #result > 0 then
                    local vehicleProps = json.decode(result[1].vehicle)
                    local info = result[1].infoimpound and json.decode(result[1].infoimpound) or {}
                    if dinero >= (info.price or price) then
                        local lastparkingResult = MySQL.query.await(
                            "SELECT lastparking FROM owned_vehicles WHERE owner = ? AND plate = ?", { identifier, plate })
                        local lastparking = lastparkingResult[1].lastparking
                        MySQL.update(
                            "UPDATE owned_vehicles SET pound = NULL, infoimpound = NULL, parking = ?, calle = 1  WHERE owner = ? AND plate = ?",
                            { lastparking, identifier, plate },
                            function(rowsChanged)
                                if rowsChanged > 0 then
                                    local entity = CrearVehiculo(vehicleProps.model, pos, hea, vehicleProps)

                                    if Garage.CarKeys then
                                        ox_inventory:AddItem(source, Keys.ItemName, 1,
                                            {
                                                plate = vehicleProps.plate,
                                                description = locale('key_description', vehicleProps.plate)
                                            })
                                    end

                                    if intocar then
                                        while true do
                                            Wait(0)
                                            TaskWarpPedIntoVehicle(source, entity, -1)
                                            if GetPedInVehicleSeat(entity, -1) > 0 then
                                                break
                                            end
                                        end
                                    end

                                    if not society then
                                        xPlayer.removeAccountMoney(money, (info.price or price))
                                    else
                                        TriggerEvent('esx_addonaccount:getSharedAccount', society, function(cuenta)
                                            xPlayer.removeAccountMoney(money, (info.price or price))
                                            cuenta.addMoney((info.price or price))
                                        end)
                                    end
                                    TriggerClientEvent('mono_garage:Notification', source,
                                        locale('SERVER_RetirarImpound', (info.price or price)))
                                else
                                    TriggerClientEvent('mono_garage:Notification', source,
                                        locale('SERVER_RetirarImpoundError'))
                                end
                            end)
                    else
                        TriggerClientEvent('mono_garage:Notification', source, locale('SERVER_SinDinero'))
                    end
                end
            end)
    end

    if money == 'money' then
        RetirarVehiculo(xPlayer.getMoney())
    elseif money == 'bank' then
        RetirarVehiculo(bank.money)
    end
end)


function DeleteVehicleByPlate(plate)
    if Garage.Debug.Prints then
        print('DeleteVehicleByPlate ' .. plate)
    end
    local vehicles = GetAllVehicles()
    for i = 1, #vehicles, 1 do
        if GetVehicleNumberPlateText(vehicles[i]) == plate then
            DeleteEntity(vehicles[i])
            if Garage.Debug.Prints then
                print('^2 Vehicle delete by Plate:' .. plate)
            end
            return true
        end
    end
    return false
end

RegisterServerEvent('mono_garage:ImpoundJoB', function(plate, impound, price, reason, date)
    if Garage.Debug.Prints then
        print('mono_garage:ImpoundJoB ' .. plate, impound, price, reason, date)
    end
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    local identifier = xPlayer.identifier
    local formattedDate = os.date("%d/%m/%Y", date)
    local info = { date = formattedDate, price = price, reason = reason }
    MySQL.update(
        "UPDATE owned_vehicles SET parking = ?, infoimpound = ?, pound = 1, calle = 0, stored = 0  WHERE owner = ? AND plate = ?",
        { impound, json.encode(info), identifier, plate }, function(rowsChanged)
            if rowsChanged > 0 then
                for entity, plate2 in pairs(vehiculoCreado) do
                    if plate2 == plate then
                        DeleteVehicleByPlate(plate)
                        --vehiculoCreado[entity] = nil
                    end
                end
                TriggerClientEvent('mono_garage:Notification', source, locale('impfunc_noti', plate, impound))
                if Garage.Debug.Prints then
                    print('^2 Plate:' ..
                        plate .. ', Impound:' .. impound .. ', Price:' ..
                        price .. ', Reason:' .. reason .. ', Date:' .. formattedDate)
                end
            else
                TriggerClientEvent('mono_garage:Notification', source, locale('SERVER_MandarMal'))
            end
        end)
end)

RegisterServerEvent('mono_garage:MandarVehiculoImpound', function(plate, impound)
    if Garage.Debug.Prints then
        print('mono_garage:MandarVehiculoImpound ' .. plate, impound)
    end
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    local identifier = xPlayer.identifier

    MySQL.update("UPDATE owned_vehicles SET parking = ?, pound = 1, calle = 0 WHERE owner = ? AND plate = ?",
        { impound, identifier, plate },
        function(rowsChanged)
            if rowsChanged > 0 then
                for k, v in pairs(vehiculoCreado) do
                    if v == plate then
                        DeleteEntity(k)
                        vehiculoCreado[k] = nil
                    end
                end
                TriggerClientEvent('mono_garage:Notification', source, locale('SERVER_MandarVehiculoImpound'))
            else
                TriggerClientEvent('mono_garage:Notification', source, locale('SERVER_MandarMal'))
            end
        end)
end)


RegisterNetEvent('mono_garage:ChangeGarage', function(data)
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    local bank = xPlayer.getAccount("bank")
    if data.price == false then
        MySQL.update('UPDATE owned_vehicles SET parking = ? WHERE owner = ? and plate = ? ', {
            data.garage, data.owner, data.plate
        }, function(affectedRows)
            if affectedRows > 0 then
                TriggerClientEvent('mono_garage:Notification', source,locale('enviado', data.garage))

                print(affectedRows, 'Vehiculo transladado')
            else
                TriggerClientEvent('mono_garage:Notification', source,
                    locale('SERVER_RetirarImpoundError'))
            end
        end)
    else
        local function RetirarVehiculo(dinero)
            if dinero >= data.price then
                MySQL.update(
                    'UPDATE owned_vehicles SET parking = ?, stored = 1, pound = NULL   WHERE owner = ? and plate = ?  ',
                    {
                        data.garage, data.owner, data.plate
                    }, function(affectedRows)
                        print(affectedRows, 'Vehiculo transladado')
                        if affectedRows > 0 then
                            if not data.society then
                                xPlayer.removeAccountMoney(data.money, data.price)
                            else
                                TriggerEvent('esx_addonaccount:getSharedAccount', data.society, function(cuenta)
                                    xPlayer.removeAccountMoney(data.money, data.price)
                                    cuenta.addMoney(data.price)
                                end)
                            end
                            TriggerClientEvent('mono_garage:Notification', source,
                                locale('SERVER_RetirarImpound', data.price))
                        else
                            TriggerClientEvent('mono_garage:Notification', source,
                                locale('SERVER_RetirarImpoundError'))
                        end
                    end)
            else
                TriggerClientEvent('mono_garage:Notification', source, locale('SERVER_SinDinero'))
            end
        end

        if data.money == 'money' then
            RetirarVehiculo(xPlayer.getMoney())
        elseif data.money == 'bank' then
            RetirarVehiculo(bank.money)
        end
    end
end)




RegisterNetEvent('mono_garage:SetCarDB', function(vehicleData, plate, garage)
    if Garage.Debug.Prints then
        print('mono_garage:SetCarDB ' .. json.encode(vehicleData), plate)
    end
    local source = source
    local xPlayer = ESX.GetPlayerFromId(source)
    if xPlayer.getGroup() == Garage.OwnerCarAdmin.Group then
        local plate = plate
        local results = MySQL.query.await("SELECT * FROM owned_vehicles WHERE plate = ?", { plate })
        if results[1] ~= nil then
            TriggerClientEvent('mono_garage:Notification', source, locale('setcardb_enpropiedad', plate))
            if Garage.Debug.Prints then
                print('^2 El vehículo con placa ' .. plate .. ' ya está en propiedad.')
            end
        else
            vehicleData.plate = plate
            local jsonVehicleData = json.encode(vehicleData)
            MySQL.update.await(
                "INSERT INTO owned_vehicles (owner, plate, vehicle, parking) VALUES (?, ?, ?, ?)",
                { xPlayer.identifier, plate, jsonVehicleData, garage })
            if Garage.CarKeys then
                ox_inventory:AddItem(source, Keys.ItemName, 1,
                    { plate = plate, description = locale('key_description', plate) })
            end
            TriggerClientEvent('mono_garage:Notification', source, locale('setcardb_agregado', plate))

            if Garage.Debug.Prints then
                print(' ^2El vehículo con placa ' ..
                    plate .. ' ha sido agregado a las propiedades de ' .. xPlayer.getName() .. '.')
            end
        end
    else
        if Garage.Debug.Prints then
            print('^2 El jugador ' ..
                xPlayer.getName() .. ' no tiene permisos suficientes para agregar vehículos a las propiedades.')
        end
    end
end)




local function PlateCount(platecounted)
    if Garage.Debug.Prints then
        print('PlateCount ' .. platecounted)
    end
    local cantidad = 0
    for entity, plate in pairs(vehiculoCreado) do
        if plate == platecounted then
            cantidad = cantidad + 1
            if cantidad > 1 then
                return true
            end
        end
    end
    return false
end

CreateThread(function()
    while true do
        Wait(0)
        for entity, plate in pairs(vehiculoCreado) do
            if PlateCount(plate) then
                DeleteEntity(entity)
                --vehiculoCreado[entity] = nil
            end
        end
    end
end)




if Garage.AutoImpound.AutoImpound then
    CreateThread(function()
        while true do
            local vehicles = MySQL.query.await("SELECT * FROM owned_vehicles")
            for i = 1, #vehicles do
                local data = vehicles[i]
                local vehicleFound = false
                for entity, plate in pairs(vehiculoCreado) do
                    if plate == data.plate then
                        if DoesEntityExist(entity) then
                            vehicleFound = true
                            if Garage.Debug.Prints then
                                print('AutoImpound.AutoImpound ' .. entity, plate, vehicleFound)
                            end
                        end
                    end
                end
                if not vehicleFound and data.stored == 0 and data.pound == nil and data.calle == 1 then
                    MySQL.update(
                        "UPDATE owned_vehicles SET parking = ?, pound = 1, calle = 0 WHERE  plate = ?",
                        { Garage.AutoImpound.ImpoundIn, data.plate },
                        function(rowsChanged)
                            if rowsChanged > 0 then
                                if Garage.Debug.Autoimpound then
                                    print('^2 El vehiculo con la matricula ' ..
                                        data.plate .. ' fue depositado en ' .. Garage.AutoImpound.ImpoundIn)
                                end
                            else
                                if Garage.Debug.Autoimpound then
                                    print('^2 ERROR')
                                end
                            end
                        end)
                end
            end
            Wait(Garage.AutoImpound.TimeCheck)
        end
    end)
end


--[[CreateThread(function()
    while true do
        Wait(1000)
        local vehicles = MySQL.query.await("SELECT * FROM owned_vehicles")
        for i = 1, #vehicles do
            local data = vehicles[i]
            local all = GetAllVehicles()
            for i = 1, #all, 1 do
                local entity = all[i]
                local plate1 = SP(data.plate)
                local plate2 = SP(GetVehicleNumberPlateText(entity))
                if plate1 == plate2 then
                    local driver = GetPedInVehicleSeat(entity, -1)
                    if driver > 0 then
                        local PosAnituga = GetEntityCoords(entity)
                        Wait(1000)
                        local PosNueva = GetEntityCoords(entity)
                        local distance = #(PosAnituga - PosNueva)
                        data.mileage = data.mileage + tonumber(distance)
                        if Garage.Debug.Prints then
                            print('Actual km: ' .. data.mileage .. ', Distancia: ' .. distance)
                        end
                        MySQL.update(
                            'UPDATE owned_vehicles SET mileage = @kms WHERE plate = @plate',
                            { ['@plate'] = plate2, ['@kms'] = data.mileage })
                        break
                    end
                end
            end
        end
    end
end)]]

if Garage.Persistent then
    RegisterNetEvent('esx:playerLoaded', function(player, xPlayer, isNew)
        if xPlayer then
            local results = MySQL.query.await("SELECT * FROM owned_vehicles WHERE owner = ?", { xPlayer.getIdentifier() })
            if results[1] ~= nil then
                for i = 1, #results do
                    local result = results[i]
                    local veh = json.decode(result.vehicle)
                    if result.calle == 1 and result.stored == 2 then
                        local pos = json.decode(result.lastposition)
                        if pos ~= nil then
                            local plate = veh.plate
                            local model = veh.model
                            local coords = vector3(pos.x, pos.y, pos.z)
                            local Heading = pos.h
                            if not vehiclesSpawned[plate] then
                                vehiclesSpawned[plate] = true
                                while true do
                                    local Ped = GetPlayerPed(player)
                                    local coordsped = GetEntityCoords(Ped)
                                    local distance = #(coordsped - coords)
                                    Wait(0)
                                    if distance < 500 then
                                        local vehicle = CrearVehiculo(model, coords, Heading, veh)
                                        SetVehicleDoorsLocked(vehicle, pos.doors)
                                        MySQL.update(
                                            'UPDATE owned_vehicles SET stored = ?, lastposition = ?  WHERE plate = ?',
                                            { 0, nil, plate, })
                                        break
                                    else
                                        if Garage.Debug.Prints then
                                            print('^2 Distance to vehicle spawn :' .. distance)
                                        end
                                    end
                                end

                                if Garage.Debug.Persistent then
                                    print('^2 Vehicle Spawn, Plate: ' ..
                                        plate .. ', Coords' ..
                                        coords .. ', Doors:' .. pos.doors .. ', ( 0 = open / 2 close))')
                                end
                                vehiclesSpawned[plate] = true
                            end
                        end
                    end
                end
            end
        end
    end)

    RegisterNetEvent('esx:playerDropped', function(source)
        local xPlayer = ESX.GetPlayerFromId(source)
        local vehicles = MySQL.query.await("SELECT * FROM owned_vehicles")
        for i = 1, #vehicles do
            local data = vehicles[i]
            if data.owner == xPlayer.getIdentifier() then
                for entity, plate in pairs(vehiculoCreado) do
                    if data.plate == plate then
                        if data.calle == 1 then
                            local position = GetEntityCoords(entity)
                            local heading = GetEntityHeading(entity)
                            local doorLockStatus = GetVehicleDoorLockStatus(entity)
                            local posTable = {
                                x = position.x,
                                y = position.y,
                                z = position.z,
                                h = heading,
                                doors = doorLockStatus
                            }
                            local posStr = json.encode(posTable)
                            MySQL.update(
                                'UPDATE owned_vehicles SET lastposition = ?, stored = 2 WHERE plate = ?',
                                { posStr, plate },
                                function()
                                    vehiclesSpawned[plate] = false
                                    DeleteEntity(entity)
                                    --vehiculoCreado[entity] = nil

                                    if Garage.Debug.Persistent then
                                        print('^2 Vehicle Save, Plate: ' ..
                                            plate ..
                                            ', Coords' ..
                                            position .. ', Doors:' .. doorLockStatus .. ', ( 0 = open / 2 close))')
                                    end
                                end)
                        end
                    end
                end
            end
        end
    end)
end





--[[lib.addCommand('mono_garage:table', {
    help = 'mono_garage:vehicle_table',
    restricted = Garage.OwnerCarAdmin.Group,
}, function(source, args)
    for entity, plate in pairs(vehiculoCreado) do
        print('Entity: ' .. entity .. ', Plate: ' .. plate)
    end
end)
]]


lib.addCommand(Garage.OwnerCarAdmin.Command, {
    help = locale('setearcar2'),
    restricted = Garage.OwnerCarAdmin.Group,
    params = {
        {
            name = 'target',
            type = 'playerId',
            help = 'Target player\'s server id',
        },
    },
}, function(source, args)
    TriggerClientEvent('mono_garage:GiveVehicle', args.target)
end)


if Garage.Version then
    local function GitHubUpdate()
        PerformHttpRequest('https://raw.githubusercontent.com/Mono-94/mono_garage/main/fxmanifest.lua',
            function(error, result, headers)
                local actual = GetResourceMetadata(GetCurrentResourceName(), 'version')

                if not result then print("^6MONO GARAGE^7 -  version couldn't be checked") end

                local version = string.sub(result, string.find(result, "%d.%d.%d"))

                if tonumber((version:gsub("%D+", ""))) > tonumber((actual:gsub("%D+", ""))) then
                    print('^6MONO GARAGE^7  - The version ^2' ..
                        version ..
                        '^0 is available, you are still using version ^1' ..
                        actual .. ', ^0Download the new version at: https://github.com/Mono-94/mono_garage')
                else
                    print('^6MONO GARAGE^7 - You are using the latest version of the script.')
                end
            end)
    end
    GitHubUpdate()
end
