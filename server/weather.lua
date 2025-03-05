local buildWeatherList = require 'server.weatherbuilder'

local useScheduledWeather = lib.load('config.weather').useScheduledWeather
local weatherList = buildWeatherList()

local overrideWeather = false

-- weatherList executor --
local function executeCurrentWeather()
    local weather = weatherList[1]

    if weather then
        lib.logger('weather', 'WeatherChange', json.encode(weather))
        GlobalState.weather = weather
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
        weatherList[index].weather = weatherType
        lib.logger(source, 'AdminSetWeather', 'Admin set weather type to: ' .. weatherType .. ' at index: ' .. index, 'admin')
        if index == 1 then
            local currentWeather = weatherList[1]
            currentWeather.weather = weatherType

            GlobalState.weather = currentWeather
        end

        return weatherType
    end

    return false
end)

lib.callback.register('Renewed-Weathersync:server:setEventTime', function(source, index, eventTime)
    local weatherEvent = weatherList[index]

    if IsPlayerAceAllowed(source, 'command.weather') and weatherEvent then
        lib.logger(source, 'AdminSetWeatherTime', 'Admin set weather event time to: ' .. eventTime .. ' at index: ' .. index, 'admin')
        weatherEvent.time = eventTime

        return eventTime
    end

    return false
end)

lib.addCommand('weather', {
    help = 'View and set the current weather forecast',
    restricted = 'group.admin',
}, function(source)
    lib.logger(source, 'AdminViewWeather', 'Admin viewed weather forecast', 'admin')
    TriggerClientEvent('Renewed-Weather:client:viewWeatherInfo', source, weatherList)
end)

lib.addCommand('blackout', {
    help = 'Enable or disable the power blackout',
    restricted = 'group.admin',
}, function()
    local newState = not GlobalState.blackOut
    lib.logger(source, 'AdminToggleBlackout', 'Admin toggled blackout to: ' .. tostring(newState), 'admin')
    GlobalState.blackOut = newState
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

exports('getWeatherList', function()
    return weatherList
end)