C *********************************************************************************************

C ******************************* CHREM_Calculate_Building_Data *********************************
C
C Created by: Lukas Swan, based on Alex Fergusons 'H3K_transport_build_data'
C Created on: March 24, 2009
C Modified on: March 2010
C Copyright: Dalhousie University
C ________
C ABSTRACT:
C This is a very simple routine used to transport miscellanoues building data to the H3K
C reporting facilities. It duplicates most of the functionality found in CETC's h3k_report_data.F,
C but this redundancy is acceptable as we are generating results for our own use.
C
C
C**********************************************************************************************

      SUBROUTINE CHREM_Calculate_Building_Data(iZone)
       use h3kmodule
      IMPLICIT NONE	! require declaration of each variable

C HEADER FILES that define common variables (located in /include)
C parameters declaration for the building (e.g. array indexing)
#include "building.h"
C variables for use with AIM infiltration modeling
#include "aim2_common.h"
C parameter and variable declaration for control information (e.g. simplified plant control)
#include "control.h"

C parameters declaration for CFC (complex fenestration construction)
#include "CFC_common.h"

C.....PASSED VARIABLE from the calling subroutine /esrubps/bmatsv.F mznuma
      integer iZone ! Zone number

C.....COMMON VARIABLES
      common/c1/ncomp,ncon
      integer ncomp          ! # of zones in bld
      integer ncon           ! # of connections in bld

C.....Zone volumes.
      common/prec2/vol(mcom)
      real vol	! m^3


      common/c20/nzsur(mcom),nztv(mcom)
      integer nzsur           ! # of surfaces in a zone
      integer nztv            ! # of verticies in a zone (not used)

      common/prec9/nConst(mcom),nELts(mcom,ms),ngaps(mcom,ms),
     &             npgap(mcom,ms,mgp)
      integer nConst          ! # of surfaces per zone
      integer nELts           ! # number of layers per surface
      integer ngaps           ! # number of air gaps witin surface (not used)
      integer npgap           ! Location of air gap. (not used)

C TPA(MCOM),           ! - present zone air point temperature (oC)
C QPA(MCOM)            ! - zone air point heat injection (W)
      COMMON/PVALA/TPA(MCOM),QPA(MCOM)
      REAL TPA, QPA

C TFA(MCOM)            ! - future zone air point temperature (oC)
C QFA(MCOM)            ! - zone air point heat injection (W)
      COMMON/FVALA/TFA(MCOM),QFA(MCOM)
      REAL TFA, QFA

C TPC(MCOM,MS,MN),     ! - present zone surface node temperatures (oC)
C QPC(MCOM)            ! - total zone surface heat injection (W)
      COMMON/PVALC/TPC(MCOM,MS,MN),QPC(MCOM)
      REAL TPC, QPC

C TFC(MCOM,MS,MN),     ! - future zone surface node temperatures (oC)
C QFC(MCOM)            ! - total zone surface heat injection (W)
      COMMON/FVALC/TFC(MCOM,MS,MN),QFC(MCOM)
      REAL TFC, QFC

C TPS(MCOM,MS),        ! - present surface temperature (oC), inside
C QPS(MCOM)            ! - surface heat injection (W)
      COMMON/PVALS/TPS(MCOM,MS),QPS(MCOM)
      REAL TPS, QPS

C TFS(MCOM,MS),        ! - future surface temperature (oC)
C QFS(MCOM)            ! - surface heat injection (W)
      COMMON/FVALS/TFS(MCOM,MS),QFS(MCOM)
      REAL TFS, QFS

      COMMON/SETUQ/           ! PLANT heat injection/extration:
     &     QPLTP(MCOM),         !  - present (W)
     &     QPLTF(MCOM),         !  - future (W)
     &     CONV(MCOM)           !  - convective ratio
      real qpltp, qpltf, conv

C.....Climate data
      COMMON/CLIMI/QFP,QFF,TP,TF,QDP,QDF,VP,VF,DP,DF,HP,HF
