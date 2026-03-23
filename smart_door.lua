local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")

local lp = Players.LocalPlayer

-- ==========================================
-- SISTEMA SMART DOOR: CALCULAR ROTA E ABRIR PORTAS
-- ==========================================

-- Função para simular o aperto do "E"
local function PressE()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
    task.wait(0.1)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
end

-- Função para checar portas próximas e abrir
local function HandleNearbyDoors(hrp)
    -- Procura portas no workspace (ajustado para a estrutura do Bloxburg)
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and (string.find(string.lower(obj.Name), "door") or string.find(string.lower(obj.Name), "porta")) then
            local pivot = obj:GetPivot().Position
            local distance = (hrp.Position - pivot).Magnitude
            
            -- Se estiver a menos de 6 passos da porta, tenta abrir
            if distance < 6 then
                -- Tenta achar ProximityPrompt (alguns jogos usam)
                local prompt = obj:FindFirstChildWhichIsA("ProximityPrompt", true)
                if prompt and prompt.Enabled then
                    if fireproximityprompt then
                        fireproximityprompt(prompt, 1)
                    else
                        PressE()
                    end
                    task.wait(0.3) -- Espera a animação da porta
                else
                    -- Se for sistema próprio (tipo Bloxburg), manda o E direto
                    PressE()
                    task.wait(0.3)
                end
            end
        end
    end
end

-- Função principal para ir até o destino
local function SmartNavigate(targetPosition)
    local char = lp.Character
    if not char or not char:FindFirstChild("Humanoid") or not char:FindFirstChild("HumanoidRootPart") then return end
    
    local hum = char.Humanoid
    local hrp = char.HumanoidRootPart

    -- TRUQUE: Deixar portas intangíveis só pro Pathfinder não desviar delas
    local allDoors = {}
    for _, obj in pairs(workspace:GetDescendants()) do
        if obj:IsA("BasePart") and string.find(string.lower(obj.Parent.Name), "door") then
            table.insert(allDoors, {Part = obj, OriginalCollide = obj.CanCollide})
            obj.CanCollide = false
        end
    end

    -- Cria e calcula a rota
    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
        AgentJumpHeight = 10,
        AgentMaxSlope = 45,
    })
    
    local success, errorMessage = pcall(function()
        path:ComputeAsync(hrp.Position, targetPosition)
    end)

    -- Devolve a colisão das portas ao normal pra não bugar o mapa
    for _, data in pairs(allDoors) do
        data.Part.CanCollide = data.OriginalCollide
    end

    if success and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        
        for i, waypoint in ipairs(waypoints) do
            -- Pula o waypoint se quisermos (opcional, mas bom pra caminhos travados)
            if waypoint.Action == Enum.PathWaypointAction.Jump then
                hum.Jump = true
            end
            
            -- Move o personagem
            hum:MoveTo(waypoint.Position)
            
            -- Enquanto está andando para o waypoint, checa portas e espera chegar
            local moveTimeout = tick() + 3 -- Timeout de 3 segundos por waypoint (evita loop infinito se travar)
            repeat
                HandleNearbyDoors(hrp)
                task.wait(0.1)
            until (hrp.Position - waypoint.Position).Magnitude < 2 or tick() > moveTimeout
        end
        print("✅ Destino alcançado!")
    else
        warn("❌ Não foi possível criar uma rota. Erro: ", errorMessage)
    end
end

-- ==========================================
-- COMO TESTAR (EXEMPLO)
-- ==========================================
-- Digamos que você achou a geladeira no mapa:
-- local geladeira = workspace.ObjectModel.Fridge
-- SmartNavigate(geladeira:GetPivot().Position)
