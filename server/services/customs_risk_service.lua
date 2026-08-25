PortOps=PortOps or {}; PortOps.Services=PortOps.Services or {}; local S={}; S.__index=S
function S.new(config) return setmetatable({config=config or {randomSampleRate=0.05}},S) end
function S:assess(input)
    input=input or {}; local score=0; local reasons={}
    if input.origin and self.config.highRiskOrigins and self.config.highRiskOrigins[input.origin] then score=score+35; reasons[#reasons+1]='HIGH_RISK_ORIGIN' end
    if input.cargo and (input.cargo.hazardousClass or input.cargo.reefer) then score=score+20; reasons[#reasons+1]='CARGO_ANOMALY' end
    if input.manifestAnomaly then score=score+25; reasons[#reasons+1]='MANIFEST_ANOMALY' end
    if input.sealAnomaly then score=score+25; reasons[#reasons+1]='SEAL_ANOMALY' end
    local sample = input.randomSample == true or (input.sampleValue and input.sampleValue < (self.config.randomSampleRate or 0))
    if sample then score=score+15; reasons[#reasons+1]='RANDOM_SAMPLE' end
    return {score=math.min(score,100), reasons=reasons, sampled=sample}
end
PortOps.Services.CustomsRisk=S; return S
