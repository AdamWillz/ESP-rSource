C ******* ESPrVersion
C Spit out ESP-r versioning information.
C
C  Arguement cVerbosity allows some control on the amount of detail 
C  provided: 
C    - 'summary' attempts to print release information, 
C    - 'details' prints versioning/build information.
C
C  But versioning/build information will be reported in all cases 
C  if the Install script has deemed this to be a 'development build'.

      subroutine ESPrVersion(cPassedType,cPassedAppName,iuout)
      implicit none
      
C PASSED VARIABLES 
      character cType*16            ! Flag indicating if version/build
                                    !  info should be dumped

      character cPassedAppName*(*)
      character cPassedType*(*)
      character cAppName*8           ! Name of current application
      integer iuout                  ! Output channel.

C LOCAL VARIABLES
C declare variables describing version and build information

      character cBuilder*32          ! User who compiled system
      character cArchitecture*32     ! Machine archictecture
      character cOperSystem*32       ! Operating system
      character cOSversion*32        ! OS flavour/version
      character cHost*256            ! Host name
      character cDate*64             ! Build date 
      logical   bVersioned           ! Flag indicating if repository 
                                     !   is versioned 
      logical bRelease               ! Logical indicating if this is 
                                     !   a release version.
      logical bBuild_Info            ! Flag indicating if build info should 
                                     !   be dumped. 
      logical bModified              ! Flag indicating local copy contains 
                                     !   modifications
      character cRelease_Num*8       ! Release version
      character cBase*8              ! Base version
      character cURL*256             ! Repository URL
      character cSource*32           ! Repository version
      character cBranch*48           ! Branch name 
      character cRevision*32         ! Revision number 
      character cState*32            ! Flag indicating repository state.
      character cCC*32               ! Flags for compilers
      character cFC*32               !
      character cCPL*32              !
      character cXML_support*32      ! Flags for compile-time options
      character cXlibrary*32         !
      
      character cTemp_a*124, cTemp_b*124 ! Temporary strings
      integer iLen
      
C Arrays mapping binary names to longer descriptions
      
      integer iBinCount
      parameter (iBinCount=22)
      
      character cBinNames*8
      character cBinDesc*72 
      dimension cBinNames(iBinCount)
      dimension cBinDesc(iBinCount)
      
      integer iBinIndex, iCurIndex
      character*3 cXLibs

      data cBinNames / 'aco', 'b2e', 'bps', 'dbm', 'dfs', 'c2e', 'cfg',
     &                 'clm', 'e2r', 'ecnv', 'eco', 'grd', 'ish', 'mfs',
     &                 'mld', 'mrt', 'net', 'pdb', 'prj', 'res', 'tdf', 
     &                 'vew' /
      
      
      data cBinDesc / 'Acoustics Analysis Module',
     &                'BEMS link',
     &                'Integrated Building Performance Simulator',
     &                'Database Manager',
     &                'Domain Flow Solver',
     &                ' ',
     &                'Topology Tool',
     &                'Climate Analysist Tool',
     &                'Radiance link',
     &                'Data Conversion Utility',
     &                ' ',
     &                'Construction Gridding Tool',
     &                'Shading Analysis Tool',
     &                'Mass Flow Solver',
     &                'Mould analysis tool',
     &                'Mean Radiant Temperature Module',
     &                'Network tool',
     &                'Plant Database Tool',
     &                'Project Manager',
     &                'Results Analysis Tool',
     &                'Temporal Definition Tool',
     &                'Hidden Line Viewer' /
     
      save cBinNames, cBinDesc
      
C References:
      integer lnblnk
      logical rep_xmlstatus
      
C include dynamically-created installation information. 
#include "build_info.h"

C Store passed application name and type in arrays of known
C length.
      iLen = lnblnk ( cPassedAppName )
      write (cAppName, '(A)' ) cPassedAppName( 1:MIN(iLen,8) )

      iLen = lnblnk ( cPassedType )
      write (cType, '(A)') cPassedType( 1:MIN(iLen,16) )

C Deterimine of summary or details 
      if ( cType(1:7) == "details" ) then
        bBuild_Info = .true.
      elseif ( cType(1:7) == "summary" ) then
        bBuild_Info = .false. 
      else
C cType is set programmically,
C and needs only rudementry error trapping.
        STOP " Arguement to ESPrVersion must be 'summary' or 'details'"
      endif 

C Determine index of current application in cBinNames/cBinDesc arrays      
      do iCurIndex = 1, iBinCount
      
        if ( cAppName(1:lnblnk(cAppName)) .eq. 
     &       cBinNames(iCurIndex)(1:lnblnk(cBinNames(iCurIndex)))) then 
          
          iBinIndex = iCurIndex
          
        endif 
      enddo

     
C Write out header ('ESP-r XYZ tool (xyx)'). 
C  e.g.: 'ESP-r integrated builing performance simulator (bps)'
      
      
C.....ESP-r banner 
      if ( bRelease ) then 
