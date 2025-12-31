local buildWeatherList = require 'server.weatherbuilder'

local WeatherConfig = lib.load('config.weather')
local useScheduledWeather = WeatherConfig.useScheduledWeather


---@type renewed_weather[]
local weatherList = buildWeatherList()

local overrideWeather = false

local snowWeathers = {
    SNOW = true,
    SNOWLIGHT = true,
    BLIZZARD = true,
    XMAS = true,
}

-- weatherList executor --
local function executeCurrentWeather()
    local weather = weatherList[1]

    if weather then
        lib.logger('weather', 'WeatherChange', json.encode(weather:GetWeatherData()))
        GlobalState.weather = weather:GetWeatherData()
    end

    return weather
end

local function runWeatherList()
    local currentWeather = executeCurrentWeather()
    lib.logger('weather', 'WeatherSystemStart', 'Weather system initialized', 'startup')
    while not overrideWeather do

        if weatherList[1] then
            currentWeather.time -= 1

            if currentWeather.time <= 0 then
                lib.logger('weather', 'WeatherExpired', 'Weather event expired: ' .. json.encode(currentWeather), 'expired')
                table.remove(weatherList, 1)
                currentWeather = executeCurrentWeather()
            end
        else
            lib.logger('weather', 'WeatherListEmpty', 'Weather list is empty, regenerating', 'warning')
            currentWeather = executeCurrentWeather()
        end
        Wait(60000)
    end
end

CreateThread(runWeatherList)

-- Admin related events --
RegisterNetEvent('Renewed-Weather:server:removeWeatherEvent', function(index)
    if IsPlayerAceAllowed(source, 'command.weather') and weatherList[index] then
        lib.logger(source, 'AdminRemoveWeather', json.encode(weatherList[index]))
        table.remove(weatherList, index)
    end
end)

lib.callback.register('Renewed-Weathersync:server:setWeatherType', function(source, index, weatherType)
    if IsPlayerAceAllowed(source, 'command.weather') and weatherList[index] then
        local weatherEvent = weatherList[index]

        weatherEvent:SetWeather(weatherType)

        lib.logger(source, 'AdminSetWeather', 'Admin set weather type to: ' .. weatherType .. ' at index: ' .. index, 'admin')
        if index == 1 then
            GlobalState.weather = weatherEvent:GetWeatherData()
        end

        return weatherType
    end

    return false
end)

lib.callback.register('Renewed-Weathersync:server:setEventTime', function(source, index, eventTime)
    local weatherEvent = weatherList[index]

    if IsPlayerAceAllowed(source, 'command.weather') and weatherEvent then
        lib.logger(source, 'AdminSetWeatherTime', 'Admin set weather event time to: ' .. eventTime .. ' at index: ' .. index, 'admin')
        weatherEvent:SetEventTime(eventTime)

        return eventTime
    end

    return false
end)

lib.addCommand('weather', {
    help = 'View and set the current weather forecast',
    restricted = 'group.superadmin',
}, function(source)
    lib.logger(source, 'AdminViewWeather', 'Admin viewed weather forecast', 'admin')
    TriggerClientEvent('Renewed-Weather:client:viewWeatherInfo', source, weatherList)
end)

lib.addCommand('blackout', {
    help = 'Toggle server wide or player only blackout',
	restricted = 'group.superadmin',
	params = {
		{ name = 'target', type = 'playerId', help = 'Target player\'s server id', optional = true },
	}
}, function(source, args)
	if not args.target then
		local newState = not GlobalState.blackOut
    lib.logger(source, 'AdminToggleBlackout', 'Admin toggled blackout to: ' .. tostring(newState), 'admin')
    GlobalState.blackOut = newState
	else
		local playerState = Player(args.target)
        if not playerState then return end
        playerState.state:set('playerBlackOut', not playerState.state?.playerBlackOut, true)
	end
end)

-- Scheduled restart --
if useScheduledWeather then
    AddEventHandler('txAdmin:events:scheduledRestart', function(eventData)
        local secondsRemaining = eventData.secondsRemaining
        local weather = secondsRemaining == 900 and 'OVERCAST' or secondsRemaining == 600 and 'RAIN' or secondsRemaining == 300 and 'THUNDER'

        if weather then
            lib.logger('system', 'ScheduledRestartWeather', 'Setting weather to ' .. weather .. ' for scheduled restart in ' .. secondsRemaining .. ' seconds', 'restart')
            overrideWeather = true
            GlobalState.weather = {
                weather = weather,
                time = 9000000
            }
        end
    end)
end

local function sanitizeDuration(value)
    local duration = tonumber(value)
    if duration then
        duration = math.floor(duration)
        if duration < 1 then
            duration = 1
        end
    end
    return duration
end

local function parseBoolean(value)
    if type(value) == 'boolean' then
        return value
    end
    if type(value) == 'number' then
        return value ~= 0
    end
    if type(value) == 'string' then
        local lowered = value:lower()
        if lowered == 'true' or lowered == '1' or lowered == 'yes' or lowered == 'on' then
            return true
        end
        if lowered == 'false' or lowered == '0' or lowered == 'no' or lowered == 'off' then
            return false
        end
    end
end

exports('setWeather', function(weatherType, durationMinutes, metadata)
    if type(weatherType) ~= 'string' then
        return false
    end
    weatherType = weatherType:upper()
    local invokingResource = GetInvokingResource() or 'external'
    local currentWeather = weatherList[1]
    local duration = sanitizeDuration(durationMinutes)
    if not currentWeather then
        currentWeather = {
            weather = weatherType,
            time = duration or WeatherConfig.weatherCycletimer or 10,
        }
        weatherList[1] = currentWeather
    else
        currentWeather.weather = weatherType

        if duration then
            currentWeather.time = duration
        end
    end
    local metadataTable = type(metadata) == 'table' and metadata or nil
    if metadataTable and metadataTable.windSpeed ~= nil then
        local parsed = tonumber(metadataTable.windSpeed)
        if parsed then
            currentWeather.windSpeed = parsed
        end
    end
    if metadataTable and metadataTable.windDirection ~= nil then
        local parsed = tonumber(metadataTable.windDirection)
        if parsed then
            currentWeather.windDirection = parsed
        end
    end
    if metadataTable and metadataTable.hasSnow ~= nil then
        currentWeather.hasSnow = metadataTable.hasSnow and true or false
    elseif not metadataTable then
        currentWeather.hasSnow = snowWeathers[weatherType] or false
    end
    GlobalState.weather = currentWeather
    lib.logger('weather', 'ExportSetWeather', ('%s set weather to %s'):format(invokingResource, weatherType), 'export')
    return true
end)

exports('toggleBlackout', function()
    local invokingResource = GetInvokingResource() or 'external'
    local newState = not (GlobalState.blackOut or false)
    GlobalState.blackOut = newState
    lib.logger('weather', 'ExportToggleBlackout', ('%s toggled blackout to %s'):format(invokingResource, tostring(newState)), 'export')
    return newState
end)

exports('setBlackout', function(state)
    local invokingResource = GetInvokingResource() or 'external'
    local parsed = parseBoolean(state)
    if parsed == nil then
        lib.logger('weather', 'ExportSetBlackoutFailed', ('%s attempted to set blackout with invalid value'):format(invokingResource), 'export')
        return false
    end
    GlobalState.blackOut = parsed
    lib.logger('weather', 'ExportSetBlackout', ('%s set blackout to %s'):format(invokingResource, tostring(parsed)), 'export')
    return parsed
end)

exports('getWeatherList', function()
    return weatherList
end)
