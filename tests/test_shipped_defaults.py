"""Fresh accounts/characters inherit Zabbu's preset; existing saves stay intact."""
from pathlib import Path
from lupa.lua51 import LuaRuntime, lua_type

root = Path(__file__).resolve().parents[1]
localization = (root / "MikScrollingBattleText/localization.lua").read_text(encoding="utf-8-sig")
# Vanilla allows tables as generic-for iterators; Lua 5.1 needs pairs in this
# pre-existing font-path loop. Adapt only the test harness, not the shipped code.
localization = localization.replace("for _, fontInfo in MikSBT.AVAILABLE_FONTS do", "for _, fontInfo in pairs(MikSBT.AVAILABLE_FONTS) do")
preset = (root / "default_profile.lua").read_text(encoding="utf-8-sig")

def runtime(locale="enUS"):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().testLocale = locale
    lua.execute('''
GetLocale=function() return testLocale end
L=setmetatable({},{__index=function(t,k) return k end})
AceLibrary=function() return setmetatable({new=function() return L end},{__index=function(t,k) return k end}) end
setmetatable(_G,{__index=function(t,k)
 if string.find(k,"^[A-Z_][A-Z0-9_]*$") then return string.upper(string.sub(k,1,1))..string.lower(string.sub(k,2)) end
end})
''')
    lua.execute(preset)
    lua.execute(localization)
    return lua

lua = runtime()
source = (root / "MikScrollingBattleText/MikScrollingBattleText.lua").read_text(encoding="utf-8-sig")
lua.execute('''
SlashCmdList={}; scrollAreas={}
function deepCopy(t)
 local result={}; for k,v in pairs(t) do result[k]=type(v)=="table" and deepCopy(v) or v end; return result
end
MikSBT.CopyTable=deepCopy
MikSBT.ProfileExists=function(n) return MikSBT_Save and MikSBT_Save.Profiles[n]~=nil end
MikSBT.UpdateProfiles=function() end
MikSBT.SetupAnimationScrollAreas=function() end
MikSBT.RepositionAnimationFrames=function() end
MikSBT.RegisterTriggers=function() end
MikSBT.SetOptionUserDisabled=function() end
''')
lua.execute(source[source.index("function MikSBT.ResetProfile("):source.index("function MikSBT.SelectProfile(")])
lua.execute(source[source.index("function MikSBT.Init("):source.index("function MikSBT.SetupAnimationScrollAreas(")])
lua.execute('''
MikSBT.Init()
local p=MikSBT.CurrentProfile
assert(p.TextSpeed==65 and p.FadeDelay==3)
assert(p.MasterFontSettings.Normal.FontIndex==26 and p.MasterFontSettings.Normal.FontSize==24)
assert(p.MasterFontSettings.Crit.FontSize==34)
assert(p.DisplaySettings.Outgoing.FontSettings.Normal.FontSize==16)
assert(p.DisplaySettings.Outgoing.FontSettings.Crit.FontSize==28)
assert(p.Triggers.MSBT_TRIGGER_CUSTOM1.EventSettings.Message=="Lacerate")
assert(not MikSBT_Save.zNameplatesProfileImport) -- No account import metadata.
p.TextSpeed=99; p.MasterFontSettings.Normal.FontSize=33
MikSBT.Init(); assert(MikSBT.CurrentProfile==p and p.TextSpeed==99)
assert(MikSBT.DEFAULT_CONFIG.TextSpeed==65 and MikSBT.DEFAULT_CONFIG.MasterFontSettings.Normal.FontSize==24)
MikSBT_Save.Profiles.Second={}; MikSBT.ResetProfile("Second")
assert(MikSBT_Save.Profiles.Second.MasterFontSettings.Normal.FontSize==24)
-- Existing alternate profiles, selection, false toggles and unknown fields
-- survive initialization; neither the preset nor Init resets them.
custom={TextSpeed=37,MasterFontSettings={Normal={FontSize=9}},customValue="keep"}
existing={Profiles={Mine=custom,Other={customValue="also keep"}},CurrentProfile="Mine",UserDisabled=true,importMarker="keep"}
MikSBT_Save=existing; MikSBT.Init()
assert(MikSBT_Save==existing and MikSBT.CurrentProfile==custom)
assert(custom.TextSpeed==37 and custom.MasterFontSettings.Normal.FontSize==9 and custom.customValue=="keep")
assert(existing.Profiles.Other.customValue=="also keep" and existing.UserDisabled and existing.importMarker=="keep")
''')

attachment = (root / "zDNumbers.lua").read_text(encoding="utf-8-sig")
lua.execute(attachment[:attachment.index("local TEXT_SLOTS")] + '\nmerge=MergeDefaults')
lua.execute('''
fresh={}; merge(fresh)
assert(fresh.icon_opacity=="55" and fresh.perspective_tilt=="30" and fresh.height=="142" and fresh.fade==".65")
assert(fresh.width=="120" and fresh.x=="0" and fresh.y=="8" and fresh.align=="CENTER")
assert(fresh.split_pet=="0" and not fresh.pet_side)
assert(not fresh.native_cards and not fresh.zNameplatesImport)
established={enabled="0",icons="0",height="71",fade=".9",native_cards="old",customValue="keep",zNameplatesImport="1",split_pet="1",pet_side="LEFT"}
merge(established)
assert(established.enabled=="0" and established.icons=="0" and established.height=="71" and established.fade==".9")
assert(established.customValue=="keep" and established.native_cards=="old" and established.zNameplatesImport=="1")
assert(established.split_pet=="1" and established.pet_side=="LEFT")
''')

# Locale-specific font lists must not get out-of-range saved English indices.
russian = runtime("ruRU")
russian.execute('''
local p=MikSBT.DEFAULT_CONFIG
assert(p.MasterFontSettings.Normal.FontIndex==3 and p.MasterFontSettings.Crit.FontIndex==3)
assert(p.BlizzardFontSettings.Normal.FontIndex==3)
assert(MikSBT.AVAILABLE_FONTS[3].Name=="Friz")
''')

def plain(value):
    if lua_type(value) == "table":
        return {key: plain(item) for key, item in value.items()}
    return value

# When the source saves are available locally, compare every profile leaf and
# supported attachment setting to the captured character, not just a sample.
account = Path("G:/Games/OctoWoW/WTF/Account/ZABUU/SavedVariables/z_DNumbers.lua")
character = Path("G:/Games/OctoWoW/WTF/Account/ZABUU/N'Zoth/Zabbu/SavedVariables/z_DNumbers.lua")
if account.exists() and character.exists():
    saved = LuaRuntime(unpack_returned_tuples=True)
    saved.execute(account.read_text(encoding="utf-8-sig"))
    save = saved.globals().MikSBT_Save
    assert plain(runtime().globals().MikSBT.DEFAULT_CONFIG) == plain(save.Profiles[save.CurrentProfile])
    saved.execute(character.read_text(encoding="utf-8-sig"))
    for key, value in lua.globals().zDNumbers.defaults.items():
        if key not in {"split_pet", "pet_side"}:  # New opt-in controls were not in the captured preset.
            assert value == saved.globals().zDNumbersDB[key], key

toc = (root / "z_DNumbers.toc").read_text(encoding="utf-8-sig")
assert toc.index("default_profile.lua") < toc.index("MikScrollingBattleText\\localization.lua")
assert (root / "MikScrollingBattleText/Fonts/Expressway.ttf").is_file()
print("Zabbu defaults: exact saved-profile match, fresh initialization, existing-save preservation, isolated copies, and locale-safe fonts passed.")
