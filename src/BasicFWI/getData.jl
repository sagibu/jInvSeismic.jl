export getData

import jInv.ForwardShare.getData
function getData(m,pFor::BasicFWIparam,doClear::Bool=false)
    println("starting GetData5");
    tstart = time_ns();
    # extract pointers
    Mesh  = pFor.Mesh
    omega = pFor.omega
    gamma = pFor.gamma
    Q     = pFor.Sources
    P     = pFor.Receivers
    # Qo = pFor.originalSources

    nrec  = size(P,2)
    nsrc  = size(Q,2)
    nfreq = length(omega)

    # allocate space for data and fields
    D  = zeros(nrec,nsrc,nfreq)
    U  = zeros(ComplexF64,prod(Mesh.n.+1),nsrc,nfreq)

    # store factorizations
    LU = Array{Any}(undef, nfreq)
    for i=1:length(omega)
        H = getHelmholtzOperator(m,gamma,omega[i],Mesh)

        LU[i] = lu(H)
        for k=1:nsrc
            U[:,k,i] = LU[i]\Vector(Q[:,k])
            D[:,k,i] = real(P'*U[:,k,i])
        end
    end
    pFor.Ainv   = LU
    pFor.Fields = U
    tend = time_ns();
    println("Runtime of getData:");
    println((tend - tstart)/1.0e9);
    return D ,pFor
end
