local PathfindingService = game:GetService("PathfindingService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")

local SmartDoor = {} 
SmartDoor.CurrentWalkId = 0 
local lastDoorClick = 0

if _G.MostrarBolinhas == nil then _G.MostrarBolinhas = true end

-- Função de Log
local function LogSD(msg)
    if _G.StatusTextoTeste then _G.StatusTextoTeste.Text = msg end
    print("[SmartDoor] " .. msg)
end

-- ==========================================
-- 🔴 ROTA VISUAL (DISCOS HOLOGRÁFICOS)
-- ==========================================
local function DesenharCaminho(waypoints)
    local folder = workspace:FindFirstChild("CaminhoSmartDoor")
    if folder then folder:Destroy() end
    
    if not _G.MostrarBolinhas then return {} end

    folder = Instance.new("Folder")
    folder.Name = "CaminhoSmartDoor"
    folder.Parent = workspace

    local parts = {}
    for i, wp in ipairs(waypoints) do
        local part = Instance.new("Part")
        part.Size = Vector3.new(1.4, 0.05, 1.4) 
        part.Position = wp.Position + Vector3.new(0, 0.15, 0) 
        part.Anchored = true
        part.CanCollide = false
        part.Material = Enum.Material.Neon
        part.Color = Color3.fromRGB(0, 200, 255) 
        part.Shape = Enum.PartType.Cylinder
        part.Orientation = Vector3.new(0, 0, 90) 
        part.Parent = folder

        local light = Instance.new("PointLight")
        light.Color = part.Color
        light.Range = 5
        light.Brightness = 1.5
        light.Parent = part
        
        parts[i] = part
    end
    
    return parts 
end

local function EfeitoSumir(part)
    if not part then return end
    local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local tween = TweenService:Create(part, tweenInfo, {Size = Vector3.new(0, 0, 0), Transparency = 1})
    tween:Play()
    game.Debris:AddItem(part, 0.35)
end

-- ==========================================
-- 🗺️ FANTASMAS (ATRAVESSA PORTAS NO GPS)
-- ==========================================
local function PrepararFisica(estado, alvo)
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return end

    for _, plot in pairs(plots:GetChildren()) do
        local house = plot:FindFirstChild("House")
        if house then
            for _, part in pairs(house:GetDescendants()) do
                if part:IsA("BasePart") then
                    local isDoor = false
                    local atual = part
                    while atual and atual ~= house do
                        local name = string.lower(atual.Name)
                        if string.find(name, "door") or string.find(name, "gate") then
                            isDoor = true
                            break
                        end
                        atual = atual.Parent
                    end

                    if isDoor then
                        if estado == "LIGAR" and not part:FindFirstChild("IgnorarGPS_Porta") then
                            local mod = Instance.new("PathfindingModifier")
                            mod.Name = "IgnorarGPS_Porta"
                            mod.PassThrough = true
                            mod.Parent = part
                        elseif estado == "DESLIGAR" and part:FindFirstChild("IgnorarGPS_Porta") then
                            if part:FindFirstChild("IgnorarGPS_Porta") then part.IgnorarGPS_Porta:Destroy() end
                        end
                    end
                end
            end
        end
    end

    if alvo then
        local model = alvo:FindFirstAncestorWhichIsA("Model") or alvo
        for _, part in pairs(model:GetDescendants()) do
            if part:IsA("BasePart") then
                if estado == "LIGAR" and not part:FindFirstChild("IgnorarGPS_Alvo") then
                    local mod = Instance.new("PathfindingModifier")
                    mod.Name = "IgnorarGPS_Alvo"
                    mod.PassThrough = true
                    mod.Parent = part
                elseif estado == "DESLIGAR" and part:FindFirstChild("IgnorarGPS_Alvo") then
                    if part:FindFirstChild("IgnorarGPS_Alvo") then part.IgnorarGPS_Alvo:Destroy() end
                end
            end
        end
    end
end

-- ==========================================
-- 👁️ ABRIR PORTA (VERSÃO ESTÁVEL COM FREIO E PAUSA)
-- ==========================================
local function TentarAbrirPorta()
    local p = Players.LocalPlayer
    local char = p.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return false end
    
    local texto, botao = nil, nil

    pcall(function()
        local interactUI = p.PlayerGui:FindFirstChild("_interactUI")
        if interactUI then
            local indicator = interactUI:FindFirstChild("InteractIndicator")
            if indicator and indicator.Visible then
                local label = indicator:FindFirstChild("TextLabel")
                if label and label.Text ~= "" then
                    texto = string.lower(label.Text)
                    botao = indicator
                end
            end
        end
    end)
    
    if texto then
        if texto:find("open") or texto:find("abrir") then
            if tick() - lastDoorClick > 0.8 then
                lastDoorClick = tick()
                
                LogSD("🚪 Porta detectada. Abrindo...")
                
                -- Freia para garantir a interação sem bugar
                char.Humanoid:MoveTo(char.HumanoidRootPart.Position)
                
                if botao and getconnections then
                    for _, c in pairs(getconnections(botao.MouseButton1Click)) do c:Fire() end
                    for _, c in pairs(getconnections(botao.Activated)) do c:Fire() end
                end
                
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                task.wait(0.1)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                
                task.wait(0.4) -- Pausa rápida pra porta abrir e ele não bater a cara
                return true
            end
        elseif texto:find("close") or texto:find("fechar") then
            return false 
        end
    end
    
    return false 
