local Players = game:GetService("Players")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local PathfindingService = game:GetService("PathfindingService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local Camera = workspace.CurrentCamera

-- ==========================================
-- MÓDULO INTERNO: SMART DOOR & NAVIGATION
-- ==========================================
local SmartDoor = {}
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

function SmartDoor.IrPara(destino, escopo_portas)
    local char = LocalPlayer.Character
    if not char or not char:FindFirstChild("Humanoid") or not char:FindFirstChild("HumanoidRootPart") then return false end

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

-- ==========================================
-- SCRIPT PRINCIPAL: BLOXBURG CHEF
-- ==========================================
_G.BloxburgChef = {}
local isRunning = false
local currentMacroId = 0
local selectedFood = "Hot Dogs"

local validActions = {
    "fry", "bake", "cook", "prepare", "stir", "mix", "chop", 
    "cut", "pour", "form", "garnish", "boil", "add", "blend",
    "fritar", "assar", "cozinhar", "preparar", "mexer", "misturar", "cortar",
    "picar", "despejar", "formar", "modelar", "decorar", "guarnecer", "ferver", 
    "adicionar", "bater"
}

local finishedActions = { "eat", "place", "take portion", "store", "comer", "colocar", "pegar porção", "guardar" }

local function Log(texto, cor)
    if _G.BloxburgChef_AddLog then _G.BloxburgChef_AddLog(texto, cor) else print("[Chef] " .. texto) end
end

local function GetCurrentAction()
    local hudGui = PlayerGui:FindFirstChild("HUDGui")
    if hudGui then
        local hotbar = hudGui:FindFirstChild("Hotbar")
        if hotbar then
            local layout = hotbar:FindFirstChild("LayoutContainer")
            if layout then
                local leftBtn = layout:FindFirstChild("LeftButtonContainer")
                if leftBtn then
                    local equippedContainer = leftBtn:FindFirstChild("EquippedContainer")
                    if equippedContainer and equippedContainer.Visible then
                        local actionLabel = equippedContainer:FindFirstChild("ActionLabel")
                        if actionLabel and actionLabel.Text ~= "" then
                            return string.lower(actionLabel.Text), equippedContainer
                        end
                    end
                end
            end
        end
    end
    return nil, nil
end

local function SafeClick(element)
    if not element then return false end
    local success = false
    pcall(function()
        if getconnections then
            if element.MouseButton1Click then for _, conn in pairs(getconnections(element.MouseButton1Click)) do conn:Fire(); success = true end end
            if not success and element.Activated then for _, conn in pairs(getconnections(element.Activated)) do conn:Fire(); success = true end end
        end
    end)
    return success
end

local function GetMyOwnPlot()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    for _, plot in pairs(plots:GetChildren()) do
        if plot:FindFirstChild("Occupant") and plot.Occupant.Value == LocalPlayer.Name then return plot
        elseif string.find(plot.Name, LocalPlayer.Name) then return plot end
    end
    for _, plot in pairs(plots:GetChildren()) do
        if plot:FindFirstChild("House") then
            local pPos = plot:GetPivot().Position
            local charPos = LocalPlayer.Character.HumanoidRootPart.Position
            if (Vector3.new(pPos.X, 0, pPos.Z) - Vector3.new(charPos.X, 0, charPos.Z)).Magnitude < 50 then return plot end
        end
    end
    return nil
end

local function FindMyStation(stationName)
    local myPlot = GetMyOwnPlot()
    if not myPlot then return nil end
    local countersFolder = myPlot:FindFirstChild("House") and myPlot.House:FindFirstChild("Counters")
    if not countersFolder then return nil end

    local target, shortestDist = nil, math.huge
    for _, obj in pairs(countersFolder:GetChildren()) do
        if obj.Name == stationName then
            local d = (LocalPlayer.Character.HumanoidRootPart.Position - obj:GetPivot().Position).Magnitude
            if d < shortestDist then shortestDist = d; target = obj end
        end
    end
    return target
end

local function AimAtObject(obj)
    local targetPos = obj:GetPivot().Position
    local lookTarget = targetPos + Vector3.new(0, -0.5, 0) 
    local tween = TweenService:Create(Camera, TweenInfo.new(0.5, Enum.EasingStyle.Quad), {CFrame = CFrame.lookAt(Camera.CFrame.Position, lookTarget)})
    tween:Play()
    task.wait(0.5)
end

local function MoveToStation(name)
    local station = FindMyStation(name)
    if not station then return false end

    local myPlot = GetMyOwnPlot()
    
    -- Chama o módulo localmente (sem _G)
    local chegou_no_destino = SmartDoor.IrPara(station, myPlot)

    if chegou_no_destino then
        local hrp = LocalPlayer.Character.HumanoidRootPart
        local targetPos = station:GetPivot().Position
        
        hrp.CFrame = CFrame.lookAt(hrp.Position, Vector3.new(targetPos.X, hrp.Position.Y, targetPos.Z))
        AimAtObject(station)

        task.wait(0.2)
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
        return true
    end
    return false
end

local function ProcessMinigameButtons()
    local acted = false
    local function HandleButton(b)
        local letra = nil
        for _, c in pairs(b:GetDescendants()) do
            if c:IsA("TextLabel") and c.Text ~= "" and string.match(c.Text, "^%s*([A-Za-z])%s*$") then
                letra = string.upper(string.match(c.Text, "^%s*([A-Za-z])%s*$"))
                break
            end
        end

        if letra and letra ~= "E" then
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode[letra], false, game)
            task.wait(0.05)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode[letra], false, game)
            acted = true
        else
            SafeClick(b) 
            acted = true
        end
    end

    local float = PlayerGui:FindFirstChild("FloatingGui")
    if float then
        for _, b in pairs(float:GetDescendants()) do
            if b.Name == "DefaultButton" and b:IsA("ImageButton") and b.Visible then HandleButton(b) end
        end
    end

    if getnilinstances then
        for _, v in next, getnilinstances() do 
            if v.ClassName == "ImageButton" and v.Name == "DefaultButton" then HandleButton(v) end 
        end
    end
    return acted