C QFP Diffuse horizontal radiation - present time row
C QFF Diffuse horizontal radiation - future time row
C TP Ambient temperature - present time row
C TF Ambient temperature - future time row
C QDP Direct normal radiation - present time row
C QDF Direct normal radiation - future time row
C VP Wind velocity - present time row
C VF Wind velocity - future time row
C DP Wind direction - present time row
C DF Wind direction - future time row
C HP Relative humidity - present time row
C HF relative humidity - future time row
      REAL QFP,QFF,TP,TF,QDP,QDF,VP,VF,DP,DF,HP,HF


      COMMON/CasDat/            ! Building casual gains
     &     Cas_Rad_dat(MCOM),   !  - Radiant (W)
     &     Cas_Con_dat(MCOM),   !  - Convective (W)
     &     Cas_Lat_dat(MCOM)    !  - Latent (W)
      real Cas_Rad_dat, Cas_Con_dat, Cas_Lat_dat

C.....Window properties
      common/prectc/itmcfl(mcom,ms),tmct(mcom,mtmc,5),
     &       tmca(mcom,mtmc,me,5),tmcref(mcom,mtmc),tvtr(mcom,mtmc)
      real tmct, tmca, tmcref, tvtr
      integer itmcfl

C.....Description of zone control action; these data are used
C.....in H3Kreports to determine heating, cooling loads and
C.....to evaluate passive solar design performance.
      common/H3KReportsControl/bZoneHeated,   bZoneCooled,
     &                         fHeatSetpoint, fCoolSetpoint

C.....Flags indicating zone is heated, cooled.
      logical bZoneHeated(MCOM), bZoneCooled(MCOM)

C.....Heating and cooling setpoint (oC)
      real fHeatSetpoint(MCOM), fCoolSetpoint(MCOM)

C.....Ventilation, infiltration data
      common/coe39/cvip,cvvp,cvif,cvvf,qvnp,xx3,cvvpm,cvvfm
      real cvip, cvif           ! Conductances assoc. w/ infiltration
                                !   on present and future time rows
      real cvvp, cvvf           ! Conductances assoc. w/ ventilation
                                !   on present and future time rows
					! note that cvv? is for temperature difference between zones
      real qvnp,xx3,cvvpm,cvvfm ! Not used in current context
!	note that cvv?m is normalized to temperature difference between the zone and ambient

C.....Zone boundary conditions
      COMMON/ADJC/IE(MCOM,MS),ATP(MCOM,MS),ATF(MCOM,MS),ARP(MCOM,MS),
     &            ARF(MCOM,MS)

      integer IE                ! Indicates type of connection for zone
                                !   surfaces
      real ARF                  ! Future time-row radiation from
                                !   an external surface.
      real ATP,ATF,ARP          ! Not used in current context


C.....Surface Energy balances.
      common/SRFBAL/              ! Surface energy balances (W):
     &         qswrdi(MCOM,MS,2), !  - INT face: radiation: short-wave
     &         qlwrdi(MCOM,MS,2), !                         long-wave
     &         qconvi(MCOM,MS,2), !              convection
     &         qcondi(MCOM,MS,2), !              conduction ?
     &         qstori(MCOM,MS,2), !              storage ?
     &         qcri(MCOM,MS,2),   !              radiation: casual gains
     &         qpltri(MCOM,MS,2), !              radiation: plant comp.
     &         qstore(MCOM,MS,2), !              energy stored ?
     &         qconde(MCOM,MS,2), !  - EXT face: conduction
     &         qconve(MCOM,MS,2), !              convection
     &         qlwrde(MCOM,MS,2), !              radiation: long-wave to ground
     &         qlwrbd(MCOM,MS,2), !                         long-wave to buildings
     &         qlwrsk(MCOM,MS,2), !                         long-wave to sky
     &         qswrde(MCOM,MS,2)  !                         short wave

      real qswrdi, qlwrdi, qconvi, qcondi, qstori, qcri, qpltri, qstore,
     &     qconde, qconve, qlwrde, qlwrbd, qlwrsk, qswrde


C.....MLC data
      common/gr1d01/nnds,nndz(mcom),nndc(mcom,ms),nndl(mcom,ms,me)
      integer nnds             ! - # of nodes per: building
      integer nndz             !                   zone
      integer nndc             !                   construction
      integer nndl             !                   layer

