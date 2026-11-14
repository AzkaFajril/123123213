-- KyHub v4 (autoexec fix)
-- RightShift = sembunyikan menu, E = auto harvest

-- tunggu game siap (penting untuk autoexec)
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

if getgenv().KyHub_Cleanup then pcall(getgenv().KyHub_Cleanup) end

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

local cleanups = {}
local function onCleanup(f) cleanups[#cleanups + 1] = f end

local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local function fmtDur(s)
    s = math.max(0, math.floor(tonumber(s) or 0))
    local h, m = s // 3600, (s % 3600) // 60
    if h > 0 then return ("%dj %dm"):format(h, m) end
    if m > 0 then return ("%dm %ds"):format(m, s % 60) end
    return ("%ds"):format(s)
end

local T = {
    bg = Color3.fromRGB(20, 20, 26),
    side = Color3.fromRGB(27, 27, 35),
    card = Color3.fromRGB(35, 35, 46),
    stroke = Color3.fromRGB(54, 54, 70),
    text = Color3.fromRGB(236, 236, 246),
    sub = Color3.fromRGB(150, 150, 172),
    accent = Color3.fromRGB(108, 120, 255),
    on = Color3.fromRGB(64, 200, 120),
    off = Color3.fromRGB(70, 70, 86),
    danger = Color3.fromRGB(205, 62, 72),
    good = Color3.fromRGB(165, 225, 180),
}

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
local function stroke(o, c)
    new("UIStroke", {Color = c or T.stroke, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border}, o)
    return o
end

-- pengaturan bawaan
local SlimeCFG = {
    ISLAND_NAME = "Island_" .. LP.UserId .. ":1",
    Priority = {"pink", "orange", "blue", "green"},
    UseHub = true,
    AutoHub = true,
    WalkSpeed = 22,
    StuckTime = 2,
    SkipFor = 30,
    AttackRange = 7,
    SwingDelay = 0.4,
    EquipEvery = 15,
    SwingArgs = {},
    LobbyName = "Hub",
    LobbyPad = 10,
    AfterDelay = 3,
    FindTimeout = 5,
}

local ChestCFG = {
    ISLAND_NAME = "Island_" .. LP.UserId .. ":1",
    Teleport = true,
    OnlyFull = true,
    IntervalMin = 1,        -- menit.detik, 0.30 = 30 detik, 1.30 = 1 menit 30 detik
    OpenWait = 3,
    CollectWait = 0.8,
    BetweenChest = 0.3,
    HomeModel = "Hub",      -- model yang punya TouchPart untuk balik ke home
    HomeTouchName = "TouchPart",
    HomeWait = 8,
    AfterHomeDelay = 2,
}

local HarvestCFG = {
    WalkSpeed = 30,
    Radius = 20,
    PerSecond = 10,
    FireLimitPerBush = 1,
    BlacklistTime = 15,
    TeleportFallback = true,
    StuckTime = 1,
}

local Rejoin = {On = false, Delay = 5, Loader = ""}

local Slime, Chest, Harvest, Sys, Webhook = {}, {}, {}, {}, {}
local Link = {pause = false, hubBusy = false}   -- slime berhenti sementara kalau chest lagi jalan
local DC = {handlers = {}, fired = false}       -- disconnect
local WH, CfgUI = {}, {}
local Tg = {}
local Controls = {}
local Deferred = {}

-- window
local guiParent = (gethui and gethui()) or CoreGui
local old = guiParent:FindFirstChild("KyHubGui")
if old then old:Destroy() end

local Gui = new("ScreenGui", {Name = "KyHubGui", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, guiParent)

local Win = corner(new("Frame", {
    Size = UDim2.new(0, 560, 0, 360), Position = UDim2.new(0.5, -280, 0.5, -180),
    BackgroundColor3 = T.bg, BorderSizePixel = 0,
}, Gui), 12)
stroke(Win)

local Toast = corner(new("TextLabel", {
    Size = UDim2.new(0, 320, 0, 30), Position = UDim2.new(0.5, -160, 1, -80),
    BackgroundColor3 = T.accent, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamMedium,
    TextSize = 12, Text = "", Visible = false, ZIndex = 50,
}, Gui), 8)
local toastId = 0
local function notify(t)
    toastId += 1
    local id = toastId
    Toast.Text = t
    Toast.Visible = true
    task.delay(2.5, function() if toastId == id then Toast.Visible = false end end)
end

local Side = corner(new("Frame", {Size = UDim2.new(0, 150, 1, 0), BackgroundColor3 = T.side, BorderSizePixel = 0}, Win), 12)
new("Frame", {Size = UDim2.new(0, 12, 1, 0), Position = UDim2.new(1, -12, 0, 0), BackgroundColor3 = T.side, BorderSizePixel = 0}, Side)
local Brand = new("TextLabel", {
    Size = UDim2.new(1, -20, 0, 46), Position = UDim2.new(0, 16, 0, 0), BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold, TextSize = 19, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left,
    RichText = true, Text = 'Ky<font color="rgb(108,120,255)">Hub</font>',
}, Side)
local TabList = new("Frame", {Size = UDim2.new(1, 0, 1, -58), Position = UDim2.new(0, 0, 0, 52), BackgroundTransparency = 1}, Side)
new("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, TabList)
new("UIPadding", {PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8)}, TabList)

local Content = new("Frame", {Size = UDim2.new(1, -150, 1, 0), Position = UDim2.new(0, 150, 0, 0), BackgroundTransparency = 1}, Win)
local TopBar = new("Frame", {Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 1}, Content)
local PageTitle = new("TextLabel", {
    Size = UDim2.new(1, -90, 1, 0), Position = UDim2.new(0, 14, 0, 0), BackgroundTransparency = 1,
    Font = Enum.Font.GothamBold, TextSize = 15, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left, Text = "",
}, TopBar)
local CloseBtn = corner(new("TextButton", {
    Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(1, -36, 0, 8), BackgroundColor3 = T.danger,
    Text = "X", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Color3.new(1, 1, 1),
}, TopBar), 8)
local MinBtn = corner(new("TextButton", {
    Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(1, -68, 0, 8), BackgroundColor3 = T.card,
    Text = "-", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = T.text,
}, TopBar), 8)

local PageHolder = new("Frame", {
    Position = UDim2.new(0, 12, 0, 46), Size = UDim2.new(1, -24, 1, -58), BackgroundTransparency = 1, ClipsDescendants = true,
}, Content)

-- tombol bulat kecil waktu menu disembunyikan
local Float = corner(new("TextButton", {
    Size = UDim2.new(0, 42, 0, 42), Position = UDim2.new(0, 14, 0.5, -21), BackgroundColor3 = T.accent,
    Text = "Ky", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = Color3.new(1, 1, 1), Visible = false,
}, Gui), 21)
local function setWinVisible(v)
    Win.Visible = v
    Float.Visible = not v
end
Float.Activated:Connect(function() setWinVisible(true) end)
MinBtn.Activated:Connect(function() setWinVisible(false) end)

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

local hotkeyConn = UIS.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.RightShift then setWinVisible(not Win.Visible) end
end)
onCleanup(function() hotkeyConn:Disconnect() end)

-- tab dan komponen
local Pages, TabBtns = {}, {}
local orderCounter = 0
local function nextOrder() orderCounter += 1; return orderCounter end

local function newPage(name)
    local p = new("ScrollingFrame", {
        Name = name, Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0,
        ScrollBarThickness = 3, ScrollBarImageColor3 = T.accent, CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false,
    }, PageHolder)
    new("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, p)
    new("UIPadding", {PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8)}, p)
    Pages[name] = p
    return p
end

local function selectTab(name)
    for n, p in pairs(Pages) do p.Visible = (n == name) end
    for n, b in pairs(TabBtns) do
        local on = (n == name)
        TweenService:Create(b.btn, TweenInfo.new(0.15), {
            BackgroundTransparency = on and 0 or 1, TextColor3 = on and T.text or T.sub,
        }):Play()
        b.bar.Visible = on
    end
    PageTitle.Text = name
end

local function addTab(name)
    local btn = corner(new("TextButton", {
        Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = T.card, BackgroundTransparency = 1, AutoButtonColor = false,
        Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Left,
        Text = name, LayoutOrder = nextOrder(),
    }, TabList), 8)
    new("UIPadding", {PaddingLeft = UDim.new(0, 16)}, btn)
    local bar = corner(new("Frame", {
        Size = UDim2.new(0, 3, 0, 18), Position = UDim2.new(0, -12, 0.5, -9), BackgroundColor3 = T.accent,
        BorderSizePixel = 0, Visible = false,
    }, btn), 2)
    TabBtns[name] = {btn = btn, bar = bar}
    btn.Activated:Connect(function() selectTab(name) end)
    return newPage(name)
end

local function row(page, h)
    local f = corner(new("Frame", {
        Size = UDim2.new(1, 0, 0, h or 40), BackgroundColor3 = T.card, BorderSizePixel = 0, LayoutOrder = nextOrder(),
    }, page), 8)
    stroke(f)
    return f
end

local function Section(page, text)
    new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 11,
        TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Left, Text = text:upper(), LayoutOrder = nextOrder(),
    }, page)
