-- Initialization bridge for MSBT when its files are loaded by zDNumbers.toc.
-- Guards make initialization independent of ADDON_LOADED frame ordering.

zDNumbers = zDNumbers or {}

local function NormalizeCurrentProfile()
  if type(MikSBT_Save) ~= "table" or type(MikSBT_Save.Profiles) ~= "table" then return end

  local profiles = MikSBT_Save.Profiles
  if not next(profiles) then
    MikSBT_Save = nil
    return
  end

  if not MikSBT_Save.CurrentProfile or not profiles[MikSBT_Save.CurrentProfile] then
    if profiles.Default then
      MikSBT_Save.CurrentProfile = "Default"
    else
      for profileName in pairs(profiles) do
        MikSBT_Save.CurrentProfile = profileName
        break
      end
    end
  end
end

function zDNumbers.EnsureEmbeddedMSBT()
  if not MikSBT then return end

  if not MikSBT.EmbeddedRuntimeInitialized then
    NormalizeCurrentProfile()
    MikSBT.RegisterEvents()
    MikSBT.Init()
    MikSBT.EmbeddedRuntimeInitialized = true
  end

  if not MikSBT.CurrentProfile and MikSBT_Save and MikSBT_Save.Profiles then
    NormalizeCurrentProfile()
    MikSBT.CurrentProfile = MikSBT_Save.Profiles[MikSBT_Save.CurrentProfile]
  end

  if MikSBT.CurrentProfile and MikSBTOpt and MikSBTOpt.Init and not MikSBTOpt.EmbeddedInitialized then
    MikSBTOpt.Init()
    MikSBTOpt.EmbeddedInitialized = true
  end
end

-- The MSBT settings editor (about 330 KB of code and 170 frames) lives in the
-- load-on-demand z_DNumbers_Options addon and loads the first time it opens.
function zDNumbers.LoadMSBTOptions()
  if not MSBTFrameOptions and LoadAddOn then
    local loaded, reason = LoadAddOn("z_DNumbers_Options")
    if not loaded and DEFAULT_CHAT_FRAME then
      DEFAULT_CHAT_FRAME:AddMessage("|cff7dff33z|rDNumbers: MSBT settings could not load (" .. tostring(reason) .. "). Enable z_DNumbers_Options in the AddOns list.")
    end
  end
  zDNumbers.EnsureEmbeddedMSBT()
  return MSBTFrameOptions
end
