# private math functions

"""
A helper function for `ldexpk`

First note that `r = (q >> n) << n` clears the lowest n bits of q, i.e. returns 2^n where n is the
largest integer such that q >= 2^n

For numbers q less than 2^m the following code does the same as the above snippet
    `r = ( (q>>v + q) >> n - q>>v ) << n`
For numbers larger than or equal to 2^v this subtracts 2^n from q for q>>n times.

The function returns q(input) := q(output) + offset*r

In the code for ldexpk we actually use
    `m = ( (m>>n + m) >> n -  m>>m ) << (n-2)`.
So that x has to be multplied by u four times `x = x*u*u*u*u` to put the value  of the offset
exponent amount back in.
"""
@inline function _split_exponent(q, n, v, offset)
    m = q >> v
    m = (((m + q) >> n) - m) << (n - offset)
    q = q - (m << offset)
    m, q
end
@inline split_exponent(::Type{Float64}, q::Int) = _split_exponent(q, UInt(9), UInt(31), UInt(2))
@inline split_exponent(::Type{Float32}, q::Int) = _split_exponent(q, UInt(6), UInt(31), UInt(2))

"""
    ldexpk(a::IEEEFloat, n::Int) -> IEEEFloat

Computes `a × 2^n`.
"""
@inline function ldexpk(x::T, q::Int) where {T<:IEEEFloat}
    bias = exponent_bias(T)
    emax = exponent_raw_max(T)
    m, q = split_exponent(T, q)
    m += bias
    m = ifelse(m < 0, 0, m)
    m = ifelse(m > emax, emax, m)
    q += bias
    u = integer2float(T, m)
    x = x * u * u * u * u
    u = integer2float(T, q)
    x * u
end

@inline ldexpk2(x::T, e::Int) where {T<:IEEEFloat} = x * pow2i(T, e >> UInt(1)) * pow2i(T, e - (e >> UInt(1)))



# threshold values for `ilogbk`
const threshold_exponent(::Type{Float64}) = 300
const threshold_exponent(::Type{Float32}) = 64
"""
    ilogbk(x::IEEEFloat) -> Int

Returns the integral part of the logarithm of `|x|`, using 2 as base for the logarithm; in other
words this returns the binary exponent of `x` so that

    x = significand × 2^exponent

where `significand ∈ [1, 2)`.
"""
@inline function ilogbk(d::T) where {T<:IEEEFloat}
    m = d < T(2)^-threshold_exponent(T)
    d = ifelse(m, d * T(2)^threshold_exponent(T), d)
    q = float2integer(d) & exponent_raw_max(T)
    q = ifelse(m, q - (threshold_exponent(T) + exponent_bias(T)), q - exponent_bias(T))
end


let
global atan2k_fast
global atan2k

const c20d =  1.06298484191448746607415e-05
const c19d = -0.000125620649967286867384336
const c18d =  0.00070557664296393412389774
const c17d = -0.00251865614498713360352999
const c16d =  0.00646262899036991172313504
const c15d = -0.0128281333663399031014274
const c14d =  0.0208024799924145797902497
const c13d = -0.0289002344784740315686289
const c12d =  0.0359785005035104590853656
const c11d = -0.041848579703592507506027
const c10d =  0.0470843011653283988193763
const c9d  = -0.0524914210588448421068719
const c8d  =  0.0587946590969581003860434
const c7d  = -0.0666620884778795497194182
const c6d  =  0.0769225330296203768654095
const c5d  = -0.0909090442773387574781907
const c4d  =  0.111111108376896236538123
const c3d  = -0.142857142756268568062339
const c2d  =  0.199999999997977351284817
const c1d =  -0.333333333333317605173818

const c9f = -0.00176397908944636583328247f0
const c8f =  0.0107900900766253471374512f0
const c7f = -0.0309564601629972457885742f0
const c6f =  0.0577365085482597351074219f0
const c5f = -0.0838950723409652709960938f0
const c4f =  0.109463557600975036621094f0
const c3f = -0.142626821994781494140625f0
const c2f =  0.199983194470405578613281f0
const c1f = -0.333332866430282592773438f0

global @inline atan2k_fast_kernel(x::Float64) = @horner x c1d c2d c3d c4d c5d c6d c7d c8d c9d c10d c11d c12d c13d c14d c15d c16d c17d c18d c19d c20d
global @inline atan2k_fast_kernel(x::Float32) = @horner x c1f c2f c3f c4f c5f c6f c7f c8f c9f

@inline function atan2k_fast(y::T, x::T) where {T<:IEEEFloat}
    q = 0
    if x < 0
        x = -x
        q = -2
    end
    if y > x
        t = x; x = y
        y = -t
        q += 1
    end
    s = y / x
    t = s * s
    u = atan2k_fast_kernel(t)
    t = u * t * s + s
    q * T(MPI2) + t