end

local function rowLabel(parent, text, width)
    return new("TextLabel", {
        BackgroundTransparency = 1, Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, width, 1, 0),
        Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left, Text = text,
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, parent)
end

local function Toggle(page, key, text, default, cb)
    local f = row(page, 40)
    rowLabel(f, text, -70)
    local sw = corner(new("TextButton", {
        Text = "", AutoButtonColor = false, Size = UDim2.new(0, 40, 0, 22), Position = UDim2.new(1, -52, 0.5, -11),
        BackgroundColor3 = T.off,
    }, f), 11)
    local knob = corner(new("Frame", {
        Size = UDim2.new(0, 16, 0, 16), Position = UDim2.new(0, 3, 0.5, -8), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
    }, sw), 8)
    local state = false
    local obj = {}
    function obj.Get() return state end
    function obj.Set(v, silent)
        v = v and true or false
        if v == state then return end
        state = v
        TweenService:Create(sw, TweenInfo.new(0.15), {BackgroundColor3 = v and T.on or T.off}):Play()
        TweenService:Create(knob, TweenInfo.new(0.15), {Position = v and UDim2.new(0, 21, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)}):Play()
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
    local f = row(page, 40)
    rowLabel(f, text, -110)
    local box = corner(new("TextBox", {
        Size = UDim2.new(0, 86, 0, 26), Position = UDim2.new(1, -98, 0.5, -13), BackgroundColor3 = T.bg,
        Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = T.text, Text = tostring(default), ClearTextOnFocus = false,
    }, f), 6)
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
end

