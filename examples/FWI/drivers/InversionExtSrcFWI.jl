using Revise
using Distributed
using DelimitedFiles
using MAT
using JLD
using Multigrid.ParallelJuliaSolver
using jInvSeismic.FWI
using jInvSeismic.Utils
using Helmholtz
using Statistics
using jInv.InverseSolve
using jInv.LinearSolvers
using Multigrid

# NumWorkers = 4;
# if nworkers() == 1
# 	addprocs(NumWorkers);
# elseif nworkers() < NumWorkers
#  	addprocs(NumWorkers - nworkers());
# end

@everywhere begin
	using jInv.InverseSolve
	using jInv.LinearSolvers
	using jInvSeismic.FWI
	using jInv.Mesh
	using Multigrid.ParallelJuliaSolver
	using jInv.Utils
	using DelimitedFiles
	using jInv.ForwardShare
	using KrylovMethods
end

plotting = true;
if plotting
	using jInvVisPyPlot
	using PyPlot
	close("all")
end

println(pwd())
@everywhere FWIDriversPath = "./";
include(string(FWIDriversPath,"prepareFWIDataFiles.jl"));
include(string(FWIDriversPath,"setupFWI.jl"));


dataDir 	= pwd();
resultsDir 	= pwd();
modelDir 	= pwd();

########################################################################################################

########## uncomment block for SEG ###############
#
# dim     = 2;
# pad     = 30;
# jumpSrc = 5;
# jumpRcv = 1;
# newSize = [600,300];
#
# # (m,Minv,mref,boundsHigh,boundsLow) = readModelAndGenerateMeshMref(modelDir,"../../SEGmodel2Dsalt.dat",dim,pad,[0.0,13.5,0.0,4.2],newSize,1.752,2.9);
# #(m,Minv,mref,boundsHigh,boundsLow) = readModelAndGenerateMeshMref(modelDir,"examples/SEGmodel2D_edges.dat",dim,pad,[0.0,13.5,0.0,4.2],newSize,1.752,2.9, false);
# (m,Minv,mref,boundsHigh,boundsLow) = readModelAndGenerateMeshMref(modelDir,"examples/SEGmodel2D_up.dat",dim,pad,[0.0,13.5,0.0,4.2],newSize,1.752,2.9, false);
# #omega = [2.0,2.5,3.0,3.5,4.5,5.5,6.5]*2*pi; #SEG
# omega = Array(3.0:0.3:6.0)*2*pi;
# offset  = newSize[1];  #ceil(Int64,(newSize[1]*(8.0/13.5)));
# println("Offset is: ",offset," cells.")
#
# alpha1 = 5e-1;
# alpha2 = 5e2;
# # stepReg = 1e4; #1e2;#4e+3

##################################################


########## uncomment block for overthrust slice ###############

include(string(FWIDriversPath,"generateMrefOverthrust.jl"));
omega = [2.5,3.0,3.5,4.0,5.0]*2*pi; #Marmousi

alpha1 = 1e1;
alpha2 = 1e1;
# stepReg = 1e4; #1e2;#4e+3

#######################################################


########## uncomment block for marmousi ###############

# include(string(FWIDriversPath,"generateMrefMarmousi.jl"));
# omega = [2.0,2.5,3.5,4.5,6.0,8.0]*2*pi; #Marmousi
#
# alpha1 = 1e-1;
# alpha2 = 1e1;
# stepReg = 1e4; #1e2;#4e+3

#######################################################

maxBatchSize = 24;
useFilesForFields = false;

# ###################################################################################################################
dataFilenamePrefix = string(dataDir,"/DATA_Marmousi",tuple((Minv.n)...));
resultsFilename = string(resultsDir,"/FWI_ExtSrc",tuple((Minv.n)...));
#######################################################################################################################
writedlm(string(resultsFilename,"_mtrue.dat"),convert(Array{Float16},m));
writedlm(string(resultsFilename,"_mref.dat"),convert(Array{Float16},mref));
resultsFilename = string(resultsFilename,".dat");

println("omega*maximum(h): ",omega*maximum(Minv.h)*sqrt(maximum(1.0./(boundsLow.^2))));
ABLpad = pad + 4;

