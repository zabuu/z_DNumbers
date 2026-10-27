-- Optional transport adapter. zDNumbers/MSBT retain all text/frame ownership.
local Z=zDNumbers
Z.PairedDamageVersion=1

function Z.SetPairedDamageSource(provider)
  Z.pairedDamageSource=type(provider)=="function" and provider or nil
end

function Z.SetOutgoingDamageObserver(observer,enabled)
  if MikSBT then
    MikSBT.OutgoingDamageObserver=type(observer)=="function" and observer or nil
    MikSBT.OutgoingDamageObserverActive=type(enabled)=="function" and enabled or nil
  end
end

function Z.ShowPairedDamage(data,sourceGUID)
  if not MikSBT or type(Z.pairedDamageSource)~="function" or type(MikSBT.SubmitPairedPetDamage)~="function" then return false end
  local ok,current=pcall(Z.pairedDamageSource,sourceGUID)
  if not ok or not current or current~=sourceGUID then return false end
  return MikSBT.SubmitPairedPetDamage(data,sourceGUID)
end