C.......Release version        
        write(cTemp_a,'(A,A,A,A,A,A,A)') 
     &       "ESP-r ", 
     &       cBinDesc(iBinIndex)(1:lnblnk(cBinDesc(iBinIndex))), 
     &       " (",
     &       cAppName(1:lnblnk(cAppName)),
     &       ") Release ", 
     &       cRelease_Num(1:lnblnk(cRelease_Num)),
     &       "."
        call edisp(iuout,cTemp_a)      
      
      else 
        
        write(cTemp_a,'(A,A,A,A,A)') "ESP-r ", 
     &       cBinDesc(iBinIndex)(1:lnblnk(cBinDesc(iBinIndex))), " (",
     &       cAppName(1:lnblnk(cAppName)),
     &       ")."
        call edisp(iuout,cTemp_a)      
        
        write(cTemp_a,'(A,A,A,A,A,A)') "This is a development copy of ", 
     &       cAppName(1:lnblnk(cAppName)),
     &       ", based on ESP-r release ",
     &       cRelease_Num(1:lnblnk(cRelease_Num)),"."
        call edisp(iuout,cTemp_a)    
        
      endif 
      
      
      
C Copyright information:
      call edisp(iuout," ")      
      write(cTemp_a,'(A)') 
     &  "Copyright 2001-2007 Energy Systems Research Unit."
      
      call edisp(iuout,cTemp_a)      

C Check if source was versioned (that is, was svn available, and 
C is it a working copy)
      if ( .not. bVersioned ) then     
C.......Write out non-versioned disclaimer.        
        
        call edisp(iuout," ")
       
        write (cTemp_a,'(A)') 
     &  "This copy of ESP-r is not under versioning control. Using un-"

        call edisp(iuout,cTemp_a)
        
        write (cTemp_a,'(A)') 
     &  "versioned copies of ESP-r may prevent you from reconstituting"
        call edisp(iuout,cTemp_a)
        
        write (cTemp_a,'(A)') 
     &  "models and reproducing simulation results in the future. "
        call edisp(iuout,cTemp_a)
        
        write (cTemp_a,'(A)') 
     &  "Development using unversioned copies of ESP-r is also prone to"
        call edisp(iuout,cTemp_a)
        
        write (cTemp_a,'(A)') 
     &  "error, and strongly discouraged."
        call edisp(iuout,cTemp_a)
        
        call edisp(iuout," ")
        
        write (cTemp_a,'(A)') 
     &  "You can obtain a versioned copy of ESP-r here:"
        call edisp(iuout,cTemp_a)
        
        call edisp(iuout," ")
        
        write (cTemp_a,'(A)') 
     &  "   http://www.esru.strath.ac.uk/Programs/ESP-r_central.htm"
        call edisp(iuout,cTemp_a)
              
      endif 
      
      if ( bBuild_Info .or. .not. bRelease ) then 
C. .....Information about build:
        call edisp(iuout," ")
                 
                    
          write (cTemp_a,'(A)') "Build information:"
          call edisp(iuout,cTemp_a)
        
C.........Source code version:
C............' - Source:    BRANCH @ rXYZ (modified state)'
          
          if ( bVersioned ) then 
            
            write (cTemp_a,'(A,A,A,A,A)') 
     &       "  - SVN Source:       ",
     &       cBranch(1:lnblnk(cBranch)), 
     &       "@r",
     &       cRevision(1:lnblnk(cRevision))
  
            if ( bModified ) then
              write (cTemp_a,'(A,A)') cTemp_a(1:lnblnk(cTemp_a)),
     &         " (locally modified)"
            else 
              write (cTemp_a,'(A,A)') cTemp_a(1:lnblnk(cTemp_a)),
     &         " (unmodified)"
            endif
             
             
            else
              write (cTemp_a,'(A)') 
     &       "  - SVN Source:       UNKNOWN"
            endif 
          call edisp(iuout,cTemp_a)      
          
C.........Build Platform (e.g.: i686:LINUX:2.6.9-gentoo-r1)
          write (cTemp_a,'(A,A,A,A,A,A)')   "  - Platform:         ",
     &         cArchitecture(1:lnblnk(cArchitecture)),":",
     &         cOperSystem(1:lnblnk(cOperSystem)),":",
     &         cOSversion(1:lnblnk(cOSversion))
          call edisp(iuout,cTemp_a)      
         
C.........Compiliers ( eg: gcc/g++/g77)
          write (cTemp_a,'(A,A,A,A,A,A)')   "  - Compilers:        ",
     &         cCC(1:lnblnk(cCC)),"/",
     &         cCPL(1:lnblnk(cCPL)),"/",
     &         cFC(1:lnblnk(cFC))
        call edisp(iuout,cTemp_a)


        call getXlibs(cXlibs)
        
        write (cTemp_a,'(A,A)')   "  - Graphics Library: ",
     &         cXLibs(1:3)
        call edisp(iuout,cTemp_a)


        if ( rep_xmlstatus() ) then

          write (cXML_support, '(A)') "Supported"

        else

          write (cXML_support, '(A)') "Unsupported"

        endif 
        
        write (cTemp_a,'(A,A)')   "  - XML output:       ",
     &         cXML_support(1:lnblnk(cXML_support))
        call edisp(iuout,cTemp_a) 
        

          
      endif
      


      return
      end