levels      = 3;
numCores 	= 16;
BLAS.set_num_threads(numCores);
maxIter     = 30;
relativeTol = 1e-6;
relaxType   = "Jac";
relaxParam  = 0.75;
relaxPre 	= 2;
relaxPost   = 2;
cycleType   ='W';
coarseSolveType = "Julia";
MG = getMGparam(ComplexF64,Int64,levels,numCores,maxIter,relativeTol,relaxType,relaxParam,relaxPre,relaxPost,cycleType,coarseSolveType,0.0,0.0);
shift = 0.2;
Hparam = HelmholtzParam(Minv,zeros(0),zeros(0),0.0,true,true);
Ainv = getShiftedLaplacianMultigridSolver(Hparam, MG,shift,"BiCGSTAB",0,true);

# Ainv  = getParallelJuliaSolver(ComplexF32,UInt32,numCores=16,backend=3);

workersFWI = workers();
println(string("The workers that we allocate for FWI are:",workersFWI));


figure(1,figsize = (22,10));
plotModel(m,includeMeshInfo=true,M_regular = Minv,cutPad=pad,limits=[2.5,6.0],figTitle="orig",filename="orig.png");

figure(2,figsize = (22,10));
plotModel(mref,includeMeshInfo=true,M_regular = Minv,cutPad=pad,limits=[2.5,6.0],figTitle="mref",filename="mref2.png");

prepareFWIDataFiles(m,Minv,mref,boundsHigh,boundsLow,dataFilenamePrefix,omega,ones(ComplexF64,size(omega)),
									pad,ABLpad,jumpSrc,jumpRcv,offset,workersFWI,maxBatchSize,Ainv,useFilesForFields);




########################################################################################################################
################### READING AND COMPARING THE DATA FOR PLOTTING - NOT NECESSARY FOR INVERSION #######################################
########################################################################################################################
## Data that is generated through frequency domain simulation
### Read receivers and sources files
RCVfile = string(dataFilenamePrefix,"_rcvMap.dat");
SRCfile = string(dataFilenamePrefix,"_srcMap.dat");
srcNodeMap = readSrcRcvLocationFile(SRCfile,Minv);
rcvNodeMap = readSrcRcvLocationFile(RCVfile,Minv);

DobsFD = Array{Array{ComplexF64,2}}(undef,length(omega));
WdFD = Array{Array{ComplexF64,2}}(undef,length(omega));

for k = 1:length(omega)
	omRound = string(round((omega[k]/(2*pi))*100.0)/100.0);
	(Dk,Wk) =  readDataFileToDataMat(string(dataFilenamePrefix,"_freq",omRound,".dat"),srcNodeMap,rcvNodeMap);
	DobsFD[k] = Dk;
	WdFD[k] = Wk;
end



########################################################################################################################
########################################################################################################################
########################################################################################################################

(Q,P,pMis,SourcesSubInd,contDiv,Iact,sback,mref,boundsHigh,boundsLow) =
	setupFWI(m,dataFilenamePrefix,plotting,workersFWI,maxBatchSize,Ainv,SSDFun,useFilesForFields);

########################################################################################################
# Setting up the inversion for slowness instead of velocity:
########################################################################################################
function dump(mc,Dc,iter,pInv,PMis,resultsFilename)
	if iter==0
		return;
	end
	fullMc = slowSquaredToVelocity(reshape(Iact*pInv.modelfun(mc)[1] + sback,tuple((pInv.MInv.n)...)))[1];
	Temp = splitext(resultsFilename);
	if iter>0
		Temp = string(Temp[1],iter,Temp[2]);
	else
		Temp = resultsFilename;
	end
	if resultsFilename!=""
		writedlm(Temp,convert(Array{Float16},fullMc));
	end
	if plotting
		figure(888,figsize = (22,10));
		clf();
		filename = splitdir(Temp)[2];
		plotModel(fullMc,includeMeshInfo=true,M_regular = Minv,cutPad=pad,limits=[2.5,6.0],filename=filename,figTitle=filename);
	end
end

#####################################################################################################
# Setting up the inversion for velocity:
#####################################################################################################
mref 		= velocityToSlowSquared(mref)[1];
t    		= copy(boundsLow);
boundsLow 	= velocityToSlowSquared(boundsHigh)[1];
boundsHigh 	= velocityToSlowSquared(t)[1]; t = 0;
modfun 		= identityMod;

