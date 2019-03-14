module WolvesAndRabbits
using Omega
using Flux, DiffEqFlux, DifferentialEquations, Plots, DiffEqNoiseProcess, StatsBase
PLOTSPATH = joinpath(@__DIR__, "..", "figures")

# Plot results
function plotwr(data; kwargs)
  plot(data)
end

# Lotka Volterra represents dynamics of wolves and Rabbit Populations over time
function lotka_volterra(du, u, p, t)
  x, y = u
  α, β, δ, γ = p
  du[1] = dx = α*x - β*x*y
  du[2] = dy = -δ*y + γ*x*y
end

# Initial conditions
# u0 = constant([1.0, 1.0])
u0 = uniform(0.5, 1.5, (2,))

# Time now
t_now = 20.0

# Iterate over 10 time steps
tspan = constant((0.0, t_now))

# Parameters of the simulation
# p = constant([1.5,1.0,3.0,1.0])
# p = uniform(0.5, 4.0, (4,))
p = ciid(ω -> [uniform(ω, 1.3, 1.7), uniform(ω, 0.7, 1.3), uniform(ω, 2.7, 3.3), uniform(ω, 0.7, 1.3)])

prob = ciid(ω -> ODEProblem(lotka_volterra, u0(ω), tspan(ω), p(ω)))
sol = lift(solve)(prob)

# Plot time series from prior
function plot1()
  plot(rand(sol))
end

# Counter-factual model #
function gencf(; affect! = integrator -> integrator.u[2] /= 2.0,
                 t_int = uniform(tspan[1], tspan[2]/2.0),
                 tspan = tspan)
  condition = ciid(ω -> (u, t, integrator) -> t == t_int(ω))
  cb = DiscreteCallback(condition, affect!)

  # Solution to differential equation with intervention
  sol_int = ciid(ω -> solve(ODEProblem(lotka_volterra, u0(ω), tspan(ω), p(ω)),
                            EM(),
                            callback = DiscreteCallback(condition(ω), affect!),
                            tstops = t_int(ω)))
end

# impulse = uniform(tspan[1], tspan[2]/2.0)
# condition = ciid(ω -> (u, t, integrator) -> t == impulse(ω))
# affect!(integrator) = integrator.u[2] /= 2.0 
# cb = DiscreteCallback(condition, affect!)

# # Solution to differential equation with intervention
# sol_int = ciid(ω -> solve(prob(ω),
#                           EM(),
#                           callback = DiscreteCallback(condition(ω), affect!),
#                           tstops = impulse(ω)))

# Plot a solution from an intervened model 
function sampleint()
  t, sol_int_ = rand((impulse, sol_int))
  println("intervention occured at time $t")
  plot(sol_int_)
end              

# Suppose we observe that there are no rabbits
function totalrabbits_(ω; ndays = 10)
  sol_ = sol(ω)
  n = length(sol_)
  rabbits = [sol_[i][1] for i = (n - ndays):n]
  sum(rabbits)
end

totalrabbits = ciid(totalrabbits_)

# There are no rabbits if integrated mean value is 0
norabbits = totalrabbits ==ₛ 0.0

toomanyrabbits = totalrabbits ==ₛ 5.0

# No Rabbits
function plot_cond()
end

# Effect Of Action #
sol_inc_rab = gencf(; affect! = integrator -> integrator.u[1] += 2.0,
                      t_int = constant(t_now),
                      tspan = constant((0, t_now * 2)))

function plot_effect_action(; n = 100, alg = SSMH, kwargs...)
  samples = rand((toomanyrabbits, sol, sol_inc_rab), toomanyrabbits, n; alg = alg, kwargs...)
  norabbit_, sol_, sol_inc_rab_ = ntranspose(samples)
  p1 = plot(sol_[end], title = "Conditioned Model")
  p2 = plot(sol_inc_rab_[end], title = "Action: Cull Prey")
  display(p1)
  display(p2)
  p1, p2
end

"Affect of increasing the number of predators"
function plot_treatment_action(; n = 10000, alg = SSMH, kwargs...)
  samples = rand((toomanyrabbits, replace(sol, tspan => constant((0, t_now * 2))), sol_inc_rab), toomanyrabbits, n; alg = alg, kwargs...)
  norabbit_, sol_, sol_inc_rab_ = ntranspose(samples)
  a = [sum(extractvals(a, 1, 20.0, 40.0)) for a in sol_[div(n, 2):n]]
  b = [sum(extractvals(a, 1, 20.0, 40.0)) for a in sol_inc_rab_[div(n, 2):n]]
  @show unique(b .- a)
  @show b .- a
  histogram(b .- a, title = "Prey Cull Treatment Effect", yaxis = false)
  # norabbit_, sol_, sol_inc_rab_, a, b
end


# Counter Factual #
t_int = uniform(tspan[1], tspan[2]/2.0)
sol_inc_pred = gencf(; t_int = t_int,
                       affect! = integrator -> integrator.u[2] += 2.0)
using ZenUtils

function maxpop(sol)
  xs = sol[]
end