local function TextInput(page, key, text, default, cb, width, placeholder)
    local w = width or 150
    local f = row(page, 40)
    rowLabel(f, text, -(w + 24))
    local box = corner(new("TextBox", {
        Size = UDim2.new(0, w, 0, 26), Position = UDim2.new(1, -(w + 12), 0.5, -13), BackgroundColor3 = T.bg,
        Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = T.text, PlaceholderText = placeholder or "",
        PlaceholderColor3 = T.sub, Text = default or "", ClearTextOnFocus = false,
        TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left,
    }, f), 6)
    new("UIPadding", {PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6)}, box)
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
    local b = corner(new("TextButton", {
        Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = color or T.card, Font = Enum.Font.GothamMedium, TextSize = 13,
        TextColor3 = T.text, Text = text, LayoutOrder = nextOrder(),
    }, page), 8)
    stroke(b)
    b.Activated:Connect(cb)
    return b
end

-- beberapa tombol sebaris: {{teks, fungsi, warna}, ...}
local function ButtonRow(page, items)
    local f = new("Frame", {Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, LayoutOrder = nextOrder()}, page)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
    }, f)
    local n = #items
    for i, it in ipairs(items) do
        local b = corner(new("TextButton", {
            Size = UDim2.new(1 / n, -math.floor(6 * (n - 1) / n), 1, 0), BackgroundColor3 = it[3] or T.card,
            Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = T.text, Text = it[1], LayoutOrder = i,
        }, f), 8)
        stroke(b)
        b.Activated:Connect(it[2])
    end
end

-- kotak teks, tingginya ngikut isi
local function Info(page, text, minH)
    local f = corner(new("Frame", {
        Size = UDim2.new(1, 0, 0, minH or 32), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = T.card, BorderSizePixel = 0, LayoutOrder = nextOrder(),
    }, page), 8)
    stroke(f)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
    }, f)
    return new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
        Font = Enum.Font.Gotham, TextSize = 12, TextWrapped = true, TextColor3 = T.good, Text = text,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
    }, f)
end

-- daftar config yang bisa dipilih
local function ConfigPicker(page, height)
    local f = row(page, height)
    local sc = new("ScrollingFrame", {
        Size = UDim2.new(1, -12, 1, -12), Position = UDim2.new(0, 6, 0, 6), BackgroundTransparency = 1, BorderSizePixel = 0,
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
                Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 12,
                TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Left, Text = "  belum ada config tersimpan",
            }, sc)
            return
        end
        for i, n in ipairs(obj.names) do
            local picked = (n == obj.selected)
            local b = corner(new("TextButton", {
                Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = picked and T.accent or T.bg, AutoButtonColor = false,
                Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left,
                Text = "  " .. n .. ((n == obj.auto) and "    [auto load]" or ""), LayoutOrder = i,
            }, sc), 6)
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

-- halaman
local pSlime = addTab("Auto Slime")
local pChest = addTab("Overflow Chest")
local pHarvest = addTab("Auto Harvest")
local pWeb = addTab("Webhook")
local pSet = addTab("Settings")

Section(pSlime, "Auto Slime")
Tg.slime = Toggle(pSlime, "slime.on", "Auto Slime", false, function(v) Slime.Set(v) end)
Toggle(pSlime, "slime.usehub", "Touch portal HUB", SlimeCFG.UseHub, function(v) SlimeCFG.UseHub = v end)
Toggle(pSlime, "slime.autohub", "Auto Hub (ulangi portal)", SlimeCFG.AutoHub, function(v) SlimeCFG.AutoHub = v end)
Section(pSlime, "Pengaturan")
Input(pSlime, "slime.walkspeed", "WalkSpeed", SlimeCFG.WalkSpeed, function(n) SlimeCFG.WalkSpeed = n end, 1)
Input(pSlime, "slime.stuck", "Stuck (detik) lalu skip", SlimeCFG.StuckTime, function(n) SlimeCFG.StuckTime = n end, 0.5)
Input(pSlime, "slime.range", "Jarak pukul (studs)", SlimeCFG.AttackRange, function(n) SlimeCFG.AttackRange = n end, 1)
Section(pSlime, "Status")
Slime.info = Info(pSlime, "Siap.", 50)

Section(pChest, "Overflow Chest")
Tg.chest = Toggle(pChest, "chest.on", "Auto Collect", false, function(v) Chest.Set(v) end)
Input(pChest, "chest.interval", "Interval (menit.detik, 0.30 = 30 dtk)", ChestCFG.IntervalMin, function(n) ChestCFG.IntervalMin = n end, 0.05)
Toggle(pChest, "chest.onlyfull", "Hanya chest FULL", ChestCFG.OnlyFull, function(v) ChestCFG.OnlyFull = v end)
Toggle(pChest, "chest.teleport", "Teleport ke chest", ChestCFG.Teleport, function(v) ChestCFG.Teleport = v end)
Button(pChest, "DEBUG (lihat console)", function() Chest.Debug() end, Color3.fromRGB(120, 90, 40))
Section(pChest, "Status")
Chest.info = Info(pChest, "Siap.", 50)

