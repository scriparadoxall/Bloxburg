local PathfindingService = game:GetService("PathfindingService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local SmartDoor = {} 
SmartDoor.CurrentWalkId = 0 
local lastDoorClick = 0

-- Orbs visuais desativados por padrão
if _G.MostrarBolinhas == nil then _G.MostrarBolinhas = false end

local function DesenharCaminho(waypoints)
    local folder = workspace:FindFirstChild("CaminhoSmartDoor")
    if folder then folder:Destroy() end
    
    if not _G.MostrarBolinhas then return {} end

    folder = Instance.new("Folder")
    folder.Name = "CaminhoSmartDoor"
    folder.Parent = workspace

    local parts = {}
    for i, wp in ipairs(waypoints) do
        local part = Instance.new("Part")
        part.Size = Vector3.new(0.8, 0.8, 0.8) 
        part.Position = wp.Position + Vector3.new(0, 0.5, 0) 
        part.Anchored = true
        part.CanCollide = false
        part.Material = Enum.Material.Neon
        part.Color = Color3.fromRGB(0, 255, 200) 
        part.Shape = Enum.PartType.Ball 
        part.Transparency = 0.2
        part.Parent = folder

        local light = Instance.new("PointLight")
        light.Color = part.Color
        light.Range = 6
        light.Brightness = 2
        light.Parent = part
        
        parts[i] = part
    end
    
    return parts 
end

local function EfeitoSumir(part)
    if not part then return end
    local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In)
    local tween = TweenService:Create(part, tweenInfo, {Size = Vector3.new(0, 0, 0), Transparency = 1})
    tween:Play()
    game.Debris:AddItem(part, 0.35)
end

local function PrepararFisica(estado, alvo)
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return end

    for _, plot in pairs(plots:GetChildren()) do
        local house = plot:FindFirstChild("House")
        if house then
            for _, obj in pairs(house:GetDescendants()) do
                if obj:IsA("BasePart") then
                    local nome = string.lower(obj.Name)
                    local pai = obj.Parent and string.lower(obj.Parent.Name) or ""
                    local avo = obj.Parent and obj.Parent.Parent and string.lower(obj.Parent.Parent.Name) or ""

                    if nome:find("door") or pai:find("door") or avo:find("door") then
                        if estado == "LIGAR" and not obj:FindFirstChild("IgnorarGPS") then
                            local mod = Instance.new("PathfindingModifier")
                            mod.Name = "IgnorarGPS"
                            mod.PassThrough = true
                            mod.Parent = obj
                        elseif estado == "DESLIGAR" and obj:FindFirstChild("IgnorarGPS") then
                            obj.IgnorarGPS:Destroy()
                        end
                    end
                end
            end
            
            local pathsFolder = house:FindFirstChild("Paths")
            if pathsFolder then
                for _, obj in pairs(pathsFolder:GetDescendants()) do
                    if obj:IsA("BasePart") then
                        if estado == "LIGAR" and not obj:FindFirstChild("PrioridadeCaminho") then
                            local mod = Instance.new("PathfindingModifier")
                            mod.Name = "PrioridadeCaminho"
                            mod.Label = "CaminhoLegal"
                            mod.PassThrough = false
                            mod.Parent = obj
                        elseif estado == "DESLIGAR" and obj:FindFirstChild("PrioridadeCaminho") then
                            obj.PrioridadeCaminho:Destroy()
                        end
                    end
                end
            end
        end
    end

    if alvo then
        local model = alvo:FindFirstAncestorWhichIsA("Model") or alvo
        for _, part in pairs(model:GetDescendants()) do
            if part:IsA("BasePart") then
                if estado == "LIGAR" and not part:FindFirstChild("IgnorarGPS_Alvo") then
                    local mod = Instance.new("PathfindingModifier")
                    mod.Name = "IgnorarGPS_Alvo"
                    mod.PassThrough = true
                    mod.Parent = part
                elseif estado == "DESLIGAR" and part:FindFirstChild("IgnorarGPS_Alvo") then
                    if part:FindFirstChild("IgnorarGPS_Alvo") then part.IgnorarGPS_Alvo:Destroy() end
                end
            end
        end
    end
end