########################################################################################################
# Set up Inversion #################################################################################
########################################################################################################

flush(Base.stdout)


GN = "projGN"
maxStep=0.05*maximum(boundsHigh);
regparams = [1.0,1.0,1.0,1e-6];
# regfun(m,mref,M) 	= wdiffusionReg(m,mref,M,Iact=Iact,C=[]);
regfun(m,mref,M) 	= wFourthOrderSmoothing(m,mref,M,Iact=Iact,C=[]);
if dim==2
	HesPrec=getExactSolveRegularizationPreconditioner();
else
	HesPrec = getSSORCGFourthOrderRegularizationPreconditioner(regparams,Minv,Iact,1.0,1e-8,1000);
end

alpha 	= 1e+2;
pcgTol 	= 1e-1;
maxit 	= 15;
cgit 	= 5;

pInv = getInverseParam(Minv,modfun,regfun,alpha,mref[:],boundsLow,boundsHigh,
                         maxStep=maxStep,pcgMaxIter=cgit,pcgTol=pcgTol,
						 minUpdate=1e-3, maxIter = maxit,HesPrec=HesPrec);
dump(mref, 1, 1,  pInv, pMis, "mref2.png")
mc = copy(mref[:]);



function saveCheckpoint(resultsFilename,mc,Z1,Z2,alpha1,alpha2,pInv,cyc)
	file = matopen(string(splitext(resultsFilename)[1],"_Cyc",cyc,"_checkpoint.mat"), "w");
	write(file,"mc",mc);
	write(file,"Z1",Z1);
	write(file,"Z2",Z2);
	write(file,"alpha1",alpha1);
	write(file,"alpha2",alpha2);
	write(file,"alpha",pInv.alpha);
	write(file,"mref",pInv.mref);
	close(file);
	println("****************************************************************************")
	println("*********************** Saving Checkpoint for cycle ",cyc," ********************")
	println("****************************************************************************")
end

function loadCheckpoint(resultsFilename,cyc)
	file = matopen(string(splitext(resultsFilename)[1],"_Cyc",cyc,"_checkpoint.mat"), "r");
	mc = read(file,"mc");
	Z1 = read(file,"Z1");
	Z2 = read(file,"Z2");
	alpha1 = read(file,"alpha1");
	alpha2 = read(file,"alpha2");
	alpha = read(file,"alpha");
	mref = read(file,"mref");
	close(file);
	return mc,Z1,Z2,alpha1,alpha2,alpha,mref
end









################ uncomment for regular FWI ##################

# mc, = freqCont(mc, pInv, pMis,contDiv, 3,resultsFilename,dump,"",1,0,GN);
# mc, = freqCont(mc, pInv, pMis,contDiv, 3,resultsFilename,dump,"",3,1,GN);
# mc, = freqCont(mc, pInv, pMis,contDiv, 3,resultsFilename,dump,"",3,2,GN);

#############################################################


N_nodes = prod(Minv.n.+1);
nsrc = size(Q,2);
p = 16;
Z1 = 2e-4*rand(ComplexF64,(N_nodes, p));
# Z2 = zeros(ComplexF64, (p, nsrc)); #0.01*rand(ComplexF64, (p, nsrc)) .+ 0.01;
pInv.maxIter = 1;

############# uncomment for extended sources only ####################
# Z2 = zeros(ComplexF64, (p, nsrc));
# ts = time_ns();
# mc,Z1,Z2,alpha1,alpha2, = freqContExtendedSources(mc,Z1,Z2,7,Q,size(P,2),SourcesSubInd,pInv, pMis,contDiv, 4,resultsFilename,dump,Iact,sback,alpha1,alpha2,"",2,0,GN);
# mc,Z1,Z2,alpha1,alpha2, = freqContExtendedSources(mc,Z1,Z2,10,Q,size(P,2),SourcesSubInd, pInv, pMis,contDiv, 4,resultsFilename,dump,Iact,sback,alpha1,alpha2,"",3,1,GN);
#
# regfun(m,mref,M) 	= wdiffusionReg(m,mref,M,Iact=Iact,C=[]);
# pInv.regularizer = regfun;
#
# mc,Z1,Z2,alpha1,alpha2, = freqContExtendedSources(mc,Z1,Z2,10,Q,size(P,2),SourcesSubInd, pInv, pMis,contDiv, 4,resultsFilename,dump,Iact,sback,alpha1,alpha2,"",3,2,GN);
# te = time_ns();
####################################################################################

