-- BokHub Universal Loader v2.0
-- Fixed ID Detection & Error Handling

local Games = {
    -- Murder Mystery 2
    [142823291] = { 
        Name = "Murder Mystery 2", 
        Url = "https://raw.githubusercontent.com/AzkaFajril/123123213/refs/heads/main/mm2" 
    },

     [13772394625] = { 
        Name = "Blade-Ball ",
        Url = "https://raw.githubusercontent.com/AzkaFajril/123123213/refs/heads/main/bb" 
    },
    
    -- ABOVE (Beberapa kemungkinan ID)
    [12435783578554] = { 
        Name = "ABOVE", 
        Url = "https://raw.githubusercontent.com/AzkaFajril/123123213/refs/heads/main/Above" 
    },
    [1243578357855] = { -- ID Pendek (jika ada typo di ID panjang)
        Name = "ABOVE", 
        Url = "https://raw.githubusercontent.com/AzkaFajril/123123213/refs/heads/main/Above" 
    },
}

local function Notify(Text)
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "BokHub Loader",
            Text = Text,
            Duration = 5
        })
    end)
end

local GameId = game.GameId
local Info = Games[GameId]

-- Jika ID tidak ditemukan, coba cek nama game sebagai backup (opsional)
if not Info then
    -- Cek manual jika ID berubah-ubah
    if game.PlaceId == 142823291 then
        Info = Games[142823291]
    elseif string.find(game.PlaceId, "124357") then -- Deteksi parsial untuk ABOVE
         Info = Games[12435783578554] -- Gunakan ID default ABOVE
    end
end

if not Info then
    Notify("Game ID " .. tostring(GameId) .. " tidak didukung.")
    warn("[BokHub] Game ID " .. tostring(GameId) .. " is not in the supported list.")
    print("Silakan hubungi developer untuk menambahkan ID ini.")
    return
end

Notify("Loading " .. Info.Name .. "...")

local Success, Error = pcall(function()
    -- Coba ambil script dari GitHub
    local ScriptContent = game:HttpGet(Info.Url)
    
    -- Cek apakah respons kosong atau error HTML
    if ScriptContent == "" or string.find(ScriptContent, "404: Not Found") then
        error("File script tidak ditemukan di GitHub (404).")
    end
    
    local RunScript = loadstring(ScriptContent)
    
    if RunScript then
        RunScript()
    else
        error("Gagal memuat script: Syntax error atau file kosong.")
    end
end)

if not Success then
    Notify("Gagal memuat script!")
    warn("[BokHub] Error loading " .. Info.Name .. ": " .. tostring(Error))
    print("Pastikan link GitHub benar dan file tersebut ada.")
else
    Notify(Info.Name .. " Loaded Successfully!")
end
