{ lib
, stdenv
, python3
, gfortran
, blas
, lapack
, fftw
, libint
, libvori
, libxc
, mpi
, gsl
, scalapack
, openssh
, makeWrapper
, libxsmm
, spglib
, which
, pkg-config
, plumed
, zlib
, enableElpa ? false
, elpa
, dbcsr
, fypp
, enable_sse3 ? stdenv.hostPlatform.sse3Support
, enable_ssse3 ? stdenv.hostPlatform.ssse3Support
, enable_sse4_1 ? stdenv.hostPlatform.sse4_1Support
, enable_sse4_2 ? stdenv.hostPlatform.sse4_2Support
, enable_sse4_a ? stdenv.hostPlatform.sse4_aSupport
, enable_avx ? stdenv.hostPlatform.avxSupport
, enable_avx2 ? stdenv.hostPlatform.avx2Support
, enable_avx512 ? stdenv.hostPlatform.avx512Support
, enable_aes ? stdenv.hostPlatform.aesSupport
, enable_fma ? stdenv.hostPlatform.fmaSupport
, enable_fma4 ? stdenv.hostPlatform.fma4Support
}:

let
  cp2kVersion = "psmp";
  arch = "Linux-x86-64-gfortran";

in
stdenv.mkDerivation rec {
  pname = "cp2k";
  version = "dev";

  #src = lib.cleanSource ../.;
  src = ../.;

  nativeBuildInputs = [ python3 which openssh makeWrapper pkg-config ];
  buildInputs = [
    gfortran
    fftw
    gsl
    libint
    libvori
    libxc
    libxsmm
    spglib
    scalapack
    blas
    lapack
    plumed
    zlib
  ] ++ lib.optional enableElpa elpa;

  propagatedBuildInputs = [ mpi ];
  propagatedUserEnvPkgs = [ mpi ];

  makeFlags = [
    "ARCH=${arch}"
    "VERSION=${cp2kVersion}"
  ];

  doCheck = true;

  enableParallelBuilding = true;

  postPatch = ''
    mkdir -p exts/dbcsr
    cp -r ${dbcsr.src}/* exts/dbcsr/. && chmod -R +rwx exts/dbcsr
    cp -r ${fypp.src}/* exts/dbcsr/tools/build_utils/fypp/. && chmod -R +rwx exts/dbcsr/tools/build_utils/fypp/

    patchShebangs tools exts/dbcsr/tools/build_utils exts/dbcsr/.cp2k
    substituteInPlace exts/build_dbcsr/Makefile \
      --replace '/usr/bin/env python3' '${python3}/bin/python' \
      --replace 'SHELL = /bin/sh' 'SHELL = bash'
  '';

  configurePhase = ''
    cat > arch/${arch}.${cp2kVersion} << EOF
    CC         = mpicc
    CPP        =
    FC         = mpif90
    LD         = mpif90
    AR         = ar -r
    DFLAGS     = -D__FFTW3 -D__LIBXC -D__LIBINT -D__parallel -D__SCALAPACK \
                 -D__MPI_VERSION=3 -D__F2008 -D__LIBXSMM -D__SPGLIB \
                 -D__MAX_CONTR=4 -D__LIBVORI ${lib.optionalString enableElpa "-D__ELPA"} \
                 -D__PLUMED2
    CFLAGS    = -fopenmp
    FCFLAGS    = \$(DFLAGS) -O2 -ffree-form -ffree-line-length-none \
                 -ftree-vectorize -funroll-loops -msse2 \
                 -std=f2008 \
                 -fopenmp -ftree-vectorize -funroll-loops \
                 -I${lib.getDev libxc}/include -I${lib.getDev libxsmm}/include \
                 -I${lib.getDev libint}/include ${lib.optionalString enableElpa "$(pkg-config --variable=fcflags elpa)"} \
                 ${lib.optionalString enable_sse3 "-msse3"} \
                 ${lib.optionalString enable_ssse3 "-mssse3"} \
                 ${lib.optionalString enable_sse4_1 "-msse4.1"} \
                 ${lib.optionalString enable_sse4_2 "-msse4.2"} \
                 ${lib.optionalString enable_sse4_a "-msse4a"} \
                 ${lib.optionalString enable_avx "-mavx"} \
                 ${lib.optionalString enable_avx2 "-mavx2"} \
                 ${lib.optionalString enable_avx512 "-mavx512"} \
                 ${lib.optionalString enable_aes "-maes"} \
                 ${lib.optionalString enable_fma "-mfma"} \
                 ${lib.optionalString enable_fma4 "-mfma4"}
    LIBS       = -lfftw3 -lfftw3_threads \
                 -lscalapack -lblas -llapack \
                 -lxcf03 -lxc -lxsmmf -lxsmm -lsymspg \
                 -lint2 -lstdc++ -lvori \
                 -lgomp -lpthread -lm \
                 -fopenmp ${lib.optionalString enableElpa "$(pkg-config --libs elpa)"} \
                 -lz -ldl -lstdc++ ${lib.optionalString (mpi.pname == "openmpi") "$(mpicxx --showme:link)"} \
                 -lplumed
    LDFLAGS    = \$(FCFLAGS) \$(LIBS)
    include ${plumed}/lib/plumed/src/lib/Plumed.inc
    EOF
  '';

  checkPhase = ''
    export OMP_NUM_THREADS=1

    export HYDRA_IFACE=lo  # Fix to make mpich run in a sandbox
    export OMPI_MCA_rmaps_base_oversubscribe=1
    export CP2K_DATA_DIR=data

    mpirun -np 2 exe/${arch}/libcp2k_unittest.${cp2kVersion}
  '';

  installPhase = ''
    mkdir -p $out/bin $out/share/cp2k

    cp exe/${arch}/* $out/bin

    for i in cp2k cp2k_shell graph; do
      wrapProgram $out/bin/$i.${cp2kVersion} \
        --set-default CP2K_DATA_DIR $out/share/cp2k
    done

    wrapProgram $out/bin/cp2k.popt \
      --set-default CP2K_DATA_DIR $out/share/cp2k \
      --set OMP_NUM_THREADS 1

    cp -r data/* $out/share/cp2k
  '';

  passthru = { inherit mpi; };

  meta = with lib; {
    description = "Quantum chemistry and solid state physics program";
    homepage = "https://www.cp2k.org";
    license = licenses.gpl2Plus;
    maintainers = [ maintainers.sheepforce ];
    platforms = [ "x86_64-linux" ];
  };
}
