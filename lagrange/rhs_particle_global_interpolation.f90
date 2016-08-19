#include "types.h"
#include "dns_error.h"
#include "dns_const.h"

!########################################################################
!# Tool/Library
!#
!########################################################################
!# DESCRIPTION
!#
!# Particle set as tracer.
!# Interpolation of particle velocity.
!# Here particles are inside the cpu grid.
!#
!########################################################################
!# ARGUMENTS 
!#
!########################################################################
SUBROUTINE  RHS_PARTICLE_GLOBAL_INTERPOLATION &
    (q,l_q,l_hq,y,wrk1d, txc, grid_start, grid_end)

USE DNS_GLOBAL, ONLY: imax,jmax,kmax,isize_field
USE DNS_CONSTANTS, ONLY : efile
USE DNS_GLOBAL, ONLY: imax_total,kmax_total,  isize_particle, inb_particle
USE DNS_GLOBAL, ONLY :  visc
USE LAGRANGE_GLOBAL, ONLY: particle_number, jmin_part ,inb_lag_aux_field, inb_lag_total_interp
USE LAGRANGE_GLOBAL, ONLY: ilagrange
USE THERMO_GLOBAL, ONLY : thermo_param
#ifdef USE_MPI
   USE DNS_MPI, ONLY: ims_pro_i, ims_pro_k, ims_pro
#endif

IMPLICIT NONE
#include "integers.h"

  TREAL, DIMENSION(*)                                 :: y
  TREAL, DIMENSION(imax,jmax,kmax,*)                  :: q
  TREAL, DIMENSION(isize_particle,inb_particle)       :: l_q,l_hq  !position and velocity
  TREAL, DIMENSION(*),intent(in)                      :: wrk1d
  TREAL, DIMENSION(imax,jmax,kmax, *)                 :: txc !Auxiliary arrays to calculate lagrange tendencies
  TREAL length_g_p(6), cube_g_p(4)
  TINTEGER  gridpoint(6)
  TINTEGER i, j, jloc, grid_start, grid_end
  TREAL particle_local_grid_posx, particle_local_grid_posy, particle_local_grid_posz
  TREAL, DIMENSION(inb_lag_total_interp) ::  interpolated_value
  TREAL delta_inv0, delta_inv2, delta_inv4

  IF  (kmax_total .NE. 1) THEN ! 3D case
  
    DO i=grid_start,grid_end !loop over all particles inside the grid (no halo)
    
#ifdef USE_MPI
      particle_local_grid_posx = l_q(i,1)/wrk1d(1) + 1 - ims_pro_i*imax
      particle_local_grid_posy = ((l_q(i,2)-y(jmin_part))/wrk1d(2))+jmin_part  
      particle_local_grid_posz = l_q(i,3)/wrk1d(3) + 1 - ims_pro_k*kmax
#else
      particle_local_grid_posx = l_q(i,1)/wrk1d(1) + 1 
      particle_local_grid_posy = ((l_q(i,2)-y(jmin_part))/wrk1d(2))+jmin_part  
      particle_local_grid_posz = l_q(i,3)/wrk1d(3) + 1
