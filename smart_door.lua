local PathfindingService = game:GetService("PathfindingService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Players = game:GetService("Players")

local SmartDoor = {} 
SmartDoor.CurrentWalkId = 0 
local lastDoorClick = 0

-- Sistema de Logs integrado com a sua UI do Hub
local function LogSD(msg)
    if _G.BloxburgChef_AddLog then
        _G.BloxburgChef_AddLog(msg, Color3.fromRGB(255, 170, 0)) -- Laranja para destacar
    else
        print(msg)
    end
end

-- Função para frear o boneco e cancelar a rota
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

-- Coleta as portas do mapa para desligar a colisão delas no cálculo
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

-- Interage com a porta apenas lendo a UI do jogo
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
                LogSD("🚪 Abrindo porta...")
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

-- Motor principal de caminhada
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

    LogSD("📍 Calculando rota para o destino...")

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

    -- CORREÇÃO AQUI: Boneco fininho para o Roblox não achar que a porta é pequena demais!
    local path = PathfindingService:CreatePath({
        AgentRadius = 0.5, 
        AgentHeight = 4, 
        AgentCanJump = true, 
        AgentMaxSlope = 45,
        WaypointSpacing = 3 
    })

    local success, err = pcall(function() path:ComputeAsync(hrp.Position, targetPos) end)

    for _, data in pairs(doorParts) do if data.part then data.part.CanCollide = data.coll end end
    for _, data in pairs(targetParts) do if data.part then data.part.CanCollide = data.coll end end

    if success and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        LogSD("✅ Rota criada com " .. #waypoints .. " passos.")

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
                        LogSD("⚠️ Preso! Pulando para tentar sair...")
                        hum.Jump = true 
                    end
                    lastPos = hrp.Position
                    tempoChecagemStuck = tick()
                end

                if tick() - tempoInicio > 3 then 
                    LogSD("⏳ Ponto demorou muito, ignorando...")
                    break 
                end

                if i >= #waypoints - 1 and (hrp.Position - targetPos).Magnitude < 4.5 then
                    LogSD("🎯 Destino alcançado!")
                    return true
                end

                task.wait() 
            end
        end
        
        local chegou = (hrp.Position - targetPos).Magnitude < 5
        if not chegou then LogSD("❌ Rota acabou mas não chegou perto.") end
        return chegou
    else
        LogSD("🚨 Pathfinding falhou! Tentando ir em linha reta...")
        
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
                    LogSD("⚠️ Travado na linha reta! Pulando...")
                    hum.Jump = true 
                end
                lastPos = hrp.Position
                tempoChecagemStuck = tick()
            end

            if tick() - tempoInicio > 5 then 
                LogSD("⏳ Desistiu da linha reta (Tempo esgotado).")
                break 
            end
            task.wait()
        end
        
        local chegou = (hrp.Position - flatTarget).Magnitude < 5
        if chegou then LogSD("🎯 Chegou na marra (linha reta)!") else LogSD("❌ Falhou na linha reta.") end
        return chegou
    end
end

return SmartDoor
