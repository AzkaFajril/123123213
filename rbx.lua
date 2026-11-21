-- KyHub v17.2 ("Candy Night" theme: sidebar search + icon tiles, group cards, profile)
-- RightShift = hide/show menu
--
-- v17.2: "Auto Slime" tab replaced by "Auto Combat" tab (Auto Slime + Auto Boss + Auto Skeleton).
--        * Auto Slime: weapon select (WoodSword / IronSword / GoldboneSword / SoulScepter), shoot range, shot effect.
--        * Auto Boss: Island -> HUB -> RUINS -> teleport to RuinsBoss + fly while attacking, Realtime Boss Status.
--        * Auto Skeleton: Island -> HUB -> RUINS -> hit Skeleton / Archer / Knight in Guardians.
--        * Slime / Boss / Skeleton / Harvest / Tree / Mine turn each other off (only one active at a time).
--
-- v17.1: Auto Farm tab upgraded with the KyFarm v8.8 engine:
--        * Pine route: Island -> touch HUB portal -> Hub -> find RUINS -> TouchPart -> farm pine in every ResourceField.
--        * Respawn / back on island -> route is repeated automatically.
--        * Pathfinding walk (with side-stepping when a target is unreachable), hover while hitting (stay away from mobs).
--        * Mining works on real ore parts (not Terrain), replacement detection when a rock is mined out.
--        * New settings: hover, hover height, walk speed, max time per rock, rock area, RUINS portal delay.
-- v17.0: NEW "Auto Farm" tab (Auto Tree + Auto Mine). Whole UI translated to English. Single merged file.
--
-- v16.7: Ripe detection uses the game's Shared.GrowTime module (same as the in-game timer label):
--        timer still running = skipped, needs water = skipped, only crops whose timer finished are harvested.
-- v16.6: Auto Harvest skips crops that need water. Toggle "Skip crops that need water".
-- v16.5: Auto Harvest only harvests ripe crops (toggle "Only ripe crops"); idle if there are none.
-- v16.4: Auto Plant seed is a dropdown and follows the crop selected in Auto Harvest.
-- v16.3: Compatibility for all executors (safeParent, httpGet fallback, fireTouch fallback, clickGui fallback).
-- v16.2: Auto Harvest can AUTO PLANT (replant on freshly harvested plots).
-- v16:   Auto Slime hub teleport is verified (retries up to 3x), Anti Same Server (server hop) in Settings.

-- wait for the game to be ready (important for autoexec)




if not game:IsLoaded() then game.Loaded:Wait() end
do
    local P = game:GetService("Players")
    while not P.LocalPlayer do task.wait() end
    P.LocalPlayer:WaitForChild("PlayerGui", 30)
    if not P.LocalPlayer.Character then
        pcall(function() P.LocalPlayer.CharacterAdded:Wait() end)
    end
    task.wait(2)
end

local env = (getgenv and getgenv()) or _G
if env.KyHub_Cleanup then pcall(env.KyHub_Cleanup) end

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local RS = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local PathfindingService = game:GetService("PathfindingService")
local VirtualUser = game:GetService("VirtualUser")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")
local CoreGui = game:GetService("CoreGui")
local LP = Players.LocalPlayer

-- ============================================================
-- EXECUTOR COMPATIBILITY HELPERS
-- ============================================================
local httpReq = (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request)

local function httpGet(url)
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body) == "string" then return body end
    if httpReq then
        local ok2, res = pcall(httpReq, {Url = url, Method = "GET"})
        if ok2 and type(res) == "table" and res.Body then return res.Body end
    end
    return nil
end

-- parent a ScreenGui safely: gethui -> CoreGui -> PlayerGui
local function safeParent(gui)
    if syn and syn.protect_gui then pcall(syn.protect_gui, gui) end
    local ok = false
    if gethui then ok = pcall(function() gui.Parent = gethui() end) end
    if not ok or not gui.Parent then ok = pcall(function() gui.Parent = CoreGui end) end
    if not ok or not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end
end

local function destroyOld(name)
    local places = {CoreGui, LP:FindFirstChildOfClass("PlayerGui")}
    if gethui then
        local ok, g = pcall(gethui)
        if ok and g then places[#places + 1] = g end
    end
    for _, p in ipairs(places) do
        local o = p and p:FindFirstChild(name)
        if o then pcall(function() o:Destroy() end) end
    end
end

-- touch a portal; if the executor has no firetouchinterest, move right onto the portal
local function fireTouch(part)
    local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not (hrp and part) then return false end
    if firetouchinterest then
        local ok = pcall(function()
            firetouchinterest(hrp, part, 0)
            task.wait(0.15)
            firetouchinterest(LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") or hrp, part, 1)
        end)
        if ok then return true end
    end
    return pcall(function()
        hrp.CFrame = part.CFrame
        task.wait(0.3)
    end)
end
-- ============================================================

local Alive = true
local cleanups = {}
local function onCleanup(f) cleanups[#cleanups + 1] = f end

local Compat = {}
Compat.hasHook = (hookmetamethod and getnamecallmethod) and true or false
Compat.hasFS = (writefile and readfile and isfile and makefolder and isfolder) and true or false
Compat.qot = queue_on_teleport or (syn and syn.queue_on_teleport) or queueonteleport or (fluxus and fluxus.queue_on_teleport)
Compat.newcc = newcclosure or function(f) return f end
Compat.isOwn = checkcaller or function() return false end

local Hooks = {}
if Compat.hasHook then
    pcall(function()
        local old
        old = hookmetamethod(game, "__namecall", Compat.newcc(function(self, ...)
            if Alive and getnamecallmethod() == "FireServer" and typeof(self) == "Instance" then
                local h = Hooks[self.Name]
                if h and not Compat.isOwn() then pcall(h, ...) end
            end
            return old(self, ...)
        end))
    end)
end
local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function fmtDur(s)
    s = math.max(0, math.floor(tonumber(s) or 0))
    local h, m = s // 3600, (s % 3600) // 60
    if h > 0 then return ("%dh %dm"):format(h, m) end
    if m > 0 then return ("%dm %ds"):format(m, s % 60) end
    return ("%ds"):format(s)
end

-- "Candy Night" theme
local T = {
    bg1 = Color3.fromRGB(40, 22, 78),
    bg2 = Color3.fromRGB(12, 18, 46),
    side = Color3.fromRGB(255, 255, 255),
    card = Color3.fromRGB(255, 255, 255),
    field = Color3.fromRGB(0, 0, 0),
    stroke = Color3.fromRGB(255, 255, 255),
    text = Color3.fromRGB(248, 244, 252),
    sub = Color3.fromRGB(178, 170, 206),
    accent = Color3.fromRGB(255, 94, 168),
    accent2 = Color3.fromRGB(255, 159, 104),
    accent3 = Color3.fromRGB(88, 200, 255),
    on = Color3.fromRGB(60, 220, 190),
    off = Color3.fromRGB(110, 104, 136),
    danger = Color3.fromRGB(255, 84, 98),
    good = Color3.fromRGB(184, 232, 255),
}
local CARD_T = 0.93

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end
local function corner(o, r)
    new("UICorner", {CornerRadius = UDim.new(0, r or 8)}, o)
    return o
end
local function stroke(o, c, tr)
    new("UIStroke", {
        Color = c or T.stroke, Transparency = tr or 0.92, Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, o)
    return o
end
local function gradient(o, c1, c2, rot)
    return new("UIGradient", {Color = ColorSequence.new(c1, c2), Rotation = rot or 0}, o)
end
local function hover(b, base)
    b.MouseEnter:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12), {BackgroundTransparency = math.max(0, base - 0.1)}):Play()
    end)
    b.MouseLeave:Connect(function()
        TweenService:Create(b, TweenInfo.new(0.12), {BackgroundTransparency = base}):Play()
    end)
end

-- ============================================================
-- KEY SYSTEM
-- ============================================================
local KeyCFG = {
    API = "https://serverbokhub-kpbp.vercel.app",
    VerifyPath = "/api/keys/verify",
    ApiSecret = "rahasia_bokhub_super_aman_2026",
    GetKeyLink = "https://discord.gg/bFKRrrU4w",
    Discord = "https://discord.gg/bFKRrrU4w",
    Folder = "KyHub",
    File = "KyHub/key.dat",
}

do
    local fsOK = (writefile and readfile and isfile) and true or false

    local function getHwid()
        local ok, id = pcall(function() return game:GetService("RbxAnalyticsService"):GetClientId() end)
        if ok and id and id ~= "" then return id end
        return tostring(LP.UserId)
    end

    local function saveKey(k)
        if not fsOK then return end
        pcall(function()
            if makefolder and isfolder and not isfolder(KeyCFG.Folder) then makefolder(KeyCFG.Folder) end
            writefile(KeyCFG.File, k)
        end)
    end
    local function loadKey()
        if not fsOK then return nil end
        local okE, ex = pcall(isfile, KeyCFG.File)
        if not (okE and ex) then return nil end
        local ok, v = pcall(readfile, KeyCFG.File)
        if not ok or type(v) ~= "string" then return nil end
        v = trim(v)
        return v ~= "" and v or nil
    end
    local function clearKey()
        if not fsOK then return end
        pcall(function() writefile(KeyCFG.File, "") end)
    end

    local function verify(key)
        if not httpReq then return "error", "Executor does not support request/http_request." end
        local ok, res = pcall(httpReq, {
            Url = KeyCFG.API .. KeyCFG.VerifyPath,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json", ["x-api-key"] = KeyCFG.ApiSecret},
            Body = HttpService:JSONEncode({keyString = key, hwid = getHwid()}),
        })
        if not ok or type(res) ~= "table" then return "error", "Could not reach the server." end
        local code = tonumber(res.StatusCode) or 0
        local okD, d = pcall(function() return HttpService:JSONDecode(res.Body or "") end)
        if not okD or type(d) ~= "table" then
            if code >= 500 or code == 0 then return "error", "Server error (" .. code .. ")." end
            return "invalid", "Invalid key."
        end
        local msg = d.error or d.message
        if d.valid == true then return "ok", "Key is valid." end
        if code == 401 or code == 429 or code >= 500 then
            return "error", msg or ("Server rejected the request (" .. code .. ").")
        end
        return "invalid", msg or "Invalid key."
    end

    local saved = loadKey()
    local prefill = saved
    if saved then
        local st = verify(saved)
        if st == "ok" then
            KeyCFG.Passed = true
        elseif st == "invalid" then
            clearKey()
            prefill = nil
        end
    end

    if not KeyCFG.Passed then
        destroyOld("KyHubKeyGui")
        local KG = new("ScreenGui", {Name = "KyHubKeyGui", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 100})
        safeParent(KG)

        local W, H = 340, 262
        local KWin = new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(0, W, 0, H), Position = UDim2.new(0.5, 0, 0.5, 0),
            BackgroundTransparency = 1, BorderSizePixel = 0,
        }, KG)
        new("ImageLabel", {
            BackgroundTransparency = 1, Image = "rbxassetid://6014261993", ImageColor3 = Color3.new(0, 0, 0),
            ImageTransparency = 0.4, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(49, 49, 450, 450),
            Position = UDim2.new(0, -24, 0, -18), Size = UDim2.new(1, 48, 1, 48), ZIndex = 0,
        }, KWin)
        local KBody = corner(new("Frame", {
            Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.03,
            BorderSizePixel = 0, ZIndex = 1,
        }, KWin), 16)
        new("UIGradient", {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, T.bg1),
                ColorSequenceKeypoint.new(0.55, Color3.fromRGB(30, 20, 66)),
                ColorSequenceKeypoint.new(1, T.bg2),
            }), Rotation = 130,
        }, KBody)
        stroke(KBody, T.stroke, 0.82)

        local KClose = corner(new("TextButton", {
            Position = UDim2.new(0, 14, 0, 14), Size = UDim2.new(0, 16, 0, 16), BackgroundColor3 = Color3.fromRGB(255, 95, 87),
            Text = "", AutoButtonColor = false, ZIndex = 2,
        }, KBody), 8)

        local KLogo = corner(new("Frame", {
            AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 22), Size = UDim2.new(0, 40, 0, 40),
            BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 2,
        }, KBody), 12)
        gradient(KLogo, T.accent, T.accent2, 45)
        new("TextLabel", {
            Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 22,
            TextColor3 = Color3.new(1, 1, 1), Text = "K", ZIndex = 3,
        }, KLogo)
        new("TextLabel", {
            Position = UDim2.new(0, 0, 0, 68), Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1,
            Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = T.text, Text = "KyHub", ZIndex = 2,
        }, KBody)
        new("TextLabel", {
            Position = UDim2.new(0, 0, 0, 88), Size = UDim2.new(1, 0, 0, 14), BackgroundTransparency = 1,
            Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = T.sub, Text = "Enter your key to continue", ZIndex = 2,
        }, KBody)

        local KBox = corner(new("TextBox", {
            Position = UDim2.new(0, 20, 0, 114), Size = UDim2.new(1, -40, 0, 34), BackgroundColor3 = T.field,
            BackgroundTransparency = 0.55, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = T.text,
            PlaceholderText = "🔑  Paste your key here", PlaceholderColor3 = T.sub, Text = prefill or "",
            ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 2,
        }, KBody), 10)
        new("UIPadding", {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 10)}, KBox)
        stroke(KBox)

        local KVerify = corner(new("TextButton", {
            Position = UDim2.new(0, 20, 0, 156), Size = UDim2.new(1, -40, 0, 34), BackgroundColor3 = Color3.new(1, 1, 1),
            BackgroundTransparency = 0, Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = Color3.new(1, 1, 1),
            Text = "Verify Key", AutoButtonColor = false, ZIndex = 2,
        }, KBody), 10)
        gradient(KVerify, T.accent, T.accent2, 0)

        local function ghost(text, x, w)
            local b = corner(new("TextButton", {
                Position = UDim2.new(0, x, 0, 198), Size = UDim2.new(0.5, -24, 0, 30), BackgroundColor3 = T.card,
                BackgroundTransparency = CARD_T, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = T.text,
                Text = text, AutoButtonColor = false, ZIndex = 2,
            }, KBody), 9)
            stroke(b, T.stroke, 0.8)
            hover(b, CARD_T)
            return b
        end
        local KGet = ghost("🔗  Get Key", 20)
        local KDisc = ghost("💬  Discord", 0)
        KDisc.Position = UDim2.new(0.5, 4, 0, 198)

        local KStatus = new("TextLabel", {
            Position = UDim2.new(0, 20, 0, 234), Size = UDim2.new(1, -40, 0, 16), BackgroundTransparency = 1,
            Font = Enum.Font.GothamMedium, TextSize = 11, TextColor3 = T.sub, Text = "", ZIndex = 2,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, KBody)

        local state, busy = nil, false
        local function say(msg, color) KStatus.Text = msg or ""; KStatus.TextColor3 = color or T.sub end

        local function copy(text, btn, label)
            local orig = btn.Text
            if setclipboard or toclipboard then
                pcall(setclipboard or toclipboard, text)
                btn.Text = "✓  Copied!"
                say(label .. " copied to clipboard.", T.on)
            else
                say(text, T.accent3)
            end
            task.delay(1.5, function() if btn.Parent then btn.Text = orig end end)
        end
        KGet.Activated:Connect(function() copy(KeyCFG.GetKeyLink, KGet, "Key link") end)
        KDisc.Activated:Connect(function() copy(KeyCFG.Discord, KDisc, "Discord link") end)

        local function submit()
            if busy then return end
            local k = trim(KBox.Text)
            if k == "" then say("Key cannot be empty.", T.danger); return end
            busy = true
            KVerify.Text = "Checking..."
            say("Contacting server...", T.sub)
            local st, msg = verify(k)
            if st == "ok" then
                saveKey(k)
                say("✓ " .. tostring(msg), T.on)
                KVerify.Text = "Success!"
                task.wait(0.6)
                state = "ok"
            else
                say(tostring(msg), T.danger)
                KVerify.Text = "Verify Key"
                busy = false
            end
        end
        KVerify.Activated:Connect(submit)
        KBox.FocusLost:Connect(function(enter) if enter then submit() end end)
        KClose.Activated:Connect(function() state = "closed" end)

        KWin.Position = UDim2.new(0.5, 0, 0.5, 20)
        TweenService:Create(KWin, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Position = UDim2.new(0.5, 0, 0.5, 0),
        }):Play()

        if prefill then say("Saved key found, but the server did not respond. Try Verify again.", T.sub) end

        while state == nil and KG.Parent do task.wait(0.1) end
        local result = state
        pcall(function() KG:Destroy() end)
        if result ~= "ok" then return end
    end
end
-- ============================================================

-- Auto Combat config (Auto Slime + Auto Boss + Auto Skeleton)
local SlimeCFG = {
    Priority = {"pink", "orange", "blue", "green"},
    Enabled = {pink = true, orange = true, blue = true, green = true},
    UseHub = true,
    AutoHub = true,
    WalkSpeed = 22,
    StuckTime = 2,
    SkipFor = 30,
    AttackRange = 7,
    SwingDelay = 0.4,
    SwingAnim = true,
    FixCamera = true,
    EquipEvery = 15,
    SwingArgs = {},
    LobbyName = "Hub",
    LobbyPad = 10,
    AfterDelay = 3,
    FindTimeout = 5,
    HubVerifyWait = 6,
    HubAttempts = 3,
    IslandStuckWait = 10,
    Weapon = "WoodSword",   -- WoodSword / IronSword / GoldboneSword / SoulScepter
    ShootRange = 20,        -- distance to stand & shoot with SoulScepter (studs), small = close
    ShootType = 1,          -- 3rd argument of RequestShoot
    ShotFx = true,          -- orb effect when shooting
}

local SkelCFG = {
    Types = {"Skeleton", "SkeletonArcher", "SkeletonKnight"},
    Priority = {"Skeleton", "SkeletonArcher", "SkeletonKnight"},
    Enabled = {Skeleton = true, SkeletonArcher = true, SkeletonKnight = true},
    UseRoute = true,        -- island -> HUB -> RUINS before farming
    HubName = "Hub",        -- Hub model in Workspace
    PortalName = "HUB",     -- HUB portal inside Island_*
    RuinsName = "RUINS",
    TouchName = "TouchPart",
    HubPad = 10,
    HubWait = 6,
    HubAttempts = 3,
    RuinsDelay = 4,         -- wait in the HUB so the RUINS portal can load first
    WaitTimeout = 10,
    FindTimeout = 15,       -- wait for skeletons to appear after entering RUINS
    NearRange = 300,        -- skeleton within this range = already in RUINS
    EquipEvery = 15,
    ScanEvery = 3,
}

local BossCFG = {
    UseRoute = true,        -- island -> HUB -> RUINS before going to the boss
    Folder = "RuinsBoss",   -- boss folder in Workspace
    Height = 25,             -- fly height above the boss (studs)
    Offset = 3,             -- horizontal offset from the boss (studs)
    Realtime = false,       -- Realtime Boss Status: keep Hub & Ruins streamed in
    StreamEvery = 3,        -- repeat the stream request every X seconds
}

local ChestCFG = {
    Teleport = true,
    OnlyFull = true,
    IntervalMin = 1,
    OpenWait = 3,
    CollectWait = 0.8,
    BetweenChest = 0.3,
    HomeModel = "Hub",
    HomeTouchName = "TouchPart",
    HomeKeyword = "home",
    HomeWait = 8,
    AfterHomeDelay = 2,
}

-- ===== SETTING AUTO PLANT (ubah angka di sini) =====
-- ===== SETTING AUTO PLANT (ubah angka di sini) =====
-- ===== SETTING PLANT AFTER HARVEST (ubah angka di sini) =====
local PlantCFG = {
    AfterHarvest = true, -- true = setelah panen langsung tanam lagi
    Slot = 63,           -- slot bibit cadangan untuk kalibrasi
    YOff = 1,            -- jangan diubah
    CropGoneWait = 2,    -- detik menunggu tanaman lama hilang. Kalau tidak hilang (belum matang / tumbuh lagi) petak dilewati
    RetryGap = 0.8,      -- jeda sebelum kirim ulang kalau tanaman belum muncul (detik)
    Retries = 7,         -- berapa kali kirim ulang per petak
        PlantNear = true,    -- tanam juga petak kosong di sekitar karakter
    NearRadius = 20,     -- jarak cari petak kosong (stud, maksimal 30)
    GrowSkip = 30,       -- detik: tanaman yang baru ditanam tidak dikejar harvest
    UnripeSkip = 25,     -- detik: tanaman yang panennya ditolak (belum matang) dilewati
    StuckSkip = 8,       -- detik: batas menuju satu tanaman sebelum dilewati (anti stuck)
}
-- WalkSpeed/Radius/PerSecond are used internally and not shown in the UI
local HarvestCFG = {
    WalkSpeed = 30,
    Radius = 20,
    PerSecond = 10,
    FireLimitPerBush = 1,
    BlacklistTime = 15,
    TeleportFallback = true,
    StuckTime = 1,
    OnlyRipe = true,
    SkipNeedsWater = true,
    Replant = true,
    Seed = "WheatSeeds",
    Slot = 63,
    Block = "FarmSoil",
    YOff = 1,
    GoneWait = 2,
    Origin = Vector3.new(2121, 201, 2121),
    Crops = {"berry", "wheat", "onion", "tomato", "carrot"},
    Crop = "wheat",
    SeedMap = {berry = "BerrySeeds", wheat = "WheatSeeds", onion = "OnionSeeds", tomato = "TomatoSeeds", carrot = "CarrotSeeds"},
    Seeds = {"WheatSeeds", "BerrySeeds", "OnionSeeds", "TomatoSeeds", "CarrotSeeds"},
    Enabled = {berry = false, wheat = true, onion = false, tomato = false, carrot = false},
}

-- Auto Farm (Auto Tree + Auto Mine) - engine from KyFarm v8.8
local Farm = {}
local FarmCFG = {
    TreeKind = "wood",          -- "wood" / "pine"
    HitTime = 15,               -- seconds spent on one tree before moving on
    MineMaxTime = 0,            -- seconds spent on one rock (0 = until it is mined out)
    SwingDelay = 0.4,
    StandDist = 4,              -- distance to stand from the target (studs)
    WalkSpeed = 30,
    PathRadius = 2.5,
    PathHeight = 5,
    WaypointSpacing = 6,
    RockNear = 10,              -- area used to find the next rock after one is mined out
    SwingAnim = true,
    MineList = {"stone", "ironore", "coal", "sand", "clay"},
    MineEnabled = {stone = true, ironore = true, coal = true, sand = true, clay = true},
    MinePriority = "ironore",
    MineRoot = "",              -- empty = ResourceField (in Hub)
    Hover = true,               -- float while hitting (stay away from slime / skeleton)
    HoverHeight = 15,           -- studs above the ground
    UseHub = true,              -- wood & mine: enter the Hub from the island first
    ReturnToHub = true,         -- switching from pine (RUINS) to wood / mine: go back to the Hub first
    ReturnPortalName = "Hub",   -- model INSIDE RUINS that leads back to the Hub (name contains this)
    HubName = "Hub",            -- Hub model in Workspace
    IslandPortalName = "HUB",   -- HUB portal inside Island_*
    HubPad = 10,
    HubWait = 6,
    RuinsName = "RUINS",
    TouchPartName = "TouchPart",
    ResourceName = "ResourceField",
    TeleportOffset = Vector3.new(0, 4, 0),
    RuinsLoadDelay = 4,         -- wait in the Hub so the RUINS portal can load before teleporting
    WaitTimeout = 10,
}

local Rejoin = {On = false, Delay = 5, Loader = ""}
local Blk = {on = false, ids = {}, set = {}}

local Island = {override = "", cache = nil, at = -100}
do
    local function sameMe(v)
        if v == LP then return true end
        local tv = type(v)
        if tv ~= "string" and tv ~= "number" then return false end
        local s = tostring(v)
        return s == tostring(LP.UserId) or s == LP.Name
    end

    local function refersToMe(isl)
        local ok, attrs = pcall(function() return isl:GetAttributes() end)
        if ok then
            for _, v in pairs(attrs) do
                if sameMe(v) then return true end
            end
        end
        for _, c in ipairs(isl:GetChildren()) do
            if c:IsA("ValueBase") then
                local ok2, v = pcall(function() return c.Value end)
                if ok2 and sameMe(v) then return true end
            end
        end
        return false
    end

    local function nameHasMe(isl)
        return isl.Name:find(tostring(LP.UserId), 1, true) ~= nil
    end

    local function containsChar(isl, hrp)
        if not (hrp and isl:IsA("Model")) then return false end
        local ok, inside = pcall(function()
            local cf, size = isl:GetBoundingBox()
            local rel = cf:PointToObjectSpace(hrp.Position)
            local h = size / 2 + Vector3.new(60, 80, 60)
            return math.abs(rel.X) <= h.X and math.abs(rel.Y) <= h.Y and math.abs(rel.Z) <= h.Z
        end)
        return ok and inside
    end

    local function distTo(isl, hrp)
        if not hrp then return math.huge end
        local ok, d = pcall(function() return (isl:GetPivot().Position - hrp.Position).Magnitude end)
        return ok and d or math.huge
    end

    function Island.get()
        if Island.override ~= "" then
            local o = workspace:FindFirstChild(Island.override)
            if o then return o end
        end
        local now = os.clock()
        if Island.cache and Island.cache.Parent and now - Island.at < 3 then return Island.cache end
        Island.at = now

        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        local best, bestScore, bestDist = nil, -1, math.huge
        for _, c in ipairs(workspace:GetChildren()) do
            if c.Name:find("^Island_") then
                local score = 0
                if c:FindFirstChild("HUB") or c:FindFirstChild("Blocks") then score += 1 end
                if nameHasMe(c) then score += 50 end
                if refersToMe(c) then score += 100 end
                if containsChar(c, hrp) then score += 200 end
                local d = distTo(c, hrp)
                if score > bestScore or (score == bestScore and d < bestDist) then
                    best, bestScore, bestDist = c, score, d
                end
            end
        end
        Island.cache = best
        return best
    end

    function Island.contains(hrp)
        local isl = Island.get()
        return isl ~= nil and containsChar(isl, hrp)
    end

    function Island.list()
        local out = {}
        for _, c in ipairs(workspace:GetChildren()) do
            if c.Name:find("^Island_") then out[#out + 1] = c end
        end
        return out
    end
end

local Slime, Skel, Boss, Combat = {}, {}, {}, {}
local Chest, Harvest, Sys, Webhook = {}, {}, {}, {}
local Link = {pause = false, hubBusy = false}
local DC = {handlers = {}, fired = false, hopping = false}
local WH, CfgUI = {}, {}
local Tg = {}
local Controls = {}
local Deferred = {}
local Stats = {
    start = os.time(), farmSec = 0, swings = 0, kills = 0, hitSlimes = 0, color = {},
    seen = setmetatable({}, {__mode = "k"}),
}

-- only one automation may run at a time: turn every toggle off except `keep`
function Combat.Exclusive(keep)
    for _, k in ipairs({"slime", "boss", "skel", "harvest", "tree", "mine", "plant"}) do
        if k ~= keep and Tg[k] then Tg[k].Set(false) end
    end
end

destroyOld("KyHubGui")
local Gui = new("ScreenGui", {Name = "KyHubGui", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling})
safeParent(Gui)

local vpInit = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
local winW = math.clamp(vpInit.X - 24, 400, 640)
local winH = math.clamp(vpInit.Y - 24, 260, 400)
local sideW = winW < 500 and 138 or 168

local Win = new("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5),
    Size = UDim2.new(0, winW, 0, winH), Position = UDim2.new(0.5, 0, 0.5, 0),
    BackgroundTransparency = 1, BorderSizePixel = 0,
}, Gui)

new("ImageLabel", {
    Name = "Shadow", BackgroundTransparency = 1, Image = "rbxassetid://6014261993",
    ImageColor3 = Color3.new(0, 0, 0), ImageTransparency = 0.4, ScaleType = Enum.ScaleType.Slice,
    SliceCenter = Rect.new(49, 49, 450, 450), Position = UDim2.new(0, -24, 0, -18),
    Size = UDim2.new(1, 48, 1, 48), ZIndex = 0,
}, Win)

local Body = corner(new("Frame", {
    Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.03,
    BorderSizePixel = 0, ZIndex = 1,
}, Win), 16)
new("UIGradient", {
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, T.bg1),
        ColorSequenceKeypoint.new(0.55, Color3.fromRGB(30, 20, 66)),
        ColorSequenceKeypoint.new(1, T.bg2),
    }),
    Rotation = 130,
}, Body)
stroke(Body, T.stroke, 0.82)

local Toast = corner(new("TextLabel", {
    AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.new(0, 300, 0, 34), Position = UDim2.new(0.5, 0, 0, 14),
    BackgroundColor3 = Color3.fromRGB(28, 20, 54), BackgroundTransparency = 0.05, TextColor3 = T.text,
    Font = Enum.Font.GothamMedium, TextSize = 12, Text = "", Visible = false, ZIndex = 50,
    TextTruncate = Enum.TextTruncate.AtEnd,
}, Gui), 17)
stroke(Toast, T.accent, 0.5)
local toastId = 0
local function notify(t)
    toastId += 1
    local id = toastId
    Toast.Text = t
    Toast.Position = UDim2.new(0.5, 0, 0, -20)
    Toast.Visible = true
    TweenService:Create(Toast, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, 0, 0, 14),
    }):Play()
    task.delay(2.5, function() if toastId == id then Toast.Visible = false end end)
end

local Side = corner(new("Frame", {
    Position = UDim2.new(0, 8, 0, 8), Size = UDim2.new(0, sideW, 1, -16),
    BackgroundColor3 = T.side, BackgroundTransparency = 0.92, BorderSizePixel = 0,
}, Body), 14)
stroke(Side, T.stroke, 0.88)

