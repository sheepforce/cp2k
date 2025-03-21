!--------------------------------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations                              !
!   Copyright 2000-2023 CP2K developers group <https://cp2k.org>                                   !
!                                                                                                  !
!   SPDX-License-Identifier: GPL-2.0-or-later                                                      !
!--------------------------------------------------------------------------------------------------!

! **************************************************************************************************
!> \brief builds the input structure for the VIBRATIONAL_ANALYSIS module
!> \par History
!>      01.2008 [tlaino] Teodoro Laino - University of Zurich
!>                       Creating an own module for vibrational analysis
!> \author [tlaino]
! **************************************************************************************************
MODULE input_cp2k_vib
   USE cp_output_handling,              ONLY: add_last_numeric,&
                                              cp_print_key_section_create,&
                                              debug_print_level,&
                                              low_print_level,&
                                              medium_print_level,&
                                              silent_print_level
   USE cp_units,                        ONLY: cp_unit_to_cp2k
   USE input_constants,                 ONLY: do_rep_blocked,&
                                              do_rep_interleaved,&
                                              ms_guess_atomic,&
                                              ms_guess_bfgs,&
                                              ms_guess_molden,&
                                              ms_guess_restart,&
                                              ms_guess_restart_vec
   USE input_keyword_types,             ONLY: keyword_create,&
                                              keyword_release,&
                                              keyword_type
   USE input_section_types,             ONLY: section_add_keyword,&
                                              section_add_subsection,&
                                              section_create,&
                                              section_release,&
                                              section_type
   USE input_val_types,                 ONLY: integer_t,&
                                              real_t
   USE kinds,                           ONLY: dp
   USE string_utilities,                ONLY: s2a
#include "../base/base_uses.f90"

   IMPLICIT NONE
   PRIVATE

   LOGICAL, PRIVATE, PARAMETER :: debug_this_module = .TRUE.
   CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'input_cp2k_vib'

   PUBLIC :: create_vib_section
CONTAINS

! **************************************************************************************************
!> \brief Creates the exteranal restart section
!> \param section the section to create
!> \author tlaino
! **************************************************************************************************
   SUBROUTINE create_vib_section(section)
      TYPE(section_type), POINTER                        :: section

      TYPE(keyword_type), POINTER                        :: keyword
      TYPE(section_type), POINTER                        :: subsection

      CPASSERT(.NOT. ASSOCIATED(section))
      CALL section_create( &
         section, __LOCATION__, name="VIBRATIONAL_ANALYSIS", &
         description="Section to setup parameters to perform a Normal Modes, vibrational, or phonon analysis. "// &
         "Vibrations are computed using finite differences, "// &
         "which implies a very tight (e.g. 1E-8) threshold is needed for EPS_SCF to get accurate low frequencies. "// &
         "The analysis assumes a stationary state (minimum or TS),"// &
         " i.e. tight geometry optimization (MAX_FORCE) is needed as well.", &
         n_keywords=1, n_subsections=0, repeats=.FALSE.)
      NULLIFY (keyword, subsection)

      CALL keyword_create(keyword, __LOCATION__, name="DX", &
                          description="Specify the increment to be used to construct the HESSIAN with "// &
                          "finite difference method", &
                          default_r_val=1.0E-2_dp, unit_str="bohr")
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="NPROC_REP", &
                          description="Specify the number of processors to be used per replica "// &
                          "environment (for parallel runs). "// &
                          "In case of mode selective calculations more than one replica will start"// &
                          " a block Davidson algorithm to track more than only one frequency", &
                          default_i_val=1)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="PROC_DIST_TYPE", &
                          description="Specify the topology of the mapping of processors into replicas.", &
                          usage="PROC_DIST_TYPE (INTERLEAVED|BLOCKED)", &
                          enum_c_vals=s2a("INTERLEAVED", &
                                          "BLOCKED"), &
                          enum_desc=s2a("Interleaved distribution", &
                                        "Blocked distribution"), &
                          enum_i_vals=(/do_rep_interleaved, do_rep_blocked/), &
                          default_i_val=do_rep_blocked)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="FULLY_PERIODIC", &
                          description="Avoids to clean rotations from the Hessian matrix.", &
                          default_l_val=.FALSE., lone_keyword_l_val=.TRUE.)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="INTENSITIES", &
                          description="Calculation of the IR/Raman-Intensities."// &
                          "Calculation of dipoles and/or polarizabilities have to be "// &
                          "specified explicitly in DFT/PRINT/MOMENTS and/or "// &
                          "PROPERTIES/LINRES/POLAR", &
                          default_l_val=.FALSE., lone_keyword_l_val=.TRUE.)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="THERMOCHEMISTRY", &
                          description="Calculation of the thermochemical data. Valid for molecules in the gas phase. ", &
                          default_l_val=.FALSE., lone_keyword_l_val=.TRUE.)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="TC_TEMPERATURE", &
                          description="Temperature for the calculation of the thermochemical data ", &
                          usage="tc_temperature 325.0", default_r_val=cp_unit_to_cp2k(value=273.150_dp, unit_str="K"), &
                          unit_str="K")
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="TC_PRESSURE", &
                          description="Pressure for the calculation of the thermochemical data  ", &
                          default_r_val=cp_unit_to_cp2k(value=101325.0_dp, unit_str="Pa"), unit_str="Pa")
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL create_mode_selective_section(subsection)
      CALL section_add_subsection(section, subsection)
      CALL section_release(subsection)

      CALL create_print_vib_section(subsection)
      CALL section_add_subsection(section, subsection)
      CALL section_release(subsection)
   END SUBROUTINE create_vib_section

