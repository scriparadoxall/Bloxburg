local PathfindingService = game:GetService("PathfindingService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Players = game:GetService("Players")

local SmartDoor = {} 
SmartDoor.CurrentWalkId = 0 
local lastDoorClick = 0

-- Sistema de Logs na sua UI
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

-- Acha TODAS as portas da casa lendo o Plot
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

-- Tenta interagir com a porta e avisa se conseguiu (para o boneco pausar)
local function HandleDoorInteraction(hrp, doors)
    if tick() - lastDoorClick < 1.5 then return false end 
    
    local portaMaisPerto = nil
    local menorDistancia = 7 

    for _, door in pairs(doors) do
        if door and door.Parent then
            local dist = (hrp.Position - door:GetPivot().Position).Magnitude
            if dist < menorDistancia then
                menorDistancia = dist
                portaMaisPerto = door
            end
        end
    end

    if portaMaisPerto then
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
                    LogSD("🚪 Porta detectada! Pressionando E...")
                    lastDoorClick = tick()
                    task.spawn(function()
                        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                        task.wait(0.1)
                        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                    end)
                    return true -- Retorna TRUE para o bot saber que precisa esperar ela abrir
                elseif string.find(txt, "close") or string.find(txt, "fechar") then
                    return false
                end
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
    local targetParts = {} 

    if typeof(destino) == "Instance" then
        targetPos = destino:IsA("Model") and destino:GetPivot().Position or destino.Position

        for _, part in pairs(destino:GetDescendants()) do
            if part:IsA("BasePart") then
                table.insert(targetParts, {part = part, coll = part.CanCollide})
                part.CanCollide = false
            end
        end
    elseif typeof(destino) == "Vector3" then 
        targetPos = destino
    else 
        return false 
    end

    LogSD("📍 Preparando mapa para calcular rota...")

    local doors = GetDoors()
    local doorParts = {}

    for _, door in pairs(doors) do
        for _, part in pairs(door:GetDescendants()) do
            if part:IsA("BasePart") then
                table.insert(doorParts, {part = part, coll = part.CanCollide})
                part.CanCollide = false
            end
        end
    end

    -- O GRANDE SEGREDO: Dá um tempinho pro Roblox atualizar o mapa 3D sem as portas!
    task.wait(0.15)

    local path = PathfindingService:CreatePath({
        AgentRadius = 1.0, 
        AgentHeight = 4, 
        AgentCanJump = true, 
        AgentMaxSlope = 45,
        WaypointSpacing = 3 
    })

    local success, err = pcall(function() path:ComputeAsync(hrp.Position, targetPos) end)

    -- Liga as colisões de volta
    for _, data in pairs(doorParts) do if data.part then data.part.CanCollide = data.coll end end
    for _, data in pairs(targetParts) do if data.part then data.part.CanCollide = data.coll end end

    if success and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        LogSD("✅ Rota traçada por dentro da casa (" .. #waypoints .. " passos).")

        for i, wp in ipairs(waypoints) do
            if SmartDoor.CurrentWalkId ~= myWalkId then return false end 

            if i == 1 and (hrp.Position - wp.Position).Magnitude < 3 then
                continue
            end

            if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end

            local tempoInicio = tick()
            local tempoChecagemStuck = tick()
            local lastPos = hrp.Position

            while (hrp.Position - wp.Position).Magnitude > 3.5 do
                if SmartDoor.CurrentWalkId ~= myWalkId then return false end 
                
                hum:MoveTo(wp.Position) 
                
                -- Se ele acabou de apertar E na porta, ele faz uma pausa pra ela abrir!
                local abriuPorta = HandleDoorInteraction(hrp, doors)
                if abriuPorta then
                    LogSD("⏳ Esperando a porta abrir...")
                    hum.Jump = true -- Dá um pulinho pra evitar bater
                    task.wait(0.6)
                end

                if tick() - tempoChecagemStuck > 0.6 then
                    if (hrp.Position - lastPos).Magnitude < 1 then
                        LogSD("⚠️ Preso! Forçando pulo...")
                        hum.Jump = true 
                    end
                    lastPos = hrp.Position
                    tempoChecagemStuck = tick()
                end

                if tick() - tempoInicio > 3.5 then 
                    break 
                end

                if i >= #waypoints - 1 and (hrp.Position - targetPos).Magnitude < 4.5 then
                    LogSD("🎯 Destino alcançado com sucesso!")
                    return true
                end

                task.wait() 
            end
        end
        
        local chegou = (hrp.Position - targetPos).Magnitude < 5
        return chegou
    else
        LogSD("🚨 Pathfinding falhou! (Rota reta ativada)")
        
        local flatTarget = Vector3.new(targetPos.X, hrp.Position.Y, targetPos.Z)
        local dir = (hrp.Position - flatTarget).Unit
        local walkPos = flatTarget + (dir * 2.8)
        
        local tempoInicio = tick()
        local tempoChecagemStuck = tick()
        local lastPos = hrp.Position

        while (hrp.Position - walkPos).Magnitude > 2 do
            if SmartDoor.CurrentWalkId ~= myWalkId then return false end
            
            hum:MoveTo(walkPos)
            
            if HandleDoorInteraction(hrp, doors) then
                task.wait(0.6)
            end
            
            if tick() - tempoChecagemStuck > 0.6 then
                if (hrp.Position - lastPos).Magnitude < 1 then 
                    hum.Jump = true 
                end
                lastPos = hrp.Position
                tempoChecagemStuck = tick()
            end

            if tick() - tempoInicio > 5 then break end
            task.wait()
        end
        
        return (hrp.Position - flatTarget).Magnitude < 5
    end
end

return SmartDoor
