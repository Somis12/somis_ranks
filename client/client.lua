local isLeaderboardOpen = false

RegisterNetEvent("open_stats", function(top50, personal)
    if not top50 then return end
    
    SendNUIMessage({
        action = "open",
        leaderboard = top50,
        personal = personal
    })
    
    SetNuiFocus(true, true)
    isLeaderboardOpen = true
end)

RegisterCommand("stats", function()
    TriggerServerEvent("open_stats")
end)

RegisterNUICallback("closeLeaderboard", function(data, cb)
    SetNuiFocus(false, false)
    isLeaderboardOpen = false
    cb("ok")
end)