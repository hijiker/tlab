#include "types.h"
#include "dns_error.h"
#include "dns_const.h"

SUBROUTINE SCAL_MEAN(is, s, wrk1d,wrk2d,wrk3d)

  USE DNS_CONSTANTS, ONLY : efile, gfile
  USE DNS_GLOBAL, ONLY : g
  USE DNS_GLOBAL, ONLY : imax,jmax,kmax
  USE DNS_GLOBAL, ONLY : imode_flow, imode_sim
  USE DNS_GLOBAL, ONLY : pbg, rbg, tbg, sbg, qbg

#ifdef USE_MPI
  USE DNS_MPI
#endif

  IMPLICIT NONE

#include "integers.h"

  TINTEGER is
  TREAL, DIMENSION(imax,jmax,kmax), INTENT(OUT)   :: s
  TREAL, DIMENSION(*),              INTENT(INOUT) :: wrk3d
  TREAL, DIMENSION(imax,jmax,*),    INTENT(INOUT) :: wrk2d
  TREAL, DIMENSION(jmax,*),         INTENT(INOUT) :: wrk1d

! -------------------------------------------------------------------
  TINTEGER i, j, ij, k
  TREAL FLOW_SHEAR_TEMPORAL, FLOW_JET_TEMPORAL, ycenter, dummy
  EXTERNAL FLOW_SHEAR_TEMPORAL, FLOW_JET_TEMPORAL

! ###################################################################
! Isotropic case
! ###################################################################
  IF      ( imode_flow .EQ. DNS_FLOW_ISOTROPIC ) THEN
     s =  sbg(is)%mean + s

! ###################################################################
! Shear layer case
! ###################################################################
  ELSE IF ( imode_flow .EQ. DNS_FLOW_SHEAR     ) THEN
! -------------------------------------------------------------------
! Temporal
! -------------------------------------------------------------------
     IF      ( imode_sim .EQ. DNS_MODE_TEMPORAL ) THEN
        ycenter = g(2)%nodes(1) + g(2)%scale *sbg(is)%ymean
        DO j = 1,jmax
           dummy =  FLOW_SHEAR_TEMPORAL&
                (sbg(is)%type, sbg(is)%thick, sbg(is)%delta, sbg(is)%mean, ycenter, sbg(is)%parameters, g(2)%nodes(j))
           s(:,j,:) = dummy + s(:,j,:)
        ENDDO

! -------------------------------------------------------------------
! Spatial
! -------------------------------------------------------------------
     ELSE IF ( imode_sim .EQ. DNS_MODE_SPATIAL  ) THEN
        CALL IO_WRITE_ASCII(efile, 'SCAL_MEAN. Spatial shear layer undeveloped')
        CALL DNS_STOP(DNS_ERROR_UNDEVELOP)

     ENDIF

! ###################################################################
! Jet case
! ###################################################################
  ELSE IF ( imode_flow .EQ. DNS_FLOW_JET ) THEN
     ycenter = g(2)%nodes(1) + g(2)%scale *sbg(is)%ymean
     DO j = 1,jmax
        dummy =  FLOW_JET_TEMPORAL&
             (sbg(is)%type, sbg(is)%thick, sbg(is)%delta, sbg(is)%mean, sbg(is)%diam, ycenter, sbg(is)%parameters, g(2)%nodes(j))
! pilot to be added: ijet_pilot, rjet_pilot_thickness, XIST
        s(:,j,:) = dummy + s(:,j,:)
     ENDDO

! -------------------------------------------------------------------
! Spatial
! -------------------------------------------------------------------
     IF ( imode_sim .EQ. DNS_MODE_SPATIAL ) THEN

! temperature/mixture profile are given
        IF ( rbg%type .EQ. PROFILE_NONE ) THEN
#define rho_vi(j) wrk1d(j,1)
#define u_vi(j)   wrk1d(j,2)
#define z_vi(j)   wrk1d(j,3)
#define aux1(j)   wrk1d(j,4)
#define aux2(j)   wrk1d(j,5)
#define aux3(j)   wrk1d(j,6)
#define aux4(j)   wrk1d(j,7)
#define rho_loc(i,j) wrk2d(i,j,1)
#define p_loc(i,j)   wrk2d(i,j,2)
#define u_loc(i,j)   wrk2d(i,j,3)
#define v_loc(i,j)   wrk2d(i,j,4)
#define t_loc(i,j)   wrk2d(i,j,5)
! Inflow profile of scalar
           DO j = 1,jmax
              z_vi(j) = s(1,j,1)
           ENDDO

