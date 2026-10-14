-- Shipped MSBT preferences captured from Zabbu's active profile, 2026-10-13.
-- Apply only to the factory template, never to saved or active user profiles.
zDNumbers = zDNumbers or {}
local Z = zDNumbers
Z.msbtDefaultOverrides = {
  TextSpeed = 65, FadeDelay = 3,
  MasterFontSettings = {
    Normal = {FontIndex=26, OutlineIndex=1, FontSize=24},
    Crit = {FontIndex=26, OutlineIndex=2, FontSize=34},
  },
  DisplaySettings = {
    Incoming = {FrameOffsets={x=-1,y=-190}, ScrollDirection=2, ScrollHeight=158,
      FontSettings={Normal={FontSize=14}, Crit={FontSize=28}}},
    Outgoing = {FrameOffsets={x=127,y=-93}, ScrollHeight=428,
      FontSettings={Normal={FontSize=16}, Crit={FontSize=28}}},
    Notification = {FrameOffsets={x=-1,y=-207}, ScrollDirection=2, ScrollHeight=178,
      FontSettings={Normal={FontSize=14}, Crit={FontSize=20}, TextAlignIndex=1}},
    PetIncoming = {FrameOffsets={x=-152,y=-222}, ScrollDirection=2, ScrollHeight=100,
      FontSettings={Normal={FontSize=12}, Crit={FontSize=20}, TextAlignIndex=2}},
    PetOutgoing = {FrameOffsets={x=-277,y=-188}, ScrollDirection=1, ScrollHeight=100,
      FontSettings={Normal={FontSize=12}, Crit={FontSize=22}, TextAlignIndex=2}},
  },
  EventSettings = {
    MSBT_EVENTTYPE_INCOMING_MISS = {FontSettings={Color={r=.4274509803921568,g=.4274509803921568,b=.8313725490196078}}},
    MSBT_EVENTTYPE_INCOMING_BLOCK = {FontSettings={Color={r=.392156862745098,g=.3607843137254902}}},
    MSBT_EVENTTYPE_INCOMING_PARRY = {FontSettings={Color={r=.4392156862745098,g=.4313725490196079,b=.8235294117647058}}},
    MSBT_EVENTTYPE_INCOMING_DODGE = {FontSettings={Color={r=.4352941176470588,g=.4313725490196079,b=.8235294117647058}}},
    MSBT_EVENTTYPE_OUTGOING_BLOCK = {FontSettings={Color={r=.4549019607843137,g=.3882352941176471}}},
    MSBT_EVENTTYPE_OUTGOING_PARRY = {FontSettings={Color={r=.5098039215686274,g=.5647058823529412}}},
    MSBT_EVENTTYPE_OUTGOING_DODGE = {FontSettings={Color={r=.7450980392156863,g=.7568627450980392,b=.5254901960784314}}},
    MSBT_EVENTTYPE_OUTGOING_MISS = {FontSettings={Color={r=.4666666666666667,g=.4431372549019608,b=.4666666666666667}}},
    MSBT_EVENTTYPE_OUTGOING_PET_DAMAGE = {Message="%a",FontSettings={Color={g=.7568627450980392,b=.4901960784313725}}},
    MSBT_EVENTTYPE_OUTGOING_PET_DODGE = {Message="Dodge!",FontSettings={Color={g=.8588235294117647,b=.7098039215686275}}},
    MSBT_EVENTTYPE_OUTGOING_PET_PARRY = {Message="Parry!",FontSettings={Color={g=.8392156862745098,b=.615686274509804}}},
    MSBT_EVENTTYPE_OUTGOING_PET_MISS = {Message="Miss!",FontSettings={Color={g=.8705882352941177,b=.6666666666666666}}},
    MSBT_EVENTTYPE_OUTGOING_PET_BLOCK = {Message="Block!",FontSettings={Color={g=.8745098039215686,b=.6470588235294118}}},
    MSBT_EVENTTYPE_OUTGOING_PET_EVADE = {Message="Evade!"},
    MSBT_EVENTTYPE_OUTGOING_PET_IMMUNE = {Message="Immune!"},
    MSBT_EVENTTYPE_OUTGOING_PET_ABSORB = {Message="Absorb!"},
    MSBT_EVENTTYPE_OUTGOING_SPELL_EVADE = {Message="Evade!"},
    MSBT_EVENTTYPE_OUTGOING_SPELL_IMMUNE = {Message=" Immune!"},
    MSBT_EVENTTYPE_OUTGOING_SPELL_REFLECT = {Message="Reflect!"},
    MSBT_EVENTTYPE_OUTGOING_SPELL_ABSORB = {Message="Absorb!"},
    MSBT_EVENTTYPE_OUTGOING_PET_SPELL_DAMAGE = {Message="%a"},
    MSBT_EVENTTYPE_OUTGOING_PET_SPELL_DODGE = {Message="Dodge!"},
    MSBT_EVENTTYPE_OUTGOING_PET_SPELL_PARRY = {Message="Parry!"},
    MSBT_EVENTTYPE_OUTGOING_PET_SPELL_MISS = {Message="Miss!"},
    MSBT_EVENTTYPE_OUTGOING_PET_SPELL_BLOCK = {Message="Block!"},
    MSBT_EVENTTYPE_OUTGOING_PET_SPELL_EVADE = {Message="Evade!"},
    MSBT_EVENTTYPE_OUTGOING_PET_SPELL_IMMUNE = {Message="Immune!"},
    MSBT_EVENTTYPE_OUTGOING_PET_SPELL_ABSORB = {Message="Absorb!"},
    MSBT_EVENTTYPE_OUTGOING_PET_SPELL_RESIST = {Message="Resist!"},
    MSBT_EVENTTYPE_INCOMING_PET_DAMAGE = {Message="-%a"},
    MSBT_EVENTTYPE_INCOMING_PET_DODGE = {Message="Dodge!"},
    MSBT_EVENTTYPE_INCOMING_PET_PARRY = {Message="Parry!"},
    MSBT_EVENTTYPE_INCOMING_PET_MISS = {Message="Miss!"},
    MSBT_EVENTTYPE_INCOMING_PET_BLOCK = {Message="Block!"},
    MSBT_EVENTTYPE_INCOMING_PET_EVADE = {Message="Evade!"},
    MSBT_EVENTTYPE_INCOMING_PET_IMMUNE = {Message="Immune!"},
    MSBT_EVENTTYPE_INCOMING_PET_ABSORB = {Message="Absorb!"},
    MSBT_EVENTTYPE_INCOMING_PET_SPELL_DAMAGE = {Message="-%a"},
    MSBT_EVENTTYPE_INCOMING_PET_SPELL_DOT = {Message="-%a"},
    MSBT_EVENTTYPE_INCOMING_PET_SPELL_DODGE = {Message="Dodge!"},
    MSBT_EVENTTYPE_INCOMING_PET_SPELL_PARRY = {Message="Parry!"},
    MSBT_EVENTTYPE_INCOMING_PET_SPELL_MISS = {Message="Miss!"},
    MSBT_EVENTTYPE_INCOMING_PET_SPELL_BLOCK = {Message="Block!"},
    MSBT_EVENTTYPE_INCOMING_PET_SPELL_EVADE = {Message="(%s) Evade!"},
    MSBT_EVENTTYPE_INCOMING_PET_SPELL_IMMUNE = {Message="(%s) Immune!"},
    MSBT_EVENTTYPE_INCOMING_PET_SPELL_ABSORB = {Message="(%s) Absorb!"},
    MSBT_EVENTTYPE_INCOMING_PET_SPELL_REFLECT = {Message="(%s) Reflect!"},
    MSBT_EVENTTYPE_INCOMING_PET_SPELL_RESIST = {Message="Resist!"},
    MSBT_EVENTTYPE_INCOMING_PET_HEAL = {Message="+%a (%n)"},
    MSBT_EVENTTYPE_INCOMING_PET_HOT = {Message="+%a (%n)"},
    MSBT_EVENTTYPE_NOTIFICATION_REP_GAIN = {Message="+%a Reputation (%s)"},
    MSBT_EVENTTYPE_NOTIFICATION_REP_LOSS = {Message="-%a Reputation (%s)"},
  },
  Triggers = {
    MSBT_TRIGGER_RIPOSTE = {EventSettings={Show=false}},
    MSBT_TRIGGER_CLEARCAST = {EventSettings={Show=false},TriggerSettings={SearchPatterns={"You gain Clearcasting."}}},
    MSBT_TRIGGER_NIGHTFALL = {EventSettings={Show=false},TriggerSettings={SearchPatterns={"You gain Shadow Trance."}}},
    MSBT_TRIGGER_OVERPOWER = {EventSettings={Show=false}},
    MSBT_TRIGGER_COUNTER_ATTACK = {EventSettings={Show=false}},
    MSBT_TRIGGER_HAMMER_OF_WRATH = {EventSettings={Show=false}},
    MSBT_TRIGGER_MONGOOSE_BITE = {EventSettings={Show=false}},
    MSBT_TRIGGER_WINDFURY = {TriggerSettings={SearchPatterns={"You gain Windfury Totem."}}},
    MSBT_TRIGGER_CUSTOM1 = {
      TriggerSettings={Threshold=40,TriggerType=1},
      EventSettings={IsSticky=false,Message="Lacerate",Show=true,
        FontSettings={Normal={FontSize=26,FontIndex=0,OutlineIndex=0},Color={r=1,g=.502,b=.502}}},
    },
  },
}

local function Overlay(target, values)
  for key, value in pairs(values) do
    if type(value)=="table" then
      if type(target[key])~="table" then target[key]={} end
      Overlay(target[key],value)
    else target[key]=value end
  end
end

function Z.ApplyEmbeddedMSBTDefaults(template, fonts)
  if type(template)~="table" then return end
  Overlay(template,Z.msbtDefaultOverrides)
  -- Saved indices refer to the English font list. Resolve named fonts for
  -- other locales too; Russian's smaller list must not receive index 26.
  if fonts then
    local expressway, friz
    for index, font in pairs(fonts) do
      if font.Name=="Expressway" then expressway=index end
      if font.Name=="Friz" then friz=index end
    end
    local function ResolveFonts(table)
      for key, value in pairs(table) do
        if type(value)=="table" then ResolveFonts(value)
        elseif key=="FontIndex" and value==26 then table[key]=expressway or friz or 1
        elseif key=="FontIndex" and value==6 then table[key]=friz or 1 end
      end
    end
    ResolveFonts(template)
  end
end