local function TentarAbrirPorta()
    local p = Players.LocalPlayer
    local gui = p.PlayerGui:FindFirstChild("_interactUI")
    
    if gui and gui:FindFirstChild("InteractIndicator") and gui.InteractIndicator.Visible then
        local lbl = gui.InteractIndicator:FindFirstChild("TextLabel")
        if lbl then
            local texto = string.lower(lbl.Text)
            if texto:find("open") or texto:find("abrir") then
                if tick() - lastDoorClick > 0.8 then
                    lastDoorClick = tick()
                    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                    task.wait(0.05)
                    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                    return true
                end
            end
        end
    end
    return false
end

local function ObterPosicaoNaFrente(alvoPart)
    local pos = alvoPart.Position
    local cf = alvoPart.CFrame
    local direcoes = {cf.LookVector, -cf.LookVector, cf.RightVector, -cf.RightVector}
    local melhorDirecao = Vector3.new(0, 0, 1)
    local maiorEspacoLivre = -1
    
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    local modelIgnore = alvoPart:FindFirstAncestorWhichIsA("Model") or alvoPart
    rp.FilterDescendantsInstances = {Players.LocalPlayer.Character, modelIgnore}
    
    for _, dir in ipairs(direcoes) do
        local resultado = workspace:Raycast(pos, dir * 10, rp)
        local dist = resultado and (resultado.Position - pos).Magnitude or 10
        if dist > maiorEspacoLivre then
            maiorEspacoLivre = dist
            melhorDirecao = dir
        end
    end
    
    local alvoFinal = pos + (melhorDirecao * 2.5)
    return Vector3.new(alvoFinal.X, Players.LocalPlayer.Character.HumanoidRootPart.Position.Y, alvoFinal.Z)
end

function SmartDoor.IrPara(destino)
    SmartDoor.CurrentWalkId = SmartDoor.CurrentWalkId + 1
    local myId = SmartDoor.CurrentWalkId

    local char = Players.LocalPlayer.Character
    if not char or not char:FindFirstChild("Humanoid") then return false end
    local hum = char.Humanoid
    local hrp = char.HumanoidRootPart

    local alvoPart = destino:IsA("Model") and (destino.PrimaryPart or destino:FindFirstChildWhichIsA("BasePart", true)) or destino
    local targetPos = ObterPosicaoNaFrente(alvoPart)

    PrepararFisica("LIGAR", destino)
    task.wait(0.3)

    local path = PathfindingService:CreatePath({
        AgentRadius = 0.8, 
        AgentHeight = 5, 
        AgentCanJump = true, 
        WaypointSpacing = 3,
        Costs = {
            CaminhoLegal = 0.1 
        }
    })
    path:ComputeAsync(hrp.Position, targetPos)
    PrepararFisica("DESLIGAR", destino)

    if path.Status ~= Enum.PathStatus.Success then
        return false
    end

    local waypoints = path:GetWaypoints()
    local orbs = DesenharCaminho(waypoints)

    for i, wp in ipairs(waypoints) do
        if SmartDoor.CurrentWalkId ~= myId then break end
        
        if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
        hum:MoveTo(wp.Position)

        local timeout = tick()
        local checkStuck = tick()
        local lastPos = hrp.Position

        while true do
            if SmartDoor.CurrentWalkId ~= myId then break end
            
            local pPos = Vector3.new(hrp.Position.X, 0, hrp.Position.Z)
            local wPos = Vector3.new(wp.Position.X, 0, wp.Position.Z)
            
            local tolerancia = (i == #waypoints) and 1.5 or 2.5
            if (pPos - wPos).Magnitude <= tolerancia then
                EfeitoSumir(orbs[i])
                break 
            end

            if TentarAbrirPorta() then
                hum:MoveTo(wp.Position)
            end

            if tick() - checkStuck > 1.0 then
                if (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(lastPos.X, 0, lastPos.Z)).Magnitude < 0.5 then 
                    hum.Jump = true
                    hum:MoveTo(wp.Position)
                end
                lastPos = hrp.Position
                checkStuck = tick()
            end

            if tick() - timeout > 4 then break end
            task.wait()
        end
    end

    if (hrp.Position - targetPos).Magnitude < 6.5 then
        return true
    end
    return false
end

function SmartDoor.Cancelar()
    SmartDoor.CurrentWalkId = SmartDoor.CurrentWalkId + 1
    local folder = workspace:FindFirstChild("CaminhoSmartDoor")
    if folder then folder:Destroy() end
end

return SmartDoor
