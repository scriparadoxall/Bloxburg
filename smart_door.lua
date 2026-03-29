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

        local path = PathfindingService:CreatePath({
            AgentRadius = 0.8, 
            AgentHeight = 5, 
            AgentCanJump = true, 
            WaypointSpacing = 3 
        })

        local success, err = pcall(function() path:ComputeAsync(hrp.Position, targetPos) end)

        AlterarFantasmas("DESLIGAR")
        if typeof(destino) == "Instance" then TransformarAlvoEmFantasma(destino, "DESLIGAR") end

        if success and (path.Status == Enum.PathStatus.Success or path.Status == Enum.PathStatus.ClosestNoPath) then
            local waypoints = path:GetWaypoints()
            local limiteDePassos = #waypoints

            if path.Status == Enum.PathStatus.ClosestNoPath and limiteDePassos > 1 then
                limiteDePassos = limiteDePassos - 1
            end

            LogSD("✅ Rota segura encontrada! Andando...")
            local chegouNoAlvo = false

            for i = 1, limiteDePassos do
                if SmartDoor.CurrentWalkId ~= myWalkId then return false end 
                local wp = waypoints[i]
                
                if i == 1 and (hrp.Position - wp.Position).Magnitude < 3 then continue end
                if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end

                local tempoInicioWhileLoop = tick()
                local tempoChecagemStuck = tick()
                local tempoDoUltimoCheckDePortaDentroDoWhile = tick() -- NOVA VARIAVEL THRESHOLD

                -- Ordem de andar UMA ÚNICA VEZ fora do while para suavidade
                hum:MoveTo(wp.Position) 

                while (hrp.Position - wp.Position).Magnitude > 1.5 do
                    if SmartDoor.CurrentWalkId ~= myWalkId then return false end 
                    
                    -- FREIO DE PROXIMIDADE (Mantemos, é rápido)
                    local dist2D = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
                    if dist2D <= 3.0 then
                        LogSD("🎯 Chegou perfeitamente na frente do alvo!")
                        hum:MoveTo(hrp.Position) 
                        chegouNoAlvo = true
                        break
                    end

                    -- ==============================================================
                    -- REDUZINDO O LAG: THROTTLE DO CHECK DE PORTA
                    -- ==============================================================
                    -- Em vez de verificar GUI/texto todo frame (0.01s), verificamos a cada 0.15s
                    if tick() - tempoDoUltimoCheckDePortaDentroDoWhile > 0.15 then
                        local textoUI = LerTextoDaInterface()
                        
                        if textoUI and (string.find(textoUI, "open") or string.find(textoUI, "abrir")) then
                            LogSD("🚪 Porta na frente! Puxando o freio para abrir...")
                            hum:MoveTo(hrp.Position) -- Puxa o freio imediatamente
                            
                            local tempoTentando = tick()
                            -- Loop intenso de abertura, mas boneco parado, então sem lag de caminhada
                            while tick() - tempoTentando < 5 do
                                if SmartDoor.CurrentWalkId ~= myWalkId then return false end 
                                
                                local statusAtual = LerTextoDaInterface()
                                
                                if statusAtual then
                                    if string.find(statusAtual, "close") or string.find(statusAtual, "fechar") then
                                        LogSD("🔓 O caminho está livre! Retomando a caminhada...")
                                        task.wait(0.3) 
                                        -- A porta abriu, manda ele voltar a andar UMA vez de novo!
                                        hum:MoveTo(wp.Position)
                                        break 
                                        
                                    elseif string.find(statusAtual, "open") or string.find(statusAtual, "abrir") then
                                        if tick() - lastDoorClick > 1.0 then
                                            lastDoorClick = tick()
                                            LogSD("👉 Apertando E para abrir...")
                                            task.spawn(function()
                                                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                                                task.wait(0.1)
                                                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                                            end)
                                        end
                                    end
                                else
                                    -- Micro passinho se a UI sumir
                                    hum:MoveTo(wp.Position)
                                    task.wait(0.1)
                                    hum:MoveTo(hrp.Position)
                                end
                                task.wait(0.2)
                            end
                        end
                        tempoDoUltimoCheckDePortaDentroDoWhile = tick() -- Reseta timer de porta
                    end

                    -- STUCK CHECK (Mantemos throttled a 0.6s)
                    if tick() - tempoChecagemStuck > 0.6 then
                        if (hrp.Position - lastPos).Magnitude < 1 then hum.Jump = true end
                        lastPos = hrp.Position
                        tempoChecagemStuck = tick()
                    end

                    if tick() - tempoInicioWhileLoop > 3.5 then break end
                    task.wait() -- Espera um frame físico
                end

                if chegouNoAlvo then break end
                
                -- Check de segurança 2D fora do while
                local dist2D = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
                if dist2D <= 3.0 then
                    hum:MoveTo(hrp.Position)
                    chegouNoAlvo = true
                    break
                end
            end

            if chegouNoAlvo or (hrp.Position - targetPos).Magnitude < 7 then
                LogSD("✅ Posicionado e pronto para interagir!")
                return true
            else
                LogSD("🚨 Não chegou perto o suficiente. Recalculando...")
            end

        else
            LogSD("🚨 Caminho bloqueado pelo labirinto de paredes! Tentando dnv...")
            task.wait(1) 
        end
    end

    LogSD("❌ Falhou após várias tentativas.")
    return false
end

return SmartDoor