! Initialize density field
           rho_vi(1:jmax) = C_0_R
           ycenter = g(2)%nodes(1) + g(2)%scale *tbg%ymean
           DO j = 1,jmax
              dummy = FLOW_JET_TEMPORAL&
                   (tbg%type, tbg%thick, tbg%delta, tbg%mean, tbg%diam, ycenter, tbg%parameters, g(2)%nodes(j))
! pilot to be added: ijet_pilot, rjet_pilot_thickness, XIST
              DO i = 1,imax
                 t_loc(i,j) = dummy
              ENDDO
           ENDDO
! the species array here is wrong for multispecies case !!!
           DO ij = 1,imax*jmax
              p_loc(ij,1) = pbg%mean
           ENDDO
           CALL THERMO_THERMAL_DENSITY&
                (imax, jmax, i1, s, p_loc(1,1), t_loc(1,1), rho_loc(1,1))

! Inflow profile of density
           DO j = 1,jmax
              rho_vi(j) = rho_loc(1,j)
           ENDDO

! inflow profile of velocity
           u_vi(1:jmax) = C_0_R
           ycenter = g(2)%nodes(1) + g(2)%scale *qbg(1)%ymean
           DO j = 1,jmax
              u_vi(j) = FLOW_JET_TEMPORAL&
                   (qbg(1)%type, qbg(1)%thick, qbg(1)%delta, qbg(1)%mean, qbg(1)%diam, ycenter, qbg(1)%parameters, g(2)%nodes(j))
! pilot to be added: ijet_pilot, rjet_pilot_thickness, rjet_pilot_velocity
           ENDDO

! 2D distributions of density and velocity
           IF ( rbg%delta .NE. C_0_R ) THEN
              CALL FLOW_JET_SPATIAL_DENSITY(imax,jmax, &
                   tbg%type, tbg%thick, tbg%delta, tbg%mean, tbg%ymean, tbg%diam, tbg%parameters, &
                   qbg(1)%type, qbg(1)%thick, qbg(1)%delta, qbg(1)%mean, qbg(1)%ymean, qbg(1)%diam, qbg(1)%parameters, &
                   g(2)%scale, g(1)%nodes, g(2)%nodes, s,p_loc(1,1),rho_vi(1),u_vi(1),aux1(1),rho_loc(1,1), &
                   aux2(1), aux3(1), aux4(1))
           ENDIF
           ycenter = g(2)%nodes(1) + g(2)%scale *qbg(1)%ymean
           CALL FLOW_JET_SPATIAL_VELOCITY(imax,jmax, &
                qbg(1)%type, qbg(1)%thick, qbg(1)%delta, qbg(1)%mean, qbg(1)%diam, ycenter, &
                qbg(1)%parameters(1), qbg(1)%parameters(2), qbg(1)%parameters(3), &
                g(1)%nodes, g(2)%nodes, rho_vi(1), u_vi(1), rho_loc(1,1), u_loc(1,1), v_loc(1,1), aux1(1), wrk3d)
! 2D distribution of scalar
           ycenter = g(2)%nodes(1) + g(2)%scale *sbg(is)%ymean
           CALL FLOW_JET_SPATIAL_SCALAR(imax,jmax, &
                sbg(is)%type, sbg(is)%thick, sbg(is)%delta, sbg(is)%mean, sbg(is)%diam, sbg(is)%diam, ycenter, &
                sbg(is)%parameters(1), sbg(is)%parameters(2), sbg(is)%parameters(3), &
                g(1)%nodes, g(2)%nodes, rho_vi(1), u_vi(1), z_vi(1), rho_loc(1,1), u_loc(1,1), s, wrk3d)
           IF ( kmax .GT. 1 ) THEN
              DO k = 2,kmax
                 s(:,:,k) = s(:,:,1)
              ENDDO
           ENDIF
        ENDIF

     ENDIF

  ENDIF

  RETURN
END SUBROUTINE SCAL_MEAN
