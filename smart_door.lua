local PathfindingService = game:GetService("PathfindingService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")

local SmartDoor = {} 
SmartDoor.CurrentWalkId = 0 
local lastDoorClick = 0

-- Função de Log
local function LogSD(msg)
    if _G.StatusTextoTeste then _G.StatusTextoTeste.Text = msg end
    print("[SmartDoor] " .. msg)
end

-- ==========================================
-- 🔴 DESENHAR O CAMINHO (VISUALIZADOR DE GPS)
-- ==========================================
local function DesenharCaminho(waypoints)
    local folder = workspace:FindFirstChild("CaminhoSmartDoor")
    if folder then folder:Destroy() end
    
    folder = Instance.new("Folder")
    folder.Name = "CaminhoSmartDoor"
    folder.Parent = workspace

    for i, wp in ipairs(waypoints) do
        local part = Instance.new("Part")
        part.Size = Vector3.new(1, 1, 1)
        part.Position = wp.Position
        part.Anchored = true
        part.CanCollide = false
        part.Material = Enum.Material.Neon
        part.Color = Color3.fromRGB(255, 50, 50)
        part.Shape = Enum.PartType.Ball
        part.Parent = folder
    end
end

-- ==========================================
-- 🗺️ FANTASMAS (SÓ PARA PORTAS E O ALVO)
-- ==========================================
local function PrepararFisica(estado, alvo)
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return end

    -- 1. Ignorar todas as portas da casa (Continua intacto!)
    for _, plot in pairs(plots:GetChildren()) do
        local house = plot:FindFirstChild("House")
        if house then
            for _, obj in pairs(house:GetDescendants()) do
                if obj:IsA("Model") and (string.find(string.lower(obj.Name), "door") or string.find(string.lower(obj.Name), "gate")) then
                    for _, part in pairs(obj:GetDescendants()) do
                        if part:IsA("BasePart") then
                            if estado == "LIGAR" and not part:FindFirstChild("IgnorarGPS_Porta") then
                                local mod = Instance.new("PathfindingModifier")
                                mod.Name = "IgnorarGPS_Porta"
                                mod.PassThrough = true
                                mod.Parent = part
                            elseif estado == "DESLIGAR" and part:FindFirstChild("IgnorarGPS_Porta") then
                                part.IgnorarGPS_Porta:Destroy()
                            end
                        end
                    end
                end
            end
        end
    end

    -- 2. Ignorar o alvo para o GPS
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
                    part.IgnorarGPS_Alvo:Destroy()
                end
            end
        end
    end
end

-- ==========================================
-- 👁️ ABRIR PORTA COM A INTERFACE (Continua intacto!)
-- ==========================================
local function TentarAbrirPorta()
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
    
    if texto and (texto:find("open") or texto:find("abrir")) then
        if tick() - lastDoorClick > 0.6 then
            lastDoorClick = tick()
            LogSD("🚪 Porta Fechada! Clicando para abrir...")
            
            if botao and getconnections then
                pcall(function()
                    for _, c in pairs(getconnections(botao.MouseButton1Click)) do c:Fire() end
                    for _, c in pairs(getconnections(botao.Activated)) do c:Fire() end
                end)
            end
            
            task.spawn(function()
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                task.wait(0.1)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
            end)
        end
        return true 
    end
    
    return false 
end

-- ==========================================
-- 🎯 RADAR: ACHA A FRENTE DO MÓVEL (NOVO!)
-- ==========================================
local function ObterPosicaoNaFrente(alvoPart)
    local pos = alvoPart.Position
    local cf = alvoPart.CFrame
    
    -- Dispara para 4 lados (Frente, Trás, Esquerda, Direita do móvel)
    local direcoes = {
        cf.LookVector,
        -cf.LookVector,
        cf.RightVector,
        -cf.RightVector
    }
    
    local melhorDirecao = Vector3.new(0, 0, 1)
    local maiorEspacoLivre = -1
    
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    -- Ignora o player e o próprio móvel para o raio não bater neles mesmos
    local model = alvoPart:FindFirstAncestorWhichIsA("Model") or alvoPart
    rp.FilterDescendantsInstances = {Players.LocalPlayer.Character, model}
    
    for _, dir in ipairs(direcoes) do
        -- Raio de 10 blocos de distância
        local resultado = workspace:Raycast(pos, dir * 10, rp)
        local distanciaLivre = 10
        
        -- Se bateu em algo (tipo a parede), anota a distância
        if resultado then
            distanciaLivre = (resultado.Position - pos).Magnitude
        end
        
        -- Pega a direção que tem mais espaço sobrando
        if distanciaLivre > maiorEspacoLivre then
            maiorEspacoLivre = distanciaLivre
            melhorDirecao = dir
        end
    end
    
    -- Calcula o alvo: 3 passos na direção mais livre (oposto da parede)
    local posicaoAlvo = pos + (melhorDirecao * 3)
    
    -- Pega a altura do chão do player pra não tentar voar
    local hrp = Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local alturaY = hrp and hrp.Position.Y or pos.Y
    
    return Vector3.new(posicaoAlvo.X, alturaY, posicaoAlvo.Z)
