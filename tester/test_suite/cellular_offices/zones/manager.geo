# geometry of manager defined in: ../zones/manager.geo
GEN  manager  manager describes cellular office  # type, name, descr
      24      11   0.000    # vertices, surfaces, rotation angle
#  X co-ord, Y co-ord, Z co-ord
      0.00000     0.00000     0.00000  # vert   1
      3.00000     0.00000     0.00000  # vert   2
      3.00000     4.50000     0.00000  # vert   3
      1.00000     4.50000     0.00000  # vert   4
      0.00000     4.50000     0.00000  # vert   5
      0.00000     0.00000     3.00000  # vert   6
      3.00000     0.00000     3.00000  # vert   7
      3.00000     4.50000     3.00000  # vert   8
      1.00000     4.50000     3.00000  # vert   9
      0.00000     4.50000     3.00000  # vert  10
      0.00000     0.00000     0.90000  # vert  11
      3.00000     0.00000     0.90000  # vert  12
      1.00000     0.00000     0.90000  # vert  13
      2.00000     0.00000     0.90000  # vert  14
      1.00000     0.00000     0.50000  # vert  15
      2.00000     0.00000     0.50000  # vert  16
      0.10000     0.00000     1.00000  # vert  17
      2.90000     0.00000     1.00000  # vert  18
      2.90000     0.00000     2.90000  # vert  19
      0.10000     0.00000     2.90000  # vert  20
      2.90000     4.50000     0.10000  # vert  21
      1.10000     4.50000     0.10000  # vert  22
      1.10000     4.50000     2.90000  # vert  23
      2.90000     4.50000     2.90000  # vert  24
# no of vertices followed by list of associated vert
   5,  2,  3,  8,  7, 12,
  10,  3,  4,  9,  8,  3, 21, 24, 23, 22, 21,
   4,  4,  5, 10,  9,
   5,  5,  1, 11,  6, 10,
   5,  6,  7,  8,  9, 10,
   5,  1,  5,  4,  3,  2,
   8,  1,  2, 12, 14, 16, 15, 13, 11,
   4, 15, 16, 14, 13,
  12, 11, 13, 14, 12,  7,  6, 11, 17, 20, 19, 18, 17,
   4, 17, 18, 19, 20,
   4, 21, 22, 23, 24,
# unused index
 0,0,0,0,0,0,0,0,0,0,0
# surfaces indentation (m)
 0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00
    3   0   0   0    # default insolation distribution
# surface attributes follow: 
# id  surface      geom  loc/  construction environment
# no  name         type  posn  name         other side
  1, pt_general    OPAQ  VERT  gyp_gyp_ptn  SIMILAR        
  2, part_frame    OPAQ  VERT  insul_frame  SIMILAR        
  3, door          OPAQ  VERT  door         SIMILAR        
  4, pt_other      OPAQ  VERT  gyp_gyp_ptn  SIMILAR        
  5, ceiling       OPAQ  CEIL  ceiling      SIMILAR        
  6, floor         OPAQ  FLOR  susp_flr_re  SIMILAR        
  7, spandral      OPAQ  VERT  extern_wall  EXTERIOR       
  8, vent          OPAQ  VERT  insul_frame  EXTERIOR       
  9, frame         OPAQ  VERT  insul_frame  EXTERIOR       
 10, glazing       TRAN  VERT  dbl_glz      EXTERIOR       
 11, part_glaz     TRAN  VERT  dbl_glz      SIMILAR        
# base
  6  0  0  0  0  0    13.50 0
