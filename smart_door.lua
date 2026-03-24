local PathfindingService = game:GetService("PathfindingService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Players = game:GetService("Players")

local SmartDoor = {} 
local lastDoorClick = 0

local function GetDoors(scope)
    local doors = {}
    local searchArea = (scope and scope:FindFirstChild("House")) or scope or workspace
    for _, obj in pairs(searchArea:GetDescendants()) do
        if obj:IsA("Model") then
            local name = string.lower(obj.Name)
            if string.match(name, "door") or string.match(name, "porta") then
                table.insert(doors, obj)
            end
        end
    end
    return doors
end

local function OpenNearbyDoors(hrp, doors)
    if tick() - lastDoorClick < 2.5 then return end
    for _, door in pairs(doors) do
        if door and door.Parent then
            local dist = (hrp.Position - door:GetPivot().Position).Magnitude
            if dist < 6.5 then 
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

getgenv().SmartDoor.IrPara = function(destino, escopo_portas)
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
        
        -- MODO FANTASMA: Desliga a colisão do móvel temporariamente
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

    -- Restaura a colisão instantaneamente
    for _, data in pairs(doorParts) do if data.part then data.part.CanCollide = data.coll end end
    for _, data in pairs(targetParts) do if data.part then data.part.CanCollide = data.coll end end

    if success and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        
        for i, wp in ipairs(waypoints) do
            -- Evita o solavanco inicial se o ponto estiver muito perto
            if i == 1 and (hrp.Position - wp.Position).Magnitude < 3 then
                continue
            end

            if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
            hum:MoveTo(wp.Position)

            local tempoInicio = tick()
            
            -- A MÁGICA DA FLUIDEZ AQUI: > 3.5 studs em vez de 2.5
            while (hrp.Position - wp.Position).Magnitude > 3.5 do
                OpenNearbyDoors(hrp, doors) 
                
                -- Anti-Stuck por tempo (se ficar preso em algo invisível por 2s, pula)
                if tick() - tempoInicio > 2 then 
                    hum.Jump = true 
                    break 
                end
                
                -- Se estiver a chegar ao móvel (últimos waypoints), trava em segurança
                if i >= #waypoints - 1 and (hrp.Position - flatTarget).Magnitude < 3.2 then
                    return true
                end
                
                task.wait() -- Sem número, atualiza super rápido e remove qualquer engasgo
            end
        end
        return true
    else
        -- Fallback de emergência em linha reta
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

getgenv().SmartDoor = SmartDoor
