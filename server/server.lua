local debug = false
local data_to_save = {}
local data_to_send_top50 = {}
local playerDataLoaded = {}
local playerDirty = {}
local serv_cooldown_death = {}
local cooldown_duration_death = 500
local restart_ahead = false
local shutdown = false
local lastLeaderboardRefresh = 0
local REFRESH_COOLDOWN = 60000

function debugprint(text)
    if not debug then return end
    print(text)
end

local function refreshLeaderboard()
    MySQL.query('SELECT identifier, kills, deaths, name FROM somis_ranks ORDER BY kills DESC LIMIT 50', {}, function(result, err)
        if err then
            print("^1[somis-rank]^7 ERROR refreshing leaderboard: " .. tostring(err))
            return
        end
        if result then
            local top50 = {}
            for i, row in ipairs(result) do
                top50[i] = {
                    identifier = row.identifier,
                    kills = row.kills or 0,
                    deaths = row.deaths or 0,
                    name = row.name or '',
                    rank = i
                }
            end
            data_to_send_top50 = top50
            debugprint("^2[somis-rank]^7 Top 50 leaderboard refreshed")
        else
            data_to_send_top50 = {}
        end
    end)
end

local function tryRefreshLeaderboard()
    local now = GetGameTimer()
    if now - lastLeaderboardRefresh >= REFRESH_COOLDOWN then
        refreshLeaderboard()
        lastLeaderboardRefresh = now
    end
end

CreateThread(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `somis_ranks` (
            `identifier` VARCHAR(60) NOT NULL PRIMARY KEY,
            `kills` INT(11) NOT NULL DEFAULT 0,
            `deaths` INT(11) NOT NULL DEFAULT 0,
            `name` VARCHAR(100) NOT NULL DEFAULT ''
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    ]], {}, function(result, err)
        if err then
            print("^1[somis-rank]^7 ERROR creating table: " .. tostring(err))
        else
            debugprint("^2[somis-rank]^7 Table 'somis_ranks' is ready!")
            refreshLeaderboard()
            lastLeaderboardRefresh = GetGameTimer()
        end
    end)
end)

local function isEntityPed(entity)
    return GetEntityType(entity) == 1
end

AddEventHandler('weaponDamageEvent', function(sender, data)
    if restart_ahead then return end
    if not data.willKill then return end
    local killerId = sender or 0
    local entity = NetworkGetEntityFromNetworkId(data.hitGlobalId)
    if not DoesEntityExist(entity) or not isEntityPed(entity) or not IsPedAPlayer(entity) then return end
    local victimId = NetworkGetEntityOwner(entity)
    local now = GetGameTimer()
    if serv_cooldown_death[victimId] and now < serv_cooldown_death[victimId] then return end
    if killerId == 0 then return end
    serv_cooldown_death[victimId] = now + cooldown_duration_death
    Kill(killerId, victimId)
end)

function save(src)
    if shutdown or restart_ahead then return false end
    if not data_to_save[src] or not data_to_save[src].identifier then return false end
    
    local identifier = data_to_save[src].identifier
    local kills = data_to_save[src].kills or 0
    local deaths = data_to_save[src].deaths or 0
    
    MySQL.query('INSERT INTO somis_ranks (identifier, kills, deaths) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE kills = VALUES(kills), deaths = VALUES(deaths)', {
        identifier, kills, deaths
    }, function(result, err)
        if err then
            print(string.format("^1[somis-rank]^7 ERROR saving player %s: %s", identifier, tostring(err)))
        else
            debugprint(string.format("^2[somis-rank]^7 Saved player %s (kills: %d, deaths: %d)", identifier, kills, deaths))
            playerDirty[src] = nil
            tryRefreshLeaderboard()
        end
    end)
    
    return true
end

function save_everyone()
    debugprint("^5[somis-rank]^7 Starting save everyone...")
    local playersToSave = {}
    
    for src, _ in pairs(playerDirty) do
        if data_to_save[src] and data_to_save[src].identifier then
            table.insert(playersToSave, src)
        end
    end
    
    local total = #playersToSave
    if total == 0 then
        debugprint("^3[somis-rank]^7 No dirty players to save")
        tryRefreshLeaderboard()
        return
    end
    
    debugprint(string.format("^5[somis-rank]^7 Saving %d dirty players...", total))
    local saved = 0
    
    for _, src in ipairs(playersToSave) do
        local identifier = data_to_save[src].identifier
        local kills = data_to_save[src].kills or 0
        local deaths = data_to_save[src].deaths or 0
        
        MySQL.query('INSERT INTO somis_ranks (identifier, kills, deaths) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE kills = VALUES(kills), deaths = VALUES(deaths)', {
            identifier, kills, deaths
        }, function(result, err)
            saved = saved + 1
            if err then
                print(string.format("^1[somis-rank]^7 ERROR saving player %s: %s", identifier, tostring(err)))
            else
                debugprint(string.format("^6[somis-rank]^7 Saved player %s (%d/%d)", identifier, saved, total))
            end
            if saved == total then
                debugprint(string.format("^2[somis-rank]^7 All %d dirty players saved", total))
                playerDirty = {}
                tryRefreshLeaderboard()
            end
        end)
    end