end

local function MonitorAndCook(expectedAction)
    local lastActionTime = tick()

    while isRunning do
        local acted = false
        if ProcessMinigameButtons() then acted = true end

        local currentAct, currentBtn = GetCurrentAction()

        if currentAct and currentBtn then
            for _, fAct in pairs(finishedActions) do
                if string.find(currentAct, string.lower(fAct)) then
                    Log("Prato Finalizado!", Color3.fromRGB(50, 255, 50))
                    return "finished"
                end
            end

            for _, vAct in pairs(validActions) do
                if string.find(currentAct, string.lower(vAct)) then
                    SafeClick(currentBtn) 
                    acted = true
                    break
                end
            end

            if currentAct ~= expectedAction then return "changed_station" end
        end

        if acted then
            lastActionTime = tick() 
            task.wait(0.2)
        end

        if tick() - lastActionTime >= 20 then
            Log("Nenhuma ação há 20 segundos! Resetando...", Color3.fromRGB(255, 100, 100))
            return "timeout"
        end
        task.wait(0.1)
    end
    return "stopped"
end

function _G.BloxburgChef.Start(food)
    if isRunning then return end
    selectedFood = food or "Hot Dogs"
    isRunning = true
    currentMacroId = currentMacroId + 1
    local myId = currentMacroId

    Log("Farm Iniciado", Color3.fromRGB(50, 255, 50))

    task.spawn(function()
        while isRunning and currentMacroId == myId do
            local hasFood = false

            while isRunning and currentMacroId == myId and not hasFood do
                local startActText, _ = GetCurrentAction()
                if startActText then
                    for _, vAct in pairs(validActions) do
                        if string.find(startActText, string.lower(vAct)) then
                            hasFood = true
                            Log("Comida já na mão! (" .. startActText .. ")", Color3.fromRGB(50, 255, 50))
                            break
                        end
                    end
                end

                if hasFood then break end

                if MoveToStation("Icebox Fridge") then
                    Log("Chegou na geladeira. Aguardando UI...", Color3.fromRGB(200, 200, 200))

                    local listMenu = nil
                    local waitTime = 0
                    while waitTime < 30 do
                        listMenu = PlayerGui:FindFirstChild("_ListFrame (T_Ingredients)", true)
                        if listMenu and listMenu.Visible then break end
                        task.wait(0.1)
                        waitTime = waitTime + 1
                    end

                    if not listMenu or not listMenu.Visible then
                        local interactUI = PlayerGui:FindFirstChild("_interactUI")
                        if interactUI then
                            for _, el in pairs(interactUI:GetDescendants()) do
                                if el:IsA("TextLabel") and (string.lower(el.Text):find("take") or string.lower(el.Text):find("pegar") or string.lower(el.Text):find("ingredients")) then
                                    SafeClick(el.Parent)
                                    break
                                end
                            end
                        end
                        task.wait(0.5)
                        listMenu = PlayerGui:FindFirstChild("_ListFrame (T_Ingredients)", true)
                    end

                    if listMenu then
                        Log("Menu aberto. Selecionando...", Color3.fromRGB(200, 200, 200))
                        task.wait(1.5) 

                        local mainFrame = listMenu:FindFirstChild("Frame")
                        local uiEvent = mainFrame and mainFrame:FindFirstChild("Event")
                        local foodBtn = listMenu:FindFirstChild(selectedFood .. "_Button", true)

                        if not foodBtn then
                            for _, v in pairs(listMenu:GetDescendants()) do
                                if v:IsA("TextLabel") and string.find(string.lower(v.Text), string.lower(selectedFood)) then
                                    if v.Parent:IsA("GuiButton") or v.Parent:IsA("ImageButton") then foodBtn = v.Parent; break
                                    elseif v.Parent.Parent:IsA("GuiButton") then foodBtn = v.Parent.Parent; break end
                                end
                            end
                        end

                        if uiEvent and foodBtn then
                            pcall(function() uiEvent:Fire(foodBtn) end)
                            task.wait(0.2)
                            pcall(function() uiEvent:Fire(selectedFood) end)
                        end
                    end

                    local fridgeStartTime = tick()
                    while tick() - fridgeStartTime < 4 do
                        if not isRunning or currentMacroId ~= myId then break end
                        local actText, _ = GetCurrentAction()
                        if actText then
                            for _, vAct in pairs(validActions) do
                                if string.find(actText, string.lower(vAct)) then hasFood = true; break end
                            end
                        end
                        if hasFood then break end
                        task.wait(0.1)
                    end
                else
                    Log("Geladeira não encontrada ou caminho bloqueado!", Color3.fromRGB(255, 50, 50))
                    task.wait(3)
                end
            end

            local cookingStatus = "cooking"

            while isRunning and currentMacroId == myId and cookingStatus ~= "finished" and cookingStatus ~= "timeout" do
                local actText, equippedBtn = GetCurrentAction()

                if actText and equippedBtn then
                    for _, fAct in pairs(finishedActions) do
                        if string.find(actText, string.lower(fAct)) then
                            Log("Prato Finalizado!", Color3.fromRGB(50, 255, 50))
                            cookingStatus = "finished"
                            break
                        end
                    end
                    if cookingStatus == "finished" then break end

                    local isStove = string.find(actText, "fry") or string.find(actText, "boil") or string.find(actText, "cook") or string.find(actText, "bake") or string.find(actText, "fritar") or string.find(actText, "ferver") or string.find(actText, "cozinhar") or string.find(actText, "assar")
                    local targetName = isStove and "Basic Stove" or "Basic Counter"

                    Log("Indo para " .. targetName .. "...", Color3.fromRGB(150, 200, 255))

                    if MoveToStation(targetName) then
                        task.wait(0.5)
                        local interactUI = PlayerGui:FindFirstChild("_interactUI")
                        if interactUI then
                            for _, el in pairs(interactUI:GetDescendants()) do
                                if el:IsA("TextLabel") and (string.lower(el.Text) == "clean" or string.lower(el.Text) == "limpar") then
                                    SafeClick(el.Parent)
                                    task.wait(9)
                                    break
                                end
                            end
                        end
                        cookingStatus = MonitorAndCook(actText)
                    end
                else
                     task.wait(0.5)
                end
            end
        end
    end)
end

function _G.BloxburgChef.Stop()
    isRunning = false
    currentMacroId = currentMacroId + 1
    Log("Farm Parado.", Color3.fromRGB(255, 100, 100))
end
