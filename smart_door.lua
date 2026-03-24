local PathfindingService = game:GetService("PathfindingService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Players = game:GetService("Players")

local SmartDoor = {} 
local lastDoorClick = 0

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

local function OpenNearbyDoors(hrp, doors)
    -- Cooldown reduzido de 2.5s para 1s, pois agora ele é mais inteligente e não erra
    if tick() - lastDoorClick < 1 then return end 
    
    for _, door in pairs(doors) do
        if door and door.Parent then
            local dist = (hrp.Position - door:GetPivot().Position).Magnitude
            if dist < 6.5 then 
                
                -- Checa a UI para ver se a porta está aberta ou fechada
                local PlayerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
                if PlayerGui then
                    local interactUI = PlayerGui:FindFirstChild("_interactUI")
                    if interactUI then
                        local center = interactUI:FindFirstChild("Center")
                        local button = center and center:FindFirstChild("Button")
                        local textLabel = button and button:FindFirstChild("TextLabel")
                        
                        if textLabel and textLabel.Text ~= "" then
                            local txt = string.lower(textLabel.Text)
                            
                            -- Se disser "Open" ou "Abrir", ele aperta E
                            if string.find(txt, "open") or string.find(txt, "abrir") then
                                lastDoorClick = tick()
                                task.spawn(function()
                                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                                    task.wait(0.1)
                                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                                end)
                                break 
                                
                            -- Se disser "Close" ou "Fechar", ele passa reto
                            elseif string.find(txt, "close") or string.find(txt, "fechar") then
                                break 
                            end
                        end
                    end
                end
            end
        end
    end
end

function SmartDoor.IrPara(destino, escopo_portas)
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

    local flatTarget = Vector3.new(targetPos.X, hrp.Position.Y, targetPos.Z)
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

    local path = PathfindingService:CreatePath({
        AgentRadius = 1.2, 
        AgentHeight = 5, 
        AgentCanJump = true, 
        AgentMaxSlope = 45,
    })

    local success, err = pcall(function() path:ComputeAsync(hrp.Position, flatTarget) end)

    for _, data in pairs(doorParts) do if data.part then data.part.CanCollide = data.coll end end
    for _, data in pairs(targetParts) do if data.part then data.part.CanCollide = data.coll end end

    if success and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()

        for i, wp in ipairs(waypoints) do
            if i == 1 and (hrp.Position - wp.Position).Magnitude < 3 then
                continue
            end

            if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
            hum:MoveTo(wp.Position)

            local tempoInicio = tick()

            while (hrp.Position - wp.Position).Magnitude > 3.5 do
                OpenNearbyDoors(hrp, doors) 

                if tick() - tempoInicio > 2 then 
                    hum.Jump = true 
                    break 
                end

                if i >= #waypoints - 1 and (hrp.Position - flatTarget).Magnitude < 3.2 then
                    return true
                end

                task.wait() 
            end
        end
        return true
    else
        local dir = (hrp.Position - flatTarget).Unit
        local walkPos = flatTarget + (dir * 2.8)
        hum:MoveTo(walkPos)

        local tempoInicio = tick()
        while (hrp.Position - walkPos).Magnitude > 1.5 do
            OpenNearbyDoors(hrp, doors)
            if tick() - tempoInicio > 5 then hum.Jump = true; break end
            task.wait()
        end
        return true 
    end
end

return SmartDoor
