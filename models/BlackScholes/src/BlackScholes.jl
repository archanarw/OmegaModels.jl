module BlackScholes

using Omega
using Omega.Prim: samplemeanᵣ
using Plots
using Lens
using Statistics
using Dates

export bsmmc, simrv, diff_σ, sampleprior

# TODO
# Be able to use many observations
# Split plot into prior, one observation, many

# Some visualization functions
const FIGHOME = "figures"
plothist(samples) = histogram(samples)
plotseries(samples) = plot(samples)

# This model simulates the Black-Scholes differential equations

"""
Black-Scholes monte-carlo stochastic differential equation
T: time to maturity (in years)
r: riskfree rate of interest
σ: volatility
nsteps: number of time steps
S: initial stock price 
"""
function bsmmc(ω, σ, T = 0.5, nsteps = 16, S = 202.73, r = 0.025)
  Δt = T/nsteps
  # series = [S]
  for i = 1:nsteps
    # z = normal(ω, 0, 1)
    z = randn(ω)
    S = S * exp((r - 0.5σ^2) * Δt + (σ * sqrt(Δt) * z))
    # push!(series, S)
  end
  S
  # series
end

# Apple data
strikedate = Date(2019, 9, 20)
today_ = Date(2019, 7, 5)
const tradingdays = 252             # Number of trading days per year
T = (strikedate - today_).value / 365
nsteps = Int(floor(T * tradingdays))
AAPLS = 204.23
data = [(K = 205.00,	c = 8.66, σ = 0.2340, T = T),
(K = 210.00,	c = 6.20, σ = 0.2287, T = T),
(K = 215.00,	c = 4.42, σ = 0.2250, T = T),
(K = 220.00,	c = 2.91, σ = 0.2200, T = T)]

      
o1 = data[1]  
# We use priors over \sigma, which represents the volatility of the model
const σ = uniform(0.0, 1.0)
const r = 0.02                     # risk-free

# Now we create random variables for the time series, and the value of the stock at time T
const simrv = ciid(bsmmc, σ, o1.T, nsteps, AAPLS, r)
const lastsim =  lift(last)(simrv)

# Let's draw some prior samples from the model
sampleprior() = rand(simrv, 10)
#   nb fig =  plot(samplesprior(); xlabel = "time", ylabel = "S", legend = false)
# savefig(fig, joinpath(FIGHOME, "bsseries1.pdf"))

# Single obseration
const diff = lift(max)(simrv - o1.K, 0)
const diff_σ =  rid(diff, σ)  
const diffexp = samplemeanᵣ(diff_σ, 1000000)
const C_discount = diffexp * exp(-r*o1.T)

const c1 = C_discount ==ₛ o1.c 
run(; n = 1000, alg = HMCFAST, kwargs...) =
  @leval HMCFASTLoop => default_cbs(n) rand(σ, C_discount ==ₛ o1.c, n; alg = alg, kwargs...)

runsilent(; n = 1000, alg = SSMH, kwargs...) =
  rand(σ, diffexp ==ₛ o1.c, n; alg = alg, kwargs...)  


"Histogram of prior vs posterior samples over σ"
function volatilityplot()
  postsamples = run(; n = 1000)
  priorsamples = rand(σ, 1000)
  histogram([priorsamples, postsamples], fillalpha = 0.5, normalize = true, label = ["Prior", "Posterior"])
end
# savefig(fig, joinpath(FIGHOME, "bshist1.pdf"))

# Multiple observations
function diffmulti_(ω, ks)
  ls = simrv(ω)
  [max(ls - k, 0) for k in ks]
end

# disp(x; msg = "") = (println(msg, "value : ", x); x)

const selected = [data[1], data[end-1]]
const nobs = length(selected)
const ks = [o.K for o in selected] 
const cs = [o.c * exp(r*o.T) for o in selected]
const diffmulti = ciid(diffmulti_, ks)
const diffmulti_σ = rid(diffmulti, σ)
const diffmultiexp =  samplemeanᵣ(diffmulti_σ, 2)
# const diffmultiexp = lift(disp)(diffmultiexp_)
const norms = ciid(ω -> [normal(ω, 0.0, 1.0) for i = 1:nobs])
const diffmultiexpnoise = diffmultiexp + norms
# normal(0.0, 0.01, (nobs,))

function condition_(ω)
  diffmultiexpnoise(ω) ==ₛ cs
end

condition2 = ciid(condition_)

# const condition = (samplemeanᵣ(diffmulti_σ, 10000) + normal(0, 0.01, (nobs,)))  ==ₛ cs
runmulti(; n = 1000, alg = SSMH, kwargs...) =
  @leval SSMHLoop => default_cbs(n) rand(σ, condition2, n; alg = alg, kwargs...)

runmultisilent(; n = 1000, alg = Replica, kwargs...) =
  rand(σ, diffmultiexpnoise .==ₛ cs, n; alg = alg, kwargs...)

# runmulti() = @leval SSMHLoop => default_cbs(1000) rand(σ, diffmultiexpnoise ==ₛ cs, 1000; alg = Replica)

end # module