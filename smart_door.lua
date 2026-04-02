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
-- 🚪 GERENCIAMENTO DOS FANTASMAS
-- ==========================================
local function AlterarFantasmas(estado)
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return end

    for _, plot in pairs(plots:GetChildren()) do
        if plot:FindFirstChild("House") then
            for _, obj in pairs(plot.House:GetDescendants()) do
                if obj:IsA("Model") and (string.find(string.lower(obj.Name), "door") or string.find(string.lower(obj.Name), "gate")) then
                    for _, part in pairs(obj:GetDescendants()) do
                        if part:IsA("BasePart") then
                            if estado == "LIGAR" then
                                if not part:FindFirstChild("IgnorarNoGPS") then
                                    local modifier = Instance.new("PathfindingModifier")
                                    modifier.Name = "IgnorarNoGPS"
                                    modifier.PassThrough = true
                                    modifier.Parent = part
                                end
                            elseif estado == "DESLIGAR" then
                                local mod = part:FindFirstChild("IgnorarNoGPS")
                                if mod then mod:Destroy() end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function TransformarAlvoEmFantasma(alvo, estado)
    if not alvo then return end
    local model = alvo:FindFirstAncestorWhichIsA("Model") or alvo
    for _, part in pairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            if estado == "LIGAR" then
                if not part:FindFirstChild("FantasmaAlvo") then
                    local mod = Instance.new("PathfindingModifier")
                    mod.Name = "FantasmaAlvo"
                    mod.PassThrough = true
                    mod.Parent = part
                end
            else
                local mod = part:FindFirstChild("FantasmaAlvo")
                if mod then mod:Destroy() end
            end
        end
    end
end

function SmartDoor.Cancelar()
    SmartDoor.CurrentWalkId = SmartDoor.CurrentWalkId + 1
    LogSD("🛑 Rota Cancelada e freio puxado!")
    pcall(function()
        local char = Players.LocalPlayer.Character
        if char and char:FindFirstChild("Humanoid") and char:FindFirstChild("HumanoidRootPart") then
            char.Humanoid:MoveTo(char.HumanoidRootPart.Position)
        end
    end)
end

-- ==========================================
-- 👁️ LEITOR DA INTERFACE E CLIQUE (MOBILE + PC)
-- ==========================================
local function LerStatusDaPorta()
    local player = Players.LocalPlayer
    local texto = nil
    local botao = nil

    pcall(function()
        local interactUI = player.PlayerGui:FindFirstChild("_interactUI")
        if interactUI then
            -- O Caminho exato que você pediu
            local indicator = interactUI:FindFirstChild("InteractIndicator")
            if indicator then
                local label = indicator:FindFirstChild("TextLabel")
                if label and label.Text ~= "" then
                    texto = string.lower(label.Text)
                    botao = indicator
                end
            end
            
            -- Fallback
            if not texto then
                local center = interactUI:FindFirstChild("Center")
                if center then
                    local btn = center:FindFirstChild("Button")
                    if btn then
                        local lbl = btn:FindFirstChild("TextLabel")
                        if lbl and lbl.Text ~= "" then
                            texto = string.lower(lbl.Text)
                            botao = btn
                        end
                    end
                end
            end
        end
    end)
    
    return texto, botao
end

local function ClicarNaUI(botao)
    pcall(function()
        if getconnections and botao then
            for _, conn in pairs(getconnections(botao.MouseButton1Click)) do conn:Fire() end
            for _, conn in pairs(getconnections(botao.Activated)) do conn:Fire() end
        end
    end)
end

