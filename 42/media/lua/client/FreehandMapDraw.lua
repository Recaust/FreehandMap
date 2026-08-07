local isDrawing = false
local isErasing = false
local currentLine = nil
local freehandEnabled = false
local eraserEnabled = false
local eraseRadius = 15

local currentColor = nil

-- Persistent Storage: Player ModData
local function getSavedLines()
    local player = getSpecificPlayer(0)
    if not player then return {} end
    
    local modData = player:getModData()
    if not modData.freehandMapLines then
        modData.freehandMapLines = {}
    end
    return modData.freehandMapLines
end

-- Helper: Check for inventory item (Build 42 compatible)
local function hasItemInInv(inv, itemType)
    if not inv then return false end
    if inv.containsType then
        return inv:containsType(itemType)
    elseif inv.containsTypeRec then
        return inv:containsTypeRec(itemType)
    end
    return false
end

-- Check if player has an item capable of erasing
local function hasEraser(character)
    if not character then return false end
    local inv = character:getInventory()
    return hasItemInInv(inv, "Eraser") or hasItemInInv(inv, "Pencil")
end

-- Inventory check for writing utensils
local function getAvailableColors(character)
    if not character then return {} end
    local inv = character:getInventory()
    if not inv then return {} end

    local colors = {}

    if hasItemInInv(inv, "Pen") then
        table.insert(colors, { name = "Black Pen", r = 0.1, g = 0.1, b = 0.1, a = 1.0 })
    end
    if hasItemInInv(inv, "RedPen") then
        table.insert(colors, { name = "Red Pen", r = 0.8, g = 0.1, b = 0.1, a = 1.0 })
    end
    if hasItemInInv(inv, "BluePen") then
        table.insert(colors, { name = "Blue Pen", r = 0.1, g = 0.3, b = 0.8, a = 1.0 })
    end
    if hasItemInInv(inv, "Pencil") then
        table.insert(colors, { name = "Pencil (Gray)", r = 0.4, g = 0.4, b = 0.4, a = 1.0 })
    end

    return colors
end

-- Coordinate conversions
local function UItoWorld(mapUI, x, y)
    if mapUI.mapAPI and mapUI.mapAPI.uiToWorldX then
        return mapUI.mapAPI:uiToWorldX(x, y), mapUI.mapAPI:uiToWorldY(x, y)
    elseif mapUI.uiToWorldX then
        return mapUI:uiToWorldX(x), mapUI:uiToWorldY(y)
    end
    return nil, nil
end

local function WorldtoUI(mapUI, x, y)
    if mapUI.mapAPI and mapUI.mapAPI.worldToUIX then
        return mapUI.mapAPI:worldToUIX(x, y), mapUI.mapAPI:worldToUIY(x, y)
    elseif mapUI.worldToUIX then
        return mapUI:worldToUIX(x), mapUI:worldToUIY(y)
    end
    return nil, nil
end

-- Erase drawn points near screen coordinates (x, y)
local function eraseAt(mapUI, mouseX, mouseY)
    local lines = getSavedLines()
    local radSq = eraseRadius * eraseRadius

    for lIdx = #lines, 1, -1 do
        local line = lines[lIdx]
        for pIdx = #line.points, 1, -1 do
            local pt = line.points[pIdx]
            local sx, sy = WorldtoUI(mapUI, pt.x, pt.y)
            if sx and sy then
                local distSq = (sx - mouseX)^2 + (sy - mouseY)^2
                if distSq <= radSq then
                    table.remove(line.points, pIdx)
                end
            end
        end
        if #line.points == 0 then
            table.remove(lines, lIdx)
        end
    end
end

