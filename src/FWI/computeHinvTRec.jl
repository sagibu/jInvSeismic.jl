export computeHinvTRec

function computeHinvTRec(pMis::Array{RemoteChannel})
HinvTRec = Array{Array{ComplexF64}}(undef,length(pMis))
@sync begin
	@async begin
		for k=1:length(pMis)
			HinvTRec[k] = remotecall_fetch(computeHinvTRec,pMis[k].where,pMis[k]);
		end
	end
end
return HinvTRec;
end


function computeHinvTRec(pMisRF::RemoteChannel)
pMis = fetch(pMisRF)
HinvTP, = solveLinearSystem(spzeros(ComplexF64,0,0),complex(Matrix(pMis.pFor.Receivers)),pMis.pFor.ForwardSolver,1);
return HinvTP;
end

function computeHinvTRec(pMisRF::RemoteChannel, x, doTranspose)
pMis = fetch(pMisRF)
if doTranspose == 0
	HinvTP, = solveLinearSystem(spzeros(ComplexF64,0,0),x,pMis.pFor.ForwardSolver,doTranspose);
	return complex(Matrix(pMis.pFor.Receivers')) * HinvTP;
else
	HinvTP, = solveLinearSystem(spzeros(ComplexF64,0,0),complex(Matrix(pMis.pFor.Receivers) * x),pMis.pFor.ForwardSolver,doTranspose);
	return  HinvTP;
end
end

function computeHinvTRecX(pMis::Array{RemoteChannel}, x, doTranspose=1)
HinvTRec = Array{Array{ComplexF64}}(undef,length(pMis))
@sync begin
	@async begin
		for k=1:length(pMis)
			HinvTRec[k] = remotecall_fetch(computeHinvTRec,pMis[k].where,pMis[k],x,doTranspose);
		end
	end
end
return HinvTRec;
end

function computeHinvTRecXarr(pMis::Array{RemoteChannel}, x, doTranspose=1)
HinvTRec = Array{Array{ComplexF64}}(undef,length(pMis))
@sync begin
	@async begin
		for k=1:length(pMis)
			HinvTRec[k] = remotecall_fetch(computeHinvTRec,pMis[k].where,pMis[k],x[k],doTranspose);
		end
	end
end
return HinvTRec;
end