end


global @inline atan2k_kernel(x::Double{Float64}) = @horner x.hi c1d c2d c3d c4d c5d c6d c7d c8d c9d c10d c11d c12d c13d c14d c15d c16d c17d c18d c19d c20d
global @inline atan2k_kernel(x::Double{Float32}) = dadd(c1f, x.hi * (@horner x.hi c2f c3f c4f c5f c6f c7f c8f c9f))

@inline function atan2k(y::Double{T}, x::Double{T}) where {T<:IEEEFloat}
    q = 0
    if x < 0
        x = -x
        q = -2
    end
    if y > x
        t = x; x = y
        y = -t
        q += 1
    end
    s = ddiv(y, x)
    t = dsqu(s)
    u = atan2k_kernel(t)
    t = dmul(s, dadd(T(1), dmul(t, u)))
    dadd(dmul(T(q), MDPI2(T)), t)
end
end


let
global expk
global expk2

const c10d = 2.51069683420950419527139e-08
const c9d  = 2.76286166770270649116855e-07
const c8d  = 2.75572496725023574143864e-06
const c7d  = 2.48014973989819794114153e-05
const c6d  = 0.000198412698809069797676111
const c5d  = 0.0013888888939977128960529
const c4d  = 0.00833333333332371417601081
const c3d  = 0.0416666666665409524128449
const c2d  = 0.166666666666666740681535
const c1d  = 0.500000000000000999200722

const c5f = 0.00136324646882712841033936f0
const c4f = 0.00836596917361021041870117f0
const c3f = 0.0416710823774337768554688f0
const c2f = 0.166665524244308471679688f0
const c1f = 0.499999850988388061523438f0

global @inline expk_kernel(x::Float64) = @horner x c1d c2d c3d c4d c5d c6d c7d c8d c9d c10d
global @inline expk_kernel(x::Float32) = @horner x c1f c2f c3f c4f c5f

@inline function expk(d::Double{T}) where {T<:IEEEFloat}
    q = round(T(d) * T(MLN2E))
    s = dadd(d, -q * LN2U(T))
    s = dadd(s, -q * LN2L(T))
    u = expk_kernel(T(s))
    t = dadd(s, dmul(dsqu(s), u))
    t = dadd(T(1), t)
    ldexpk(T(t), unsafe_trunc(Int, q))
end


@inline function expk2(d::Double{T}) where {T<:IEEEFloat}
    q = round(T(d) * T(MLN2E))
    s = dadd(d, -q * LN2U(T))
    s = dadd(s, -q * LN2L(T))
    u = expk_kernel(s.hi)
    t = dadd(s, dmul(dsqu(s), u))
    t = dadd(T(1), t)
    scale(t, pow2i(T, unsafe_trunc(Int, q)))
end
end


let
global logk
global logk2

const c8d = 0.13860436390467167910856
const c7d = 0.131699838841615374240845
const c6d = 0.153914168346271945653214
const c5d = 0.181816523941564611721589
const c4d = 0.22222224632662035403996
const c3d = 0.285714285511134091777308
const c2d = 0.400000000000914013309483
const c1d = 0.666666666666664853302393

const c4f = 0.2392828464508056640625f0
const c3f = 0.28518211841583251953125f0
const c2f = 0.400005877017974853515625f0
const c1f = 0.666666686534881591796875f0

global @inline logk_kernel(x::Float64) = @horner x c1d c2d c3d c4d c5d c6d c7d c8d
global @inline logk_kernel(x::Float32) = @horner x c1f c2f c3f c4f

@inline function logk(d::T) where {T<:IEEEFloat}
    e  = ilogbk(d * T(1.0/0.75))
    m  = ldexpk(d, -e)

    x  = ddiv(dsub2(m, T(1)), dadd2(T(1), m))
    x2 = dsqu(x)

    t  = logk_kernel(x2.hi)

    dadd(dmul(MDLN2(T), T(e)), dadd(scale(x, T(2)), dmul(dmul(x2, x), t)))
end


@inline function logk2(d::Double{T}) where {T<:IEEEFloat}
    e  = ilogbk(d.hi * T(1.0/0.75))
    m  = scale(d, pow2i(T, -e))

    x  = ddiv(dsub2(m, T(1)), dadd2(m, T(1)))
    x2 = dsqu(x)

    t  = logk_kernel(x2.hi)

    dadd(dmul(MDLN2(T), T(e)), dadd(scale(x, T(2)), dmul(dmul(x2, x), t)))
end
end
