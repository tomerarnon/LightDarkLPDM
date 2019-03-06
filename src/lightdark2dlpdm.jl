using Discretizers
import LPDM: default_action, next_actions, isterminal
import POMDPs: rand, actions

mutable struct LightDark2DLpdm <: AbstractLD2
# @with_kw mutable struct LightDark2DLpdm <: AbstractLD2
    min_noise::Float64
    min_noise_loc::Float64
    Q::Float64
    R::Float64
    term_radius::Float64
    n_bins::Int         # per linear dimension
    max_x::Float64     # assume symmetry in x and y for simplicity
    bin_edges::Vector{Float64}
    bin_centers::Vector{Float64}
    lindisc::LinearDiscretizer
    init_dist::Any
    discount::Float64
    count::Int
    n_rand::Int
    resample_std::Float64
    exploit_visits::Int64
    max_actions::Int64
    action_limits::Tuple{Float64,Float64}
    action_space_type::Symbol
    base_action_space::Vector{LD2Action}
    nominal_action_space::Vector{LD2Action}
    extended_action_space::Vector{LD2Action}
    reward_func::Symbol

    function LightDark2DLpdm(action_space_type::Symbol; reward_func = :quadratic)
        this = new()
        this.min_noise               = 0.0
        this.min_noise_loc           = 5.0
        this.Q                       = 0.5
        this.R                       = 0.5
        this.term_radius             = 0.05
        this.n_bins                  = 100 # per linear dimension
        this.max_x                   = 10     # assume symmetry in x and y for simplicity
        this.bin_edges               = collect(-this.max_x:(2*this.max_x)/this.n_bins:this.max_x)
        this.bin_centers             = [(this.bin_edges[i]+this.bin_edges[i+1])/2 for i=1:this.n_bins]
        this.lindisc                 = LinearDiscretizer(this.bin_edges)
        this.discount                = 1.0
        this.count                   = 0
        this.n_rand                  = 0
        this.resample_std            = 0.5 # st. deviation for particle resampling
        this.max_actions             = 30
        this.action_limits           = (-5.0,5.0)
        this.action_space_type       = action_space_type
        this.exploit_visits          = 50
        # this.base_action_space       = [1.0, 0.1, 0.01]
        this.nominal_action_space    = [1.0, 0.1, 0.01]
        this.extended_action_space   = vcat(1*this.nominal_action_space,
                                            2*this.nominal_action_space,
                                            3*this.nominal_action_space,
                                            4*this.nominal_action_space,
                                            5*this.nominal_action_space)
        this.reward_func                  = reward_func
        return this
    end
end

# POMDPs.actions(p::LightDark2DLpdm) = vcat(-POMDPs.actions(p, true), [0.0], POMDPs.actions(p,true))
LPDM.default_action(p::LightDark2DLpdm) = 0.00
LPDM.default_action(p::LightDark2DLpdm, ::Vector{LPDMParticle{LD2State}}) = LPDM.default_action(p)

POMDPs.rand(p::LightDark2DLpdm, s::LD2State, rng::LPDM.RNGVector) = norminvcdf(s, p.resample_std, rand(rng)) # for resampling

# Replaces the default call
function LPDM.isterminal(pomdp::LightDark2DLpdm, particles::Vector{LPDMParticle{LD2State}})
    expected_state = 0.0

    for p in particles
        expected_state += p.state*p.weight # NOTE: assume weights are normalized
    end
    return isterminal(pomdp,expected_state)
end

# Version with discrete observations
function generate_o(p::LightDark2DLpdm, sp::Float64, rng::AbstractRNG)
    o = rand(rng, observation(p, sp))
    o_disc = p.bin_centers[encode(p.lindisc,o)]
    return o_disc
end

# For bounds calculations
POMDPs.actions(pomdp::LightDark2DLpdm) = vcat(-pomdp.extended_action_space, pomdp.extended_action_space)
LPDM.max_actions(pomdp::LightDark2DLpdm) = pomdp.max_actions

# For "simulated annealing"
function LPDM.next_actions(pomdp::LightDark2DLpdm,
                           current_action_space::Vector{LD2Action},
                           a_star::LD2Action,
                           n_visits::Int64,
                           rng::RNGVector)::Vector{LD2Action}

    initial_space = vcat(-pomdp.nominal_action_space, pomdp.nominal_action_space)

    # simulated annealing temperature
    if isempty(current_action_space) # initial request
        # return vcat(-pomdp.nominal_action_space, [0], pomdp.nominal_action_space)
        return initial_space
    end

    l_initial = length(initial_space)

    # don't count initial "seed" actions in computing T
    T = 1 - (length(current_action_space) - l_initial)/(LPDM.max_actions(pomdp) - l_initial)
    adj_exploit_visits = pomdp.exploit_visits * (1-T) # exploit more as T decreases

    # generate new action(s)
    if (n_visits > adj_exploit_visits) && (length(current_action_space) < LPDM.max_actions(pomdp))

        # Use the full range as initial radius to accomodate points at the edges of it
        radius = abs(pomdp.action_limits[2]-pomdp.action_limits[1]) * T

        in_set = true
        a = NaN
        while in_set
            a = (rand(rng, Uniform(a_star - radius, a_star + radius)))
            a = clamp(a, pomdp.action_limits[1], pomdp.action_limits[2]) # if outside action space limits, clamp to them
            in_set = a ∈ current_action_space
        end

        # println("a_star: $a_star, T: $T, radius: $radius, a: $a")
        return [a] # New action, returned as a one element vector.
    else
        return []
    end
