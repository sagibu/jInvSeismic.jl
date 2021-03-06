export getSensMatVec

function getSensMatVec(v::Vector,m::Vector,pFor::FWIparam)

    # extract pointers
    M    			= pFor.Mesh
    omega 			= pFor.omega
    gamma 			= pFor.gamma
    Q     			= pFor.Sources
    P     			= pFor.Receivers
    Ainv   			= pFor.ForwardSolver
    nsrc 			= size(Q,2)
    nrec 			= size(P,2)
	n 				= prod(M.n.+1);
	batchSize 		= pFor.forwardSolveBatchSize;
	select  		= pFor.sourceSelection;
	
	
	if length(select) > 0
		nsrc = length(select);
	end
	
	if batchSize > nsrc
		batchSize = nsrc;
	end
	
	numBatches 	= ceil(Int64,nsrc/batchSize);
	
	# derivative of mass matrix
	
	## ALL AT ONCE CODE
	H = spzeros(ComplexF64,n,n);
	if isa(Ainv,ShiftedLaplacianMultigridSolver)
		H = GetHelmholtzOperator(M,m,omega, gamma, true,useSommerfeldBC);
		Ainv.helmParam = HelmholtzParam(M,gamma,m,omega,true,useSommerfeldBC);
		H = H + GetHelmholtzShiftOP(m, omega,Ainv.shift[1]); 
		H = sparse(H');
		# H is actually shifted laplacian now...
	elseif isa(Ainv,JuliaSolver)
		H = GetHelmholtzOperator(M,m,omega, gamma, true,useSommerfeldBC);
	end
	
	Jv = zeros(ComplexF64,nrec,nsrc);
	t = ((1.0.-1im*vec(gamma./omega)).*v);
	# t = ((1.0.+1im*vec(gamma)).*v);
	for k_batch = 1:numBatches
		batchIdxs = (k_batch-1)*batchSize + 1 : min(k_batch*batchSize,nsrc);
		if pFor.useFilesForFields
			filename = getFieldsFileName(omega);
			file     = matopen(filename);
			U        = read(file,string("Ubatch_",k_batch));
			close(file);
		else
			U = pFor.Fields[:,batchIdxs];
		end
		U = t.*U;
		U,Ainv = solveLinearSystem(H,U,Ainv,0);
		Jv[:,batchIdxs] = omega^2*(P'*U);
	end
	
	# if isa(Ainv,ShiftedLaplacianMultigridSolver) 
		# Experimental: J does not necessarily needs to clear the setup.
		# clear!(Ainv.MG);
	# end
	

    return vec(Jv)
end


