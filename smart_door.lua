local PathfindingService = game:GetService("PathfindingService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Players = game:GetService("Players")

local SmartDoor = {} 
SmartDoor.CurrentWalkId = 0 
local lastDoorClick = 0

function SmartDoor.Cancelar()
    SmartDoor.CurrentWalkId = SmartDoor.CurrentWalkId + 1
    print("[SmartDoor] 🛑 Rota Cancelada!")
    pcall(function()
        local char = Players.LocalPlayer.Character
        if char and char:FindFirstChild("Humanoid") and char:FindFirstChild("HumanoidRootPart") then
            char.Humanoid:MoveTo(char.HumanoidRootPart.Position)
        end
    end)
end

local function GetDoors(scope)
    local doors = {}
    local searchArea = scope or workspace

    if searchArea:FindFirstChild("House") then
        local house = searchArea.House
        if house:FindFirstChild("Walls") then
            for _, wall in pairs(house.Walls:GetChildren()) do
                if wall:FindFirstChild("ItemHolder") then
                    for _, item in pairs(wall.ItemHolder:GetChildren()) do
                        local name = string.lower(item.Name)
                        if string.match(name, "door") or string.match(name, "porta") then
                            table.insert(doors, item)
                        end
                    end
                end
            end
        end
        if house:FindFirstChild("Doors") then
            for _, door in pairs(house.Doors:GetChildren()) do
                table.insert(doors, door)
            end
        end
    else
        for _, obj in pairs(searchArea:GetDescendants()) do
            if obj:IsA("Model") then
                local name = string.lower(obj.Name)
                if string.match(name, "door") or string.match(name, "porta") then
                    table.insert(doors, obj)
                end
            end
        end
    end
    return doors
end

local function HandleDoorInteraction()
    if tick() - lastDoorClick < 1 then return end 
    
    local PlayerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
    if not PlayerGui then return end

    local interactUI = PlayerGui:FindFirstChild("_interactUI")
    if interactUI then
        local center = interactUI:FindFirstChild("Center")
        local button = center and center:FindFirstChild("Button")
        local textLabel = button and button:FindFirstChild("TextLabel")
        
        if textLabel and textLabel.Text ~= "" then
            local txt = string.lower(textLabel.Text)
            
            if string.find(txt, "open") or string.find(txt, "abrir") then
                print("[SmartDoor] 🚪 Abrindo porta!")
                lastDoorClick = tick()
                task.spawn(function()
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                    task.wait(0.1)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                end)
            elseif string.find(txt, "close") or string.find(txt, "fechar") then
                return
            end
        end
    end
end

function SmartDoor.IrPara(destino, escopo_portas)
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

    print("[SmartDoor] 📍 Iniciando cálculo de rota para: ", targetPos)

    local doors = GetDoors(escopo_portas)
    local doorParts = {}

    for _, door in pairs(doors) do
        for _, part in pairs(door:GetDescendants()) do
            if part:IsA("BasePart") then
                table.insert(doorParts, {part = part, coll = part.CanCollide})
                part.CanCollide = false
            end
        end
    end

    -- Ajustado para 1.5 para ele caber nas portas do Bloxburg de novo
    local path = PathfindingService:CreatePath({
        AgentRadius = 1.5, 
        AgentHeight = 5, 
        AgentCanJump = true, 
        AgentMaxSlope = 45,
        WaypointSpacing = 3 
    })

    local success, err = pcall(function() path:ComputeAsync(hrp.Position, targetPos) end)

    for _, data in pairs(doorParts) do if data.part then data.part.CanCollide = data.coll end end
    for _, data in pairs(targetParts) do if data.part then data.part.CanCollide = data.coll end end

    if success then
        print("[SmartDoor] ⚙️ Status do Pathfinding:", tostring(path.Status))
    else
        warn("[SmartDoor] ❌ Erro ao calcular rota:", err)
    end

    if success and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        print("[SmartDoor] ✅ Rota inteligente criada com", #waypoints, "passos.")

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
                HandleDoorInteraction() 

                if tick() - tempoChecagemStuck > 0.6 then
                    if (hrp.Position - lastPos).Magnitude < 1 then
                        print("[SmartDoor] ⚠️ Boneco travou fisicamente! Pulando...")
                        hum.Jump = true 
                    end
                    lastPos = hrp.Position
                    tempoChecagemStuck = tick()
                end

                if tick() - tempoInicio > 3 then 
                    print("[SmartDoor] ⏳ Demorou muito num waypoint, pulando pro próximo.")
                    break 
                end

                if i >= #waypoints - 1 and (hrp.Position - targetPos).Magnitude < 4.5 then
                    print("[SmartDoor] 🎯 Chegou no destino via rota inteligente!")
                    return true
                end

                task.wait() 
            end
        end
        
        if (hrp.Position - targetPos).Magnitude < 5 then
            return true
        else
            print("[SmartDoor] ❌ Fim da rota, mas ainda está longe do alvo.")
            return false
        end
    else
        warn("[SmartDoor] 🚨 Pathfinding falhou! Usando rota burra (linha reta).")
        
        local flatTarget = Vector3.new(targetPos.X, hrp.Position.Y, targetPos.Z)
        local dir = (hrp.Position - flatTarget).Unit
        local walkPos = flatTarget + (dir * 2.8)
        
        local tempoInicio = tick()
        local tempoChecagemStuck = tick()
        local lastPos = hrp.Position

        while (hrp.Position - walkPos).Magnitude > 2 do
            if SmartDoor.CurrentWalkId ~= myWalkId then return false end
            
            hum:MoveTo(walkPos)
            HandleDoorInteraction() 
            
            if tick() - tempoChecagemStuck > 0.6 then
                if (hrp.Position - lastPos).Magnitude < 1 then 
                    print("[SmartDoor] ⚠️ Travado na linha reta! Pulando...")
                    hum.Jump = true 
                end
                lastPos = hrp.Position
                tempoChecagemStuck = tick()
            end

            if tick() - tempoInicio > 5 then 
                print("[SmartDoor] ⏳ Desistiu da linha reta por tempo.")
                break 
            end
            task.wait()
        end
        
        local chegou = (hrp.Position - flatTarget).Magnitude < 5
        if chegou then print("[SmartDoor] 🎯 Chegou no destino na linha reta!") end
        return chegou
    end
end

return SmartDoor