end

function Kill(killer, victim)
    if not playerDataLoaded[killer] or not playerDataLoaded[victim] then
        debugprint("^1[somis-rank]^7 Kill ignored: player data not loaded")
        return
    end

    data_to_save[killer].kills = data_to_save[killer].kills + 1
    data_to_save[victim].deaths = data_to_save[victim].deaths + 1
    playerDirty[killer] = true
    playerDirty[victim] = true

    local killerIdentifier = data_to_save[killer].identifier or "Unknown"
    local victimIdentifier = data_to_save[victim].identifier or "Unknown"

    debugprint(string.format("^3[somis-rank]^7 Kill: %s -> %s | %d/%d -> %d/%d", 
        killerIdentifier, victimIdentifier,
        data_to_save[killer].kills - 1, data_to_save[victim].deaths - 1,
        data_to_save[killer].kills, data_to_save[victim].deaths))
end

function getidenfitier(src)
    return GetPlayerIdentifierByType(src, 'license')
end

function loadPlayerData(src)
    local license = getidenfitier(src)
    if not license then return end
    
    local playerName = GetPlayerName(src) or ''
    
    data_to_save[src] = {
        identifier = license,
        name = playerName,
        kills = 0,
        deaths = 0
    }
    
    playerDataLoaded[src] = false

    MySQL.single('SELECT kills, deaths, name FROM somis_ranks WHERE identifier = ?', {license}, function(result, err)
        if err then
            print(string.format("^1[somis-rank]^7 ERROR loading data for %s: %s", license, tostring(err)))
        elseif result then
            data_to_save[src].kills = result.kills or 0
            data_to_save[src].deaths = result.deaths or 0
            data_to_save[src].name = playerName
            debugprint(string.format("^2[somis-rank]^7 Loaded %s (ID: %d) - Kills: %d, Deaths: %d", license, src, result.kills or 0, result.deaths or 0))
        else
            debugprint(string.format("^6[somis-rank]^7 New player %s (ID: %d)", license, src))
        end
        
        MySQL.query('INSERT INTO somis_ranks (identifier, kills, deaths, name) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE name = VALUES(name)', {
            license, data_to_save[src].kills, data_to_save[src].deaths, playerName
        }, function(_, nameErr)
            if nameErr then
                print(string.format("^1[somis-rank]^7 ERROR updating name for %s: %s", license, tostring(nameErr)))
            end
        end)
        
        playerDataLoaded[src] = true
        tryRefreshLeaderboard()
    end)
end

function loadAllPlayers()
    debugprint("^5[somis-rank]^7 Loading all connected players...")
    local players = GetPlayers()
    local loaded = 0
    
    for _, playerId in ipairs(players) do
        local src = tonumber(playerId)
        if src then
            loadPlayerData(src)
            loaded = loaded + 1
        end
    end
    
    debugprint(string.format("^2[somis-rank]^7 Started loading %d players", loaded))
end

AddEventHandler('playerJoining', function()
    local src = source
    loadPlayerData(src)
end)

AddEventHandler('playerDropped', function()
    local src = source
    playerDataLoaded[src] = nil
    playerDirty[src] = nil
    save(src)
    data_to_save[src] = nil
end)

AddEventHandler('txAdmin:events:serverShuttingDown', function()
    shutdown = true
    save_everyone()
end)

AddEventHandler('txAdmin:events:scheduledRestart', function(eventData)
    if eventData.secondsRemaining ~= 60 then return end
    save_everyone()
    restart_ahead = true
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        save_everyone()
    end
end)

RegisterCommand("save_ranks", function(source, args, rawCommand)
    if source ~= 0 then return end
    save_everyone()
end, false)

local command_cool = {}
local command_cool_time = 3000

RegisterNetEvent("open_stats", function()
    local src = source
    local now = GetGameTimer()
    if command_cool[src] and now < command_cool[src] then return end
    command_cool[src] = now + command_cool_time
    if not data_to_save[src] then
        TriggerClientEvent("open_stats", src, data_to_send_top50, {kills = 0, deaths = 0, name = GetPlayerName(src) or '', rank = "Unranked"})
        return
    end

    local personalKills = data_to_save[src].kills
    local personalName = GetPlayerName(src) or data_to_save[src].name or ''

    local query = [[
        SELECT COUNT(*) + 1 AS rank_position
        FROM somis_ranks
        WHERE kills > ?
    ]]

    MySQL.single(query, {personalKills}, function(rankResult)
        local playerRank = "Unranked"
        if rankResult and rankResult.rank_position then
            playerRank = "#" .. rankResult.rank_position
        end

        local personal = {
            kills = personalKills,
            deaths = data_to_save[src].deaths,
            name = personalName,
            rank = playerRank
        }

        TriggerClientEvent("open_stats", src, data_to_send_top50, personal)
    end)
end)

Wait(1000)
loadAllPlayers()
refreshLeaderboard()

CreateThread(function()
    while true do
        Wait(5 * 60000)
        save_everyone()
    end
end)
