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
-- 🗺️ CONFIGURAÇÃO DO MAPA (PORTAS E CALÇADAS)
-- ==========================================
local function ConfigurarMapa(estado)
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return end

    for _, plot in pairs(plots:GetChildren()) do
        if plot:FindFirstChild("House") then
            
            -- 1. FANTASMAS (Ignora as portas para passar por elas)
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

            -- 2. PREFERÊNCIA DE CAMINHOS (O seu fru-fru dos Paths!)
            local caminhos = plot.House:FindFirstChild("Paths")
            if caminhos then
                for _, part in pairs(caminhos:GetDescendants()) do
                    if part:IsA("BasePart") then
                        if estado == "LIGAR" then
                            if not part:FindFirstChild("PrioridadeCaminho") then
                                local mod = Instance.new("PathfindingModifier")
                                mod.Name = "PrioridadeCaminho"
                                mod.ModifierId = "CaminhoTop" -- Marca essa peça com ID especial
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

-- Transforma o próprio fogão/geladeira em fantasma para o GPS chegar BEM perto
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
    pcall(function()
        local char = Players.LocalPlayer.Character
        if char and char:FindFirstChild("Humanoid") and char:FindFirstChild("HumanoidRootPart") then
            char.Humanoid:MoveTo(char.HumanoidRootPart.Position)
        end
    end)
end

-- ==========================================
-- 👁️ LEITOR DA INTERFACE EXATA
-- ==========================================
local function LerStatusDaPorta()
    local player = Players.LocalPlayer
    local texto = nil
    local botao = nil

    pcall(function()
        -- Usando exatamente o caminho que você enviou
        local interactUI = player.PlayerGui:FindFirstChild("_interactUI")
        if interactUI then
            local indicator = interactUI:FindFirstChild("InteractIndicator")
            if indicator then
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

    local targetPos = typeof(destino) == "Instance" and (destino:IsA("Model") and destino:GetPivot().Position or destino.Position) or destino

    local maxTentativas = 4
    local tentativaAtual = 0

    while tentativaAtual < maxTentativas do
        if SmartDoor.CurrentWalkId ~= myWalkId then return false end 
        tentativaAtual = tentativaAtual + 1
        
        ConfigurarMapa("LIGAR")
        if typeof(destino) == "Instance" then TransformarAlvoEmFantasma(destino, "LIGAR") end

        -- GPS DE RESPEITO: AgentRadius ajustado para não entalar em portas
        local path = PathfindingService:CreatePath({
            AgentRadius = 0.8,     -- 📉 Diminuímos a "gordura" do bot
            AgentHeight = 5,
            AgentCanJump = true,
            WaypointSpacing = 1.5, -- 📉 Reduzido para evitar bugar em curvas
            Costs = {
                CaminhoTop = 0.1 -- Faz o GPS dar MUITA preferência para andar nas suas calçadas!
            }
        })

        local success, _ = pcall(function() path:ComputeAsync(hrp.Position, targetPos) end)

        ConfigurarMapa("DESLIGAR")
        if typeof(destino) == "Instance" then TransformarAlvoEmFantasma(destino, "DESLIGAR") end

        -- LIXO DA LINHA RETA REMOVIDO: Ou ele faz a rota certa, ou ele tenta de novo.
        if not success or path.Status ~= Enum.PathStatus.Success then
            LogSD("⚠️ Rota bloqueada ou falhou. Tentando recalcular...")
            task.wait(1)
        else
            -- TEMOS ROTA VÁLIDA
            local waypoints = path:GetWaypoints()
            LogSD("✅ Rota encontrada (Priorizando caminhos)!")

            for i, wp in ipairs(waypoints) do
                if SmartDoor.CurrentWalkId ~= myWalkId then return false end 
                
                if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end

                hum:MoveTo(wp.Position) 

                local tempoInicio = tick()
                local lastPos = hrp.Position
                local tempoChecagemStuck = tick()

                while (hrp.Position - wp.Position).Magnitude > 3.0 do
                    if SmartDoor.CurrentWalkId ~= myWalkId then return false end 

                    local status, botao = LerStatusDaPorta()
                    
                    if status and (string.find(status, "open") or string.find(status, "abrir")) then
                        LogSD("🚪 Porta fechada. Abrindo...")
                        hum:MoveTo(hrp.Position) -- Freia
                        
                        local tempoTentando = tick()
                        while tick() - tempoTentando < 4 do
                            if SmartDoor.CurrentWalkId ~= myWalkId then return false end 

                            local statusAtual, botaoAtual = LerStatusDaPorta()

                            if not statusAtual or string.find(statusAtual, "close") or string.find(statusAtual, "fechar") then
                                LogSD("🔓 Porta abriu, passando...")
                                break
                            elseif string.find(statusAtual, "open") or string.find(statusAtual, "abrir") then
                                if tick() - lastDoorClick > 0.5 then
                                    lastDoorClick = tick()
                                    if botaoAtual then ClicarNaUI(botaoAtual) end
                                    task.spawn(function()
                                        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                                        task.wait(0.1)
                                        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                                    end)
                                end
                            end
                            task.wait(0.1)
                        end
                        hum:MoveTo(wp.Position) -- Retoma a caminhada pro Waypoint
                    
                    elseif status and (string.find(status, "close") or string.find(status, "fechar")) then
                        -- Ignora e segue andando. A porta já está aberta!
                    end

                    -- Anti-stuck básico (se agarrar, ele pula)
                    if tick() - tempoChecagemStuck > 1.0 then
                        if (hrp.Position - lastPos).Magnitude < 0.5 then 
                            hum.Jump = true 
                            hum:MoveTo(wp.Position)
                        end
                        lastPos = hrp.Position
                        tempoChecagemStuck = tick()
                    end

                    if tick() - tempoInicio > 5.0 then 
                        break -- Cancela esse ponto e vai pro próximo se ficar travado tempo demais
                    end
                    task.wait() 
                end
            end

            -- Verifica a distância final exata
            if (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude < 5 then
                hum:MoveTo(hrp.Position)
                LogSD("🎯 Chegou no alvo final!")
                return true
            else
                LogSD("🚨 Bateu em algo no fim. Recalculando...")
            end
        end
    end

    LogSD("❌ Falhou de verdade. O Bloxburg é implacável.")
    return false
end

return SmartDoor