############# uncomment for extended sources and simultaneous sources #########
ts = time_ns();
simSrcDim = 16;
Z2 = 0.1*rand(ComplexF64, (p, simSrcDim)) .+ 0.01;
#Z2 = 0.1*rand(ComplexF64, (p, nsrc)) .+ 0.01;
#simSrcDim = 1;
windowSize = 4;
updateMref = false;
#####################################################################################################
cyc = 0;startFrom = 1;endAtContDiv = length(contDiv)-3;
mc,Z1,Z2,alpha1,alpha2, = freqContExtendedSourcesSS(mc,Z1,Z2,simSrcDim,10,Q,size(P,2),
				SourcesSubInd,pInv, pMis,contDiv, windowSize,resultsFilename,dump,Iact,sback,alpha1,alpha2,"",startFrom,endAtContDiv,cyc,GN,updateMref);
saveCheckpoint(resultsFilename,mc,Z1,Z2,alpha1,alpha2,pInv,cyc);
#=
#####################################################################################################
endAtContDiv = length(contDiv)-1
#####################################################################################################
pInv.alpha /= 100

# mc,Z1,Z2,alpha1,alpha2,pInv.alpha,pInv.mref = loadCheckpoint(resultsFilename,cyc);
cyc = 1;startFrom = windowSize;
mc,Z1,Z2,alpha1,alpha2, = freqContExtendedSourcesSS(mc,Z1,Z2,simSrcDim,15,Q,size(P,2),
				SourcesSubInd, pInv, pMis,contDiv, windowSize,resultsFilename,dump,Iact,sback,alpha1,alpha2,"",startFrom,endAtContDiv,cyc,GN,updateMref);
saveCheckpoint(resultsFilename,mc,Z1,Z2,alpha1,alpha2,pInv,cyc);
=#
#####################################################################################################

updateMref = true;
regfun(m,mref,M) = wdiffusionReg(m,mref,M,Iact=Iact,C=[]);
pInv.regularizer = regfun;
#####################################################################################################
pInv.maxIter = 10;
mc, = freqCont(mc, pInv, pMis,contDiv, 4,resultsFilename,dump,"",4,1,GN);
mc, = freqCont(mc, pInv, pMis,contDiv, 4,resultsFilename,dump,"",4,2,GN);
#=
# mc,Z1,Z2,alpha1,alpha2,pInv.alpha,pInv.mref = loadCheckpoint(resultsFilename,cyc);

cyc = 2;startFrom = windowSize;
mc,Z1,Z2,alpha1,alpha2, = freqContExtendedSourcesSS(mc,Z1,Z2,simSrcDim,20,Q,size(P,2),
				SourcesSubInd, pInv, pMis,contDiv, windowSize,resultsFilename,dump,Iact,sback,alpha1,alpha2,"",startFrom,endAtContDiv,cyc,GN,updateMref);
saveCheckpoint(resultsFilename,mc,Z1,Z2,alpha1,alpha2,pInv,cyc);
#####################################################################################################

newReg(m,mref,M) 	= wTVReg(m,mref,M,Iact=Iact,C=[]);
pInv.regularizer = newReg;

# mc,Z1,Z2,alpha1,alpha2,pInv.alpha,pInv.mref = loadCheckpoint(resultsFilename,cyc);
cyc = 4;startFrom = windowSize;
mc,Z1,Z2,alpha1,alpha2, = freqContExtendedSourcesSS(mc,Z1,Z2,simSrcDim,10,Q,size(P,2),
				SourcesSubInd, pInv, pMis,contDiv, windowSize,resultsFilename,dump,Iact,sback,alpha1,alpha2,"",startFrom,endAtContDiv,cyc,GN,updateMref);
saveCheckpoint(resultsFilename,mc,Z1,Z2,alpha1,alpha2,pInv,cyc);

=#


te = time_ns();


####################################################################################



println("runtime of inversion");
println((ts - te)/1.0e9);
