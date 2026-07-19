-- ===== 1. LIFECYCLE MANAGER ===== --
if shared.UY_Lifecycle then
    shared.UY_Lifecycle:Destroy()
end

local Lifecycle = {
    Connections = {},
    Instances = {},
    CleanupFuncs = {},
    Threads = {}
}

function Lifecycle:AddConnection(conn) table.insert(self.Connections, conn); return conn end
function Lifecycle:AddInstance(inst) table.insert(self.Instances, inst); return inst end
function Lifecycle:AddCleanup(fn) table.insert(self.CleanupFuncs, fn) end
function Lifecycle:AddThread(thread) table.insert(self.Threads, thread); return thread end

function Lifecycle:Destroy()
    for _, conn in ipairs(self.Connections) do if conn.Connected then conn:Disconnect() end end
    for _, inst in ipairs(self.Instances) do if inst and inst.Parent then pcall(function() inst:Destroy() end) end end
    for _, thread in ipairs(self.Threads) do pcall(function() task.cancel(thread) end) end
    for _, fn in ipairs(self.CleanupFuncs) do pcall(fn) end
    
    table.clear(self.Connections)
    table.clear(self.Instances)
    table.clear(self.Threads)
    table.clear(self.CleanupFuncs)
end
shared.UY_Lifecycle = Lifecycle

for _, gui in ipairs(game:GetService("CoreGui"):GetChildren()) do
    if gui.Name == "Rayfield" then gui:Destroy() end
end

-- ===== 2. INITIALIZATION & GLOBALS ===== --
local Rayfield = loadstring(game:HttpGet("https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")
local Stats = game:GetService("Stats")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local speedEnabled, globalSpeed = false, 16
local jumpEnabled, globalJump = false, 50

local lastNormalWalkSpeed, lastNormalJumpPower, lastNormalJumpHeight, lastNormalUseJumpPower = nil, nil, nil, nil
local humanoidConnections = {}

local flyEnabled, flySpeed = false, 50
local flyBodyVelocity, flyBodyGyro = nil, nil
local flyConnection = nil

local noclipEnabled = false
local noclipPartsCache, noclipOriginalCanCollide = {}, {}

local flingEnabled = false
local oldSubject = nil

local FlingTrackedPartsArray = {}
local FlingTrackedPartsDict = {}
local targetOriginalCanCollide = {}

local fullbrightEnabled, nofogEnabled = false, false
local origLighting = {
    Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime,
    GlobalShadows = Lighting.GlobalShadows, Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient, FogStart = Lighting.FogStart, FogEnd = Lighting.FogEnd
}
local atmosphereBackup, lightingConnections = {}, {}

local selectedTpPlayer = ""
local loopTpEnabled = false

local savedPositionsList = {}
local savedPositionsMap = {}
local selectedWaypoint = ""
local renameInputText = ""
local antiAfkEnabled = false
local antiGameplayPausedEnabled = false
local networkPausedConn = nil
local antiVoidEnabled = false
local antiVoidConn = nil

local tpYourselfDistanceText = ""

local selectedBindFunction = ""
local keybindInputText = ""
local selectedCurrentBind = ""
local functionToBinds = {}
local activeKeybinds = {}
local keybindsListForDropdown = {}

local friendCheckQueue = {}
local processingFriendQueue = false

local spectateEnabled = false
local spectateLoopConn = nil

local xrayEnabled, xrayMode, xrayDistance = false, "Dynamic", 500
local xrayOriginalTransparencies = {}
local lastXrayUpdate = 0
local xrayOverlapParams = OverlapParams.new()
xrayOverlapParams.FilterType = Enum.RaycastFilterType.Exclude

local cameraNoclipEnabled = false
local previousOcclusionMode = nil

local fovValue = 70
local loopFovEnabled = false
local fovConnection = nil
local lastNormalFov = nil

local Options = {
    EspHighlight = false, EspNames = false, EspHealth = false, EspDistance = false,
    EspTracers = false, ShowEspIcon = false, TeamCheck = false,
    AntiFriends = false, MaxDistance = 500, Whitelist = {}, Blacklist = {}
}

local FriendsCache, ActiveEspObjects, ActiveTracers = {}, {}, {}
local PlayerTracking = {}
local Cache_MyTeam, Cache_MyNeutral = nil, false

local WhitelistDropdown, BlacklistDropdown, TpDropdown, FlingToggle, SpectateToggle, WaypointDropdown = nil, nil, nil, nil, nil, nil
local RenameInput, KeybindInput, KeybindFunctionDropdown, CurrentKeybindsDropdown = nil, nil, nil, nil

local WalkSpeedToggleComponent, JumpPowerToggleComponent, InfJumpToggleComponent, FlyToggleComponent, NoclipToggleComponent = nil, nil, nil, nil, nil
local FullbrightToggleComponent, NoFogToggleComponent, XrayToggleComponent, EnableFovToggleComponent, AntiAfkToggleComponent, AntiGameplayPausedToggleComponent, AntiVoidToggleComponent, Spin360ToggleComponent = nil, nil, nil, nil, nil, nil, nil, nil

local labelsConnection = nil
local espConnection = nil
local noclipSteppedConn = nil
local flingSteppedConn = nil
local loopTpHeartbeatConn = nil
local xrayHeartbeatConn = nil
local flingDiedConnection = nil
local flingHeartbeatConn = nil

-- ===== 3. CORE LOGIC & UTILITIES ===== --
local function processFriendQueue()
    if processingFriendQueue then return end
    processingFriendQueue = true
    while #friendCheckQueue > 0 do
        local player = table.remove(friendCheckQueue, 1)
        if player and player.Parent then
            pcall(function() 
                FriendsCache[player.Name] = LocalPlayer:IsFriendsWith(player.UserId) 
            end)
            task.wait(0.3)
        end
    end
    processingFriendQueue = false
end

local function queueFriendCheck(player)
    table.insert(friendCheckQueue, player)
    task.spawn(processFriendQueue)
end

local function clearHumanoidConnections()
    for i = 1, #humanoidConnections do humanoidConnections[i]:Disconnect() end
    table.clear(humanoidConnections)
end

local setSpeedEnabled = function(Value)
    speedEnabled = Value
    pcall(function()
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            if Value then
                lastNormalWalkSpeed = hum.WalkSpeed
                hum.WalkSpeed = globalSpeed
            elseif lastNormalWalkSpeed then 
                hum.WalkSpeed = lastNormalWalkSpeed 
            end
        end
    end)
end

local setGlobalSpeed = function(Value)
    globalSpeed = Value
    if speedEnabled then
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = globalSpeed end
    end
end

local setJumpEnabled = function(Value)
    jumpEnabled = Value
    pcall(function()
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            if Value then
                lastNormalJumpPower = hum.JumpPower
                lastNormalJumpHeight = hum.JumpHeight
                lastNormalUseJumpPower = hum.UseJumpPower
                if not hum.UseJumpPower then hum.UseJumpPower = true end
                hum.JumpPower = globalJump
            elseif lastNormalUseJumpPower ~= nil then
                hum.UseJumpPower = lastNormalUseJumpPower
                if lastNormalUseJumpPower then
                    if lastNormalJumpPower then hum.JumpPower = lastNormalJumpPower end
                else
                    if lastNormalJumpHeight then hum.JumpHeight = lastNormalJumpHeight end
                end
            end
        end
    end)
end

local setGlobalJump = function(Value)
    globalJump = Value
    if jumpEnabled then
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            if not hum.UseJumpPower then hum.UseJumpPower = true end
            hum.JumpPower = globalJump
        end
    end
end

local infiniteJumpConnection = nil
local setInfJump = function(Value)
    if infiniteJumpConnection then infiniteJumpConnection:Disconnect() infiniteJumpConnection = nil end
    if Value then
        infiniteJumpConnection = Lifecycle:AddConnection(UserInputService.JumpRequest:Connect(function()
            local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
        end))
    end
end

local setFlySpeed = function(Value) flySpeed = Value end

local setFlyEnabled = function(Value)
    flyEnabled = Value
    if flyConnection then flyConnection:Disconnect() flyConnection = nil end
    
    local character = LocalPlayer.Character
    local hrp = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart or character:FindFirstChildOfClass("BasePart"))
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    
    if Value then
        if not hrp or not humanoid then return end
        humanoid.PlatformStand = true
        
        flyBodyGyro = Lifecycle:AddInstance(Instance.new("BodyGyro"))
        flyBodyGyro.P = 9e4
        flyBodyGyro.maxTorque = Vector3.new(9e9, 9e9, 9e9)
        flyBodyGyro.cframe = hrp.CFrame
        flyBodyGyro.Parent = hrp
        
        flyBodyVelocity = Lifecycle:AddInstance(Instance.new("BodyVelocity"))
        flyBodyVelocity.velocity = Vector3.new(0, 0, 0)
        flyBodyVelocity.maxForce = Vector3.new(9e9, 9e9, 9e9)
        flyBodyVelocity.Parent = hrp
        
        flyConnection = Lifecycle:AddConnection(RunService.Heartbeat:Connect(function()
            local camCF = Camera.CFrame
            local dir = Vector3.zero
            
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += camCF.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= camCF.LookVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= camCF.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += camCF.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir -= Vector3.new(0, 1, 0) end
            
            if dir.Magnitude > 0 then dir = dir.Unit end
            flyBodyVelocity.velocity = dir * flySpeed
            flyBodyGyro.cframe = camCF
        end))
    else
        if humanoid then humanoid.PlatformStand = false end
        if flyBodyVelocity then flyBodyVelocity:Destroy() flyBodyVelocity = nil end
        if flyBodyGyro then flyBodyGyro:Destroy() flyBodyGyro = nil end
    end
