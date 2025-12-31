local Config = lib.load('config.time')
local globalState = GlobalState
local useRealTime = Config.useRealTime

-- GlobalState checks here are to ensure that the if the script is being restarted live the time doesn't reset.
local configScale = useRealTime and 60000 or Config.timeScale
local currentScale = globalState.timeScale or configScale
local freezeTime = globalState.freezeTime
local startTime = useRealTime and { hour = tonumber(os.date('%H')), minute = tonumber(os.date('%M')) } or Config.startUpTime

local minute = startTime.minute
local hour = startTime.hour

-- Log system initialization
lib.logger('time', 'TimeSystemInit', 'Time system initialized - Mode: ' .. (useRealTime and 'RealTime' or 'GameTime') .. ', Starting: ' .. hour .. ':' .. minute, 'startup')

-- Syncs the GlobalStates (does not replicate if the values are the same)
globalState.timeScale = currentScale
globalState.freezeTime = freezeTime
globalState.isNight = hour >= Config.nightTime.beginning or hour < Config.nightTime.ending

-- Loop that syncs the minute and hours of the servers to clients.
CreateThread(function()
    while true do
        if not freezeTime then
            local newMinute = minute == 59 and 0 or minute + 1
            local newHour = minute == 59 and (hour == 23 and 0 or hour + 1) or hour

            -- Log time changes hourly to avoid excessive logging
            if newHour ~= hour then
                lib.logger('time', 'HourChange', 'Time changed to ' .. newHour .. ':' .. newMinute)
            end

            globalState.currentTime = {
                minute = newMinute,
                hour = newHour,
            }
        end

        Wait(currentScale)
    end
end)

-- Add server side statebag change handlers so third party resources can set globalstates and we can replicate the data.
AddStateBagChangeHandler('freezeTime', 'global', function(_, _, value)
    lib.logger('time', 'FreezeTimeChanged', 'Time freeze state changed to: ' .. tostring(value), 'state')
    freezeTime = value
end)

local nightScale = Config.timeScaleNight
local nightStart, nightEnd = Config.nightTime.beginning, Config.nightTime.ending

AddStateBagChangeHandler('currentTime', 'global', function(_, _, value)
    if value then
        hour = value.hour
        minute = value.minute

        if not useRealTime and Config.useNightScale then
            if (hour > nightStart or hour < nightEnd) and currentScale ~= nightScale then
                lib.logger('time', 'NightScaleActivated', 'Night time scale activated: ' .. nightScale, 'night')
                currentScale = nightScale
                globalState.timeScale = currentScale
            elseif (hour < nightStart and hour > nightEnd) and currentScale ~= configScale then
                lib.logger('time', 'DayScaleActivated', 'Day time scale activated: ' .. configScale, 'day')
                currentScale = configScale
                globalState.timeScale = currentScale
            end
        end
    end

    globalState.isNight = hour >= Config.nightTime.beginning or hour < Config.nightTime.ending
end)

AddStateBagChangeHandler('timeScale', 'global', function(_, _, value)
    if value then
        lib.logger('time', 'TimeScaleChanged', 'Time scale changed to: ' .. value, 'scale')
        currentScale = value
    end
end)

if not useRealTime then
    lib.addCommand('time', {
        help = 'Set the current time',
        restricted = 'group.superadmin',
        params = {
            {
                name = 'hour',
                type = 'number',
                help = 'set the Hour',
            },
            {
                name = 'minute',
                type = 'number',
                help = 'set the Minute',
                optional = true
            },
        },
    }, function(source, args) -- source, args
        local newHours, newMinutes = args.hour, args.minute or 0
        newHours = newHours > 23 and 0 or newHours < 0 and 0 or newHours
        newMinutes = newMinutes > 59 and 59 or newMinutes < 0 and 0 or newMinutes

        lib.logger(source, 'AdminSetTime', 'Admin set time to ' .. newHours .. ':' .. newMinutes, 'admin')

        globalState.currentTime = {
            hour = newHours,
            minute = newMinutes,
        }
    end)

    lib.addCommand('noon', {
        help = 'Set the current time to noon (12:00)',
        restricted = 'group.superadmin',
    }, function(source, _)
        lib.logger(source, 'AdminSetNoon', 'Admin set time to noon (12:00)', 'admin')

        globalState.currentTime = {
            hour = 12,
            minute = 0,
        }
    end)

    lib.addCommand('morning', {
        help = 'Set the current time to morning (9:00)',
        restricted = 'group.superadmin',
    }, function(source, _)
        lib.logger(source, 'AdminSetMorning', 'Admin set time to morning (9:00)', 'admin')

        globalState.currentTime = {
            hour = 9,
            minute = 0,
        }
    end)

    lib.addCommand('evening', {
        help = 'Set the current time to evening (18:00)',
        restricted = 'group.superadmin',
    }, function(source, _)
        lib.logger(source, 'AdminSetEvening', 'Admin set time to evening (18:00)', 'admin')

        globalState.currentTime = {
            hour = 18,
            minute = 0,
        }
    end)

    lib.addCommand('night', {
        help = 'Set the current time to night (23:00)',
        restricted = 'group.superadmin',
    }, function(source, _)
        lib.logger(source, 'AdminSetNight', 'Admin set time to night (23:00)', 'admin')

        globalState.currentTime = {
            hour = 23,
            minute = 0,
        }
    end)

    lib.addCommand('timescale', {
        help = ('Set milliseconds per game second (default %s)'):format(currentScale),
        restricted = 'group.superadmin',
        params = {
            {
                name = 'scale',
                type = 'number',
                help = 'Milliseconds per game second',
            },
        },
    }, function(source, args) -- source, args
        if args.scale > 2000 then
            lib.logger(source, 'AdminSetTimeScale', 'Admin set time scale to ' .. args.scale, 'admin')
            globalState.timeScale = args.scale
        end
    end)

    lib.addCommand('freezetime', {
        help = 'Freeze / unfreeze time',
        restricted = 'group.superadmin',
        params = {
            {
                name = 'time',
                type = 'number',
                help = 'Freeze time? (1 = yes, 0 = no)',
            },
        },
    }, function(source, args)
        local newFreeze = args.time == 1 and true or false

        lib.logger(source, 'AdminFreezeTime', 'Admin ' .. (newFreeze and 'froze' or 'unfroze') .. ' time', 'admin')

        globalState.freezeTime = newFreeze
    end)
end

local function clampTimeComponent(value, maximum)
    local number = tonumber(value)
    if not number then
        return nil
    end
    number = math.floor(number)
    if number < 0 then
        number = 0
    elseif number > maximum then
        number = maximum
    end
    return number
end

exports('setTime', function(hourValue, minuteValue)
    local invokingResource = GetInvokingResource() or 'external'
    local newHour = clampTimeComponent(hourValue, 23)
    if newHour == nil then
        lib.logger('time', 'ExportSetTimeFailed', ('%s attempted to set time with invalid hour'):format(invokingResource), 'export')
        return false
    end
    local newMinute = clampTimeComponent(minuteValue or 0, 59)
    if newMinute == nil then
        newMinute = 0
    end
    lib.logger('time', 'ExportSetTime', ('%s set time to %02d:%02d'):format(invokingResource, newHour, newMinute), 'export')
    globalState.currentTime = {
        hour = newHour,
        minute = newMinute,
    }
    return true
end)

