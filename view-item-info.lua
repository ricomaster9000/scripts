-- Extended Item Viewscreens
-- Shows information on material properties, weapon or armour stats, and more.
-- By PeridexisErrant, adapted from nb_item_info by Raidau
--@ enable = true
local help = [====[

view-item-info
==============
A script to extend the item or unit viewscreen with additional information
including a custom description of each item (when available), and properties
such as material statistics, weapon attacks, armor effectiveness, and more.

The associated script item-descriptions supplies custom descriptions
of items.  Individual descriptions can be added or overridden by a similar
script :file:`raw/scripts/more-item-descriptions.lua`.  Both work as sparse lists,
so missing items simply go undescribed if not defined in the fallback.

]====]

local utils = require 'utils'

local default_descriptions = reqscript('internal/view-item-info/item-descriptions').descriptions

function isInList(list, item, helper)
    if not helper then
        helper = function(v) return v end
    end
    for k,v in pairs (list) do
        if item == helper(v) then
            return true
        end
    end
    return false
end

if dfhack_flags and dfhack_flags.enable then
    --luacheck: global
    enabled = dfhack_flags.enable_state
end

local args = {...}
local lastframe = df.global.enabler.frame_last
if isInList(args, "help") or isInList(args, "?") then
    print(help)
    return
elseif isInList(args, "enable") then
    enabled = true
elseif isInList(args, "disable") then
    enabled = false
end

local standard = nil --as:df.material

function append (list, str, indent)
    local str = str or " "
    local indent = indent or 0
    table.insert(list, {str, indent * 4})
end

