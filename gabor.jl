module Gabor
import Base:*
import Base.size
using LinearAlgebra

# Exceptions
struct InvalidFuncDimensions <: Exception
    funcSize::Int
    spaceSize::Int
end
Base.showerror(io::IO, e::InvalidFuncDimensions) =
    print(io, "The dimensions ($(e.funcSize)) of the Func values"
          * " do not match the size ($(e.spaceSize)) of the space!")

struct InvalidElemFuncDimensions <: Exception
    spaceSize::Int
    timeStep::Int
    freqStep::Int
end
Base.showerror(io::IO, e::InvalidElemFuncDimensions) =
    print(io, "Unable to fit time-step $(e.timeStep) and frequency-step"
         * " of $(e.freqStep) in space of size $(e.spaceSize)!")

struct FunctionsDoNotMatch <: Exception
end
Base.showerror(io::IO, e::FunctionsDoNotMatch) =
    print(io, "Cannot compare functions with different dimensions or"
         * " domains for biorthogonality")

struct AnalyseMismatch <: Exception
end
Base.showerror(io::IO, e::AnalyseMismatch) =
print(io, "Domain of function being analysed does not match"
      * " elementary function domain")

struct SynthesiseMismatch <: Exception
end
Base.showerror(io::IO, e::AnalyseMismatch) =
print(io, "Size of coefficients does not match elementary function dimensions")



Scalar = Complex{Float64}

periodic(k::Integer, P) = ((k%P)+P)%P

struct Func
    domain::UnitRange{Int64}
    values::Vector{Scalar}
    function Func(domain::UnitRange{Int64}, values::Vector{Scalar})
        if length(values) ≠ length(domain)
            throw(InvalidFuncDimensions(length(values), length(domain)))
        end 
        new(domain, values)
    end
end
(f::Func)(k::Int)::Scalar = f.values[findfirst(isequal(periodic(k, length(f.domain))), f.domain)]
*(A::Array{Gabor.Scalar}, f::Func) = Func(f.domain, A*f.values)

# the shift-modulation operator on funcs
function ψ(p::Int, q::Int, g::Func)::Func
    g_shift = Func(g.domain, circshift(g.values, p))
    L = length(g.domain)
    Func(g.domain, [exp(2π*im*q*k/L)*g_shift(k) for k in g.domain])
end

struct ElemFunc
    func::Func
    timeStep::Int
    freqStep::Int
    function ElemFunc(func::Func, timeStep::Int, freqStep::Int)
        sizeDivisors = [length(func.domain) % i for i in [timeStep, freqStep]]
        nonDiv = filter(k -> k ≠ 0, sizeDivisors) # failed to divide evenly
        if (timeStep ≤ 0) || (freqStep ≤ 0) || (length(nonDiv) ≠ 0)
            throw(InvalidElemFuncDimensions(length(func.domain), timeStep, freqStep))
        end
        new(func, timeStep, freqStep)
    end
    ElemFunc(f::Func, ψg::ElemFunc) = ElemFunc(f, ψg.timeStep, ψg.freqStep)
end
(ψg::ElemFunc)(m::Int, n::Int)::Func = ψ(m*ψg.timeStep, n*ψg.freqStep, ψg.func)
dimensions(ψg::ElemFunc) = vcat(map(div -> Int(length(ψg.func.domain)/div), [ψg.timeStep, ψg.freqStep]), length(ψg.func.domain))

function operator(ψg::ElemFunc)
    M, N, _ = dimensions(ψg)
    shift_values = [ψg(m, n).values for m in 0:M-1, n in 0:N-1]
    sum([v*transpose(v) for v in shift_values])
end

netΔ(A, B) = sum([abs(A[i]-B[i]) for i in 1:length(A)])

# returns the netΔ to the L×L identity of the outer product sum
function biorthogonal(ψg::ElemFunc, ψγ::ElemFunc)
    if (dimensions(ψg) ≠ dimensions(ψγ)) 
        throw(FunctionsDoNotMatch())
    end
    L = length(ψg.func.domain)
    M, N, _ = dimensions(ψg)
    out_prod = sum([ψg(m, n).values*conj(transpose(ψγ(m, n).values)) for m in 0:M-1, n in 0:N-1])
    id_L = Matrix{Scalar}(LinearAlgebra.I, L, L)
    netΔ(id_L, out_prod)
end

function frame(ψg::ElemFunc)
    S = operator(ψg)
    γ = inv(S)*ψg.func
    ψγ = ElemFunc(γ, ψg)
    biorthogonal(ψg, ψγ)
end

struct Lattice
    values::Array{Scalar, 2}
end
(c::Lattice)(m::Int, n::Int) = c.values[m+1, n+1]
size(c::Lattice) = size(c.values)

function analyse(ψg::ElemFunc, x::Func)
    M, N, _ = dimensions(ψg)
    if (x.domain ≠ ψg.func.domain)
        throw(AnalyseMismatch())
    end
    Σ(m,n) = sum([conj(ψg(m, n)(k))*x(k) for k in ψg.func.domain])
    Lattice([Σ(m,n) for m in 0:M-1, n in 0:N-1])
end

function synthesize(ψg::ElemFunc, c::Lattice)
    M, N, _ = dimensions(ψg)
    if (M,N) ≠ size(c)
        throw(SynthesizeMismatch())
    end
    x(k) = sum([c(m,n)*ψg(m,n)(k) for m in 0:M-1, n in 0:N-1])
    domain = ψg.func.domain
    Func(domain, map(x, domain))
end

# compute Wexler-Raz minimum energy dual
function wr_bio(ψg::ElemFunc)::ElemFunc
    L = length(ψg.func.domain)
    M, N, _ = dimensions(ψg)
    lattice = [(m,n) for m in 0:M-1 for n in 0:N-1]
    G = [conj(ψg(m, n)(k)) for (m,n) in lattice, k in ψg.func.domain]
    μ = vcat(L/(M*N), zeros(Scalar, L-1))
    γ = Func(ψg.func.domain, G \ μ)
    ElemFunc(γ, ψg)
end

end


domain = 0:11
L = length(domain)


window(k::Integer)::Complex{Float64} = (2^(1/2)/8)^(1/2)*exp(-(2k)^2)

g = Gabor.Func(domain, map(window, domain))
ψg = Gabor.ElemFunc(g, 1, 12)
S = Gabor.operator(ψg)
g̃ = inv(S)*g
ψg̃ = Gabor.ElemFunc(g̃, ψg.timeStep, ψg.freqStep)

# ψγ = Gabor.wr_bio(ψg)
# γ = ψγ.func