local Dots = new("Frame", {Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1}, Side)
local dotSyms = {}
local function dot(x, color, sym, name)
    local b = corner(new("TextButton", {
        Name = name, Size = UDim2.new(0, 16, 0, 16), Position = UDim2.new(0, x, 0.5, -8),
        BackgroundColor3 = color, Text = "", AutoButtonColor = false,
    }, Dots), 8)
    local s = new("TextLabel", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 11,
        TextColor3 = Color3.fromRGB(70, 20, 20), Text = sym, Visible = false,
    }, b)
    dotSyms[#dotSyms + 1] = s
    b.MouseEnter:Connect(function() for _, l in ipairs(dotSyms) do l.Visible = true end end)
    b.MouseLeave:Connect(function() for _, l in ipairs(dotSyms) do l.Visible = false end end)
    return b
end
local CloseBtn = dot(12, Color3.fromRGB(255, 95, 87), "x", "KyHubClose")
local MinBtn = dot(36, Color3.fromRGB(254, 188, 46), "-", "KyHubMin")
local ZoomBtn = dot(60, Color3.fromRGB(40, 200, 64), "+", "KyHubZoom")

local Brand = new("Frame", {Position = UDim2.new(0, 0, 0, 30), Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1}, Side)
local Logo = corner(new("Frame", {
    Position = UDim2.new(0, 12, 0, 5), Size = UDim2.new(0, 30, 0, 30), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
}, Brand), 9)
gradient(Logo, T.accent, T.accent2, 45)
new("TextLabel", {
    Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 16,
    TextColor3 = Color3.new(1, 1, 1), Text = "K",
}, Logo)
new("TextLabel", {
    Position = UDim2.new(0, 50, 0, 4), Size = UDim2.new(1, -56, 0, 18), BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left, Text = "KyHub",
}, Brand)
new("TextLabel", {
    Position = UDim2.new(0, 50, 0, 21), Size = UDim2.new(1, -56, 0, 14), BackgroundTransparency = 1,
    Font = Enum.Font.Gotham, TextSize = 10, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Left,
    Text = "farm toolkit · v17.2",
}, Brand)

local SearchBox = corner(new("TextBox", {
    Position = UDim2.new(0, 10, 0, 76), Size = UDim2.new(1, -20, 0, 28), BackgroundColor3 = T.field,
    BackgroundTransparency = 0.55, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = T.text,
    PlaceholderText = "🔍  Search", PlaceholderColor3 = T.sub, Text = "", ClearTextOnFocus = false,
    TextXAlignment = Enum.TextXAlignment.Left,
}, Side), 9)
new("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 8)}, SearchBox)
stroke(SearchBox)

local TabList = new("ScrollingFrame", {
    Size = UDim2.new(1, 0, 1, -170), Position = UDim2.new(0, 0, 0, 110), BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 2, ScrollBarImageColor3 = T.accent, CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, Side)
new("UIListLayout", {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder}, TabList)
new("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8)}, TabList)

local Profile = new("Frame", {
    AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 54), BackgroundTransparency = 1,
}, Side)
new("Frame", {
    Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -24, 0, 1), BackgroundColor3 = T.stroke,
    BackgroundTransparency = 0.88, BorderSizePixel = 0,
}, Profile)
local Avatar = corner(new("ImageLabel", {
    Position = UDim2.new(0, 12, 0.5, -15), Size = UDim2.new(0, 30, 0, 30), BackgroundColor3 = T.accent,
    BackgroundTransparency = 0.5, BorderSizePixel = 0, Image = "",
}, Profile), 15)
new("TextLabel", {
    Position = UDim2.new(0, 50, 0.5, -16), Size = UDim2.new(1, -56, 0, 16), BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd, Text = LP.DisplayName,
}, Profile)
new("TextLabel", {
    Position = UDim2.new(0, 50, 0.5, 0), Size = UDim2.new(1, -56, 0, 14), BackgroundTransparency = 1,
    Font = Enum.Font.Gotham, TextSize = 10, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd, Text = "@" .. LP.Name,
}, Profile)
task.spawn(function()
    local ok, img = pcall(function()
        return Players:GetUserThumbnailAsync(LP.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
    end)
    if ok and img and Avatar.Parent then Avatar.Image = img end
end)

local Content = new("Frame", {
    Size = UDim2.new(1, -(sideW + 16), 1, 0), Position = UDim2.new(0, sideW + 16, 0, 0), BackgroundTransparency = 1,
}, Body)
local TopBar = new("Frame", {Size = UDim2.new(1, 0, 0, 58), BackgroundTransparency = 1}, Content)
local PageTitle = new("TextLabel", {
    Size = UDim2.new(1, -20, 0, 26), Position = UDim2.new(0, 10, 0, 8), BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold, TextSize = 21, TextColor3 = Color3.new(1, 1, 1),
    TextXAlignment = Enum.TextXAlignment.Left, Text = "",
}, TopBar)
gradient(PageTitle, Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 190, 220), 0)
local PageSub = new("TextLabel", {
    Size = UDim2.new(1, -20, 0, 14), Position = UDim2.new(0, 10, 0, 35), BackgroundTransparency = 1,
    Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Left, Text = "",
}, TopBar)

local PageHolder = new("Frame", {
    Position = UDim2.new(0, 6, 0, 58), Size = UDim2.new(1, -18, 1, -66), BackgroundTransparency = 1, ClipsDescendants = true,
}, Content)

local FloatBox = corner(new("Frame", {
    Size = UDim2.new(0, 46, 0, 46), Position = UDim2.new(0, 14, 0.5, -23), BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0, Visible = false,
}, Gui), 14)
gradient(FloatBox, T.accent, T.accent2, 45)
stroke(FloatBox, T.stroke, 0.7)
local Float = new("TextButton", {
    Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "Ky", Font = Enum.Font.GothamBlack,
    TextSize = 16, TextColor3 = Color3.new(1, 1, 1), AutoButtonColor = false,
}, FloatBox)

local function setWinVisible(v)
    Win.Visible = v
    FloatBox.Visible = not v
end
Float.Activated:Connect(function() setWinVisible(true) end)
MinBtn.Activated:Connect(function() setWinVisible(false) end)

local zoomed = false
ZoomBtn.Activated:Connect(function()
    zoomed = not zoomed
    local vp = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
    local target = zoomed
        and UDim2.new(0, math.clamp(vp.X - 24, 400, 840), 0, math.clamp(vp.Y - 24, 260, 560))
        or UDim2.new(0, winW, 0, winH)
    TweenService:Create(Win, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = target}):Play()
end)

local function makeDrag(handle, target)
    local dragging, startPos, startInput
    handle.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging, startInput, startPos = true, i.Position, target.Position
        end
    end)
    local c1 = UIS.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - startInput
            target.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    local c2 = UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    onCleanup(function() c1:Disconnect(); c2:Disconnect() end)
end
makeDrag(TopBar, Win)
makeDrag(Brand, Win)
makeDrag(Dots, Win)

local hotkeyConn = UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.RightShift then setWinVisible(not Win.Visible) end
end)
onCleanup(function() hotkeyConn:Disconnect() end)

local Pages, TabBtns, TabOrder, PageData = {}, {}, {}, {}
local currentTab = nil
local orderCounter = 0
local function nextOrder() orderCounter += 1; return orderCounter end

local function newPage(name)
    local p = new("ScrollingFrame", {
        Name = name, Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, ScrollBarImageColor3 = T.accent, ScrollBarImageTransparency = 0.3,
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false,
    }, PageHolder)
    new("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, p)
    new("UIPadding", {PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8)}, p)
    Pages[name] = p
    PageData[p] = {name = name, groups = {}, cur = nil}
    return p
end

local function selectTab(name)
    currentTab = name
    for n, p in pairs(Pages) do p.Visible = (n == name) end
    for n, b in pairs(TabBtns) do
        local on = (n == name)
        TweenService:Create(b.btn, TweenInfo.new(0.15), {TextColor3 = on and Color3.new(1, 1, 1) or T.sub}):Play()
        TweenService:Create(b.pill, TweenInfo.new(0.15), {BackgroundTransparency = on and 0.8 or 1}):Play()
        TweenService:Create(b.ps, TweenInfo.new(0.15), {Transparency = on and 0.45 or 1}):Play()
    end
    PageTitle.Text = name
    PageSub.Text = (TabBtns[name] and TabBtns[name].sub) or ""
end

