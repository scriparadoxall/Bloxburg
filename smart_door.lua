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
        print(msg)
    end
end

-- ==========================================
-- 🚪 GERENCIAMENTO DOS FANTASMAS
-- ==========================================
local function AlterarFantasmas(estado)
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return end

    for _, plot in pairs(plots:GetChildren()) do
        if plot:FindFirstChild("House") and plot.House:FindFirstChild("Walls") then
            for _, obj in pairs(plot.House.Walls:GetDescendants()) do
                if obj:IsA("BasePart") then
                    local nome = string.lower(obj.Name)
                    local nomePai = obj.Parent and string.lower(obj.Parent.Name) or ""
                    
                    if string.find(nome, "door") or string.find(nomePai, "door") then
                        if estado == "LIGAR" then
                            if not obj:FindFirstChild("IgnorarNoGPS") then
                                local modifier = Instance.new("PathfindingModifier")
                                modifier.Name = "IgnorarNoGPS"
                                modifier.PassThrough = true
                                modifier.Parent = obj
                            end
                        elseif estado == "DESLIGAR" then
                            local fantasma = obj:FindFirstChild("IgnorarNoGPS")
                            if fantasma then fantasma:Destroy() end
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
-- 👁️ LEITOR DE PLACAS DA PORTA
-- ==========================================
local function LerTextoDaInterface()
    local PlayerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
    if not PlayerGui then return nil end

    local interactUI = PlayerGui:FindFirstChild("_interactUI")
    if interactUI then
        local indicator = interactUI:FindFirstChild("InteractIndicator")
        local textLabel = indicator and indicator:FindFirstChild("TextLabel")

        if not textLabel then
            local center = interactUI:FindFirstChild("Center")
            local button = center and center:FindFirstChild("Button")
            textLabel = button and button:FindFirstChild("TextLabel")
        end

        if textLabel and textLabel.Text ~= "" then
            return string.lower(textLabel.Text)
        end
    end
    return nil
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

        -- LÓGICA FLUIDA E FINA: Radius 0.1 pra não bugar nas portas, WaypointSpacing 4 pra passos longos e fluidos
        local path = PathfindingService:CreatePath({
            AgentRadius = 0.1, 
            AgentHeight = 4, 
            AgentCanJump = true, 
            WaypointSpacing = 4 
        })

        local success, err = pcall(function() path:ComputeAsync(hrp.Position, targetPos) end)

        AlterarFantasmas("DESLIGAR")
        if typeof(destino) == "Instance" then TransformarAlvoEmFantasma(destino, "DESLIGAR") end

        local waypoints = {}
        
        -- SISTEMA FALLBACK (Corrige o erro do quintal/areia sem NavMesh)
        if success and (path.Status == Enum.PathStatus.Success or path.Status == Enum.PathStatus.ClosestNoPath) then
            waypoints = path:GetWaypoints()
            LogSD("✅ Rota encontrada pelo GPS!")
        else
            LogSD("⚠️ GPS falhou. Forçando caminhada em linha reta!")
            waypoints = {
                PathWaypoint.new(targetPos, Enum.PathWaypointAction.Walk)
            }
        end

        for i, wp in ipairs(waypoints) do
            if SmartDoor.CurrentWalkId ~= myWalkId then return false end 
            
            if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end

            -- MANDAR ANDAR UMA ÚNICA VEZ POR PONTO (Isso evita os engasgos da engine)
            hum:MoveTo(wp.Position) 
            
            local tempoInicio = tick()
            local lastPos = hrp.Position
            local tempoChecagemStuck = tick()

            -- Distância > 4.0: Ele "corta caminho" pro próximo ponto sem parar 100% no anterior
            while (hrp.Position - wp.Position).Magnitude > 4.0 do
                if SmartDoor.CurrentWalkId ~= myWalkId then return false end 
                
                -- Check Final de Proximidade (3.5 studs de distância da peça exata)
                local distFinal = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
                if distFinal <= 3.5 then
                    LogSD("🎯 Chegou no alvo final!")
                    hum:MoveTo(hrp.Position) 
                    return true
                end

                local textoUI = LerTextoDaInterface()
                if textoUI and (string.find(textoUI, "open") or string.find(textoUI, "abrir")) then
                    LogSD("🚪 Porta trancada detectada! Puxando freio...")
                    hum:MoveTo(hrp.Position) 
                    
                    local tempoTentando = tick()
                    while tick() - tempoTentando < 5 do
                        if SmartDoor.CurrentWalkId ~= myWalkId then return false end 
                        
                        local statusAtual = LerTextoDaInterface()
                        
                        if not statusAtual or string.find(statusAtual, "close") or string.find(statusAtual, "fechar") then
                            LogSD("🔓 Caminho livre! Voltando a correr...")
                            break
                        elseif string.find(statusAtual, "open") or string.find(statusAtual, "abrir") then
                            if tick() - lastDoorClick > 0.5 then
                                lastDoorClick = tick()
                                task.spawn(function()
                                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                                    task.wait(0.1)
                                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                                end)
                            end
                        end
                        task.wait(0.1)
                    end
                    -- Retoma o movimento após a porta abrir
                    hum:MoveTo(wp.Position) 
                end

                -- Sistema Anti-Travar na Parede
                if tick() - tempoChecagemStuck > 0.8 then
                    if (hrp.Position - lastPos).Magnitude < 1 then 
                        hum.Jump = true 
                        hum:MoveTo(wp.Position)
                    end
                    lastPos = hrp.Position
                    tempoChecagemStuck = tick()
                end

                if tick() - tempoInicio > 3.0 then break end
                
                -- THROTTLE PARA FLUIDEZ: Processa a lógica só 10x por segundo, liberando o jogo para andar liso
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
