
require "Window"
require "GameLib"
require "Apollo"

local MailAutoText = Apollo.GetPackage("Gemini:Addon-1.1").tPackage:NewAddon("MailAutoText", false, {"Mail"}, "Gemini:Hook-1.0")
MailAutoText.ADDON_VERSION = {1, 2, 0}

local L = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:GetLocale("MailAutoText")

function MailAutoText:OnEnable()
    -- TODO: Check if "Mail" is installed (or have been replaced)
    Apollo.RegisterEventHandler("MailAddAttachment", "ItemAttachmentAdded", self)

    -- Hooking can only be done once the "luaMailCompose" object is initialized inside Mail
    MailAutoText:PostHook(Apollo.GetAddon("Mail"), "ComposeMail", MailAutoText.HookMailModificationFunctions)
end

function MailAutoText:HookMailModificationFunctions()	
    -- Now that Mail.luaComposeMail exist, hook into editing functions
	local luaMail = Apollo.GetAddon("Mail").luaComposeMail
    MailAutoText:Hook(luaMail, "OnClickAttachment", MailAutoText.ItemAttachmentRemoved)
    MailAutoText:Hook(luaMail, "OnCashAmountChanged", MailAutoText.CashAmountChanged)
    MailAutoText:Hook(luaMail, "OnMoneyCODCheck", MailAutoText.MoneyCODOn)
    MailAutoText:Hook(luaMail, "OnMoneyCODUncheck", MailAutoText.MoneyCODOff)
    MailAutoText:Hook(luaMail, "OnMoneySendCheck", MailAutoText.MoneySendOn)
    MailAutoText:Hook(luaMail, "OnMoneySendUncheck", MailAutoText.MoneySendOff)
end

function MailAutoText:ItemAttachmentAdded(nValue)
	-- Event fired at times we're not actually composing mail, such as right-clicking to equip items
	if Apollo.GetAddon("Mail").luaComposeMail == nil then
		return
	end

    -- Calculate new item-string and trigger body-update
    MailAutoText.strItemList = MailAutoText:GenerateItemListString(nValue, nil)
    MailAutoText:UpdateMessage()
end

function MailAutoText:ItemAttachmentRemoved(wndHandler, wndControl)
    -- Function is called twice by Mail addon - these filters (copied from Mail.lua) filters out one of them
    if wndHandler ~= wndControl then
        return
    end
    local iAttach = wndHandler:GetData()
    if iAttach == nil then
        return
    end
		
    -- Calculate new item-string and trigger body-update
    MailAutoText.strItemList = MailAutoText:GenerateItemListString(nil, iAttach)
    MailAutoText:UpdateMessage()
end

function MailAutoText:CashAmountChanged()	
    MailAutoText:UpdateMessage()
end

function MailAutoText:MoneyCODOn()
    MailAutoText.CreditsSend = false
    MailAutoText.CreditsCOD = true
    MailAutoText:UpdateMessage()
end

function MailAutoText:MoneyCODOff()
    MailAutoText.CreditsSend = false
    MailAutoText.CreditsCOD = false
    MailAutoText:UpdateMessage()
end

function MailAutoText:MoneySendOn()
    MailAutoText.CreditsSend = true
    MailAutoText.CreditsCOD = false
    MailAutoText:UpdateMessage()
end

function MailAutoText:MoneySendOff()
    MailAutoText.CreditsSend = false
    MailAutoText.CreditsCOD = false
    MailAutoText:UpdateMessage()
end

function MailAutoText:GoldPrettyPrint(monAmount)
    if monAmount == 0 then
        return ""
    end

    local strAmount = tostring(monAmount)
    local copper = string.sub(strAmount, -2, -1)
    local silver = string.sub(strAmount, -4, -3)
    local gold = string.sub(strAmount, -6, -5)
    local plat = string.sub(strAmount, -8, -7)

    local strResult = ""
    strResult = MailAutoText:AppendDenomination(strResult, MailAutoText:PrettyPrintDenomination(plat, "Platinum"))
    strResult = MailAutoText:AppendDenomination(strResult, MailAutoText:PrettyPrintDenomination(gold, "Gold"))
    strResult = MailAutoText:AppendDenomination(strResult, MailAutoText:PrettyPrintDenomination(silver, "Silver"))
    strResult = MailAutoText:AppendDenomination(strResult, MailAutoText:PrettyPrintDenomination(copper, "Copper"))

    return(strResult)
end

function MailAutoText:AppendDenomination(strFull, strAmount)
    local strResult = strFull

    -- If we're adding text to an existing string, insert a space
    if string.len(strResult) > 0 and string.len(strAmount) > 0 then
        strResult = strResult .. " "
    end

    -- Added current denom-string (if any) to the existing string
    if string.len(strAmount) > 0 then
        strResult = strResult .. strAmount
    end

    return strResult
end

