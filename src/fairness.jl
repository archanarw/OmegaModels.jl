using Revise
using Omega

"Population model"
function popModel_(ω, sex)
    # sex = step_dis_(ω, [(0,1,0.3307), (1,2,0.6693)])
    # sex = Omega.categorical(ω, [0.3307, 0.6693])
    # sex -= 0.5
    if sex < 1
        capital_gain = normal(ω[@id], 568.4105, sqrt(24248365.5428))
        if capital_gain < 7298.0000
            age = normal(ω[@id], 38.4208, sqrt(184.9151))
            education_num = normal(ω[@id], 10.0827, sqrt(6.5096))
            capital_loss = normal(ω[@id], 86.5949, sqrt(157731.9553))
        else
            age = normal(ω[@id], 38.8125, sqrt(193.4918))
            education_num = normal(ω[@id], 10.1041, sqrt(6.1522))
            capital_loss = normal(ω[@id], 117.8083, sqrt(252612.0300))
        end
    else
        capital_gain = normal(ω[@id], 1329.3700, sqrt(69327473.1006))
        if capital_gain < 5178.0000
            age = normal(ω[@id], 38.6361, sqrt(187.2435))
            education_num = normal(ω[@id], 10.0817, sqrt(6.4841))
            capital_loss = normal(ω[@id], 87.0152, sqrt(161032.4157))
        else
            age = normal(ω[@id], 38.2668, sqrt(187.2747))
            education_num = normal(ω[@id], 10.0974, sqrt(7.1793))
            capital_loss = normal(ω[@id], 101.7672, sqrt(189798.1926))
        end
    end

    if (education_num > age)
        age = education_num
    end
    # sensitiveAttribute(sex < 1)
    # qualified(age > 18)
    return (sex, age, capital_gain, capital_loss)
end

function popModel(ω)
    sex = Omega.categorical(ω[@id], [0.3307, 0.6693])
    sex -= 0.5
    return popModel_(ω,sex)
end

function maleModel(ω)
    return popModel_(ω,1.5)
end

function femaleModel(ω)
    return popModel_(ω,0.5)
end

# Zen: FIXME These are globals

W = randarray([normal(0.0006, 1.0), normal(-5.7363, 1.0), normal(-0.0002, 1.0)])
b = normal(1.0003, 1.0)
δ = normal(-0.0003, 1.0)

"Classifier: does person have same classification?"
function F(ω, sex, age, capital_gain, capital_loss)
    N_age = (age - 17.0) / 62.0
    N_capital_gain = (capital_gain - 0.0) / 22040.0
    N_capital_loss = (capital_loss - 0.0) / 1258.0
    # t = W[1] * N_age + W[2] * N_capital_gain + W[3] * N_capital_loss + b
    t = W[1](ω) * N_age + W[2](ω) * N_capital_gain + W[3](ω) * N_capital_loss + b(ω)
    if sex > 1.0
        t = t + δ(ω)
        # t = t + δ
    end
    return t < 0
    # fairnessTarget(t < 0)
end

isrich(ω) = F(ω, popModel(ω)[1], popModel(ω)[2], popModel(ω)[3], popModel(ω)[4])
gender(ω) = popModel(ω)[1]
age(ω) = popModel(ω)[2]

isrich_var = ciid(isrich, T = Bool)
gender_var = ciid(gender, T = Float64)
age_var = ciid(age, T = Float64)

# Three versions of fairness

"Demographic fairness property
m_isrich and f_isrich by construction version"
function groupfair(nsamplesmean = 10000, thresh = 0.85)
    m_attrs = ciid(maleModel)
    f_attrs = ciid(femaleModel)
    m_isrich_(ω) = F(ω, m_attrs(ω)...)
    f_isrich_(ω) = F(ω, f_attrs(ω)...)
    
    m_isrich = ciid(m_isrich_; T = Bool)
    f_isrich = ciid(f_isrich_; T = Bool) # FIX
    ratio = prob(f_isrich ∥ (W, b, δ), nsamplesmean) / prob(m_isrich ∥ (W, b, δ), nsamplesmean)
    fairness = ratio > thresh
end

"Version 2, second fastest, the fairness property is the strong version (equal opportunity).
The conditions are party by construction"
function equalopportunity1(nsamplesmean = 10000, thresh = 0.85)
    m_attrs = ciid(maleModel)
    f_attrs = ciid(femaleModel)
    m_isrich_(ω) = F(ω, m_attrs(ω)...)
    f_isrich_(ω) = F(ω, f_attrs(ω)...)

    m_agevar = m_attrs[2]
    f_agevar = f_attrs[2]
    
    m_isrich = ciid(m_isrich_; T = Bool)
    f_isrich = ciid(f_isrich_; T = Bool) # FIX
    ratio = prob(f_isrich ∥ (W, b, δ), nsamplesmean) / prob(m_isrich ∥ (W, b, δ), nsamplesmean)
    fairness = (ratio > thresh) & (m_agevar > 18) & (f_agevar > 18)
end

"Version 3, slowest, equal opportunity"
function  equalopportunity2()
    isrich_var_ = isrich_var ∥ (W,b,δ)

    isrich_var_p = mean(isrich_var_)

    m_prob = rand(isrich_var_p, (gender_var > 1) & (age_var > 18))
    f_prob = rand(isrich_var_p, gender_var < 1 & age_var > 18)

    fairness =  f_prob / m_prob > 0.85
end

"Conditional parameters"
function main(faircriteria = groupfair, n = 1)
    fairness = faircriteria()
    samples = rand((W, b, δ), fairness, ; n = 10)

    println("Samples: $(samples)")
end

main(equalopportunity1)