C.....Thermal characteristics of MLC layers
      common/vthp14/thrmli(mcom,ms,me,7)
      real ThrMlI

      common/vthp22/thconf(ms,mn),thdnsf(ms,mhcv),thcapf(ms,mhcv)
      real thconf                    ! Thermal conductivity of layers.
      real thdnsf, thcapf            ! Not used in this context

C.....Flags for temperature-dependence of MLC themal properties
      common/vthp32/ivthps,ivthpz(mcom)
      logical ivthps, ivthpz

C.....Surface area data
      common/prec1/sna(mcom,ms),zoa(mcom)
      real sna                 ! Area of a surface
      real zoa                 ! Total surface area for zone

      common/cctl/icascf(mcom)  ! Zone control type
      integer icascf


      COMMON/PERS/ISD1,ISM1,ISD2,ISM2,ISDS,ISDF,NTSTEP
      Integer ISD1,ISM1,ISD2,ISM2,ISDS,ISDF,NTSTEP


C Common block for the window model.           
      COMMON/WindowControl/
     &     fWindowSetpoint,
     &     fACSetPoint, 
     &     bWindowControlFlag,
     &     iWindowControlZone,
     &     bWindowsAreOpen,
     &     fDeltaTInttoExt,
     &     fWindowLowSetpoint


C     Exterior Temperature at which and below the windows could open.  
      REAL fWindowSetpoint
C     The AC Temperature setpoint. 
      REAL fACSetPoint
C     The zone at which the temperature is controlled against.
      INTEGER iWindowControlZone
C     The flag which indicates the window feature is active.
      LOGICAL bWindowControlFlag
C     Common block variable to tell other routines that the windows are open. 
C     (This saves processor time)
      LOGICAL bWindowsAreOpen
C     The DeltaT that is used to detemine if cooling can be used from the outside.
C     Thus Windows could be open when DeltaT >= Zone Temp - ExteriorTemp
      REAL  fDeltaTInttoExt
C     The temperature at which and below that the windows remain closed.
C     This prevents the zone becoming too cold. 
      REAL fWindowLowSetpoint


C.....Local variables
      INTEGER i_ZnCtl           ! Zone control flag


      INTEGER iSurface, iNode,iViewSurface  ! Counters


C.....DECLARATIONS for H3Kreporting object
      CHARACTER*2   cZone_Chars, cSurf_Chars, cNode_Chars

C lnblnk is a function returning the index of last non-blank character in a string.
      INTEGER LNBLNK

C.....Timerows (named constants)
      integer iPresent, iFuture
      parameter (iPresent=1, iFuture=2)

c Common for the current and future hours of the simulation
      common/simtim/ihrp,ihrf,idyp,idyf,idwp,idwf,nsinc,its

      INTEGER ihrp,ihrf,idyp,idyf,idwp,idwf,nsinc,its


C----------------------------------------------------------------------
C     CHREM variables for storing average heat flux results per timestep
C     and indicators such as temperature
C     The use of average values allows for a zone energy balance (EB) to be determined
C     The summation of all average fluxes (e.g. conduction) and generation terms
C     over a timestep can be set equal to the change in stored energy (sensible and latent)
C     over the timestep (from present to future temperature).
C----------------------------------------------------------------------