end

-- ==========================================
-- 🎯 RADAR: ACHA A FRENTE DO MÓVEL
-- ==========================================
local function ObterPosicaoNaFrente(alvoPart)
    local pos = alvoPart.Position
    local cf = alvoPart.CFrame
    local direcoes = {cf.LookVector, -cf.LookVector, cf.RightVector, -cf.RightVector}
    local melhorDirecao = Vector3.new(0, 0, 1)
    local maiorEspacoLivre = -1
    
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    rp.FilterDescendantsInstances = {Players.LocalPlayer.Character, alvoPart.Parent}
    
    for _, dir in ipairs(direcoes) do
        local resultado = workspace:Raycast(pos, dir * 10, rp)
        local dist = resultado and (resultado.Position - pos).Magnitude or 10
        if dist > maiorEspacoLivre then
            maiorEspacoLivre = dist
            melhorDirecao = dir
        end
    end
    
    local alvoFinal = pos + (melhorDirecao * 1.8)
    return Vector3.new(alvoFinal.X, Players.LocalPlayer.Character.HumanoidRootPart.Position.Y, alvoFinal.Z)
end

-- ==========================================
-- 🚶 MOTOR DE CAMINHADA
-- ==========================================
function SmartDoor.IrPara(destino)
    SmartDoor.CurrentWalkId = SmartDoor.CurrentWalkId + 1
    local myId = SmartDoor.CurrentWalkId

    local char = Players.LocalPlayer.Character
    if not char or not char:FindFirstChild("Humanoid") then return false end
    local hum = char.Humanoid
    local hrp = char.HumanoidRootPart

    local alvoPart = destino:IsA("Model") and (destino.PrimaryPart or destino:FindFirstChildWhichIsA("BasePart", true)) or destino
    local targetPos = ObterPosicaoNaFrente(alvoPart)

    LogSD("1. Preparando Motor...")
    PrepararFisica("LIGAR", destino)
    task.wait(0.1)

    local path = PathfindingService:CreatePath({
        AgentRadius = 0.8, 
        AgentHeight = 5, 
        AgentCanJump = true, 
        WaypointSpacing = 3
    })
    
    path:ComputeAsync(hrp.Position, targetPos)
    PrepararFisica("DESLIGAR", destino)

    if path.Status ~= Enum.PathStatus.Success then
        LogSD("❌ GPS Falhou: " .. tostring(path.Status))
        return false
    end

    local waypoints = path:GetWaypoints()
    LogSD("✅ Rota encontrada! Andando...")
    local bolinhas = DesenharCaminho(waypoints)

    for i, wp in ipairs(waypoints) do
        if SmartDoor.CurrentWalkId ~= myId then break end
        
        if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
        hum:MoveTo(wp.Position)

        local timeout = tick()
        local checkStuck = tick()
        local lastPos = hrp.Position

        while true do
            if SmartDoor.CurrentWalkId ~= myId then break end
            
            -- Ignora a altura pra não bugar a distância
            local pPos = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
            local wPos = Vector3.new(wp.Position.X, 0, wp.Position.Z)
            
            local tolerancia = (i == #waypoints) and 1.2 or 2.2
            if (pPos - wPos).Magnitude <= tolerancia then
                EfeitoSumir(bolinhas[i])
                break 
            end

            if TentarAbrirPorta() then
                hum:MoveTo(wp.Position)
            end

            -- ANTI-TRAVAMENTO
            if tick() - checkStuck > 1.0 then
                if (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(lastPos.X, 0, lastPos.Z)).Magnitude < 0.5 then 
                    hum.Jump = true
                    hum:MoveTo(wp.Position)
                end
                lastPos = hrp.Position
                checkStuck = tick()
            end

            if tick() - timeout > 4 then break end
            task.wait()
        end
    end

    local distFinal = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
    if distFinal < 6.5 then
        hum:MoveTo(hrp.Position)
        LogSD("🎯 Destino Alcançado!")
        return true
    end
    
    LogSD("⚠️ Rota terminou, mas ficou longe.")
    return false
end

function SmartDoor.Cancelar()
    SmartDoor.CurrentWalkId = SmartDoor.CurrentWalkId + 1
    LogSD("🚫 Caminhada cancelada.")
    local folder = workspace:FindFirstChild("CaminhoSmartDoor")
    if folder then folder:Destroy() end
end

-- ==========================================
-- 🖥️ GUI DE TESTE
-- ==========================================
if CoreGui:FindFirstChild("TestSmartDoorGUI") then
    CoreGui:FindFirstChild("TestSmartDoorGUI"):Destroy()
end

local sg = Instance.new("ScreenGui")
sg.Name = "TestSmartDoorGUI"
sg.Parent = CoreGui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 220, 0, 330)
frame.Position = UDim2.new(0.5, -110, 0.2, 0)
frame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
frame.BorderSizePixel = 2
frame.Active = true
frame.Draggable = true
frame.Parent = sg