function MailAutoText:PrettyPrintDenomination(strAmount, strDenomination)
    local strResult = ""
    if strAmount ~= nil and strAmount ~= "" and strAmount ~= "00" then
        if string.sub(strAmount, 1, 1) == "0" then
            -- Don't print "04 Silver", just "4 Silver"
            strResult = string.sub(strAmount, 2, 2) .. " " .. strDenomination
        else
            strResult = strAmount .. " " .. strDenomination
        end
    end
    return strResult
end

function MailAutoText:GenerateItemListString(addedAttachmentId, removedAttachmentIndex)

    -- Deep-copy "arAttachments" (except removed index) into local array
    local allAttachmentIds = {}
    for k,v in ipairs(Apollo.GetAddon("Mail").luaComposeMail.arAttachments) do
		if removedAttachmentIndex == nil or removedAttachmentIndex ~= k then
			allAttachmentIds[#allAttachmentIds+1] = v
		end
    end

    -- Check if the newly-attached item (if any) already exist in array, since we do not control the event call-order
    local bExists = false
    for k,v in ipairs(allAttachmentIds) do
        if v == addedAttachmentId then
            bExists = true
        end
    end

    -- Add new item to end of array if not present
    if bExists == false then
        allAttachmentIds[#allAttachmentIds+1] = addedAttachmentId
    end

    -- Concatenate list of items
    local strItems = ""
    for _,attachmentId in ipairs(allAttachmentIds) do
		local itemData = MailSystemLib.GetItemFromInventoryId(attachmentId)
        local itemId = itemData:GetItemId()
		local stackCount = itemData:GetStackCount()
        local itemDetails = Item.GetDetailedInfo(itemId)
        
		strItems = strItems .. itemDetails.tPrimary.strName		
		if stackCount > 1 then
			strItems = strItems .. " (x" .. stackCount .. ")"
		end
		strItems = strItems .. "\n"
    end

    return strItems
end

function MailAutoText:GenerateSubjectString()
    -- Get current subject string from GUI
    local currentSubject = Apollo.GetAddon("Mail").luaComposeMail.wndSubjectEntry:GetText()
	
	-- Check if current subject is an auto-generated one (or empty). If so, replace with updated auto-generated one
	local bUpdate = false
	if currentSubject == "" then 
		bUpdate = true
	else
		for k,v in pairs(L) do
			if v == currentSubject then 
				bUpdate = true
				break
			end
		end
	end
	
	-- Not an auto-generated subject? just return current subject then
	if bUpdate == false then
		return currentSubject
	end
	
	-- Sending items COD?
	if MailAutoText.CreditsCOD then
		return L["Subject_COD"]
	end
	
	-- Sending items and cash?
	if MailAutoText.CreditsSend == true and MailAutoText.strItemList ~= nil and MailAutoText.strItemList ~= "" then
		return L["Subject_Both"]
	end
	
	-- Sending items only?
	if MailAutoText.strItemList ~= nil and MailAutoText.strItemList ~= "" then
		return L["Subject_Items"]
	end

	-- Sending cash only?
	if MailAutoText.CreditsSend == true then
		return L["Subject_Cash"]
	end
	
	-- Not sending anything, no special subject autocompletion required.
	return currentSubject	
end

function MailAutoText:UpdateMessage()
	local strCredits = MailAutoText:GoldPrettyPrint(Apollo.GetAddon("Mail").luaComposeMail.wndCashWindow:GetAmount())
    local bCreditsText = (MailAutoText.CreditsSend or MailAutoText.CreditsCOD) and strCredits ~= ""
    local bItemListText = MailAutoText.strItemList ~= nil and MailAutoText.strItemList ~= ""

    -- Update subject
	Apollo.GetAddon("Mail").luaComposeMail.wndSubjectEntry:SetText(MailAutoText:GenerateSubjectString())

    -- Update body
    local currentBody = Apollo.GetAddon("Mail").luaComposeMail.wndMessageEntryText:GetText()

    -- Cut off the bottom half (our auto-text) of the msg body
    local newBody = ""
    if currentBody ~= nil then
        local index = string.find(currentBody, Apollo.GetString("CRB_Attachments_1"))

        if index == nil then
            newBody = currentBody
        else
            local strFirst = string.sub(currentBody, 1, (index-1))
            newBody = strFirst
        end
    end

    -- Append "Attachments" header if any attachments are identified
    if bCreditsText == true or bItemListText == true then
        if newBody == "" then
            newBody = Apollo.GetString("CRB_Attachments_1") .. "\n"
        else
            newBody = newBody .. Apollo.GetString("CRB_Attachments_1") .. "\n"
        end
    end

    -- Append credits text if sending credits
    if bCreditsText == true then		
        if MailAutoText.CreditsCOD == true then
            newBody = newBody .. "Cost: " .. strCredits .. "\n"
        end
        if MailAutoText.CreditsSend == true then
            newBody = newBody .. "Credits: " .. strCredits .. "\n"
        end
    end

	-- Append itemlist if sending items
    if bItemListText == true then
        newBody = newBody .. MailAutoText.strItemList
    end

	-- Update body
	Apollo.GetAddon("Mail").luaComposeMail.wndMessageEntryText:SetText(newBody)
end