-- UI Setup
local function addDrawUI(mapUI)
    if mapUI.freehandBtn then return end

    local btnWidth = 90
    local btnHeight = 25
    local startX = 20
    local spacing = 100

    -- Toggle Draw Button
    mapUI.freehandBtn = ISButton:new(startX, mapUI.height - 60, btnWidth, btnHeight, "Draw: OFF", mapUI, function(targetUI, btn)
        freehandEnabled = not freehandEnabled
        if freehandEnabled then
            eraserEnabled = false
            if mapUI.eraseBtn then 
                mapUI.eraseBtn:setTitle("Erase: OFF") 
                mapUI.eraseBtn.backgroundColor = {r=0.2, g=0.2, b=0.2, a=0.8} 
            end
            btn:setTitle("Draw: ON")
            btn.backgroundColor = {r = 0.1, g = 0.6, b = 0.1, a = 0.8}
        else
            btn:setTitle("Draw: OFF")
            btn.backgroundColor = {r = 0.2, g = 0.2, b = 0.2, a = 0.8}
        end
    end)
    mapUI.freehandBtn:initialise()
    mapUI.freehandBtn:instantiate()
    mapUI:addChild(mapUI.freehandBtn)

    -- Toggle Eraser Button
    mapUI.eraseBtn = ISButton:new(startX + spacing, mapUI.height - 60, btnWidth, btnHeight, "Erase: OFF", mapUI, function(targetUI, btn)
        local player = getSpecificPlayer(0)
        if not hasEraser(player) then
            if player and player.Say then
                player:Say("I need an Eraser or Pencil to erase!")
            end
            return
        end

        eraserEnabled = not eraserEnabled
        if eraserEnabled then
            freehandEnabled = false
            if mapUI.freehandBtn then 
                mapUI.freehandBtn:setTitle("Draw: OFF") 
                mapUI.freehandBtn.backgroundColor = {r=0.2, g=0.2, b=0.2, a=0.8} 
            end
            btn:setTitle("Erase: ON")
            btn.backgroundColor = {r = 0.8, g = 0.2, b = 0.2, a = 0.8}
        else
            btn:setTitle("Erase: OFF")
            btn.backgroundColor = {r = 0.2, g = 0.2, b = 0.2, a = 0.8}
        end
    end)
    mapUI.eraseBtn:initialise()
    mapUI.eraseBtn:instantiate()
    mapUI:addChild(mapUI.eraseBtn)

    -- Color Selector Button
    mapUI.colorBtn = ISButton:new(startX + (spacing * 2), mapUI.height - 60, btnWidth, btnHeight, "Color", mapUI, function(targetUI, btn)
        local player = getSpecificPlayer(0)
        local available = getAvailableColors(player)

        if #available == 0 then
            if player and player.Say then
                player:Say("I need a Pen or Pencil to draw!")
            end
            return
        end

        local context = ISContextMenu.get(0, btn:getAbsoluteX(), btn:getAbsoluteY() - (#available * 20))
        for _, c in ipairs(available) do
            context:addOption(c.name, nil, function()
                currentColor = { r = c.r, g = c.g, b = c.b, a = c.a }
                btn.backgroundColor = { r = c.r, g = c.g, b = c.b, a = 0.8 }
            end)
        end
    end)
    mapUI.colorBtn:initialise()
    mapUI.colorBtn:instantiate()
    mapUI:addChild(mapUI.colorBtn)
end

-- Hook into ISWorldMap UI instantiation
local original_instantiate = ISWorldMap.instantiate
function ISWorldMap:instantiate()
    original_instantiate(self)
    addDrawUI(self)
end

-- High-density spline smoothing algorithm
local function getSmoothedPoints(points)
    if #points < 3 then return points end

    local smoothed = {}
    for i = 1, #points - 1 do
        local p0 = points[math.max(1, i - 1)]
        local p1 = points[i]
        local p2 = points[i + 1]
        local p3 = points[math.min(#points, i + 2)]

        table.insert(smoothed, p1)

        for step = 1, 8 do
            local t = step / 9
            local t2 = t * t
            local t3 = t2 * t

            local x = 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
            local y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)

            table.insert(smoothed, { x = x, y = y })
        end
    end
    table.insert(smoothed, points[#points])
    return smoothed
end

-- Mouse Handling
local original_onMouseDown = ISWorldMap.onMouseDown
function ISWorldMap:onMouseDown(x, y)
    if eraserEnabled then
        local player = getSpecificPlayer(0)
        if not hasEraser(player) then
            eraserEnabled = false
            if self.eraseBtn then
                self.eraseBtn:setTitle("Erase: OFF")
                self.eraseBtn.backgroundColor = {r=0.2, g=0.2, b=0.2, a=0.8}
            end
            if player and player.Say then
                player:Say("I need an Eraser or Pencil to erase!")
            end
            return true
        end

        isErasing = true
        eraseAt(self, x, y)
        return true
    elseif freehandEnabled then
        local player = getSpecificPlayer(0)
        local available = getAvailableColors(player)

        if #available == 0 then
            if player and player.Say then
                player:Say("I need a Pen or Pencil to draw!")
            end
            return true
        end

        if not currentColor then
            currentColor = { r = available[1].r, g = available[1].g, b = available[1].b, a = available[1].a }
        else
            local valid = false
            for _, c in ipairs(available) do
                if c.r == currentColor.r and c.g == currentColor.g and c.b == currentColor.b then
                    valid = true
                    break
                end
            end
            if not valid then
                currentColor = { r = available[1].r, g = available[1].g, b = available[1].b, a = available[1].a }
            end
        end

        isDrawing = true
        local worldX, worldY = UItoWorld(self, x, y)
        if worldX and worldY then
            currentLine = { 
                points = {{ x = worldX, y = worldY }},
                color = { r = currentColor.r, g = currentColor.g, b = currentColor.b, a = currentColor.a }
            }
            table.insert(getSavedLines(), currentLine)
        end
        return true
    end
    return original_onMouseDown(self, x, y)
end

local original_onMouseMove = ISWorldMap.onMouseMove
function ISWorldMap:onMouseMove(dx, dy)
    local mouseX = self:getMouseX()
    local mouseY = self:getMouseY()

    if isErasing then
        eraseAt(self, mouseX, mouseY)
        return true
    elseif isDrawing and currentLine then
        local worldX, worldY = UItoWorld(self, mouseX, mouseY)
        if worldX and worldY then
            local last = currentLine.points[#currentLine.points]
            local distSq = (worldX - last.x)^2 + (worldY - last.y)^2
            if distSq > 0.1 then
                table.insert(currentLine.points, { x = worldX, y = worldY })
            end
        end
        return true
    end
    return original_onMouseMove(self, dx, dy)
end

local original_onMouseUp = ISWorldMap.onMouseUp
function ISWorldMap:onMouseUp(x, y)
    if isErasing then
        isErasing = false
        return true
    elseif isDrawing then
        isDrawing = false
        if currentLine and #currentLine.points > 2 then
            currentLine.points = getSmoothedPoints(currentLine.points)
        end
        currentLine = nil
        return true
    end
    return original_onMouseUp(self, x, y)
end

-- Render Loop
local original_render = ISWorldMap.render
function ISWorldMap:render()
    original_render(self)

    if not self.freehandBtn then
        addDrawUI(self)
    end

    -- Render lines connected via filled line bounding segments (eliminates dotted gaps)
    local lines = getSavedLines()
    for _, line in ipairs(lines) do
        local c = line.color or { r = 0, g = 0, b = 0, a = 1 }
        for i = 1, #line.points - 1 do
            local p1 = line.points[i]
            local p2 = line.points[i + 1]

            local sx1, sy1 = WorldtoUI(self, p1.x, p1.y)
            local sx2, sy2 = WorldtoUI(self, p2.x, p2.y)

            if sx1 and sy1 and sx2 and sy2 then
                -- Interpolate line segments to form a solid stroke
                local dx = sx2 - sx1
                local dy = sy2 - sy1
                local dist = math.max(1, math.floor(math.sqrt(dx * dx + dy * dy)))
                
                for step = 0, dist do
                    local t = step / dist
                    local x = sx1 + dx * t
                    local y = sy1 + dy * t
                    self:drawRect(x - 1, y - 1, 2, 2, c.a, c.r, c.g, c.b)
                end
            end
        end
    end

    -- Draw Eraser Cursor Preview
    if eraserEnabled then
        local mx = self:getMouseX()
        local my = self:getMouseY()
        self:drawRectBorder(mx - eraseRadius, my - eraseRadius, eraseRadius * 2, eraseRadius * 2, 0.8, 1.0, 0.2, 0.2)
    end
end