Section(pHarvest, "Auto Harvest (tekan E)")
Tg.harvest = Toggle(pHarvest, "harvest.on", "Auto Harvest", false, function(v) Harvest.Set(v) end)
Input(pHarvest, "harvest.speed", "WalkSpeed", HarvestCFG.WalkSpeed, function(n) HarvestCFG.WalkSpeed = n end, 1)
Input(pHarvest, "harvest.radius", "Radius harvest", HarvestCFG.Radius, function(n) HarvestCFG.Radius = n end, 1)
Input(pHarvest, "harvest.persec", "Harvest per detik", HarvestCFG.PerSecond, function(n) HarvestCFG.PerSecond = n end, 1)
Toggle(pHarvest, "harvest.tpfallback", "Teleport jika stuck", HarvestCFG.TeleportFallback, function(v) HarvestCFG.TeleportFallback = v end)
Section(pHarvest, "Status")
Harvest.info = Info(pHarvest, "Idle", 32)

Section(pWeb, "Discord Webhook")
WH.url = TextInput(pWeb, "wh.url", "Webhook URL", "", nil, 220, "https://discord.com/api/webhooks/...")
WH.master = Toggle(pWeb, "wh.on", "Webhook aktif", false, function(v) Webhook.Set(v) end)
Input(pWeb, "wh.cooldown", "Jeda notif item (detik)", 5, nil, 1)

Section(pWeb, "Status Online")
WH.hb = Toggle(pWeb, "wh.hb.on", "Kirim 'masih online' berkala", true)
Input(pWeb, "wh.hb.every", "Tiap (menit)", 10, nil, 1)
WH.dc = Toggle(pWeb, "wh.dc.on", "Notif saat disconnect / kick", true)
WH.rejoin = Toggle(pWeb, "wh.rejoin.on", "Notif saat rejoin", true)

Section(pWeb, "Pink Gear")
WH.pink = {
    on = Toggle(pWeb, "wh.pink.on", "Kirim saat dapat Pink Gear", true),
    kw = TextInput(pWeb, "wh.pink.kw", "Nama item", "PinkGear", nil, 150),
}
Section(pWeb, "Batu")
WH.stone = {
    on = Toggle(pWeb, "wh.stone.on", "Kirim saat dapat Batu", false),
    kw = TextInput(pWeb, "wh.stone.kw", "Nama item", "Stone", nil, 150),
}

Section(pWeb, "Alat")
ButtonRow(pWeb, {
    {"Kirim Test", function() Webhook.Test() end, Color3.fromRGB(52, 62, 110)},
    {"Scan Inventory (console)", function() Webhook.Debug() end, Color3.fromRGB(120, 90, 40)},
})
Section(pWeb, "Status")
WH.info = Info(pWeb, "Siap.", 32)
Info(pWeb, "Nama item dicocokkan persis, huruf besar/kecil dan spasi diabaikan (\"Pink Gear\" = PinkGear). Pakai * untuk mengandung, misal *pink*. Beberapa nama dipisah koma. Kalau item tidak terbaca, klik Scan Inventory lalu lihat console (F9).", 32)
Info(pWeb, "Pesan rejoin cuma terkirim kalau script jalan lagi setelah rejoin (autoexec atau loader di Settings) dan config dengan webhook aktif di-auto load. Kalau PC atau game mati total tidak ada pesan yang bisa dikirim, tandanya pesan 'masih online' berhenti masuk.", 32)

Section(pSet, "Performa & keamanan")
Toggle(pSet, "set.antilag", "Anti Lag", false, function(v) Sys.AntiLag(v) end)
Toggle(pSet, "set.antiafk", "Anti AFK", true, function(v) Sys.AntiAFK(v) end)

Section(pSet, "Auto Rejoin")
Toggle(pSet, "rejoin.on", "Auto Rejoin", false, function(v) Rejoin.On = v end)
Input(pSet, "rejoin.delay", "Delay rejoin (detik)", 5, function(n) Rejoin.Delay = n end, 3)
TextInput(pSet, "rejoin.loader", "Loader (URL / file)", "", function(t) Rejoin.Loader = trim(t) end, 190, "kosongkan kalau pakai autoexec")
Info(pSet, "Loader dipakai untuk menjalankan KyHub lagi setelah rejoin: isi link raw script, atau nama file di folder workspace executor. Kalau KyHub sudah ada di autoexec, kosongkan. Rejoin masuk ke server baru, bukan server yang sama.", 32)

