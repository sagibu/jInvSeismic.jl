include("setupInversionExample.jl");

@everywhere begin
using jInv.InverseSolve
using jInv.LinearSolvers
end

using jInvVis
using PyPlot

close("all")
tstart = time_ns();

function plotInputData()
	figure(20)
	imshow(m');colorbar();

	figure(21);
	imshow(reshape(gamma,tuple(size(m)...))');
end
plotInputData();
Dobs, Wd = solveForwardProblem(m, pForp, omega, nrec, nsrc, nfreq);

for i=1:nfreq
	figure(i);

	imshow(Dobs[i][:,:]);
end

function plotModelResult(model)
	close(888);
	figure(888);
	imshow(model);colorbar();
	pause(1.0);
end
nx = size(m)[1];
nz = size(m)[2];

figure(22);
imshow(mref'); colorbar();

mc, Dc, pInv, Iact, mback = solveInverseProblem(pForp, Dobs, Wd, nfreq, nx, nz, mref,
												Mr, 0.5, 0.035,"ORIG_FWI.dat", true, plotModelResult);

#Show results
fullMc = reshape(Iact*pInv.modelfun(mc)[1] + mback,tuple((pInv.MInv.n)...));
println("Model error:");
println(norm(fullMc.-m));
tend = time_ns();
println("Runtime:");
println((tend - tstart)/1.0e9);

#Plot residuals
figure(23);
imshow((abs.(m.-fullMc))'); colorbar();
