using Omega
using UnicodePlots
using CSV
using DataFrames
using RunTools
using ArgParse

include("distances.jl")
include("evals.jl")


lift(:(Base.getindex), 2)
const Δxk = :x2
const Δyk = :y2

abstract type AbstractObject end

struct ShallowObject{T} <: AbstractObject
  x::T
  y::T
  Δx::T
  Δy::T
end

struct Object{T} <: AbstractObject
  x::T
  y::T
  Δx::T
  Δy::T
  vx::T
  vy::T
  d::T
end

"View port into scene"
struct Camera{T1, T2, T3, T4}
  x::T1
  y::T2
  Δx::T3
  Δy::T4
end

"Latent scene: camera and objects"
struct Scene{O, C}
  objects::Vector{O}
  camera::C
end

struct Image{O}
  objects::Vector{O}
end

"Render scene into an image"
render(scene, camera)::Image = scene

function blockedarea(a, b)
  # Compute area that a blocks in b
  # if a is farther away, it cannot block it.
  if (a.d >= b.d)
    return 0
  end
  # Otherwise compute intersecting rectangle.
  interwidth = minimum([a.x + a.Δx, b.x + b.Δx]) - maximum([a.x, b.x])
  interheight = minimum([a.y, b.y]) - maximum([a.y + a.Δy, b.y + b.Δy])
  interarea = interwidth * interheight
  barea = b.Δx * b.Δy
  return interarea/barea
end

function render(scene)
  # Better rendering function that computes overlap, and
  # returns probability proportional to percentage of overlap.
  # But should be changed to be a learned thing.
  blockmatrix = [blockedarea(a, b) for a in scene.objects, b in scene.objects]
  print(blockmatrix)
  objectids = Int[]
  for objid = 1:length(scene.objects)
    if rand() >= sum(blockmatrix[:, objid])
      append!(objectids, objid)
    end
  end
  objects = [scene.objects[id] for id in objectids]
  return Scene(objects, scene.camera)
end

function accumprop(prop, video)
  props = Float64[]
  for scene in video, object in scene.objects
    push!(props, getfield(object, prop))
  end
  props
end

#nboxes = poisson(3) + 1
#nboxes = poisson(1) + 3
nboxes = 3
#nboxes(ω)

"Scene at frame t=0"
function initscene(ω, data)
  objects = map(1:nboxes) do i
    Object(normal(ω[@id][i], mean(accumprop(:x, data)), std(accumprop(:x, data))),
       normal(ω[@id][i], mean(accumprop(:y, data)), std(accumprop(:y, data))),
       normal(ω[@id][i], mean(accumprop(:Δx, data)), std(accumprop(:Δx, data))),
       normal(ω[@id][i], mean(accumprop(:Δy, data)), std(accumprop(:Δy, data))),
       normal(ω[@id][i], 5.0, 0.5), # Speedies on x
       normal(ω[@id][i], -3.0, 0.5), # velocity on y
       uniform(ω[@id][i], [1.0, 2.0])) # Depth, encoded as distance from camera.
       #normal(ω[@id][i], 0.0, 1.0),
       #normal(ω[@id][i], 0.0, 1.0))
  end
  camera = Camera(normal(ω[@id], 0.0, 1.0),
                  normal(ω[@id], 0.0, 1.0),
                  640.0,
                  480.0)
  @assert length(objects) == 3
  Scene(objects, camera)
end


"Shift an object by adding gaussian perturbation to x, y, Δx, Δy"
function move(ω, object::Object)
  Object(object.x + object.vx,
         object.y + object.vy,
         object.Δx,
         object.Δy,
         object.vx,
         object.vy,
         object.d)
end

"Move entire all objects in scene"
function move(ω, scene::Scene)
  Scene(map(iobj -> move(ω[iobj[1]], iobj[2]), enumerate(scene.objects)), scene.camera)
end

"Simulate `nsteps`"
function video_(ω, scene::Scene = initscene(ω), nsteps = 1000, f = identity)
  trajectories = Scene[]
  for i = 1:nsteps
    scene = move(ω[i], scene)
    push!(trajectories, f(scene))
  end
  trajectories
end

video_(ω, data::Vector, nsteps = 1000, f = identity) = video_(ω, initscene(ω, data), nsteps, f)

## GP model
## ========

d(x1, x2) = x1 - x2
K(x1, x2; l=0.1) = exp(-(d(x1, x2)^2)/(2l^2))
t = 1:0.1:10
using PDMats
Σ = PDMat([K(x, y) for x in t, y in t] * 300)