Section(pSet, "Config")
CfgUI.name = TextInput(pSet, nil, "Nama config", "", nil, 170, "contoh: farming-slime")
CfgUI.list = ConfigPicker(pSet, 120)
CfgUI.status = Info(pSet, "Auto Load: OFF", 28)
ButtonRow(pSet, {
    {"Save", function() Sys.Save() end, Color3.fromRGB(48, 90, 70)},
    {"Load", function() Sys.Load() end, Color3.fromRGB(52, 62, 110)},
    {"Delete", function() Sys.Delete() end, Color3.fromRGB(110, 48, 54)},
})
ButtonRow(pSet, {
    {"Jadikan Auto Load", function() Sys.SetAuto() end, Color3.fromRGB(70, 60, 120)},
    {"Matikan Auto Load", function() Sys.ClearAuto() end, Color3.fromRGB(60, 60, 76)},
    {"Refresh", function() Sys.Refresh() end, Color3.fromRGB(60, 60, 76)},
})
Info(pSet, "Klik nama config di daftar untuk memilih. Save pakai nama yang diketik (kalau kosong, pakai yang dipilih). Delete harus diklik 2x. Config ikut menyimpan Webhook URL, jangan dibagikan.", 32)

-- auto slime
do
    local CFG = SlimeCFG
    local active, runId = false, 0
    local teleported = false
    local kills, lastEquip = 0, 0
    local function setInfo(t) if Slime.info then Slime.info.Text = t end end

    -- kalau mati / respawn, portal HUB diulang
    local function hookDeath(char)
        local hum = char:WaitForChild("Humanoid", 10)
        if not hum then return end
        hum.Died:Connect(function()
            teleported = false
            lastEquip = 0
        end)
    end
    local deathConn = LP.CharacterAdded:Connect(function(char)
        teleported = false
        lastEquip = 0
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

    local function getRemote(name)
        local remotes = RS:FindFirstChild("Remotes")
        return remotes and remotes:FindFirstChild(name)
    end

    local function getIsland()
        return workspace:FindFirstChild(CFG.ISLAND_NAME)
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

    local function touchPart(part)
        local hrp = getHRP()
        if not hrp then return false end
        return pcall(function()
            firetouchinterest(hrp, part, 0)
            task.wait(0.15)
            firetouchinterest(getHRP() or hrp, part, 1)
        end)
    end

    -- return true kalau berhasil, atau false + alasan (+ true kalau layak dicoba lagi)
    local function runHubTeleport()
        if not getHRP() then return false, "Karakter tidak ditemukan.", true end
        if not getIsland() then return false, "Island tidak ditemukan:\n" .. CFG.ISLAND_NAME end
        local touch = getTouch()
        if not touch then return false, "TouchPart tidak ditemukan di HUB." end
        if not firetouchinterest then return false, "Executor tidak support firetouchinterest." end

        setInfo("Menyentuh TouchPart HUB...")
        touchPart(touch)
        task.wait(1.5)

        setInfo(("Teleport... menunggu %ds"):format(CFG.AfterDelay))
        task.wait(CFG.AfterDelay)

        -- tunggu slime muncul
        local target
        for _ = 1, math.max(1, math.floor(CFG.FindTimeout / 0.5)) do
            local hrp = getHRP()
            if hrp then target = pickTarget(hrp) end
            if target then break end
            task.wait(0.5)
        end
        return true
    end

    local function getGuardians()
        local island = getIsland()
        return (island and island:FindFirstChild("Guardians", true)) or workspace:FindFirstChild("Guardians", true)
    end

    local function slimeRank(model)
        local n = model.Name:lower()
        for i, key in ipairs(CFG.Priority) do
            if n:find(key, 1, true) then return i end
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

    -- prioritas warna dulu, baru yang paling dekat
    function pickTarget(hrp)
        local g = getGuardians()
        if not g then return nil, "Folder Guardians tidak ditemukan" end
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
        return best, g
    end

    local function equipWeapon()
        local r = getRemote("RequestEquipSlot")
        if r then pcall(function() r:FireServer("Weapon") end) end
        lastEquip = os.clock()
    end
local slashTrack, slashAnimator
local SWING_IDS = {"rbxassetid://86861921756773", "rbxassetid://89881700832616"}
local swingTracks, swingAnimator, swingIndex = {}, nil, 0

local function playSwingAnim()
    local c = LP.Character
    local hum = c and c:FindFirstChildOfClass("Humanoid")
    local animator = hum and hum:FindFirstChildOfClass("Animator")
    if not animator then return end

    -- muat ulang kalau animator berubah (respawn)
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
   local function swing()
    local r = getRemote("RequestSwing")
    if not r then setInfo("Remote RequestSwing tidak ditemukan!"); return end
    pcall(playSwingAnim)
    pcall(function() r:FireServer(table.unpack(CFG.SwingArgs)) end)
end

    local function applySpeed(hum)
        if hum.WalkSpeed ~= CFG.WalkSpeed then hum.WalkSpeed = CFG.WalkSpeed end
    end

    -- path dihitung ulang kalau tujuan geser jauh atau tiap 2 detik
    local walkPath = {wps = nil, i = 1, goal = nil, at = 0}
    local function stepTowards(hum, hrp, pos)
        local now = os.clock()
        if not walkPath.wps or not walkPath.goal
            or (pos - walkPath.goal).Magnitude > 6 or now - walkPath.at > 2 then
            local path = PathfindingService:CreatePath({AgentRadius = 2, AgentHeight = 5, AgentCanJump = true})
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
                hum:MoveTo(wp.Position)
                return
            end
        end
        hum:MoveTo(pos)
    end

    -- menghadap target cuma kalau arahnya sudah melenceng
    local function faceTarget(hrp, pos)
        local flat = Vector3.new(pos.X - hrp.Position.X, 0, pos.Z - hrp.Position.Z)
        if flat.Magnitude < 0.1 then return end
        local look = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
        if look.Magnitude < 0.01 or look.Unit:Dot(flat.Unit) < 0.94 then
            hrp.CFrame = CFrame.lookAt(hrp.Position, hrp.Position + flat)
        end
    end

    local function farmLoop(id)
        while active and runId == id do
            local hum, hrp = getChar()
            if Link.pause then
                setInfo("Dijeda, Auto Collect lagi jalan...")
                task.wait(0.3)
            elseif not hum then
                setInfo("Menunggu karakter...")
                task.wait(1)
            else
                local skipFarm = false
                if CFG.UseHub and not teleported and inLobby() then
                    teleported = true
                    setInfo("Sudah di Hub, jalan ke slime...")
                elseif CFG.UseHub and not teleported then
                    Link.hubBusy = true
                    local ok, why, retry = runHubTeleport()
                    Link.hubBusy = false
                    if ok then
                        teleported = true
                        equipWeapon()
                        task.wait(0.5)
                        setInfo("Teleport selesai.\nMenuju slime...")
                    elseif CFG.AutoHub or retry then
                        setInfo(why or "Teleport gagal, coba lagi...")
                        skipFarm = true
                        task.wait(1)
                    else
                        teleported = true
                        setInfo((why or "Teleport dilewati.") .. "\nLanjut jalan ke slime.")
                    end
                end

                if not skipFarm then
                    hum, hrp = getChar()
                    if hum then
                        applySpeed(hum)
                        if os.clock() - lastEquip > CFG.EquipEvery then equipWeapon() end

                        local target, g = pickTarget(hrp)
                        if not target then
                            -- belum ada slime, jalan ke tengah area guardians
                            local gp = typeof(g) == "Instance" and guardiansPos(g)
                            if gp and (gp - hrp.Position).Magnitude > CFG.AttackRange * 2 then
                                setInfo(("Mendekat ke area slime (%.0f studs)\nKill: %d"):format((gp - hrp.Position).Magnitude, kills))
                                stepTowards(hum, hrp, gp)
                                task.wait(0.1)
                            else
                                setInfo((type(g) == "string" and g) or ("Menunggu slime. Kill: " .. kills))
                                task.wait(1)
                            end
                        else
                            local rank = slimeRank(target)
                            local tag = CFG.Priority[rank]:upper()
                            local attacking, wasAttacking, lastCheck = false, false, 0
                            local stuckPos, stuckT = hrp.Position, os.clock()
                            while active and runId == id and isAlive(target) and not Link.pause do
                                local h, r = getChar()
                                if not h then break end
                                applySpeed(h)
                                if os.clock() - lastEquip > CFG.EquipEvery then equipWeapon() end
                                local tp = posOf(target)
                                if not tp then break end

                                -- ada slime yang prioritasnya lebih tinggi? cek 1x per detik
                                if os.clock() - lastCheck > 1 then
                                    lastCheck = os.clock()
                                    local better = pickTarget(r)
                                    if better and better ~= target and slimeRank(better) < rank then break end
                                end

                                -- mulai mukul di AttackRange, jalan lagi kalau lewat AttackRange + 3
                                local dist = (tp - r.Position).Magnitude
                                if attacking then
                                    attacking = dist <= CFG.AttackRange + 3
                                else
                                    attacking = dist <= CFG.AttackRange
                                end

                                if not attacking then
                                    wasAttacking = false
                                    local now = os.clock()
                                    if (r.Position - stuckPos).Magnitude > 2 then
                                        stuckPos, stuckT = r.Position, now
                                    elseif now - stuckT > CFG.StuckTime then
                                        skipped[target] = now + CFG.SkipFor
                                        walkPath.wps = nil
                                        setInfo(("Stuck menuju %s, cari target lain"):format(tag))
                                        break
                                    end
                                    setInfo(("Menuju %s (%.0f studs)\nKill: %d"):format(tag, dist, kills))
                                    stepTowards(h, r, tp)
                                    task.wait(0.1)
                                else
                                    stuckPos, stuckT = r.Position, os.clock()
                                    setInfo(("Memukul %s\nKill: %d"):format(tag, kills))
                                    if not wasAttacking then
                                        h:MoveTo(r.Position)
                                        wasAttacking = true
                                    end
                                    faceTarget(r, tp)
                                    swing()
                                    task.wait(CFG.SwingDelay)
                                end
                            end
                            if not isAlive(target) then kills += 1 end
                        end
                    end
                end
            end
            task.wait()
        end
        if not active then setInfo("Dimatikan. Kill: " .. kills) end
    end

    function Slime.IsActive() return active end
    function Slime.ResetHub() teleported = false; lastEquip = 0 end

    function Slime.Set(v)
        if v == active then return end
        active = v
        if v then
            if Tg.harvest then Tg.harvest.Set(false) end
            runId += 1
            equipWeapon()
            task.spawn(farmLoop, runId)
        end
    end
    onCleanup(function() active = false end)
end

-- overflow chest
do
    local CFG = ChestCFG
    local active, busy, runId = false, false, 0
    local lastMsg = "Siap."
    local function setInfo(t) if Chest.info then Chest.info.Text = t end end

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
        local island = workspace:FindFirstChild(CFG.ISLAND_NAME)
        if not island then
            for _, c in ipairs(workspace:GetChildren()) do
                if c.Name:find("^Island_" .. LP.UserId) then island = c break end
            end
        end
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

    local function findCollect()
        for _, o in ipairs(LP.PlayerGui:GetDescendants()) do
            if (o:IsA("TextLabel") or o:IsA("TextButton")) and o.Text:upper():find("COLLECT") and visible(o) then
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
        if not panel then return end
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

    -- balik ke home lewat TouchPart di model Hub
    local function goHome()
        if atHome() then return true end
        local m = workspace:FindFirstChild(CFG.HomeModel)
        local part = m and m:FindFirstChild(CFG.HomeTouchName, true)
        if not part or not firetouchinterest then return false end
        for _ = 1, 3 do
            local hrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
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
        return false
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
        local slimeOn = Slime.IsActive and Slime.IsActive()
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

        if slimeOn then
            Link.pause = true; paused = true
            local w = 0
            while Link.hubBusy and w < 12 do task.wait(0.25); w += 0.25 end
            task.wait(0.3)
            setInfo("Auto Slime dijeda, balik ke home...")
            if not goHome() then
                return finish(("Gagal balik ke home (cek %s > %s)."):format(CFG.HomeModel, CFG.HomeTouchName))
            end
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
                    task.wait(0.05); t += 0.05
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
                    runOnce()
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
        local _, island, blocks, total, fullCount = getPrompts()
        print("=== DEBUG CHEST ===")
        print("Island:", island and island:GetFullName() or "TIDAK ADA")
        print("Total chest:", total, "| FULL:", fullCount)
        print("getconnections:", getconnections ~= nil, "| firesignal:", firesignal ~= nil,
            "| fireproximityprompt:", fireproximityprompt ~= nil)
        local hm = workspace:FindFirstChild(CFG.HomeModel)
        local ht = hm and hm:FindFirstChild(CFG.HomeTouchName, true)
        print("Home model:", hm and hm:GetFullName() or "TIDAK ADA", "| TouchPart:", ht and ht:GetFullName() or "TIDAK ADA",
            "| atHome:", tostring(atHome()))
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
            for _, d in ipairs(panel:GetDescendants()) do
                if d:IsA("GuiButton") then
                    print("  ", d:GetFullName(), "| closeBtn:", tostring(isCloseBtn(d)))
                end
            end
        else
            print("(GUI chest lagi tertutup, buka satu chest manual lalu klik DEBUG lagi buat lihat tombol close)")
        end
        setInfo(("Total: %d | FULL: %d. Lihat console."):format(total, fullCount))
    end
end

-- auto harvest
do
    local C = HarvestCFG
    local autoFarm = false
    local blacklist = {}
    local firedCount = {}
    local target = nil
    local fireAcc, lastMove, lastScan, lastPos, lastPosTime = 0, 0, 0, nil, 0
    local function setInfo(t) if Harvest.info then Harvest.info.Text = t end end

    local function refs()
        local c = LP.Character
        return c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("HumanoidRootPart")
    end

    local remoteCache
    local function harvestRemote()
        if remoteCache and remoteCache.Parent then return remoteCache end
        local remotes = RS:FindFirstChild("Remotes")
        remoteCache = remotes and remotes:FindFirstChild("RequestHarvest")
        return remoteCache
    end

    local function findNearest(rootPart)
        local now = tick()
        local best, bestDist = nil, math.huge
        local fallback, fallbackExp = nil, math.huge
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj.Name == "BerryBush" then
                local hb = obj:FindFirstChild("HB")
                if hb and hb:IsA("BasePart") then
                    local exp = blacklist[hb]
                    if exp and exp > now then
                        if exp < fallbackExp then fallbackExp, fallback = exp, hb end
                    else
                        local d = (rootPart.Position - hb.Position).Magnitude
                        if d < bestDist then bestDist, best = d, hb end
                    end
                end
            end
        end
        return best or fallback
    end

    function Harvest.Set(v)
        if v == autoFarm then return end
        autoFarm = v
        target = nil
        fireAcc = 0
        if v then
            if Tg.slime then Tg.slime.Set(false) end
            setInfo("Berjalan...")
        else
            setInfo("Idle")
            local h, r = refs()
            if h and r then pcall(function() h:MoveTo(r.Position) end) end
        end
    end

    local conn = RunService.Heartbeat:Connect(function(dt)
        if not autoFarm then return end
        local humanoid, rootPart = refs()
        if not (humanoid and rootPart) then return end
        humanoid.WalkSpeed = C.WalkSpeed

        local now = tick()

        if (not target) or (not target:IsDescendantOf(workspace)) then
            target = nil
            if now - lastScan >= 0.15 then
                lastScan = now
                target = findNearest(rootPart)
                lastPos = nil
            end
            if not target then
                setInfo("Mencari BerryBush...")
                return
            end
        end

        local dist = (rootPart.Position - target.Position).Magnitude
        local manual = UIS:IsKeyDown(Enum.KeyCode.W) or UIS:IsKeyDown(Enum.KeyCode.A)
            or UIS:IsKeyDown(Enum.KeyCode.S) or UIS:IsKeyDown(Enum.KeyCode.D)

        -- terus jalan ke semak, tidak berhenti waktu harvest
        if not manual and now - lastMove >= 0.1 then
            lastMove = now
            pcall(function() humanoid:MoveTo(target.Position) end)
        end

        if dist <= C.Radius then
            fireAcc = fireAcc + dt * C.PerSecond
            while fireAcc >= 1 do
                fireAcc = fireAcc - 1
                firedCount[target] = (firedCount[target] or 0) + 1
                pcall(function()
                    local r = harvestRemote()
                    if r then r:FireServer(target) end
                end)
            end
            setInfo(("Harvest %d/%d"):format(firedCount[target] or 0, C.FireLimitPerBush))

            if (firedCount[target] or 0) >= C.FireLimitPerBush then
                blacklist[target] = now + C.BlacklistTime
                firedCount[target] = 0
                target = nil
                fireAcc = 0
            end
        else
            fireAcc = 0
            setInfo("Jalan ke Berry Bush...")

            -- stuck, teleport dekat semak
            if lastPos == nil or (rootPart.Position - lastPos).Magnitude > 1 then
                lastPos = rootPart.Position
                lastPosTime = now
            elseif C.TeleportFallback and now - lastPosTime >= C.StuckTime then
                local dir = rootPart.Position - target.Position
                dir = (dir.Magnitude > 0) and dir.Unit or Vector3.new(1, 0, 0)
                rootPart.CFrame = CFrame.new(target.Position + dir * (C.Radius - 4) + Vector3.new(0, 3, 0))
                lastPos = nil
            end
        end
    end)

    local keyConn = UIS.InputBegan:Connect(function(input, gp)
        if gp then return end
        if input.KeyCode == Enum.KeyCode.E and Tg.harvest then Tg.harvest.Set(not Tg.harvest.Get()) end
    end)

    onCleanup(function()
        autoFarm = false
        conn:Disconnect()
        keyConn:Disconnect()
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
        if DC.fired then return end
        if not hard then
            task.wait(2)
            if not DC.confirm() then return end
        end
        if DC.fired then return end
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
            for _, nm in ipairs({LP.Name, tostring(LP.UserId)}) do
                local ok, o = pcall(function() return RS:FindFirstChild(nm, true) end)
                if ok and o then scanRoot(o, inv) end
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
        if os.clock() - guiCache.t > 6 then guiCache.t = os.clock(); guiCache.v = readGui() end
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
        if Tg.chest and Tg.chest.Get() then t[#t + 1] = "Auto Collect" end
        if Tg.harvest and Tg.harvest.Get() then t[#t + 1] = "Auto Harvest" end
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
        local since = 0
        while alive do
            task.wait(2)
            since += 2
            if not DC.fired and since >= 20 then
                since = 0
                writeSession("online")
            end
            if master and not DC.fired then
                pcall(tickItems)
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
        if not fsOK() or not isfile(AUTO_FILE) then return nil end
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

    function Sys.Load(nameArg, silent)
        if not fsOK() then notify("Executor tidak support file (writefile/readfile)."); return false end
        local name = clean(nameArg)
        if name == "" then name = CfgUI.list.selected or clean(CfgUI.name.Get()) end
        if name == "" then notify("Pilih config yang mau di-load dulu."); return false end
        if not isfile(pathOf(name)) then notify("Config tidak ditemukan: " .. name); return false end
        local ok, data = pcall(function() return HttpService:JSONDecode(readfile(pathOf(name))) end)
        if not ok or type(data) ~= "table" then notify("Config rusak / tidak bisa dibaca."); return false end
        -- angka dan teks dulu, baru toggle, supaya fitur nyala dengan nilai yang benar
        for k, c in pairs(Controls) do
            if c.kind ~= "toggle" and data[k] ~= nil then pcall(c.set, data[k]) end
        end
        for k, c in pairs(Controls) do
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

-- penutup
CloseBtn.Activated:Connect(function() getgenv().KyHub_Cleanup() end)

getgenv().KyHub_Cleanup = function()
    for _, f in ipairs(cleanups) do pcall(f) end
    pcall(function() Gui:Destroy() end)
end

selectTab("Auto Slime")
for _, f in ipairs(Deferred) do pcall(f) end

Sys.Refresh()

task.spawn(function()
    -- tunggu island dan Remotes muncul (maks 30 detik)
    local t0 = os.clock()
    while os.clock() - t0 < 30 do
        if workspace:FindFirstChild(SlimeCFG.ISLAND_NAME) and RS:FindFirstChild("Remotes") then break end
        task.wait(0.5)
    end
    task.wait(2)

    local autoName = Sys.GetAuto()
    if autoName and Sys.Load(autoName, true) then
        notify("Auto Load: " .. autoName)
    else
        notify("KyHub siap.")
    end

    Webhook.OnStart()
end)
