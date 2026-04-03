local PathfindingService = game:GetService("PathfindingService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")

local SmartDoor = {} 
SmartDoor.CurrentWalkId = 0 
local lastDoorClick = 0
_G.StatusTextoTeste = nil

local function LogSD(msg)
    if _G.StatusTextoTeste then _G.StatusTextoTeste.Text = msg end
    if _G.BloxburgChef_AddLog then _G.BloxburgChef_AddLog(msg, Color3.fromRGB(255, 170, 0)) end
    print("[SmartDoor] " .. msg)
end

-- ==========================================
-- 🗺️ CONFIGURAÇÃO DE GPS (UMA ÚNICA VEZ)
-- ==========================================
-- Isso evita o erro de "set the parent" que estava crashando seu executor
local function ConfigurarMapaUmaVez()
    if _G.MapaBloxburgConfigurado then return end
    
    LogSD("Configurando Mapa (Isso só acontece 1 vez)...")
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return end

    pcall(function()
        for _, plot in pairs(plots:GetChildren()) do
            local house = plot:FindFirstChild("House")
            if house then
                -- 1. Ignorar Portas no GPS permanentemente
                for _, obj in pairs(house:GetDescendants()) do
                    if obj:IsA("Model") and (string.find(string.lower(obj.Name), "door") or string.find(string.lower(obj.Name), "gate")) then
                        for _, part in pairs(obj:GetDescendants()) do
                            if part:IsA("BasePart") and not part:FindFirstChild("IgnorarNoGPS") then
                                local mod = Instance.new("PathfindingModifier")
                                mod.Name = "IgnorarNoGPS"
                                mod.PassThrough = true
                                mod.Parent = part
                            end
                        end
                    end
                end

                -- 2. Prioridade Permanente nas Calçadas
                local caminhos = house:FindFirstChild("Paths")
                if caminhos then
                    for _, part in pairs(caminhos:GetDescendants()) do
                        if part:IsA("BasePart") and not part:FindFirstChild("PrioridadeCaminho") then
                            local mod = Instance.new("PathfindingModifier")
                            mod.Name = "PrioridadeCaminho"
                            mod.ModifierId = "Calcada" 
                            mod.Parent = part
                        end
                    end
                end
            end
        end
    end)
    
    _G.MapaBloxburgConfigurado = true
    LogSD("Mapa configurado com sucesso!")
end

-- ==========================================
-- 👁️ LÓGICA DE PORTA DA INTERFACE
-- ==========================================
local function ObterStatusPorta()
    local p = Players.LocalPlayer
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
    return texto, botao
end

local function ClicarBotao(btn)
    if not btn then return end
    pcall(function()
        if getconnections then
            for _, c in pairs(getconnections(btn.MouseButton1Click)) do c:Fire() end
            for _, c in pairs(getconnections(btn.Activated)) do c:Fire() end
        end
    end)
end

-- ==========================================
-- 🚶 MOVIMENTAÇÃO PRINCIPAL
-- ==========================================
function SmartDoor.IrPara(destino, targetPosForcado)
    SmartDoor.CurrentWalkId = SmartDoor.CurrentWalkId + 1
    local myId = SmartDoor.CurrentWalkId

    local lp = Players.LocalPlayer
    local char = lp.Character
    if not char or not char:FindFirstChild("Humanoid") then return false end
    local hum = char.Humanoid
    local hrp = char.HumanoidRootPart

    local targetPos = targetPosForcado or (typeof(destino) == "Instance" and (destino:IsA("Model") and destino:GetPivot().Position or destino.Position) or destino)

    -- Configura as portas só na primeira vez que rodar
    ConfigurarMapaUmaVez()

    LogSD("Calculando rota pelo GPS...")
    local path = PathfindingService:CreatePath({
        AgentRadius = 0.8, -- Perfeito para não raspar na parede e passar na porta
        AgentHeight = 5,
        AgentCanJump = true,
        WaypointSpacing = 3,
        Costs = { Calcada = 0.1 } 
    })

    local success, err = pcall(function() path:ComputeAsync(hrp.Position, targetPos) end)

    if not success or (path.Status ~= Enum.PathStatus.Success and path.Status ~= Enum.PathStatus.ClosestNoPath) then
        LogSD("❌ GPS Falhou ou não achou caminho.")
        return false
    end

    local waypoints = path:GetWaypoints()
    LogSD("✅ Rota achada! Andando...")

    for i, wp in ipairs(waypoints) do
        if SmartDoor.CurrentWalkId ~= myId then return false end
        
        if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
        hum:MoveTo(wp.Position)

        local tempoInicio = tick()
        local lastPos = hrp.Position
        local tempoChecagemStuck = tick()

        while (hrp.Position - wp.Position).Magnitude > 3.0 do
            if SmartDoor.CurrentWalkId ~= myId then return false end
            
            -- Lógica da Porta (Lê a sua UI)
            local txt, btn = ObterStatusPorta()
            if txt and (txt:find("open") or txt:find("abrir")) then
                hum:MoveTo(hrp.Position) 
                LogSD("🚪 Porta Fechada! Abrindo...")
                
                if tick() - lastDoorClick > 0.6 then
                    lastDoorClick = tick()
                    ClicarBotao(btn)
                    task.spawn(function()
                        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                        task.wait(0.1)
                        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                    end)
                end
                task.wait(0.3)
                hum:MoveTo(wp.Position) 
            end

            -- Anti-Stuck (Destravar)
            if tick() - tempoChecagemStuck > 0.8 then
                local distMovida = (hrp.Position - lastPos).Magnitude
                if distMovida < 0.5 then 
                    hum.Jump = true
                    hum:MoveTo(wp.Position)
                end
                lastPos = hrp.Position
                tempoChecagemStuck = tick()
            end

            if tick() - tempoInicio > 5.0 then break end
            task.wait()
        end
    end

    local distFinal = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
    if distFinal < 6 then
        hum:MoveTo(hrp.Position)
        LogSD("✅ Chegou no móvel com sucesso!")
        return true
    end
    LogSD("⚠️ Parou perto do alvo.")
    return true