end
Lifecycle:AddCleanup(function() setFlyEnabled(false) end)

local function cacheNoclipParts(character)
    table.clear(noclipPartsCache)
    if not character then return end
    for _, child in ipairs(character:GetDescendants()) do
        if child:IsA("BasePart") then
            table.insert(noclipPartsCache, child)
            if noclipOriginalCanCollide[child] == nil then
                noclipOriginalCanCollide[child] = child.CanCollide
            end
        end
    end
end

local function updateNoclipState()
    if noclipEnabled then
        if not noclipSteppedConn then
            noclipSteppedConn = RunService.Stepped:Connect(function()
                for i = 1, #noclipPartsCache do
                    local part = noclipPartsCache[i]
                    if part and part.Parent then part.CanCollide = false end
                end
            end)
            Lifecycle:AddConnection(noclipSteppedConn)
        end
    else
        if noclipSteppedConn then
            noclipSteppedConn:Disconnect()
            noclipSteppedConn = nil
        end
    end
end

local setNoclipEnabled = function(Value)
    noclipEnabled = Value
    local character = LocalPlayer.Character
    if not character then return end
    
    if not Value then
        updateNoclipState()
        for i = 1, #noclipPartsCache do
            local child = noclipPartsCache[i]
            if child and child.Parent then
                if noclipOriginalCanCollide[child] ~= nil then child.CanCollide = noclipOriginalCanCollide[child] end
            end
        end
        table.clear(noclipOriginalCanCollide)
    else
        cacheNoclipParts(character)
        updateNoclipState()
    end
end
Lifecycle:AddCleanup(function() setNoclipEnabled(false) end)

local function applyFullbright()
    Lighting.Brightness, Lighting.ClockTime, Lighting.GlobalShadows = 1, 12, false
    Lighting.Ambient, Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178), Color3.fromRGB(178, 178, 178)
end

local setFullbrightEnabled = function(Value)
    fullbrightEnabled = Value
    for i = 1, #lightingConnections do lightingConnections[i]:Disconnect() end
    table.clear(lightingConnections)
    
    if Value then
        applyFullbright()
        for _, prop in ipairs({"Brightness", "ClockTime", "GlobalShadows", "Ambient", "OutdoorAmbient"}) do
            table.insert(lightingConnections, Lifecycle:AddConnection(Lighting:GetPropertyChangedSignal(prop):Connect(function()
                if fullbrightEnabled then applyFullbright() end
            end)))
        end
    else
        Lighting.Brightness, Lighting.ClockTime = origLighting.Brightness, origLighting.ClockTime
        Lighting.GlobalShadows, Lighting.Ambient = origLighting.GlobalShadows, origLighting.Ambient
        Lighting.OutdoorAmbient = origLighting.OutdoorAmbient
    end
end
Lifecycle:AddCleanup(function() setFullbrightEnabled(false) end)

local function applyNoFog() Lighting.FogStart, Lighting.FogEnd = 0, 9e9 end

local setNoFogEnabled = function(Value)
    nofogEnabled = Value
    if Value then
        applyNoFog()
        table.insert(lightingConnections, Lifecycle:AddConnection(Lighting:GetPropertyChangedSignal("FogStart"):Connect(function() if nofogEnabled then applyNoFog() end end)))
        table.insert(lightingConnections, Lifecycle:AddConnection(Lighting:GetPropertyChangedSignal("FogEnd"):Connect(function() if nofogEnabled then applyNoFog() end end)))
        
        for _, obj in ipairs(Lighting:GetDescendants()) do
            if obj:IsA("Atmosphere") or obj:IsA("Clouds") then
                table.insert(atmosphereBackup, {object = obj, parent = obj.Parent})
                obj.Parent = nil
            end
        end
        table.insert(lightingConnections, Lifecycle:AddConnection(Lighting.DescendantAdded:Connect(function(obj)
            if obj:IsA("Atmosphere") or obj:IsA("Clouds") then
                table.insert(atmosphereBackup, {object = obj, parent = obj.Parent})
                obj.Parent = nil
            end
        end)))
    else
        Lighting.FogStart, Lighting.FogEnd = origLighting.FogStart, origLighting.FogEnd
        for i = 1, #atmosphereBackup do pcall(function() if atmosphereBackup[i].object then atmosphereBackup[i].object.Parent = atmosphereBackup[i].parent end end) end
        table.clear(atmosphereBackup)
    end
end
Lifecycle:AddCleanup(function() setNoFogEnabled(false) end)

local function executeXrayScan()
    local ignoreList = {}
    local playersAll = Players:GetPlayers()
    for i = 1, #playersAll do
        local p = playersAll[i]
        if p.Character then table.insert(ignoreList, p.Character) end
    end
    xrayOverlapParams.FilterDescendantsInstances = ignoreList

    local size = Vector3.new(xrayDistance * 2, xrayDistance * 2, xrayDistance * 2)
    local partsInBox = workspace:GetPartBoundsInBox(Camera.CFrame, size, xrayOverlapParams)
    
    local currentHits = {}
    for i = 1, #partsInBox do
        local part = partsInBox[i]
        if part:IsA("BasePart") then
            currentHits[part] = true
            if not xrayOriginalTransparencies[part] then xrayOriginalTransparencies[part] = part.LocalTransparencyModifier end
            if part.LocalTransparencyModifier ~= 0.8 then part.LocalTransparencyModifier = 0.8 end
        end
    end
    
    for part, originalValue in pairs(xrayOriginalTransparencies) do
        if not currentHits[part] then
            if part and part.Parent and part.LocalTransparencyModifier ~= originalValue then part.LocalTransparencyModifier = originalValue end
            xrayOriginalTransparencies[part] = nil
        end
    end
end

local function updateXrayState()
    if xrayEnabled and xrayMode == "Dynamic" then
        if not xrayHeartbeatConn then
            xrayHeartbeatConn = RunService.Heartbeat:Connect(function()
                if tick() - lastXrayUpdate >= 0.5 then
                    lastXrayUpdate = tick()
                    executeXrayScan()
                end
            end)
            Lifecycle:AddConnection(xrayHeartbeatConn)
        end
    else
        if xrayHeartbeatConn then
            xrayHeartbeatConn:Disconnect()
            xrayHeartbeatConn = nil
        end
    end
end

local setXrayEnabled = function(Value)
    xrayEnabled = Value
    if not Value then
        updateXrayState()
        for part, originalValue in pairs(xrayOriginalTransparencies) do
            if part and part.Parent then part.LocalTransparencyModifier = originalValue end
        end
        table.clear(xrayOriginalTransparencies)
    elseif xrayMode == "Static" then
        updateXrayState()
        executeXrayScan()
    else
        updateXrayState()
    end
end
Lifecycle:AddCleanup(function() setXrayEnabled(false) end)

-- ===== 4. CAMERA UTILITIES ===== --
local setCameraNoclipEnabled = function(Value)
    cameraNoclipEnabled = Value
    if Value then
        if LocalPlayer.DevCameraOcclusionMode ~= Enum.DevCameraOcclusionMode.Invisicam then
            previousOcclusionMode = LocalPlayer.DevCameraOcclusionMode
            LocalPlayer.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Invisicam
        end
    else
        if previousOcclusionMode then
            LocalPlayer.DevCameraOcclusionMode = previousOcclusionMode
            previousOcclusionMode = nil
        end
    end
end
Lifecycle:AddCleanup(function() setCameraNoclipEnabled(false) end)

local updateFovStatic = function(Value)
    fovValue = Value
    if loopFovEnabled and Camera.FieldOfView ~= Value then
        Camera.FieldOfView = Value
    end
end

local setLoopFovEnabled = function(Value)
    loopFovEnabled = Value
    if fovConnection then fovConnection:Disconnect() fovConnection = nil end
    
    if Value then
        lastNormalFov = Camera.FieldOfView
        fovConnection = RunService.RenderStepped:Connect(function()
            if Camera.FieldOfView ~= fovValue then
                Camera.FieldOfView = fovValue
            end
        end)
        Lifecycle:AddConnection(fovConnection)
    else
        if lastNormalFov then
            Camera.FieldOfView = lastNormalFov
        end
    end
end
Lifecycle:AddCleanup(function() setLoopFovEnabled(false) end)

-- ===== 5. COMBAT PHYSICS & FLING SYSTEM ===== --
local walkflinging = false
local preFlingCFrame = nil
local isTargetFling = false

local spinEnabled = false
local spinDuration = 0.5
local spinConnection = nil

local function FlingAddPart(part)
    if part:IsA("BasePart") then
        if not FlingTrackedPartsDict[part] then
            table.insert(FlingTrackedPartsArray, part)
            FlingTrackedPartsDict[part] = #FlingTrackedPartsArray
            if targetOriginalCanCollide[part] == nil then
                targetOriginalCanCollide[part] = part.CanCollide
            end
        end
    end
end

