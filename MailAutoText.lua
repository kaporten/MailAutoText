-----------------------------------------------------------------------------------------------
-- Client Lua Script for MailAutoText
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------
 
require "Window"
 
-----------------------------------------------------------------------------------------------
-- MailAutoText Module Definition
-----------------------------------------------------------------------------------------------
local MailAutoText = {} 
 
-----------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------
-- e.g. local kiExampleVariableMax = 999
 
-----------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------
function MailAutoText:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self 

    -- initialize variables here

    return o
end

function MailAutoText:Init()
	local bHasConfigureFunction = false
	local strConfigureButtonText = ""
	local tDependencies = {
		-- "UnitOrPackageName",
	}
    Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)
end
 

-----------------------------------------------------------------------------------------------
-- MailAutoText OnLoad
-----------------------------------------------------------------------------------------------
function MailAutoText:OnLoad()
    -- load our form file
	self.xmlDoc = XmlDoc.CreateFromFile("MailAutoText.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
end

-----------------------------------------------------------------------------------------------
-- MailAutoText OnDocLoaded
-----------------------------------------------------------------------------------------------
function MailAutoText:OnDocLoaded()

	if self.xmlDoc ~= nil and self.xmlDoc:IsLoaded() then
	    self.wndMain = Apollo.LoadForm(self.xmlDoc, "MailAutoTextForm", nil, self)
		if self.wndMain == nil then
			Apollo.AddAddonErrorText(self, "Could not load the main window for some reason.")
			return
		end
		
	    self.wndMain:Show(false, true)

		-- if the xmlDoc is no longer needed, you should set it to nil
		-- self.xmlDoc = nil
		
		-- Register handlers for events, slash commands and timer, etc.
		-- e.g. Apollo.RegisterEventHandler("KeyDown", "OnKeyDown", self)


		-- Do additional Addon initialization here
	end
end

-----------------------------------------------------------------------------------------------
-- MailAutoText Functions
-----------------------------------------------------------------------------------------------
-- Define general functions here


-----------------------------------------------------------------------------------------------
-- MailAutoTextForm Functions
-----------------------------------------------------------------------------------------------
-- when the OK button is clicked
function MailAutoText:OnOK()
	self.wndMain:Close() -- hide the window
end

-- when the Cancel button is clicked
function MailAutoText:OnCancel()
	self.wndMain:Close() -- hide the window
end


-----------------------------------------------------------------------------------------------
-- MailAutoText Instance
-----------------------------------------------------------------------------------------------
local MailAutoTextInst = MailAutoText:new()
MailAutoTextInst:Init()
