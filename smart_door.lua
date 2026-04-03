local PathfindingService = game:GetService("PathfindingService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")

local SmartDoor = {} 
SmartDoor.CurrentWalkId = 0 
local lastDoorClick = 0

-- Variável global para a tela de teste
_G.StatusTextoTeste = nil

local function LogSD(msg)
    -- Manda pra UI
    if _G.StatusTextoTeste then _G.StatusTextoTeste.Text = msg end
    -- Manda pro Hub original se existir
    if _G.BloxburgChef_AddLog then _G.BloxburgChef_AddLog(msg, Color3.fromRGB(255, 170, 0)) end
end

-- ==========================================
-- 🗺️ CONFIGURAÇÃO DE GPS (PORTAS E CALÇADAS)
-- ==========================================
local function ConfigurarMapa(estado)
    print("[DEBUG-MAPA] Configurando Mapa: " .. estado)
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return end

    for _, plot in pairs(plots:GetChildren()) do
        local house = plot:FindFirstChild("House")
        if house then
            for _, obj in pairs(house:GetDescendants()) do
                if obj:IsA("Model") and (string.find(string.lower(obj.Name), "door") or string.find(string.lower(obj.Name), "gate")) then
                    for _, part in pairs(obj:GetDescendants()) do
                        if part:IsA("BasePart") then
                            if estado == "LIGAR" then
                                if not part:FindFirstChild("IgnorarNoGPS") then
                                    local mod = Instance.new("PathfindingModifier")
                                    mod.Name = "IgnorarNoGPS"
                                    mod.PassThrough = true
                                    mod.Parent = part
                                end
                            elseif estado == "DESLIGAR" then
                                local mod = part:FindFirstChild("IgnorarNoGPS")
                                if mod then mod:Destroy() end
                            end
                        end
                    end
                end
            end

            local caminhos = house:FindFirstChild("Paths")
            if caminhos then
                for _, part in pairs(caminhos:GetDescendants()) do
                    if part:IsA("BasePart") then
                        if estado == "LIGAR" then
                            if not part:FindFirstChild("PrioridadeCaminho") then
                                local mod = Instance.new("PathfindingModifier")
                                mod.Name = "PrioridadeCaminho"
                                mod.ModifierId = "Calcada" 
                                mod.Parent = part
                            end
                        elseif estado == "DESLIGAR" then
                            local mod = part:FindFirstChild("PrioridadeCaminho")
                            if mod then mod:Destroy() end
                        end
                    end
                end
            end
        end
    end
end

local function FantasmaAlvo(alvo, estado)
    if not alvo then return end
    print("[DEBUG-FANTASMA] Transformando alvo em fantasma: " .. estado)
    local m = alvo:FindFirstAncestorWhichIsA("Model") or alvo
    for _, p in pairs(m:GetDescendants()) do
        if p:IsA("BasePart") then
            if estado == "LIGAR" then
                if not p:FindFirstChild("TargetMod") then
                    local mod = Instance.new("PathfindingModifier")
                    mod.Name = "TargetMod"
                    mod.PassThrough = true
                    mod.Parent = p
                end
            else
                local mod = p:FindFirstChild("TargetMod")
                if mod then mod:Destroy() end
            end
        end
    end
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
    print("[DEBUG-CLIQUE] Forçando clique na UI")
    pcall(function()
        if getconnections then
            for _, c in pairs(getconnections(btn.MouseButton1Click)) do c:Fire() end
            for _, c in pairs(getconnections(btn.Activated)) do c:Fire() end
        end
    end)
end

function SmartDoor.Cancelar()
    SmartDoor.CurrentWalkId = SmartDoor.CurrentWalkId + 1
    print("[DEBUG-CANCEL] Cancelando rota atual.")
    pcall(function()
        local c = Players.LocalPlayer.Character
        if c and c:FindFirstChild("Humanoid") then
            c.Humanoid:MoveTo(c.HumanoidRootPart.Position)
        end
    end)
end