local function FlingRemovePart(part)
    local index = FlingTrackedPartsDict[part]
    if index then
        local lastPart = FlingTrackedPartsArray[#FlingTrackedPartsArray]
        FlingTrackedPartsArray[index] = lastPart
        FlingTrackedPartsDict[lastPart] = index
        FlingTrackedPartsArray[#FlingTrackedPartsArray] = nil
        FlingTrackedPartsDict[part] = nil
        
        if targetOriginalCanCollide[part] ~= nil then
            pcall(function() part.CanCollide = targetOriginalCanCollide[part] end)
            targetOriginalCanCollide[part] = nil
        end
    end
end

local function updateFlingSteppedState()
    if flingEnabled then
        if not flingSteppedConn then
            flingSteppedConn = RunService.Stepped:Connect(function()
                for i = 1, #FlingTrackedPartsArray do
                    local part = FlingTrackedPartsArray[i]
                    if part.CanCollide then
                        part.CanCollide = false
                    end
                end
            end)
            Lifecycle:AddConnection(flingSteppedConn)
        end
    else
        if noclipEnabled then return end
        if flingSteppedConn then
            flingSteppedConn:Disconnect()
            flingSteppedConn = nil
        end
    end
end

local setSpinEnabled = function(Value)
    spinEnabled = Value
    if spinConnection then spinConnection:Disconnect() spinConnection = nil end
    
    if Value then
        spinConnection = RunService.Heartbeat:Connect(function()
            if flingEnabled then return end
            local char = LocalPlayer.Character
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart or char:FindFirstChildOfClass("BasePart"))
            if root then
                local rps = (2 * math.pi) / math.max(spinDuration, 0.01)
                root.RotVelocity = Vector3.new(0, rps, 0)
            end
        end)
        Lifecycle:AddConnection(spinConnection)
    else
        local char = LocalPlayer.Character
        local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart or char:FindFirstChildOfClass("BasePart"))
        if root and not flingEnabled then
            root.RotVelocity = Vector3.zero
        end
    end
end
Lifecycle:AddCleanup(function() setSpinEnabled(false) end)

local setFlingEnabled = function(Value)
    flingEnabled = Value
    
    local char = LocalPlayer.Character
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart or char:FindFirstChildOfClass("BasePart"))
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    
    if not Value then
        walkflinging = false
        
        if flingDiedConnection then flingDiedConnection:Disconnect() flingDiedConnection = nil end
        if flingHeartbeatConn then flingHeartbeatConn:Disconnect() flingHeartbeatConn = nil end
        updateFlingSteppedState()
        
        for part, originalValue in pairs(targetOriginalCanCollide) do
            if part and part.Parent then
                part.CanCollide = originalValue
            end
        end
        table.clear(targetOriginalCanCollide)
        
        pcall(function()
            local myChar = LocalPlayer.Character
            local myHum = myChar and myChar:FindFirstChildOfClass("Humanoid")
            if myHum then
                Camera.CameraSubject = myHum
            elseif oldSubject then
                Camera.CameraSubject = oldSubject
            end
        end)
        oldSubject = nil

        if isTargetFling and preFlingCFrame then
            task.spawn(function()
                RunService.Heartbeat:Wait()
                local myChar = LocalPlayer.Character
                local myRoot = myChar and (myChar:FindFirstChild("HumanoidRootPart") or myChar.PrimaryPart or myChar:FindFirstChildOfClass("BasePart"))
                if myRoot then
                    myRoot.Anchored = true
                    local returnStart = os.clock()
                    while (os.clock() - returnStart) < 0.3 do
                        myRoot.Velocity = Vector3.zero
                        myRoot.RotVelocity = spinEnabled and Vector3.new(0, (2 * math.pi) / math.max(spinDuration, 0.01), 0) or Vector3.zero
                        myRoot.CFrame = preFlingCFrame
                        RunService.Heartbeat:Wait()
                    end
                    myRoot.Anchored = false
                end
                preFlingCFrame = nil
            end)
        else
            if root then
                root.Velocity = Vector3.zero
                root.RotVelocity = spinEnabled and Vector3.new(0, (2 * math.pi) / math.max(spinDuration, 0.01), 0) or Vector3.zero
            end
            preFlingCFrame = nil
        end
        isTargetFling = false
    else
        if not root or not hum then 
            flingEnabled = false
            if FlingToggle then FlingToggle:Set(false) end
            return 
        end

        isTargetFling = (selectedTpPlayer and selectedTpPlayer ~= "")
        if isTargetFling then
            preFlingCFrame = root.CFrame
        end

        for i = 1, #FlingTrackedPartsArray do
            local p = FlingTrackedPartsArray[i]
            if targetOriginalCanCollide[p] == nil then
                targetOriginalCanCollide[p] = p.CanCollide
            end
        end

        walkflinging = true
        updateFlingSteppedState()

        if flingDiedConnection then flingDiedConnection:Disconnect() end
        flingDiedConnection = hum.Died:Connect(function()
            if FlingToggle then 
                FlingToggle:Set(false) 
            else
                setFlingEnabled(false)
            end
        end)

        local flingThread = task.spawn(function()
            local movel = 0.5
            while walkflinging do
                RunService.Heartbeat:Wait()
                if not walkflinging then break end
                
                local c = LocalPlayer.Character
                local r = c and (c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart or c:FindFirstChildOfClass("BasePart"))
                if not (c and c.Parent and r and r.Parent) then continue end

                local vel = r.Velocity
                local rps = (2 * math.pi) / math.max(spinDuration, 0.01)
                local currentSpinVel = spinEnabled and Vector3.new(0, rps, 0) or Vector3.new(100000, 100000, 100000)
                
                r.Velocity = vel * 100000 + Vector3.new(0, 100000, 0)
                r.RotVelocity = currentSpinVel

                RunService.RenderStepped:Wait()
                if not walkflinging then break end
                if c and c.Parent and r and r.Parent then
                    r.Velocity = vel
                    r.RotVelocity = spinEnabled and Vector3.new(0, rps, 0) or Vector3.zero
                end

                RunService.Stepped:Wait()
                if not walkflinging then break end
                if c and c.Parent and r and r.Parent then
                    r.Velocity = vel + Vector3.new(0, movel, 0)
                    movel = movel * -1
                end
            end
        end)
        Lifecycle:AddThread(flingThread)

        flingHeartbeatConn = RunService.Heartbeat:Connect(function()
            local targetPlayer = (selectedTpPlayer and selectedTpPlayer ~= "") and Players:FindFirstChild(selectedTpPlayer) or nil
            local targetChar = targetPlayer and targetPlayer.Character
            local targetRoot = targetChar and (targetChar:FindFirstChild("HumanoidRootPart") or targetChar.PrimaryPart or targetChar:FindFirstChildOfClass("BasePart"))
            local targetHum = targetChar and targetChar:FindFirstChildOfClass("Humanoid")

            local isTargetValid = false
            if targetPlayer and targetChar and targetRoot and targetRoot.Parent and targetHum and targetHum.Health > 0 then
                local targetPos = targetRoot.Position
                if targetPos.Y > -200 and math.abs(targetPos.X) < 100000 and math.abs(targetPos.Z) < 100000 then
                    isTargetValid = true
                end
            end

            if isTargetValid then
                if Camera.CameraSubject ~= targetRoot then
                    oldSubject = Camera.CameraSubject
                    Camera.CameraSubject = targetRoot
                end

                local myRoot = LocalPlayer.Character and (LocalPlayer.Character:FindFirstChild("HumanoidRootPart") or LocalPlayer.Character.PrimaryPart or LocalPlayer.Character:FindFirstChildOfClass("BasePart"))
                if myRoot then
                    local predictedCFrame = targetRoot.CFrame + (targetRoot.Velocity * 0.15) + (targetRoot.CFrame.LookVector * 1.0)
                    local t = tick() * 25
                    local offsetZ = math.sin(t) * 1.2
                    myRoot.CFrame = predictedCFrame * CFrame.new(0, 0, offsetZ)
                end
            else
                pcall(function()
                    local myChar = LocalPlayer.Character
                    local myHum = myChar and myChar:FindFirstChildOfClass("Humanoid")
                    if myHum and Camera.CameraSubject ~= myHum then
                        Camera.CameraSubject = myHum
                    end
                end)
                
                if selectedTpPlayer and selectedTpPlayer ~= "" then
                    if FlingToggle then 
                        FlingToggle:Set(false) 
                    else
                        setFlingEnabled(false)
                    end
                end
            end
        end)
        Lifecycle:AddConnection(flingHeartbeatConn)
    end
end
Lifecycle:AddCleanup(function() setFlingEnabled(false) end)

local setSpectateEnabled = function(Value)
    spectateEnabled = Value
    if spectateLoopConn then spectateLoopConn:Disconnect() spectateLoopConn = nil end
    if Value then
        spectateLoopConn = Lifecycle:AddConnection(RunService.RenderStepped:Connect(function()
            local targetPlayer = (selectedTpPlayer ~= "") and Players:FindFirstChild(selectedTpPlayer) or nil
            local targetHum = targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChildOfClass("Humanoid")
            if targetHum then
                if Camera.CameraSubject ~= targetHum then Camera.CameraSubject = targetHum end
            else
                local myHum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                if myHum and Camera.CameraSubject ~= myHum then Camera.CameraSubject = myHum end
            end
        end))
    else
        local myHum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if myHum then Camera.CameraSubject = myHum end
    end
end
Lifecycle:AddCleanup(function() setSpectateEnabled(false) end)

local tipToPlayer = function(targetName)
    if not targetName or targetName == "" then return end
    local targetPlayer = Players:FindFirstChild(targetName)
    local targetHrp = targetPlayer and targetPlayer.Character and (targetPlayer.Character:FindFirstChild("HumanoidRootPart") or targetPlayer.Character.PrimaryPart or targetPlayer.Character:FindFirstChildOfClass("BasePart"))
    local myHrp = LocalPlayer.Character and (LocalPlayer.Character:FindFirstChild("HumanoidRootPart") or LocalPlayer.Character.PrimaryPart or LocalPlayer.Character:FindFirstChildOfClass("BasePart"))
    if targetHrp and myHrp then myHrp.CFrame = targetHrp.CFrame end
end