local layout = Instance.new("UIListLayout")
layout.Parent = frame
layout.Padding = UDim.new(0, 8)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Center

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.new(1,1,1)
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.Text = "TESTE DE ROTAS"
title.Parent = frame

local statusLog = Instance.new("TextLabel")
statusLog.Size = UDim2.new(0, 200, 0, 40)
statusLog.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
statusLog.TextColor3 = Color3.fromRGB(255, 200, 50)
statusLog.Font = Enum.Font.Code
statusLog.TextSize = 12
statusLog.TextWrapped = true
statusLog.Text = "Aguardando..."
statusLog.Parent = frame
_G.StatusTextoTeste = statusLog

local btnVis = Instance.new("TextButton")
btnVis.Size = UDim2.new(0, 180, 0, 30)
btnVis.BackgroundColor3 = _G.MostrarBolinhas and Color3.fromRGB(40, 150, 40) or Color3.fromRGB(150, 40, 40)
btnVis.TextColor3 = Color3.new(1,1,1)
btnVis.Font = Enum.Font.GothamBold
btnVis.TextSize = 12
btnVis.Text = _G.MostrarBolinhas and "👁️ ROTA VISUAL [ON]" or "👁️ ROTA VISUAL [OFF]"
btnVis.Parent = frame
Instance.new("UICorner").Parent = btnVis

btnVis.MouseButton1Click:Connect(function()
    _G.MostrarBolinhas = not _G.MostrarBolinhas
    btnVis.BackgroundColor3 = _G.MostrarBolinhas and Color3.fromRGB(40, 150, 40) or Color3.fromRGB(150, 40, 40)
    btnVis.Text = _G.MostrarBolinhas and "👁️ ROTA VISUAL [ON]" or "👁️ ROTA VISUAL [OFF]"
    
    if not _G.MostrarBolinhas then
        local folder = workspace:FindFirstChild("CaminhoSmartDoor")
        if folder then folder:Destroy() end
    end
end)

local function EncontrarMovel(tipo)
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    
    local char = Players.LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return nil end
    local myPos = char.HumanoidRootPart.Position
    
    local nearestObj = nil
    local nearestDist = math.huge

    LogSD("Buscando na casa...")

    -- VOLTOU PARA A BUSCA LEVE NA PASTA 'Counters' (Mais segura)
    for _, plot in pairs(plots:GetChildren()) do
        if plot:FindFirstChild("House") and plot.House:FindFirstChild("Counters") then
            for _, obj in pairs(plot.House.Counters:GetChildren()) do
                local name = string.lower(obj.Name)
                local isMatch = false
                
                if tipo == "Fridge" and (name:find("fridge") or name:find("refrigerator") or name:find("icebox")) then isMatch = true end
                if tipo == "Stove" and (name:find("stove") or name:find("oven") or name:find("cook")) then isMatch = true end
                if tipo == "Cover" and (name:find("counter") or name:find("island") or name:find("cabinet")) then isMatch = true end

                if isMatch then
                    local alvoPart = obj
                    local objModel = obj:FindFirstChild("ObjectModel")
                    if objModel then
                        alvoPart = objModel:FindFirstChild("OvenDoor") or objModel:FindFirstChild("MainDoor") or objModel:FindFirstChild("Door") or objModel
                    end
                    
                    local partParaMedir = alvoPart:IsA("Model") and (alvoPart.PrimaryPart or alvoPart:FindFirstChildWhichIsA("BasePart", true)) or alvoPart
                    
                    if partParaMedir and partParaMedir:IsA("BasePart") then
                        local dist = (myPos - partParaMedir.Position).Magnitude
                        if dist < nearestDist then
                            nearestDist = dist
                            nearestObj = alvoPart
                        end
                    end
                end
            end
        end
    end
    return nearestObj
end

local function CriarBotaoTeste(label, busca)
    local b = Instance.new("TextButton")
    b.Size = UDim2.new(0, 180, 0, 40)
    b.Text = label
    b.BackgroundColor3 = Color3.fromRGB(0, 120, 200)
    b.TextColor3 = Color3.fromRGB(255, 255, 255)
    b.Font = Enum.Font.SourceSansBold
    b.TextSize = 16
    b.Parent = frame
    Instance.new("UICorner").Parent = b

    b.MouseButton1Click:Connect(function()
        if b.Text == "Andando..." then return end 
        b.Text = "Procurando..."
        
        task.spawn(function()
            local success, alvo = pcall(function()
                return EncontrarMovel(busca)
            end)
            
            if not success or not alvo then
                b.Text = label
                LogSD("❌ Erro ou Móvel não achado.")
                return
            end
            
            b.Text = "Andando..."
            LogSD("Alvo localizado. Acionando GPS...")
            SmartDoor.IrPara(alvo)
            b.Text = label 
        end)
    end)
end

CriarBotaoTeste("❄️ GELADEIRA", "Fridge")
CriarBotaoTeste("🔥 FOGÃO", "Stove")
CriarBotaoTeste("🔪 BANCADA", "Cover")

return SmartDoor