! **************************************************************************************************
!> \brief Create the print section for VIB
!> \param section the section to create
!> \author Teodoro Laino [tlaino] - 10.2008
! **************************************************************************************************
   SUBROUTINE create_print_vib_section(section)
      TYPE(section_type), POINTER                        :: section

      TYPE(keyword_type), POINTER                        :: keyword
      TYPE(section_type), POINTER                        :: print_key

      CPASSERT(.NOT. ASSOCIATED(section))
      CALL section_create(section, __LOCATION__, name="PRINT", &
                          description="Section controlling the print information during a vibrational "// &
                          "analysis.", n_keywords=1, n_subsections=0, repeats=.FALSE.)
      NULLIFY (keyword, print_key)

      CALL cp_print_key_section_create(print_key, __LOCATION__, "BANNER", &
                                       description="Controls the printing of the vibrational analysis banner", &
                                       print_level=low_print_level, common_iter_levels=1, &
                                       filename="__STD_OUT__")
      CALL section_add_subsection(section, print_key)
      CALL section_release(print_key)

      CALL cp_print_key_section_create(print_key, __LOCATION__, "PROGRAM_RUN_INFO", &
                                       description="Controls the printing basic info about the vibrational method", &
                                       print_level=medium_print_level, add_last=add_last_numeric, filename="__STD_OUT__")
      CALL section_add_subsection(section, print_key)
      CALL section_release(print_key)

      CALL cp_print_key_section_create(print_key, __LOCATION__, "MOLDEN_VIB", &
                                       description="Controls the printing for visualization in molden format", &
                                       print_level=low_print_level, add_last=add_last_numeric, filename="VIBRATIONS")
      CALL section_add_subsection(section, print_key)
      CALL section_release(print_key)

      CALL cp_print_key_section_create(print_key, __LOCATION__, "ROTATIONAL_INFO", &
                                       description="Controls the printing basic info during the cleaning of the "// &
                                       "rotational degrees of freedom.", &
                                       print_level=debug_print_level, add_last=add_last_numeric, filename="__STD_OUT__")
      ! Print_key keywords
      CALL keyword_create(keyword, __LOCATION__, name="COORDINATES", &
                          description="Prints atomic coordinates after rotation", &
                          default_l_val=.FALSE., lone_keyword_l_val=.TRUE.)
      CALL section_add_keyword(print_key, keyword)
      CALL keyword_release(keyword)
      CALL section_add_subsection(section, print_key)
      CALL section_release(print_key)

      CALL cp_print_key_section_create(print_key, __LOCATION__, "CARTESIAN_EIGS", &
                                       description="Controls the printing of Cartesian "// &
                                       "frequencies and eigenvectors of the Hessian used "// &
                                       "for initializing ensemble for MD calculations. "// &
                                       "This should always print to a file, and will not "// &
                                       "effect the same frequencies and eigenvectors printed "// &
                                       "in the main vibrational analysis output", &
                                       print_level=low_print_level, &
                                       add_last=add_last_numeric, &
                                       filename="VIBRATIONS")
      CALL keyword_create(keyword, __LOCATION__, name="BACKUP_COPIES", &
                          description="Specifies the maximum number of backup copies.", &
                          usage="BACKUP_COPIES {int}", &
                          default_i_val=1)
      CALL section_add_keyword(print_key, keyword)
      CALL keyword_release(keyword)
      CALL section_add_subsection(section, print_key)
      CALL section_release(print_key)

      CALL cp_print_key_section_create(print_key, __LOCATION__, name="NAMD_PRINT", &
                                       description="Adjust cartesian eigenvalues / vectors to NewtonX format.", &
                                       print_level=debug_print_level + 1, add_last=add_last_numeric, &
                                       filename="FullNormalizedCartesian")
      CALL keyword_create(keyword, __LOCATION__, name="BACKUP_COPIES", &
                          description="Specifies the maximum number of backup copies.", &
                          usage="BACKUP_COPIES {int}", &
                          default_i_val=1)
      CALL section_add_keyword(print_key, keyword)
      CALL keyword_release(keyword)
      CALL section_add_subsection(section, print_key)
      CALL section_release(print_key)

      CALL cp_print_key_section_create(print_key, __LOCATION__, "HESSIAN", &
                                       description="Write the Hessian matrix from a vibrational analysis calculation "// &
                                       "into a binary file.", &
                                       print_level=low_print_level, add_last=add_last_numeric, filename="Hessian")
      CALL section_add_subsection(section, print_key)
      CALL section_release(print_key)

   END SUBROUTINE create_print_vib_section