local function updateLoopTpState()
    if loopTpEnabled and selectedTpPlayer ~= "" and not flingEnabled then
        if not loopTpHeartbeatConn then
            loopTpHeartbeatConn = RunService.Heartbeat:Connect(function()
                if loopTpEnabled and selectedTpPlayer ~= "" and not flingEnabled then
                    tipToPlayer(selectedTpPlayer)
                else
                    if loopTpHeartbeatConn then
                        loopTpHeartbeatConn:Disconnect()
                        loopTpHeartbeatConn = nil
                    end
                end
            end)
            Lifecycle:AddConnection(loopTpHeartbeatConn)
        end
    else
        if loopTpHeartbeatConn then
            loopTpHeartbeatConn:Disconnect()
            loopTpHeartbeatConn = nil
        end
    end
end

local getActivePlayerNames = function()
    local names = {}
    local playersAll = Players:GetPlayers()
    for i = 1, #playersAll do
        local p = playersAll[i]
        if p ~= LocalPlayer then table.insert(names, p.Name) end
    end
    return names
end

-- ===== 6. ESP EVENT-DRIVEN SYSTEM ===== --
local function removeEspObjects(player)
    if ActiveEspObjects[player] then
        pcall(function() ActiveEspObjects[player].Folder:Destroy() end)
        ActiveEspObjects[player] = nil
    end
    if ActiveTracers[player] then
        pcall(function()
            if type(ActiveTracers[player]) == "table" and ActiveTracers[player].Line then
                ActiveTracers[player].Line:Remove()
            else
                ActiveTracers[player]:Remove()
            end
        end)
        ActiveTracers[player] = nil
    end
end

local function buildEsp(player, character)
    removeEspObjects(player)
    if player == LocalPlayer or not character then return end
    
    local folder = Instance.new("Folder")
    folder.Name = player.Name .. "_UY"
    folder.Parent = CoreGui
    Lifecycle:AddInstance(folder)

    local highlight = Instance.new("Highlight", folder)
    highlight.Adornee = character
    highlight.OutlineColor, highlight.FillTransparency, highlight.OutlineTransparency, highlight.Enabled = Color3.new(1,1,1), 0.5, 0, false

    local billboard = Instance.new("BillboardGui", folder)
    billboard.Size, billboard.AlwaysOnTop, billboard.StudsOffset, billboard.MaxDistance, billboard.ResetOnSpawn, billboard.Enabled = UDim2.new(0, 200, 0, 150), true, Vector3.new(0, 3.5, 0), 0, false, false

    local iconImage = Instance.new("ImageLabel", billboard)
    iconImage.AnchorPoint, iconImage.Position, iconImage.Size, iconImage.BackgroundTransparency, iconImage.Visible = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 0), UDim2.new(0, 40, 0, 40), 1, false
    iconImage.Image = "rbxthumb://type=AvatarHeadShot&id=" .. player.UserId .. "&w=150&h=150"
    Instance.new("UICorner", iconImage).CornerRadius = UDim.new(1, 0)

    local textLabel = Instance.new("TextLabel", billboard)
    textLabel.AnchorPoint, textLabel.Position, textLabel.Size, textLabel.BackgroundTransparency, textLabel.TextStrokeTransparency, textLabel.Visible = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, 45), UDim2.new(1, 0, 0, 30), 1, 0, false
    textLabel.TextColor3, textLabel.TextSize, textLabel.Font, textLabel.Text = Color3.new(1,1,1), 12, Enum.Font.SourceSansBold, ""

    local initialRoot = character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart or character:FindFirstChildOfClass("BasePart")
    if initialRoot then
        billboard.Adornee = initialRoot
    end

    local currentObj = {
        Folder = folder, Highlight = highlight, Billboard = billboard, Label = textLabel, IconImage = iconImage,
        Character = character, RootPart = initialRoot,
        Cache = { Health = -1, MaxHealth = -1, Dist = -1, Txt = "", Color = nil, HLEnabled = false, BBEnabled = false, LabelVisible = false, IconVisible = false }
    }

    ActiveEspObjects[player] = currentObj
    
    if Drawing then
        pcall(function()
            local line = Drawing.new("Line")
            line.Color, line.Thickness, line.Transparency, line.Visible = Color3.new(1,0,0), 1.0, 1, false
            ActiveTracers[player] = {
                Line = line,
                Visible = false,
                Color = nil,
                From = Vector2.zero,
                To = Vector2.zero
            }
            Lifecycle:AddInstance(line)
        end)
    end
end

local function cleanPlayerTracking(player)
    if PlayerTracking[player] then
        for i = 1, #PlayerTracking[player].Connections do
            local conn = PlayerTracking[player].Connections[i]
            if conn and conn.Connected then conn:Disconnect() end
        end
        table.clear(PlayerTracking[player].Connections)
        removeEspObjects(player)
        PlayerTracking[player] = nil
    end
end

Lifecycle:AddCleanup(function()
    local playersAll = Players:GetPlayers()
    for i = 1, #playersAll do cleanPlayerTracking(playersAll[i]) end
end)

local function setupHumanoidProperties(humanoid)
    if not humanoid then return end
    clearHumanoidConnections()
    
    table.insert(humanoidConnections, Lifecycle:AddConnection(humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        if speedEnabled and humanoid.WalkSpeed ~= globalSpeed then humanoid.WalkSpeed = globalSpeed elseif not speedEnabled then lastNormalWalkSpeed = humanoid.WalkSpeed end
    end)))
    table.insert(humanoidConnections, Lifecycle:AddConnection(humanoid:GetPropertyChangedSignal("JumpPower"):Connect(function()
        if jumpEnabled then if not humanoid.UseJumpPower then humanoid.UseJumpPower = true end if humanoid.JumpPower ~= globalJump then humanoid.JumpPower = globalJump end elseif not jumpEnabled then lastNormalJumpPower = humanoid.JumpPower end
    end)))
    table.insert(humanoidConnections, Lifecycle:AddConnection(humanoid:GetPropertyChangedSignal("UseJumpPower"):Connect(function()
        if jumpEnabled and not humanoid.UseJumpPower then humanoid.UseJumpPower = true elseif not jumpEnabled then lastNormalUseJumpPower = humanoid.UseJumpPower end
    end)))

    if not speedEnabled then lastNormalWalkSpeed = humanoid.WalkSpeed end
    if speedEnabled then humanoid.WalkSpeed = globalSpeed end
    if jumpEnabled then humanoid.UseJumpPower = true; humanoid.JumpPower = globalJump end
end

local function hideEsp(player, esp, tracerData)
    if esp then
        if esp.Cache.HLEnabled then
            esp.Highlight.Enabled = false
            esp.Cache.HLEnabled = false
        end
        if esp.Cache.BBEnabled then
            esp.Billboard.Enabled = false
            esp.Cache.BBEnabled = false
        end
    end
    if tracerData then
        if tracerData.Visible then
            tracerData.Line.Visible = false
            tracerData.Visible = false
        end
    end
end

