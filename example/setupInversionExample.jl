using jInvSeismic.BasicFWI
using jInvSeismic.Utils
using jInv.Mesh
using jInv.Utils
using jInv.ForwardShare
using Distributed

using DelimitedFiles

if nworkers() == 1
	addprocs(4);
elseif nworkers() < 4
	addprocs(4 - nworkers());
end


println("IM here")
@everywhere using jInvSeismic.BasicFWI

	@everywhere using jInv.Mesh
	@everywhere using jInv.Utils
@everywhere using jInv.ForwardShare

function readModelAndGenerateMeshMref(readModelFolder::String,modelFilename::String,dim::Int64,pad::Int64,domain::Vector{Float64},newSize::Vector=[],velBottom::Float64=0.0,velHigh::Float64=0.0)
########################## m,mref are in Velocity here. ###################################
	m = readdlm(string(readModelFolder,"/",modelFilename));
	m = m*1e-3;
	m = copy(m');
	mref = getSimilarLinearModel(m,velBottom,velHigh);

	sea = abs.(m[:] .- minimum(m)) .< 7e-2;
	mref[sea] = m[sea];
	if newSize!=[]
		m    = expandModelNearest(m,   collect(size(m)),newSize);
		mref = expandModelNearest(mref,collect(size(mref)),newSize);
	end

	Minv = getRegularMesh(domain,collect(size(m)));

	(mPadded,MinvPadded) = addAbsorbingLayer(m,Minv,pad);
	(mrefPadded,MinvPadded) = addAbsorbingLayer(mref,Minv,pad);

	N = prod(MinvPadded.n.+1);
	boundsLow  = minimum(mPadded);
	boundsHigh = maximum(mPadded);

	boundsLow  = ones(N)*boundsLow;
	boundsLow = convert(Array{Float32},boundsLow);
	boundsHigh = ones(N)*boundsHigh;
	boundsHigh = convert(Array{Float32},boundsHigh);

	return (mPadded,MinvPadded,mrefPadded,boundsHigh,boundsLow);
end

dim     = 2;
pad     = 30;
newSize = [600,300];

(m,Mr,mref,boundsHigh,boundsLow) = readModelAndGenerateMeshMref("example","SEGmodel2Dsalt.dat",dim,pad,[0.0,13.5,0.0,4.2],newSize,1.752,2.7);
m = 1 ./ (m.^2);
mref = 1 ./ (mref.^2);

# attenuation for BC
padx = 34; padz = 34
a    = 2.0;
xc = getCellCenteredGrid(Mr)
gamma = getABL(Mr,true,[padx;padz],a);

# parameters for the Helmholtz (units in km)
h = Mr.h;
n = Mr.n;
omega = 2*pi*[2.0;2.5;3.5;4.5;6.0;]
nfreq = length(omega)
# generate sources
q = zeros(tuple(n.+1...)); q[padx+1:4:end-padx-1,1] .= 1e4
Q = sdiag(vec(q))
Q = Q[:,(LinearIndices(sum(Q,dims=2) .!= 0))[findall(sum(Q,dims=2) .!= 0)]]
nsrc = size(Q,2)
println(size(Q))
# receivers
p = zeros(tuple(n.+1...)); p[padx+1:end-padx-1,1] .= 1
P = sdiag(vec(p))
P = P[:,(LinearIndices(sum(P,dims=2) .!= 0))[findall(sum(P,dims=2) .!= 0)]]
nrec = size(P,2)
println(size(P))
pFor  = getFWIparam(omega,gamma,Q,P,Mr)
pForp = getFWIparam(omega,gamma,Q,P,Mr,true)

# inversion mesh and forward mesh are the same here
M2Mp = ones(length(pForp))
