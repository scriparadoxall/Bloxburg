-- ==========================================
-- MÓDULO: SMART DOOR & NAVIGATION
-- ==========================================
local PathfindingService = game:GetService("PathfindingService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Players = game:GetService("Players")

_G.SmartDoor = {}

-- Variável de controle para não spammar a tecla "E" e bugar a porta
local lastDoorClick = 0

-- Função interna para listar todas as portas (Pode passar um escopo, ex: lote do jogador)
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

-- Função interna que aperta "E" se tiver porta perto
local function OpenNearbyDoors(hrp, doors)
    if tick() - lastDoorClick < 2 then return end -- Cooldown de 2 segundos

    for _, door in pairs(doors) do
        if door and door.Parent then
            local dist = (hrp.Position - door:GetPivot().Position).Magnitude
            
            -- Se a porta estiver a menos de 6 studs de distância, ele abre
            if dist < 6 then
                lastDoorClick = tick()
                task.spawn(function()
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                    task.wait(0.1)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                end)
                break -- Já abriu a porta mais próxima, sai do loop
            end
        end
    end
end

-- ==========================================
-- FUNÇÃO PRINCIPAL: CHAME ESSA NOS SEUS SCRIPTS
-- ==========================================
-- @param destino: Pode ser um Vector3 (coordenada) ou uma Instance (Móvel, Peça, etc)
-- @param escopo_portas (Opcional): A pasta da casa para ele não procurar portas no mapa inteiro
function _G.SmartDoor.IrPara(destino, escopo_portas)
    local player = Players.LocalPlayer
    local char = player.Character
    if not char or not char:FindFirstChild("Humanoid") or not char:FindFirstChild("HumanoidRootPart") then 
        return false 
    end

    local hrp = char.HumanoidRootPart
    local hum = char.Humanoid
    
    -- Descobre se você mandou uma coordenada exata ou um objeto
    local targetPos
    if typeof(destino) == "Vector3" then
        targetPos = destino
    elseif typeof(destino) == "Instance" and destino:IsA("Model") then
        targetPos = destino:GetPivot().Position
    elseif typeof(destino) == "Instance" and destino:IsA("BasePart") then
        targetPos = destino.Position
    else
        warn("[SmartDoor] Destino inválido! Passe um Vector3 ou um Objeto.")
        return false
    end

    -- 1. Coleta portas e desativa colisão temporariamente
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

    -- 2. Cria a inteligência do caminho
    local path = PathfindingService:CreatePath({
        AgentRadius = 1.5,   -- Raio magro para passar em portas do Bloxburg
        AgentHeight = 5,
        AgentCanJump = true,
        AgentMaxSlope = 45,
    })

    local success, err = pcall(function()
        path:ComputeAsync(hrp.Position, targetPos)
    end)

    -- 3. Restaura a colisão das portas IMEDIATAMENTE antes de começar a andar
    for _, data in pairs(doorParts) do
        if data.part then data.part.CanCollide = data.coll end
    end

    -- 4. Começa a caminhar pela rota calculada
    if success and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()

        for i, wp in ipairs(waypoints) do
            -- Se o caminho mandar pular, ele pula
            if wp.Action == Enum.PathWaypointAction.Jump then
                hum.Jump = true
            end

            hum:MoveTo(wp.Position)

            local timeOut = 0
            -- Loop que segura o script enquanto o boneco anda até o ponto atual
            while (hrp.Position - wp.Position).Magnitude > 3 and timeOut < 40 do
                -- CHAMA A INTELIGÊNCIA DA PORTA AQUI! (Checa enquanto caminha)
                OpenNearbyDoors(hrp, doors) 
                
                -- Sistema Anti-Stuck: Se o boneco enroscou em algo (velocidade quase 0), ele tenta pular
                if hum.MoveDirection.Magnitude < 0.1 and timeOut > 5 then
                    hum.Jump = true
                end
                
                task.wait(0.05)
                timeOut = timeOut + 1
            end
        end
        return true -- Retorna true avisando o seu script principal que chegou no destino
    else
        warn("[SmartDoor] Caminho bloqueado! Não encontrei rota para o destino.")
        -- Fallback de emergência: vai reto
        hum:MoveTo(targetPos)
        return false
    end
end