local function updateEspState()
    local isEspActive = Options.EspHighlight or Options.EspNames or Options.EspHealth or Options.EspDistance or Options.EspTracers or Options.ShowEspIcon
    
    if isEspActive then
        if not espConnection then
            local next = next
            espConnection = RunService.RenderStepped:Connect(function()
                Cache_MyTeam, Cache_MyNeutral = LocalPlayer.Team, (LocalPlayer.Neutral == true)
                local myChar = LocalPlayer.Character
                local myHrp = myChar and (myChar:FindFirstChild("HumanoidRootPart") or myChar.PrimaryPart or myChar:FindFirstChildOfClass("BasePart"))
                local myPos = (myHrp and myHrp.Position) or Camera.CFrame.Position
                local viewportCenter = Camera.ViewportSize * 0.5
                local maxDistSq = Options.MaxDistance * Options.MaxDistance

                local hasBlacklist = (next(Options.Blacklist) ~= nil)

                local playersAll = Players:GetPlayers()
                for i = 1, #playersAll do
                    local player = playersAll[i]
                    if player == LocalPlayer then continue end

                    local char = player.Character
                    local esp = ActiveEspObjects[player]
                    local tracerData = ActiveTracers[player]

                    if char and char.Parent then
                        if not esp or esp.Character ~= char then
                            buildEsp(player, char)
                            esp = ActiveEspObjects[player]
                            tracerData = ActiveTracers[player]
                        end
                    else
                        hideEsp(player, esp, tracerData)
                        continue
                    end

                    if not esp then continue end

                    local hrp = esp.RootPart
                    if not hrp or not hrp.Parent or hrp.Parent ~= char then
                        hrp = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart or char:FindFirstChildOfClass("BasePart")
                        esp.RootPart = hrp
                        if hrp and esp.Billboard.Adornee ~= hrp then 
                            esp.Billboard.Adornee = hrp 
                        end
                    end

                    local humanoid = char:FindFirstChildOfClass("Humanoid")
                    if not hrp or not humanoid or humanoid.Health <= 0 then 
                        hideEsp(player, esp, tracerData)
                        continue 
                    end
                    
                    local rx, ry, rz = hrp.Position.X, hrp.Position.Y, hrp.Position.Z
                    local dx, dy, dz = myPos.X - rx, myPos.Y - ry, myPos.Z - rz
                    local distSq = dx*dx + dy*dy + dz*dz

                    if distSq > maxDistSq then 
                        hideEsp(player, esp, tracerData)
                        continue 
                    end

                    if hasBlacklist and not Options.Blacklist[player.Name] then
                        hideEsp(player, esp, tracerData)
                        continue
                    end

                    local isAllowedVisual = not (Options.TeamCheck and ((player.Neutral and Cache_MyNeutral) or (player.Team ~= nil and player.Team == Cache_MyTeam))) and not (Options.AntiFriends and FriendsCache[player.Name]) and not Options.Whitelist[player.Name]

                    if not isAllowedVisual then 
                        hideEsp(player, esp, tracerData)
                        continue 
                    end

                    local teamColor = player.TeamColor and player.TeamColor.Color or Color3.fromRGB(255, 0, 0)
                    local cache = esp.Cache

                    if Options.EspHighlight then
                        if cache.Color ~= teamColor then esp.Highlight.FillColor = teamColor; cache.Color = teamColor end
                        if not cache.HLEnabled then esp.Highlight.Enabled = true; cache.HLEnabled = true end
                    else
                        if cache.HLEnabled then esp.Highlight.Enabled = false; cache.HLEnabled = false end
                    end

                    local showText = Options.EspNames or Options.EspHealth or Options.EspDistance
                    if showText or Options.ShowEspIcon then
                        if not cache.BBEnabled then esp.Billboard.Enabled = true; cache.BBEnabled = true end
                        if showText then
                            if not cache.LabelVisible then esp.Label.Visible = true; cache.LabelVisible = true end
                            local hpInt, maxHpInt, distInt = math.floor(humanoid.Health), math.floor(humanoid.MaxHealth), math.floor(math.sqrt(distSq))
                            
                            if cache.Health ~= hpInt or cache.MaxHealth ~= maxHpInt or cache.Dist ~= distInt then
                                cache.Health, cache.MaxHealth, cache.Dist = hpInt, maxHpInt, distInt
                                local txt = ""
                                if Options.EspNames then txt = txt .. player.Name .. "\n" end
                                if Options.EspHealth then txt = txt .. "HP: " .. hpInt .. "/" .. maxHpInt .. " " end
                                if Options.EspDistance then txt = txt .. "[" .. distInt .. "m]" end
                                
                                if cache.Txt ~= txt then esp.Label.Text = txt; cache.Txt = txt end
                            end
                        else 
                            if cache.LabelVisible then esp.Label.Visible = false; cache.LabelVisible = false end 
                        end
                        
                        if Options.ShowEspIcon then
                            if not cache.IconVisible then esp.IconImage.Visible = true; cache.IconVisible = true end
                        else
                            if cache.IconVisible then esp.IconImage.Visible = false; cache.IconVisible = false end
                        end
                    else
                        if cache.BBEnabled then esp.Billboard.Enabled = false; cache.BBEnabled = false end 
                    end

                    if Options.EspTracers and tracerData then
                        local screenPos, onScreen = Camera:WorldToViewportPoint(hrp.Position)
                        if onScreen then
                            local line = tracerData.Line
                            if tracerData.Color ~= teamColor then line.Color = teamColor; tracerData.Color = teamColor end
                            if tracerData.From ~= viewportCenter then line.From = viewportCenter; tracerData.From = viewportCenter end
                            local toVec = Vector2.new(screenPos.X, screenPos.Y)
                            if tracerData.To ~= toVec then line.To = toVec; tracerData.To = toVec end
                            if not tracerData.Visible then line.Visible = true; tracerData.Visible = true end
                        else
                            if tracerData.Visible then tracerData.Line.Visible = false; tracerData.Visible = false end
                        end
                    else
                        if tracerData and tracerData.Visible then tracerData.Line.Visible = false; tracerData.Visible = false end
                    end
                end
            end)
            Lifecycle:AddConnection(espConnection)
        end
    else
        if espConnection then
            espConnection:Disconnect()
            espConnection = nil
            for _, esp in pairs(ActiveEspObjects) do
                hideEsp(nil, esp, nil)
            end
            for _, tracer in pairs(ActiveTracers) do 
                if tracer and tracer.Visible then tracer.Line.Visible = false; tracer.Visible = false end
            end
        end
    end
end

-- ===== 7. LABELS UI SYSTEM ===== --
local LabelsGui = Instance.new("ScreenGui")
LabelsGui.Name = "UY_LabelsMonitor"
LabelsGui.ResetOnSpawn = false
LabelsGui.Parent = CoreGui
Lifecycle:AddInstance(LabelsGui)

local LabelsData = {}
local function CreateLabelPanel(name, defaultPos)
    local frame = Instance.new("Frame", LabelsGui)
    frame.Size, frame.Position, frame.BackgroundColor3, frame.BorderSizePixel, frame.Visible = UDim2.new(0, 150, 0, 40), defaultPos, Color3.fromRGB(30, 30, 35), 0, false
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 6)

    local title = Instance.new("TextLabel", frame)
    title.Size, title.BackgroundTransparency, title.TextColor3, title.TextSize, title.Font, title.Text = UDim2.new(1, 0, 0, 15), 1, Color3.fromRGB(200, 200, 200), 10, Enum.Font.GothamBold, name

    local val = Instance.new("TextLabel", frame)
    val.Size, val.Position, val.BackgroundTransparency, val.TextColor3, val.TextSize, val.Font, val.Text = UDim2.new(1, 0, 0, 25), UDim2.new(0, 0, 0, 15), 1, Color3.fromRGB(255, 255, 255), 14, Enum.Font.Gotham, "..."

    local dragging, dragInput, dragStart, startPos
    Lifecycle:AddConnection(frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, input.Position, frame.Position
            input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
        end
    end))
    Lifecycle:AddConnection(frame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
    end))
    Lifecycle:AddConnection(UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end))
    LabelsData[name] = { Frame = frame, ValLabel = val, Visible = false, DefaultPos = defaultPos }
end

CreateLabelPanel("FPS Monitor", UDim2.new(0, 20, 0, 20))
CreateLabelPanel("Ping Monitor", UDim2.new(0, 20, 0, 70))
CreateLabelPanel("Position Monitor", UDim2.new(0, 20, 0, 120))
CreateLabelPanel("Stat Monitor", UDim2.new(0, 20, 0, 170))
CreateLabelPanel("Server Monitor", UDim2.new(0, 20, 0, 220))
CreateLabelPanel("Target Monitor", UDim2.new(0, 20, 0, 270))
CreateLabelPanel("Camera Monitor", UDim2.new(0, 20, 0, 320))

local function updateLabelsState()
    local anyVisible = false
    for _, data in pairs(LabelsData) do
        if data.Visible then
            anyVisible = true
            break
        end
    end

    if anyVisible then
        if not labelsConnection then
            local fpsFrames, lastFpsUpdate, lastFastUpdate, lastSlowUpdate = 0, tick(), tick(), tick()
            labelsConnection = RunService.RenderStepped:Connect(function()
                fpsFrames += 1
                local t = tick()
                local myHrp = LocalPlayer.Character and (LocalPlayer.Character:FindFirstChild("HumanoidRootPart") or LocalPlayer.Character.PrimaryPart or LocalPlayer.Character:FindFirstChildOfClass("BasePart"))

                if t - lastFastUpdate >= 0.1 then
                    lastFastUpdate = t
                    if LabelsData["Position Monitor"].Visible then
                        LabelsData["Position Monitor"].ValLabel.Text = myHrp and string.format("X: %.1f Y: %.1f Z: %.1f", myHrp.Position.X, myHrp.Position.Y, myHrp.Position.Z) or "N/A"
                    end
                    if LabelsData["Stat Monitor"].Visible then
                        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
                        local hp = hum and hum.Health or 0
                        local maxHp = hum and hum.MaxHealth or 100
                        local speed = myHrp and (myHrp.AssemblyLinearVelocity * Vector3.new(1,0,1)).Magnitude or 0
                        LabelsData["Stat Monitor"].ValLabel.Text = string.format("HP: %.0f/%.0f | Speed: %.1f", hp, maxHp, speed)
                    end
                    if LabelsData["Target Monitor"].Visible then
                        if selectedTpPlayer ~= "" then
                            local tgt = Players:FindFirstChild(selectedTpPlayer)
                            local tgtHum = tgt and tgt.Character and tgt.Character:FindFirstChildOfClass("Humanoid")
                            local tgtHrp = tgt and tgt.Character and (tgt.Character:FindFirstChild("HumanoidRootPart") or tgt.Character.PrimaryPart or tgt.Character:FindFirstChildOfClass("BasePart"))
                            if tgtHum and tgtHrp and myHrp then
                                LabelsData["Target Monitor"].ValLabel.Text = string.format("HP: %.0f | Dist: %.0f | WS: %.1f", tgtHum.Health, (myHrp.Position - tgtHrp.Position).Magnitude, tgtHum.WalkSpeed)
                            else LabelsData["Target Monitor"].ValLabel.Text = "Target Dead/N/A" end
                        else LabelsData["Target Monitor"].ValLabel.Text = "No Target" end
                    end
                    if LabelsData["Camera Monitor"].Visible then
                        LabelsData["Camera Monitor"].ValLabel.Text = string.format("FOV: %.0f | %s", Camera.FieldOfView, Camera.CameraType.Name)
                    end
                end

                if t - lastSlowUpdate >= 1 then
                    if LabelsData["FPS Monitor"].Visible then
                        LabelsData["FPS Monitor"].ValLabel.Text = string.format("FPS: %.0f", fpsFrames / (t - lastFpsUpdate))
                    end
                    fpsFrames, lastFpsUpdate, lastSlowUpdate = 0, t, t

                    if LabelsData["Ping Monitor"].Visible then
                        pcall(function() LabelsData["Ping Monitor"].ValLabel.Text = string.format("Ping: %.0f ms", Stats.Network.ServerStatsItem["Data Ping"]:GetValue()) end)
                    end
                    if LabelsData["Server Monitor"].Visible then
                        LabelsData["Server Monitor"].ValLabel.Text = string.format("Players: %d/%d", #Players:GetPlayers(), Players.MaxPlayers)
                    end
                end
            end)
            Lifecycle:AddConnection(labelsConnection)
        end
    else
        if labelsConnection then
            labelsConnection:Disconnect()
            labelsConnection = nil
        end
    end
end

-- ===== 8. ANTI BACKGROUND CONNECTOR ===== --
Lifecycle:AddConnection(LocalPlayer.Idled:Connect(function()
    if not antiAfkEnabled then return end
    pcall(function()
        VirtualUser:Button2Down(Vector2.new(0,0))
        task.wait(0.1)
        VirtualUser:Button2Up(Vector2.new(0,0))
    end)
end))

local function setAntiGameplayPaused(Value)
    antiGameplayPausedEnabled = Value
    if Value then
        local existing = CoreGui.RobloxGui:FindFirstChild("CoreScripts/NetworkPause")
		local existing2 = CoreGui.RobloxGui.Modules:FindFirstChild("CoreScripts/NetworkPause")
        if existing then 
			existing.Enabled = false
		end
		if existing2 then
			existing2.Enabled = false
		end
	else
		local existing = CoreGui.RobloxGui:FindFirstChild("CoreScripts/NetworkPause")
		local existing2 = CoreGui.RobloxGui.Modules:FindFirstChild("CoreScripts/NetworkPause")
		if existing then
			existing.Enabled = true
		end
		if existing2 then 
			existing2.Enabled = true
		end
    end
end

local function setAntiVoid(Value)
    antiVoidEnabled = Value
    if antiVoidConn then antiVoidConn:Disconnect() antiVoidConn = nil end
    if Value then
        local orgDestroyHeight = workspace.FallenPartsDestroyHeight
        antiVoidConn = RunService.Stepped:Connect(function()
            local char = LocalPlayer.Character
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart or char:FindFirstChildOfClass("BasePart"))
            if root then
                if root.Position.Y <= orgDestroyHeight + 25 then
                    root.Velocity = Vector3.new(root.Velocity.X, 250, root.Velocity.Z)
                end
            end
        end)
        Lifecycle:AddConnection(antiVoidConn)
    end
