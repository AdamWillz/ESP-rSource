C------------------------
          SUBROUTINE PLAN
C------------------------
#include "viewer.h"
#include "viewer.h2"
      COMMON/OUTIN/IUOUT,IUIN
      COMMON/SPAD/MMOD,LIMIT,LIMTTY
      integer menuchw,igl,igr,igt,igb,igw,igwh
      COMMON/VIEWPX/menuchw,igl,igr,igt,igb,igw,igwh
      integer ifs,itfs,imfs
      COMMON/GFONT/IFS,ITFS,IMFS
      character outs*80
#ifdef OSI
      integer igwid,igheight  ! for use with axiscale
      integer ipos,isize      ! for use with etlabel
      integer iupdown,isym    ! passed to etplot
      integer iigl,iigr,iigt,iigb,iigw,iigwh
#else
      integer*8 igwid,igheight  ! for use with axiscale
      integer*8 ipos,isize      ! for use with etlabel
      integer*8 iupdown,isym    ! passed to etplot
      integer*8 iigl,iigr,iigt,iigb,iigw,iigwh
#endif

      LOGICAL J1J2
      IF(MMOD.LT.0)RETURN

C Cast values for linescale.
      iigl=igl;iigr=igr;iigt=igt;iigb=igb;iigw=igw;iigwh=igwh

      call startbuffer()
      igwid=igw
      igheight=igwh
      call axiscale(igwid,igheight,XMN,XMX,YMN,YMX,xsc,ysc,sca,
     &  Xadd,Yadd)
      scap=sca*0.2
      addx=(FLOAT(igw)*0.4)/scap
      addy=(FLOAT(igwh)*0.4)/scap
      call linescale(iigl,addx,scap,iigb,addy,scap)

      X1=XMN-1.
      Y1=YMN-1.
      DO 40 I=1,NR

        J2=IREPU1(I)
        J3=IREPU2(I)

        X2=PUNT(J2,1)
        Y2=PUNT(J2,2)
        X3=PUNT(J3,1)
        Y3=PUNT(J3,2)
        J1J2=X2.EQ.X1 .AND. Y2.EQ.Y1
        IF(X3.EQ.X1 .AND. Y3.EQ.Y1)GOTO 30

        IF(J1J2)GOTO 10

        IF(X3.EQ.X2 .AND. Y3.EQ.Y2)GOTO 40

        iupdown=0
        isym=0
        CALL etplot(X2,Y2,iupdown,isym)
10      iupdown=1
        CALL etplot(X3,Y3,iupdown,isym)
20      X1=X3
        Y1=Y3
        GOTO 40

30      IF(J1J2)GOTO 40

        iupdown=1
        isym=0
        CALL etplot(X2,Y2,iupdown,isym)
        X1=X2
        Y1=Y2
40      CONTINUE

C   PRINT Z LIMITS
      write(outs,'(A,F6.2,A,F6.2)')'Zmin=',ZMNP,' Zmax=',ZMXP
      call edisp(iuout,outs)

C   LABEL PLAN WITH E,F,M
      IPLN=1
      ipos=0
      isize=ifs
      call etlabel('Eye',DDDD(1),DDDD(2),ipos,isize)
      call etlabel('F',CCCC(1),CCCC(2),ipos,isize)
      call etlabel('M',BBBB(1),BBBB(2),ipos,isize)
      call forceflush()

      RETURN
      END