#endif
  
      !Calculating gridpoints AFTER particles are shifted
      gridpoint(1)= floor(particle_local_grid_posx)       !tracer position to the left (x1)
      gridpoint(2)= gridpoint(1)+1               !to the right (x2)
      gridpoint(3)= (floor((l_q(i,2)-y(jmin_part))/wrk1d(2)))+jmin_part       !to the bottom 
      gridpoint(4)= gridpoint(3)+1               !to the top (y2)
      gridpoint(5)= floor(particle_local_grid_posz)       !front side
      gridpoint(6)= gridpoint(5)+1               !back side
    
    
   
      ! ###################################################################
      ! Own Interpolation
      ! ###################################################################
        length_g_p(1)=particle_local_grid_posx - gridpoint(1)  !legnth x between x(i) and p
        length_g_p(2)=gridpoint(2) - particle_local_grid_posx
        length_g_p(3)=particle_local_grid_posy-gridpoint(3)
        length_g_p(4)=gridpoint(4)-particle_local_grid_posy
        length_g_p(5)=particle_local_grid_posz - gridpoint(5)  !length between z(i) and p
        length_g_p(6)=gridpoint(6) - particle_local_grid_posz  !length between z(i+1) and p
   
  
  
        cube_g_p(1)=length_g_p(1)*length_g_p(3) ! cubes
        cube_g_p(2)=length_g_p(1)*length_g_p(4) !  be carefull multiply other side cube of grid for correct interpolation
        cube_g_p(3)=length_g_p(4)*length_g_p(2)
        cube_g_p(4)=length_g_p(2)*length_g_p(3)
    
        !Safety check
        !cube_g_p(5)=cube_g_p(1)+cube_g_p(2)+cube_g_p(3)+cube_g_p(4)
        !IF  (cube_g_p(5) .GT. 1) THEN
        !    print*,'zu grosse wuerfel'
        !END IF
      
  
  
      ! ###################################################################
      ! Set the field arrays into the particle
      ! Two bilinear calculation for each k direction (gridpoint(5) and gridpoint(6)
      ! Then multipled by (1-length) for Trilinear aspect
      ! ###################################################################
  
        DO j = 1,3
           interpolated_value(j) = &
           ((cube_g_p(3)*q(gridpoint(1),gridpoint(3),gridpoint(5),j) &
                +cube_g_p(4)*q(gridpoint(1),gridpoint(4),gridpoint(5),j) &
                +cube_g_p(1)*q(gridpoint(2),gridpoint(4),gridpoint(5),j) &
                +cube_g_p(2)*q(gridpoint(2),gridpoint(3),gridpoint(5),j))*length_g_p(6)) &
                +((cube_g_p(3)*q(gridpoint(1),gridpoint(3),gridpoint(6),j) &
                +cube_g_p(4)*q(gridpoint(1),gridpoint(4),gridpoint(6),j) &
                +cube_g_p(1)*q(gridpoint(2),gridpoint(4),gridpoint(6),j) &
                +cube_g_p(2)*q(gridpoint(2),gridpoint(3),gridpoint(6),j))*length_g_p(5))
        ENDDO
         
        DO j = 4,inb_lag_total_interp
               jloc = j - 3  
           interpolated_value(j) =  &
           ((cube_g_p(3)*txc(gridpoint(1),gridpoint(3),gridpoint(5),jloc) &
                +cube_g_p(4)*txc(gridpoint(1),gridpoint(4),gridpoint(5),jloc) &
                +cube_g_p(1)*txc(gridpoint(2),gridpoint(4),gridpoint(5),jloc) &
                +cube_g_p(2)*txc(gridpoint(2),gridpoint(3),gridpoint(5),jloc))*length_g_p(6)) &
                +((cube_g_p(3)*txc(gridpoint(1),gridpoint(3),gridpoint(6),jloc) &
                +cube_g_p(4)*txc(gridpoint(1),gridpoint(4),gridpoint(6),jloc) &
                +cube_g_p(1)*txc(gridpoint(2),gridpoint(4),gridpoint(6),jloc) &
                +cube_g_p(2)*txc(gridpoint(2),gridpoint(3),gridpoint(6),jloc))*length_g_p(5))
        ENDDO
  
  ! ######################################################################
  !  Set the tendencies (in the future this can be optimized doing different cases in different loops)
  !  In this case it is assumed that the tendencies were send in the txc fields. Change it if this is not the case.
  !  This is the line to be changed if a new case is added (here and in the halo routines). The rest can be copy/paste.
  ! #####################################################################
 

      IF (ilagrange .EQ. LAG_TYPE_BIL_CLOUD_3 .OR. ilagrange .EQ. LAG_TYPE_BIL_CLOUD_4) THEN
        DO  j = 1,3
            l_hq(i,j) = l_hq(i,j) +  interpolated_value(j)
        ENDDO
        
        !interpolated_value(4) = equation without ds/dxi 
        !interpolated_value(5) = xi
        !interpolated_value(6) = evaporation/condensation term without d2s/dxi2 
        !interpolated_value(7) = radiation term without ds/dxi
      
        delta_inv0 = C_1_R/thermo_param(1)/thermo_param(3)
        delta_inv2 = -C_05_R/thermo_param(1)/thermo_param(3)
        delta_inv4 = -C_025_R/thermo_param(1)/thermo_param(3)


        l_hq(i,4) = l_hq(i,4) - interpolated_value(4)/(C_1_R + EXP(interpolated_value(5)*delta_inv0))

        l_hq(i,5) = l_hq(i,5)  & 
                    - interpolated_value(7)/(C_1_R + EXP(interpolated_value(5)*delta_inv0)) &
                    - interpolated_value(6)*delta_inv4/(COSH(interpolated_value(5)*delta_inv2)**2) 




      ELSE
        DO  j = 1,inb_particle
            l_hq(i,j) = l_hq(i,j) +  interpolated_value(j)
        ENDDO
      END IF
 
    END DO
    

 
  
  ELSE !2D case
  
   DO i=grid_start,grid_end !loop over all particles inside the grid (no halo)
    
#ifdef USE_MPI
      particle_local_grid_posx = l_q(i,1)/wrk1d(1) + 1 - ims_pro_i*imax
      particle_local_grid_posy = ((l_q(i,2)-y(jmin_part))/wrk1d(2))+jmin_part  
#else
      particle_local_grid_posx = l_q(i,1)/wrk1d(1) + 1 
      particle_local_grid_posy = ((l_q(i,2)-y(jmin_part))/wrk1d(2))+jmin_part  
#endif
  
      !Calculating gridpoints AFTER particles are shifted
      gridpoint(1)= floor(particle_local_grid_posx)       !tracer position to the left (x1)
      gridpoint(2)= gridpoint(1)+1               !to the right (x2)
      gridpoint(3)= (floor((l_q(i,2)-y(jmin_part))/wrk1d(2)))+jmin_part       !to the bottom 
      gridpoint(4)= gridpoint(3)+1               !to the top (y2)
      gridpoint(5)=1
      gridpoint(6)=1
   
      ! ###################################################################
      ! Own Interpolation
      ! ###################################################################
        length_g_p(1)=particle_local_grid_posx - gridpoint(1)  !legnth x between x(i) and p
        length_g_p(2)=gridpoint(2) - particle_local_grid_posx
        length_g_p(3)=particle_local_grid_posy-gridpoint(3)
        length_g_p(4)=gridpoint(4)-particle_local_grid_posy
  
  
        cube_g_p(1)=length_g_p(1)*length_g_p(3) ! cubes
        cube_g_p(2)=length_g_p(1)*length_g_p(4) !  be carefull multiply other side cube of grid for correct interpolation
        cube_g_p(3)=length_g_p(4)*length_g_p(2)
        cube_g_p(4)=length_g_p(2)*length_g_p(3)
    
        !Safety check
        !cube_g_p(5)=cube_g_p(1)+cube_g_p(2)+cube_g_p(3)+cube_g_p(4)
        !IF  (cube_g_p(5) .GT. 1) THEN
        !    print*,'zu grosse wuerfel'
        !END IF
      
  
  
      ! ###################################################################
      ! Two bilinear calculation for each k direction (gridpoint(5) and gridpoint(6)
      ! Then multipled by (1-length) for Trilinear aspect
      ! ###################################################################
     
        l_hq(i,3)=0
   
        DO j = 1,2
           interpolated_value(j) = &
                (cube_g_p(3)*q(gridpoint(1),gridpoint(3),gridpoint(5),j) &
                +cube_g_p(4)*q(gridpoint(1),gridpoint(4),gridpoint(5),j) &
                +cube_g_p(1)*q(gridpoint(2),gridpoint(4),gridpoint(5),j) &
                +cube_g_p(2)*q(gridpoint(2),gridpoint(3),gridpoint(5),j))        
        ENDDO
        
        interpolated_value(3)=0
         
        DO j = 4,inb_lag_total_interp
               jloc = j - 3  
           interpolated_value(j) =  &
                (cube_g_p(3)*txc(gridpoint(1),gridpoint(3),gridpoint(5),jloc) &
                +cube_g_p(4)*txc(gridpoint(1),gridpoint(4),gridpoint(5),jloc) &
                +cube_g_p(1)*txc(gridpoint(2),gridpoint(4),gridpoint(5),jloc) &
                +cube_g_p(2)*txc(gridpoint(2),gridpoint(3),gridpoint(5),jloc))
        ENDDO
  
  ! ######################################################################
  !  Set the tendencies (in the future this can be optimized doing different cases in different loops)
  !  In this case it is assumed that the tendencies were send in the txc fields. Change it if this is not the case.
  !  This is the line to be changed if a new case is added (here and in the halo routines). The rest can be copy/paste.
  ! #####################################################################
      

        IF (ilagrange .EQ. LAG_TYPE_BIL_CLOUD_3 .OR. ilagrange .EQ. LAG_TYPE_BIL_CLOUD_4) THEN
           DO  j = 1,3
              l_hq(i,j) = l_hq(i,j) +  interpolated_value(j)
           ENDDO
        
        !interpolated_value(4) = equation without ds/dxi 
        !interpolated_value(5) = xi
        !interpolated_value(6) = evaporation/condensation term without d2s/dxi2 
        !interpolated_value(7) = radiation term without ds/dxi
        
        delta_inv0 = C_1_R/thermo_param(1)/thermo_param(3)
        delta_inv2 = -C_05_R/thermo_param(1)/thermo_param(3)
        delta_inv4 = -C_025_R/thermo_param(1)/thermo_param(3)


        l_hq(i,4) = l_hq(i,4) - interpolated_value(4)/(C_1_R + EXP(interpolated_value(5)*delta_inv0))

        l_hq(i,5) = l_hq(i,5)  & 
                    - interpolated_value(7)/(C_1_R + EXP(interpolated_value(5)*delta_inv0)) &
                    - interpolated_value(6)*delta_inv4/(COSH(interpolated_value(5)*delta_inv2)**2) 



      ELSE
        DO  j = 1,inb_particle
            l_hq(i,j) = l_hq(i,j) +  interpolated_value(j)
        ENDDO
      END IF
 
     
    END DO

END IF

  
  RETURN
END SUBROUTINE RHS_PARTICLE_GLOBAL_INTERPOLATION