end

-- ===== 9. RAYFIELD UI CREATION ===== --
local Window = Rayfield:CreateWindow({
    Name = "Universal Yield Menu", Icon = "globe",
    LoadingTitle = "Universal Utilities", LoadingSubtitle = "by Finalelele", Theme = "Ocean",
    ToggleUIKeybind = "K", ConfigurationSaving = { Enabled = true, FolderName = "UniversalYield", FileName = "Config" }
})
Lifecycle:AddCleanup(function() Rayfield:Destroy() end)

local PlayerTab = Window:CreateTab("Player", "user")
PlayerTab:CreateSection("Movement Physics")
WalkSpeedToggleComponent = PlayerTab:CreateToggle({ Name = "Enable Custom WalkSpeed", CurrentValue = false, Flag = "WalkSpeed_Toggle", Callback = setSpeedEnabled })
PlayerTab:CreateSlider({ Name = "WalkSpeed Multiplier", Range = {16, 250}, Increment = 1, Suffix = " studs", CurrentValue = 16, Flag = "WalkSpeed_Slider", Callback = setGlobalSpeed })
JumpPowerToggleComponent = PlayerTab:CreateToggle({ Name = "Enable Custom Jump", CurrentValue = false, Flag = "JumpPower_Toggle", Callback = setJumpEnabled })
PlayerTab:CreateSlider({ Name = "Jump Strength", Range = {7, 300}, Increment = 1, Suffix = " power", CurrentValue = 50, Flag = "JumpPower_Slider", Callback = setGlobalJump })
InfJumpToggleComponent = PlayerTab:CreateToggle({ Name = "Enable Infinite Jump", CurrentValue = false, Flag = "InfJump_Toggle", Callback = setInfJump })
PlayerTab:CreateSection("Abilities")
FlyToggleComponent = PlayerTab:CreateToggle({ Name = "Enable Fly", CurrentValue = false, Flag = "Fly_Toggle", Callback = setFlyEnabled })
PlayerTab:CreateSlider({ Name = "Fly Speed", Range = {10, 300}, Increment = 5, Suffix = " studs", CurrentValue = 50, Flag = "FlySpeed_Slider", Callback = setFlySpeed })
NoclipToggleComponent = PlayerTab:CreateToggle({ Name = "Noclip", CurrentValue = false, Flag = "Noclip_Toggle", Callback = setNoclipEnabled })

local EspTab = Window:CreateTab("ESP", "eye")
EspTab:CreateSection("Visuals")
EspTab:CreateToggle({ Name = "Chams", CurrentValue = false, Flag = "Esp_Highlight", Callback = function(v) Options.EspHighlight = v; updateEspState() end })
EspTab:CreateToggle({ Name = "Names", CurrentValue = false, Flag = "Esp_Names", Callback = function(v) Options.EspNames = v; updateEspState() end })
EspTab:CreateToggle({ Name = "Health", CurrentValue = false, Flag = "Esp_Health", Callback = function(v) Options.EspHealth = v; updateEspState() end })
EspTab:CreateToggle({ Name = "Distance", CurrentValue = false, Flag = "Esp_Distance", Callback = function(v) Options.EspDistance = v; updateEspState() end })
EspTab:CreateToggle({ Name = "Tracers", CurrentValue = false, Flag = "Esp_Tracers", Callback = function(v) Options.EspTracers = v; updateEspState() end })
EspTab:CreateToggle({ Name = "Icon", CurrentValue = false, Flag = "Esp_Icon", Callback = function(v) Options.ShowEspIcon = v; updateEspState() end })
EspTab:CreateSection("Filters")
EspTab:CreateToggle({ Name = "Team Check", CurrentValue = false, Flag = "TeamCheck_Toggle", Callback = function(v) Options.TeamCheck = v; updateEspState() end })
EspTab:CreateToggle({ Name = "Anti-Friends", CurrentValue = false, Flag = "AntiFriends_Toggle", Callback = function(v) Options.AntiFriends = v; updateEspState() end })
EspTab:CreateSlider({ Name = "Max Distance", Range = {10, 2000}, Increment = 25, Suffix = " studs", CurrentValue = 500, Flag = "Distance_Slider", Callback = function(v) Options.MaxDistance = v; updateEspState() end })
WhitelistDropdown = EspTab:CreateDropdown({ 
    Name = "Whitelist", 
    Options = {}, 
    CurrentOption = {}, 
    MultipleOptions = true, 
    Flag = "Whitelist_Drop", 
    Callback = function(opts) 
        table.clear(Options.Whitelist) 
        for i = 1, #opts do 
            local name = opts[i]
            if Options.Blacklist[name] then
                Rayfield:Notify({Title = "Ошибка", Content = "ошибка игрок уже выбран в Черный список", Duration = 3, Image = "x"})
            else
                Options.Whitelist[name] = true 
            end
        end 
        updateEspState() 
    end 
})
BlacklistDropdown = EspTab:CreateDropdown({
    Name = "Blacklist",
    Options = {},
    CurrentOption = {},
    MultipleOptions = true,
    Flag = "Blacklist_Drop",
    Callback = function(opts)
        table.clear(Options.Blacklist)
        for i = 1, #opts do
            local name = opts[i]
            if Options.Whitelist[name] then
                Rayfield:Notify({Title = "Ошибка", Content = "ошибка игрок уже выбран в Белый список", Duration = 3, Image = "x"})
            else
                Options.Blacklist[name] = true
            end
        end
        updateEspState()
    end
})

local OtherTab = Window:CreateTab("Others", "list")

OtherTab:CreateSection("Visuals")
FullbrightToggleComponent = OtherTab:CreateToggle({ Name = "Fullbright", CurrentValue = false, Flag = "Fullbright_Toggle", Callback = setFullbrightEnabled })
NoFogToggleComponent = OtherTab:CreateToggle({ Name = "NoFog", CurrentValue = false, Flag = "NoFog_Toggle", Callback = setNoFogEnabled })
XrayToggleComponent = OtherTab:CreateToggle({ Name = "X-Ray", CurrentValue = false, Flag = "Xray_Toggle", Callback = setXrayEnabled })
OtherTab:CreateDropdown({ Name = "X-Ray Mode", Options = {"Dynamic", "Static"}, CurrentOption = {"Dynamic"}, MultipleOptions = false, Flag = "Xray_Mode_Drop", Callback = function(opt) xrayMode = opt[1] or opt; setXrayEnabled(xrayEnabled) end })
OtherTab:CreateSlider({ Name = "X-Ray Distance", Range = {10, 2000}, Increment = 25, Suffix = " studs", CurrentValue = 500, Flag = "Xray_Distance_Slider", Callback = function(Value) xrayDistance = Value; if xrayEnabled and xrayMode == "Static" and (tick() - lastXrayUpdate > 1) then executeXrayScan() end end })

OtherTab:CreateSection("Camera")
OtherTab:CreateToggle({ Name = "Noclip Cam", CurrentValue = false, Flag = "CameraNoclip_Toggle", Callback = setCameraNoclipEnabled })
OtherTab:CreateSlider({ Name = "Field Of View", Range = {30, 120}, Increment = 1, Suffix = " fov", CurrentValue = 70, Flag = "Fov_Slider", Callback = updateFovStatic })
EnableFovToggleComponent = OtherTab:CreateToggle({ Name = "Enable FOV", CurrentValue = false, Flag = "LoopFov_Toggle", Callback = setLoopFovEnabled })