end

-- ==========================================
-- 🖥️ GUI DE INTERFACE DE TESTE
-- ==========================================

if CoreGui:FindFirstChild("TestSmartDoorGUI") then
    CoreGui:FindFirstChild("TestSmartDoorGUI"):Destroy()
end

local sg = Instance.new("ScreenGui")
sg.Name = "TestSmartDoorGUI"
sg.Parent = CoreGui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 220, 0, 280)
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

-- Funções Blindadas de Busca
local function GetSafePosition(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj.Position end
    if obj:IsA("Model") then
        if obj.PrimaryPart then return obj.PrimaryPart.Position end
        return obj:GetPivot().Position
    end
    local firstPart = obj:FindFirstChildWhichIsA("BasePart", true)
    if firstPart then return firstPart.Position end
    return nil
end

local function GetInteractionPart(obj)
    local objectModel = obj:FindFirstChild("ObjectModel")
    if objectModel then
        local door = objectModel:FindFirstChild("OvenDoor") 
                  or objectModel:FindFirstChild("MainDoor") 
                  or objectModel:FindFirstChild("Door")
                  or objectModel:FindFirstChild("Handle")
        if door then return door end
        return objectModel
    end
    return obj
end

local function EncontrarMovel(tipo)
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil, nil end
    
    local char = Players.LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return nil, nil end
    local myPos = char.HumanoidRootPart.Position
    
    local nearestObject = nil
    local nearestPos = nil
    local nearestDist = math.huge

    LogSD("Buscando sua casa...")

    for _, plot in pairs(plots:GetChildren()) do
        if plot:FindFirstChild("House") and plot.House:FindFirstChild("Counters") then
            for _, obj in pairs(plot.House.Counters:GetChildren()) do
                local name = string.lower(obj.Name)
                local isMatch = false
                
                if tipo == "Fridge" and (name:find("fridge") or name:find("refrigerator") or name:find("icebox")) then isMatch = true end
                if tipo == "Stove" and (name:find("stove") or name:find("oven") or name:find("cook")) then isMatch = true end
                if tipo == "Cover" and (name:find("counter") or name:find("island")) then isMatch = true end

                if isMatch then
                    local part = GetInteractionPart(obj)
                    local safePos = GetSafePosition(part)
                    
                    if safePos then
                        local dist = (myPos - safePos).Magnitude
                        if dist < nearestDist then
                            nearestDist = dist
                            nearestObject = part
                            nearestPos = safePos
                        end
                    end
                end
            end
        end
    end
    return nearestObject, nearestPos
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
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = b

    b.MouseButton1Click:Connect(function()
        if b.Text == "Andando..." then return end 
        
        b.Text = "Procurando..."
        
        task.spawn(function()
            local success, alvo, posExata = pcall(function()
                return EncontrarMovel(busca)
            end)
            
            if not success then
                b.Text = label
                LogSD("❌ Erro ao buscar móvel.")
                return
            end
            
            if alvo and posExata then
                b.Text = "Andando..."
                SmartDoor.IrPara(alvo, posExata)
                b.Text = label 
            else
                b.Text = label
                LogSD("❌ Móvel não achado.")
            end
        end)
    end)
end

CriarBotaoTeste("❄️ GELADEIRA", "Fridge")
CriarBotaoTeste("🔥 FOGÃO", "Stove")
CriarBotaoTeste("🔪 BANCADA", "Cover")

return SmartDoor