function plot_inc_pred(; n = 100, alg = SSMH, kwargs...)
  samples = rand((t_int, toomanyrabbits, sol, sol_inc_pred), toomanyrabbits, n; alg = alg, kwargs...)
  t_int_, nor, sol_, sol_inc_pred_ = ntranspose(samples)
  println("intervention occured at time $(t_int_[end])")
  # display(plot(logerr.(nor)))
  # @grab sol_
  # @assert false
  x1, y1 = ntranspose(sol_[end].u)
  x2, y2 = ntranspose(sol_inc_pred_[end].u)
  m = max(maximum(x1), maximum(y1), maximum(x2), maximum(y2))

  p1 = plot(sol_[end], title = "Conditioned Model", ylim = [0, m])
  p2 = plot(sol_inc_pred_[end], title = "Counterfactual: Inc Predators", ylim = [0, m])
  display(p1)
  display(p2)
  p1, p2
end

"Affect of increasing the number of predators"
function plot_treatment(; n = 1000, alg = Replica, kwargs...)
  samples = rand((t_int, toomanyrabbits, sol, sol_inc_pred), toomanyrabbits, n; alg = alg, kwargs...)
  t_int_, nor, sol_, sol_inc_pred_ = ntranspose(samples)
  sol_[end], sol_inc_pred_[end]
  a = [sum(extractvals(a, 1, 0.0, 10.0)) for a in sol_[500:1000]]
  b = [sum(extractvals(a, 1, 0.0, 10.0)) for a in sol_inc_pred_[500:1000]]
  histogram(b .- a, title = "Pred Inc Treatment effect", yaxis = false)
end

"Values of i Population between a and b"
function extractvals(v, id, a, b, ::Type{T} = Float64) where T
  res = Float64[]
  for i = 1:length(v)
    if a < v.t[i] < b
      push!(res, v.u[i][id])
    end
  end
  res
end

# Plot

function makeplots(; save = true, fname = joinpath(PLOTSPATH, "allfigs.pdf"))
  @show fname
  @show @__DIR__
  plts_ea = plot_effect_action()
  # plts = [sample() for i = 1:6]
  plt = plot(plts_ea..., plot_inc_pred()..., plot_treatment_action(), plot_treatment(),
             layout = (3,2),
             legend = false)
  display(plt)
  save && savefig(plt, fname)
end

# THINKING
# 1. We need another cause that will make the rabbit population fall
# 2. Cutting randomly doesn't make much sense
#    Makes more sense to say if we had culled population 
#    at its peak? at some maximum value
# 3. Maybe we need to simulate for longer
# 

# samplecond1() = plot(rand(sol, norabbits, 1000)[end])

# # But we know that at some time before there were rabbits and wolves
# usetobeboth = any(sol[1] .>ₛ 5.0) & any(sol[2] .>ₛ 5.0)

# samplecond2() = plot(rand(sol, norabbits, 1000)[end])

# # Counterfactual if we had made an intervention to cull the number of foxes would there still be no rabbits
# solcf = cond(solcf, norabbits)

# function lotka_volterra_noise(du,u,p,tt)
#   du[1] = 0.1u[1]
#   du[2] = 0.1u[2]
# end
# dt = 1//2^(4)

# μ = 1.0
# σ = 2.0
# W = ciid(ω ->  WienerProcess(0.0,0.0,0.0; rng = ω))
# # W = ciid(ω -> GeometricBrownianMotionProcess(μ,σ,0.0,1.0,1.0; rng = ω))
# prob = ciid(ω -> SDEProblem(lotka_volterra,lotka_volterra_noise,[1.0,1.0],(0.0,10.0), p, noise = W(ω)))
# sol = ciid(ω -> solve(prob(ω),EM()))


# # Verify ODE solution
# sol = solve(prob,Tsit5(), callback=cb, tstops = 4.0)
# plot(sol)

# # Generate data from the ODE
# data_sol = solve(prob,Tsit5(),saveat=0.1)
# A1 = data_sol[1,:] # length 101 vector
# A2 = data_sol[2,:] # length 101 vector
# t = 0:0.1:10.0
# scatter!(t,A1,color=[1],label = "rabbits")
# scatter!(t,A2,color=[2],label = "wolves")

# # Build a neural network that sets the cost as the difference from the
# # generated data and true data

# p = param([4., 1.0, 2.0, 0.4]) # Initial Parameter Vector
# function predict_rd() # Our 1-layer neural network
#   diffeq_rd(p,prob,Tsit5(),saveat=0.1)
# end
# loss_rd() = sum(abs2,predict_rd()-data_sol) # loss function

# # Optimize the parameters so the ODE's solution stays near 1

# data = Iterators.repeated((), 1000)
# opt = ADAM(0.1)
# cb = function () #callback function to observe training
#   #= display(loss_rd()) =#
#   # using `remake` to re-create our `prob` with current parameters `p`
#   scatter(t,A1,color=[1],label = "rabbit data")
#   scatter!(t,A2,color=[2],label = "wolves data")
#   display(plot!(solve(remake(prob,p=Flux.data(p)),Tsit5(),saveat=0.1),ylim=(0,6),labels = ["rabbit model","wolf model"],color=[1 2]))
# end
# # Display the ODE with the initial parameter values.
# cb()
# Flux.train!(loss_rd, [p], data, opt, cb = cb)

# # Can we do an intervention on the Ode?


end # module
