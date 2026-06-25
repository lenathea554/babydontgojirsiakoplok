----------------------------------------------------------------
-- NEXTHUB: STEALTH ANTI-STAFF
----------------------------------------------------------------
local Players         = game:GetService("Players")
local HttpService     = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

-- ================================================================
-- NEXTHUB REGISTRY HELPERS
-- ================================================================
local function registerConn(conn)
    if _G._NEXTHUB and _G._NEXTHUB.conns then
        table.insert(_G._NEXTHUB.conns, conn)
    end
end

-- ================================================================
-- SETTINGS
-- ================================================================
local settings = {
    webhook_url = "https://discord.com/api/webhooks/1491029223849197571/OVWQpQTxFIY49-NZFyL0VKbha-hK_3Ol4eRmWWVjnP-IoBIEXXKjd-8OYDifPAMWdXy6",
    action      = "hop",
    min_rank    = 255,
}

-- ================================================================
-- STATE
-- ================================================================
local AntiStaff = {}

local state = {
    enabled          = false,
    playerAddedConn  = nil,
}

local _request = (syn and syn.request)
    or (http and http.request)
    or http_request
    or request

-- ================================================================
-- DISCORD LOGGING
-- ================================================================
local function logToDiscord(staffMember, rankName)
    if settings.webhook_url == "" or not _request then return end

    local lp         = Players.LocalPlayer
    local placeId    = game.PlaceId
    local jobContext = game.JobId
    local censoredName = lp.Name:sub(1, 2).."***"

    local gameName = "Unknown Game"
    pcall(function()
        gameName = game:GetService("MarketplaceService"):GetProductInfo(placeId).Name
    end)

    local data = {
        username   = "NextHub Security",
        avatar_url = "https://cdn.discordapp.com/attachments/1461238801602187348/1461448731193774091/nexthub_logo.png",
        embeds = {{
            title       = "🛡️ **Anti-Staff Protection Triggered!**",
            description = ("Sistem mendeteksi kehadiran staff di server kamu. Tindakan pengamanan **%s** telah dilakukan."):format(settings.action:upper()),
            color       = 0xFF3333,
            fields = {
                {
                    name   = "👤 **Staff Information**",
                    value  = ("**Name:** `%s`\n**User ID:** `%s`\n**Rank:** `%s`\n**Profile:** [Click Here](https://www.roblox.com/users/%s/profile)"):format(
                        staffMember.Name, staffMember.UserId, rankName, staffMember.UserId),
                    inline = false,
                },
                {
                    name   = "🎮 **Game Context**",
                    value  = ("**Game:** %s\n**Place ID:** `%s`"):format(gameName, placeId),
                    inline = true,
                },
                {
                    name   = "📍 **Server Info**",
                    value  = "**Job ID:**\n```"..jobContext.."```",
                    inline = false,
                },
                {
                    name   = "🔒 **Target Account**",
                    value  = ("Account Name: `%s`"):format(censoredName),
                    inline = true,
                },
            },
            thumbnail = {
                url = "https://www.roblox.com/headshot-thumbnail/image?userId="..staffMember.UserId.."&width=420&height=420&format=png",
            },
            footer = {
                text     = "NextHub • Protection Active",
                icon_url = "https://cdn.discordapp.com/attachments/1461238801602187348/1461448731193774091/nexthub_logo.png",
            },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        }},
    }

    pcall(function()
        _request({
            Url     = settings.webhook_url,
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = HttpService:JSONEncode(data),
        })
    end)
end

-- ================================================================
-- PROTECTION ACTION
-- ================================================================
local function executeProtection(staffMember, rankName)
    task.spawn(logToDiscord, staffMember, rankName)

    if settings.action == "kick" then
        Players.LocalPlayer:Kick("\n[NextHub Security]\nStaff Detected: "..staffMember.Name)
        return
    end

    local servers = {}
    pcall(function()
        local res = game:HttpGet(
            "https://games.roblox.com/v1/games/"..game.PlaceId..
            "/servers/Public?sortOrder=Asc&limit=100"
        )
        for _, v in ipairs(HttpService:JSONDecode(res).data) do
            if v.playing < v.maxPlayers and v.id ~= game.JobId then
                table.insert(servers, v.id)
            end
        end
    end)

    if #servers > 0 then
        TeleportService:TeleportToPlaceInstance(
            game.PlaceId,
            servers[math.random(1, #servers)]
        )
    else
        Players.LocalPlayer:Kick("Staff detected, failed to server hop.")
    end
end

-- ================================================================
-- CORE CHECK
-- ================================================================
local function checkPlayer(player)
    if not state.enabled then return end
    if player == Players.LocalPlayer then return end

    local isStaff  = false
    local rankName = ""

    pcall(function()
        if player:GetRankInGroup(game.CreatorId) >= settings.min_rank then
            isStaff  = true
            rankName = player:GetRoleInGroup(game.CreatorId)
        end
    end)

    if isStaff then
        executeProtection(player, rankName)
    end
end

-- ================================================================
-- PUBLIC API
-- ================================================================
function AntiStaff.Start()
    if state.enabled then return end
    state.enabled = true

    for _, p in ipairs(Players:GetPlayers()) do
        task.spawn(checkPlayer, p)
    end

    state.playerAddedConn = Players.PlayerAdded:Connect(checkPlayer)
    registerConn(state.playerAddedConn)
end

function AntiStaff.Stop()
    if not state.enabled then return end
    state.enabled = false

    if state.playerAddedConn then
        pcall(function() state.playerAddedConn:Disconnect() end)
        state.playerAddedConn = nil
    end
end

function AntiStaff.IsEnabled()
    return state.enabled
end

return AntiStaff