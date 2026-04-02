local PathfindingService = game:GetService("PathfindingService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Players = game:GetService("Players")

local SmartDoor = {} 
SmartDoor.CurrentWalkId = 0 
local lastDoorClick = 0

local function LogSD(msg)
    if _G.BloxburgChef_AddLog then
        _G.BloxburgChef_AddLog(msg, Color3.fromRGB(255, 170, 0))
    else
        print("[SmartDoor] " .. msg)
    end
end

-- ==========================================
-- 🗺️ CONFIGURAÇÃO DE GPS (PORTAS E CALÇADAS)
-- ==========================================
local function ConfigurarMapa(estado)
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return end

    for _, plot in pairs(plots:GetChildren()) do
        if plot:FindFirstChild("House") then
            
            -- 1. TRATAR PORTAS COMO PASSÁVEIS (FANTASMAS PRO GPS)
            for _, obj in pairs(plot.House:GetDescendants()) do
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

            -- 2. PRIORIZAR SUAS CALÇADAS (workspace.Plots...House.Paths)
            local caminhos = plot.House:FindFirstChild("Paths")
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

-- Impede que o móvel de destino bloqueie o próprio GPS
local function FantasmaAlvo(alvo, estado)
    if not alvo then return end
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
-- 👁️ INTERAÇÃO MOBILE (CLIQUE NA UI)
-- ==========================================
local function ObterStatusPorta()
    local p = Players.LocalPlayer
    local texto, botao = nil, nil
    pcall(function()
        -- Caminho exato fornecido: PlayerGui._interactUI.InteractIndicator.TextLabel
        local indicator = p.PlayerGui._interactUI.InteractIndicator
        if indicator and indicator.Visible then
            texto = string.lower(indicator.TextLabel.Text)
            botao = indicator
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

function SmartDoor.Cancelar()
    SmartDoor.CurrentWalkId = SmartDoor.CurrentWalkId + 1
    pcall(function()
        local c = Players.LocalPlayer.Character
        c.Humanoid:MoveTo(c.HumanoidRootPart.Position)
    end)
end

-- ==========================================
-- 🚶 MOVIMENTAÇÃO PRINCIPAL
-- ==========================================
function SmartDoor.IrPara(destino)
    SmartDoor.CurrentWalkId = SmartDoor.CurrentWalkId + 1
    local myId = SmartDoor.CurrentWalkId

    local lp = Players.LocalPlayer
    local char = lp.Character
    if not char or not char:FindFirstChild("Humanoid") then return false end
    local hum = char.Humanoid
    local hrp = char.HumanoidRootPart

    local targetPos = typeof(destino) == "Instance" and (destino:IsA("Model") and destino:GetPivot().Position or destino.Position) or destino

    ConfigurarMapa("LIGAR")
    if typeof(destino) == "Instance" then FantasmaAlvo(destino, "LIGAR") end

    local path = PathfindingService:CreatePath({
        AgentRadius = 1.2, -- Mantém distância das paredes
        AgentHeight = 5,
        AgentCanJump = true,
        WaypointSpacing = 4,
        Costs = { Calcada = 0.01 } -- Preferência total por calçadas
    })

    local success, _ = pcall(function() path:ComputeAsync(hrp.Position, targetPos) end)
    
    ConfigurarMapa("DESLIGAR")
    if typeof(destino) == "Instance" then FantasmaAlvo(destino, "DESLIGAR") end

    if not success or path.Status ~= Enum.PathStatus.Success then
        LogSD("❌ GPS falhou em achar rota segura.")
        return false
    end

    local waypoints = path:GetWaypoints()
    for i, wp in ipairs(waypoints) do
        if SmartDoor.CurrentWalkId ~= myId then return false end
        
        if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
        hum:MoveTo(wp.Position)

        -- Loop de monitoramento do ponto atual
        while (hrp.Position - wp.Position).Magnitude > 3.5 do
            if SmartDoor.CurrentWalkId ~= myId then return false end
            
            -- Lógica de Porta (UI)
            local txt, btn = ObterStatusPorta()
            if txt and (txt:find("open") or txt:find("abrir")) then
                hum:MoveTo(hrp.Position) -- Freia
                if tick() - lastDoorClick > 0.5 then
                    lastDoorClick = tick()
                    ClicarBotao(btn)
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                    task.wait(0.1)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                end
                task.wait(0.2)
                hum:MoveTo(wp.Position) -- Retoma
            end

            -- Checagem de distância final (Só ativa no último trecho do GPS)
            if i >= #waypoints - 1 then
                if (hrp.Position - targetPos).Magnitude < 4.5 then
                    hum:MoveTo(hrp.Position)
                    return true 
                end
            end
            task.wait()
        end
    end
    return true
end

return SmartDoor