OtherTab:CreateSection("Target Selection")
TpDropdown = OtherTab:CreateDropdown({ Name = "Target Player", Options = {}, CurrentOption = "", MultipleOptions = false, Flag = "Tp_Player_Drop", Callback = function(Option) selectedTpPlayer = Option[1] or Option or ""; updateLoopTpState() end })
OtherTab:CreateButton({ Name = "Reset Target", Callback = function() selectedTpPlayer = "" pcall(function() if TpDropdown then TpDropdown:Set({""}) end end); updateLoopTpState() end })
SpectateToggle = OtherTab:CreateToggle({ Name = "Spectate Target", CurrentValue = false, Flag = "Spectate_Toggle", Callback = setSpectateEnabled })
OtherTab:CreateButton({ Name = "Teleport Once", Callback = function() tipToPlayer(selectedTpPlayer) end })
OtherTab:CreateToggle({ Name = "Loop Teleport", CurrentValue = false, Flag = "LoopTp_Toggle", Callback = function(v) loopTpEnabled = v; updateLoopTpState() end })

OtherTab:CreateSection("TP Yourself")
OtherTab:CreateInput({
    Name = "TP Distance",
    CurrentValue = "",
    PlaceholderText = "E.g. 50 or -25",
    RemoveTextAfterFocusLost = false,
    Flag = "Tp_Yourself_Distance",
    Callback = function(Text)
        tpYourselfDistanceText = Text
    end,
})

OtherTab:CreateButton({
    Name = "tp Y pos",
    Callback = function()
        local dist = tonumber(tpYourselfDistanceText)
        if not dist then
            Rayfield:Notify({Title = "Ошибка", Content = "Введите корректное число!", Duration = 2, Image = "x"})
            return
        end
        local char = LocalPlayer.Character
        local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart or char:FindFirstChildOfClass("BasePart"))
        if root then
            root.CFrame = root.CFrame * CFrame.new(0, dist, 0)
        end
    end
})

OtherTab:CreateButton({
    Name = "tp x/z pos",
    Callback = function()
        local dist = tonumber(tpYourselfDistanceText)
        if not dist then
            Rayfield:Notify({Title = "Ошибка", Content = "Введите корректное число!", Duration = 2, Image = "x"})
            return
        end
        local char = LocalPlayer.Character
        local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart or char:FindFirstChildOfClass("BasePart"))
        if root then
            root.CFrame = root.CFrame * CFrame.new(0, 0, -dist)
        end
    end
})

OtherTab:CreateSection("Anti")
AntiAfkToggleComponent = OtherTab:CreateToggle({ Name = "Anti AFK", CurrentValue = false, Flag = "AntiAFK_Toggle", Callback = function(v) antiAfkEnabled = v end })
AntiGameplayPausedToggleComponent = OtherTab:CreateToggle({ Name = "Anti Gameplay Paused", CurrentValue = false, Flag = "AntiGameplayPaused_Toggle", Callback = setAntiGameplayPaused })
AntiVoidToggleComponent = OtherTab:CreateToggle({ Name = "Anti Game Void", CurrentValue = false, Flag = "AntiVoid_Toggle", Callback = setAntiVoid })

OtherTab:CreateSection("Waypoints")
WaypointDropdown = OtherTab:CreateDropdown({
    Name = "Saved Positions List",
    Options = {},
    CurrentOption = "",
    MultipleOptions = false,
    Flag = "Waypoint_Dropdown_List",
    Callback = function(Option)
        selectedWaypoint = Option[1] or Option or ""
    end
})

RenameInput = OtherTab:CreateInput({
    Name = "New Position Name",
    CurrentValue = "",
    PlaceholderText = "Type new name here...",
    RemoveTextAfterFocusLost = false,
    Flag = "Waypoint_Rename_Input",
    Callback = function(Text)
        renameInputText = Text
    end,
})

OtherTab:CreateButton({
    Name = "Rename Selected Position",
    Callback = function()
        if selectedWaypoint ~= "" and renameInputText ~= "" and savedPositionsMap[selectedWaypoint] then
            local oldName = selectedWaypoint
            local newName = renameInputText

            if savedPositionsMap[newName] then
                Rayfield:Notify({Title = "Ошибка", Content = "Имя уже существует!", Duration = 2, Image = "x"})
                return
            end

            local targetCF = savedPositionsMap[oldName]
            savedPositionsMap[oldName] = nil
            savedPositionsMap[newName] = targetCF

            for i = 1, #savedPositionsList do
                if savedPositionsList[i] == oldName then
                    savedPositionsList[i] = newName
                    break
                end
            end

            selectedWaypoint = newName
            WaypointDropdown:Refresh(savedPositionsList, true)
            WaypointDropdown:Set({newName})
            RenameInput:Set("")
            renameInputText = ""
            Rayfield:Notify({Title = "Переименовано", Content = "Позиция успешно переименована.", Duration = 2, Image = "check"})
        else
            Rayfield:Notify({Title = "Ошибка", Content = "Выберите позицию и введите корректное имя!", Duration = 2, Image = "x"})
        end
    end
})

OtherTab:CreateButton({
    Name = "Save Current Position",
    Callback = function()
        local myHrp = LocalPlayer.Character and (LocalPlayer.Character:FindFirstChild("HumanoidRootPart") or LocalPlayer.Character.PrimaryPart or LocalPlayer.Character:FindFirstChildOfClass("BasePart"))
        if myHrp then
            local currentCF = myHrp.CFrame
            local formattedName = string.format("X: %.1f | Y: %.1f | Z: %.1f", currentCF.X, currentCF.Y, currentCF.Z)
            
            if not savedPositionsMap[formattedName] then
                table.insert(savedPositionsList, formattedName)
            end
            savedPositionsMap[formattedName] = currentCF
            
            WaypointDropdown:Refresh(savedPositionsList, true)
            WaypointDropdown:Set({formattedName})
            selectedWaypoint = formattedName
            Rayfield:Notify({Title = "Сохранено", Content = "Позиция добавлена в выпадающий список.", Duration = 2, Image = "check"})
        end
    end
})

OtherTab:CreateButton({
    Name = "Tp To Selected Position",
    Callback = function()
        local targetCF = savedPositionsMap[selectedWaypoint]
        if targetCF then
            local myHrp = LocalPlayer.Character and (LocalPlayer.Character:FindFirstChild("HumanoidRootPart") or LocalPlayer.Character.PrimaryPart or LocalPlayer.Character:FindFirstChildOfClass("BasePart"))
            if myHrp then 
                myHrp.CFrame = targetCF 
            end
        else
            Rayfield:Notify({Title = "Ошибка", Content = "Выберите корректную позицию из списка!", Duration = 2, Image = "x"})
        end
    end
})

 OtherTab:CreateButton({
    Name = "Delete Selected Position",
    Callback = function()
        if selectedWaypoint ~= "" and savedPositionsMap[selectedWaypoint] then
            savedPositionsMap[selectedWaypoint] = nil
            for i = 1, #savedPositionsList do
                if savedPositionsList[i] == selectedWaypoint then
                    table.remove(savedPositionsList, i)
                    break
                end
            end
            selectedWaypoint = ""
            WaypointDropdown:Refresh(savedPositionsList, true)
            WaypointDropdown:Set({""})
            Rayfield:Notify({Title = "Удалено", Content = "Координата убрана из списка.", Duration = 2, Image = "trash"})
        end
    end
})

OtherTab:CreateButton({
    Name = "Delete All Positions",
    Callback = function()
        table.clear(savedPositionsList)
        table.clear(savedPositionsMap)
        selectedWaypoint = ""
        WaypointDropdown:Refresh(savedPositionsList, true)
        WaypointDropdown:Set({""})
        Rayfield:Notify({Title = "Очищено", Content = "Все сохранённые координаты удалены.", Duration = 2, Image = "trash-2"})
    end
})

OtherTab:CreateSection("Combat")
FlingToggle = OtherTab:CreateToggle({ Name = "enable fling (work with target)", CurrentValue = false, Flag = "Fling_Toggle", Callback = setFlingEnabled })
Spin360ToggleComponent = OtherTab:CreateToggle({ Name = "Spin 360", CurrentValue = false, Flag = "Spin360_Toggle", Callback = setSpinEnabled })
OtherTab:CreateSlider({ Name = "Spin 360 Duration", Range = {0.1, 2}, Increment = 0.1, Suffix = " sec", CurrentValue = 0.5, Flag = "Spin360_Duration", Callback = function(v) spinDuration = v end })

local LabelsTab = Window:CreateTab("Labels", "monitor")
LabelsTab:CreateSection("On-Screen Monitors")
for _, m in ipairs({"FPS", "Ping", "Position", "Stat", "Server", "Target", "Camera"}) do
    LabelsTab:CreateToggle({ Name = m.." Monitor", CurrentValue = false, Flag = "Lbl_"..m, Callback = function(v) if LabelsData[m.." Monitor"] then LabelsData[m.." Monitor"].Visible = v; LabelsData[m.." Monitor"].Frame.Visible = v; updateLabelsState() end end })
end

LabelsTab:CreateSection("Actions")
LabelsTab:CreateButton({
    Name = "Reset Labels Position",
    Callback = function()
        for _, data in pairs(LabelsData) do
            if data.Frame and data.DefaultPos then
                data.Frame.Position = data.DefaultPos
            end
        end
        Rayfield:Notify({Title = "Сброс успешен", Content = "Позиции окон восстановлены.", Duration = 2, Image = "refresh-cw"})
    end
})