C     Air-point components, convection, and generation
      real fZN_AP_AirSens ! Sensible heating of air mass

      real fZN_AP_Infil ! Uncontrolled ambient-zone heat advection (infiltration)
      real fZN_AP_AmbVent ! Controlled ambient-zone heat advection (mechanical ventilation and HVAC)
      real fZN_AP_ZnCpldVent ! Zone-coupled heat advection (defined in *.opr ventilation)
      Common /CHREM_AF/ ! Storage of present and future flow conductances to differentiate ambient-zone heat advection infiltration from mechanical ventilation
     &  fAF_AZ_Infil_Cond(MCOM,2), fAF_AZ_MechVent_Cond(MCOM,2)
      Real fAF_AZ_Infil_Cond, fAF_AZ_MechVent_Cond
      Real fTF_noZero, fTP_noZero ! Used to alter the ambient temperatures from 0 to 1 degree C as this is the normalization of zone-coupled heat advection coefficient CVV?M 

      real fZN_AP_ConvCasGain ! Casual gains - convective component
      COMMON/COE34D/QCASR(2),QCASC(2) ! Casual gain information - use convective only
      Real QCASR, QCASC

      real fZN_AP_Heat ! Active Heating
      real fZN_AP_Cool ! Active Cooling

      real fZN_O_Sens ! Sensible heating of opaque interior node
      real fZN_O_Cond ! Conduction of opaque interior node
      real fZN_O_SW ! Short wave absorptance of opaque interior node
      real fZN_O_Conv ! Convection of the opaque interior node
      real fZN_O_LWsurface ! LW to other surfaces of the opaque interior node
      real fZN_O_LWcasual ! LW casual gain of the opaque interior node
      real fZN_O_LWplant ! LW plant gain of the opaque interior node
      
      real fZN_T_Sens ! Sensible heating of transparent interior node
      real fZN_T_Cond ! Conduction of transparent interior node
      real fZN_T_SW ! Short wave absorptance of transparent interior node
      real fZN_T_Conv ! Convection of the transparent interior node
      real fZN_T_LWsurface ! LW to other surfaces of the transparent interior node
      real fZN_T_LWcasual ! LW casual gain of the transparent interior node
      real fZN_T_LWplant ! LW plant gain of the transparent interior node
      real fZN_T_LW_CFC_gen !LW due to CFC genereation

      Real AIRDEN ! used to call function in /esrucom/psychro.F

      Logical AreWindowsOpen

      Real flag_CFC ! if CFC used flag=1 otherwise flag=0
      
C----------------------------------------------------------------------
C     Check zone index. If iZone=1, re-zero running totals for
C     entire building.
C----------------------------------------------------------------------

      reset_building_totals: if ( iZone == 1 ) then


      endif reset_building_totals

C.....Pad zone index to 'XX'
      if ( iZone .gt. 9 ) then
         write (cZone_Chars,'(I2)') iZone
      else
        write (cZone_Chars,'(A,I1)') '0', iZone
      endif

       flag_CFC = 0.
C----------------------------------------------------------------------
C     CHREM Energy Balance calculations for the air-point
C----------------------------------------------------------------------
C     Determine the air point sensible heating over the timestep
!     Vol * rho * Cp * DeltaT * timesteps/h / 3600 s/h = (W)
      fZN_AP_AirSens = Vol(iZone) * 
     &  AIRDEN(TFA(iZone) + TPA(iZone) / 2) * 1006.
     &  * (TFA(iZone)- TPA(iZone)) * real(NTSTEP) / 3600.

C     Uncontrolled ambient-zone heat advection (infiltration)
      fZN_AP_Infil = (fAF_AZ_Infil_Cond(iZone,1) * (TP - TPA(iZone)) +
     &  fAF_AZ_Infil_Cond(iZone,2) * (TF - TFA(iZone))) / 2

C     Controlled ambient-zone heat advection (mechanical ventilation)
      fZN_AP_AmbVent = (fAF_AZ_MechVent_Cond(iZone,1) * 
     &  (TP - TPA(iZone))
     &  + fAF_AZ_MechVent_Cond(iZone,2) * (TF - TFA(iZone))) / 2

C     Zone-zone heat advection (called ventilation in the *.opr file)
      ! Set the following temperatures so they can be modified to account for 0 C as in the normalization procedure in MZVENT
      fTF_noZero=TF
      fTP_noZero=TP
      IF(ABS(fTF_noZero) .LT. 1.0E-15) fTF_noZero=1.
      IF(ABS(fTP_noZero) .LT. 1.0E-15) fTP_noZero=1.
      ! Calculate as per equations - see QZONE and MZLS3
      fZN_AP_ZnCpldVent =  (CVVPM * fTP_noZero - 
     &  CVVP * TPA(iZone) +
     &  CVVFM * fTF_noZero - 
     &  CVVF * TFA(iZone)) / 2

