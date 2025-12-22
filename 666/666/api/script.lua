-- VORAHUB 2026 KEYSYSTEM – FIXED AUTO-REDEEM BUG
-- Fix: Tidak lagi coba bind jika _G.script_key kosong/invalid

local API_KEY = "AIzaSyDSzv4tvzV8oxk4TVVacAa54F-KS2kBQoM"
local PROJECT_ID = "vorahub-3e462"
local BASE = "https://firestore.googleapis.com/v1/projects/"..PROJECT_ID.."/databases/(default)/documents"

local Http = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local Players = game:GetService("Players")
local Tween = game:GetService("TweenService")
local RbxAnalyticsService = game:GetService("RbxAnalyticsService")
local LocalPlayer = Players.LocalPlayer

-- Universal HTTP request
local function request(url, method, body)
    local success, response = pcall(function()
        local req
        if syn and syn.request then
            req = syn.request
        elseif http_request then
            req = http_request
        elseif request then
            req = request
        else
            return method == "POST" and Http:PostAsync(url, body or "", Enum.HttpContentType.ApplicationJson)
                or Http:GetAsync(url)
        end
        local res = req({
            Url = url,
            Method = method or "GET",
            Headers = {["Content-Type"] = "application/json"},
            Body = body
        })
        return res.Body or res
    end)
    if success then
        return response
    else
        warn("[VORAHUB] HTTP Request failed: ", response)
        return nil
    end
end

-- Ambil HWID
local HWID = RbxAnalyticsService:GetClientId()

-- Log + copy HWID
print("\n========================================")
print("VORAHUB 2026 - HWID LOG")
print("HWID: " .. HWID)
print("========================================\n")

setclipboard(HWID)
StarterGui:SetCore("SendNotification", {
    Title = "VORAHUB",
    Text = "HWID telah di-copy ke clipboard!",
    Duration = 5,
    Icon = "rbxassetid://6031075938"
})

-- Fungsi redeem (tetap sama, sudah aman dengan updateMask)
local function redeem(key)
    key = key:gsub("%s+", ""):upper()
    if #key < 6 then
        StarterGui:SetCore("SendNotification", {
            Title = "VORAHUB",
            Text = "Key terlalu pendek atau kosong!",
            Duration = 5,
            Icon = "rbxassetid://6031082533"
        })
        return false
    end

    StarterGui:SetCore("SendNotification", {
        Title = "VORAHUB",
        Text = "Memeriksa key...",
        Duration = 8,
        Icon = "rbxassetid://6031075938"
    })

    local data = request(BASE.."/keys/"..key.."?key="..API_KEY)
    if not data then
        StarterGui:SetCore("SendNotification", {
            Title = "VORAHUB",
            Text = "Gagal terhubung ke server!",
            Duration = 6,
            Icon = "rbxassetid://6031082533"
        })
        return false
    end

    local success, json = pcall(function() return Http:JSONDecode(data) end)
    if not success or not json.fields then
        StarterGui:SetCore("SendNotification", {
            Title = "VORAHUB",
            Text = "Key tidak valid atau error server!",
            Duration = 6,
            Icon = "rbxassetid://6031082533"
        })
        return false
    end

    local isUsed = json.fields.used and json.fields.used.booleanValue or false
    local boundHWID = json.fields.hwid and json.fields.hwid.stringValue or ""

    if isUsed then
        if boundHWID == HWID then
            StarterGui:SetCore("SendNotification", {
                Title = "VORAHUB 2026",
                Text = "Key valid! Loading script...",
                Duration = 5,
                Icon = "rbxassetid://6031075938"
            })
            task.wait(2)
            StarterGui:SetCore("SendNotification", {
                Title = "LOADED!",
                Text = "Selamat datang, "..LocalPlayer.Name.."!",
                Duration = 6,
                Icon = "rbxassetid://6031075938"
            })
            return true
        else
            StarterGui:SetCore("SendNotification", {
                Title = "ACCESS DENIED",
                Text = "Key terikat ke device lain!",
                Duration = 8,
                Icon = "rbxassetid://6031082533"
            })
            task.wait(3)
            LocalPlayer:Kick("\n[VORAHUB 2026]\nKey ini sudah digunakan di device lain.\nHWID kamu: "..HWID.."\nKirim HWID ke admin Discord untuk reset.")
            return false
        end
    end

    -- Bind key baru (hanya update field tertentu)
    local updateFields = {
        used = { booleanValue = true },
        usedBy = { stringValue = LocalPlayer.Name },
        hwid = { stringValue = HWID },
        usedAt = { timestampValue = os.date("!%Y-%m-%dT%H:%M:%SZ") }
    }

    local bodyTable = {
        writes = {{
            update = {
                name = "projects/" .. PROJECT_ID .. "/databases/(default)/documents/keys/" .. key,
                fields = updateFields
            },
            updateMask = {
                fieldPaths = { "used", "usedBy", "hwid", "usedAt" }
            }
        }}
    }

    local body = Http:JSONEncode(bodyTable)
    local commitResponse = request(BASE .. "/:commit?key=" .. API_KEY, "POST", body)

    local commitSuccess, commitJson = pcall(function() return Http:JSONDecode(commitResponse or "") end)
    if not commitResponse or not commitSuccess or (commitJson.commitResponse and not commitJson.commitResponse.success) then
        StarterGui:SetCore("SendNotification", {
            Title = "VORAHUB",
            Text = "Gagal bind key! Coba lagi nanti.",
            Duration = 6,
            Icon = "rbxassetid://6031082533"
        })
        return false
    end

    StarterGui:SetCore("SendNotification", {
        Title = "VORAHUB 2026",
        Text = "Key berhasil di-activate!\nLoading script...",
        Duration = 5,
        Icon = "rbxassetid://6031075938"
    })
    task.wait(2)
    StarterGui:SetCore("SendNotification", {
        Title = "LOADED!",
        Text = "Selamat datang, "..LocalPlayer.Name.."!",
        Duration = 6,
        Icon = "rbxassetid://6031075938"
    })
    return true
