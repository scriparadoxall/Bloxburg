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
-- 🚪 INTERAÇÃO PRECISA COM A PORTA
-- ==========================================
local function HandleDoorInteraction()
    if tick() - lastDoorClick < 1.0 then return false end 

    local PlayerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
    if not PlayerGui then return false end

    local interactUI = PlayerGui:FindFirstChild("_interactUI")
    if interactUI then
        -- Usa o caminho exato que você descobriu no Dex!
        local indicator = interactUI:FindFirstChild("InteractIndicator")
        local textLabel = indicator and indicator:FindFirstChild("TextLabel")

        -- Fallback de segurança pro padrão antigo caso o jogo mude
        if not textLabel then
            local center = interactUI:FindFirstChild("Center")
            local button = center and center:FindFirstChild("Button")
            textLabel = button and button:FindFirstChild("TextLabel")
        end

        if textLabel and textLabel.Text ~= "" then
            local txt = string.lower(textLabel.Text)
            
            -- Se já tá "Close", a porta tá aberta! Ignora e passa reto.
            if string.find(txt, "close") or string.find(txt, "fechar") then
                return false
            end

            -- Só aperta E se for pra Abrir
            if string.find(txt, "open") or string.find(txt, "abrir") then
                LogSD("🚪 UI de abrir detectada! Apertando E...")
                lastDoorClick = tick()
                task.spawn(function()
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                    task.wait(0.1)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                end)
                return true 
            end
        end
    end
    return false
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

        local path = PathfindingService:CreatePath({
            AgentRadius = 1.2, 
            AgentHeight = 5, 
            AgentCanJump = true, 
            WaypointSpacing = 3 
        })

        local success, err = pcall(function() path:ComputeAsync(hrp.Position, targetPos) end)

        AlterarFantasmas("DESLIGAR")

        if success and path.Status == Enum.PathStatus.Success then
            local waypoints = path:GetWaypoints()
            LogSD("✅ Rota livre encontrada! Andando...")

            local precisouRecalcular = false

            for i, wp in ipairs(waypoints) do
                if SmartDoor.CurrentWalkId ~= myWalkId then return false end 
                if i == 1 and (hrp.Position - wp.Position).Magnitude < 3 then continue end
                if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end

                local tempoInicio = tick()
                local tempoChecagemStuck = tick()
                local lastPos = hrp.Position

                while (hrp.Position - wp.Position).Magnitude > 3.5 do
                    if SmartDoor.CurrentWalkId ~= myWalkId then return false end 
                    hum:MoveTo(wp.Position) 

                    -- Checa se trombou numa porta fechada
                    if HandleDoorInteraction() then
                        LogSD("⏳ Aguardando a porta abrir fisicamente...")
                        hum:MoveTo(hrp.Position) 
                        task.wait(1.5) 
                        precisouRecalcular = true
                        break
                    end

                    if tick() - tempoChecagemStuck > 0.6 then
                        if (hrp.Position - lastPos).Magnitude < 1 then hum.Jump = true end
                        lastPos = hrp.Position
                        tempoChecagemStuck = tick()
                    end

                    if tick() - tempoInicio > 3.5 then break end
                    task.wait() 
                end

                if precisouRecalcular then break end
            end

            if not precisouRecalcular then
                if (hrp.Position - targetPos).Magnitude < 5 then
                    LogSD("🎯 Destino alcançado com sucesso!")
                    return true
                end
            end

        else
            LogSD("🚨 Caminho bloqueado estruturalmente! Cancelando.")
            break
        end
    end

    LogSD("❌ Falhou após várias tentativas.")
    return false
end

return SmartDoor