C     Casual gains - convective component only
      fZN_AP_ConvCasGain = (QCASC(1) + QCASC(2)) / 2



C-----------------------------------------------------------------------
C     COMPUTE INJECTED/EXTRACTED ENERGY TO MAINTAIN THE CONTROL STRATEGY

C.....Determine control function for current zone.
C.....The following code should determine the zone heat injection
C.....For each zone regardless of the mechanism used to inject the
C.....heat.
C-----------------------------------------------------------------------
      i_ZnCtl=icascf(iZone)
      
C     Reset the CHREM Energy Balance zone heating and cooling system convection to zero
      fZN_AP_Heat = 0.
      fZN_AP_Cool = 0.

      if(i_ZnCtl.ne.0)then

C If i_ZnCtl is non-zero then iban will be testable.
C Determine where heat is injected/extracted
        if ( iban(i_ZnCtl,2) .gt. 0 .and. iban(i_ZnCtl,3) .eq. 0 ) then

c PIN is at surface.
         ! Q_zone = QFS(iZone)

        elseif ( iban(i_ZnCtl,3) .gt. 0 ) then

C PIN is within construction
         ! Q_zone = QFC(iZone)

        elseif ( iban(i_ZnCtl,1) .eq. -1 ) then

C PIN is in a plant component node - not implemented yet.

        elseif ( iban(i_ZnCtl,1) .eq. -2 ) then

C PIN is mix of radiative/convective flux (ie - plant component)
        ! Q_zone = QPLTF(iZone)

        else

C PIN is air point
        !  Q_zone = QFA(iZone)

          ! Calculate the CHREM system flux
          if ((QFA(iZone) + QPA(iZone)) / 2 .gt. 0) then ! Heating
            fZN_AP_Heat = (QFA(iZone) + QPA(iZone)) / 2
          elseif ((QFA(iZone) + QPA(iZone)) / 2 .lt. 0) then ! Cooling
            fZN_AP_Cool = (QFA(iZone) + QPA(iZone)) / 2
          ! No else because the values were initialized to zero
          end if

        endif
      else

C A zone with no control 
       ! Q_zone = 0.0

      endif
!        write (*,*) "hour, day, zone, qpa, qfa",
!      &        ihrp, idyp, iZone, QPA(iZone), QFA(iZone)

C-----------------------------------------------------------------------
C     Reset the CHREM Energy Balance surface nodes
C-----------------------------------------------------------------------
      fZN_O_Sens = 0.
      fZN_O_Cond = 0.
      fZN_O_SW = 0.
      fZN_O_Conv = 0.
      fZN_O_LWsurface = 0.
      fZN_O_LWcasual = 0.
      fZN_O_LWplant = 0.
      
      fZN_T_Sens = 0.
      fZN_T_Cond = 0.
      fZN_T_SW = 0.
      fZN_T_Conv = 0.
      fZN_T_LWsurface = 0.
      fZN_T_LWcasual = 0.
      fZN_T_LWplant = 0.
      fZN_T_LW_CFC_gen = 0.


C-----------------------------------------------------------------------
C     Loop over surfaces
C-----------------------------------------------------------------------

      zone_surface_loop: do iSurface = 1, nzsur(iZone)

         check_for_window: if ( (itmcfl( iZone, iSurface ) == 0) .and. 
     &    (icfcfl( iZone, iSurface) == 0) ) then
        