end

-- ==================== UI PREMIUM ====================
local sg = Instance.new("ScreenGui")
sg.Parent = game:GetService("CoreGui")
sg.ResetOnSpawn = false

local main = Instance.new("Frame", sg)
main.Size = UDim2.new(0, 460, 0, 340)
main.Position = UDim2.new(0.5, -230, 0.5, -170)
main.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
main.BorderSizePixel = 0
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 24)

local grad = Instance.new("UIGradient", main)
grad.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 10, 100)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 10, 30))
}
grad.Rotation = 135

local stroke = Instance.new("UIStroke", main)
stroke.Color = Color3.fromRGB(120, 80, 255)
stroke.Thickness = 3

-- ... (semua UI element sama seperti sebelumnya) ...
-- (title, box, redeemBtn, getkeyBtn, status – tetap sama)

local title = Instance.new("TextLabel", main)
title.Text = "VORAHUB 2026"
title.Size = UDim2.new(1, 0, 0, 90)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.fromRGB(180, 120, 255)
title.Font = Enum.Font.GothamBlack
title.TextSize = 48

local box = Instance.new("TextBox", main)
box.PlaceholderText = "Masukkan key disini..."
box.Position = UDim2.new(0.08, 0, 0, 100)
box.Size = UDim2.new(0.84, 0, 0, 65)
box.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
box.TextColor3 = Color3.new(1, 1, 1)
box.Font = Enum.Font.GothamBold
box.TextSize = 28
box.ClearTextOnFocus = false
Instance.new("UICorner", box).CornerRadius = UDim.new(0, 16)

local redeemBtn = Instance.new("TextButton", main)
redeemBtn.Text = "REDEEM KEY"
redeemBtn.Position = UDim2.new(0.08, 0, 0, 180)
redeemBtn.Size = UDim2.new(0.84, 0, 0, 75)
redeemBtn.Font = Enum.Font.GothamBlack
redeemBtn.TextSize = 34
redeemBtn.TextColor3 = Color3.new(1, 1, 1)
local rg = Instance.new("UIGradient", redeemBtn)
rg.Color = ColorSequence.new{
    ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 50, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 0, 200))
}
Instance.new("UICorner", redeemBtn).CornerRadius = UDim.new(0, 20)

local getkeyBtn = Instance.new("TextButton", main)
getkeyBtn.Text = "GET KEY (DISCORD)"
getkeyBtn.Position = UDim2.new(0.08, 0, 0, 270)
getkeyBtn.Size = UDim2.new(0.84, 0, 0, 55)
getkeyBtn.BackgroundColor3 = Color3.fromRGB(88, 101, 242)
getkeyBtn.Font = Enum.Font.GothamBold
getkeyBtn.TextSize = 28
getkeyBtn.TextColor3 = Color3.new(1, 1, 1)
Instance.new("UICorner", getkeyBtn).CornerRadius = UDim.new(0, 16)

local status = Instance.new("TextLabel", main)
status.Position = UDim2.new(0, 0, 0.85, 0)
status.Size = UDim2.new(1, 0, 0.12, 0)
status.BackgroundTransparency = 1
status.TextColor3 = Color3.fromRGB(200, 200, 255)
status.Font = Enum.Font.Gotham
status.TextSize = 22
status.Text = "Masukkan key untuk melanjutkan"

-- Animasi
main.Position = UDim2.new(0.5, -230, -0.5, 0)
Tween:Create(main, TweenInfo.new(0.8, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
    Position = UDim2.new(0.5, -230, 0.5, -170)
}):Play()

-- === PERBAIKAN UTAMA: Auto redeem yang lebih aman ===
if _G.script_key and typeof(_G.script_key) == "string" then
    local cleanedKey = _G.script_key:gsub("%s+", ""):upper()
    if #cleanedKey >= 6 then
        box.Text = _G.script_key
        task.spawn(function()
            task.wait(1.5)
            if redeem(cleanedKey) then
                task.wait(3)
                sg:Destroy()
                loadstring(game:HttpGet("https://raw.githubusercontent.com/Andrazx23/vorahub/refs/heads/main/main.lua"))()
            end
        end)
    else
        -- Key kosong atau terlalu pendek → skip auto-redeem, UI tetap muncul
        print("[VORAHUB] Auto-redeem skipped: _G.script_key invalid atau kosong")
    end
else
    print("[VORAHUB] No valid _G.script_key found")
end

-- Manual redeem
redeemBtn.MouseButton1Click:Connect(function()
    if redeem(box.Text) then
        task.wait(3)
        sg:Destroy()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/Andrazx23/vorahub/refs/heads/main/main.lua"))()
    end
end)

-- Get key
getkeyBtn.MouseButton1Click:Connect(function()
    setclipboard("https://discord.gg/vorahub")
    StarterGui:SetCore("SendNotification", {
        Title = "VORAHUB",
        Text = "Link Discord di-copy ke clipboard!",
        Duration = 4
    })
end)

-- Anti destroy
sg.DescendantRemoving:Connect(function(child)
    if child == sg then
        task.spawn(function()
            while task.wait(0.1) do
                if not sg.Parent then
                    LocalPlayer:Kick("[VORAHUB] Jangan hapus key system!")
                end
            end
        end)
    end
end)