end

-- ==========================================
-- 🚶 MOTOR DE CAMINHADA
-- ==========================================
function SmartDoor.IrPara(destino, targetPosForcado)
    SmartDoor.CurrentWalkId = SmartDoor.CurrentWalkId + 1
    local myId = SmartDoor.CurrentWalkId

    local char = Players.LocalPlayer.Character
    if not char or not char:FindFirstChild("Humanoid") then return false end
    local hum = char.Humanoid
    local hrp = char.HumanoidRootPart

    -- Verifica qual é o alvo de verdade e acha a parte da frente dele
    local alvoPart = destino
    if typeof(destino) == "Instance" and destino:IsA("Model") then
        alvoPart = destino.PrimaryPart or destino:FindFirstChildWhichIsA("BasePart", true)
    end
    
    -- Usa a posição forçada ou calcula a frente pra desviar da parede
    local targetPos = targetPosForcado
    if typeof(alvoPart) == "Instance" and alvoPart:IsA("BasePart") then
        targetPos = ObterPosicaoNaFrente(alvoPart)
    end

    LogSD("1. Preparando o motor de Pathfinding...")
    PrepararFisica("LIGAR", destino)

    task.wait(0.15) 

    local path = PathfindingService:CreatePath({
        AgentRadius = 1.0, 
        AgentHeight = 5,
        AgentCanJump = true,
        WaypointSpacing = 4
    })

    LogSD("2. Calculando Rota para a FRENTE do móvel...")
    local success, errorMessage = pcall(function() 
        path:ComputeAsync(hrp.Position, targetPos) 
    end)
    
    PrepararFisica("DESLIGAR", destino)

    if not success or (path.Status ~= Enum.PathStatus.Success and path.Status ~= Enum.PathStatus.ClosestNoPath) then
        LogSD("❌ GPS Falhou completamente. Motivo: " .. tostring(path.Status))
        return false
    end

    local waypoints = path:GetWaypoints()
    LogSD("✅ Rota encontrada! Desenhando pontos...")
    DesenharCaminho(waypoints)

    for i, wp in ipairs(waypoints) do
        if SmartDoor.CurrentWalkId ~= myId then return false end
        
        if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
        
        hum:MoveTo(wp.Position)

        local tStart = tick()
        local lastPos = hrp.Position
        local checkStuck = tick()

        while true do
            if SmartDoor.CurrentWalkId ~= myId then return false end
            
            local pPos = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
            local wPos = Vector3.new(wp.Position.X, 0, wp.Position.Z)
            
            if (pPos - wPos).Magnitude <= 3.5 then
                break 
            end

            if TentarAbrirPorta() then
                task.wait(0.5)
                hum:MoveTo(wp.Position)
            end

            if tick() - checkStuck > 1.0 then
                if (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(lastPos.X, 0, lastPos.Z)).Magnitude < 0.5 then 
                    hum.Jump = true
                    hum:MoveTo(wp.Position)
                end
                lastPos = hrp.Position
                checkStuck = tick()
            end

            if tick() - tStart > 4.0 then 
                LogSD("⚠️ Ponto demorou muito. Pulando...")
                break 
            end
            
            task.wait()
        end
    end

    local distFinal = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
    if distFinal < 6.5 then
        hum:MoveTo(hrp.Position)
        LogSD("🎯 Chegou no alvo com sucesso!")
        return true
    end
    
    LogSD("⚠️ Rota terminou, mas ficou longe do alvo.")
    return false
end

function SmartDoor.Cancelar()
    SmartDoor.CurrentWalkId = SmartDoor.CurrentWalkId + 1
    LogSD("🚫 Caminhada cancelada.")
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

local function EncontrarMovel(tipo)
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    
    local char = Players.LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then return nil end
    local myPos = char.HumanoidRootPart.Position
    
    local nearestObj = nil
    local nearestDist = math.huge

    LogSD("Buscando na casa...")

    for _, plot in pairs(plots:GetChildren()) do
        if plot:FindFirstChild("House") and plot.House:FindFirstChild("Counters") then
            for _, obj in pairs(plot.House.Counters:GetChildren()) do
                local name = string.lower(obj.Name)
                local isMatch = false
                
                if tipo == "Fridge" and (name:find("fridge") or name:find("refrigerator") or name:find("icebox")) then isMatch = true end
                if tipo == "Stove" and (name:find("stove") or name:find("oven") or name:find("cook")) then isMatch = true end
                if tipo == "Cover" and (name:find("counter") or name:find("island")) then isMatch = true end

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
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = b

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
            -- Agora só mandamos o objeto pro IrPara, ele calcula a frente sozinho!
            SmartDoor.IrPara(alvo)
            b.Text = label 
        end)
    end)
end

CriarBotaoTeste("❄️ GELADEIRA", "Fridge")
CriarBotaoTeste("🔥 FOGÃO", "Stove")
CriarBotaoTeste("🔪 BANCADA", "Cover")

return SmartDoor