! **************************************************************************************************
!> \brief Create the input section for MODE selective
!> \param section the section to create
!> \author fschiff
! **************************************************************************************************
   SUBROUTINE create_mode_selective_section(section)
      TYPE(section_type), POINTER                        :: section

      TYPE(keyword_type), POINTER                        :: keyword
      TYPE(section_type), POINTER                        :: print_key, subsection

      NULLIFY (keyword, subsection, print_key)
      CPASSERT(.NOT. ASSOCIATED(section))
      CALL section_create(section, __LOCATION__, name="MODE_SELECTIVE", &
                          description="All parameters needed for to run a mode selective vibrational analysis. "// &
                          "The keywords FREQUENCY, RANGE, and the subsection INVOLVED_ATOMS are mutually exclusive.", &
                          n_keywords=8, n_subsections=1, repeats=.FALSE.)

      CALL keyword_create(keyword, __LOCATION__, name="FREQUENCY", &
                          description="value close to the expected value of the frequency to look for. "// &
                          "If the block Davidson algorithm is applied, the nrep closest frequencies are tracked. ", &
                          usage="FREQUENCY {REAL}", default_r_val=-1._dp)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="RANGE", &
                          description="Track modes in a given range of frequencies. "// &
                          "No warranty that the set of frequencies is complete.", &
                          usage="RANGE {REAL} {REAL}", &
                          n_var=-1, type_of_var=real_t)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="LOWEST_FREQUENCY", &
                          description="Lowest frequency mode to include when writing output. "// &
                          "Use a negative value to print imaginary frequencies. "// &
                          "Useful for visualizing the imaginary frequency along a reaction path coordinate "// &
                          "Depending on accuracy settings, the output might include spurious low frequency "// &
                          " imaginary modes which should be visually checked (see MOLDEN_VIB).", &
                          usage="LOWEST_FREQUENCY <REAL>", default_r_val=0.0_dp)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="ATOMS", &
                          description="Specifies the list of atoms which should be displaced for the Initial guess", &
                          usage="ATOMS {integer} {integer} .. {integer}", &
                          n_var=-1, type_of_var=integer_t)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="EPS_MAX_VAL", &
                          description="Convergence criterion for the davidson algorithm. Specifies the maximal value in the "// &
                          "residuum vectors ", &
                          usage="EPS_MAX_VAL {REAL}", default_r_val=5.0E-7_dp)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create( &
         keyword, __LOCATION__, name="EPS_NORM", &
         description="Convergence criterion for the davidson algorithm. Specifies the maximal value of the norm "// &
         "of the residuum vectors ", &
         usage="EPS_NORM {REAL}", default_r_val=2.0E-6_dp)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create( &
         keyword, __LOCATION__, name="INITIAL_GUESS", &
         description="The type of initial guess for the normal modes", &
         usage="INITIAL_GUESS BFGS_HESS", &
         default_i_val=ms_guess_atomic, &
         enum_c_vals=s2a("BFGS_HESS", "ATOMIC", "RESTART", "RESTART_VEC", "MOLDEN_RESTART"), &
         enum_desc=s2a("get the first displacement vector out of the BFGS approximate Hessian", &
                       "use random displacements for a set of atoms specified", &
                       "use data from MS_RESTART as initial guess", &
                       "use a vector from MS_RESTART, useful if you want to increase accurcy by changing functionals or basis", &
                       "use the .mol file of a former run, to restart a vector"// &
                       "(similar to Restart_vec, but a different file FORMAT is used)"), &
         enum_i_vals=(/ms_guess_bfgs, ms_guess_atomic, ms_guess_restart, ms_guess_restart_vec, ms_guess_molden/))
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create(keyword, __LOCATION__, name="RESTART_FILE_NAME", &
                          description="Specifies the name of the file used to create the restarted vectors", &
                          usage="RESTART_FILE_NAME {filename}", &
                          default_lc_val="")
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL create_involved_atoms_section(subsection)
      CALL section_add_subsection(section, subsection)
      CALL section_release(subsection)

      CALL section_create(subsection, __LOCATION__, name="PRINT", &
                          description="Controls the printing mode selective vibrational analysis", &
                          n_keywords=0, n_subsections=1, repeats=.TRUE.)

      CALL cp_print_key_section_create(print_key, __LOCATION__, "MS_RESTART", &
                                       description="Controls the printing of the Mode Selective Restart file.", &
                                       print_level=silent_print_level, common_iter_levels=1, &
                                       add_last=add_last_numeric, filename="")
      CALL section_add_subsection(subsection, print_key)
      CALL section_release(print_key)

      CALL section_add_subsection(section, subsection)
      CALL section_release(subsection)

   END SUBROUTINE create_mode_selective_section