function add_lines_to_list(t1,t2)
    local t1 = t1 --as:{1:string,2:number}[]
    local t2 = t2 --as:{1:string,2:number}[]
    for i=1,#t2 do
        t1[#t1+1] = t2[i]
    end
    return t1
end

function GetMatPlant (item)
    if dfhack.matinfo.decode(item).mode == "plant" then
        return dfhack.matinfo.decode(item).plant
    end
end

function compare_iron (mat_prop, iron_prop)
    return " "..mat_prop.." ("..math.floor(mat_prop/iron_prop*100).."% of iron)"
end

function GetMatPropertiesStringList (item)
    local item = item --as:df.item_actual
    local mat = dfhack.matinfo.decode(item).material
    local list = {}
    local deg_U = item.temperature.whole
    local deg_C = math.floor((deg_U-10000)*5/9)
    append(list,"Temperature: "..deg_C.."\248C ("..deg_U.."U)")
    if mat.state_color.Solid ~= -1 then
        append(list,"Color: "..df.global.world.raws.descriptors.colors[mat.state_color.Solid].name)
    end
    local function GetStrainDescription (number)
        if tonumber(number) < 1 then return "crystalline"
        elseif tonumber(number) < 1000 then return "very stiff"
        elseif tonumber(number) < 5001 then return "stiff"
        elseif tonumber(number) < 15001 then return "medium"
        elseif tonumber(number) < 50000 then return "elastic"
        elseif tonumber(number) >= 50000 then return "very elastic"
        else return "unknown" end
    end
    local mat_properties_for = {"BAR", "SMALLGEM", "BOULDER", "ROUGH",
        "WOOD", "GEM", "ANVIL", "THREAD", "SHOES", "CLOTH", "ROCK", "WEAPON", "TRAPCOMP",
        "ORTHOPEDIC_CAST", "SIEGEAMMO", "SHIELD", "PANTS", "HELM", "GLOVES", "ARMOR", "AMMO"}
    if isInList(mat_properties_for, df.item_type[item:getType()]) then
        append(list,"Material name: "..mat.state_name.Solid)
        append(list,"Material properties: ")
        append(list,"Solid density: "..mat.solid_density..'kg/m^3',1)
        local maxedge = mat.strength.max_edge
        append(list,"Maximum sharpness: "..maxedge.." ("..maxedge/standard.strength.max_edge*100 .."%)",1)
        if mat.molar_mass > 0 then
            append(list,"Molar mass: "..mat.molar_mass,1)
        end
        append(list,"Shear strength:",1)
        append(list, "yield:"..compare_iron(mat.strength.yield.SHEAR, standard.strength.yield.SHEAR), 2)
        append(list, "fracture:"..compare_iron(mat.strength.fracture.SHEAR, standard.strength.fracture.SHEAR), 2)
        local s_strain = mat.strength.strain_at_yield.SHEAR
        append(list, "elasticity: "..s_strain.." ("..GetStrainDescription(s_strain)..")", 2)
        append(list,"Impact strength:",1)
        append(list, "yield:"..compare_iron(mat.strength.yield.IMPACT, standard.strength.yield.IMPACT), 2)
        append(list, "fracture:"..compare_iron(mat.strength.fracture.IMPACT, standard.strength.fracture.IMPACT), 2)
        local i_strain = mat.strength.strain_at_yield.IMPACT
        append(list, "elasticity: "..i_strain.." ("..GetStrainDescription(i_strain)..")", 2)
    end
    return list
end

function GetArmorPropertiesStringList (item)
    local item = item --as:df.item_armorst
    local mat = dfhack.matinfo.decode(item).material
    local list = {}
    append(list,"Armor properties: ")
    append(list,"Thickness: "..item.subtype.props.layer_size,1)
    append(list,"Coverage: "..item.subtype.props.coverage.."%",1)
    local craw = df.creature_raw.find(item.maker_race)
    if craw then
        append(list,"Fit for "..craw.name[0],1)
    end
    return list
end

function GetShieldPropertiesStringList (item)
    local item = item --as:df.item_shieldst
    local mat = dfhack.matinfo.decode(item).material
    local list = {}
    append(list,"Shield properties:")
    append(list,"Base block chance: "..item.subtype.blockchance,1)
    local craw = df.creature_raw.find(item.maker_race)
    if craw then
        append(list,"Fit for "..craw.name[0],1)
    end
    return list
end

function GetWeaponPropertiesStringList (item)
    local mat = dfhack.matinfo.decode(item).material
    local list = {}
    if item._type == df.item_toolst and #item.subtype.attacks < 1 then --hint:df.item_toolst
        return list
    end
    local item = item --as:df.item_weaponst
    append(list,"Weapon properties: ")
    if item.sharpness > 0 then
        append(list,"Sharpness:"..compare_iron(item.sharpness, standard.strength.max_edge),1)
    else
        append(list,"Not edged",1)
    end
    if string.len(item.subtype.ranged_ammo) > 0 then
        append(list,"Ranged weapon",1)
        append(list,"Ammo: "..item.subtype.ranged_ammo:lower(),2)
        if item.subtype.shoot_force > 0 then
            append(list,"Shoot force: "..item.subtype.shoot_force,2)
        end
        if item.subtype.shoot_maxvel > 0 then
            append(list,"Maximum projectile velocity: "..item.subtype.shoot_maxvel,2)
        end
    end
    append(list,"Required size: "..item.subtype.minimum_size*10,1)
    if item.subtype.two_handed*10 > item.subtype.minimum_size*10 then
        append(list,"Used as 2-handed until unit size: "..item.subtype.two_handed*10,2)
    end
    append(list,"Attacks: ",1)
    for k,attack in pairs (item.subtype.attacks) do
        local name = attack.verb_2nd
        if attack.noun ~= "NO_SUB" then
            name = name.." with "..attack.noun
        end
        if attack.edged then
            name = name.." (edged)"
        else
            name = name.." (blunt)"
        end
        append(list,name,2)
        append(list,"Contact area: "..attack.contact,3)
        if attack.edged then
            append(list,"Penetration: "..attack.penetration,3)
        end
        append(list,"Velocity multiplier: "..attack.velocity_mult/1000,3)
        if attack.flags.bad_multiattack then
            append(list,"Bad multiattack",3)
        end
        append(list,"Prepare "..attack.prepare.." / recover "..attack.recover,3)
    end
    return list
end

function GetAmmoPropertiesStringList (item)
    local mat = dfhack.matinfo.decode(item).material
    local list = {}
    if item._type == df.item_toolst and #item.subtype.attacks < 1 then --hint:df.item_toolst
        return list
    end
    local item = item --as:df.item_ammost
    append(list,"Ammo properties: ")
    if item.sharpness > 0 then
        append(list,"Sharpness: "..item.sharpness,1)
    else
        append(list,"Not edged",1)
    end
    append(list,"Attacks: ", 1)
    for k,attack in pairs (item.subtype.attacks) do
        local name = attack.verb_2nd
        if attack.noun ~= "NO_SUB" then
            name = name.." with "..attack.noun
        end
        if attack.edged then
            name = name.." (edged)"
        else
            name = name.." (blunt)"
        end
        append(list,name,2)
        append(list,"Contact area: "..attack.contact,3)
        if attack.edged then
            append(list,"Penetration: "..attack.penetration,3)
        end
        append(list,"Velocity multiplier: "..attack.velocity_mult/1000,3)
        if attack.flags.bad_multiattack then
            append(list,"Bad multiattack",3)
        end
        append(list,"Prepare "..attack.prepare.." / recover "..attack.recover,3)
    end
    return list
end

function edible_string (mat)
    local edible_string = "Edible"
    if mat.flags.EDIBLE_RAW or mat.flags.EDIBLE_COOKED then
        if mat.flags.EDIBLE_RAW then
            edible_string = edible_string.." raw"
            if mat.flags.EDIBLE_COOKED then
                edible_string = edible_string.." and cooked"
            end
        elseif mat.flags.EDIBLE_COOKED then
            edible_string = edible_string.." only when cooked"
        end
    else
        edible_string = "Not edible"
    end
    return edible_string
end

function GetReactionProduct (inmat, reaction)
    for k,v in pairs (inmat.reaction_product.id) do
        if v.value == reaction then
            return inmat.reaction_product.material.mat_type[k],
                    inmat.reaction_product.material.mat_index[k]
        end
    end
end

function add_react_prod (list, mat, product, str)
    local mat_type, mat_index = GetReactionProduct (mat, product)
    if mat_type then
        local result = dfhack.matinfo.decode(mat_type, mat_index).material.state_name.Liquid
        append(list, str..result)
    end
end

function get_plant_reaction_products (mat)
    local list = {}
    add_react_prod (list, mat, "GROWTH_JUICE_PROD", "Pressed into ")
    add_react_prod (list, mat, "PRESS_LIQUID_MAT", "Pressed into ")
    add_react_prod (list, mat, "LIQUID_EXTRACTABLE", "Extractable product: ")
    add_react_prod (list, mat, "WATER_SOLUTION_PROD", "Can be mixed with water to make ")
    add_react_prod (list, mat, "RENDER_MAT", "Rendered into ")
    add_react_prod (list, mat, "SOAP_MAT", "Used to make soap")
    if GetReactionProduct (mat, "SUGARABLE") then
        append(list,"Used to make sugar")
    end
    if  GetReactionProduct (mat, "MILLABLE") or
        GetReactionProduct (mat, "GRAIN_MILLABLE") or
        GetReactionProduct (mat, "GROWTH_MILLABLE") then
        append(list,"Can be milled")
    end
    if GetReactionProduct(mat, "GRAIN_THRESHABLE") then
        append(list,"Grain can be threshed")
    end
    if GetReactionProduct (mat, "CHEESE_MAT") then
        local mat_type, mat_index = GetReactionProduct (mat, "CHEESE_MAT")
        append(list,"Used to make "..dfhack.matinfo.decode(mat_type, mat_index).material.state_name.Solid)
    end
    return list
end

function GetFoodPropertiesStringList (item)
    local mat = dfhack.matinfo.decode(item).material
    local list = {{" ", 0}}
    append(list,edible_string(mat))
    if item._type == df.item_foodst then
        append(list,"This is prepared meal")
        return list
    end
    if mat == dfhack.matinfo.find ("WATER") then
        append(list,"Water is drinkable")
        return list
    end
    add_lines_to_list(list, get_plant_reaction_products(mat))
    if item._type == df.item_plantst and GetMatPlant (item) then
        local plant = GetMatPlant (item)
        if plant.material_defs.type[df.plant_material_def.mill] ~= -1 then
            local targetmat = dfhack.matinfo.decode(plant.material_defs.type[df.plant_material_def.mill], plant.material_defs.idx[df.plant_material_def.mill])
            append(list,'Ground into '..targetmat.material.prefix..''..targetmat.material.state_name[df.matter_state.Powder])
        end
        if plant.material_defs.type[df.plant_material_def.thread] ~= -1 then
            local targetmat = dfhack.matinfo.decode(plant.material_defs.type[df.plant_material_def.thread], plant.material_defs.idx[df.plant_material_def.thread])
            append(list,'Woven into '..targetmat.material.prefix..''..targetmat.material.state_name[df.matter_state.Solid])
        end
        if plant.material_defs.type[df.plant_material_def.drink] ~= -1 then
            local targetmat = dfhack.matinfo.decode(plant.material_defs.type[df.plant_material_def.drink], plant.material_defs.idx[df.plant_material_def.drink])
            append(list,'Brewed into '..targetmat.material.prefix..''..targetmat.material.state_name[df.matter_state.Liquid])
        end
        if plant.material_defs.type[df.plant_material_def.extract_barrel] ~= -1 then
            local targetmat = dfhack.matinfo.decode(plant.material_defs.type[df.plant_material_def.extract_barrel], plant.material_defs.idx[df.plant_material_def.extract_barrel])
            append(list,'Cask-aged into '..targetmat.material.prefix..''..targetmat.material.state_name[df.matter_state.Liquid])
        end
        if plant.material_defs.type[df.plant_material_def.extract_vial] ~= -1 then
            local targetmat = dfhack.matinfo.decode(plant.material_defs.type[df.plant_material_def.extract_vial], plant.material_defs.idx[df.plant_material_def.extract_vial])
            append(list,'Refined into vials of '..targetmat.material.prefix..''..targetmat.material.state_name[df.matter_state.Liquid])
        end
        if plant.material_defs.type[df.plant_material_def.extract_still_vial] ~= -1 then
            local targetmat = dfhack.matinfo.decode(plant.material_defs.type[df.plant_material_def.extract_still_vial], plant.material_defs.idx[df.plant_material_def.extract_still_vial])
            append(list,'Distilled into vials of '..targetmat.material.prefix..''..targetmat.material.state_name[df.matter_state.Liquid])
        end
    end
    return list
end

--luacheck: in=df.item_actual out=string[][]
function get_all_uses_strings (item)
    local all_lines = {} --as:string[][]
    local FoodsAndPlants = {df.item_type.MEAT, df.item_type.GLOB,
        df.item_type.PLANT, df.item_type.PLANT_GROWTH, df.item_type.LIQUID_MISC,
        df.item_type.POWDER_MISC, df.item_type.CHEESE, df.item_type.FOOD}
    local ArmourTypes = {df.item_type.ARMOR, df.item_type.PANTS,
        df.item_type.HELM, df.item_type.GLOVES, df.item_type.SHOES}
    if df.global.gamemode == df.game_mode.ADVENTURE and item ~= "COIN" then
        add_lines_to_list(all_lines, {{"Value: "..dfhack.items.getValue(item),0}})
    elseif isInList(ArmourTypes, item:getType()) then
        add_lines_to_list(all_lines, GetArmorPropertiesStringList(item))
    elseif item._type == df.item_weaponst or item._type == df.item_toolst then
        add_lines_to_list(all_lines, GetWeaponPropertiesStringList(item))
    elseif item._type == df.item_ammost then
        add_lines_to_list(all_lines, GetAmmoPropertiesStringList(item))
    elseif item._type == df.item_shieldst then
        add_lines_to_list(all_lines, GetShieldPropertiesStringList(item))
    elseif item._type == df.item_seedsst then
        local str = math.floor(GetMatPlant(item).growdur/12).." days"
        add_lines_to_list(all_lines, {{"Growth time: "..str, 0}})
    elseif isInList(FoodsAndPlants, item:getType()) then
        add_lines_to_list(all_lines, GetFoodPropertiesStringList(item))
    end
    if not dfhack.items.isCasteMaterial(item:getType()) then
        add_lines_to_list(all_lines, GetMatPropertiesStringList(item))
    end
    return all_lines
end

function get_custom_item_desc (item)
    local ID = df.item_type[item:getType()]
    if ID and dfhack.items.getSubtypeCount(df.item_type[ID]) ~= -1 then
        local item = item --as:df.item_armorst
        ID = item.subtype.id end
    if not ID then return nil end
    local desc = default_descriptions[ID]
    if dfhack.findScript("more-item-descriptions") then --luacheck: skip
        desc = dfhack.script_environment("more-item-descriptions").descriptions[ID] or desc
    end
    if desc then
        desc = utils.clone(desc)
        add_lines_to_list(desc, {""})
    end
    return desc
end

function AddUsesString (viewscreen,line,indent)
    local str = df.new("string")
    str.value = tostring(line)
    local indent = indent or 0
    viewscreen.entry_ref:insert('#', nil)
    viewscreen.entry_indent:insert('#', indent)
    viewscreen.entry_spatters:insert('#', nil) -- TODO: get this into structures, and fix usage!
    viewscreen.entry_string:insert('#', str)
    viewscreen.entry_reaction:insert('#', -1)
end

function dfhack.onStateChange.item_info (code)
    local vi_label = 'More information (DFHack):'
    if not enabled then return end
    if code == SC_VIEWSCREEN_CHANGED and dfhack.isWorldLoaded() then
        standard = dfhack.matinfo.find("INORGANIC:IRON").material
        if not standard then return end
        local scr = dfhack.gui.getCurViewscreen() --as:df.viewscreen_itemst
        if scr._type == df.viewscreen_itemst then
            if isInList(scr.entry_string, vi_label, function(v) return v.value end) then
                return
            end
            if #scr.entry_string > 0 then
                AddUsesString(scr, '')
            end
            AddUsesString(scr, vi_label)
            AddUsesString(scr, '')
            local description = get_custom_item_desc (scr.item) or ""
            for i = 1, #description do
                AddUsesString(scr,description[i])
            end
            local all_lines = get_all_uses_strings(scr.item)
            for i = 1, #all_lines do
                AddUsesString(scr,all_lines[i][1],all_lines[i][2])
            end
            scr.caption_uses = true
        end
    end
end
