using Omega
using Distributions
using Test

# colors of balls
k = 5       
n_obs = 50
weights = Omega.dirichlet([1.0 for i = 1:k])

function y_(ω)
  [Omega.categorical(ω[@id][i], weights(ω[@id][i])) for i = 1:n_obs]
end

y = ciid(y_, Vector{Float64})

function ccount(samples, k)
  counts = zeros(k)
  for s in samples
    counts[s] += 1
  end
  counts
end

Omega.lift(:ccount, 2)

# Observations
function ball()
  y_obs = zeros(k)
  y_obs[2] = n_obs

  c = ccount(y, k)
  samples = rand(weights, c == y_obs)
  meds = [median(map(x->x[i], samples)) for i = 1:k]
  @test findmax(meds)[2] == 2
end