function SmartDoor.IrPara(destino)
    SmartDoor.CurrentWalkId = SmartDoor.CurrentWalkId + 1
    local myWalkId = SmartDoor.CurrentWalkId 

    local player = Players.LocalPlayer
    local char = player.Character
    if not char or not char:FindFirstChild("Humanoid") or not char:FindFirstChild("HumanoidRootPart") then 
        return false 
    end

    local hrp = char.HumanoidRootPart
    local hum = char.Humanoid

    local targetPos
    if typeof(destino) == "Instance" then
        targetPos = destino:IsA("Model") and destino:GetPivot().Position or destino.Position
    elseif typeof(destino) == "Vector3" then 
        targetPos = destino
    else 
        return false 
    end

    local maxTentativas = 5
    local tentativaAtual = 0

    while tentativaAtual < maxTentativas do
        if SmartDoor.CurrentWalkId ~= myWalkId then return false end 
        tentativaAtual = tentativaAtual + 1
        LogSD("📍 Calculando rota (Tentativa " .. tentativaAtual .. "/5)...")

        AlterarFantasmas("LIGAR")
        if typeof(destino) == "Instance" then TransformarAlvoEmFantasma(destino, "LIGAR") end

        local path = PathfindingService:CreatePath({
            AgentRadius = 0.5, 
            AgentHeight = 4, 
            AgentCanJump = true, 
            WaypointSpacing = 3 
        })

        local success, err = pcall(function() path:ComputeAsync(hrp.Position, targetPos) end)

        AlterarFantasmas("DESLIGAR")
        if typeof(destino) == "Instance" then TransformarAlvoEmFantasma(destino, "DESLIGAR") end

        local waypoints = {}

        if success and (path.Status == Enum.PathStatus.Success or path.Status == Enum.PathStatus.ClosestNoPath) then
            waypoints = path:GetWaypoints()
            LogSD("✅ Rota encontrada pelo GPS!")
        else
            LogSD("⚠️ GPS falhou. Forçando caminhada em linha reta!")
            waypoints = {
                PathWaypoint.new(targetPos, Enum.PathWaypointAction.Walk)
            }
        end

        local totalPontos = #waypoints

        for i, wp in ipairs(waypoints) do
            if SmartDoor.CurrentWalkId ~= myWalkId then return false end 

            if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end

            hum:MoveTo(wp.Position) 

            local tempoInicio = tick()
            local lastPos = hrp.Position
            local tempoChecagemStuck = tick()

            while (hrp.Position - wp.Position).Magnitude > 3.0 do
                if SmartDoor.CurrentWalkId ~= myWalkId then return false end 

                -- Ele só usa o radar de distância final se estiver nos DOIS ÚLTIMOS passos da rota
                if i >= totalPontos - 1 then
                    local distFinal = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
                    if distFinal <= 3.5 then
                        LogSD("🎯 Chegou no alvo final!")
                        hum:MoveTo(hrp.Position) 
                        return true
                    end
                end

                -- LÓGICA EXATA DA PORTA
                local status, botao = LerStatusDaPorta()
                
                if status and (string.find(status, "open") or string.find(status, "abrir")) then
                    LogSD("🚪 Porta fechada detectada! Puxando freio...")
                    hum:MoveTo(hrp.Position) 

                    local tempoTentando = tick()
                    while tick() - tempoTentando < 5 do
                        if SmartDoor.CurrentWalkId ~= myWalkId then return false end 

                        local statusAtual, botaoAtual = LerStatusDaPorta()

                        if not statusAtual or string.find(statusAtual, "close") or string.find(statusAtual, "fechar") then
                            LogSD("🔓 Caminho livre! Voltando a correr...")
                            break
                        elseif string.find(statusAtual, "open") or string.find(statusAtual, "abrir") then
                            if tick() - lastDoorClick > 0.5 then
                                lastDoorClick = tick()
                                
                                -- Clique Mobile
                                if botaoAtual then ClicarNaUI(botaoAtual) end
                                
                                -- Clique PC
                                task.spawn(function()
                                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                                    task.wait(0.1)
                                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                                end)
                            end
                        end
                        task.wait(0.1)
                    end
                    hum:MoveTo(wp.Position) 
                elseif status and (string.find(status, "close") or string.find(status, "fechar")) then
                    -- Ignora e passa direto, a porta já está aberta
                end

                if tick() - tempoChecagemStuck > 0.8 then
                    if (hrp.Position - lastPos).Magnitude < 0.5 then 
                        hum.Jump = true 
                        hum:MoveTo(wp.Position)
                    end
                    lastPos = hrp.Position
                    tempoChecagemStuck = tick()
                end

                if tick() - tempoInicio > 4.0 then break end
                task.wait(0.1) 
            end
        end

        local distCheckFinal = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
        if distCheckFinal < 7 then
            LogSD("✅ Posicionado e pronto para interagir!")
            return true
        else
            LogSD("🚨 Caiu longe do alvo. Recalculando...")
        end
    end

    LogSD("❌ Falhou após várias tentativas.")
    return false
end

return SmartDoor