C-----------------------------------------------------------------------
C         Store the CHREM Energy Balance OPAQUE surface nodes (see SURBAL)
C-----------------------------------------------------------------------
          ! Sensible heating
          fZN_O_Sens = fZN_O_Sens + qstori(iZone,iSurface,2) - 
     &      qstori(iZone,iSurface,1)
          ! Conduction
          fZN_O_Cond = fZN_O_Cond + (qcondi(iZone,iSurface,1) + 
     &      qcondi(iZone,iSurface,2)) / 2
          ! Convection
          fZN_O_Conv = fZN_O_Conv + (qconvi(iZone,iSurface,1) + 
     &      qconvi(iZone,iSurface,2)) / 2
          ! Short wave
          fZN_O_SW = fZN_O_SW + (qswrdi(iZone,iSurface,1) + 
     &      qswrdi(iZone,iSurface,2)) / 2
          ! Long wave to other surfaces
          fZN_O_LWsurface = fZN_O_LWsurface + 
     &      (qlwrdi(iZone,iSurface,1) + 
     &      qlwrdi(iZone,iSurface,2)) / 2
          ! Long wave from casual gains
          fZN_O_LWcasual = fZN_O_LWcasual + 
     &      (qcri(iZone,iSurface,1) + 
     &      qcri(iZone,iSurface,2)) / 2
          ! Long wave from plant
          fZN_O_LWplant = fZN_O_LWplant + 
     &      (qpltri(iZone,iSurface,1) + 
     &      qpltri(iZone,iSurface,2)) / 2

        else
C         TRANSPARENT SURFACES:
C-----------------------------------------------------------------------
C         Store the CHREM Energy Balance TRANSPARENT surface nodes (see SURBAL)
C-----------------------------------------------------------------------
          fZN_T_Sens = fZN_T_Sens + qstori(iZone,iSurface,2) - 
     &      qstori(iZone,iSurface,1)
          ! Conduction
          fZN_T_Cond = fZN_T_Cond + (qcondi(iZone,iSurface,1) + 
     &      qcondi(iZone,iSurface,2)) / 2
          ! Convection
          fZN_T_Conv = fZN_T_Conv + (qconvi(iZone,iSurface,1) + 
     &      qconvi(iZone,iSurface,2)) / 2
          ! Short wave
          fZN_T_SW = fZN_T_SW + (qswrdi(iZone,iSurface,1) + 
     &      qswrdi(iZone,iSurface,2)) / 2
          ! Long wave to other surfaces
          fZN_T_LWsurface = fZN_T_LWsurface + 
     &      (qlwrdi(iZone,iSurface,1) + 
     &      qlwrdi(iZone,iSurface,2)) / 2
          ! Long wave from casual gains
          fZN_T_LWcasual = fZN_T_LWcasual + 
     &      (qcri(iZone,iSurface,1) + 
     &      qcri(iZone,iSurface,2)) / 2
          ! Long wave from plant
          fZN_T_LWplant = fZN_T_LWplant + 
     &      (qpltri(iZone,iSurface,1) + 
     &      qpltri(iZone,iSurface,2)) / 2

	  check_for_CFC: if (icfcfl( iZone, iSurface) > 0) then
	      ! LW CFC generation term ( result of Resistance network balance)
	      flag_CFC = 1
              fZN_T_LW_CFC_gen = fZN_T_LW_CFC_gen + 
     &            ((qcfc_lw(iZone,iSurface,nndc(iZone,iSurface),1) +
     &             qcfc_lw(iZone,iSurface,nndc(iZone,iSurface),2)) / 2 )
     &             * SNA(iZone,iSurface)
          endif check_for_CFC

        endif check_for_window

      enddo zone_surface_loop

C-----------------------------------------------------------------------
C     Complete the CHREM Energy Balance Surface stored energy calculations by converting to an average flux
C-----------------------------------------------------------------------
!     Energy * timesteps/h / 3600 s/h = (W) 
      fZN_O_Sens = fZN_O_Sens * real(NTSTEP) / 3600.
      fZN_T_Sens = fZN_T_Sens * real(NTSTEP) / 3600.

C-----------------------------------------------------------------------
C      Store the CHREM values starting withe 'CHREM' for identification
C-----------------------------------------------------------------------

C     ZONE VARIABLES

C     Air point sensible
      call AddToReport(rvZNAPAirSens%Identifier,
     &    fZN_AP_AirSens, cZone_Chars)

C     Infiltration
      call AddToReport(
     & rvZNAPInfil%Identifier,
     & fZN_AP_Infil, cZone_Chars)

C     Controlled ambient ventilation
      call AddToReport (
     & rvZNAPAmbVent%Identifier,
     & fZN_AP_AmbVent, cZone_Chars)