! **************************************************************************************************
!> \brief Create the input section for Ivolved_atoms keyword in mode selective
!> \param section the section to create
!> \author fschiff
! **************************************************************************************************
   SUBROUTINE create_involved_atoms_section(section)
      TYPE(section_type), POINTER                        :: section

      TYPE(keyword_type), POINTER                        :: keyword

      NULLIFY (keyword)
      CPASSERT(.NOT. ASSOCIATED(section))
      CALL section_create( &
         section, __LOCATION__, name="INVOLVED_ATOMS", &
         description="All parameters needed for the tracking of modes dominated by the motion of selected atoms. "// &
         "Warning, if many atoms are involved, only low frequency modes are detected, "// &
         "since they are more delocalized and match the tracked eigenvector.", &
         n_keywords=2, n_subsections=0, repeats=.FALSE.)

      CALL keyword_create( &
         keyword, __LOCATION__, name="RANGE", &
         description=" Specifies the range of wavenumbers in which the modes related to the ATOMS have to be tracked. "// &
         " If not specified frequencies >400cm-1 will be used to avoid tracking of translational or rotational modes", &
         usage="RANGE {REAL} {REAL}", &
         n_var=-1, type_of_var=real_t)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

      CALL keyword_create( &
         keyword, __LOCATION__, name="INVOLVED_ATOMS", &
         description="Specifies the list of atoms on which the tracked eigenvector should have the highest value "// &
         "similar to looking for the vibration of a set of atoms", &
         usage="INVOLVED_ATOMS {integer} {integer} .. {integer}", &
         n_var=-1, type_of_var=integer_t)
      CALL section_add_keyword(section, keyword)
      CALL keyword_release(keyword)

   END SUBROUTINE create_involved_atoms_section

END MODULE input_cp2k_vib