"Gaussian Process Random Variable"
function gp_(ω)
  trajectories = Scene[]
  objects = map(1:nboxes) do i
    x = mvnormal(ω[@id][i][1], zeros(t), Σ)
    y = mvnormal(ω[@id][i][2], zeros(t), Σ)
    # Δx = mvnormal(ω[@id][i][3], zeros(t), Σ)
    # Δy = mvnormal(ω[@id][i][4], zeros(t), Σ)
    Δx = 50.0
    Δy = 50.0
    # Whatever for now.
    vx = 0
    vy = 0
    Object.(x, y, Δx, Δy, vx, vy)
    # @grab x
  end
  #@grab objects
  camera = Camera(0.0, 0.0, 640.0, 480.0)
  obj_(t) = map(obj -> obj[t], objects)
  [Scene(obj_(i), camera) for i = 1:length(t)] 
end

"Gaussian Process Prior"
function testgpprior()
  w = SimpleΩ{Int, Array}()
  gpvideo = ciid(gp_)
  samples = gpvideo(w)
  viz(samples)
end

## Inference
## =========

"Construct a scene from dataset"
function Scene(df::AbstractDataFrame)
  objects = map(eachrow(df)) do row
    x = row[:x]
    dx = row[Δxk]
    Δx = abs(dx - x)
    y = row[:y]
    dy = row[Δyk]
    Δy = abs(dy - y)
    ShallowObject(float(x), float(y), float(Δx), float(Δy))
  end
  camera = Camera(0.0, 0.0, 640.0, 480.0)
  Scene(objects, camera)
end

Δ(a::Real, b::Real) = sqrt((a - b)^2)
Δ(a::AbstractObject, b::AbstractObject) =
  mean([Δ(a.x, b.x), Δ(a.y, b.y), Δ(a.Δx, b.Δx), Δ(a.Δy, b.Δy)])
Δ(a::Scene, b::Scene) = surjection(a.objects, b.objects)

function Omega.softeq(a::Array{<:Scene,1}, b::Array{<:Scene})
  dists = Δ.(a, b)
  d = mean(dists)
  e = 1 - Omega.kse(d, 0.08)
  eps = 1e-6
  Omega.SoftBool(e + eps)
end

## Visualization
## =============
include("video.jl")

"Four points (x, y) - corners of `box`"
function corners(box)
  ((box.x, box.y),
   (box.x + box.Δx, box.y),
   (box.x + box.Δx, box.y - box.Δy),
   (box.x, box.y -  box.Δy))
end

"Draw Box"
function draw(obj, canvas, color = :blue)
  corners_ = corners(obj)
  for i = 1:length(corners_)
    p1 = corners_[i]
    p2 = i < length(corners_) ? corners_[i + 1] : corners_[1]
    lines!(canvas, p1..., p2..., color)
  end
  canvas
end

"Fix aspect ratio (account that uncicode is taller than wide)"
fixao(x, y; aspectratio = 0.5) = (x, Int(y * aspectratio))

"Draw Scene"
function draw(scene::Scene,
              canvas = BrailleCanvas(fixao(64, 32)..., origin_x = -50.0, origin_y = -50.0,
                                     width = scene.camera.Δx + 10, height = scene.camera.Δy + 10))
  draw(scene.camera, canvas, :red)
  foreach(obj -> draw(obj, canvas, :blue), scene.objects)
  canvas
end

"Draw a sequence of frames"
function viz(vid, sleeptime = 0.02)
  foreach(vid) do o
    display(draw(o))
    sleep(sleeptime)
  end
end

## Run
## ===
datapath = joinpath(datadir(), "spelke", "TwoBalls", "TwoBalls_DetectedObjects.csv")
datapath = joinpath(datadir(), "spelke", "data", "Balls_3_Clean_Diverge", "Balls_3_Clean_Diverge_DetectedObjects.csv")

function train(n = 10000)
  # datapath = joinpath(datadir(), "spelke", "TwoBalls", "TwoBalls_DetectedObjects.csv")
  # datapath = joinpath(datadir(), "spelke", "data", "Balls_2_DivergenceA", "Balls_2_DivergenceA_DetectedObjects.csv")
  datapath = joinpath(datadir(), "spelke", "data", "Balls_3_Clean_Diverge", "Balls_3_Clean_Diverge_DetectedObjects.csv")

  data = CSV.read(datapath)
  nframes = length(unique(data[:frame]))
  frames = groupby(data, :frame)
  realvideo = map(Scene, frames)
  video = ciid(ω -> video_(ω, realvideo, nframes, render))
  latentvideo = ciid(ω -> video_(ω, realvideo, nframes))
  rand(video)
<<<<<<< HEAD
  samples = rand(video, video == realvideo, SSMH, n=n);
=======
  samples = rand(latentvideo, video == realvideo, SSMH, n=1000);
>>>>>>> rcd
  evalposterior(samples, realvideo, false, true)
  samples
end

"Frame by frame differences"
function Δs(video)
  Δs = Float64[]
  for i = 1:length(video) - 1
    v1 = video[i]
    v2 = video[i + 1]
    push!(Δs,  Δ(v1, v2))
  end
  Δs
end