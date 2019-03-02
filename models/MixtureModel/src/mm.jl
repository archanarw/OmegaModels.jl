using Omega
using Distributions


k = 3     # Number of components
nobs = 10 # Number of observations
y_obs = vcat((randn(div(nobs, 2)) + 50)-10, (randn(div(nobs,2)))) # Data

μ_data = mean(y_obs)  # Data dependent mean prior
σ²data = var(y_obs)   # Variance prior

λ = normal(μ_data, sqrt(σ²data))

r = Γ(1.0, 1/σ²data)

μ =  [normal(λ, 1/r) for i = 1:k]

# Inference goal: conditional posterior distribution of means given data
β = inversegamma(1.0, 1.0)
w = Γ(1.0, σ²data)
s = [Γ(β, 1/w) for i = 1:k]

α = Γ(1.0, 1.0)
a_k = α / k

π = dirichlet([a_k for i = 1:k])

"Finite Mixture Model"
mm(π, μ, s) = sum([π[i] * normal(μ[i], s[i]) for i = 1:k])

y = [mm(π, μ, s) for _ in y_obs]

y_ = Omega.randarray(y)

# Inference goal: conditional distribution of means given data
samples = rand(Omega.randarray(μ), y_ == y_obs, MI, n=10000)
@show [median(map(x->x[i], samples)) for i=1:k]


samples_π = rand(Omega.randarray(π), y_ == y_obs, SSMH, n=10000)
@show [median(map(x->x[i], samples_π)) for i=1:k]