local PathfindingService = game:GetService("PathfindingService") -- Corrigido o "local" minúsculo
local VirtualInputManager = game:GetService("VirtualInputManager")
local Players = game:GetService("Players")

-- Usando getgenv() para compartilhar com qualquer outro script!
getgenv().SmartDoor = {} 

local lastDoorClick = 0

local function GetDoors(scope)
    local doors = {}
    local searchArea = scope or workspace
    for _, obj in pairs(searchArea:GetDescendants()) do
        if obj:IsA("Model") and (string.match(string.lower(obj.Name), "door") or string.match(string.lower(obj.Name), "porta")) then
            table.insert(doors, obj)
        end
    end
    return doors
end

local function OpenNearbyDoors(hrp, doors)
    if tick() - lastDoorClick < 2.5 then return end
    for _, door in pairs(doors) do
        if door and door.Parent then
            local dist = (hrp.Position - door:GetPivot().Position).Magnitude
            if dist < 6 then
                lastDoorClick = tick()
                task.spawn(function()
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                    task.wait(0.1)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                end)
                break 
            end
        end
    end
end

-- CORRIGIDO A SINTAXE DA FUNÇÃO AQUI:
getgenv().SmartDoor.IrPara = function(destino, escopo_portas)
    local player = Players.LocalPlayer
    local char = player.Character
    if not char or not char:FindFirstChild("Humanoid") or not char:FindFirstChild("HumanoidRootPart") then 
        return false 
    end

    local hrp = char.HumanoidRootPart
    local hum = char.Humanoid

    local targetPos
    if typeof(destino) == "Vector3" then targetPos = destino
    elseif typeof(destino) == "Instance" and destino:IsA("Model") then targetPos = destino:GetPivot().Position
    elseif typeof(destino) == "Instance" and destino:IsA("BasePart") then targetPos = destino.Position
    else return false end

    local flatTarget = Vector3.new(targetPos.X, hrp.Position.Y, targetPos.Z)
    local dir = (hrp.Position - flatTarget).Unit
    local walkPos = flatTarget + (dir * 2.8)

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
        AgentRadius = 1.5, AgentHeight = 5, AgentCanJump = true, AgentMaxSlope = 45,
    })

    local success, err = pcall(function() path:ComputeAsync(hrp.Position, walkPos) end)

    for _, data in pairs(doorParts) do
        if data.part then data.part.CanCollide = data.coll end
    end

    if success and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        for i, wp in ipairs(waypoints) do
            if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
            hum:MoveTo(wp.Position)

            local timeOut = 0
            while (hrp.Position - wp.Position).Magnitude > 2.5 and timeOut < 40 do
                OpenNearbyDoors(hrp, doors) 
                if hum.MoveDirection.Magnitude < 0.1 and timeOut > 5 then hum.Jump = true end
                task.wait(0.05)
                timeOut = timeOut + 1
            end
        end
        return true
    else
        hum:MoveTo(walkPos)
        local timeOut = 0
        while (hrp.Position - walkPos).Magnitude > 1.5 and timeOut < 60 do
            OpenNearbyDoors(hrp, doors)
            if hum.MoveDirection.Magnitude < 0.1 and timeOut > 5 then hum.Jump = true end
            task.wait(0.05)
            timeOut = timeOut + 1
        end
        return true 
    end
end