-- ==========================================
-- 🚶 MOVIMENTAÇÃO PRINCIPAL
-- ==========================================
function SmartDoor.IrPara(destino, targetPosForcado)
    print("[DEBUG-GPS] --- INICIANDO FUNÇÃO IRPARA ---")
    SmartDoor.CurrentWalkId = SmartDoor.CurrentWalkId + 1
    local myId = SmartDoor.CurrentWalkId

    local lp = Players.LocalPlayer
    local char = lp.Character
    if not char or not char:FindFirstChild("Humanoid") then 
        print("[DEBUG-GPS] Erro: Personagem ou Humanoid não encontrado!")
        return false 
    end
    local hum = char.Humanoid
    local hrp = char.HumanoidRootPart

    local targetPos = targetPosForcado or (typeof(destino) == "Instance" and (destino:IsA("Model") and destino:GetPivot().Position or destino.Position) or destino)
    print("[DEBUG-GPS] Posição de destino definida: " .. tostring(targetPos))

    LogSD("Configurando Fantasmas...")
    ConfigurarMapa("LIGAR")
    if typeof(destino) == "Instance" then FantasmaAlvo(destino, "LIGAR") end

    LogSD("Calculando rota pelo GPS...")
    print("[DEBUG-GPS] Solicitando rota ao Roblox Engine...")
    local path = PathfindingService:CreatePath({
        AgentRadius = 0.5, 
        AgentHeight = 5,
        AgentCanJump = true,
        WaypointSpacing = 4,
        Costs = { Calcada = 0.1 } 
    })

    local success, err = pcall(function() path:ComputeAsync(hrp.Position, targetPos) end)
    
    print("[DEBUG-GPS] ComputeAsync terminou. Success: " .. tostring(success))
    if not success then
        print("[DEBUG-GPS] ERRO CRÍTICO NO GPS: " .. tostring(err))
    end
    
    ConfigurarMapa("DESLIGAR")
    if typeof(destino) == "Instance" then FantasmaAlvo(destino, "DESLIGAR") end

    if not success or path.Status ~= Enum.PathStatus.Success then
        print("[DEBUG-GPS] Rota falhou. Status do Path: " .. tostring(path.Status))
        LogSD("❌ GPS Falhou. Bloqueado ou inalcançável.")
        return false
    end

    local waypoints = path:GetWaypoints()
    print("[DEBUG-GPS] Rota criada com sucesso! Waypoints totais: " .. #waypoints)
    LogSD("✅ Rota achada (" .. #waypoints .. " pontos). Andando...")

    for i, wp in ipairs(waypoints) do
        if SmartDoor.CurrentWalkId ~= myId then 
            print("[DEBUG-GPS] Rota abortada pois um novo ID foi chamado.")
            return false 
        end
        
        print("[DEBUG-GPS] Indo para o waypoint " .. i)
        if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
        hum:MoveTo(wp.Position)

        local tempoInicio = tick()
        local lastPos = hrp.Position
        local tempoChecagemStuck = tick()

        while (hrp.Position - wp.Position).Magnitude > 3.5 do
            if SmartDoor.CurrentWalkId ~= myId then return false end
            
            local txt, btn = ObterStatusPorta()
            if txt and (txt:find("open") or txt:find("abrir")) then
                print("[DEBUG-PORTA] Porta encontrada na UI (Open). Freando...")
                hum:MoveTo(hrp.Position) 
                LogSD("🚪 Porta Fechada! Tentando abrir...")
                
                if tick() - lastDoorClick > 0.6 then
                    lastDoorClick = tick()
                    print("[DEBUG-PORTA] Enviando clique pra abrir a porta.")
                    ClicarBotao(btn)
                    task.spawn(function()
                        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                        task.wait(0.1)
                        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                    end)
                end
                task.wait(0.3)
                hum:MoveTo(wp.Position) 
                LogSD("Andando...")
            end

            if tick() - tempoChecagemStuck > 0.8 then
                local distMovida = (hrp.Position - lastPos).Magnitude
                if distMovida < 0.5 then 
                    print("[DEBUG-STUCK] Boneco parece travado! Distância movida em 0.8s: " .. distMovida)
                    hum.Jump = true
                    hum:MoveTo(wp.Position)
                end
                lastPos = hrp.Position
                tempoChecagemStuck = tick()
            end

            if tick() - tempoInicio > 5.0 then 
                print("[DEBUG-GPS] Tempo limite do waypoint excedido (5s). Pulando para o próximo.")
                break 
            end
            task.wait()
        end
    end

    local distFinal = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
    print("[DEBUG-GPS] Checagem final. Distância pro alvo: " .. distFinal)
    
    if distFinal < 6 then
        hum:MoveTo(hrp.Position)
        LogSD("✅ Chegou no móvel com sucesso!")
        return true
    end
    
    LogSD("⚠️ Parou antes do fim.")
    return false
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

-- Função 100% Blindada para pegar a Posição
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
    print("[DEBUG-BUSCA] --- INICIANDO BUSCA POR: " .. tostring(tipo) .. " ---")
    local plots = workspace:FindFirstChild("Plots")
    if not plots then 
        print("[DEBUG-BUSCA] Pasta 'Plots' não encontrada no workspace!")
        return nil, nil 
    end
    
    local char = Players.LocalPlayer.Character
    if not char or not char:FindFirstChild("HumanoidRootPart") then 
        print("[DEBUG-BUSCA] Personagem do jogador não encontrado!")
        return nil, nil 
    end
    local myPos = char.HumanoidRootPart.Position
    
    local nearestObject = nil
    local nearestPos = nil
    local nearestDist = math.huge

    LogSD("Buscando na pasta Counters...")
    print("[DEBUG-BUSCA] Iterando sobre os Plots...")

    for _, plot in pairs(plots:GetChildren()) do
        if plot:FindFirstChild("House") and plot.House:FindFirstChild("Counters") then
            print("[DEBUG-BUSCA] Casa e Counters encontrados no Plot: " .. plot.Name)
            for _, obj in pairs(plot.House.Counters:GetChildren()) do
                local name = string.lower(obj.Name)
                local isMatch = false
                
                if tipo == "Fridge" and (name:find("fridge") or name:find("refrigerator") or name:find("icebox")) then isMatch = true end
                if tipo == "Stove" and (name:find("stove") or name:find("oven") or name:find("cook")) then isMatch = true end
                if tipo == "Cover" and (name:find("counter") or name:find("island")) then isMatch = true end

                if isMatch then
                    print("[DEBUG-BUSCA] Móvel alvo detectado na pasta: " .. obj.Name)
                    local part = GetInteractionPart(obj)
                    local safePos = GetSafePosition(part)
                    
                    if safePos then
                        local dist = (myPos - safePos).Magnitude
                        print("[DEBUG-BUSCA] Distância pro móvel: " .. dist)
                        if dist < nearestDist then
                            nearestDist = dist
                            nearestObject = part
                            nearestPos = safePos
                        end
                    else
                        print("[DEBUG-BUSCA] ALERTA: Não foi possível extrair a posição física do móvel " .. obj.Name)
                    end
                end
            end
        end
    end
    
    if nearestObject then
        print("[DEBUG-BUSCA] Busca concluída com sucesso. Alvo finalizado.")
    else
        print("[DEBUG-BUSCA] Nenhum móvel atendeu aos critérios.")
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
        
        print("\n\n[=== TESTE INICIADO: " .. label .. " ===]")
        b.Text = "Procurando..."
        
        task.spawn(function()
            local success, alvo, posExata = pcall(function()
                return EncontrarMovel(busca)
            end)
            
            if not success then
                b.Text = label
                print("[DEBUG-MAIN] ERRO NO PCALL DA BUSCA!")
                LogSD("❌ Erro interno de Lógica (Crash evitado).")
                return
            end
            
            if alvo and posExata then
                b.Text = "Andando..."
                LogSD("Alvo localizado. Indo...")
                print("[DEBUG-MAIN] Chamando IrPara...")
                SmartDoor.IrPara(alvo, posExata)
                b.Text = label 
                print("[DEBUG-MAIN] Ciclo concluído.")
            else
                b.Text = label
                LogSD("❌ Móvel não achado em Counters.")
            end
        end)
    end)
end

CriarBotaoTeste("❄️ GELADEIRA", "Fridge")
CriarBotaoTeste("🔥 FOGÃO", "Stove")
CriarBotaoTeste("🔪 BANCADA", "Cover")

return SmartDoor