end

# version for Blind Value
function LPDM.next_actions(pomdp::LightDark2DLpdm,
                           current_action_space::Vector{LD2Action},
                           Q::Vector{Float64},
                           n_visits::Int64,
                           rng::RNGVector)::Vector{LD2Action}

     initial_space = vcat(-pomdp.nominal_action_space, pomdp.nominal_action_space)
     # initial_space = [0.0]

       # simulated annealing temperature
     if isempty(current_action_space) # initial request
           return initial_space
     end

    if (n_visits > 25) && (length(current_action_space) < LPDM.max_actions(pomdp))
        M = 100
        # TODO: Create a formal sampler for RNGVector when there is time
        Apool = [rand(rng, Uniform(pomdp.action_limits[1], pomdp.action_limits[2])) for i in 1:M]
        σ_known = std(Q)
        σ_pool = std(Apool) # in our case distance to 0 (center of the domain) is just the abs. value of an action
        ρ = σ_known/σ_pool
        bv_vector = [bv(a,ρ,current_action_space,Q) for a in Apool]

        return [Apool[argmax(bv_vector)]] # New action, returned as a one element vector.
    else
        return []
    end
end


# Blind Value function
function bv(a::LD2Action, ρ::Float64, Aexpl::Vector{LD2Action}, Q::Vector{Float64})::LD2Action
    scores = [ρ*abs(a-Aexpl[i])+Q[i] for i in 1:length(Aexpl)]
    return Aexpl[argmin(scores)]
end

# NOTE: OLD VERSION. implements "fast" simulated annealing
# function LPDM.next_actions(pomdp::LightDark2DLpdm,
#                            current_action_space::Vector{LD2Action},
#                            a_star::LD2Action,
#                            n_visits::Int64,
#                            rng::RNGVector)::Vector{LD2Action}
#
#     initial_space = vcat(-pomdp.nominal_action_space, pomdp.nominal_action_space)
#
#     # simulated annealing temperature
#     if isempty(current_action_space) # initial request
#         # return vcat(-pomdp.nominal_action_space, [0], pomdp.nominal_action_space)
#         return initial_space
#     end
#
#     l_initial = length(initial_space)
#
#     # don't count initial "seed" actions in computing T
#     T = 1 - (length(current_action_space) - l_initial)/(LPDM.max_actions(pomdp) - l_initial)
#     adj_exploit_visits = pomdp.exploit_visits * (1-T) # exploit more as T decreases
#
#     # generate new action(s)
#     if (n_visits > adj_exploit_visits) && (length(current_action_space) < LPDM.max_actions(pomdp))
#         # NOTE: use the actual point for now, convert to a distribution around it later
#         left_d = abs(pomdp.action_limits[1]-a_star)
#         right_d = abs(pomdp.action_limits[2]-a_star)
#         d = left_d > right_d ? -left_d : right_d
#         # println("a_star: $a_star, T: $T, left_d: $left_d, right_d: $right_d, d: $d, a: $(a_star + d*T)")
#         return [a_star + d*T] # New action, returned as a one element vector. Value is scaled by T.
#     else
#         return []
#     end
# end

# # Hard-coded version for now for debugging
# function LPDM.next_actions(pomdp::LightDark2DLpdm, current_action_space::Vector{LD2Action})::Vector{LD2Action}
#     if isempty(current_action_space) # initial request
#         return vcat(-pomdp.nominal_action_space, [0], pomdp.nominal_action_space)
#     end
#
#     # index of the new action in the extended_action_space
#     n = round(Int64, 0.5*(length(current_action_space) - (2*length(pomdp.nominal_action_space) + 1))) + 1
#     if (length(current_action_space) < pomdp.max_actions -1) && (n <= length(pomdp.extended_action_space))
#         # println("current: $current_action_space")
#         # accounting for zero with the first +1; 0.5 because we add in pairs.
#
#         return [-pomdp.extended_action_space[n], pomdp.extended_action_space[n]] # return as a 2-element vector
#     else
#         return []
#     end
# end