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

local function GetDoors()
    local doors = {}
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return doors end

    for _, plot in pairs(plots:GetChildren()) do
        local house = plot:FindFirstChild("House")
        if house then
            local walls = house:FindFirstChild("Walls")
            if walls then
                for _, wall in pairs(walls:GetChildren()) do
                    local itemHolder = wall:FindFirstChild("ItemHolder")
                    if itemHolder then
                        for _, item in pairs(itemHolder:GetChildren()) do
                            local name = string.lower(item.Name)
                            if string.find(name, "door") or string.find(name, "porta") then
                                table.insert(doors, item)
                            end
                        end
                    end
                end
            end
        end
    end
    return doors
end

local function HandleDoorInteraction(hrp, doors)
    if tick() - lastDoorClick < 1.0 then return false end 
    
    local PlayerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
    if not PlayerGui then return false end

    local interactUI = PlayerGui:FindFirstChild("_interactUI")
    if interactUI then
        local center = interactUI:FindFirstChild("Center")
        local button = center and center:FindFirstChild("Button")
        local textLabel = button and button:FindFirstChild("TextLabel")
        
        if textLabel and textLabel.Text ~= "" then
            local txt = string.lower(textLabel.Text)
            if string.find(txt, "open") or string.find(txt, "abrir") then
                LogSD("🚪 UI de abrir detectada! Apertando E...")
                lastDoorClick = tick()
                task.spawn(function()
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                    task.wait(0.1)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                end)
                return true 
            elseif string.find(txt, "close") or string.find(txt, "fechar") then
                return false
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
        LogSD("📍 Calculando rota pra geladeira (Tentativa " .. tentativaAtual .. "/5)...")

        local doors = GetDoors()

        local path = PathfindingService:CreatePath({
            AgentRadius = 1.0, 
            AgentHeight = 4, 
            AgentCanJump = true, 
            WaypointSpacing = 3 
        })

        local success, err = pcall(function() path:ComputeAsync(hrp.Position, targetPos) end)

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
                    
                    if HandleDoorInteraction(hrp, doors) then
                        LogSD("⏳ Abriu uma porta no meio do caminho! Recalculando...")
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
            LogSD("🚨 Caminho bloqueado! Achando a porta mais próxima...")
            
            local bestDoor = nil
            local bestDist = math.huge

            for _, door in pairs(doors) do
                if door and door.Parent then
                    local dPos = door:GetPivot().Position
                    local dist = (hrp.Position - dPos).Magnitude
                    if dist < bestDist then
                        bestDist = dist
                        bestDoor = door
                    end
                end
            end

            if bestDoor then
                local doorPos = bestDoor:GetPivot().Position
                LogSD("🚶 Indo até a porta pra destrancar...")

                local doorPath = PathfindingService:CreatePath({ AgentRadius = 1.0, AgentHeight = 4, AgentCanJump = true })
                doorPath:ComputeAsync(hrp.Position, doorPos)

                local dWaypoints = {}
                if doorPath.Status == Enum.PathStatus.Success then
                    dWaypoints = doorPath:GetWaypoints()
                else
                    table.insert(dWaypoints, {Position = doorPos, Action = Enum.PathWaypointAction.Walk})
                end

                local abriuPorta = false

                for i, wp in ipairs(dWaypoints) do
                    if SmartDoor.CurrentWalkId ~= myWalkId then return false end
                    if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end

                    local tempoInicio = tick()
                    local tempoChecagemStuck = tick()
                    local lastPos = hrp.Position

                    while (hrp.Position - wp.Position).Magnitude > 3 do
                        if SmartDoor.CurrentWalkId ~= myWalkId then return false end
                        
                        local distParaPorta = (hrp.Position - doorPos).Magnitude
                        
                        -- AUMENTADA A DISTÂNCIA DE FREIO PARA 6.5 (Bem mais longe da porta)
                        if distParaPorta < 6.5 then
                            LogSD("🛑 Distância segura atingida. Parando de frente pra porta...")
                            
                            -- Dá um passinho minúsculo em direção à porta só pra alinhar o corpo e ajudar a UI a aparecer
                            hum:MoveTo(doorPos)
                            task.wait(0.1)
                            hum:MoveTo(hrp.Position) -- Puxa o freio de vez
                            
                            local apertouNaUI = false
                            local tempoParado = tick()
                            
                            -- Fica 2 segundos parado tentando ler a UI pra apertar E
                            while tick() - tempoParado < 2 do
                                if HandleDoorInteraction(hrp, doors) then
                                    LogSD("✅ Apertou E pela UI! Esperando a porta abrir...")
                                    task.wait(1.5)
                                    abriuPorta = true
                                    apertouNaUI = true
                                    break
                                end
                                task.wait(0.2)
                            end
                            
                            -- SISTEMA DE FORÇA BRUTA: Se a UI não apareceu em 2 segundos, aperta E na marra!
                            if not apertouNaUI then
                                LogSD("⚠️ UI não apareceu. Forçando o E por segurança!")
                                task.spawn(function()
                                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                                    task.wait(0.1)
                                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                                end)
                                task.wait(1.5)
                                abriuPorta = true
                            end
                            
                            break -- Sai do loop de andar em direção à porta
                        end

                        hum:MoveTo(wp.Position)

                        if HandleDoorInteraction(hrp, doors) then
                            LogSD("✅ Apertou E no caminho! Esperando abrir...")
                            hum:MoveTo(hrp.Position)
                            task.wait(1.5) 
                            abriuPorta = true
                            break
                        end

                        if tick() - tempoChecagemStuck > 0.6 then
                            if (hrp.Position - lastPos).Magnitude < 1 then hum.Jump = true end
                            lastPos = hrp.Position
                            tempoChecagemStuck = tick()
                        end

                        if tick() - tempoInicio > 4 then break end
                        task.wait()
                    end
                    if abriuPorta or (hrp.Position - doorPos).Magnitude < 6.5 then break end 
                end
            else
                LogSD("❌ Nenhuma porta encontrada! Tentando ir reto...")
                local flatTarget = Vector3.new(targetPos.X, hrp.Position.Y, targetPos.Z)
                hum:MoveTo(flatTarget)
                task.wait(2)
            end
        end
    end

    LogSD("❌ Falhou após várias tentativas. Casa totalmente trancada.")
    return false
end

return SmartDoor