C     Zone coupled ventilation
      call AddToReport (
     & rvZNAPZnCpldVent%Identifier,
     & fZN_AP_ZnCpldVent, cZone_Chars)


C     Casual gains - convective
      call AddToReport (
     & rvZNAPConvCasGain%Identifier,
     & fZN_AP_ConvCasGain, cZone_Chars)


C     Heating - air point
      call AddToReport (
     & rvZNAPHeat%Identifier,
     & fZN_AP_Heat, cZone_Chars)

C     Cooling - air point
      call AddToReport (
     & rvZNAPCool%Identifier,
     & fZN_AP_Cool, cZone_Chars)


C     Airpoint - convective to surfaces
      call AddToReport (
     & rvZNAPSurfConv%Identifier,
     & -(fZN_O_Conv + fZN_T_Conv), cZone_Chars)


C     Opaque sensible
      call AddToReport (
     & rvZNOPSens%Identifier,
     & fZN_O_Sens, cZone_Chars)

C     Opaque conduction
      call AddToReport (
     & rvZNOPCond%Identifier,
     & fZN_O_Cond, cZone_Chars)


C     Opaque SW
      call AddToReport (
     & rvZNOPSW%Identifier,
     & fZN_O_SW, cZone_Chars)


C     Opaque Convection
      call AddToReport (
     & rvZNOPConv%Identifier,
     & fZN_O_Conv, cZone_Chars)


C     Opaque LWsurface
      call AddToReport (
     & rvZNOPLWSurf%Identifier,
     & fZN_O_LWsurface, cZone_Chars)


C     Opaque LWcasual
      call AddToReport (
     & rvZNOPLWCas%Identifier,
     & fZN_O_LWcasual, cZone_Chars)


C     Opaque LWplant
      call AddToReport (
     & rvZNOPLWPlt%Identifier,
     & fZN_O_LWplant, cZone_Chars)

C     Transparent sensible
      call AddToReport (
     & rvZNTrSens%Identifier,
     & fZN_T_Sens, cZone_Chars)


C     Transparent conduction
      call AddToReport (
     & rvZNTrCond%Identifier,
     & fZN_T_Cond, cZone_Chars)


C     Transparent SW
      call AddToReport (
     & rvZNTrSW%Identifier,
     & fZN_T_SW, cZone_Chars)


C     Transparent Convection
      call AddToReport (
     & rvZNTrConv%Identifier,
     & fZN_T_Conv, cZone_Chars)


C     Transparent LWsurface
      call AddToReport (
     & rvZNTrLWSurf%Identifier,
     & fZN_T_LWsurface, cZone_Chars)


C     Transparent LWgeneration
      if (flag_CFC .eq. 1) then 
        call AddToReport (
     &   rvZNTrLWCFCGen%Identifier,
     &   fZN_T_LW_CFC_gen, cZone_Chars)

      end if

C     Transparent LWcasual
      call AddToReport (
     & rvZNTrLWCas%Identifier,
     & fZN_T_LWcasual, cZone_Chars)


C     Transparent LWplant
      call AddToReport (
     & rvZNTrLWPlt%Identifier,
     & fZN_T_LWplant, cZone_Chars)


C     Zone temperature
      call AddToReport (
     & rvZNAPTemp%Identifier,
     & (TPA(iZone) +  TFA(iZone)) / 2, cZone_Chars)


C     Zone window operation
      if (bWindowsAreOpen) then
        call AddToReport (
     &   rvWNDWOpen%Identifier,
     &   1., cZone_Chars)

      else
        call AddToReport (
     &   rvWNDWOpen%Identifier,
     &   0., cZone_Chars)

      endif

C     BUILDING VARIABLES
      if (iZone .eq. ncomp) then
      endif

C     CLIMATE VARIABLES
      if (iZone .eq. 1) then
C     Ambient temperature
        call AddToReport (
     &   rvAPAmbTemp%Identifier,
     &   (TP + TF) / 2)


C     Ambient temperature
        call AddToReport (
     &   rvAPAmbTempFut%Identifier,
     &   TF)

      endif




      RETURN ! return to calling subroutine
      END ! end of subroutine