-- ===== 10. KEYBINDS SYSTEM ===== --
local IsPC = UserInputService.KeyboardEnabled
if IsPC then
    local KeybindsTab = Window:CreateTab("Keybinds", "keyboard")
    KeybindsTab:CreateSection("Keybind Manager")

    local featureComponents = {
        ["Enable WalkSpeed"] = WalkSpeedToggleComponent,
        ["Enable Jump Power"] = JumpPowerToggleComponent,
        ["Enable Infinity Jump"] = InfJumpToggleComponent,
        ["Enable Fly"] = FlyToggleComponent,
        ["Noclip"] = NoclipToggleComponent,
        ["Enable Fling"] = FlingToggle,
        ["Spin 360"] = Spin360ToggleComponent,
        ["Anti AFK"] = AntiAfkToggleComponent,
        ["Anti Gameplay Paused"] = AntiGameplayPausedToggleComponent,
        ["Anti Game Void"] = AntiVoidToggleComponent,
        ["Enable FOV"] = EnableFovToggleComponent,
        ["X-Ray"] = XrayToggleComponent,
        ["Fullbright"] = FullbrightToggleComponent
    }

    KeybindFunctionDropdown = KeybindsTab:CreateDropdown({
        Name = "Select Function",
        Options = {"Enable WalkSpeed", "Enable Jump Power", "Enable Infinite Jump", "Enable Fly", "Noclip", "Enable Fling", "Spin 360", "Anti AFK", "Anti Gameplay Paused", "Anti Game Void", "Enable FOV", "X-Ray", "Fullbright"},
        CurrentOption = "",
        MultipleOptions = false,
        Callback = function(Option)
            selectedBindFunction = Option[1] or Option or ""
        end
    })

    KeybindInput = KeybindsTab:CreateInput({
        Name = "Keybind Button",
        CurrentValue = "",
        PlaceholderText = "E.g. G, H, T...",
        RemoveTextAfterFocusLost = false,
        Callback = function(Text)
            keybindInputText = Text:upper()
        end
    })

    CurrentKeybindsDropdown = KeybindsTab:CreateDropdown({
        Name = "Current Keybinds",
        Options = {},
        CurrentOption = "",
        MultipleOptions = false,
        Callback = function(Option)
            selectedCurrentBind = Option[1] or Option or ""
        end
    })

    KeybindsTab:CreateButton({
        Name = "Create Keybind",
        Callback = function()
            if selectedBindFunction ~= "" and keybindInputText ~= "" then
                if #keybindInputText ~= 1 or not keybindInputText:match("^[A-Z]$") then
                    Rayfield:Notify({Title = "Ошибка", Content = "Нужно написать одну английскую букву!", Duration = 3, Image = "x"})
                    return
                end

                local success, keyCode = pcall(function() return Enum.KeyCode[keybindInputText] end)
                if not success or not keyCode then
                    Rayfield:Notify({Title = "Ошибка", Content = "Неверная клавиша ввода!", Duration = 2, Image = "x"})
                    return
                end
                
                local keyName = keyCode.Name
                
                if functionToBinds[selectedBindFunction] then
                    local oldKey = functionToBinds[selectedBindFunction]
                    activeKeybinds[oldKey] = nil
                end
                
                if activeKeybinds[keyName] then
                    local oldFunc = activeKeybinds[keyName]
                    functionToBinds[oldFunc] = nil
                end
                
                functionToBinds[selectedBindFunction] = keyName
                activeKeybinds[keyName] = selectedBindFunction
                
                table.clear(keybindsListForDropdown)
                for func, key in pairs(functionToBinds) do
                    table.insert(keybindsListForDropdown, func .. " -> " .. key)
                end
                
                CurrentKeybindsDropdown:Refresh(keybindsListForDropdown, true)
                KeybindInput:Set("")
                keybindInputText = ""
                Rayfield:Notify({Title = "Связка создана", Content = "Клавиша успешно привязана к функции.", Duration = 2, Image = "check"})
            else
                Rayfield:Notify({Title = "Ошибка", Content = "Заполните функцию и введите клавишу!", Duration = 2, Image = "x"})
            end
        end
    })

    KeybindsTab:CreateButton({
        Name = "Remove Keybind",
        Callback = function()
            if selectedCurrentBind ~= "" then
                local funcName = selectedCurrentBind:match("^(.-)%s*->")
                if funcName and functionToBinds[funcName] then
                    local key = functionToBinds[funcName]
                    functionToBinds[funcName] = nil
                    activeKeybinds[key] = nil
                    
                    local comp = featureComponents[funcName]
                    if comp and comp.CurrentValue then
                        comp:Set(false)
                    end
                    
                    table.clear(keybindsListForDropdown)
                    for func, k in pairs(functionToBinds) do
                        table.insert(keybindsListForDropdown, func .. " -> " .. k)
                    end
                    
                    CurrentKeybindsDropdown:Refresh(keybindsListForDropdown, true)
                    CurrentKeybindsDropdown:Set({""})
                    selectedCurrentBind = ""
                    Rayfield:Notify({Title = "Удалено", Content = "Горячая клавиша успешно сброшена.", Duration = 2, Image = "trash"})
                end
            else
                Rayfield:Notify({Title = "Ошибка", Content = "Выберите бинд из списка для удаления!", Duration = 2, Image = "x"})
            end
        end
    })

    KeybindsTab:CreateButton({
        Name = "Remove all keybinds",
        Callback = function()
            for funcName, _ in pairs(functionToBinds) do
                local comp = featureComponents[funcName]
                if comp and comp.CurrentValue then
                    comp:Set(false)
                end
            end
            table.clear(functionToBinds)
            table.clear(activeKeybinds)
            table.clear(keybindsListForDropdown)
            
            CurrentKeybindsDropdown:Refresh({}, true)
            CurrentKeybindsDropdown:Set({""})
            selectedCurrentBind = ""
            Rayfield:Notify({Title = "Очищено", Content = "Все горячие клавиши успешно удалены.", Duration = 2, Image = "trash"})
        end
    })

    Lifecycle:AddConnection(UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.UserInputType == Enum.UserInputType.Keyboard then
            local keyName = input.KeyCode.Name
            local boundFunc = activeKeybinds[keyName]
            if boundFunc then
                local comp = featureComponents[boundFunc]
                if comp then
                    comp:Set(not comp.CurrentValue)
                end
            end
        end
    end))
end

-- ===== 11. EVENTS & UPDATE LOOPS ===== --
LocalPlayer.CharacterAdded:Connect(function(char)
    table.clear(noclipPartsCache)
    table.clear(noclipOriginalCanCollide)
    local hum = char:WaitForChild("Humanoid", 5)
    if hum then setupHumanoidProperties(hum) end
    if flyEnabled then setFlyEnabled(false) end
    if noclipEnabled then
        task.delay(0.5, function() cacheNoclipParts(char) end)
    end
end)

if LocalPlayer.Character then
    local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then setupHumanoidProperties(hum) end
    cacheNoclipParts(LocalPlayer.Character)
end

local function refreshDropdowns()
    local names = getActivePlayerNames()
    pcall(function()
        if WhitelistDropdown then WhitelistDropdown:Refresh(names, true) end
        if BlacklistDropdown then BlacklistDropdown:Refresh(names, true) end
        if TpDropdown then TpDropdown:Refresh(names, true) end
    end)
end

local function bindPlayerEvents(player)
    if player == LocalPlayer then return end
    cleanPlayerTracking(player)
    
    PlayerTracking[player] = { Connections = {} }
    
    queueFriendCheck(player)

    local function onCharAdded(char)
        for _, child in ipairs(char:GetDescendants()) do FlingAddPart(child) end
        table.insert(PlayerTracking[player].Connections, char.DescendantAdded:Connect(FlingAddPart))
        table.insert(PlayerTracking[player].Connections, char.DescendantRemoving:Connect(FlingRemovePart))
    end
    
    if player.Character then onCharAdded(player.Character) end
    
    table.insert(PlayerTracking[player].Connections, player.CharacterAdded:Connect(onCharAdded))
    table.insert(PlayerTracking[player].Connections, player.CharacterRemoving:Connect(function(char)
        for _, child in ipairs(char:GetDescendants()) do FlingRemovePart(char) end
    end))
end

local playersAll = Players:GetPlayers()
for i = 1, #playersAll do bindPlayerEvents(playersAll[i]) end

Lifecycle:AddConnection(Players.PlayerAdded:Connect(function(player)
    bindPlayerEvents(player)
    refreshDropdowns()
end))

Lifecycle:AddConnection(Players.PlayerRemoving:Connect(function(player)
    FriendsCache[player.Name] = nil
    Options.Whitelist[player.Name] = nil
    Options.Blacklist[player.Name] = nil
    if selectedTpPlayer == player.Name then
        selectedTpPlayer, loopTpEnabled = "", false
        if spectateEnabled and SpectateToggle then SpectateToggle:Set(false) end
    end
    cleanPlayerTracking(player)
    refreshDropdowns()
end))

refreshDropdowns()
Rayfield:LoadConfiguration()
pcall(function() 
    if WhitelistDropdown then 
        WhitelistDropdown:Set({})  
    end 
    if BlacklistDropdown then
        BlacklistDropdown:Set({})
    end
    if TpDropdown then 
        TpDropdown:Set({""}) 
    end 
    if WaypointDropdown then
        WaypointDropdown:Set({""})
        WaypointDropdown:Refresh({}, true)
    end
    if KeybindFunctionDropdown then 
        KeybindFunctionDropdown:Set({""}) 
    end
    if CurrentKeybindsDropdown then
        CurrentKeybindsDropdown:Set({""})
        CurrentKeybindsDropdown:Refresh({}, true)
    end
    if RenameInput then RenameInput:Set("") end
    if KeybindInput then KeybindInput:Set("") end
    
    selectedTpPlayer = ""
    selectedWaypoint = ""
    selectedBindFunction = ""
    keybindInputText = ""
    selectedCurrentBind = ""
    
    table.clear(Options.Whitelist) 
    table.clear(Options.Blacklist)
    table.clear(savedPositionsList)
    table.clear(savedPositionsMap)
    table.clear(functionToBinds)
    table.clear(activeKeybinds)
    table.clear(keybindsListForDropdown)
end)
