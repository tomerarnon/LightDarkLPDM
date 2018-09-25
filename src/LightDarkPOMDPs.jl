# __precompile__()

module LightDarkPOMDPs

importall POMDPs

using StaticArrays
using Combinatorics
using Distributions
# using Plots
using POMDPToolbox
using Parameters # for @with_kw
# using ParticleFilters # for AbstractParticleBelief
using LPDM

include("lightdark1d.jl")
include("lightdark2d.jl")
include("lightdark2dtarget.jl")
include("lightdark2dfilter.jl")
include("lightdark1ddespot.jl")
include("lightdark2ddespot.jl")

# include("lightdark2dvis.jl")
export
    AbstractLD1,
    AbstractLD2,
    LightDark1D,
    LightDark2D,
    LightDark2DTarget,
    LightDark1DDespot,
    LightDark2DDespot,
    LightDark2DKalman,
    SymmetricNormal2,
    Vec2,
    obs_std

end # module
