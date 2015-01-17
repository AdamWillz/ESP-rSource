C This file is part of the ESP-r system.
C Copyright Carleton University 2011-2012.
C Please Contact Ian Beausoliel-Morrison for details
C concerning licensing.

C ESP-r is free software.  You can redistribute it and/or
C modify it under the terms of the GNU General Public
C License as published by the Free Software Foundation
C (version 2 or later).

C ESP-r is distributed in the hope that it will be useful
C but WITHOUT ANY WARRANTY; without even the implied
C warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
C PURPOSE. See the GNU General Public License for more
C details.

C You should have received a copy of the GNU General Public
C License along with ESP-r. If not, write to the Free
C Software Foundation, Inc., 59 Temple Place, Suite 330,
C Boston, MA 02111-1307 USA.

C************************************************************************************
C************************************************************************************
C MODULE COSIMSHARE
C *******************************************************************************
C This module contains the following variables related to the
C TRNSYS coupling component (TCC) in support of the co-simulation
C between ESP-r and TRNSYS:
C coSimNumSurf    The number of surface temperatures to be sent to TRNSYS from
C                 ESP-r.
C coSimZones      Array holding the zone numbers of the surfaces to be read
C coSimSurfs      Array holding the surface numbers of the surfaces to be read
C************************************************************************************
C************************************************************************************
      MODULE COSIMSHARE

      IMPLICIT NONE
      SAVE

      INTEGER coSimNumSurf
      ! Maximum surface temperatures that can be sent to the co-simulator
      INTEGER, PARAMETER :: maxSend = 20      
      INTEGER, DIMENSION(maxSend) :: coSimZones
      INTEGER, DIMENSION(maxSend) :: coSimSurfs

      END MODULE COSIMSHARE
      
C************************************************************************************
C************************************************************************************      