local function addTab(name, icon, sub, c1, c2)
    local holder = new("Frame", {Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = nextOrder()}, TabList)
    local pill = corner(new("Frame", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = T.accent, BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1,
    }, holder), 9)
    local ps = new("UIStroke", {Color = T.accent, Transparency = 1, Thickness = 1}, pill)
    local tile = corner(new("Frame", {
        Position = UDim2.new(0, 6, 0.5, -11), Size = UDim2.new(0, 22, 0, 22), BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0, ZIndex = 2,
    }, holder), 7)
    gradient(tile, c1 or T.accent, c2 or T.accent2, 45)
    new("TextLabel", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 12,
        TextColor3 = Color3.new(1, 1, 1), Text = icon or "•", ZIndex = 3,
    }, tile)
    local btn = new("TextButton", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, AutoButtonColor = false,
        Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Left,
        Text = name, ZIndex = 4, TextTruncate = Enum.TextTruncate.AtEnd,
    }, holder)
    new("UIPadding", {PaddingLeft = UDim.new(0, 36), PaddingRight = UDim.new(0, 4)}, btn)
    local page = newPage(name)
    TabBtns[name] = {btn = btn, pill = pill, ps = ps, holder = holder, page = page, sub = sub}
    TabOrder[#TabOrder + 1] = name
    btn.Activated:Connect(function() selectTab(name) end)
    return page
end

local function Section(page, text)
    local pd = PageData[page]
    local label = new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 12,
        TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Left, Text = text, LayoutOrder = nextOrder(),
    }, page)
    new("UIPadding", {PaddingLeft = UDim.new(0, 6), PaddingTop = UDim.new(0, 8)}, label)
    local frame = corner(new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.card,
        BackgroundTransparency = CARD_T, BorderSizePixel = 0, LayoutOrder = nextOrder(),
    }, page), 12)
    stroke(frame)
    new("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder}, frame)
    local g = {label = label, frame = frame, rows = {}}
    pd.groups[#pd.groups + 1] = g
    pd.cur = g
end

local function slot(page, h, search, auto)
    local g = PageData[page].cur
    local f = new("Frame", {
        Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = #g.rows + 1,
    }, g.frame)
    if auto then f.AutomaticSize = Enum.AutomaticSize.Y end
    local div = new("Frame", {
        Size = UDim2.new(1, -28, 0, 1), Position = UDim2.new(0, 14, 0, 0), BackgroundColor3 = T.stroke,
        BackgroundTransparency = 0.9, BorderSizePixel = 0, Visible = #g.rows > 0,
    }, f)
    g.rows[#g.rows + 1] = {frame = f, div = div, text = tostring(search or ""):lower()}
    return f
end

local function splitText(text)
    local t, d = tostring(text):match("^(.-)|(.*)$")
    if t then return t, d end
    return tostring(text), nil
end
local function rowH(text)
    local _, d = splitText(text)
    return d and 52 or 44
end
local function labelBlock(f, text, reserve)
    local t, d = splitText(text)
    local lt = new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.new(0, 14, 0, d and 8 or 0), Size = UDim2.new(1, reserve, 0, d and 18 or 44),
        Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left, Text = t,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, f)
    if d then
        new("TextLabel", {
            BackgroundTransparency = 1, Position = UDim2.new(0, 14, 0, 26), Size = UDim2.new(1, reserve, 0, 16),
            Font = Enum.Font.Gotham, TextSize = 11, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Left, Text = d,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, f)
    end
    return lt
end

local function Toggle(page, key, text, default, cb)
    local f = slot(page, rowH(text), text)
    labelBlock(f, text, -76)
    local sw = corner(new("TextButton", {
        Text = "", AutoButtonColor = false, Size = UDim2.new(0, 46, 0, 26), Position = UDim2.new(1, -58, 0.5, -13),
        BackgroundColor3 = T.off,
    }, f), 13)
    local knob = corner(new("Frame", {
        Size = UDim2.new(0, 22, 0, 22), Position = UDim2.new(0, 2, 0.5, -11), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
    }, sw), 11)
    stroke(knob, Color3.new(0, 0, 0), 0.85)
    local state = false
    local obj = {}
    function obj.Get() return state end
    function obj.Set(v, silent)
        v = v and true or false
        if v == state then return end
        state = v
        TweenService:Create(sw, TweenInfo.new(0.18), {BackgroundColor3 = v and T.on or T.off}):Play()
        TweenService:Create(knob, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {Position = v and UDim2.new(0, 22, 0.5, -11) or UDim2.new(0, 2, 0.5, -11)}):Play()
        if cb and not silent then cb(v) end
    end
    sw.Activated:Connect(function() obj.Set(not state) end)
    if key then
        Controls[key] = {kind = "toggle", get = function() return state end, set = function(v) obj.Set(v) end}
    end
    if default then Deferred[#Deferred + 1] = function() obj.Set(true) end end
    return obj
end

local function Input(page, key, text, default, cb, min)
    local f = slot(page, rowH(text), text)
    labelBlock(f, text, -118)
    local box = corner(new("TextBox", {
        Size = UDim2.new(0, 86, 0, 28), Position = UDim2.new(1, -98, 0.5, -14), BackgroundColor3 = T.field,
        BackgroundTransparency = 0.5, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = T.text,
        Text = tostring(default), ClearTextOnFocus = false,
    }, f), 8)
    stroke(box)
    local value = default
    local function apply(n)
        value = n
        box.Text = tostring(n)
        if cb then cb(n) end
    end
    box.FocusLost:Connect(function()
        local n = tonumber(box.Text)
        if n and n >= (min or 0) then apply(n) else box.Text = tostring(value) end
    end)
    if key then
        Controls[key] = {kind = "input", get = function() return value end,
            set = function(v) local n = tonumber(v); if n then apply(n) end end}
    end
    local obj = {}
    function obj.Get() return value end
    function obj.Set(n, silent)
        value = n
        box.Text = tostring(n)
        if cb and not silent then cb(n) end
    end
    return obj
end

local function TextInput(page, key, text, default, cb, width, placeholder)
    local w = width or 150
    local f = slot(page, rowH(text), text)
    labelBlock(f, text, -(w + 28))
    local box = corner(new("TextBox", {
        Size = UDim2.new(0, w, 0, 28), Position = UDim2.new(1, -(w + 12), 0.5, -14), BackgroundColor3 = T.field,
        BackgroundTransparency = 0.5, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = T.text,
        PlaceholderText = placeholder or "", PlaceholderColor3 = T.sub, Text = default or "", ClearTextOnFocus = false,
        TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left,
    }, f), 8)
    new("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8)}, box)
    stroke(box)
    local obj = {}
    function obj.Get() return box.Text end
    function obj.Set(v, silent)
        box.Text = tostring(v or "")
        if cb and not silent then cb(box.Text) end
    end
    box.FocusLost:Connect(function() if cb then cb(box.Text) end end)
    if key then
        Controls[key] = {kind = "text", get = function() return box.Text end, set = function(v) obj.Set(v) end}
    end
    return obj
end

local function Button(page, text, cb, color)
    local f = slot(page, 48, text)
    local base = color and 0.1 or 0.88
    local b = corner(new("TextButton", {
        Position = UDim2.new(0, 12, 0.5, -16), Size = UDim2.new(1, -24, 0, 32), BackgroundColor3 = color or T.card,
        BackgroundTransparency = base, AutoButtonColor = false, Font = Enum.Font.GothamMedium, TextSize = 13,
        TextColor3 = T.text, Text = text,
    }, f), 9)
    stroke(b)
    hover(b, base)
    b.Activated:Connect(cb)
    return b
end

local function ButtonRow(page, items)
    local names = {}
    for _, it in ipairs(items) do names[#names + 1] = it[1] end
    local f = slot(page, 48, table.concat(names, " "))
    local holder = new("Frame", {
        Position = UDim2.new(0, 12, 0.5, -16), Size = UDim2.new(1, -24, 0, 32), BackgroundTransparency = 1,
    }, f)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
    }, holder)
    local n = #items
    for i, it in ipairs(items) do
        local base = it[3] and 0.1 or 0.88
        local b = corner(new("TextButton", {
            Size = UDim2.new(1 / n, -math.floor(6 * (n - 1) / n), 1, 0), BackgroundColor3 = it[3] or T.card,
            BackgroundTransparency = base, AutoButtonColor = false,
            Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = T.text, Text = it[1], LayoutOrder = i,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, holder), 9)
        stroke(b)
        hover(b, base)
        b.Activated:Connect(it[2])
    end
end

local function Info(page, text, minH)
    local f = slot(page, minH or 32, text, true)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
    }, f)
    return new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
        Font = Enum.Font.Gotham, TextSize = 12, TextWrapped = true, TextColor3 = T.good, Text = text,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    }, f)
end

local function ConfigPicker(page, height)
    local f = slot(page, height, "config")
    local sc = new("ScrollingFrame", {
        Size = UDim2.new(1, -20, 1, -12), Position = UDim2.new(0, 10, 0, 6), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, ScrollBarImageColor3 = T.accent, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, f)
    new("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, sc)
    local obj = {selected = nil, names = {}, auto = nil}

    function obj.Render()
        for _, c in ipairs(sc:GetChildren()) do
            if c:IsA("TextButton") or c:IsA("TextLabel") then c:Destroy() end
        end
        if #obj.names == 0 then
            new("TextLabel", {
                Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 12,
                TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Left, Text = "  no saved configs yet",
            }, sc)
            return
        end
        for i, n in ipairs(obj.names) do
            local picked = (n == obj.selected)
            local b = corner(new("TextButton", {
                Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = picked and T.accent or Color3.new(1, 1, 1),
                BackgroundTransparency = picked and 0.35 or 0.94, AutoButtonColor = false,
                Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left,
                Text = "  " .. n .. ((n == obj.auto) and "    ⚡ auto load" or ""), LayoutOrder = i,
            }, sc), 7)
            b.Activated:Connect(function() obj.Select(n) end)
        end
    end

    function obj.Select(n)
        obj.selected = n
        if CfgUI.name and n then CfgUI.name.Set(n, true) end
        obj.Render()
    end

    function obj.SetData(names, auto)
        obj.names, obj.auto = names, auto
        local still = false
        for _, n in ipairs(names) do if n == obj.selected then still = true end end
        if not still then obj.selected = nil end
        obj.Render()
    end
    return obj
end

local function applySearch(q)
    q = trim(q):lower()
    local firstVisible
    for _, name in ipairs(TabOrder) do
        local b = TabBtns[name]
        local pd = PageData[b.page]
        local nameHit = q ~= "" and name:lower():find(q, 1, true) ~= nil
        local total = 0
        for _, g in ipairs(pd.groups) do
            local shown = 0
            for _, r in ipairs(g.rows) do
                local hit = (q == "") or nameHit or (r.text ~= "" and r.text:find(q, 1, true) ~= nil)
                r.frame.Visible = hit
                if hit then
                    r.div.Visible = shown > 0
                    shown += 1
                end
            end
            g.frame.Visible = shown > 0
            g.label.Visible = shown > 0
            total += shown
        end
        local vis = (q == "") or nameHit or total > 0
        b.holder.Visible = vis
        if vis and not firstVisible then firstVisible = name end
    end
    if firstVisible and currentTab and not TabBtns[currentTab].holder.Visible then
        selectTab(firstVisible)
    end
end
SearchBox:GetPropertyChangedSignal("Text"):Connect(function() applySearch(SearchBox.Text) end)

local function StatRow(page, text, initial)
    local f = slot(page, rowH(text), text)
    labelBlock(f, text, -170)
    return new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.new(1, -164, 0, 0), Size = UDim2.new(0, 150, 1, 0),
        Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = T.accent2, TextXAlignment = Enum.TextXAlignment.Right,
        Text = initial or "-", TextTruncate = Enum.TextTruncate.AtEnd,
    }, f)
end

-- display names for dropdown options whose capitalization differs from "Xxxx"
local PRETTY = {
    ironore = "IronOre",
    WoodSword = "Wood Sword", IronSword = "Iron Sword", GoldboneSword = "Goldbone Sword", SoulScepter = "Soul Scepter",
    SkeletonArcher = "Archer", SkeletonKnight = "Knight",
}
local function labelOf(o) return PRETTY[o] or (o:sub(1, 1):upper() .. o:sub(2)) end

local function MultiSelect(page, key, text, options, selected, cb, suffix)
    local h = rowH(text)
    local f = slot(page, h, text, true)
    local inner = new("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1}, f)
    new("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder}, inner)
    local head = new("Frame", {Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 1, LayoutOrder = 1}, inner)
    labelBlock(head, text, -150)
    local btn = corner(new("TextButton", {
        Size = UDim2.new(0, 124, 0, 28), Position = UDim2.new(1, -136, 0.5, -14), BackgroundColor3 = T.field,
        BackgroundTransparency = 0.5, AutoButtonColor = false, Font = Enum.Font.GothamBold, TextSize = 12,
        TextColor3 = T.text, Text = "", TextTruncate = Enum.TextTruncate.AtEnd,
    }, head), 8)
    stroke(btn)
    local list = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
        LayoutOrder = 2, Visible = false,
    }, inner)
    new("UIListLayout", {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder}, list)
    new("UIPadding", {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 10)}, list)

    local sel, rows = {}, {}
    for _, o in ipairs(options) do sel[o] = selected[o] and true or false end

    local function label(o) return labelOf(o) end
    local function refresh()
        local names, n = {}, 0
        for _, o in ipairs(options) do
            if sel[o] then names[#names + 1] = label(o); n += 1 end
            local r = rows[o]
            if r then
                r.box.BackgroundColor3 = sel[o] and T.on or Color3.new(1, 1, 1)
                r.box.BackgroundTransparency = sel[o] and 0 or 0.85
                r.tick.Visible = sel[o]
            end
        end
        btn.Text = (n == 0 and "None selected" or (n == #options and "All" or table.concat(names, ", "))) .. "  ▾"
    end

    for i, o in ipairs(options) do
        local row = corner(new("TextButton", {
            Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.94,
            AutoButtonColor = false, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = T.text,
            TextXAlignment = Enum.TextXAlignment.Left, Text = label(o) .. (suffix or " Slime"), LayoutOrder = i,
        }, list), 7)
        new("UIPadding", {PaddingLeft = UDim.new(0, 40)}, row)
        local box = corner(new("Frame", {
            Position = UDim2.new(0, -30, 0.5, -9), Size = UDim2.new(0, 18, 0, 18), BorderSizePixel = 0,
        }, row), 5)
        local tick = new("TextLabel", {
            Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 12,
            TextColor3 = Color3.new(1, 1, 1), Text = "✓",
        }, box)
        rows[o] = {box = box, tick = tick}
        row.Activated:Connect(function()
            sel[o] = not sel[o]
            refresh()
            if cb then cb(sel) end
        end)
    end
    btn.Activated:Connect(function() list.Visible = not list.Visible end)
    refresh()
    if cb then cb(sel) end

    if key then
        Controls[key] = {
            kind = "text",
            get = function()
                local t = {}
                for _, o in ipairs(options) do if sel[o] then t[#t + 1] = o end end
                return table.concat(t, ",")
            end,
            set = function(v)
                local on = {}
                for w in tostring(v or ""):gmatch("[^,]+") do on[trim(w):lower()] = true end
                for _, o in ipairs(options) do sel[o] = on[o:lower()] or false end
                refresh()
                if cb then cb(sel) end
            end,
        }
    end
end

local function SingleSelect(page, key, text, options, default, cb)
    local h = rowH(text)
    local f = slot(page, h, text, true)
    local inner = new("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1}, f)
    new("UIListLayout", {SortOrder = Enum.SortOrder.LayoutOrder}, inner)
    local head = new("Frame", {Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 1, LayoutOrder = 1}, inner)
    labelBlock(head, text, -150)
    local btn = corner(new("TextButton", {
        Size = UDim2.new(0, 124, 0, 28), Position = UDim2.new(1, -136, 0.5, -14), BackgroundColor3 = T.field,
        BackgroundTransparency = 0.5, AutoButtonColor = false, Font = Enum.Font.GothamBold, TextSize = 12,
        TextColor3 = T.text, Text = "", TextTruncate = Enum.TextTruncate.AtEnd,
    }, head), 8)
    stroke(btn)
    local list = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
        LayoutOrder = 2, Visible = false,
    }, inner)
    new("UIListLayout", {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder}, list)
    new("UIPadding", {PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingBottom = UDim.new(0, 10)}, list)

    local cur, rows = default, {}
    local function label(o) return labelOf(o) end
    local function refresh()
        btn.Text = label(cur) .. "  ▾"
        for o, r in pairs(rows) do
            r.BackgroundColor3 = (o == cur) and T.accent or Color3.new(1, 1, 1)
            r.BackgroundTransparency = (o == cur) and 0.35 or 0.94
        end
    end
    local function choose(o)
        cur = o
        refresh()
        if cb then cb(cur) end
    end

    for i, o in ipairs(options) do
        rows[o] = corner(new("TextButton", {
            Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.94,
            AutoButtonColor = false, Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = T.text,
            TextXAlignment = Enum.TextXAlignment.Left, Text = "  " .. label(o), LayoutOrder = i,
        }, list), 7)
        rows[o].Activated:Connect(function()
            choose(o)
            list.Visible = false
        end)
    end
    btn.Activated:Connect(function() list.Visible = not list.Visible end)
    choose(default)

    if key then
        Controls[key] = {
            kind = "text",
            get = function() return cur end,
            set = function(v)
                v = trim(v):lower()
                for _, o in ipairs(options) do
                    if o:lower() == v then choose(o) return end
                end
            end,
        }
    end
    return {Get = function() return cur end, Set = function(v) choose(v) end}
end

-- pages
local pHome = addTab("Home", "🏠", "Overview and session stats", Color3.fromRGB(255, 205, 80), Color3.fromRGB(255, 110, 150))
local pCombat = addTab("Auto Combat", "⚔", "Auto slime, boss and skeleton", Color3.fromRGB(255, 94, 168), Color3.fromRGB(170, 90, 255))
local pChest = addTab("Overflow Chest", "📦", "Collect chests that are full", Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 110, 90))
local pHarvest = addTab("Auto Harvest", "🌱", "Automatic crop harvesting", Color3.fromRGB(60, 220, 140), Color3.fromRGB(40, 170, 200))
local pFarm = addTab("Auto Farm", "⛏", "Auto chop trees and mine ores", Color3.fromRGB(130, 210, 90), Color3.fromRGB(40, 150, 110))
local pWeb = addTab("Webhook", "🔔", "Discord notifications", Color3.fromRGB(88, 200, 255), Color3.fromRGB(90, 120, 255))
local pSet = addTab("Settings", "⚙", "Performance, island, rejoin, config", Color3.fromRGB(150, 150, 184), Color3.fromRGB(96, 96, 140))

local H = {c = {}}
Section(pHome, "Welcome")
Info(pHome, "Hello, " .. LP.DisplayName .. "! KyHub v17.2 is ready. Enable features from the tabs on the left. Stats below are counted since this script started.", 32)
Section(pHome, "Session stats")
H.up = StatRow(pHome, "Script uptime|Hours:minutes:seconds since KyHub started", "00:00:00")
H.farm = StatRow(pHome, "Auto Combat active|Total time slime / boss / skeleton farming has been on", "00:00:00")
H.hit = StatRow(pHome, "Slimes hit|Number of different slimes hit", "0")
H.swing = StatRow(pHome, "Total swings|Number of swings / shots sent", "0")
H.kill = StatRow(pHome, "Mobs killed|Total kills since the script started", "0")
H.rate = StatRow(pHome, "Average kills per hour|Based on Auto Combat active time", "-")
Section(pHome, "Kills per color")
for _, nm in ipairs(SlimeCFG.Priority) do
    H.c[nm] = StatRow(pHome, nm:sub(1, 1):upper() .. nm:sub(2) .. " Slime", "0")
end
Section(pHome, "Status")
H.feat = Info(pHome, "Active features: none", 32)
Button(pHome, "Reset stats", function()
    Stats.start = os.time()
    Stats.farmSec, Stats.swings, Stats.kills, Stats.hitSlimes = 0, 0, 0, 0
    Stats.color = {}
    table.clear(Stats.seen)
    notify("Stats have been reset.")
end, Color3.fromRGB(255, 84, 98))

local function fmtClock(sec)
    sec = math.max(0, math.floor(sec))
    return ("%02d:%02d:%02d"):format(sec // 3600, (sec % 3600) // 60, sec % 60)
end
task.spawn(function()
    local lastTick = os.clock()
    while Alive do
        task.wait(1)
        local now = os.clock()
        local dt = now - lastTick
        lastTick = now
        if Combat.IsActive and Combat.IsActive() then Stats.farmSec += dt end
        pcall(function()
            H.up.Text = fmtClock(os.time() - Stats.start)
            H.farm.Text = fmtClock(Stats.farmSec)
            H.hit.Text = tostring(Stats.hitSlimes)
            H.swing.Text = tostring(Stats.swings)
            H.kill.Text = tostring(Stats.kills)
            H.rate.Text = (Stats.farmSec >= 60) and ("%.1f"):format(Stats.kills / (Stats.farmSec / 3600)) or "-"
            for nm, lbl in pairs(H.c) do lbl.Text = tostring(Stats.color[nm] or 0) end
            local on = {}
            if Tg.slime and Tg.slime.Get() then on[#on + 1] = "Auto Slime" end
            if Tg.boss and Tg.boss.Get() then on[#on + 1] = "Auto Boss" end
            if Tg.skel and Tg.skel.Get() then on[#on + 1] = "Auto Skeleton" end
            if Tg.chest and Tg.chest.Get() then on[#on + 1] = "Auto Collect" end
            if Tg.harvest and Tg.harvest.Get() then on[#on + 1] = "Auto Harvest" end
            if Tg.tree and Tg.tree.Get() then on[#on + 1] = "Auto Tree" end
            if Tg.mine and Tg.mine.Get() then on[#on + 1] = "Auto Mine" end
            local isl = Island.get()
            H.feat.Text = ("Active features: %s\nIsland: %s"):format(#on > 0 and table.concat(on, ", ") or "none", isl and isl.Name or "not detected yet")
        end)
    end
end)

-- =====================================================================
-- AUTO COMBAT UI (Auto Slime + Auto Boss + Auto Skeleton)
-- =====================================================================
local COLORS = {"pink", "orange", "blue", "green"}
local WEAPONS = {"WoodSword", "IronSword", "GoldboneSword", "SoulScepter"}

Section(pCombat, "Auto Slime")
Tg.slime = Toggle(pCombat, "slime.on", "Auto Slime|Hit slimes by color priority", false, function(v) Slime.Set(v) end)
SingleSelect(pCombat, "combat.weapon", "Weapon|Sword = swing, Scepter = shoot + auto aim", WEAPONS, SlimeCFG.Weapon, function(w)
    SlimeCFG.Weapon = w
    if Combat.Equip then pcall(Combat.Equip) end
end)
MultiSelect(pCombat, "slime.targets", "Slimes to hit|Choose which slime colors to attack",
    COLORS, SlimeCFG.Enabled, function(sel) SlimeCFG.Enabled = sel end)
SingleSelect(pCombat, "slime.priority", "Priority|Hit first, the rest follow", COLORS, SlimeCFG.Priority[1], function(c)
    local list = {c}
    for _, o in ipairs(COLORS) do if o ~= c then list[#list + 1] = o end end
    for i, o in ipairs(list) do SlimeCFG.Priority[i] = o end
end)
Toggle(pCombat, "slime.usehub", "Touch HUB portal|Touch the HUB portal before farming", SlimeCFG.UseHub, function(v) SlimeCFG.UseHub = v end)
Toggle(pCombat, "slime.autohub", "Auto Hub|Retry the portal if the teleport fails", SlimeCFG.AutoHub, function(v) SlimeCFG.AutoHub = v end)
Toggle(pCombat, "slime.swinganim", "Swing animation|Play the swing animation when hitting", SlimeCFG.SwingAnim, function(v) SlimeCFG.SwingAnim = v end)
Toggle(pCombat, "slime.shotfx", "Shot effect|Blue orb when firing the Soul Scepter", SlimeCFG.ShotFx, function(v) SlimeCFG.ShotFx = v end)
Toggle(pCombat, "slime.fixcam", "Fix camera|Force the camera to follow the character while farming (mobile)", SlimeCFG.FixCamera, function(v) SlimeCFG.FixCamera = v end)


Section(pCombat, "Auto Boss")
Boss.info = Info(pCombat, "Mengecek boss...", 32)
Toggle(pCombat, "boss.realtime", "Realtime Boss Status|ON = Hub & Ruins stay loaded, boss is tracked", BossCFG.Realtime, function(v) BossCFG.Realtime = v end)
Tg.boss = Toggle(pCombat, "boss.on", "Auto Boss|Island > HUB > RUINS, then fly & attack the boss", false, function(v) Boss.Set(v) end)
Toggle(pCombat, "boss.route", "Route HUB > RUINS|Island > HUB > RUINS before going to the boss", BossCFG.UseRoute, function(v) BossCFG.UseRoute = v end)
Input(pCombat, "boss.height", "Boss fly height|Vertical distance above the boss (studs)", BossCFG.Height, function(n) BossCFG.Height = n end, 0)
Input(pCombat, "boss.offset", "Boss offset|Horizontal offset from the boss (studs)", BossCFG.Offset, function(n) BossCFG.Offset = n end, 0)

Section(pCombat, "Auto Skeleton")
Tg.skel = Toggle(pCombat, "skel.on", "Auto Skeleton|Island > HUB > RUINS, then hit skeletons", false, function(v) Skel.Set(v) end)
MultiSelect(pCombat, "skel.targets", "Skeleton to hit|Choose which skeleton types to attack",
    SkelCFG.Types, SkelCFG.Enabled, function(sel) SkelCFG.Enabled = sel end, "")
SingleSelect(pCombat, "skel.priority", "Skeleton priority|Hit first, the rest follow", SkelCFG.Types, SkelCFG.Priority[1], function(c)
    local list = {c}
    for _, o in ipairs(SkelCFG.Types) do if o ~= c then list[#list + 1] = o end end
    for i, o in ipairs(list) do SkelCFG.Priority[i] = o end
end)
Toggle(pCombat, "skel.route", "Route HUB > RUINS|Island > HUB > RUINS before farming", SkelCFG.UseRoute, function(v) SkelCFG.UseRoute = v end)
Toggle(pCombat, "skel.fly", "Fly while hit|ON = melayang di atas skeleton saat hit, OFF = hit dari tanah", false, function(v) SkelCFG.FlyWhileHit = v end)
Section(pCombat, "Skeleton status")
Skel.info = Info(pCombat, "Ready.", 32)
Info(pCombat, "Auto Slime, Auto Boss, Auto Skeleton, Auto Harvest, Auto Tree and Auto Mine turn each other off: only one can run at a time. Weapon, WalkSpeed, Hit range, Shoot range and Swing delay are shared by slime, boss and skeleton.", 32)

Section(pChest, "Overflow Chest")
Tg.chest = Toggle(pChest, "chest.on", "Auto Collect", false, function(v) Chest.Set(v) end)
Input(pChest, "chest.interval", "Interval|Minutes.seconds, 0.30 = 30 seconds", ChestCFG.IntervalMin, function(n) ChestCFG.IntervalMin = n end, 0.05)
Toggle(pChest, "chest.onlyfull", "Only FULL chests", ChestCFG.OnlyFull, function(v) ChestCFG.OnlyFull = v end)
Toggle(pChest, "chest.teleport", "Teleport", ChestCFG.Teleport, function(v) ChestCFG.Teleport = v end)

Section(pChest, "Status")
Chest.info = Info(pChest, "Ready.", 50)
Info(pChest, "Going home picks a portal inside the Hub model whose name (or parent model name) contains the word in the \"Home portal name\" field. If it picks the wrong portal or finds none, click DEBUG and check the console (F9): every portal in the Hub is listed with its full path.", 32)

-- WalkSpeed / Radius / PerSecond are intentionally not shown in the UI
Section(pHarvest, "Auto Harvest")
Tg.harvest = Toggle(pHarvest, "harvest.on", "Auto Harvest|Walk around and harvest crops automatically", false, function(v) Harvest.Set(v) end)
local seedSel
SingleSelect(pHarvest, "harvest.crop", "Crop|Crop to harvest (replant seed follows)",
    HarvestCFG.Crops, HarvestCFG.Crop, function(k)
        HarvestCFG.Crop = k
        for _, c in ipairs(HarvestCFG.Crops) do HarvestCFG.Enabled[c] = (c == k) end
        local sd = HarvestCFG.SeedMap[k]
        if sd then
            HarvestCFG.Seed = sd
            if seedSel then seedSel.Set(sd) end
        end
    end)
Toggle(pHarvest, "harvest.tpfallback", "Teleport if stuck|Jump next to the crop when blocked", HarvestCFG.TeleportFallback, function(v) HarvestCFG.TeleportFallback = v end)
Toggle(pHarvest, "harvest.onlyripe", "Only ripe crops|Stay idle until a crop is ripe", HarvestCFG.OnlyRipe, function(v) HarvestCFG.OnlyRipe = v end)
Toggle(pHarvest, "harvest.skipwater", "Skip crops that need water|Crops with the 💧 icon are not harvested", HarvestCFG.SkipNeedsWater, function(v) HarvestCFG.SkipNeedsWater = v end)
Button(pHarvest, "DEBUG crops (see console)", function() Harvest.Debug() end, Color3.fromRGB(255, 160, 60))
Section(pHarvest, "Plant after harvest")
Harvest.PCFG = PlantCFG
Toggle(pHarvest, "plant.near", "Plant nearby plots|Also plant empty plots around the character", PlantCFG.PlantNear, function(v)
    Harvest.PCFG.PlantNear = v
end)
seedSel = SingleSelect(pHarvest, "harvest.seed", "Seed|Seed to plant (follows the selected crop)",
    HarvestCFG.Seeds, HarvestCFG.SeedMap[HarvestCFG.Crop] or HarvestCFG.Seed, function(sd)
        HarvestCFG.Seed = sd
    end)
Input(pHarvest, "plant.slot", "Backup slot|Seed slot tried first when calibrating", PlantCFG.Slot, function(n) Harvest.PCFG.Slot = n end, 0)
ButtonRow(pHarvest, {
    {"Reset calibration", function() if Harvest.PlantReset then Harvest.PlantReset() end end, Color3.fromRGB(72, 160, 255)},
    {"DEBUG plant", function() if Harvest.PlantDebug then Harvest.PlantDebug() end end, Color3.fromRGB(255, 160, 60)},
})
Section(pHarvest, "Plant status")
Harvest.pinfo = Info(pHarvest, "Idle", 32)
Section(pHarvest, "Status")
Harvest.info = Info(pHarvest, "Idle", 32)
Info(pHarvest, "Pick one crop in the dropdown and the replant seed follows automatically (e.g. Wheat = WheatSeeds). Then turn on Auto Harvest: the character walks to the crop, harvests it, and plants a seed again on the same plot if Replant is on.", 32)

-- Auto Farm UI
Section(pFarm, "Auto Tree")
Tg.tree = Toggle(pFarm, "tree.on", "Auto Tree|Walk to trees, hold the Axe and chop", false, function(v) Farm.SetTree(v) end)
SingleSelect(pFarm, "tree.kind", "Tree type|Wood, or Pine (Island > Hub > RUINS)", {"wood", "pine"}, FarmCFG.TreeKind, function(k)
    if Farm.OnTreeKind then Farm.OnTreeKind(k) else FarmCFG.TreeKind = k end
end)
Button(pFarm, "DEBUG trees (see console)", function() Farm.DebugTree() end, Color3.fromRGB(255, 160, 60))

Section(pFarm, "Auto Mine")
Tg.mine = Toggle(pFarm, "mine.on", "Auto Mine|Hold the Pickaxe, find ore and mine", false, function(v) Farm.SetMine(v) end)
MultiSelect(pFarm, "mine.targets", "Materials to mine|Pick one or all of them",
    FarmCFG.MineList, FarmCFG.MineEnabled, function(sel) FarmCFG.MineEnabled = sel end, "")
SingleSelect(pFarm, "mine.priority", "Priority|Searched first, the rest follow", FarmCFG.MineList, FarmCFG.MinePriority,
    function(k) FarmCFG.MinePriority = k end)

Section(pFarm, "Settings")
-- Toggle(pFarm, "farm.usehub", "Enter Hub first|Touch the HUB portal from the island (wood / mine)", FarmCFG.UseHub, function(v) FarmCFG.UseHub = v end)
-- Toggle(pFarm, "farm.returnhub", "Return to Hub from RUINS|Switching Pine > Wood / Mine touches the TouchPart of the Hub model inside RUINS", FarmCFG.ReturnToHub, function(v) FarmCFG.ReturnToHub = v end)
-- Toggle(pFarm, "farm.swinganim", "Swing animation|Play the swing animation when hitting", FarmCFG.SwingAnim, function(v) FarmCFG.SwingAnim = v end)
-- Input(pFarm, "farm.hittime", "Time per tree|Seconds before moving to another tree", FarmCFG.HitTime, function(n) FarmCFG.HitTime = n end, 3)
-- Input(pFarm, "farm.minetime", "Max time per rock|Seconds (0 = until it is mined out)", FarmCFG.MineMaxTime, function(n) FarmCFG.MineMaxTime = n end, 0)
-- Input(pFarm, "farm.rockarea", "Rock area|Studs, used to find the next rock", FarmCFG.RockNear, function(n) FarmCFG.RockNear = n end, 2)
-- Input(pFarm, "farm.swingdelay", "Swing delay|Pause between swings (seconds)", FarmCFG.SwingDelay, function(n) FarmCFG.SwingDelay = n end, 0.1)
-- Input(pFarm, "farm.ruinsdelay", "RUINS portal delay|Seconds to wait in the Hub before the RUINS portal", FarmCFG.RuinsLoadDelay, function(n) FarmCFG.RuinsLoadDelay = n end, 0)
Section(pFarm, "Status")
Farm.info = Info(pFarm, "Ready.", 50)
Info(pFarm, "The tool is equipped automatically (Axe / Pickaxe). Pine route: Island > HUB portal > Hub > RUINS > TouchPart, repeated after a respawn. If trees or ore are not found, click a DEBUG button and check the console (F9).", 32)

Section(pWeb, "Discord Webhook")
WH.url = TextInput(pWeb, "wh.url", "Webhook URL|Discord channel webhook link", "", nil, 150, "https://discord.com/api/webhooks/...")
WH.master = Toggle(pWeb, "wh.on", "Webhook enabled|Turn on all notifications", false, function(v) Webhook.Set(v) end)
Input(pWeb, "wh.cooldown", "Item notice cooldown|Seconds, to avoid spam", 5, nil, 1)

Section(pWeb, "Online status")
WH.hb = Toggle(pWeb, "wh.hb.on", "Send 'still online'|Periodic message showing the script is alive", true)
Input(pWeb, "wh.hb.every", "Every (minutes)|Gap between online messages", 10, nil, 1)
WH.dc = Toggle(pWeb, "wh.dc.on", "Disconnect / kick notice|Send the reason for the disconnect", true)
WH.rejoin = Toggle(pWeb, "wh.rejoin.on", "Rejoin notice|Send when back online", true)

Section(pWeb, "Pink Gear")
WH.pink = {
    on = Toggle(pWeb, "wh.pink.on", "Send when Pink Gear drops", true),
    kw = TextInput(pWeb, "wh.pink.kw", "Item name", "PinkGear", nil, 130),
}
Section(pWeb, "Stone")
WH.stone = {
    on = Toggle(pWeb, "wh.stone.on", "Send when Stone drops", false),
    kw = TextInput(pWeb, "wh.stone.kw", "Item name", "Stone", nil, 130),
}

Section(pWeb, "Tools")
ButtonRow(pWeb, {
    {"Send Test", function() Webhook.Test() end, Color3.fromRGB(72, 160, 255)},
    {"Scan Inventory (console)", function() Webhook.Debug() end, Color3.fromRGB(255, 160, 60)},
})
Section(pWeb, "Status")
WH.info = Info(pWeb, "Ready.", 32)
Info(pWeb, "Item names are matched exactly, ignoring case and spaces (\"Pink Gear\" = PinkGear). Use * for \"contains\", e.g. *pink*. Separate several names with commas. If an item is not detected, click Scan Inventory and check the console (F9).", 32)
Info(pWeb, "The rejoin message is only sent if the script runs again after rejoining (autoexec or the Loader in Settings) and a config with the webhook enabled is auto-loaded. If your PC or the game shuts down completely nothing can be sent; the 'still online' messages simply stop arriving.", 32)

Section(pSet, "Performance & safety")
Toggle(pSet, "set.antilag", "Anti Lag|Disable heavy effects to run lighter", false, function(v) Sys.AntiLag(v) end)
Toggle(pSet, "set.antiafk", "Anti AFK|Prevent idle kicks", true, function(v) Sys.AntiAFK(v) end)

Section(pSet, "Island")
TextInput(pSet, "island.name", "Island name|Empty = automatic", "", function(t)
    Island.override = trim(t)
    Island.cache, Island.at = nil, -100
end, 130, "automatic")
Button(pSet, "Check detected island", function()
    Island.cache, Island.at = nil, -100
    local i = Island.get()
    notify(i and ("Island: " .. i.Name) or "Island not found.")
end)
Info(pSet, "The island is detected automatically (your own, whatever its number, or a co-op island). Fill in \"Island name\" only if automatic detection is wrong, e.g. Island_123456:2.", 32)

Section(pSet, "Auto Rejoin")
Toggle(pSet, "rejoin.on", "Auto Rejoin|Rejoin automatically if disconnected", false, function(v) Rejoin.On = v end)
Input(pSet, "rejoin.delay", "Rejoin delay|Seconds before rejoining", 5, function(n) Rejoin.Delay = n end, 3)
TextInput(pSet, "rejoin.loader", "Loader|URL or file name", "", function(t) Rejoin.Loader = trim(t) end, 150, "leave empty if autoexec")
Info(pSet, "The Loader runs KyHub again after rejoining: enter the raw script link, or a file name in the executor's workspace folder. If KyHub is already in autoexec, leave it empty. Rejoin goes to a new server, not the same one.", 32)

Section(pSet, "Anti Same Server")
Toggle(pSet, "blk.on", "Avoid specific IDs|Switch server if an ID below is in this server", false, function(v) Blk.Set(v) end)
TextInput(pSet, "blk.ids", "Blocked user IDs|Separate with commas", "", function(t) Blk.SetIds(t) end, 150, "4576506238, 1950974604")
Blk.info = Info(pSet, "Disabled.", 32)
Info(pSet, "Enter the user IDs of every account that must not share a server, separated by commas (this account's own ID may be included, it is ignored automatically). If this account just joined and one of those IDs is already in the server, KyHub switches to another server right away. If that ID joins later, it is the one that switches (that account must also run KyHub with this feature on); if it is still here after 25 seconds, this account switches. Fill in the Loader under Auto Rejoin (or use autoexec) so KyHub runs again on the new server.", 32)

Section(pSet, "Config")
CfgUI.name = TextInput(pSet, nil, "Config name", "", nil, 150, "e.g. slime-farming")
CfgUI.list = ConfigPicker(pSet, 120)
CfgUI.status = Info(pSet, "Auto Load: OFF", 28)
ButtonRow(pSet, {
    {"Save", function() Sys.Save() end, Color3.fromRGB(60, 210, 180)},
    {"Load", function() Sys.Load() end, Color3.fromRGB(72, 160, 255)},
    {"Delete", function() Sys.Delete() end, Color3.fromRGB(255, 84, 98)},
})
ButtonRow(pSet, {
    {"Set as Auto Load", function() Sys.SetAuto() end, Color3.fromRGB(170, 110, 255)},
    {"Disable Auto Load", function() Sys.ClearAuto() end},
    {"Refresh", function() Sys.Refresh() end},
})
Info(pSet, "Click a config name in the list to select it. Save uses the typed name (or the selected one if empty). Delete must be clicked twice. Configs also store the Webhook URL, so do not share them.", 32)

-- =====================================================================
-- COMBAT COMMON (shared by Auto Slime / Auto Boss / Auto Skeleton)
-- weapon equip, swing animation, SoulScepter shooting + shot effect
-- =====================================================================
do
    local CFG = SlimeCFG
    Combat.lastSet = nil
    Combat.lastEquip = 0

    local function getRemote(name)
        local remotes = RS:FindFirstChild("Remotes")
        return remotes and remotes:FindFirstChild(name)
    end

    local SWING_IDS = {"rbxassetid://86861921756773", "rbxassetid://89881700832616"}
    local swingTracks, swingAnimator, swingIndex = {}, nil, 0
    local function playSwingAnim()
        local c = LP.Character
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        local animator = hum and hum:FindFirstChildOfClass("Animator")
        if not animator then return end

        if swingAnimator ~= animator then
            swingAnimator = animator
            swingTracks = {}
            for i, id in ipairs(SWING_IDS) do
                local a = Instance.new("Animation")
                a.AnimationId = id
                local t = animator:LoadAnimation(a)
                t.Priority = Enum.AnimationPriority.Action
                swingTracks[i] = t
            end
        end

        swingIndex = swingIndex % #swingTracks + 1
        for i, t in ipairs(swingTracks) do
            if i ~= swingIndex and t.IsPlaying then t:Stop(0.08) end
        end
        swingTracks[swingIndex]:Play(0.08)
    end

    -- shot counter: 4th argument of RequestShoot goes up by 1 every shot (41, 42, 43, ...)
    local gameShotN, shotSeq, ownFire = nil, 0, false
    if hookmetamethod and getnamecallmethod then
        pcall(function()
            local old
            old = hookmetamethod(game, "__namecall", function(self, ...)
                if Alive and not ownFire and getnamecallmethod() == "FireServer"
                    and typeof(self) == "Instance" and self.Name == "RequestShoot" then
                    local a = {...}
                    if type(a[4]) == "number" then gameShotN = a[4] end
                end
                return old(self, ...)
            end)
        end)
    end

    -- real shot origin: Attachment "ShotOrigin" on the Soul Scepter (fallback: head)
    local function shotOrigin()
        local c = LP.Character
        if not c then return nil end
        local att = c:FindFirstChild("ShotOrigin", true)
        if att and att:IsA("Attachment") then return att.WorldPosition end
        local part = c:FindFirstChild("Head") or c:FindFirstChild("HumanoidRootPart")
        return part and part.Position
    end

    -- shot effect: neon blue orb with a trail
    local fxLast, fxCount = 0, 0
    local function fxOrb(origin, dir, dist)
        if not CFG.ShotFx then return end
        local now = os.clock()
        if fxCount >= 3 or now - fxLast < 0.3 then return end
        fxLast = now
        fxCount += 1
        task.spawn(function()
            local ball = Instance.new("Part")
            ball.Shape = Enum.PartType.Ball
            ball.Size = Vector3.new(1.5, 1.5, 1.5)
            ball.Material = Enum.Material.Neon
            ball.Color = Color3.fromRGB(70, 200, 255)
            ball.Anchored, ball.CanCollide, ball.CanQuery, ball.CanTouch = true, false, false, false
            ball.CastShadow = false

            local a0 = Instance.new("Attachment")
            a0.Position = Vector3.new(0, 0.7, 0)
            a0.Parent = ball
            local a1 = Instance.new("Attachment")
            a1.Position = Vector3.new(0, -0.7, 0)
            a1.Parent = ball
            local tr = Instance.new("Trail")
            tr.Attachment0, tr.Attachment1 = a0, a1
            tr.Lifetime = 0.3
            tr.MinLength = 0
            tr.FaceCamera = true
            tr.LightEmission = 1
            tr.Color = ColorSequence.new(Color3.fromRGB(90, 215, 255), Color3.fromRGB(40, 110, 255))
            tr.Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1)})
            tr.WidthScale = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0)})
            tr.Parent = ball

            local posA = origin + dir * 1
            local posB = origin + dir * math.max(dist - 1, 1.5)
            pcall(function() ball:PivotTo(CFrame.lookAt(posA, posA + dir)) end)
            ball.Parent = workspace
            game:GetService("Debris"):AddItem(ball, 1)

            local dur = math.clamp(dist / 90, 0.18, 0.4)
            local t0 = os.clock()
            local conn
            conn = RunService.Heartbeat:Connect(function()
                local k = (os.clock() - t0) / dur
                if k >= 1 or not ball.Parent then
                    conn:Disconnect()
                    -- hide the ball, let the trail fade, then remove it
                    pcall(function() ball.Transparency = 1; tr.Enabled = false end)
                    game:GetService("Debris"):AddItem(ball, 0.35)
                    fxCount -= 1
                    return
                end
                local p = posA:Lerp(posB, k)
                pcall(function() ball:PivotTo(CFrame.lookAt(p, p + dir)) end)
            end)
        end)
    end

    -- pick the weapon for the Weapon slot (only when it changed) and hold it
    function Combat.Equip()
        if Combat.lastSet ~= CFG.Weapon then
            local rs = getRemote("RequestSetEquipment")
            if rs then
                pcall(function() rs:FireServer("Weapon", CFG.Weapon, 1) end)
                Combat.lastSet = CFG.Weapon
                task.wait(0.2)
            end
        end
        local re = getRemote("RequestEquipSlot")
        if re then pcall(function() re:FireServer("Weapon") end) end
        Combat.lastEquip = os.clock()
    end

    function Combat.IsScepter() return CFG.Weapon == "SoulScepter" end
    function Combat.AtkRange() return Combat.IsScepter() and CFG.ShootRange or CFG.AttackRange end

    -- sword = swing, Soul Scepter = shoot with auto aim at tp. returns ok, reason
    function Combat.Swing(tp)
        if Combat.IsScepter() then
            local r = getRemote("RequestShoot")
            if not r then return false, "RequestShoot remote not found!" end
            local origin = shotOrigin()
            if not (origin and tp) then return false end
            local diff = tp - origin
            if diff.Magnitude < 0.1 then return false end
            shotSeq = math.max(shotSeq, gameShotN or 0) + 1
            ownFire = true
            pcall(function() r:FireServer(origin, diff.Unit, CFG.ShootType, shotSeq) end)
            ownFire = false
            fxOrb(origin, diff.Unit, diff.Magnitude)
            Stats.swings += 1
            return true
        end
        local r = getRemote("RequestSwing")
        if not r then return false, "RequestSwing remote not found!" end
        if CFG.SwingAnim then pcall(playSwingAnim) end
        pcall(function() r:FireServer(workspace.Terrain) end)
        Stats.swings += 1
        return true
    end
end

-- =====================================================================
-- AUTO SLIME (weapon select + SoulScepter support)
-- =====================================================================
do
    local CFG = SlimeCFG
    local atkRange = Combat.AtkRange
    local active, runId = false, 0
    local teleported = false
    local kills = 0
    local origSpeed = nil
    local lastInfo = ""
    local function setInfo(t)
        if t == lastInfo then return end
        lastInfo = t
        if Slime.info then Slime.info.Text = t end
    end

    local walkPath = {wps = nil, i = 1, goal = nil, at = 0, tried = 0}
    local lastMove, lastMoveGoal = 0, nil
    local function resetWalk()
        walkPath.wps, walkPath.goal = nil, nil
        lastMoveGoal = nil
    end

    local function hookDeath(char)
        local hum = char:WaitForChild("Humanoid", 10)
        if not hum then return end
        hum.Died:Connect(function()
            teleported = false
            Combat.lastEquip = 0
        end)
    end
    local deathConn = LP.CharacterAdded:Connect(function(char)
        teleported = false
        Combat.lastEquip = 0
        origSpeed = nil
        resetWalk()
        task.spawn(hookDeath, char)
    end)
    onCleanup(function() deathConn:Disconnect() end)
    if LP.Character then task.spawn(hookDeath, LP.Character) end

    local function getChar()
        local c = LP.Character
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        local hrp = c and c:FindFirstChild("HumanoidRootPart")
        if hum and hrp and hum.Health > 0 then return hum, hrp end
    end

    local function getHRP()
        return LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    end

    local function getIsland()
        return Island.get()
    end

    local function getTouch()
        local island = getIsland()
        local hub = island and island:FindFirstChild("HUB")
        return hub and hub:FindFirstChild("TouchPart", true)
    end

    local pickTarget, posOf
    local skipped = setmetatable({}, {__mode = "k"})

    local function inLobby()
        local lobby = workspace:FindFirstChild(CFG.LobbyName)
        local hrp = getHRP()
        if not (lobby and hrp and lobby:IsA("Model")) then return false end
        local cf, size = lobby:GetBoundingBox()
        local rel = cf:PointToObjectSpace(hrp.Position)
        local h = size / 2 + Vector3.new(CFG.LobbyPad, CFG.LobbyPad, CFG.LobbyPad)
        return math.abs(rel.X) <= h.X and math.abs(rel.Y) <= h.Y and math.abs(rel.Z) <= h.Z
    end

    local function hubModelExists()
        local lobby = workspace:FindFirstChild(CFG.LobbyName)
        return lobby ~= nil and lobby:IsA("Model")
    end

    local function touchPart(part)
        return fireTouch(part)
    end

    local function runHubTeleport()
        if Link.pause then return false, "Paused, Auto Collect is running...", true end
        if not getHRP() then return false, "Character not found.", true end
        if not getIsland() then return false, "Island not found (no Island_... in workspace yet).", true end
        if not getTouch() then return false, "TouchPart not found in HUB." end

        local verifiable = true
        for attempt = 1, CFG.HubAttempts do
            local touch = getTouch()
            if not touch then return false, "TouchPart not found in HUB." end
            if Link.pause then return false, "Paused, Auto Collect is running...", true end

            if attempt >= 2 then
                local hrp = getHRP()
                if hrp then pcall(function() hrp.CFrame = touch.CFrame end) end
                task.wait(0.25)
            end

            setInfo(("Touching HUB TouchPart... (attempt %d/%d)"):format(attempt, CFG.HubAttempts))
            touchPart(touch)

            if not hubModelExists() then
                verifiable = false
                task.wait(1.5)
                break
            end

            local waited, arrived = 0, false
            while waited < CFG.HubVerifyWait do
                task.wait(0.5)
                waited += 0.5
                if Link.pause then return false, "Paused, Auto Collect is running...", true end
                if inLobby() then arrived = true; break end
            end
            if arrived then break end
            if attempt == CFG.HubAttempts then
                return false, "Teleport to Hub did not work (character is still on the island).", true
            end
        end
        if Link.pause then return false, "Paused, Auto Collect is running...", true end

        setInfo(("Teleporting... waiting %ds"):format(CFG.AfterDelay))
        task.wait(CFG.AfterDelay)
        if Link.pause then return false, "Paused, Auto Collect is running...", true end

        local target
        for _ = 1, math.max(1, math.floor(CFG.FindTimeout / 0.5)) do
            if Link.pause then return false, "Paused, Auto Collect is running...", true end
            local hrp = getHRP()
            if hrp then target = pickTarget(hrp) end
            if target then break end
            task.wait(0.5)
        end
        return true
    end

    local gCache, gTry = nil, 0
    local function getGuardians()
        if gCache and gCache.Parent and #gCache:GetChildren() > 0 then return gCache end
        if os.clock() - gTry < 2 then return (gCache and gCache.Parent) and gCache or nil end
        gTry = os.clock()
        local island = getIsland()
        local found = (island and island:FindFirstChild("Guardians", true)) or workspace:FindFirstChild("Guardians", true)
        if found and #found:GetChildren() == 0 then
            local alt = workspace:FindFirstChild("Guardians", true)
            if alt and alt ~= found and #alt:GetChildren() > 0 then found = alt end
        end
        gCache = found
        return gCache
    end

    local function slimeRank(model)
        local n = model.Name:lower()
        for i, key in ipairs(CFG.Priority) do
            if CFG.Enabled[key] and n:find(key, 1, true) then return i end
        end
    end

    local function isAlive(model)
        if not model or not model.Parent then return false end
        local h = model:FindFirstChildOfClass("Humanoid")
        return not (h and h.Health <= 0)
    end

    function posOf(model)
        local ok, cf = pcall(function() return model:GetPivot() end)
        return ok and cf.Position or nil
    end

    local function guardiansPos(g)
        local ok, cf = pcall(function() return g:GetPivot() end)
        if ok and cf then return cf.Position end
        local sum, n = Vector3.zero, 0
        for _, m in ipairs(g:GetChildren()) do
            local p = posOf(m)
            if p then sum += p; n += 1 end
        end
        return n > 0 and sum / n or nil
    end

    function pickTarget(hrp)
        local any = false
        for _, k in ipairs(CFG.Priority) do
            if CFG.Enabled[k] then any = true end
        end
        if not any then return nil, "Select a slime in the dropdown first" end

        local g = getGuardians()
        if not g then return nil, "Guardians folder not found" end
        local best, bestRank, bestDist
        for _, m in ipairs(g:GetChildren()) do
            local rank = slimeRank(m)
            if rank and isAlive(m) and not (skipped[m] and skipped[m] > os.clock()) then
                local p = posOf(m)
                if p then
                    local d = (p - hrp.Position).Magnitude
                    if not best or rank < bestRank or (rank == bestRank and d < bestDist) then
                        best, bestRank, bestDist = m, rank, d
                    end
                end
            end
        end
        if not best then
            for k, v in pairs(skipped) do
                if v > os.clock() and k.Parent == g then skipped[k] = nil end
            end
        end
        return best, g
    end

    local function swing(tp)
        local ok, why = Combat.Swing(tp)
        if not ok and why then setInfo(why) end
    end

    local function applySpeed(hum)
        if origSpeed == nil then origSpeed = hum.WalkSpeed end
        if hum.WalkSpeed ~= CFG.WalkSpeed then hum.WalkSpeed = CFG.WalkSpeed end
    end

    local function setRotate(hum, v)
        if hum.AutoRotate ~= v then hum.AutoRotate = v end
    end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    pcall(function() rayParams.RespectCanCollide = true end)

    local function pathClear(hrp, goal)
        local g = getGuardians()
        rayParams.FilterDescendantsInstances = g and {LP.Character, g} or {LP.Character}
        local origin = hrp.Position
        local dir = goal - origin
        if dir.Magnitude < 0.5 then return true end
        return workspace:Raycast(origin, dir, rayParams) == nil
    end

    local function moveTo(hum, pos)
        local now = os.clock()
        if lastMoveGoal and (pos - lastMoveGoal).Magnitude < 1.5 and now - lastMove < 0.5 then return end
        lastMove, lastMoveGoal = now, pos
        hum:MoveTo(pos)
    end

    local function stepTowards(hum, hrp, pos)
        local now = os.clock()
        if pathClear(hrp, pos) then
            walkPath.wps = nil
            moveTo(hum, pos)
            return
        end

        local need = not walkPath.wps or not walkPath.goal
            or (pos - walkPath.goal).Magnitude > 10 or now - walkPath.at > 3
        if need and now - walkPath.tried > 0.8 then
            walkPath.tried = now
            local path = PathfindingService:CreatePath({AgentRadius = 3, AgentHeight = 5, AgentCanJump = true})
            local ok = pcall(function() path:ComputeAsync(hrp.Position, pos) end)
            walkPath.goal, walkPath.at = pos, now
            if ok and path.Status == Enum.PathStatus.Success then
                walkPath.wps, walkPath.i = path:GetWaypoints(), 2
            else
                walkPath.wps = nil
            end
        end

        if walkPath.wps then
            local wp = walkPath.wps[walkPath.i]
            while wp and Vector3.new(wp.Position.X - hrp.Position.X, 0, wp.Position.Z - hrp.Position.Z).Magnitude < 3 do
                walkPath.i += 1
                wp = walkPath.wps[walkPath.i]
            end
            if wp then
                if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
                moveTo(hum, wp.Position)
                return
            end
        end
        moveTo(hum, pos)
    end

    local function faceTarget(hrp, pos)
        local flat = Vector3.new(pos.X - hrp.Position.X, 0, pos.Z - hrp.Position.Z)
        if flat.Magnitude < 0.1 then return end
        local look = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
        if look.Magnitude < 0.01 or look.Unit:Dot(flat.Unit) < 0.9 then
            hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat)
        end
    end

    local function restoreChar()
        local c = LP.Character
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        local hrp = c and c:FindFirstChild("HumanoidRootPart")
        if hum then
            hum.AutoRotate = true
            if origSpeed then hum.WalkSpeed = origSpeed end
            if hrp then pcall(function() hum:MoveTo(hrp.Position) end) end
        end
        origSpeed = nil
    end

    local lastCam = 0
    local function fixCamera(hum)
        if not CFG.FixCamera then return end
        local now = os.clock()
        if now - lastCam < 1 then return end
        lastCam = now
        local cam = workspace.CurrentCamera
        if not cam then return end
        pcall(function()
            if cam.CameraType ~= Enum.CameraType.Custom then cam.CameraType = Enum.CameraType.Custom end
            if cam.CameraSubject ~= hum then cam.CameraSubject = hum end
        end)
    end

    local function farmLoop(id)
        local noTargetAt = nil
        while active and runId == id do
            local hum, hrp = getChar()
            if Link.pause then
                setInfo("Paused, Auto Collect is running...")
                task.wait(0.3)
            elseif not hum then
                setInfo("Waiting for character...")
                task.wait(1)
            else
                local skipFarm = false
                if CFG.UseHub and not teleported and inLobby() then
                    teleported = true
                    setInfo("Already in the Hub, walking to slimes...")
                elseif CFG.UseHub and not teleported then
                    Link.hubBusy = true
                    local ok, why, retry
                    if Link.pause then
                        ok, why, retry = false, "Paused, Auto Collect is running...", true
                    else
                        ok, why, retry = runHubTeleport()
                    end
                    Link.hubBusy = false
                    if ok then
                        teleported = true
                        noTargetAt = nil
                        Combat.Equip()
                        task.wait(0.5)
                        setInfo("Teleport done.\nHeading to slimes...")
                    elseif CFG.AutoHub or retry then
                        setInfo(why or "Teleport failed, retrying...")
                        skipFarm = true
                        task.wait(1)
                    else
                        teleported = true
                        setInfo((why or "Teleport skipped.") .. "\nContinuing to the slimes on foot.")
                    end
                end

                if not skipFarm then
                    hum, hrp = getChar()
                    if hum then
                        applySpeed(hum)
                        setRotate(hum, true)
                        fixCamera(hum)
                        if os.clock() - Combat.lastEquip > CFG.EquipEvery then Combat.Equip() end

                        local target, g = pickTarget(hrp)
                        if not target then
                            noTargetAt = noTargetAt or os.clock()
                            if CFG.UseHub and teleported and os.clock() - noTargetAt > CFG.IslandStuckWait
                                and Island.contains(hrp) and not inLobby() then
                                teleported = false
                                noTargetAt = nil
                                resetWalk()
                                setInfo("Still on the island, repeating the HUB portal...")
                                task.wait(0.5)
                            else
                                local gp = typeof(g) == "Instance" and guardiansPos(g)
                                if gp and (gp - hrp.Position).Magnitude > atkRange() * 2 then
                                    setInfo(("Approaching the slime area (%.0f studs)\nKills: %d"):format((gp - hrp.Position).Magnitude, kills))
                                    stepTowards(hum, hrp, gp)
                                    task.wait(0.15)
                                else
                                    setInfo((type(g) == "string" and g) or ("Waiting for slimes. Kills: " .. kills))
                                    task.wait(1)
                                end
                            end
                        else
                            noTargetAt = nil
                            resetWalk()
                            local rank = slimeRank(target)
                            local tag = CFG.Priority[rank]:upper()
                            local attacking, wasAttacking, jumped, lastCheck = false, false, false, 0
                            local stuckPos, stuckT = hrp.Position, os.clock()
                            local stopDist = math.max(2.5, atkRange() - 1.5)

                            while active and runId == id and isAlive(target) and not Link.pause do
                                local h, r = getChar()
                                if not h then break end
                                applySpeed(h)
                                if os.clock() - Combat.lastEquip > CFG.EquipEvery then Combat.Equip() end
                                local tp = posOf(target)
                                if not tp then break end

                                if os.clock() - lastCheck > 1 then
                                    lastCheck = os.clock()
                                    if not slimeRank(target) then break end
                                    local better = pickTarget(r)
                                    if better and better ~= target and slimeRank(better) < rank then break end
                                end

                                local dist = (tp - r.Position).Magnitude
                                if attacking then
                                    attacking = dist <= atkRange() + 3
                                else
                                    attacking = dist <= atkRange()
                                end

                                if not attacking then
                                    wasAttacking = false
                                    setRotate(h, true)
                                    local now = os.clock()
                                    if (r.Position - stuckPos).Magnitude > 1.5 then
                                        stuckPos, stuckT, jumped = r.Position, now, false
                                    else
                                        local idle = now - stuckT
                                        if idle > CFG.StuckTime * 0.5 and not jumped then
                                            jumped = true
                                            h.Jump = true
                                        end
                                        if idle > CFG.StuckTime then
                                            skipped[target] = now + CFG.SkipFor
                                            resetWalk()
                                            setInfo(("Stuck heading to %s, looking for another target"):format(tag))
                                            break
                                        end
                                    end

                                    local away = Vector3.new(r.Position.X - tp.X, 0, r.Position.Z - tp.Z)
                                    local goal = tp
                                    if away.Magnitude > 0.1 then goal = tp + away.Unit * stopDist end

                                    setInfo(("Heading to %s (%.0f studs)\nKills: %d"):format(tag, dist, kills))
                                    stepTowards(h, r, goal)
                                    task.wait(0.12)
                                else
                                    stuckPos, stuckT, jumped = r.Position, os.clock(), false
                                    setInfo(("Hitting %s\nKills: %d"):format(tag, kills))
                                    if not Stats.seen[target] then
                                        Stats.seen[target] = true
                                        Stats.hitSlimes += 1
                                    end
                                    if not wasAttacking then
                                        wasAttacking = true
                                        lastMoveGoal = nil
                                        pcall(function() h:MoveTo(r.Position) end)
                                    end
                                    setRotate(h, false)
                                    faceTarget(r, tp)
                                    swing(tp)
                                    task.wait(CFG.SwingDelay)
                                end
                            end
                            local hh = getChar()
                            if hh then setRotate(hh, true) end
                            if not isAlive(target) then
                                kills += 1
                                Stats.kills += 1
                                local ck = CFG.Priority[rank]
                                Stats.color[ck] = (Stats.color[ck] or 0) + 1
                            end
                        end
                    end
                end
            end
            task.wait()
        end
        if not active then setInfo("Turned off. Kills: " .. kills) end
    end

    function Slime.IsActive() return active end
    function Slime.ResetHub() teleported = false; Combat.lastEquip = 0 end

    function Slime.Set(v)
        if v == active then return end
        active = v
        if v then
            Combat.Exclusive("slime")
            runId += 1
            resetWalk()
            Combat.Equip()
            task.spawn(farmLoop, runId)
        else
            runId += 1
            restoreChar()
        end
    end
    onCleanup(function() active = false; pcall(restoreChar) end)
end

-- =====================================================================
-- AUTO SKELETON + AUTO BOSS
-- (island -> HUB -> RUINS -> skeletons in Guardians / boss in RuinsBoss)
-- Reuses Weapon, WalkSpeed, Hit range, Shoot range, Swing delay and Island from Auto Slime.
-- =====================================================================
-- =====================================================================
-- AUTO SKELETON + AUTO BOSS
-- (island -> HUB -> RUINS -> skeletons in Guardians / boss in RuinsBoss)
-- =====================================================================
do
    local CFG = SkelCFG
    local atkRange = Combat.AtkRange
    local active, runId, ready = false, 0, false
    local bossActive, bossRun = false, 0
    local kills, origSpeed = 0, nil
    local lastInfo = ""

    -- ===== setting skeleton =====
    -- CFG.FlyWhileHit diatur lewat toggle "Fly while hit" (default MATI)
    CFG.FlyHeight = 5          -- tinggi melayang (studs), pedang otomatis dibatasi jangkauan
    CFG.StuckTeleport = 4      -- detik nyangkut sebelum teleport ke atas skeleton
    CFG.HpLow = 0.4            -- di bawah 40% HP: mundur
    CFG.HpOk = 0.8             -- lanjut lagi setelah HP 80%
    CFG.RestHeight = 60        -- tinggi mundur (studs)
    CFG.RestMax = 40           -- maksimal detik menunggu HP pulih

    local function setInfo(t)
        if t == lastInfo then return end
        lastInfo = t
        if bossActive then
            Boss.action = t
        elseif Skel.info then
            Skel.info.Text = t
        end
    end

    -- ---------- helpers ----------
    local function getChar()
        local c = LP.Character
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        local hrp = c and c:FindFirstChild("HumanoidRootPart")
        if hum and hrp and hum.Health > 0 then return hum, hrp end
    end
    local function getHRP() return LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") end

    local function teleportTo(pos)
        local hrp = getHRP()
        if not hrp or typeof(pos) ~= "Vector3" then return false end
        pcall(function()
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.CFrame = CFrame.new(pos + Vector3.new(0, 4, 0))
        end)
        return true
    end

    local function waitFor(parent, name, timeout, recursive, cont)
        local t0 = os.clock()
        while os.clock() - t0 < timeout do
            if cont and not cont() then return nil end
            local o = parent and parent:FindFirstChild(name, recursive)
            if o then return o end
            task.wait(0.2)
        end
        return nil
    end

    local function hubModel()
        local h = workspace:FindFirstChild(CFG.HubName)
        return (h and h:IsA("Model")) and h or nil
    end

    local function inHub()
        local hub, hrp = hubModel(), getHRP()
        if not (hub and hrp) then return false end
        local ok, cf, size = pcall(function() local c, s = hub:GetBoundingBox(); return c, s end)
        if not ok or not cf then return false end
        local rel = cf:PointToObjectSpace(hrp.Position)
        local h = size / 2 + Vector3.new(CFG.HubPad, CFG.HubPad, CFG.HubPad)
        return math.abs(rel.X) <= h.X and math.abs(rel.Y) <= h.Y and math.abs(rel.Z) <= h.Z
    end

    -- ---------- Step 1: island -> HUB ----------
    local function enterHub(cont)
        for attempt = 1, CFG.HubAttempts do
            if not cont() then return false end
            local island = Island.get()
            local portal = island and island:FindFirstChild(CFG.PortalName)
            local touch = portal and portal:FindFirstChild(CFG.TouchName, true)
            if not touch then
                setInfo("Portal HUB tidak ditemukan di island.")
                task.wait(1.5)
                return false
            end
            if attempt >= 2 then
                teleportTo(touch.Position)
                task.wait(0.25)
            end
            setInfo(("Menyentuh portal HUB... (percobaan %d/%d)"):format(attempt, CFG.HubAttempts))
            fireTouch(touch)
            if not hubModel() then task.wait(3); return true end
            local w = 0
            while w < CFG.HubWait do
                task.wait(0.5); w += 0.5
                if not cont() then return false end
                if inHub() then task.wait(2); return true end
            end
        end
        setInfo("Teleport ke HUB gagal, mencoba lagi...")
        return false
    end

    -- ---------- skeletons in Guardians folders ----------
    local gCache, gAt = {}, -100
    local function guardianFolders()
        local now = os.clock()
        if now - gAt < CFG.ScanEvery then return gCache end
        gAt = now
        local out = {}
        for _, d in ipairs(workspace:GetDescendants()) do
            if d.Name == "Guardians" and (d:IsA("Folder") or d:IsA("Model")) then out[#out + 1] = d end
        end
        gCache = out
        return out
    end

    local function skelRank(m)
        local n = m.Name:lower()
        for i, key in ipairs(CFG.Priority) do
            if CFG.Enabled[key] and n == key:lower() then return i end
        end
    end

    local function isAlive(m)
        if not m or not m.Parent then return false end
        local h = m:FindFirstChildOfClass("Humanoid")
        return not (h and h.Health <= 0)
    end

    local function posOf(m)
        local ok, cf = pcall(function() return m:GetPivot() end)
        return ok and cf.Position or nil
    end

    local skipped = setmetatable({}, {__mode = "k"})

    -- returns: target, rank
    local function pickTarget(hrp)
        local best, bestRank, bestDist
        for _, g in ipairs(guardianFolders()) do
            if g.Parent then
                for _, m in ipairs(g:GetChildren()) do
                    local rank = skelRank(m)
                    if rank and isAlive(m) and not (skipped[m] and skipped[m] > os.clock()) then
                        local p = posOf(m)
                        if p then
                            local d = (p - hrp.Position).Magnitude
                            if not best or rank < bestRank or (rank == bestRank and d < bestDist) then
                                best, bestRank, bestDist = m, rank, d
                            end
                        end
                    end
                end
            end
        end
        if not best and next(skipped) then table.clear(skipped) end
        return best, bestRank
    end

    local function skeletonNear(hrp)
        for _, g in ipairs(guardianFolders()) do
            if g.Parent then
                for _, m in ipairs(g:GetChildren()) do
                    if skelRank(m) and isAlive(m) then
                        local p = posOf(m)
                        if p and (p - hrp.Position).Magnitude <= CFG.NearRange then return true end
                    end
                end
            end
        end
        return false
    end

    -- ---------- Step 2: HUB -> RUINS -> TouchPart ----------
    local function routeToRuins(cont)
        if not inHub() then
            setInfo("Masuk ke HUB dari island...")
            if not enterHub(cont) then return false end
        end
        if not cont() then return false end

        local t0 = os.clock()
        while os.clock() - t0 < CFG.RuinsDelay do
            if not cont() then return false end
            setInfo(("Sudah di HUB, menunggu portal RUINS load... (%.0fs)"):format(math.max(0, CFG.RuinsDelay - (os.clock() - t0))))
            task.wait(0.25)
        end

        setInfo("Mencari model RUINS di HUB...")
        local hub = waitFor(workspace, CFG.HubName, CFG.WaitTimeout, false, cont)
        if not hub then
            if cont() then setInfo("Model HUB tidak ditemukan di Workspace.") end
            return false
        end
        local ruins = waitFor(hub, CFG.RuinsName, CFG.WaitTimeout, true, cont)
        if not ruins then
            if cont() then setInfo("Model RUINS tidak ditemukan di dalam HUB.") end
            return false
        end
        setInfo("Mencari TouchPart di RUINS...")
        local tp = waitFor(ruins, CFG.TouchName, CFG.WaitTimeout, true, cont)
        if not tp and ruins:IsA("BasePart") then tp = ruins end
        if not tp then
            if cont() then setInfo("TouchPart tidak ditemukan di dalam RUINS.") end
            return false
        end

        task.wait(0.5)
        if not cont() then return false end
        setInfo("Menyentuh portal RUINS...")
        teleportTo(tp.Position)
        task.wait(0.3)
        if not cont() then return false end
        fireTouch(tp)
        task.wait(3)
        gAt = -100
        return cont()
    end

    local function swing(tp)
        local ok, why = Combat.Swing(tp)
        if not ok and why then setInfo(why) end
    end

    -- ---------- movement (hindari air) ----------
    local walk = {wps = nil, i = 1, goal = nil, at = 0, tried = 0, failed = false}
    local lastMove, lastGoal = 0, nil
    local lastLand = nil
    local terrain = workspace.Terrain

    local function resetWalk()
        walk.wps, walk.goal, walk.failed = nil, nil, false
        lastGoal = nil
    end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    pcall(function() rayParams.RespectCanCollide = true end)

    local function pathClear(hrp, goal)
        local ignore = {LP.Character}
        for _, g in ipairs(guardianFolders()) do ignore[#ignore + 1] = g end
        rayParams.FilterDescendantsInstances = ignore
        local dir = goal - hrp.Position
        if dir.Magnitude < 0.5 then return true end
        return workspace:Raycast(hrp.Position, dir, rayParams) == nil
    end

    local function waterAt(p)
        local ok, res = pcall(function()
            local c = p + Vector3.new(0, -3, 0)
            local region = Region3.new(c - Vector3.new(2, 2, 2), c + Vector3.new(2, 2, 2)):ExpandToGrid(4)
            local mats = terrain:ReadVoxels(region, 4)
            for x = 1, #mats do
                for y = 1, #mats[x] do
                    for z = 1, #mats[x][y] do
                        if mats[x][y][z] == Enum.Material.Water then return true end
                    end
                end
            end
            return false
        end)
        return ok and res or false
    end

    local function lineSafe(a, b)
        local d = b - a
        local len = d.Magnitude
        if len < 1 then return true end
        local dir = d.Unit
        local n = math.min(math.ceil(len / 4), 10)
        for i = 1, n do
            if waterAt(a + dir * (len * i / n)) then return false end
        end
        return true
    end

    local function moveTo(hum, pos)
        local now = os.clock()
        if lastGoal and (pos - lastGoal).Magnitude < 1.5 and now - lastMove < 0.5 then return end
        lastMove, lastGoal = now, pos
        hum:MoveTo(pos)
    end

    local function stepTowards(hum, hrp, pos)
        local now = os.clock()

        if hum:GetState() == Enum.HumanoidStateType.Swimming then
            hum.Jump = true
            if lastLand then
                lastGoal = nil
                moveTo(hum, lastLand)
            end
            walk.wps = nil
            return true
        end
        local fm = hum.FloorMaterial
        if fm ~= Enum.Material.Water and fm ~= Enum.Material.Air then
            lastLand = hrp.Position
        end

        if (pos - hrp.Position).Magnitude <= 30 and pathClear(hrp, pos) and lineSafe(hrp.Position, pos) then
            walk.wps, walk.failed = nil, false
            moveTo(hum, pos)
            return true
        end

        local need = not walk.wps or not walk.goal or (pos - walk.goal).Magnitude > 8 or now - walk.at > 3
        if need and now - walk.tried > 0.8 then
            walk.tried = now
            local path = PathfindingService:CreatePath({
                AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true,
                Costs = {Water = math.huge},
            })
            local ok = pcall(function() path:ComputeAsync(hrp.Position, pos) end)
            walk.goal, walk.at = pos, now
            if ok and path.Status == Enum.PathStatus.Success then
                walk.wps, walk.i, walk.failed = path:GetWaypoints(), 2, false
            else
                walk.wps, walk.failed = nil, true
            end
        end

        if walk.wps then
            local wp = walk.wps[walk.i]
            while wp and Vector3.new(wp.Position.X - hrp.Position.X, 0, wp.Position.Z - hrp.Position.Z).Magnitude < 3 do
                walk.i += 1
                wp = walk.wps[walk.i]
            end
            if wp then
                if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
                moveTo(hum, wp.Position)
            end
            return true
        end

        if walk.failed then
            lastGoal = nil
            pcall(function() hum:MoveTo(hrp.Position) end)
        end
        return true
    end

    local function faceTarget(hrp, pos)
        local flat = Vector3.new(pos.X - hrp.Position.X, 0, pos.Z - hrp.Position.Z)
        if flat.Magnitude < 0.1 then return end
        local look = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
        if look.Magnitude < 0.01 or look.Unit:Dot(flat.Unit) < 0.9 then
            hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat)
        end
    end

    local function applySpeed(hum)
        if origSpeed == nil then origSpeed = hum.WalkSpeed end
        if hum.WalkSpeed ~= SlimeCFG.WalkSpeed then hum.WalkSpeed = SlimeCFG.WalkSpeed end
    end
    local function setRotate(hum, v) if hum.AutoRotate ~= v then hum.AutoRotate = v end end

    local function restoreChar()
        local c = LP.Character
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        local hrp = c and c:FindFirstChild("HumanoidRootPart")
        if hum then
            hum.AutoRotate = true
            if origSpeed then hum.WalkSpeed = origSpeed end
            if hrp then pcall(function() hum:MoveTo(hrp.Position) end) end
        end
        origSpeed = nil
    end

    -- respawn -> ulangi rute island -> HUB -> RUINS
    local gen = 0
    local charConn = LP.CharacterAdded:Connect(function()
        gen += 1
        Combat.lastEquip = 0
        origSpeed = nil
        resetWalk()
    end)
    onCleanup(function() charConn:Disconnect() end)

    -- ---------- AUTO BOSS ----------
    local BCFG = BossCFG
    local bossKills = 0

    local function getBoss()
        local f = workspace:FindFirstChild(BCFG.Folder)
        if not f then return nil end
        for _, b in ipairs(f:GetChildren()) do
            if (b:IsA("Model") or b:IsA("BasePart")) and isAlive(b) and posOf(b) then
                return b
            end
        end
        return nil
    end

    local function bossHp(b)
        local h = b:FindFirstChildOfClass("Humanoid")
        if not h then return "" end
        return (" | HP %d/%d"):format(math.floor(h.Health), math.floor(h.MaxHealth))
    end

    local function hoverPos(bp)
        return bp + Vector3.new(BCFG.Offset, BCFG.Height, 0)
    end

    local function fightBoss(cont, boss)
        local hum = getChar()
        if not hum then return end

        setInfo("Boss ditemukan: " .. boss.Name .. "\nTeleport & terbang ke boss...")
        Combat.Equip()

        local sp = posOf(boss)
        if sp then
            local hrp0 = getHRP()
            if hrp0 then
                pcall(function()
                    hrp0.AssemblyLinearVelocity = Vector3.zero
                    hrp0.CFrame = CFrame.new(hoverPos(sp))
                end)
            end
        end
        task.wait(0.3)

        hum.PlatformStand = true
        local fly = RunService.Heartbeat:Connect(function()
            local h, r = getChar()
            local bp = boss.Parent and posOf(boss)
            if not (h and r and bp) then return end
            local hover = hoverPos(bp)
            pcall(function()
                r.AssemblyLinearVelocity = Vector3.zero
                r.AssemblyAngularVelocity = Vector3.zero
                r.CFrame = CFrame.lookAt(hover, Vector3.new(bp.X, hover.Y, bp.Z))
            end)
        end)

        while cont() and boss.Parent and isAlive(boss) and not Link.pause do
            if not getChar() then break end
            if os.clock() - Combat.lastEquip > CFG.EquipEvery then Combat.Equip() end
            local bp = posOf(boss)
            if not bp then break end
            setInfo(("Menyerang BOSS: %s%s\nBoss kills: %d"):format(boss.Name, bossHp(boss), bossKills))
            swing(bp)
            task.wait(SlimeCFG.SwingDelay)
        end

        fly:Disconnect()
        local h = getChar()
        if h then h.PlatformStand = false end
        restoreChar()
        if not (boss.Parent and isAlive(boss)) then
            bossKills += 1
            Stats.kills += 1
        end
    end

    local function bossLoop(id)
        local function cont() return bossActive and bossRun == id end
        local seenGen, routed = gen, false

        while cont() do
            local hum, hrp = getChar()
            if Link.pause then
                setInfo("Paused, Auto Collect is running...")
                task.wait(0.3)
            elseif not hum then
                setInfo("Waiting for character...")
                task.wait(1)
            else
                if gen ~= seenGen then seenGen = gen; routed = false end
                local boss = getBoss()
                if not boss then
                    routed = false
                    setInfo(("Menunggu boss muncul di %s...\nBoss kills: %d"):format(BCFG.Folder, bossKills))
                    task.wait(1)
                else
                    local go = true
                    if BCFG.UseRoute and routed and Island.contains(hrp) then routed = false end
                    if BCFG.UseRoute and not routed then
                        local bp = posOf(boss)
                        local near = bp and not Island.contains(hrp) and not inHub()
                            and (bp - hrp.Position).Magnitude <= CFG.NearRange
                        if near then
                            routed = true
                        elseif routeToRuins(cont) then
                            routed = true
                        else
                            go = false
                            task.wait(2)
                        end
                    end
                    if go and cont() then fightBoss(cont, boss) end
                end
            end
            task.wait()
        end
        Boss.action = "Turned off. Boss kills: " .. bossKills
    end

    function Boss.IsActive() return bossActive end

    function Boss.Set(v)
        if v == bossActive then return end
        bossActive = v
        bossRun += 1
        lastInfo = ""
        Boss.action = ""
        if v then
            Combat.Exclusive("boss")
            Combat.lastSet = nil
            resetWalk()
            task.spawn(bossLoop, bossRun)
        else
            local h = getChar()
            if h then pcall(function() h.PlatformStand = false end) end
            restoreChar()
        end
    end
    onCleanup(function()
        bossActive = false
        local h = getChar()
        if h then pcall(function() h.PlatformStand = false end) end
    end)

    -- ---------- terbang (fly) ----------
    local flyConn, flyTarget = nil, nil

    local function hoverH()
        if Combat.IsScepter() then return math.max(CFG.FlyHeight, 12) end
        return math.min(CFG.FlyHeight, atkRange() - 2)
    end

    -- turunkan karakter ke tanah supaya tidak kena damage jatuh
    local function dropToGround()
        local h, r = getChar()
        if not (h and r) then return end
        pcall(function()
            h.PlatformStand = false
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = {LP.Character}
            local res = workspace:Raycast(r.Position, Vector3.new(0, -300, 0), params)
            if res then r.CFrame = CFrame.new(res.Position + Vector3.new(0, 3, 0)) end
            r.AssemblyLinearVelocity = Vector3.zero
        end)
    end

    local function stopFly()
        local was = flyConn ~= nil
        if flyConn then flyConn:Disconnect(); flyConn = nil end
        flyTarget = nil
        if was then dropToGround() end
    end

    local function startFly(target, hum)
        flyTarget = target
        if flyConn then return end
        flyConn = RunService.Heartbeat:Connect(function()
            local hh, rr = getChar()
            local t = flyTarget
            local bp = t and t.Parent and posOf(t)
            if not (hh and rr and bp) then return end
            local hover = bp + Vector3.new(2, hoverH(), 0)
            pcall(function()
                rr.AssemblyLinearVelocity = Vector3.zero
                rr.AssemblyAngularVelocity = Vector3.zero
                rr.CFrame = CFrame.lookAt(hover, Vector3.new(bp.X, hover.Y, bp.Z))
            end)
        end)
    end

    -- mundur ke atas dan tunggu HP pulih
    local function restUntilHealed(cont)
        local h, r = getChar()
        if not (h and r) then return end
        if flyConn then flyConn:Disconnect(); flyConn = nil end
        flyTarget = nil
        local holdPos = r.Position + Vector3.new(0, CFG.RestHeight, 0)
        local conn = RunService.Heartbeat:Connect(function()
            local hh, rr = getChar()
            if hh and rr then
                pcall(function()
                    rr.AssemblyLinearVelocity = Vector3.zero
                    rr.AssemblyAngularVelocity = Vector3.zero
                    rr.CFrame = CFrame.new(holdPos)
                end)
            end
        end)
        local t0 = os.clock()
        while cont() and not Link.pause and os.clock() - t0 < CFG.RestMax do
            local hh = getChar()
            if not hh then break end
            if hh.Health / hh.MaxHealth >= CFG.HpOk then break end
            setInfo(("HP rendah (%d%%), istirahat di atas..."):format(math.floor(hh.Health / hh.MaxHealth * 100)))
            task.wait(0.5)
        end
        conn:Disconnect()
        dropToGround()
    end

    -- ---------- main skeleton loop ----------
    local function farmLoop(id)
        local function cont() return active and runId == id end
        local seenGen = gen

        while cont() do
            local hum, hrp = getChar()
            if Link.pause then
                stopFly()
                setInfo("Paused, Auto Collect is running...")
                task.wait(0.3)
            elseif not hum then
                stopFly()
                setInfo("Waiting for character...")
                task.wait(1)
            else
                if gen ~= seenGen then seenGen = gen; ready = false; stopFly() end
                if ready and CFG.UseRoute and Island.contains(hrp) then
                    ready = false
                    stopFly()
                    resetWalk()
                    setInfo("Kembali di island, ulangi rute ke RUINS...")
                end

                local skip = false
                if not ready then
                    stopFly()
                    if not CFG.UseRoute then
                        ready = true
                    elseif not Island.contains(hrp) and skeletonNear(hrp) then
                        ready = true
                    elseif routeToRuins(cont) then
                        ready = true
                        local t0 = os.clock()
                        while cont() and os.clock() - t0 < CFG.FindTimeout do
                            local _, h2 = getChar()
                            if h2 and pickTarget(h2) then break end
                            setInfo("Mencari skeleton di RUINS...")
                            task.wait(0.5)
                        end
                        Combat.Equip()
                    else
                        skip = true
                        task.wait(2)
                    end
                end

                if not skip and cont() then
                    hum, hrp = getChar()
                    if hum then
                        applySpeed(hum)
                        if os.clock() - Combat.lastEquip > CFG.EquipEvery then Combat.Equip() end

                        local target, rank = pickTarget(hrp)
                        if not target then
                            stopFly()
                            setRotate(hum, true)
                            setInfo("Menunggu skeleton... Kills: " .. kills)
                            task.wait(1)
                        else
                            resetWalk()
                            local tag = CFG.Priority[rank]:upper()
                            local jumped, lastCheck = false, 0
                            local stuckPos, stuckT = hrp.Position, os.clock()
                            local stopDist = math.max(2.5, atkRange() - 1.5)

                            while cont() and isAlive(target) and not Link.pause do
                                local h, r = getChar()
                                if not h then break end

                                if h.Health / h.MaxHealth < CFG.HpLow then
                                    restUntilHealed(cont)
                                    break
                                end

                                applySpeed(h)
                                if os.clock() - Combat.lastEquip > CFG.EquipEvery then Combat.Equip() end
                                local tp = posOf(target)
                                if not tp then break end

                                if os.clock() - lastCheck > 1 then
                                    lastCheck = os.clock()
                                    if CFG.UseRoute and Island.contains(r) then break end
                                    if not skelRank(target) then break end
                                    local better, brank = pickTarget(r)
                                    if better and better ~= target and brank < rank then break end
                                end

                                local dist = (tp - r.Position).Magnitude
                                local flying = flyConn ~= nil
                                local attacking = dist <= atkRange() + (flying and 3 or 0)

                                if not attacking then
                                    -- jalan di tanah menuju skeleton
                                    if flying then stopFly() end
                                    setRotate(h, true)
                                    local now = os.clock()
                                    if (r.Position - stuckPos).Magnitude > 1.5 then
                                        stuckPos, stuckT, jumped = r.Position, now, false
                                    else
                                        local idle = now - stuckT
                                        if idle > CFG.StuckTeleport * 0.5 and not jumped then
                                            jumped = true
                                            h.Jump = true
                                        end
                                        if idle >= CFG.StuckTeleport then
                                            -- stuck: teleport ke atas skeleton
                                            setInfo(("Stuck menuju %s, teleport ke atasnya"):format(tag))
                                            pcall(function()
                                                r.AssemblyLinearVelocity = Vector3.zero
                                                r.CFrame = CFrame.new(tp + Vector3.new(2, hoverH(), 0))
                                            end)
                                            startFly(target, h)
                                            resetWalk()
                                            stuckPos, stuckT, jumped = r.Position, os.clock(), false
                                        end
                                    end
                                    if not flyConn then
                                        local away = Vector3.new(r.Position.X - tp.X, 0, r.Position.Z - tp.Z)
                                        local goal = tp
                                        if away.Magnitude > 0.1 then goal = tp + away.Unit * stopDist end
                                        setInfo(("Menuju %s (%.0f studs)\nKills: %d"):format(tag, dist, kills))
                                        stepTowards(h, r, goal)
                                    end
                                    task.wait(0.12)
                                else
                                    -- sudah dekat: pukul
                                    stuckPos, stuckT, jumped = r.Position, os.clock(), false
                                    if CFG.FlyWhileHit == true then
                                        startFly(target, h)
                                        setInfo(("Terbang & hit %s\nKills: %d"):format(tag, kills))
                                    else
                                        if flyConn then stopFly() end
                                        setRotate(h, false)
                                        faceTarget(r, tp)
                                        setInfo(("Hit %s (di tanah)\nKills: %d"):format(tag, kills))
                                    end
                                    swing(tp)
                                    task.wait(SlimeCFG.SwingDelay)
                                end
                            end

                            if not isAlive(target) then
                                kills += 1
                                Stats.kills += 1
                            end
                        end
                    end
                end
            end
            task.wait()
        end

        stopFly()
        local hh = getChar()
        if hh then setRotate(hh, true) end
        if not active and Skel.info then Skel.info.Text = "Turned off. Kills: " .. kills end
    end

    function Skel.IsActive() return active end

    function Skel.Set(v)
        if v == active then return end
        active = v
        runId += 1
        if v then
            Combat.Exclusive("skel")
            ready = false
            Combat.lastSet = nil
            resetWalk()
            task.spawn(farmLoop, runId)
        else
            stopFly()
            restoreChar()
        end
    end

    onCleanup(function()
        active = false
        if flyConn then flyConn:Disconnect(); flyConn = nil end
        local h = getChar()
        if h then pcall(function() h.PlatformStand = false end) end
        pcall(restoreChar)
    end)
end
function Combat.IsActive()
    return Slime.IsActive() or Skel.IsActive() or Boss.IsActive()
end

-- live boss spawn status (runs even when Auto Boss is off)
task.spawn(function()
    while Alive do
        local found
        local f = workspace:FindFirstChild(BossCFG.Folder)
        if f then
            for _, b in ipairs(f:GetChildren()) do
                if b:IsA("Model") or b:IsA("BasePart") then
                    local h = b:FindFirstChildOfClass("Humanoid")
                    if not h or h.Health > 0 then found = b; break end
                end
            end
        end
        local txt
        if found then
            local h = found:FindFirstChildOfClass("Humanoid")
            txt = "🟢 BOSS SPAWN: " .. found.Name
            if h then txt ..= (" | HP %d/%d"):format(math.floor(h.Health), math.floor(h.MaxHealth)) end
        elseif not f then
            txt = "⚪ Folder " .. BossCFG.Folder .. " tidak ditemukan"
        else
            txt = "🔴 Boss belum spawn"
        end
        if BossCFG.Realtime then
            local hubM = workspace:FindFirstChild(SkelCFG.HubName)
            local ruinsM = hubM and hubM:FindFirstChild(SkelCFG.RuinsName, true)
            txt ..= "\n📡 Realtime ON · Hub " .. (hubM and "✅" or "❌") .. " · Ruins " .. (ruinsM and "✅" or "❌")
        end
        if Boss.IsActive() and Boss.action and Boss.action ~= "" then
            txt ..= "\n" .. Boss.action
        end
        pcall(function() Boss.info.Text = txt end)
        task.wait(0.5)
    end
end)

-- keep the Hub & Ruins areas streamed in (StreamingEnabled likes to unload faraway areas)
do
    local cache = {}
    local function pivotPos(o)
        local ok, cf = pcall(function() return o:GetPivot() end)
        return ok and cf and cf.Position or nil
    end
    task.spawn(function()
        while Alive do
            if BossCFG.Realtime or Boss.IsActive() then
                -- remember the position of each area while it is visible (anchors are usually always there)
                local hub = workspace:FindFirstChild(SkelCFG.HubName)
                local p1 = hub and pivotPos(hub)
                if p1 then cache.hub = p1 end
                local ra = workspace:FindFirstChild("RuinsArrivalAnchor")
                local p2 = ra and pivotPos(ra)
                if p2 then cache.ruins = p2 end
                local aa = workspace:FindFirstChild("ArrivalAnchor")
                local p3 = aa and pivotPos(aa)
                if p3 then cache.arrival = p3 end
                local bf = workspace:FindFirstChild(BossCFG.Folder)
                if bf then
                    for _, b in ipairs(bf:GetChildren()) do
                        local bp = pivotPos(b)
                        if bp then cache.boss = bp; break end
                    end
                end
                for _, pos in pairs(cache) do
                    if not (Alive and (BossCFG.Realtime or Boss.IsActive())) then break end
                    pcall(function() LP:RequestStreamAroundAsync(pos, 2) end)
                end
            end
            task.wait(BossCFG.StreamEvery)
        end
    end)
end

-- overflow chest
do
    local CFG = ChestCFG
    local active, busy, runId = false, false, 0
    local lastMsg = "Siap."
    local lastInfo = ""
    local function setInfo(t)
        if t == lastInfo then return end
        lastInfo = t
        if Chest.info then Chest.info.Text = t end
    end

    local function readStatus(chest)
        local sign = chest:FindFirstChild("MachineStatusSign")
        if not sign then return nil end
        local parts = {}
        for _, d in ipairs(sign:GetDescendants()) do
            if d:IsA("TextLabel") and d.Text ~= "" then table.insert(parts, d.Text) end
        end
        if #parts == 0 then return nil end
        return table.concat(parts, " | ")
    end

    local function isFull(chest)
        local raw = readStatus(chest)
        if not raw then return nil, "(tidak ada teks)" end
        local txt = raw:gsub("<[^>]+>", ""):lower()
        if txt:find("not full") or txt:find("empty") or txt:find("kosong") or txt:find("belum") then
            return false, raw
        end
        local a, b = txt:match("(%d+)%s*/%s*(%d+)")
        if a and b then return (tonumber(b) > 0 and tonumber(a) >= tonumber(b)), raw end
        if txt:find("100%%") then return true, raw end
        if txt:find("full") or txt:find("penuh") then return true, raw end
        return false, raw
    end

    local function getPrompts()
        local island = Island.get()
        local blocks = island and island:FindFirstChild("Blocks")
        local all, full = {}, {}
        if blocks then
            for _, d in ipairs(blocks:GetDescendants()) do
                if d:IsA("ProximityPrompt") and d.Parent and d.Parent.Name == "OverflowChest" then
                    table.insert(all, d)
                    if isFull(d.Parent) == true then table.insert(full, d) end
                end
            end
        end
        return (CFG.OnlyFull and full or all), island, blocks, #all, #full
    end

    local function visible(o)
        local cur = o
        while cur and cur ~= game do
            if cur:IsA("GuiObject") and not cur.Visible then return false end
            if cur:IsA("ScreenGui") and not cur.Enabled then return false end
            cur = cur.Parent
        end
        return o.AbsoluteSize.X > 0 and o.AbsoluteSize.Y > 0
    end

    local function toButton(o)
        local b = o
        while b and not b:IsA("GuiButton") do b = b.Parent end
        return b
    end

    -- GUI KyHub sendiri dilewati (ada tulisan "Auto Collect" yang tadinya ikut kebaca)
    local function findCollect()
        for _, o in ipairs(LP.PlayerGui:GetDescendants()) do
            if (o:IsA("TextLabel") or o:IsA("TextButton")) and not o:IsDescendantOf(Gui)
                and o.Text:upper():find("COLLECT") and visible(o) then
                return toButton(o) or o
            end
        end
    end

    local EVENTS = {"Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "TouchTap"}

    local function clickGui(obj)
        local fired = 0
        local cur = obj
        for _ = 1, 5 do
            if not cur or not cur:IsA("GuiObject") then break end
            if cur:IsA("GuiButton") then
                for _, ev in ipairs(EVENTS) do
                    if getconnections then
                        local ok, conns = pcall(getconnections, cur[ev])
                        if ok then
                            for _, c in ipairs(conns) do
                                if pcall(function() c:Fire() end) then fired += 1 end
                            end
                        end
                    end
                end
                if fired == 0 and firesignal then
                    for _, ev in ipairs(EVENTS) do
                        if pcall(firesignal, cur[ev]) then fired += 1 end
                    end
                end
            end
            cur = cur.Parent
        end
        return fired
    end

    -- panel chest = anak langsung ScreenGui yang berisi tombol COLLECT
    local function getPanel(collectBtn)
        local sg = collectBtn:FindFirstAncestorOfClass("ScreenGui")
        if not sg then return nil end
        local panel = collectBtn
        while panel.Parent and panel.Parent ~= sg do panel = panel.Parent end
        return panel
    end

    local function isX(text)
        local t = text:lower():gsub("%s", "")
        return t == "x" or t == "×" or t == "✕" or t == "✖"
    end

    local function isCloseBtn(btn)
        local n = btn.Name:lower()
        if n:find("close") or n:find("exit") or n == "x" then return true end
        if btn:IsA("TextButton") and isX(btn.Text) then return true end
        for _, d in ipairs(btn:GetDescendants()) do
            if d:IsA("TextLabel") and isX(d.Text) then return true end
        end
        return false
    end

    local function closeChestGui(panel)
        if not panel or panel == Gui or panel:IsDescendantOf(Gui) then return end
        for _, d in ipairs(panel:GetDescendants()) do
            if d:IsA("GuiButton") and visible(d) and isCloseBtn(d) then clickGui(d) end
        end
        task.wait(0.3)
        if findCollect() and panel.Parent and panel:IsA("GuiObject") then
            pcall(function() panel.Visible = false end)
        end
    end

    local function openPrompt(p)
        local part = p.Parent
        local cf = part:IsA("Model") and part:GetPivot() or (part:IsA("BasePart") and part.CFrame)
        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if CFG.Teleport and hrp and cf then
            hrp.CFrame = cf + Vector3.new(0, 4, 0)
            task.wait(0.25)
        end
        p.HoldDuration = 0
        p.RequiresLineOfSight = false
        p.MaxActivationDistance = math.max(p.MaxActivationDistance, 30)
        if fireproximityprompt then
            fireproximityprompt(p)
        else
            p:InputHoldBegin(); task.wait(0.1); p:InputHoldEnd()
        end
    end

    -- di home = tidak sedang berada di area lobby (workspace.Hub)
    local function atHome()
        local lobby = workspace:FindFirstChild(CFG.HomeModel)
        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not (lobby and hrp and lobby:IsA("Model")) then return true end
        local cf, size = lobby:GetBoundingBox()
        local rel = cf:PointToObjectSpace(hrp.Position)
        local h = size / 2 + Vector3.new(10, 10, 10)
        local inside = math.abs(rel.X) <= h.X and math.abs(rel.Y) <= h.Y and math.abs(rel.Z) <= h.Z
        return not inside
    end

    -- nama part dan semua model induknya (sampai model Hub), huruf kecil
    local function pathNames(part, root)
        local names = {}
        local cur = part
        while cur and cur ~= root do
            names[#names + 1] = cur.Name:lower()
            cur = cur.Parent
        end
        return names
    end

    local function homeKeywords()
        local kws = {}
        for w in tostring(CFG.HomeKeyword or ""):gmatch("[^,]+") do
            w = trim(w):lower()
            if w ~= "" then kws[#kws + 1] = w end
        end
        return kws
    end

    -- semua kandidat portal di model Hub: part bernama TouchPart atau part yang punya TouchInterest
    local function listPortals()
        local m = workspace:FindFirstChild(CFG.HomeModel)
        local list = {}
        if not m then return list, m end
        local touchName = CFG.HomeTouchName:lower()
        local kws = homeKeywords()
        for _, d in ipairs(m:GetDescendants()) do
            if d:IsA("BasePart") and (d.Name:lower() == touchName or d:FindFirstChildOfClass("TouchTransmitter")) then
                local names = pathNames(d, m)
                local hit = false
                for _, n in ipairs(names) do
                    for _, kw in ipairs(kws) do
                        if n:find(kw, 1, true) then hit = true end
                    end
                end
                list[#list + 1] = {part = d, depth = #names, hit = hit}
            end
        end
        return list, m
    end

    -- cari portal HOME saja. Kalau tidak yakin, jangan sentuh apa pun (lebih baik gagal daripada salah portal)
    local function findHomePortal()
        local list, m = listPortals()
        if not m then return nil, ("Model %s tidak ditemukan."):format(CFG.HomeModel) end
        local matched = {}
        for _, c in ipairs(list) do
            if c.hit then matched[#matched + 1] = c end
        end
        if #matched > 0 then
            table.sort(matched, function(a, b) return a.depth < b.depth end)
            return matched[1].part
        end
        if #list == 1 then return list[1].part end
        if #list == 0 then
            return nil, ("Tidak ada portal di model %s."):format(CFG.HomeModel)
        end
        return nil, ("Portal '%s' tidak ketemu di %s (ada %d portal). Klik DEBUG."):format(CFG.HomeKeyword, CFG.HomeModel, #list)
    end

    -- balik ke home lewat portal home di model Hub. return true, atau false + alasan
    local function goHome()
        if atHome() then return true end
        if not firetouchinterest then return false, "Executor tidak support firetouchinterest." end
        local part, why = findHomePortal()
        if not part then return false, why end

        for attempt = 1, 3 do
            local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if hrp and part.Parent then
                -- percobaan 1: sentuh dari jauh. Percobaan 2-3: pindah tepat ke portal home itu (di HP firetouchinterest jarak jauh sering diabaikan)
                if attempt >= 2 then
                    pcall(function() hrp.CFrame = part.CFrame end)
                    task.wait(0.2)
                end
                pcall(function()
                    firetouchinterest(hrp, part, 0)
                    task.wait(0.15)
                    firetouchinterest(LP.Character:FindFirstChild("HumanoidRootPart") or hrp, part, 1)
                end)
            end
            local t = 0
            while t < CFG.HomeWait do
                task.wait(0.5); t += 0.5
                if atHome() then task.wait(CFG.AfterHomeDelay); return true end
            end
        end
        return false, ("Portal home tidak merespons: %s"):format(part:GetFullName())
    end

    -- 0.30 = 30 detik, 1.30 = 90 detik, 2 = 120 detik
    local function intervalSec(n)
        local m = math.floor(n)
        local s = math.floor((n - m) * 100 + 0.5)
        return math.max(5, m * 60 + s)
    end

    local function runOnce()
        if busy then return end
        busy = true
        local slimeOn = Combat.IsActive and Combat.IsActive()
        local paused = false
        local function finish(msg)
            if msg then lastMsg = msg; setInfo(msg) end
            if paused then
                if Slime.ResetHub then Slime.ResetHub() end
                Link.pause = false
            end
            busy = false
        end

        local prompts, _, _, total = getPrompts()
        if total > 0 and #prompts == 0 then
            return finish(("Belum ada chest FULL (0/%d)."):format(total))
        end

        -- jeda Auto Slime hanya kalau memang nyala (tunggu dia selesai urusan portal HUB dulu)
        if slimeOn then
            Link.pause = true; paused = true
            local w = 0
            while Link.hubBusy and w < 15 do task.wait(0.25); w += 0.25 end
            task.wait(0.5)
        end

        -- balik home kalau sedang di Hub, tidak peduli Auto Slime nyala atau tidak
        if not atHome() then
            setInfo(slimeOn and "Auto Slime dijeda, balik ke home..." or "Balik ke home...")
            local okHome, whyHome = goHome()
            if not okHome then
                return finish("Gagal balik ke home: " .. tostring(whyHome or "?"))
            end
            Island.cache, Island.at = nil, -100   -- baru balik home, deteksi island ulang
            prompts, _, _, total = getPrompts()
        end

        if total == 0 then return finish("Chest tidak ditemukan. Klik DEBUG.") end
        if #prompts == 0 then return finish(("Belum ada chest FULL (0/%d)."):format(total)) end

        local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        local home = (not paused) and hrp and hrp.CFrame   -- kalau slime ikut jalan, baliknya lewat portal
        local got, failedClick = 0, 0
        for i, p in ipairs(prompts) do
            if not active then break end
            setInfo(("Chest FULL %d/%d (berhasil: %d)"):format(i, #prompts, got))
            if p.Parent and (not CFG.OnlyFull or isFull(p.Parent) == true) then
                pcall(openPrompt, p)
                local btn, t = nil, 0
                while t < CFG.OpenWait do
                    btn = findCollect()
                    if btn then break end
                    task.wait(0.1); t += 0.1
                end
                if btn then
                    local panel = getPanel(btn)
                    if clickGui(btn) > 0 then got += 1 else failedClick += 1 end
                    task.wait(CFG.CollectWait)
                    pcall(closeChestGui, panel)
                end
            end
            task.wait(CFG.BetweenChest)
        end
        if CFG.Teleport and home then
            local h = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if h then h.CFrame = home end
        end
        local msg = ("Terakhir: %d/%d chest di-collect."):format(got, #prompts)
        if failedClick > 0 then
            msg = msg .. (" Klik gagal %dx (executor tidak support getconnections/firesignal)."):format(failedClick)
        end
        finish(msg)
    end

    function Chest.Set(v)
        if not v then Link.pause = false end
        if v == active then return end
        active = v
        if v then
            runId += 1
            local id = runId
            task.spawn(function()
                while active and runId == id do
                    -- kalau runOnce error, status busy/pause harus dibersihkan supaya tidak macet selamanya
                    local ok, err = pcall(runOnce)
                    if not ok then
                        busy = false
                        Link.pause = false
                        if Slime.ResetHub then Slime.ResetHub() end
                        lastMsg = "Error: " .. tostring(err)
                        setInfo(lastMsg)
                    end
                    local remain = intervalSec(CFG.IntervalMin)
                    while active and runId == id and remain > 0 do
                        setInfo(("%s\nCek berikutnya: %02d:%02d"):format(lastMsg, remain // 60, remain % 60))
                        task.wait(1)
                        remain -= 1
                    end
                end
                if not active then setInfo("Dimatikan.") end
            end)
        end
    end
    onCleanup(function() active = false; Link.pause = false end)

    function Chest.Debug()
        Island.cache, Island.at = nil, -100
        local _, island, blocks, total, fullCount = getPrompts()
        print("=== DEBUG CHEST ===")
        print("Island terpilih:", island and island:GetFullName() or "TIDAK ADA",
            "| override:", Island.override ~= "" and Island.override or "(otomatis)")
        for i, c in ipairs(Island.list()) do
            print(("  island %d. %s%s"):format(i, c:GetFullName(), (c == island) and "  <== DIPILIH" or ""))
        end
        print("Total chest:", total, "| FULL:", fullCount)
        print("getconnections:", getconnections ~= nil, "| firesignal:", firesignal ~= nil,
            "| fireproximityprompt:", fireproximityprompt ~= nil, "| firetouchinterest:", firetouchinterest ~= nil)

        local hm = workspace:FindFirstChild(CFG.HomeModel)
        print("Model Hub:", hm and hm:GetFullName() or "TIDAK ADA", "| atHome:", tostring(atHome()))
        print("Kata kunci portal home:", CFG.HomeKeyword)
        local list = listPortals()
        local chosen, why = findHomePortal()
        print(("-- Portal di model %s: %d"):format(CFG.HomeModel, #list))
        for i, c in ipairs(list) do
            print(("  %d. %s | cocok kata kunci: %s%s"):format(
                i, c.part:GetFullName(), tostring(c.hit), (c.part == chosen) and "  <== DIPILIH" or ""))
        end
        if not chosen then print("  Tidak ada yang dipilih:", why) end

        local n = 0
        if blocks then
            for _, c in ipairs(blocks:GetChildren()) do
                if c.Name == "OverflowChest" then
                    n += 1
                    local f, raw = isFull(c)
                    print(n, "teks =", raw, "=> full:", tostring(f))
                    if n >= 15 then break end
                end
            end
        end
        local btn = findCollect()
        if btn then
            local panel = getPanel(btn)
            print("-- Tombol di panel chest:", panel and panel:GetFullName())
            if panel then
                for _, d in ipairs(panel:GetDescendants()) do
                    if d:IsA("GuiButton") then
                        print("  ", d:GetFullName(), "| closeBtn:", tostring(isCloseBtn(d)))
                    end
                end
            end
        else
            print("(GUI chest lagi tertutup, buka satu chest manual lalu klik DEBUG lagi buat lihat tombol close)")
        end
        setInfo(("Island: %s | Total: %d | FULL: %d | Portal Hub: %d. Lihat console."):format(
            island and island.Name or "-", total, fullCount, #list))
    end
end

-- auto harvest (pintar: hanya tanaman siap + jalan pakai pathfinding)
do
    local C = HarvestCFG
    local autoFarm = false
    local blacklist = setmetatable({}, {__mode = "k"})
    Harvest.Skip = setmetatable({}, {__mode = "k"})
    local target, pending, pendingAt, pendingPos = nil, false, 0, nil
    local lastScan, lastPos, lastPosTime, targetSince = 0, nil, 0, 0
    local idleStopped, origSpeed, lastInfo = false, nil, ""
    local UNRIPE_SKIP = 25
    local STUCK_TP = 3   -- detik nyangkut sebelum teleport (lompat dulu di tengah)

    local function setInfo(t)
        if t == lastInfo then return end
        lastInfo = t
        if Harvest.info then Harvest.info.Text = t end
    end
    local function refs()
        local c = LP.Character
        return c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("HumanoidRootPart")
    end
    local remoteCache
    local function harvestRemote()
        if remoteCache and remoteCache.Parent then return remoteCache end
        local r = RS:FindFirstChild("Remotes")
        remoteCache = r and r:FindFirstChild("RequestHarvest")
        return remoteCache
    end

    -- ===== jalan pintar (pathfinding + hindari tabrakan) =====
    local walk = {wps = nil, i = 1, goal = nil, at = 0, tried = 0}
    local lastMove, lastGoal = 0, nil
    local function resetWalk() walk.wps, walk.goal, lastGoal = nil, nil, nil end

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    pcall(function() rayParams.RespectCanCollide = true end)

    local function pathClear(root, goal)
        rayParams.FilterDescendantsInstances = {LP.Character}
        local dir = goal - root.Position
        if dir.Magnitude < 0.5 then return true end
        return workspace:Raycast(root.Position, dir, rayParams) == nil
    end

    local function moveTo(hum, pos)
        local now = os.clock()
        if lastGoal and (pos - lastGoal).Magnitude < 1.5 and now - lastMove < 0.5 then return end
        lastMove, lastGoal = now, pos
        hum:MoveTo(pos)
    end

    local function stepTowards(hum, root, pos)
        local now = os.clock()
        if pathClear(root, pos) then
            walk.wps = nil
            moveTo(hum, pos)
            return
        end
        local need = not walk.wps or not walk.goal or (pos - walk.goal).Magnitude > 6 or now - walk.at > 3
        if need and now - walk.tried > 0.8 then
            walk.tried = now
            local path = PathfindingService:CreatePath({AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = true})
            local ok = pcall(function() path:ComputeAsync(root.Position, pos) end)
            walk.goal, walk.at = pos, now
            if ok and path.Status == Enum.PathStatus.Success then
                walk.wps, walk.i = path:GetWaypoints(), 2
            else
                walk.wps = nil
            end
        end
        if walk.wps then
            local wp = walk.wps[walk.i]
            while wp and Vector3.new(wp.Position.X - root.Position.X, 0, wp.Position.Z - root.Position.Z).Magnitude < 3 do
                walk.i += 1
                wp = walk.wps[walk.i]
            end
            if wp then
                if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
                moveTo(hum, wp.Position)
                return
            end
        end
        moveTo(hum, pos)
    end

    -- ===== baca status tanaman persis seperti game (GrowTime.read) =====
    local GrowTime
    pcall(function() GrowTime = require(RS.Shared.GrowTime) end)
    local carrier = setmetatable({}, {__mode = "k"})

    local function readOn(inst)
        if not (GrowTime and inst and inst.Parent) or inst == workspace then return nil end
        local ok, left, flag, id = pcall(GrowTime.read, inst, workspace:GetServerTimeNow())
        if ok and type(left) == "number" and id then return left, flag end
    end
    local function eval(left, flag)
        if flag == 0 then return "water" end
        if left <= 0 then return "ripe" end
        return "growing"
    end
    local function cropState(crop)
        local c = carrier[crop]
        if c and c.Parent then
            local l, f = readOn(c)
            if l then return eval(l, f) end
        end
        for _, inst in ipairs({crop, crop:FindFirstChild("HB"), crop.Parent}) do
            local l, f = readOn(inst)
            if l then carrier[crop] = inst; return eval(l, f) end
        end
        local attrName = GrowTime and GrowTime.LeftAttribute
        if attrName then
            for _, d in ipairs(crop:GetDescendants()) do
                if d:GetAttribute(attrName) ~= nil then
                    local l, f = readOn(d)
                    if l then carrier[crop] = d; return eval(l, f) end
                end
            end
        end
    end
    local function skipReason(crop)
        local st = cropState(crop)
        if st == "water" and (C.SkipNeedsWater or C.OnlyRipe) then return "water" end
        if st == "growing" and C.OnlyRipe then return "growing" end
        return nil
    end

    -- ===== daftar tanaman =====
    local function cropKind(name)
        local n = tostring(name):lower()
        for _, k in ipairs(C.Crops) do
            if n:find(k, 1, true) then return k end
        end
    end
    local crops, cropConns, scanned = {}, {}, false
    local function addCrop(o)
        local k = cropKind(o.Name)
        if k and not o:FindFirstChildOfClass("Humanoid") then crops[o] = k end
    end
    local function startTracking()
        if scanned then return end
        scanned = true
        cropConns[1] = workspace.DescendantAdded:Connect(addCrop)
        cropConns[2] = workspace.DescendantRemoving:Connect(function(o) crops[o] = nil end)
        local n = 0
        for _, o in ipairs(workspace:GetDescendants()) do
            if not scanned then return end
            addCrop(o)
            n += 1
            if n % 3000 == 0 then task.wait() end
        end
    end
    local function stopTracking()
        scanned = false
        for _, c in ipairs(cropConns) do pcall(function() c:Disconnect() end) end
        cropConns, crops = {}, {}
    end

    local function findNearest(root)
        local now = tick()
        local best, bd
        for crop, kind in pairs(crops) do
            if not crop.Parent then
                crops[crop] = nil
            elseif C.Enabled[kind] then
                local hb = crop:FindFirstChild("HB")
                if hb and hb:IsA("BasePart")
                    and not (blacklist[hb] and blacklist[hb] > now)
                    and not (Harvest.Skip[hb] and Harvest.Skip[hb] > now)
                    and not (Harvest.IsFresh and Harvest.IsFresh(hb))
                    and not skipReason(crop) then
                    local d = (root.Position - hb.Position).Magnitude
                    if not bd or d < bd then best, bd = hb, d end
                end
            end
        end
        return best
    end

    function Harvest.Set(v)
        if v == autoFarm then return end
        autoFarm, target, pending = v, nil, false
        resetWalk()
        if v then
            Combat.Exclusive("harvest")
            task.spawn(startTracking)
            setInfo("Berjalan...")
        else
            setInfo("Idle")
            local h, r = refs()
            if h then
                if origSpeed then h.WalkSpeed = origSpeed end
                if r then pcall(function() h:MoveTo(r.Position) end) end
            end
            origSpeed = nil
            stopTracking()
        end
    end

    local conn = RunService.Heartbeat:Connect(function()
        if not autoFarm then return end
        local hum, root = refs()
        if not (hum and root) then return end
        if origSpeed == nil then origSpeed = hum.WalkSpeed end
        if hum.WalkSpeed ~= C.WalkSpeed then hum.WalkSpeed = C.WalkSpeed end
        local now = tick()

        -- sudah kirim panen: tanaman hilang = sukses, masih ada = belum bisa dipanen
        if pending then
            if (not target) or not target:IsDescendantOf(workspace) then
                if Harvest.QueuePlant and pendingPos then Harvest.QueuePlant(pendingPos) end
                pending, target = false, nil
            elseif now - pendingAt >= (C.GoneWait or 2) then
                Harvest.Skip[target] = now + UNRIPE_SKIP
                pending, target = false, nil
            end
            return
        end

        if (not target) or not target:IsDescendantOf(workspace) then
            target = nil
            if now - lastScan >= 0.3 then
                lastScan = now
                target = findNearest(root)
                lastPos, targetSince = nil, now
                resetWalk()
            end
            if not target then
                setInfo("Tidak ada tanaman siap, diam...")
                if not idleStopped then
                    idleStopped = true
                    pcall(function() hum:MoveTo(root.Position) end)
                end
                return
            end
            idleStopped = false
        end

        -- cek ulang: status bisa berubah di tengah jalan
        if target.Parent and skipReason(target.Parent) then
            Harvest.Skip[target] = now + 3
            target = nil
            return
        end

        local reach = math.min(C.Radius, 12)
        local dist = (root.Position - target.Position).Magnitude

        if dist <= reach then
            -- sudah dekat: berhenti, lalu panen
            pcall(function() hum:MoveTo(root.Position) end)
            lastGoal = nil
            setInfo("Panen tanaman siap...")
            pcall(function()
                local r = harvestRemote()
                if r then r:FireServer(target) end
            end)
            pending, pendingAt, pendingPos = true, now, target.Position
        else
            setInfo("Jalan ke tanaman siap...")
            local manual = UIS:IsKeyDown(Enum.KeyCode.W) or UIS:IsKeyDown(Enum.KeyCode.A)
                or UIS:IsKeyDown(Enum.KeyCode.S) or UIS:IsKeyDown(Enum.KeyCode.D)
            if not manual then stepTowards(hum, root, target.Position) end

            if now - targetSince > ((Harvest.PCFG and Harvest.PCFG.StuckSkip) or 8) then
                blacklist[target] = now + 30
                target = nil
                resetWalk()
                return
            end
            -- nyangkut: lompat dulu, baru teleport kalau masih nyangkut
            if lastPos == nil or (root.Position - lastPos).Magnitude > 1 then
                lastPos, lastPosTime = root.Position, now
            else
                local idle = now - lastPosTime
                if idle >= 1 then hum.Jump = true end
                if C.TeleportFallback and idle >= STUCK_TP then
                    local dir = root.Position - target.Position
                    dir = dir.Magnitude > 0 and dir.Unit or Vector3.new(1, 0, 0)
                    root.CFrame = CFrame.new(target.Position + dir * (reach - 3) + Vector3.new(0, 3, 0))
                    lastPos = nil
                    resetWalk()
                end
            end
        end
    end)

    function Harvest.Debug()
        print("[KyHub] ===== DEBUG CROPS =====")
        print("GrowTime module:", GrowTime and "ada" or "TIDAK ADA")
        local n, cnt = 0, {ripe = 0, water = 0, growing = 0, unknown = 0}
        for crop in pairs(crops) do
            local st = cropState(crop)
            cnt[st or "unknown"] += 1
            n += 1
            if n <= 8 then
                print(crop:GetFullName(), "| state:", tostring(st),
                    "| carrier:", carrier[crop] and carrier[crop]:GetFullName() or "-")
            end
        end
        print(("Total: %d | siap: %d | butuh air: %d | tumbuh: %d | tidak terbaca: %d"):format(
            n, cnt.ripe, cnt.water, cnt.growing, cnt.unknown))
    end

    onCleanup(function()
        autoFarm = false
        conn:Disconnect()
        stopTracking()
    end)
end
-- =====================================================================
-- AUTO PLANT (engine Auto Plant v8)
-- =====================================================================
-- =====================================================================
-- PLANT AFTER HARVEST (engine Auto Plant v8)
-- =====================================================================
do
    local PC = Harvest.PCFG
    local CropConfig
    pcall(function() CropConfig = require(RS.Shared.Config.CropConfig) end)

    local cellSize = 3
    pcall(function()
        local G = require(RS.Shared.Grid)
        if typeof(G.CellSize) == "number" then cellSize = G.CellSize end
    end)

    PC.Block = (CropConfig and CropConfig.RequiredGround) or "FarmSoil"
    -- Seed selalu mengikuti dropdown crop / seed di Auto Harvest
    local cfg = setmetatable({}, {
        __index = function(_, k)
            if k == "Seed" then return HarvestCFG.Seed end
            return PC[k]
        end,
        __newindex = function(_, k, v) PC[k] = v end,
    })

    local function active()
        return PC.AfterHarvest == true and Tg.harvest ~= nil and Tg.harvest.Get()
    end

    local function remote(name)
        local r = RS:FindFirstChild("Remotes")
        return r and r:FindFirstChild(name)
    end

    local origin = nil
    local placeSlots, layout, planted = {}, {}, {}
    local heldSeed, fails, total = nil, 0, 0
    local queue = {}
    local lastInfo = ""
    local function setStatus(t)
        if t == lastInfo then return end
        lastInfo = t
        if Harvest.pinfo and Harvest.pinfo.Parent then Harvest.pinfo.Text = t end
    end

    -- ===== simpan / muat =====
    local SAVE = "AutoPlant_" .. LP.UserId .. ".json"
    local saved = {slots = {}}
    local function saveState()
        if not (writefile and origin) then return end
        pcall(function()
            writefile(SAVE, HttpService:JSONEncode({
                origin = {origin.X, origin.Y, origin.Z},
                slots = placeSlots,
            }))
        end)
    end
    pcall(function()
        if readfile and isfile and isfile(SAVE) then
            local d = HttpService:JSONDecode(readfile(SAVE))
            if type(d) == "table" then
                if type(d.origin) == "table" and #d.origin == 3 then
                    saved.origin = Vector3.new(d.origin[1], d.origin[2], d.origin[3])
                end
                if type(d.slots) == "table" then saved.slots = d.slots end
            end
        end
    end)

    -- ===== util =====
    local function getChar()
        local c = LP.Character
        local h = c and c:FindFirstChildOfClass("Humanoid")
        local r = c and c:FindFirstChild("HumanoidRootPart")
        return c, h, r
    end

    local function posOf(o)
        if o:IsA("BasePart") then return o.Position, o.Size end
        if o:IsA("Model") then
            local ok, cf, sz = pcall(function() return o:GetBoundingBox() end)
            if ok then return cf.Position, sz end
        end
    end

    local function hitPart(o)
        local hb = o:FindFirstChild("HB")
        if hb and hb:IsA("BasePart") then return hb end
        if o:IsA("BasePart") then return o end
        if o:IsA("Model") then return o.PrimaryPart or o:FindFirstChildWhichIsA("BasePart", true) end
    end

    local function esc(s) return (tostring(s):gsub("%p", "%%%0")) end

    local function cropBase()
        local id
        if CropConfig and type(CropConfig.cropForSeed) == "function" then
            local ok, c = pcall(CropConfig.cropForSeed, cfg.Seed)
            if ok and type(c) == "table" then id = c.id end
        end
        return (id or tostring(cfg.Seed):gsub("[Ss]eeds?$", "")):lower()
    end

    local function isCropName(name)
        local b = cropBase()
        if b == "" then return false end
        return tostring(name):lower():match("^" .. esc(b) .. "[_%s]*%d*$") ~= nil
    end

    -- ===== pelacak tanah + model ber-HB =====
    local tr = {hb = {}, soil = {}, conns = {}, gen = 0}

    local function classify(o)
        if o.Name == "HB" and o:IsA("BasePart") and o.Parent then tr.hb[o.Parent] = true end
        if o.Name == tr.blockName and (o:IsA("BasePart") or o:IsA("Model")) then tr.soil[o] = true end
    end

    local function stopTrack()
        tr.gen += 1
        for _, c in ipairs(tr.conns) do pcall(function() c:Disconnect() end) end
        tr.conns, tr.hb, tr.soil, tr.ref, tr.blockName = {}, {}, {}, nil, nil
    end

    local function retrack()
        stopTrack()
        local gen = tr.gen
        tr.blockName = cfg.Block
        tr.conns[1] = workspace.DescendantAdded:Connect(classify)
        tr.conns[2] = workspace.DescendantRemoving:Connect(function(o)
            tr.hb[o] = nil
            tr.soil[o] = nil
            if o.Name == "HB" and o.Parent then tr.hb[o.Parent] = nil end
        end)
        task.spawn(function()
            local n = 0
            for _, o in ipairs(workspace:GetDescendants()) do
                if tr.gen ~= gen then return end
                classify(o)
                n += 1
                if n % 3000 == 0 then task.wait() end
            end
        end)
    end

    local function ensureTracking()
        if tr.blockName ~= cfg.Block then retrack() end
    end

    local function soilList()
        local list = {}
        for s in pairs(tr.soil) do
            if s.Parent then
                local p, sz = posOf(s)
                if p then list[#list + 1] = {o = s, p = p, size = sz} end
            else
                tr.soil[s] = nil
            end
        end
        if not tr.ref and list[1] then tr.ref = list[1].p end
        return list
    end

    local function lkey(p)
        if not tr.ref then soilList() end
        local r = tr.ref
        if not r then return "?" end
        return math.round((p.X - r.X) / cellSize) .. "," .. math.round((p.Z - r.Z) / cellSize)
    end

    local function occupiedSet()
        local set = {}
        soilList()
        for m in pairs(tr.hb) do
            if m.Parent and not tr.soil[m] and m.Name ~= cfg.Block then
                local part = hitPart(m)
                if part then set[lkey(part.Position)] = true end
            end
        end
        return set
    end

    -- blok tanah tepat di bawah sebuah posisi
    local function soilUnder(q)
        local best, bv
        for _, e in ipairs(soilList()) do
            local hd = math.sqrt((e.p.X - q.X) ^ 2 + (e.p.Z - q.Z) ^ 2)
            if hd < cellSize * 0.6 and e.p.Y <= q.Y + 1.5 then
                local vd = q.Y - e.p.Y
                if not bv or vd < bv then best, bv = e, vd end
            end
        end
        return best
    end

    local function cellFor(p, O)
        return {
            x = math.round((p.X - O.X) / cellSize),
            y = math.round((p.Y - O.Y) / cellSize) + cfg.YOff,
            z = math.round((p.Z - O.Z) / cellSize),
        }
    end

    -- ===== pegang bibit =====
    local function hasTool()
        local c = getChar()
        if not c then return false end
        for _, v in ipairs(c:GetChildren()) do
            if v:IsA("Tool") then return true end
        end
        return false
    end

    local function holdingSeed()
        local c = getChar()
        if not c then return false end
        local key = cropBase()
        for _, v in ipairs(c:GetChildren()) do
            if v:IsA("Tool") and v.Name:lower():find(key, 1, true) then return true end
        end
        return false
    end

    local function ensureHold()
        local HoldRemote = remote("RequestHoldBlock")
        if not HoldRemote then return end
        local _, hum = getChar()
        if not hum then return end
        local other = hasTool() and not holdingSeed()
        if heldSeed == cfg.Seed and not other then return end
        if other then
            for _ = 1, 3 do
                pcall(function() hum:UnequipTools() end)
                task.wait(0.2)
                if not hasTool() then break end
            end
        end
        pcall(function() HoldRemote:FireServer(cfg.Seed) end)
        heldSeed = cfg.Seed
        task.wait(0.3)
    end

    local charConn = LP.CharacterAdded:Connect(function() heldSeed = nil end)

    -- ===== deteksi tanaman baru =====
    local function plantMatch(d)
        local m = d
        if d.Name == "HB" and d:IsA("BasePart") and d.Parent then m = d.Parent end
        if m == workspace or not m.Parent then return nil end
        if LP.Character and m:IsDescendantOf(LP.Character) then return nil end
        if isCropName(m.Name) then return m end
    end

    local function attempt(cell, slotNo, timeout)
        local PlaceRemote = remote("RequestPlace")
        if not PlaceRemote then return nil end
        local got
        local conn = workspace.DescendantAdded:Connect(function(d)
            if not got then got = plantMatch(d) end
        end)
        pcall(function()
            PlaceRemote:FireServer({x = cell.x, y = cell.y, z = cell.z}, cfg.Seed, 0, Vector3.new(0, 1, 0), false, nil, false, slotNo)
        end)
        local t0 = os.clock()
        while not got and os.clock() - t0 < (timeout or 0.4) do task.wait(0.03) end
        conn:Disconnect()
        return got
    end

    local function watchPlant(timeout)
        local got
        local conn = workspace.DescendantAdded:Connect(function(d)
            if not got then got = plantMatch(d) end
        end)
        local t0 = os.clock()
        while not got and os.clock() - t0 < timeout do task.wait(0.03) end
        conn:Disconnect()
        return got
    end

    local function validNew(m, occ, root)
        task.wait(0.1)
        local part = hitPart(m)
        local q = part and part.Position or posOf(m)
        if not q then return nil end
        if root and (q - root.Position).Magnitude > 80 then return nil end
        if occ[lkey(q)] then return nil end
        return q
    end

    local function finalize(cell, q, seedName, slotNo)
        local e = soilUnder(q)
        if not e then return false end
        origin = e.p - Vector3.new(cell.x * cellSize, (cell.y - cfg.YOff) * cellSize, cell.z * cellSize)
        if type(slotNo) == "number" then placeSlots[seedName] = slotNo end
        planted[lkey(q)] = os.clock()
        saveState()
        print(("[AutoPlant] KALIBRASI OK | origin = %s | slot %s = %s"):format(tostring(origin), tostring(seedName), tostring(slotNo)))
        setStatus(("Calibrated. Origin %.1f, %.1f, %.1f | slot %s"):format(origin.X, origin.Y, origin.Z, tostring(slotNo)))
        return true
    end

    -- ===== hook: tangkap layout backpack + tanam manual (opsional) =====
    local hooked = false
    if hookmetamethod and getnamecallmethod then
        pcall(function()
            local nc = newcclosure or function(f) return f end
            local isOwn = checkcaller or function() return false end
            local oldNC
            oldNC = hookmetamethod(game, "__namecall", nc(function(self, ...)
                if Alive and not isOwn() and getnamecallmethod() == "FireServer" and typeof(self) == "Instance" then
                    local n = self.Name
                    if n == "RequestSetBackpackLayout" then
                        local t = ...
                        if type(t) == "table" then
                            local copy = {}
                            for k, v in pairs(t) do copy[k] = v end
                            layout = copy
                        end
                    elseif n == "RequestPlace" then
                        local pos, seed, _, _, _, _, _, slot = ...
                        if type(seed) == "string" and type(slot) == "number" then
                            placeSlots[seed] = slot
                        end
                        if type(pos) == "table" and type(pos.x) == "number" and type(seed) == "string" then
                            local cell = {x = pos.x, y = pos.y, z = pos.z}
                            task.spawn(function()
                                local occ = occupiedSet()
                                local got = watchPlant(2)
                                if got then
                                    local _, _, root = getChar()
                                    local q = validNew(got, occ, root)
                                    if q then finalize(cell, q, seed, slot) end
                                end
                            end)
                        end
                    end
                end
                return oldNC(self, ...)
            end))
            hooked = true
        end)
    end

    -- ===== kandidat slot =====
    local function guiSlots()
        local out, seen = {}, {}
        local pg = LP:FindFirstChild("PlayerGui")
        if not pg then return out end
        local base = cropBase()
        local function push(n)
            if type(n) == "number" and n >= 0 and n <= 300 and not seen[n] then
                seen[n] = true
                out[#out + 1] = n
            end
        end
        local cnt = 0
        for _, d in ipairs(pg:GetDescendants()) do
            cnt += 1
            if cnt % 2000 == 0 then task.wait() end
            if not d:IsDescendantOf(Gui) then
                local hit = (d.Name == cfg.Seed)
                if not hit and (d:IsA("TextLabel") or d:IsA("TextButton")) then
                    local t = d.Text:lower():gsub("%s", "")
                    if t:find(base .. "seed", 1, true) then hit = true end
                end
                if not hit and d:IsA("StringValue") and d.Value == cfg.Seed then hit = true end
                if not hit then
                    local ok, at = pcall(function() return d:GetAttributes() end)
                    if ok then
                        for _, v in pairs(at) do
                            if v == cfg.Seed then hit = true end
                        end
                    end
                end
                if hit then
                    local a = d
                    for _ = 1, 6 do
                        if not a or a == pg then break end
                        push(tonumber(tostring(a.Name):match("(%d+)$")))
                        local ok, at = pcall(function() return a:GetAttributes() end)
                        if ok then push(at.Slot); push(at.slot); push(at.Index); push(at.index) end
                        if a:IsA("GuiObject") and a.LayoutOrder ~= 0 then push(a.LayoutOrder) end
                        a = a.Parent
                    end
                end
            end
        end
        return out
    end

    local function quickSlots()
        local out, seen = {}, {}
        local function push(n)
            if type(n) == "number" and not seen[n] then
                seen[n] = true
                out[#out + 1] = n
            end
        end
        push(placeSlots[cfg.Seed])
        push(saved.slots[cfg.Seed])
        push(layout[cfg.Seed])
        push(cfg.Slot)
        for _, n in ipairs(guiSlots()) do push(n) end
        push(77)
        push(63)
        return out, seen
    end

    -- ===== kandidat origin =====
    local function originCandidates(sp)
        local list, seen = {}, {}
        local function add(v, why)
            if typeof(v) == "CFrame" then v = v.Position end
            if typeof(v) ~= "Vector3" then return end
            if #list >= 12 then return end
            local sv = sp - Vector3.new(
                math.round((sp.X - v.X) / cellSize) * cellSize,
                math.round((sp.Y - v.Y) / cellSize) * cellSize,
                math.round((sp.Z - v.Z) / cellSize) * cellSize)
            local key = ("%.1f,%.1f,%.1f"):format(sv.X, sv.Y, sv.Z)
            if seen[key] then return end
            seen[key] = true
            list[#list + 1] = {v = sv, why = why, exact = (sv - v).Magnitude < 0.06}
        end

        if saved.origin then add(saved.origin, "saved") end
        add(Vector3.new(2121, 201, 2121), "old origin")

        local function scanInst(inst, tag)
            local ok, attrs = pcall(function() return inst:GetAttributes() end)
            if ok then
                for k, v in pairs(attrs) do
                    if typeof(v) == "Vector3" or typeof(v) == "CFrame" then add(v, tag .. "@" .. tostring(k)) end
                end
            end
            for _, c in ipairs(inst:GetChildren()) do
                if c:IsA("Vector3Value") or c:IsA("CFrameValue") then add(c.Value, tag .. "/" .. c.Name) end
            end
        end

        scanInst(LP, "player")
        local a = nil
        for _, e in ipairs(soilList()) do
            a = e.o
            break
        end
        while a and a ~= workspace and a ~= game do
            scanInst(a, a.Name)
            if a:IsA("Model") then
                pcall(function()
                    add(a:GetPivot(), a.Name .. ":pivot")
                    local cf, sz = a:GetBoundingBox()
                    add(cf, a.Name .. ":bbox")
                    add(cf.Position - sz / 2, a.Name .. ":bbox-min")
                end)
            end
            for _, nm in ipairs({"Origin", "Center", "Anchor", "IslandOrigin", "Spawn"}) do
                local f = a:FindFirstChild(nm)
                if f then
                    if f:IsA("BasePart") then add(f.Position, a.Name .. "." .. nm) end
                    scanInst(f, a.Name .. "." .. nm)
                end
            end
            a = a.Parent
        end
        pcall(function()
            for _, nm in ipairs({LP.Name, tostring(LP.UserId)}) do
                local f = RS:FindFirstChild(nm, true)
                if f then scanInst(f, "RS." .. nm) end
            end
        end)

        table.sort(list, function(x, y)
            if x.exact ~= y.exact then return x.exact end
            return false
        end)
        return list
    end

    -- ===== kalibrasi otomatis di petak kosong `e` (petak bekas panen) =====
    local function solve(e)
        local _, _, root = getChar()
        if not root then return false end
        ensureHold()

        local occ = occupiedSet()
        local cands = origin and {{v = origin, why = "current origin"}} or originCandidates(e.p)
        local quick, quickSet = quickSlots()
        local known = placeSlots[cfg.Seed]
        local slotsQuick = known and {known} or quick

        print(("[AutoPlant] calibration: %d origin candidates, %d quick slots"):format(#cands, #slotsQuick))

        local function try(O, s)
            if not active() then return "stop" end
            local cell = cellFor(e.p, O.v)
            local got = attempt(cell, s, 0.35)
            if got then
                local q = validNew(got, occ, root)
                if q and finalize(cell, q, cfg.Seed, s) then return true end
            end
        end

        for i, O in ipairs(cands) do
            for _, s in ipairs(slotsQuick) do
                setStatus(("Calibrating: origin %d/%d (%s), slot %d"):format(i, #cands, O.why, s))
                local r = try(O, s)
                if r == "stop" then return false end
                if r then return true end
            end
        end

        if not known then
            local full = {}
            for s = 0, 120 do
                if not quickSet[s] then full[#full + 1] = s end
            end
            for i = 1, math.min(2, #cands) do
                for n, s in ipairs(full) do
                    if n % 8 == 0 then
                        setStatus(("Sweeping slots... origin %d, slot %d/120"):format(i, s))
                    end
                    local r = try(cands[i], s)
                    if r == "stop" then return false end
                    if r then return true end
                end
            end
        end

        setStatus("Calibration failed. Make sure the seed is in your inventory. Planting 1 seed manually also calibrates.")
        print("[AutoPlant] Calibration failed. Click DEBUG plant and check the console (F9).")
        return false
    end

    -- ===== antrean tanam: dipanggil Auto Harvest setiap kali selesai memanen =====
        local bad = {}
    local lastScan = 0

    -- true kalau petak ini baru kita tanam: harvest tidak perlu mengejarnya
    function Harvest.IsFresh(hb)
        if not (tr.ref and active()) then return false end
        local t = planted[lkey(hb.Position)]
        return t ~= nil and os.clock() - t < (cfg.GrowSkip or 30)
    end

    -- dipanggil Auto Harvest setiap selesai memanen
    function Harvest.QueuePlant(src)
        if not active() then return end
        local isPart = typeof(src) == "Instance"
        local pos = isPart and src.Position or src
        if typeof(pos) ~= "Vector3" or not tr.blockName then return end
        if not tr.ref then soilList() end
        if not tr.ref then return end
        local k = lkey(pos)
        if queue[k] then return end
        if planted[k] and os.clock() - planted[k] < 30 then return end
        queue[k] = {pos = pos, key = k, t = os.clock(), tries = 0, hb = isPart and src or nil}
    end

    -- tanam juga petak kosong di sekitar karakter (ke mana pun dia pergi)
    local function scanNear(root)
        if not cfg.PlantNear then return end
        local now = os.clock()
        if now - lastScan < 0.5 then return end
        lastScan = now
        local radius = math.min(tonumber(cfg.NearRadius) or 20, 30)
        local occ = occupiedSet()
        local n = 0
        for _, e in ipairs(soilList()) do
            if n >= 40 then break end
            if (e.p - root.Position).Magnitude <= radius then
                local k = lkey(e.p)
                if not occ[k] and not queue[k]
                    and not (planted[k] and now - planted[k] < 30)
                    and not (bad[k] and bad[k] > now) then
                    queue[k] = {pos = e.p, key = k, t = now, tries = 0, scan = true}
                    n += 1
                end
            end
        end
    end

    local function step()
        ensureTracking()
        local _, hum, root = getChar()
        if not (hum and root) or hum.Health <= 0 then task.wait(0.5) return end
        scanNear(root)
        if next(queue) == nil then
            setStatus(("Waiting for harvest... replanted: %d"):format(total))
            task.wait(0.05)
            return
        end

        local occ = occupiedSet()
        local now = os.clock()
        local ready = {}
        for k, it in pairs(queue) do
            if occ[k] then
                if it.sent then
                    queue[k] = nil        -- tanaman baru sudah muncul
                    fails = 0
                    total += 1
                elseif now - it.t > (cfg.CropGoneWait or 2) then
                    queue[k] = nil        -- tanaman lama tidak hilang (belum matang / tumbuh lagi)
                    if it.hb and Harvest.Skip then Harvest.Skip[it.hb] = tick() + (cfg.UnripeSkip or 25) end
                end
            else
                it.free = it.free or now
                if not it.sent then
                    if now - it.free > 60 then queue[k] = nil else ready[#ready + 1] = it end
                elseif now - it.sent >= (cfg.RetryGap or 0.8) then
                    if it.tries >= (cfg.Retries or 3) then
                        queue[k] = nil
                        if it.scan then bad[k] = now + 120 else fails += 1 end
                    else
                        ready[#ready + 1] = it
                    end
                end
            end
        end

        if fails >= 5 then
            fails = 0
            origin = nil
            placeSlots[cfg.Seed] = nil
            setStatus("Failed 5x in a row, recalibrating automatically...")
        end

        if #ready == 0 then task.wait(0.03) return end

        -- belum terkalibrasi: kalibrasi di petak kosong pertama
        if not (origin and placeSlots[cfg.Seed]) then
            local e = soilUnder(ready[1].pos)
            if not e then queue[ready[1].key] = nil return end
            setStatus("Calibrating on the first empty plot...")
            if not solve(e) then task.wait(8) end
            return
        end

        ensureHold()
        local PlaceRemote = remote("RequestPlace")
        if not PlaceRemote then setStatus("RequestPlace remote not found") task.wait(1) return end
        local slotNow = placeSlots[cfg.Seed]
        local sent = 0
        for _, it in ipairs(ready) do
            local e = soilUnder(it.pos)
            if not e then
                queue[it.key] = nil
            else
                local cell = cellFor(e.p, origin)
                it.sent, it.tries = os.clock(), it.tries + 1
                planted[it.key] = it.sent
                pcall(function()
                    PlaceRemote:FireServer({x = cell.x, y = cell.y, z = cell.z}, cfg.Seed, 0, Vector3.new(0, 1, 0), false, nil, false, slotNow)
                end)
                sent += 1
            end
        end
        setStatus(("Planting %d plot(s) | replanted: %d"):format(sent, total))
        task.wait(0.03)
    end

    task.spawn(function()
        while Alive do
            if active() then
                local ok, err = pcall(step)
                if not ok then
                    warn("[KyHub] Plant after harvest error:", err)
                    task.wait(1)
                end
            else
                if tr.blockName then stopTrack() end
                if next(queue) then table.clear(queue) end
                task.wait(0.3)
            end
        end
    end)

    -- ===== API untuk UI =====
    function Harvest.PlantReset()
        origin = nil
        planted = {}
        placeSlots[cfg.Seed] = nil
        saved = {slots = {}}
        table.clear(queue)
        setStatus("Calibration reset. It will be found again on the next harvest.")
        notify("Plant calibration reset.")
    end

    function Harvest.PlantDebug()
        ensureTracking()
        task.wait(1)
        local list = soilList()
        local nh = 0
        for _ in pairs(tr.hb) do nh += 1 end
        print("[AutoPlant] ===== DEBUG =====")
        print("[AutoPlant] block:", cfg.Block, "| count:", #list, "| HB models:", nh, "| cellSize:", cellSize)
        print("[AutoPlant] seed:", cfg.Seed, "| crop base name:", cropBase(),
            "| valid in CropConfig:", tostring(CropConfig and CropConfig.isSeed and CropConfig.isSeed(cfg.Seed)))
        print("[AutoPlant] origin:", origin, "| proven slot:", placeSlots[cfg.Seed], "| hooked:", hooked)
        print("[AutoPlant] slots from backpack GUI:", table.concat(guiSlots(), ","))
        local qn = 0
        for _ in pairs(queue) do qn += 1 end
        print("[AutoPlant] queue:", qn, "| replanted:", total, "| active:", tostring(active()))
        local _, _, root = getChar()
        if root and list[1] then
            local best
            for _, e in ipairs(list) do
                if not best or (e.p - root.Position).Magnitude < (best.p - root.Position).Magnitude then best = e end
            end
            print("[AutoPlant] nearest block:", best.o:GetFullName(), best.p)
            for k, v in pairs(best.o:GetAttributes()) do print("[AutoPlant] attr:", k, v) end
            for i, c in ipairs(originCandidates(best.p)) do
                print(("[AutoPlant] origin candidate %d: %s (%s)%s"):format(i, tostring(c.v), c.why, c.exact and "" or " [approx]"))
            end
        end
        if not active() then stopTrack() end
        setStatus("Debug printed (F9)")
    end

    onCleanup(function()
        stopTrack()
        table.clear(queue)
        charConn:Disconnect()
    end)
end

-- =====================================================================
-- AUTO FARM (Auto Tree + Auto Mine) - KyFarm v8.8 engine
-- Pine route: Island -> HUB -> Hub -> RUINS -> TouchPart -> farm pine
-- =====================================================================
do
    local CFG = FarmCFG
    local mode, runId = nil, 0
    local lastInfo = ""
    local function setInfo(t)
        if t == lastInfo then return end
        lastInfo = t
        if Farm.info and Farm.info.Parent then Farm.info.Text = t end
    end

    -- ---------- basic helpers ----------
    local function getChar()
        local c = LP.Character
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        local hrp = c and c:FindFirstChild("HumanoidRootPart")
        if hum and hrp and hum.Health > 0 then return hum, hrp end
    end
    local function getHRP() return LP.Character and LP.Character:FindFirstChild("HumanoidRootPart") end
    local function getRemote(name)
        local r = RS:FindFirstChild("Remotes")
        return r and r:FindFirstChild(name)
    end

    local origWalk = 16
    do
        local c = LP.Character
        local h = c and c:FindFirstChildOfClass("Humanoid")
        if h and h.WalkSpeed > 0 then origWalk = h.WalkSpeed end
    end
    local function restoreSpeed()
        local hum = getChar()
        if hum then hum.WalkSpeed = origWalk end
    end

    local function flatDist(a, b)
        if typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" then return math.huge end
        return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
    end

    local function groundAt(pos, hrp)
        if typeof(pos) ~= "Vector3" or typeof(hrp.Position) ~= "Vector3" then return pos end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {LP.Character}
        local origin = Vector3.new(pos.X, hrp.Position.Y + 8, pos.Z)
        local r = workspace:Raycast(origin, Vector3.new(0, -80, 0), params)
        if r then return r.Position + Vector3.new(0, 1, 0) end
        return pos
    end

    -- pathfinding walk; returns true when within stopDist of pos
    local function walkTo(pos, stopDist, timeout, cont)
        if typeof(pos) ~= "Vector3" then return false end
        local t0 = os.clock()
        local lastCheck, lastPos = os.clock(), nil
        while os.clock() - t0 < timeout do
            if cont and not cont() then return false end
            local hum, hrp = getChar()
            if not hum then return false end
            hum.WalkSpeed = CFG.WalkSpeed
            if flatDist(hrp.Position, pos) <= stopDist then return true end

            local goal = groundAt(pos, hrp)
            local path = PathfindingService:CreatePath({
                AgentRadius = CFG.PathRadius, AgentHeight = CFG.PathHeight, AgentCanJump = true,
                AgentCanClimb = false, WaypointSpacing = CFG.WaypointSpacing,
            })
            local okC = pcall(function() path:ComputeAsync(hrp.Position, goal) end)

            if okC and path.Status == Enum.PathStatus.Success then
                local wps = path:GetWaypoints()
                local blocked = false
                local conn = path.Blocked:Connect(function() blocked = true end)
                local arrived, interrupted = false, false
                for i = 2, #wps do
                    local wp = wps[i]
                    if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
                    hum:MoveTo(wp.Position)
                    local wt, reached = os.clock(), false
                    while os.clock() - wt < 2.5 do
                        if cont and not cont() then interrupted = true; break end
                        local h2, r2 = getChar()
                        if not h2 then interrupted = true; break end
                        h2.WalkSpeed = CFG.WalkSpeed
                        if flatDist(r2.Position, pos) <= stopDist then arrived = true; break end
                        if flatDist(r2.Position, wp.Position) < 3.5 then reached = true; break end
                        if blocked then break end
                        task.wait(0.05)
                    end
                    if arrived or interrupted or blocked or not reached then break end
                    if os.clock() - t0 >= timeout then break end
                end
                conn:Disconnect()
                if interrupted then return false end
                if arrived then return true end
            else
                hum:MoveTo(pos)
                if os.clock() - lastCheck > 1.2 then
                    if lastPos and (hrp.Position - lastPos).Magnitude < 1.5 then hum.Jump = true end
                    lastPos, lastCheck = hrp.Position, os.clock()
                end
                task.wait(0.15)
            end
        end
        return false
    end

    -- ---------- teleport helpers ----------
    local function teleportTo(pos)
        local hrp = getHRP()
        if not hrp or typeof(pos) ~= "Vector3" then return false end
        pcall(function()
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            hrp.CFrame = CFrame.new(pos + CFG.TeleportOffset)
        end)
        return true
    end

    -- wait for a child to appear (useful with StreamingEnabled)
    local function waitFor(parent, name, timeout, recursive, cont)
        local t0 = os.clock()
        while os.clock() - t0 < timeout do
            if cont and not cont() then return nil end
            local o = parent and parent:FindFirstChild(name, recursive)
            if o then return o end
            task.wait(0.2)
        end
        return nil
    end

    local function touchFire(part, cont)
        local hrp = getHRP()
        if not (hrp and part) then return false end
        if firetouchinterest then
            local ok = pcall(function()
                firetouchinterest(hrp, part, 0)
                task.wait(0.15)
                firetouchinterest(getHRP() or hrp, part, 1)
            end)
            if ok then return true end
        end
        return walkTo(part.Position, 2, 25, cont)
    end

    -- ---------- swing animation ----------
    local SWING_IDS = {"rbxassetid://86861921756773", "rbxassetid://89881700832616"}
    local tracks, animatorRef, aIdx = {}, nil, 0
    local function playSwingAnim()
        local c = LP.Character
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        local animator = hum and hum:FindFirstChildOfClass("Animator")
        if not animator then return end
        if animatorRef ~= animator then
            animatorRef, tracks = animator, {}
            for i, id in ipairs(SWING_IDS) do
                local a = Instance.new("Animation")
                a.AnimationId = id
                local t = animator:LoadAnimation(a)
                t.Priority = Enum.AnimationPriority.Action
                tracks[i] = t
            end
        end
        aIdx = aIdx % #tracks + 1
        for i, t in ipairs(tracks) do
            if i ~= aIdx and t.IsPlaying then t:Stop(0.08) end
        end
        tracks[aIdx]:Play(0.08)
    end

    local function swing(arg)
        local r = getRemote("RequestSwing")
        if not r then setInfo("RequestSwing remote not found!"); return end
        if CFG.SwingAnim then pcall(playSwingAnim) end
        pcall(function() r:FireServer(arg) end)
        Stats.swings += 1
    end

    -- ---------- equip (re-equips if another tool gets selected) ----------
    local learned, lastEq = {}, {}
    local function equippedTool()
        local c = LP.Character
        return c and c:FindFirstChildOfClass("Tool")
    end
    local function ensureEquip(kind)  -- kind = "Axe" / "Pickaxe"
        local now = os.clock()
        local want = learned[kind]           -- learned tool name; false = tool not readable
        local t = equippedTool()
        if want and t and t.Name == want then return end
        local gap = 1.5
        if want then gap = 0.6 elseif want == false then gap = 15 end
        if lastEq[kind] and now - lastEq[kind] < gap then return end
        lastEq[kind] = now
        local r = getRemote("RequestEquipSlot")
        if not r then return end
        pcall(function() r:FireServer(kind) end)
        if want == nil then
            task.wait(0.5)
            local t2 = equippedTool()
            learned[kind] = t2 and t2.Name or false
        end
    end

    -- ---------- target search ----------
    local function getResourceRoot()
        local hub = workspace:FindFirstChild(CFG.HubName)
        if hub then
            local field = hub:FindFirstChild(CFG.ResourceName)
            if field then return field end
        end
        return workspace:FindFirstChild(CFG.ResourceName)
    end

    local cache = {}
    local function cached(key, fn)
        local c = cache[key]
        if c and os.clock() - c.at < 4 then return c.v end
        local v = fn()
        cache[key] = {at = os.clock(), v = v}
        return v
    end
    local function radiusOf(part)
        local s = part.Size
        return math.clamp(math.max(s.X, s.Z) / 2, 0, 14)
    end
    local function treeMatch(name, kind)
        local n = name:lower()
        if kind == "pine" then return n:find("pine", 1, true) ~= nil end
        return n:find("tree", 1, true) ~= nil and n:find("pine", 1, true) == nil
    end

    -- every folder/model named ResourceField (Hub, RUINS, ...)
    local function getResourceRoots()
        return cached("roots", function()
            local roots, seen = {}, {}
            local primary = getResourceRoot()
            if primary then roots[#roots + 1] = primary; seen[primary] = true end
            for _, d in ipairs(workspace:GetDescendants()) do
                if d.Name == CFG.ResourceName and not seen[d] and (d:IsA("Folder") or d:IsA("Model")) then
                    seen[d] = true
                    roots[#roots + 1] = d
                end
            end
            return roots
        end)
    end

    local function treeNodes(kind)
        return cached("tree:" .. kind, function()
            local out = {}
            for _, root in ipairs(getResourceRoots()) do
                for _, d in ipairs(root:GetDescendants()) do
                    if d:IsA("BasePart") and d.Name == "Reach" then
                        local c = d.Parent
                        if c and treeMatch(c.Name, kind) then
                            out[#out + 1] = {key = d, pos = d.Position, arg = d, name = c.Name, radius = radiusOf(d)}
                        end
                    end
                end
            end
            return out
        end)
    end

    -- ---------- mine map ----------
    local ALIAS = {stone = {"stone"}, ironore = {"ironore", "iron"}, coal = {"coal"}, sand = {"sand"}, clay = {"clay"}}
    local function norm(s) return (s:lower():gsub("[%s_%-]", "")) end
    local function nameIs(res, name)
        local n = norm(name)
        for _, a in ipairs(ALIAS[res]) do
            if n:find(a, 1, true) then return true end
        end
        return false
    end
    local function mineRoot()
        if CFG.MineRoot ~= "" then
            local o = workspace:FindFirstChild(CFG.MineRoot, true)
            if o then return o end
        end
        return getResourceRoot() or workspace:FindFirstChild(CFG.HubName)
    end
    local function mineMap()
        return cached("mine:" .. CFG.MineRoot, function()
            local map = {}
            for _, r in ipairs(CFG.MineList) do map[r] = {} end
            local root = mineRoot()
            if not root then return map end
            local stopAt = root.Parent
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("BasePart") and d.Name ~= "Reach" then
                    local found
                    local a = d
                    while a and a ~= stopAt and not found do
                        for _, r in ipairs(CFG.MineList) do
                            if nameIs(r, a.Name) then found = r; break end
                        end
                        a = a.Parent
                    end
                    if found then
                        local list = map[found]
                        list[#list + 1] = {key = d, pos = d.Position, arg = d, name = d.Name, res = found, radius = radiusOf(d)}
                    end
                end
            end
            return map
        end)
    end
    local function mineOrder()
        local out, seen = {}, {}
        local function add(r)
            if r and CFG.MineEnabled[r] and not seen[r] then seen[r] = true; out[#out + 1] = r end
        end
        add(CFG.MinePriority)
        for _, r in ipairs(CFG.MineList) do add(r) end
        return out
    end

    local function isAlive(node)
        local p = node.key
        if not p or not p.Parent then return false end
        if not p:IsDescendantOf(workspace) then return false end
        if node.res then
            local ok, tr = pcall(function() return p.Transparency end)
            if ok and tr >= 0.95 then return false end
        end
        return true
    end
    local function whyDead(node)
        local p = node.key
        if not p or not p.Parent then return "Parent = nil (part removed)" end
        if not p:IsDescendantOf(workspace) then return "part left the workspace" end
        local ok, tr = pcall(function() return p.Transparency end)
        if ok and tr >= 0.95 then return "part became transparent (" .. tostring(tr) .. ")" end
        return "still exists"
    end
    local function findReplacement(node)
        table.clear(cache)
        local map = mineMap()
        local best, bd
        local near = (node.radius or 0) + CFG.RockNear
        for _, n in ipairs(map[node.res] or {}) do
            if n.key ~= node.key and isAlive(n) then
                local d = (n.pos - node.pos).Magnitude
                if d <= near and (not bd or d < bd) then best, bd = n, d end
            end
        end
        return best
    end
    local function nearest(list, hrp, skipped)
        local best, bd
        local now = os.clock()
        for _, n in ipairs(list) do
            if isAlive(n) and not (skipped[n.key] and skipped[n.key] > now) then
                local d = (n.pos - hrp.Position).Magnitude
                if not bd or d < bd then best, bd = n, d end
            end
        end
        return best
    end
    -- returns: node, message, manual
    local function pick(kind, hrp, skipped)
        if kind == "tree" then
            local list = treeNodes(CFG.TreeKind)
            if #list == 0 then return nil, "No " .. CFG.TreeKind .. " trees found." end
            local n = nearest(list, hrp, skipped)
            if not n and next(skipped) then
                table.clear(skipped)
                n = nearest(list, hrp, skipped)
            end
            return n, "All trees are being skipped, waiting..."
        end
        local ord = mineOrder()
        if #ord == 0 then return nil, "Select the materials to mine first" end
        local map = mineMap()
        for _, r in ipairs(ord) do
            local n = nearest(map[r] or {}, hrp, skipped)
            if n then return n end
        end
        if next(skipped) then table.clear(skipped) end
        return nil, nil, true
    end

    -- ---------- island / hub detection ----------
    local function hubModel()
        local h = workspace:FindFirstChild(CFG.HubName)
        return (h and h:IsA("Model")) and h or nil
    end

    local function inHub()
        local hub, hrp = hubModel(), getHRP()
        if not (hub and hrp) then return false end
        local ok, cf, size = pcall(function() local c, s = hub:GetBoundingBox(); return c, s end)
        if not ok or not cf then return false end
        local rel = cf:PointToObjectSpace(hrp.Position)
        local h = size / 2 + Vector3.new(CFG.HubPad, CFG.HubPad, CFG.HubPad)
        return math.abs(rel.X) <= h.X and math.abs(rel.Y) <= h.Y and math.abs(rel.Z) <= h.Z
    end

    -- is the character on the island area?
    local function onIsland()
        local hrp = getHRP()
        return hrp ~= nil and Island.contains(hrp)
    end

    -- ---------- step 1: island -> HUB (touch the HUB portal on the island) ----------
    local function enterHub(id)
        local function cont() return runId == id and not Link.pause end
        for attempt = 1, 3 do
            if not cont() then return false end
            local island = Island.get()
            local portal = island and island:FindFirstChild(CFG.IslandPortalName)
            local touch = portal and portal:FindFirstChild(CFG.TouchPartName, true)
            if not touch then
                setInfo("HUB portal not found on the island.")
                task.wait(1.5)
                return false
            end
            if attempt >= 2 then
                teleportTo(touch.Position) -- 2nd attempt on: teleport straight to the portal
                task.wait(0.25)
            end
            setInfo(("Touching the HUB portal... (attempt %d/3)"):format(attempt))
            touchFire(touch, cont)
            if not hubModel() then task.wait(3); return true end -- Hub not streamed yet, assume success
            local w = 0
            while w < CFG.HubWait do
                task.wait(0.5); w += 0.5
                if not cont() then return false end
                if inHub() then task.wait(2); return true end
            end
        end
        setInfo("Teleport to the Hub did not work, retrying...")
        return false
    end

    -- ---------- step 2: in the Hub -> RUINS -> TouchPart ----------
    local function touchRuinsPortal(id)
        local function cont() return runId == id and not Link.pause end

        -- 1. enter the Hub first (through the island portal) if not inside yet
        if not inHub() then
            setInfo("Entering the Hub from the island...")
            if not enterHub(id) then return false end
        end
        if not cont() then return false end

        -- 1b. wait in the Hub so the RUINS portal can load before teleporting
        local t0 = os.clock()
        while os.clock() - t0 < CFG.RuinsLoadDelay do
            if not cont() then return false end
            setInfo(("In the Hub, waiting for the RUINS portal to load... (%.0fs)"):format(math.max(0, CFG.RuinsLoadDelay - (os.clock() - t0))))
            task.wait(0.25)
        end

        -- 2. find the Hub model
        setInfo("Looking for the Hub model...")
        local hub = waitFor(workspace, CFG.HubName, CFG.WaitTimeout, false, cont)
        if not hub then
            if cont() then setInfo("Hub model not found in Workspace.") end
            return false
        end

        -- 3. find RUINS inside the Hub
        setInfo("Looking for RUINS in the Hub...")
        local ruins = waitFor(hub, CFG.RuinsName, CFG.WaitTimeout, true, cont)
        if not ruins then
            if cont() then setInfo("RUINS model not found inside the Hub.") end
            return false
        end

        -- 4. find TouchPart inside RUINS
        setInfo("Looking for TouchPart in RUINS...")
        local touchPart = waitFor(ruins, CFG.TouchPartName, CFG.WaitTimeout, true, cont)
        if not touchPart and ruins:IsA("BasePart") then touchPart = ruins end
        if not touchPart then
            if cont() then setInfo("TouchPart not found inside RUINS.") end
            return false
        end

        -- 5. teleport to TouchPart + touch it
        task.wait(0.5) -- let the part finish streaming in
        if not cont() then return false end
        setInfo("Touching the RUINS portal...")
        teleportTo(touchPart.Position)
        task.wait(0.3)
        if not cont() then return false end
        touchFire(touchPart, cont)

        task.wait(3) -- wait for the map change
        table.clear(cache) -- so pine trees on the new map are read
        return cont()
    end

    -- is there a live pine close to the character (not just somewhere on the map)?
    local PINE_NEAR = 300
    local function pineNear()
        local hrp = getHRP()
        if not hrp then return false end
        for _, n in ipairs(treeNodes("pine")) do
            if isAlive(n) and (n.pos - hrp.Position).Magnitude <= PINE_NEAR then return true end
        end
        return false
    end

    -- wait for pines to appear around RUINS after the teleport
    local function waitForPines(id)
        local t0 = os.clock()
        while runId == id and mode == "tree" and os.clock() - t0 < 15 do
            table.clear(cache)
            if pineNear() then return true end
            setInfo("Looking for pine in ResourceField...")
            task.wait(0.5)
        end
        return false
    end

    -- ---------- RUINS -> Hub: find the return portal inside the Hub model, then its TouchPart ----------
    -- the "Hub" model sits INSIDE a RUINS model: RUINS > ... > Hub > ... > TouchPart.
    -- Walking up from the TouchPart we must meet the Hub-named model FIRST and RUINS after it.
    -- (the entry portal Workspace.Hub > RUINS > TouchPart meets RUINS first, so it is ignored)
    local function isReturnTouch(d)
        local want = (CFG.ReturnPortalName or ""):lower()
        local sawHub = false
        local a = d.Parent
        while a and a ~= workspace do
            local n = a.Name:lower()
            if not sawHub and (want == "" or n:find(want, 1, true)) and n ~= CFG.RuinsName:lower() then
                sawHub = true
            elseif sawHub and n == CFG.RuinsName:lower() then
                return true
            elseif want == "" and not sawHub and n == CFG.RuinsName:lower() then
                return true
            end
            a = a.Parent
        end
        return false
    end

    local function findReturnTouch()
        local hrp = getHRP()
        local best, bd
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("BasePart") and d.Name == CFG.TouchPartName and isReturnTouch(d) then
                local dist = hrp and (d.Position - hrp.Position).Magnitude or 0
                if not bd or dist < bd then best, bd = d, dist end
            end
        end
        return best, bd
    end

    -- are we in the RUINS area? (touched the RUINS portal, pines close by, or the return portal is close)
    local RUINS_NEAR = 250
    local function inRuins()
        if inRuinsArea then return true end
        if pineNear() then return true end
        local t, d = findReturnTouch()
        return t ~= nil and d ~= nil and d <= RUINS_NEAR
    end

    local function returnViaPortal(id)
        local function cont() return runId == id and not Link.pause end
        setInfo("Looking for the Hub model inside RUINS...")
        local touch
        local t0 = os.clock()
        while os.clock() - t0 < CFG.WaitTimeout do
            if not cont() then return false end
            touch = findReturnTouch()
            if touch then break end
            task.wait(0.3)
        end
        if not touch then
            if cont() then setInfo("Hub model / TouchPart not found inside RUINS (click DEBUG trees to list portals).") end
            return false
        end

        local hrp0 = getHRP()
        local startPos = hrp0 and hrp0.Position
        task.wait(0.5) -- let the part finish streaming in
        if not cont() then return false end
        setInfo("Touching the return portal: " .. touch.Parent.Name)
        teleportTo(touch.Position)
        task.wait(0.3)
        if not cont() then return false end
        touchFire(touch, cont)
        task.wait(3) -- wait for the map change
        table.clear(cache)

        local hrp = getHRP()
        if startPos and hrp and (hrp.Position - startPos).Magnitude < 30 then return false end -- did not move
        return cont()
    end

    -- count character respawns (back on the island -> repeat the route to RUINS)
    local charGen = 0
    local inRuinsArea = false -- true after the RUINS portal was touched (until respawn / back on the island)
    do
        local conn = LP.CharacterAdded:Connect(function()
            charGen += 1
            inRuinsArea = false
            lastEq = {}
        end)
        onCleanup(function() conn:Disconnect() end)
    end

    -- ---------- hover (float while hitting) ----------
    local HOVER_NAME = "KyHover"
    local function disableHover()
        local c = LP.Character
        local hrp = c and c:FindFirstChild("HumanoidRootPart")
        local hum = c and c:FindFirstChildOfClass("Humanoid")
        local bv = hrp and hrp:FindFirstChild(HOVER_NAME)
        if bv then pcall(function() bv:Destroy() end) end
        if hum then pcall(function() hum.PlatformStand = false end) end
    end

    local function enableHover(hum, hrp)
        if hrp:FindFirstChild(HOVER_NAME) then return end
        local bv = Instance.new("BodyVelocity")
        bv.Name = HOVER_NAME
        bv.MaxForce = Vector3.new(1e6, 1e6, 1e6)
        bv.Velocity = Vector3.zero
        bv.Parent = hrp
        hum.PlatformStand = true
    end

    -- ground height right under the character (nil if none)
    local function groundY(hrp)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {LP.Character}
        local r = workspace:Raycast(hrp.Position + Vector3.new(0, 8, 0), Vector3.new(0, -250, 0), params)
        return r and r.Position.Y
    end

    -- ---------- hit one target ----------
    local ANGLES = {0, 70, -70, 140, -140, 180}
    local MAX_WALK_FAILS = 8

    local function hitInner(kind, node, id, equipName)
        local t0 = os.clock()
        local function labelFor(n)
            return kind == "tree" and ("Chopping " .. n.name) or ("Mining " .. (n.res or ""):upper())
        end
        local label = labelFor(node)
        local stand = CFG.StandDist + (node.radius or 0)
        local limit = (kind == "tree") and CFG.HitTime or CFG.MineMaxTime
        local angleIdx, fails = 1, 0

        local lastIslandCheck = os.clock()
        while mode == kind and runId == id and not Link.pause do
            local hum, hrp = getChar()
            if not hum then return false end

            if (CFG.UseHub or (kind == "tree" and CFG.TreeKind == "pine")) and os.clock() - lastIslandCheck > 2 then
                lastIslandCheck = os.clock()
                if onIsland() then return false end -- back on the island: stop, run() enters the Hub again
            end

            if not isAlive(node) then
                if kind ~= "mine" then return false end
                local why = whyDead(node)
                local rep
                for _ = 1, 4 do
                    task.wait(0.4)
                    if mode ~= kind or runId ~= id then return false end
                    rep = findReplacement(node)
                    if rep then break end
                end
                if not rep then
                    setInfo(label .. "\nDone (" .. why .. ")")
                    return false
                end
                node = rep
                label = labelFor(node)
                stand = CFG.StandDist + (node.radius or 0)
                angleIdx, fails = 1, 0
                continue
            end

            if limit > 0 and os.clock() - t0 > limit then return true end

            hum.WalkSpeed = CFG.WalkSpeed
            ensureEquip(equipName)
            hum, hrp = getChar()
            if not hum then return false end

            local ok, curPos = pcall(function() return node.key.Position end)
            if ok then node.pos = curPos end

            local flat = Vector3.new(hrp.Position.X - node.pos.X, 0, hrp.Position.Z - node.pos.Z)
            if flat.Magnitude > stand + 4 then
                disableHover() -- walk on the ground first, hover again once there
                local base = flat.Magnitude > 0.1 and flat.Unit or Vector3.new(0, 0, 1)
                local dir = CFrame.Angles(0, math.rad(ANGLES[angleIdx]), 0):VectorToWorldSpace(base)
                local spot = node.pos + dir * stand
                local function cont() return mode == kind and runId == id and isAlive(node) and not Link.pause end
                setInfo(label .. "\nWalking to target...")
                if not walkTo(spot, 2.5, 20, cont) then
                    if mode ~= kind or runId ~= id then return false end
                    if isAlive(node) and not Link.pause then
                        fails += 1
                        if fails >= MAX_WALK_FAILS then return true end -- cannot reach it, skip this target
                        angleIdx = angleIdx % #ANGLES + 1
                        setInfo(("%s\nNot there yet, trying another side (%d/%d)"):format(label, fails, MAX_WALK_FAILS))
                        task.wait(0.3)
                    end
                    continue
                end
                hum, hrp = getChar()
                if not hum then return false end
            end

            do
                local pos = hrp.Position
                if CFG.Hover then
                    enableHover(hum, hrp)
                    local gy = groundY(hrp)
                    if gy then pos = Vector3.new(pos.X, gy + CFG.HoverHeight, pos.Z) end
                else
                    disableHover()
                end
                local look = Vector3.new(node.pos.X, pos.Y, node.pos.Z)
                pcall(function()
                    hrp.CFrame = CFrame.lookAt(pos, look)
                    hrp.AssemblyLinearVelocity = Vector3.zero
                end)
            end
            setInfo(("%s\nOn this target for %ds"):format(label, math.floor(os.clock() - t0)))
            swing(node.arg)
            task.wait(CFG.SwingDelay)
        end
        return false
    end

    local function hit(kind, node, id, equipName)
        local ok, r = pcall(hitInner, kind, node, id, equipName)
        disableHover() -- always drop / release hover after a hit
        if not ok then error(r, 0) end
        return r
    end

    -- ---------- main loop ----------
    local function run(id, kind)
        local equipName = kind == "tree" and "Axe" or "Pickaxe"
        local skipped = {}
        local hasTouchedRuins = false
        local seenGen = charGen

        while mode == kind and runId == id do
            local hum, hrp = getChar()
            if Link.pause then
                disableHover()
                setInfo("Paused, Auto Collect is running...")
                task.wait(0.3)
            elseif not hum then
                setInfo("Waiting for character...")
                task.wait(1)
            else
                hum.WalkSpeed = CFG.WalkSpeed
                local pineMode = (kind == "tree" and CFG.TreeKind == "pine")

                -- Pine: Hub -> RUINS -> TouchPart. Respawn / back on island -> repeat the route
                if pineMode then
                    if charGen ~= seenGen then
                        seenGen = charGen
                        hasTouchedRuins = false
                    elseif hasTouchedRuins and onIsland() then
                        hasTouchedRuins = false
                        setInfo("Back on the island, repeating the route to RUINS...")
                    end
                end

                local skipLoop = false
                if pineMode and not hasTouchedRuins then
                    table.clear(cache)
                    if not onIsland() and pineNear() then
                        hasTouchedRuins = true -- already in the RUINS area, pines are close
                        inRuinsArea = true
                    else
                        Link.hubBusy = true
                        local okR = touchRuinsPortal(id)
                        Link.hubBusy = false
                        if okR then
                            hasTouchedRuins = true
                            inRuinsArea = true
                            waitForPines(id)
                        else
                            if mode ~= kind or runId ~= id then break end
                            task.wait(2)
                            skipLoop = true
                        end
                    end
                end

                -- Switched from Pine (RUINS) to Wood / Mine: leave RUINS and return to the Hub first
                if not skipLoop and not pineMode and inRuinsArea and CFG.ReturnToHub then
                    if onIsland() then
                        inRuinsArea = false
                    else
                        disableHover()
                        Link.hubBusy = true
                        local okBack = returnViaPortal(id)
                        Link.hubBusy = false
                        if okBack then
                            inRuinsArea = false
                        elseif mode == kind and runId == id and not Link.pause then
                            -- portal failed: fallback = reset, respawn on the island, then enter the Hub from there
                            setInfo("Return portal failed, resetting the character instead...")
                            local gen = charGen
                            local h2 = getChar()
                            if h2 then pcall(function() h2.Health = 0 end) end
                            local t0 = os.clock()
                            while charGen == gen and runId == id and mode == kind and os.clock() - t0 < 15 do
                                task.wait(0.25)
                            end
                            inRuinsArea = false
                            table.clear(cache)
                            task.wait(1.5)
                        end
                        skipLoop = true
                    end
                end

                -- Wood & Mine live in the Hub: if still on the island, enter the Hub first
                if not skipLoop and CFG.UseHub and not pineMode and onIsland() then
                    setInfo("On the island, entering the Hub first...")
                    Link.hubBusy = true
                    if enterHub(id) then
                        table.clear(cache)
                    else
                        task.wait(1)
                    end
                    Link.hubBusy = false
                    skipLoop = true
                end

                -- farming
                if not skipLoop then
                    ensureEquip(equipName)
                    hum, hrp = getChar()
                    if hum then
                        local node, why, manual = pick(kind, hrp, skipped)
                        if node then
                            if hit(kind, node, id, equipName) then skipped[node.key] = os.clock() + 30 end
                        elseif manual then
                            setInfo("No ore node found, hitting the Terrain at this spot.\nStand next to the material (or click DEBUG mine).")
                            swing(workspace.Terrain)
                            task.wait(CFG.SwingDelay)
                        else
                            setInfo(why or "No target.")
                            task.wait(1)
                        end
                    end
                end
            end
            task.wait()
        end
    end

    local function start(kind)
        mode = kind
        runId += 1
        local id = runId
        lastEq = {}
        task.spawn(function()
            local ok, err = pcall(run, id, kind)
            if not ok then
                warn("[KyHub] Auto Farm error:", err)
                setInfo("Error: " .. tostring(err))
            end
        end)
    end

    local function stopIf(kind)
        if mode == kind then
            mode = nil
            runId += 1
            disableHover()
            restoreSpeed()
            local hum, hrp = getChar()
            if hum and hrp then pcall(function() hum:MoveTo(hrp.Position) end) end
            setInfo("Turned off.")
        end
    end

    function Farm.SetTree(v)
        if v then
            Combat.Exclusive("tree")
            start("tree")
        else
            stopIf("tree")
        end
    end

    function Farm.SetMine(v)
        if v then
            Combat.Exclusive("mine")
            start("mine")
        else
            stopIf("mine")
        end
    end

    -- tree type changed: restart the loop only if the type really changed (pine = auto route to Hub/RUINS)
    function Farm.OnTreeKind(k)
        local changed = CFG.TreeKind ~= k
        CFG.TreeKind = k
        table.clear(cache)
        if changed and mode == "tree" then
            disableHover()
            start("tree")
        end
    end

    function Farm.IsActive() return mode ~= nil end

    -- ---------- DEBUG ----------
    local function toolNames()
        local t = {}
        for _, c in ipairs({LP:FindFirstChildOfClass("Backpack"), LP.Character}) do
            if c then
                for _, x in ipairs(c:GetChildren()) do
                    if x:IsA("Tool") then t[#t + 1] = x.Name end
                end
            end
        end
        return table.concat(t, ", ")
    end

    -- RUINS model inside the Hub (used by DEBUG trees)
    local function findRuins()
        local hub = hubModel()
        return hub and hub:FindFirstChild(CFG.RuinsName, true)
    end

    function Farm.DebugTree()
        print("[KyHub] ===== DEBUG TREES =====")
        print("Your tools:", toolNames())
        print("onIsland:", onIsland(), "| inHub:", inHub())
        local ruinsM = findRuins()
        if ruinsM then
            print("TouchParts inside RUINS (" .. ruinsM:GetFullName() .. "):")
            for _, d in ipairs(ruinsM:GetDescendants()) do
                if d:IsA("BasePart") and d.Name == CFG.TouchPartName then print("  ", d:GetFullName()) end
            end
        else
            print("RUINS model not found")
        end
        table.clear(cache)
        local roots = getResourceRoots()
        print(("ResourceField roots found: %d"):format(#roots))
        for _, r in ipairs(roots) do print("  root:", r:GetFullName()) end
        for _, kind in ipairs({"wood", "pine"}) do
            local list = treeNodes(kind)
            print(("%s: %d trees detected"):format(kind, #list))
            if list[1] then print("  example:", list[1].key:GetFullName()) end
        end
    end

    function Farm.DebugMine()
        print("[KyHub] ===== DEBUG MINE =====")
        print("Your tools:", toolNames())
        table.clear(cache)
        local root = mineRoot()
        print("Search root:", root and root:GetFullName() or "DOES NOT EXIST")
        local map = mineMap()
        for _, r in ipairs(CFG.MineList) do
            print(("%s: %d nodes"):format(r, #map[r]))
            if map[r][1] then print("  example:", map[r][1].key:GetFullName()) end
        end
        if root then
            local count, n = {}, 0
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("BasePart") then count[d.Name] = (count[d.Name] or 0) + 1 end
            end
            print("Part names under the root (max 60):")
            for name, c in pairs(count) do
                n += 1
                if n > 60 then break end
                print(("  %s x%d"):format(name, c))
            end
        end
    end

    onCleanup(function()
        mode = nil
        runId += 1
        pcall(disableHover)
        pcall(restoreSpeed)
    end)
end

-- deteksi disconnect (dipakai webhook dan auto rejoin)
do
    function DC.on(f) DC.handlers[#DC.handlers + 1] = f end

    -- masih ada pesan error / ErrorPrompt di layar?
    function DC.confirm()
        local m = ""
        pcall(function() m = GuiService:GetErrorMessage() end)
        if m ~= "" then return true end
        local ok, found = pcall(function()
            return CoreGui.RobloxPromptGui.promptOverlay:FindFirstChild("ErrorPrompt") ~= nil
        end)
        return ok and found
    end

    -- hard = pasti putus (player keluar), selain itu dicek dulu biar tidak salah deteksi
    function DC.report(reason, hard)
        -- lagi pindah server sengaja (Anti Satu Server): bukan disconnect
        if DC.fired or DC.hopping then return end
        if not hard then
            task.wait(2)
            if not DC.confirm() then return end
        end
        if DC.fired or DC.hopping then return end
        DC.fired = true
        for _, f in ipairs(DC.handlers) do task.spawn(f, reason) end
    end

    local conns = {}
    conns[#conns + 1] = GuiService.ErrorMessageChanged:Connect(function()
        local m = ""
        pcall(function() m = GuiService:GetErrorMessage() end)
        if m ~= "" then task.spawn(DC.report, m) end
    end)
    conns[#conns + 1] = Players.PlayerRemoving:Connect(function(p)
        if p == LP then task.spawn(DC.report, "Keluar dari game", true) end
    end)
    task.spawn(function()
        pcall(function()
            local overlay = CoreGui:WaitForChild("RobloxPromptGui", 15):WaitForChild("promptOverlay", 15)
            conns[#conns + 1] = overlay.ChildAdded:Connect(function(ch)
                if ch.Name ~= "ErrorPrompt" then return end
                task.wait(0.3)
                local msg = ""
                pcall(function() msg = ch.MessageArea.ErrorFrame.ErrorMessage.Text end)
                task.spawn(DC.report, msg)
            end)
        end)
    end)

    onCleanup(function()
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        table.clear(DC.handlers)
    end)
end

-- webhook discord
do
    local master, alive, started = false, true, false
    local last, pending = {}, {}      -- jumlah terakhir per item, dan tambahan yang belum dikirim
    local lastSent, hbNext, quietUntil = 0, 0, 0
    local queue = {}
    local guiCache = {t = -100, v = {}}
    local rsCache = {t = -100, list = {}}
    local startTime = os.time()
    local pendingRejoin = nil

    local TRACK = {
        {key = "pink", label = "Pink Gear", color = 0xFF69B4},
        {key = "stone", label = "Batu", color = 0x9AA0A6},
    }

    local httpReq = (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request)

    local function setInfo(t) if WH.info then WH.info.Text = t end end
    local function norm(s) return (tostring(s):lower():gsub("[^%w]", "")) end
    local function fmt(n) return tostring(math.floor((tonumber(n) or 0) + 0.5)) end
    local function num(key, default)
        local c = Controls[key]
        return c and tonumber(c.get()) or default
    end

    local function validUrl(u)
        if type(u) ~= "string" then return false end
        return (u:match("^https://discord%.com/api/webhooks/%d+/.+")
            or u:match("^https://discordapp%.com/api/webhooks/%d+/.+")
            or u:match("^https://ptb%.discord%.com/api/webhooks/%d+/.+")
            or u:match("^https://canary%.discord%.com/api/webhooks/%d+/.+")) and true or false
    end

    -- file sesi, buat deteksi rejoin
    local SESSION_FILE = "KyHub/session_" .. LP.UserId .. ".json"
    local function fsOK()
        return (writefile and readfile and isfile and makefolder and isfolder) and true or false
    end
    local function writeSession(state, reason)
        if not fsOK() then return end
        pcall(function()
            if not isfolder("KyHub") then makefolder("KyHub") end
            writefile(SESSION_FILE, HttpService:JSONEncode({state = state, t = os.time(), reason = reason, job = game.JobId}))
        end)
    end
    local function readSession()
        if not fsOK() or not isfile(SESSION_FILE) then return nil end
        local ok, d = pcall(function() return HttpService:JSONDecode(readfile(SESSION_FILE)) end)
        if ok and type(d) == "table" then return d end
    end

    -- baca inventory dari Value / Attribute / Tool milik player
    local GENERIC = {amount = true, count = true, quantity = true, qty = true, stack = true, value = true, amt = true}

    local function invAdd(inv, name, n, useMax)
        if type(n) ~= "number" or n ~= n or n <= 0 then return end
        local k = norm(name)
        if k == "" then return end
        local e = inv[k]
        if e then
            if useMax then e.count = math.max(e.count, n) else e.count += n end
        else
            inv[k] = {name = tostring(name), count = n}
        end
    end

    local function visit(d, inv)
        if d:IsA("Tool") then
            local amt = d:GetAttribute("Amount") or d:GetAttribute("Count") or d:GetAttribute("Quantity") or 1
            invAdd(inv, d.Name, tonumber(amt) or 1)
        elseif d:IsA("IntValue") or d:IsA("NumberValue") then
            local nm = d.Name
            if GENERIC[nm:lower()] and d.Parent and d.Parent ~= LP then nm = d.Parent.Name end
            invAdd(inv, nm, d.Value)
        end
        if not d:IsA("Tool") then
            for k, v in pairs(d:GetAttributes()) do
                if type(v) == "number" then
                    invAdd(inv, GENERIC[k:lower()] and d.Name or k, v)
                end
            end
        end
    end

    local function scanRoot(root, inv)
        visit(root, inv)
        for _, d in ipairs(root:GetDescendants()) do visit(d, inv) end
    end

    -- pencarian rekursif di ReplicatedStorage berat, hasilnya disimpan 30 detik
    local function rsRoots()
        if os.clock() - rsCache.t > 30 then
            rsCache.t = os.clock()
            rsCache.list = {}
            for _, nm in ipairs({LP.Name, tostring(LP.UserId)}) do
                local ok, o = pcall(function() return RS:FindFirstChild(nm, true) end)
                if ok and o then rsCache.list[#rsCache.list + 1] = o end
            end
        end
        return rsCache.list
    end

    local function readInventory()
        local inv = {}
        pcall(function()
            visit(LP, inv)
            for _, c in ipairs(LP:GetChildren()) do
                if c.Name ~= "PlayerGui" and c.Name ~= "PlayerScripts" then scanRoot(c, inv) end
            end
            if LP.Character then
                for _, c in ipairs(LP.Character:GetChildren()) do
                    if c:IsA("Tool") then visit(c, inv) end
                end
            end
            for _, o in ipairs(rsRoots()) do
                if o.Parent then scanRoot(o, inv) end
            end
        end)
        return inv
    end

    -- cadangan kalau data di atas kosong: baca teks UI seperti "Pink Gear x2" / "Pink Gear: 2"
    local function readGui()
        local inv = {}
        pcall(function()
            local pg = LP:FindFirstChild("PlayerGui")
            if not pg then return end
            for _, d in ipairs(pg:GetDescendants()) do
                if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text ~= "" and #d.Text < 60 and not d:IsDescendantOf(Gui) then
                    local t = d.Text:gsub("<[^>]+>", "")
                    local name, n = t:match("^(.-)%s*[xX]%s*(%d[%d,]*)%s*$")
                    if not name then name, n = t:match("^(.-)%s*×%s*(%d[%d,]*)%s*$") end
                    if not name then name, n = t:match("^(.-)%s*:%s*(%d[%d,]*)%s*$") end
                    if name and n and #name > 0 then
                        invAdd(inv, name, tonumber((n:gsub(",", ""))), true)
                    end
                end
            end
        end)
        return inv
    end

    local function parseKw(s)
        local list = {}
        for part in tostring(s or ""):gmatch("[^,]+") do
            local raw = part:gsub("%s", "")
            local k = norm(raw)
            if k ~= "" then list[#list + 1] = {k = k, wild = raw:find("*", 1, true) ~= nil} end
        end
        return list
    end

    local function matches(nameNorm, kws)
        for _, kw in ipairs(kws) do
            if kw.wild then
                if nameNorm:find(kw.k, 1, true) then return true end
            elseif nameNorm == kw.k then
                return true
            end
        end
        return false
    end

    local function sumMatch(inv, kws)
        local c, found = 0, false
        for nameNorm, e in pairs(inv) do
            if matches(nameNorm, kws) then c += e.count; found = true end
        end
        return c, found
    end

    local function getCount(inv, kwstr)
        local kws = parseKw(kwstr)
        if #kws == 0 then return 0 end
        local c, found = sumMatch(inv, kws)
        if found then return c end
        if os.clock() - guiCache.t > 10 then guiCache.t = os.clock(); guiCache.v = readGui() end
        return (sumMatch(guiCache.v, kws))
    end

    -- kirim
    local function embed(title, desc, color, fields)
        return {
            title = title, description = desc, color = color, fields = fields,
            footer = {text = "KyHub • " .. LP.Name},
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        }
    end

    local function push(e)
        if #queue >= 20 then table.remove(queue, 1) end
        queue[#queue + 1] = e
    end

    -- return: terkirim?, kena rate limit?
    local function deliver(e)
        local url = trim(WH.url and WH.url.Get())
        if not (httpReq and validUrl(url)) then
            setInfo("Webhook URL tidak valid / executor tidak support request.")
            return false, false
        end
        local ok, res = pcall(httpReq, {
            Url = url, Method = "POST", Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode({username = "KyHub", embeds = {e}}),
        })
        if ok and res then
            local code = res.StatusCode or res.Status
            if code == 429 then return false, true end
            if (type(code) == "number" and code >= 200 and code < 300) or (code == nil and res.Success) then
                setInfo("Terkirim: " .. tostring(e.title))
                return true, false
            end
            setInfo("Gagal kirim (HTTP " .. tostring(code) .. "). Cek URL webhook.")
            return false, false
        end
        setInfo("Gagal kirim: " .. tostring(res))
        return false, false
    end

    task.spawn(function()
        while alive do
            local e = table.remove(queue, 1)
            if e then
                local _, limited = deliver(e)
                if limited then
                    table.insert(queue, 1, e)
                    task.wait(3)
                end
                task.wait(1.2)
            else
                task.wait(0.5)
            end
        end
    end)

    local function pingText()
        local ok, p = pcall(function() return LP:GetNetworkPing() end)
        if ok and type(p) == "number" then return ("%d ms"):format(math.floor(p * 1000 + 0.5)) end
        return "-"
    end

    local function featuresText()
        local t = {}
        if Tg.slime and Tg.slime.Get() then t[#t + 1] = "Auto Slime" end
        if Tg.boss and Tg.boss.Get() then t[#t + 1] = "Auto Boss" end
        if Tg.skel and Tg.skel.Get() then t[#t + 1] = "Auto Skeleton" end
        if Tg.chest and Tg.chest.Get() then t[#t + 1] = "Auto Collect" end
        if Tg.harvest and Tg.harvest.Get() then t[#t + 1] = "Auto Harvest" end
        if Tg.tree and Tg.tree.Get() then t[#t + 1] = "Auto Tree" end
        if Tg.mine and Tg.mine.Get() then t[#t + 1] = "Auto Mine" end
        return #t > 0 and table.concat(t, ", ") or "tidak ada"
    end

    local function hbDelay() return math.max(60, num("wh.hb.every", 10) * 60) end

    local function onlineEmbed()
        return embed("Masih online", ("**%s** berjalan normal."):format(LP.Name), 0x2ECC71, {
            {name = "Uptime", value = fmtDur(os.time() - startTime), inline = true},
            {name = "Ping", value = pingText(), inline = true},
            {name = "Fitur aktif", value = featuresText(), inline = false},
        })
    end

    DC.on(function(reason)
        reason = trim(reason)
        if reason == "" then reason = "Tidak diketahui" end
        writeSession("disconnected", reason)
        if master and WH.dc.Get() then
            deliver(embed("Disconnect / Kick", ("**%s** terputus dari game."):format(LP.Name), 0xE74C3C, {
                {name = "Alasan", value = reason:sub(1, 200), inline = false},
                {name = "Online selama", value = fmtDur(os.time() - startTime), inline = true},
            }))
        end
    end)

    local function flushRejoin()
        if pendingRejoin and master then
            if WH.rejoin.Get() then
                push(pendingRejoin)
                hbNext = os.clock() + hbDelay()
            end
            pendingRejoin = nil
        end
    end

    -- notif item (Pink Gear / Batu), digabung per jeda biar tidak spam
    local function tickItems()
        local anyOn = false
        for _, it in ipairs(TRACK) do
            if WH[it.key].on.Get() then anyOn = true end
        end
        if not anyOn then return end

        local now = os.clock()
        local inv = readInventory()
        local quiet = (not LP.Character) or now < quietUntil   -- habis respawn inventory sering ke-reset

        for _, it in ipairs(TRACK) do
            local ctl = WH[it.key]
            if ctl.on.Get() and not quiet then
                local c = getCount(inv, ctl.kw.Get())
                local prev = last[it.key]
                if prev ~= nil and c > prev then pending[it.key] = (pending[it.key] or 0) + (c - prev) end
                last[it.key] = c
            else
                last[it.key] = nil
                if not ctl.on.Get() then pending[it.key] = nil end
            end
        end

        if next(pending) and now - lastSent >= num("wh.cooldown", 5) then
            lastSent = now
            for _, it in ipairs(TRACK) do
                local g = pending[it.key]
                if g then
                    pending[it.key] = nil
                    push(embed(("%s didapat!"):format(it.label), ("**+%s** %s"):format(fmt(g), it.label), it.color, {
                        {name = "Player", value = LP.Name, inline = true},
                        {name = "Total sekarang", value = fmt(last[it.key] or 0), inline = true},
                    }))
                end
            end
        end
    end

    local function tickOnline()
        if WH.hb.Get() and os.clock() >= hbNext then
            hbNext = os.clock() + hbDelay()
            push(onlineEmbed())
        end
    end

    task.spawn(function()
        local since, itemTimer = 0, 0
        while alive do
            task.wait(2)
            since += 2
            itemTimer += 2
            if not DC.fired and since >= 20 then
                since = 0
                writeSession("online")
            end
            if master and not DC.fired then
                -- scan inventory tiap 4 detik saja (lebih ringan di HP)
                if itemTimer >= 4 then
                    itemTimer = 0
                    pcall(tickItems)
                end
                pcall(tickOnline)
            end
        end
    end)

    local charConn = LP.CharacterAdded:Connect(function()
        quietUntil = os.clock() + 5
        last = {}
    end)

    function Webhook.Set(v)
        if v then
            if not httpReq then
                notify("Executor tidak support request/http_request.")
                WH.master.Set(false)
                return
            end
            if not validUrl(trim(WH.url.Get())) then
                notify("Isi Webhook URL Discord yang valid dulu.")
                WH.master.Set(false)
                return
            end
            last, pending = {}, {}
            hbNext = 0
            master = true
            setInfo("Webhook aktif.")
            if started then flushRejoin() end
        else
            master = false
            setInfo("Webhook nonaktif.")
        end
    end

    -- dipanggil sekali setelah config auto load selesai, buat cek apakah ini habis rejoin
    function Webhook.OnStart()
        started = true
        startTime = os.time()
        local prev = readSession()
        writeSession("online")
        if prev then
            local gap = os.time() - (tonumber(prev.t) or os.time())
            if prev.state == "disconnected" then
                pendingRejoin = embed("Rejoin, kembali online", ("**%s** sudah online lagi."):format(LP.Name), 0x3498DB, {
                    {name = "Offline selama", value = fmtDur(gap), inline = true},
                    {name = "Alasan terputus", value = tostring(prev.reason or "-"):sub(1, 200), inline = false},
                })
            elseif prev.state == "online" and gap > 90 then
                pendingRejoin = embed("Kembali online", ("**%s** sudah online lagi."):format(LP.Name), 0x3498DB, {
                    {name = "Tidak ada sinyal selama", value = fmtDur(gap), inline = true},
                    {name = "Keterangan", value = "Game ditutup, crash, atau koneksi putus tanpa pesan error.", inline = false},
                })
            end
        end
        flushRejoin()
    end

    function Webhook.Test()
        if not httpReq then notify("Executor tidak support request/http_request."); return end
        if not validUrl(trim(WH.url.Get())) then notify("Webhook URL belum valid."); return end
        push(embed("Test KyHub", "Webhook tersambung.", 0x6C78FF, {
            {name = "Player", value = LP.Name, inline = true},
        }))
        notify("Test dikirim.")
    end

    function Webhook.Debug()
        local function dump(title, inv, limit)
            local list = {}
            for _, e in pairs(inv) do list[#list + 1] = e end
            table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
            print(title, #list)
            for i, e in ipairs(list) do
                if i > limit then print("  ..."); break end
                print(("  %s = %s"):format(e.name, fmt(e.count)))
            end
        end
        local inv, g = readInventory(), readGui()
        print("=== DEBUG INVENTORY ===")
        dump("Dari data player (Value / Attribute / Tool):", inv, 150)
        dump("Dari teks UI (cadangan):", g, 60)
        print("--- hasil per item ---")
        for _, it in ipairs(TRACK) do
            local kwstr = WH[it.key].kw.Get()
            local kws = parseKw(kwstr)
            local c1, f1 = sumMatch(inv, kws)
            local c2, f2 = sumMatch(g, kws)
            print(("  %s | nama '%s' | data: %s (%s) | UI: %s (%s)"):format(
                it.label, kwstr, fmt(c1), f1 and "ketemu" or "tidak", fmt(c2), f2 and "ketemu" or "tidak"))
        end
        notify("Hasil scan ada di console (F9).")
        setInfo("Scan selesai, lihat console (F9).")
    end

    onCleanup(function()
        alive = false
        master = false
        if not DC.fired then writeSession("closed") end
        charConn:Disconnect()
    end)
end

-- anti lag
do
    local on = false
    local saved = setmetatable({}, {__mode = "k"})
    local conns = {}
    local origQuality

    local function keep(inst, prop)
        local s = saved[inst]
        if not s then s = {}; saved[inst] = s end
        if s[prop] == nil then s[prop] = inst[prop] end
    end

    local function lag(o)
        if o:IsA("ParticleEmitter") or o:IsA("Trail") or o:IsA("Beam") or o:IsA("Smoke")
            or o:IsA("Fire") or o:IsA("Sparkles") or o:IsA("PostEffect") then
            pcall(function() keep(o, "Enabled"); o.Enabled = false end)
        end
    end

    local function enable()
        if on then return end
        on = true
        pcall(function() keep(Lighting, "GlobalShadows"); Lighting.GlobalShadows = false end)
        pcall(function()
            local t = workspace.Terrain
            keep(t, "WaterWaveSize"); t.WaterWaveSize = 0
            keep(t, "WaterWaveSpeed"); t.WaterWaveSpeed = 0
            keep(t, "WaterReflectance"); t.WaterReflectance = 0
        end)
        pcall(function()
            origQuality = settings().Rendering.QualityLevel
            settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
        end)
        conns[#conns + 1] = workspace.DescendantAdded:Connect(lag)
        conns[#conns + 1] = Lighting.DescendantAdded:Connect(lag)
        task.spawn(function()
            local n = 0
            for _, root in ipairs({workspace, Lighting}) do
                for _, o in ipairs(root:GetDescendants()) do
                    if not on then return end
                    lag(o)
                    n += 1
                    if n % 1500 == 0 then task.wait() end
                end
            end
        end)
    end

    local function disable()
        if not on then return end
        on = false
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        table.clear(conns)
        for inst, props in pairs(saved) do
            pcall(function() for p, v in pairs(props) do inst[p] = v end end)
        end
        table.clear(saved)
        pcall(function() if origQuality then settings().Rendering.QualityLevel = origQuality end end)
    end

    function Sys.AntiLag(v) if v then enable() else disable() end end
    onCleanup(disable)
end

-- anti afk
do
    local afkConn
    function Sys.AntiAFK(v)
        if v then
            if afkConn then return end
            afkConn = LP.Idled:Connect(function()
                pcall(function()
                    VirtualUser:CaptureController()
                    VirtualUser:ClickButton2(Vector2.new(0, 0))
                end)
            end)
        elseif afkConn then
            afkConn:Disconnect()
            afkConn = nil
        end
    end
    onCleanup(function() if afkConn then afkConn:Disconnect(); afkConn = nil end end)
end

-- auto rejoin
do
    local qot = queue_on_teleport or (syn and syn.queue_on_teleport) or queueonteleport or (fluxus and fluxus.queue_on_teleport)

    DC.on(function()
        if not Rejoin.On then return end
        task.wait(Rejoin.Delay)

        -- supaya script jalan lagi di server baru
        if Rejoin.Loader ~= "" and qot then
            local code
            if Rejoin.Loader:match("^https?://") then
                code = ("loadstring(game:HttpGet(%q))()"):format(Rejoin.Loader)
            else
                code = ("loadstring(readfile(%q))()"):format(Rejoin.Loader)
            end
            pcall(qot, code)
        end

        for _ = 1, 20 do
            if not Rejoin.On then return end
            pcall(function() TeleportService:Teleport(game.PlaceId, LP) end)
            task.wait(15)
        end
    end)
end

-- anti satu server: kalau salah satu user ID di daftar ada di server ini, pindah ke server lain
do
    local qot = queue_on_teleport or (syn and syn.queue_on_teleport) or queueonteleport or (fluxus and fluxus.queue_on_teleport)
    local GRACE = 25   -- detik: ID yang baru masuk diberi waktu untuk pindah sendiri

    -- server yang sudah dicoba disimpan di env, supaya tidak balik ke server yang sama setelah script jalan lagi
    local bad = env.KyHub_BadServers
    if type(bad) ~= "table" then bad = {}; env.KyHub_BadServers = bad end
    bad[game.JobId] = true

    local busy, lastTry = false, 0
    local arrived = {}   -- [userId] = waktu dia masuk SETELAH kita (dia yang seharusnya pindah)

    local function setInfo(t) if Blk.info then Blk.info.Text = t end end

    function Blk.SetIds(text)
        local list, set = {}, {}
        for w in tostring(text or ""):gmatch("%d+") do
            local n = tonumber(w)
            if n and not set[n] then set[n] = true; list[#list + 1] = n end
        end
        Blk.ids, Blk.set = list, set
        setInfo(Blk.on and ("Aktif, memantau %d ID."):format(#list) or "Nonaktif.")
    end

    function Blk.Set(v)
        Blk.on = v and true or false
        lastTry = 0
        setInfo(Blk.on and ("Aktif, memantau %d ID."):format(#Blk.ids) or "Nonaktif.")
    end

    -- pemain di server ini yang ada di daftar (kecuali akun ini sendiri)
    local function conflicts()
        local out = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and Blk.set[p.UserId] then
                local t = arrived[p.UserId]
                -- dia baru masuk setelah kita: beri dia waktu pindah sendiri
                if not (t and os.clock() - t < GRACE) then
                    out[#out + 1] = p
                end
            end
        end
        return out
    end

    -- ambil daftar server publik, pilih acak dari yang paling sepi
    local function pickServer()
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true"):format(game.PlaceId)
        local okG, body = pcall(function() return game:HttpGet(url) end)
        if not okG then return nil, "Gagal ambil daftar server: " .. tostring(body):sub(1, 80) end
        local okJ, data = pcall(function() return HttpService:JSONDecode(body) end)
        if not (okJ and type(data) == "table" and type(data.data) == "table") then
            return nil, "Daftar server tidak terbaca (mungkin kena rate limit)."
        end
        local cands = {}
        for _, s in ipairs(data.data) do
            if type(s) == "table" and s.id and s.id ~= game.JobId and not bad[s.id]
                and type(s.playing) == "number" and type(s.maxPlayers) == "number"
                and s.playing < s.maxPlayers - 1 then
                cands[#cands + 1] = s
            end
        end
        if #cands == 0 then return nil, "Tidak ada server lain yang cocok." end
        local top = math.min(#cands, 20)
        return cands[math.random(top)].id
    end

    local function release()
        busy = false
        DC.hopping = false
        lastTry = os.clock()
    end

    local function hop(list)
        if busy then return end
        busy = true
        DC.hopping = true   -- tahan deteksi disconnect / auto rejoin / webhook selama pindah server

        local names = {}
        for _, p in ipairs(list) do names[#names + 1] = tostring(p.UserId) end
        setInfo(("ID %s ada di server ini. Mencari server lain..."):format(table.concat(names, ", ")))

        local id, why = pickServer()
        if not id then
            setInfo((why or "Gagal cari server.") .. " Coba lagi 15 detik.")
            release()
            return
        end
        bad[id] = true

        -- jalankan KyHub lagi di server baru (butuh Loader, atau KyHub ada di autoexec)
        if Rejoin.Loader ~= "" and qot then
            local code
            if Rejoin.Loader:match("^https?://") then
                code = ("loadstring(game:HttpGet(%q))()"):format(Rejoin.Loader)
            else
                code = ("loadstring(readfile(%q))()"):format(Rejoin.Loader)
            end
            pcall(qot, code)
        end

        setInfo("Pindah server...")
        local ok, err = pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, id, LP) end)
        if not ok then
            setInfo("Teleport gagal: " .. tostring(err):sub(1, 80))
            release()
            return
        end
        -- kalau 25 detik masih di sini, teleport gagal: coba server lain
        task.delay(25, function()
            if Alive and busy then
                setInfo("Teleport belum jalan, coba server lain...")
                release()
            end
        end)
    end

    local addConn = Players.PlayerAdded:Connect(function(p)
        if Blk.set[p.UserId] then arrived[p.UserId] = os.clock() end
    end)
    local tpConn = TeleportService.TeleportInitFailed:Connect(function()
        if busy then release() end
    end)

    task.spawn(function()
        while Alive do
            task.wait(3)
            if Blk.on and not busy and #Blk.ids > 0 and os.clock() - lastTry >= 15 then
                local list = conflicts()
                if #list > 0 then
                    pcall(hop, list)
                else
                    setInfo(("Aman: tidak ada dari %d ID terlarang di server ini."):format(#Blk.ids))
                end
            end
        end
    end)

    onCleanup(function()
        addConn:Disconnect()
        tpConn:Disconnect()
        Blk.on = false
        DC.hopping = false
    end)
end

-- config
do
    local FOLDER = "KyHub"
    local CFG_DIR = FOLDER .. "/configs"
    local AUTO_FILE = FOLDER .. "/autoload_" .. LP.UserId .. ".txt"
    local INDEX_FILE = FOLDER .. "/index_" .. LP.UserId .. ".json"
    local pendingDel, pendingT = nil, 0

    local function fsOK()
        return (writefile and readfile and isfile and makefolder and isfolder) and true or false
    end
    Sys.FsReady = fsOK

    local function clean(n)
        n = tostring(n or "")
        n = n:gsub("[^%w%-_ ]", "")
        return trim(n):sub(1, 30)
    end

    local function pathOf(n) return CFG_DIR .. "/" .. n .. ".json" end

    local function ensureDirs()
        if not isfolder(FOLDER) then makefolder(FOLDER) end
        if not isfolder(CFG_DIR) then makefolder(CFG_DIR) end
    end

    -- daftar dari listfiles kalau ada, ditambah index (buat executor tanpa listfiles)
    local function listNames()
        local names, seen = {}, {}
        local function add(n)
            if n and n ~= "" and not seen[n] and isfile(pathOf(n)) then
                seen[n] = true
                names[#names + 1] = n
            end
        end
        if listfiles and isfolder(CFG_DIR) then
            local ok, files = pcall(listfiles, CFG_DIR)
            if ok and type(files) == "table" then
                for _, p in ipairs(files) do add(tostring(p):match("([^/\\]+)%.json$")) end
            end
        end
        if isfile(INDEX_FILE) then
            local ok, data = pcall(function() return HttpService:JSONDecode(readfile(INDEX_FILE)) end)
            if ok and type(data) == "table" then
                for _, n in ipairs(data) do add(n) end
            end
        end
        table.sort(names, function(a, b) return a:lower() < b:lower() end)
        return names
    end

    local function writeIndex()
        pcall(function() writefile(INDEX_FILE, HttpService:JSONEncode(listNames())) end)
    end

    local function readAuto()
        if not fsOK() then return nil end
        local okE, exists = pcall(isfile, AUTO_FILE)
        if not (okE and exists) then return nil end
        local ok, v = pcall(readfile, AUTO_FILE)
        if not ok then return nil end
        v = clean(v)
        if v == "" or v == "0" or v == "1" then return nil end   -- format lama
        return v
    end

    function Sys.GetAuto() return readAuto() end

    function Sys.Refresh()
        if not fsOK() then
            CfgUI.list.SetData({}, nil)
            CfgUI.status.Text = "Executor tidak support file (writefile/readfile)."
            return
        end
        pcall(ensureDirs)
        local auto = readAuto()
        CfgUI.list.SetData(listNames(), auto)
        CfgUI.status.Text = auto and ("Auto Load: " .. auto) or "Auto Load: OFF"
    end

    function Sys.Save()
        if not fsOK() then notify("Executor tidak support file (writefile/readfile)."); return end
        local name = clean(CfgUI.name.Get())
        if name == "" then name = CfgUI.list.selected or "" end
        if name == "" then notify("Isi nama config dulu."); return end
        local data = {}
        for k, c in pairs(Controls) do data[k] = c.get() end
        local ok, err = pcall(function()
            ensureDirs()
            writefile(pathOf(name), HttpService:JSONEncode(data))
        end)
        if not ok then notify("Gagal menyimpan: " .. tostring(err)); return end
        writeIndex()
        CfgUI.list.selected = name
        CfgUI.name.Set(name, true)
        Sys.Refresh()
        notify("Config disimpan: " .. name)
    end

    -- urutan load tetap: fitur utama paling akhir, supaya nilai pengaturannya sudah terpasang
    local LAST = {["harvest.on"] = 1, ["chest.on"] = 2, ["tree.on"] = 3, ["mine.on"] = 4, ["skel.on"] = 5, ["boss.on"] = 6, ["slime.on"] = 7}
    local function sortedKeys()
        local keys = {}
        for k in pairs(Controls) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b)
            local la, lb = LAST[a] or 0, LAST[b] or 0
            if la ~= lb then return la < lb end
            return a < b
        end)
        return keys
    end

    function Sys.Load(nameArg, silent)
        local function say(m) if not silent then notify(m) end end
        if not Alive then return false end
        if not fsOK() then say("Executor tidak support file (writefile/readfile)."); return false end
        local name = clean(nameArg)
        if name == "" then name = CfgUI.list.selected or clean(CfgUI.name.Get()) end
        if name == "" then say("Pilih config yang mau di-load dulu."); return false end
        local okE, exists = pcall(isfile, pathOf(name))
        if not (okE and exists) then say("Config tidak ditemukan: " .. name); return false end
        local okR, raw = pcall(readfile, pathOf(name))
        if not okR or type(raw) ~= "string" or raw == "" then say("Config tidak bisa dibaca."); return false end
        local ok, data = pcall(function() return HttpService:JSONDecode(raw) end)
        if not ok or type(data) ~= "table" then say("Config rusak / tidak bisa dibaca."); return false end

        local keys = sortedKeys()
        -- angka dan teks dulu, baru toggle, supaya fitur nyala dengan nilai yang benar
        for _, k in ipairs(keys) do
            local c = Controls[k]
            if c.kind ~= "toggle" and data[k] ~= nil then pcall(c.set, data[k]) end
        end
        for _, k in ipairs(keys) do
            local c = Controls[k]
            if c.kind == "toggle" and data[k] ~= nil then pcall(c.set, data[k]) end
        end
        CfgUI.list.selected = name
        CfgUI.name.Set(name, true)
        Sys.Refresh()
        if not silent then notify("Config dimuat: " .. name) end
        return true
    end

    function Sys.Delete()
        if not fsOK() then notify("Executor tidak support file."); return end
        if not delfile then notify("Executor tidak support delfile."); return end
        local name = CfgUI.list.selected
        if not name then notify("Klik nama config di daftar dulu."); return end
        if pendingDel ~= name or os.clock() - pendingT > 4 then
            pendingDel, pendingT = name, os.clock()
            notify(("Klik Delete lagi dalam 4 detik untuk hapus '%s'"):format(name))
            return
        end
        pendingDel = nil
        local ok = pcall(delfile, pathOf(name))
        if ok and not isfile(pathOf(name)) then
            if readAuto() == name then pcall(writefile, AUTO_FILE, "") end
            CfgUI.list.selected = nil
            CfgUI.name.Set("", true)
            writeIndex()
            Sys.Refresh()
            notify("Config dihapus: " .. name)
        else
            notify("Gagal menghapus config.")
        end
    end

    function Sys.SetAuto()
        if not fsOK() then notify("Executor tidak support file."); return end
        local name = CfgUI.list.selected
        if not name then notify("Klik nama config di daftar dulu."); return end
        local ok = pcall(function()
            ensureDirs()
            writefile(AUTO_FILE, name)
        end)
        Sys.Refresh()
        notify(ok and ("Auto Load: " .. name) or "Gagal menyimpan Auto Load.")
    end

    function Sys.ClearAuto()
        if not fsOK() then notify("Executor tidak support file."); return end
        pcall(function() writefile(AUTO_FILE, "") end)
        Sys.Refresh()
        notify("Auto Load: OFF")
    end
end


-- =====================================================================
-- CLEANUP
-- =====================================================================
local function doCleanup()
    if not Alive then return end
    Alive = false
    for _, f in ipairs(cleanups) do pcall(f) end
    cleanups = {}
    pcall(function() Gui:Destroy() end)
end

CloseBtn.Activated:Connect(doCleanup)
env.KyHub_Cleanup = doCleanup
onCleanup(function() env.KyHub_Cleanup = nil end)

-- default toggles via Deferred
for _, f in ipairs(Deferred) do pcall(f) end

-- pick the starting tab
selectTab("Home")

Sys.Refresh()

task.spawn(function()
    -- tunggu island (terdeteksi otomatis) dan Remotes muncul, maks 30 detik
    local t0 = os.clock()
    while Alive and os.clock() - t0 < 30 do
        if Island.get() and RS:FindFirstChild("Remotes") then break end
        task.wait(0.5)
    end
    if not Alive then return end
    task.wait(2)

    -- auto load: dicoba ulang kalau file system belum siap atau baca gagal (sering terjadi di autoexec)
    local loadedName
    for attempt = 1, 6 do
        if not Alive then return end
        if Sys.FsReady() then
            local autoName = Sys.GetAuto()
            if not autoName then break end   -- memang tidak ada auto load
            if Sys.Load(autoName, true) then
                loadedName = autoName
                break
            end
        end
        task.wait(1.5)
    end
    if not Alive then return end

    if loadedName then
        notify("Auto Load: " .. loadedName)
    else
        notify("KyHub siap.")
    end

    Webhook.OnStart()
end)

notify("KyHub v17.2 loaded. Auto Combat (Slime / Boss / Skeleton) is ready.")
