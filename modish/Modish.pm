# Modish, version 0.91.
use v5.14;
use Math::Trig;
use List::Util qw[ min max reduce shuffle any];
use List::MoreUtils qw(uniq);
use List::AllUtils qw(sum);
use Statistics::Basic qw(:all);
use Data::Dump qw(dump);
use Data::Dumper;
$Data::Dumper::Terse  = 1;
$Data::Dumper::Purity  = 1;
use Vector::Object3D::Polygon;
use Math::Polygon::Tree;
#use Parallel::ForkManager;
use Storable qw(lock_store lock_nstore lock_retrieve);
use feature 'say';
no strict;
no warnings;

# Modish is a program for modifying the shading factors in the ISH (shading and insolation) files of the ESP-r building performance simulation suite in order to make it take into account the solar reflections from obstructions.
# More precisely, modish brings into account the reflective effect of solar obstructions on solar gains in the ESP-r building models on the basis of irradiance ratios. Those ratios are obtained combining the direct radiation on a surface, calculated by the means of ESP-r and by the means of a raytracer (Radiance), and the total radiation on the same surface calculated by the means of the raytracer. Using proportions, the values of the total radiation to be input to ESP-r, and from it, the modifications to the shading coefficients needed to obtain that, are calculated.
#
# How the program works
# The effect of solar reflections is taken into account at each hour on the basis of the ratios between the irradiances measured at the models' surfaces in two transitiona, fictious model derived from the primary model.
# The irradiances are calculated by the means of Radiance and can be derived from two alternative sets of models (the choice between them has to be done in the configuration file "modish_defaults.pl"):
#
# 1)
# a) a model in which all the surfaces are reflective, excepted the obstructions, which are black;
# b) a model in which everything is reflective.
#
# 2)
# a) a model in which everything is black;
# b) a model in which all the surfaces are black, excepted the obstructions, which are reflective.
#
# The value given by 1 minus the irradiance ratios gives the diffuse shading factors that are put in the ISH file of the ESP-r model in place of the original values.
#
# The original ISH's ".shda" files are not substituted. Two new files are added in the "zone" folder of the ESP-r model: the ".mod.shda" file is usable by ESP-r. It features the newly calculated shading factors; the ".report.shda" file lists the original shading factors and, at the bottom, the irradiance ratios from which the new shading factors in the ".mod.shda" file have been derived. Note that when the radiation on a surface is increased, instead of decreased, as an effect of reflections on obstructions, the shading factor will be negative.
#
# To launch Modish the following command has to be issued:
#
# perl ./modish PATH_TO_THE_ESP-r_CONFIGURATION_FILE.cfg zone_number surface_1_number surface_2_number surface_n_number
#
# For example:
#
# perl ././Modish.pm /home/x/model/cfg/model.cfg 1 7 9 (which means: calculate for zone 1, surfaces 7 and 9.)
#
# The path of the ESP-r model configuration path has to be specified in full, like in the example above.
#
# In calculating the irradiance ratios, the program defaults to the following settings: diffuse reflections: 1 ; direct reflections: 7; surface grid: 2 x 2; direction vectors for each surface: 1 ; distance from the surface for calculating the irradiances: 0.01 (metres); ratio of the of the original shading factor to the "new" shading factor under which the new shading factor is used to substitute the original one in the ".shda" file. If this value is 0, it is inactive, there is no threshold.
# These defaults are a compromise between quality and speed. They can be overridden by preparing a "modish_defaults.pl" file and placing it in the same directory from which modish is called. In that directory,
# the files "fix.sh" and "perlfix.pl" must also be present, and "fix.sh" should be chmodded 755.
#
# The content of a configuration file for the present defaults, for example, would be constituted by the following line (note that after it a line of comment follows):
#
# @defaults = ( [  2, 2 ], 1, 1, 7, 0.01, 1 );### i.e ( [ resolution_x, resolution_y ], $dirvectorsnum, $bounceambnum, $bouncemaxnum, $distgrid, $threshold )
#
# The value "$dirvectorsnum" controls the numbers of direction vectors that are used for computing the irradiances at each point of each grid over the surfaces. The values that currently can be chosen are 1, 5 and 17. When the points are more than 1, they are evenly distributed on a hemisphere following a precalculated geodetic pattern.
# Modish works with no limitation of number of surfaces, it can be used with complex geometries and takes into account parent and child surfaces.
#
# For the program to work correctly, the materials, construction and optics databases must be local to the ESP-r model.
#
# Considerations on the efficiency of the program.
# The speed of the program largely depends on the number of times that the Radiance raytracer is called, which in turn depends on the resolution of the grid on the external surface which is being considered.
#
# One drawback of the procedure in question from the viewpoint of execution speed may seem to be that the number of calls to the raytracer is double the number of the grid points defined on the considered external surface(s) for taking into account the solar reflections from obstructions. But another implication of this strategy is that it makes possible to decouple the gridding resolution on the considered external surface(s) regarding the effect of direct and diffuse reflections from obstruction from those on: (a) the considered external surface(s), for what is aimed to calculating direct radiation; (b) the internal surfaces, as regards the insolation. This makes possible to adopt a low gridding resolution for the considered external surface(s) relative to the diffuse and specular solar reflections from obstructions while adopting a higher resolution for (a) and (b). Which entails that the calculations regarding the direct radiation, which are likely to be the most important quantitatively for determining the solar gains in the thermal zones, and which are much quicker to calculate than the ones performed by the raytracer (which are necessary for determining the amount of solar radiation reflected from obstructions) can be carried out with a higher resolution than those involved in the calculations of the raytracer, so as to avoid to slow down the calculations themselves by a considerable amount. The amount of computations spared in the described manner may be significant, because the gridding entailed in the calculations not requiring the raytracer is commonly in the order of tens (for example, 20 x 20), whilst a gridding suitable for the use of a raytracer in this kind of operation is commonly in the order of units (for example, 2 x 2).
#
# The alternative to this strategy would be that of calculating all the solar radiation explicitly by defining one only gridding density for each surface; one only for all the radiation components entailed: the direct one, the diffuse one, and the one (diffuse and specular) reflected from obstruction. But this would require a gridding resolution of compromise between the components. For this reason, the calculation efficiency of the Modish procedure is likely to be most of the times not lower, but rather higher, than the alternative one entirely relying on calls to a raytracer.
#
# Modish should work with Linux and the Mac.
#
# Author: Gian Luca Brunetti, Politecnico di Milano - gianluca.brunetti@polimi.it.
# All rights reserved, 2015-17.
# This is free software.  You can redistribute it and/or modify it under the terms of the
# GNU General Public License, version 3, as published by the Free Software Foundation.


my $max_processes = $main::max_processes;
if ( not ( defined( $max_processes ) ) ) { $max_processes = 1; }

if ( ( "$^O" eq "MSWin32" ) or ( "$^O" eq "MSWin64" ) )
{
  say "\nSorry, this function presently works only on Linux and OSX." and die;
}

my ( @zoneshds, @winsdata );
my ( %surfslist, %shdfileslist, %obsinfo );

my %days_inmonths = ( Jan => 15, Feb => 14, Mar => 15, Apr => 15, May => 15, Jun => 15, Jul => 15, Aug => 15, Sep => 15, Oct => 15, Nov => 15, Dec => 15 );
my %monthsnum = ( Jan => 1, Feb => 2, Mar => 3, Apr => 4, May => 5, Jun => 6, Jul => 7, Aug => 8, Sep => 9, Oct => 10, Nov => 11, Dec => 12 );

sub getmonthname
{
  my $monthnum = shift;

  my %monthsnames = ( 1 => "Jan" , 2 => "Feb", 3 => "Mar", 4 => "Apr", 5 => "May", 6 => "Jun", 7 => "Jul", 8 => "Aug", 9 => "Sep", 10 => "Oct", 11 => "Nov", 12 => "Dec" );
  my $monthname = $monthsnames{ "$monthnum" };
  return $monthname;
}

sub getmonthnum
{
  my $monthname = shift;
  my %monthsnums = ( Jan => 1, Feb => 2, Mar => 3, Apr => 4, May => 5, Jun => 6, Jul => 7, Aug => 8, Sep => 9, Oct => 10, Nov => 11, Dec => 12 );
  my $monthnum = $monthsnums{ "$monthname" };
  return $monthnum;
}

sub getconffilenames
{  # THIS GETS THE CONSTRUCTION AND MATERIALS FILES FROM THE CFG FILE. IT IS CALLED BY sub createfictitious
  my ($conffile, $path, $askedzonenum ) = @_;
  open ( CONFFILE, "$conffile") or die;
  my @lines = <CONFFILE>;

  close CONFFILE;
  my ($constrdbfile, $matdbfile);
  my @zonedata;
  my $semaphore;
  my $countline = 0;
  my $countzone = 0;
  foreach my $line (@lines)
  {
    my ($geofile, $constrfile, $shdfile, $zonenum_cfg );
    $readline = s/^\s+//;
    my @row = split(/\s+|,/, $line);
    if ($row[0] eq "*mlc")
    {
      $constrdbfile = $row[1];
      $constrdbfile =~ s/\.\.//;
      $constrdbfile = $path . $constrdbfile;
    }
    elsif ($row[0] eq "*mat")
    {
      $matdbfile = $row[1];
      $matdbfile =~ s/\.\.//;
      $matdbfile = $path . $matdbfile;
    }
    elsif ($row[0] eq "*zon")
    {
      $countzone++;
      my $zonenum = $row[1];
      if ( $zonenum eq $askedzonenum )
      {
        $semaphore = "yes";
        push ( @{$zonedata[$countzone -1]}, $zonenum );
      }
      else
      {
        $semaphore = "no";
      }
    }

    if ( ($row[0] eq "*geo") and ( $semaphore eq "yes" ) )
    {
      $geofile = $row[1];
      $geofile =~ s/\.\.//;
      $geofile = $path . $geofile;
      push ( @{$zonedata[ $countzone -1 ]}, $geofile );
    }
    elsif ( ($row[0] eq "*con") and ( $semaphore eq "yes" ) )
    {
      $constrfile = $row[1];
      $constrfile =~ s/\.\.//;
      $constrfile = $path . $constrfile;
      push ( @{$zonedata[ $countzone - 1 ]}, $constrfile );
    }
    elsif ( ( $row[0] eq "*isi") and ( $semaphore eq "yes" ) )
    {
      $shdfile = $row[1];
      $shdfile =~ s/\.\.//;
      $shdfile = $path . $shdfile;
      push ( @{$zonedata[ $countzone - 1 ]}, $shdfile );
    }
  }
  return ( $constrdbfile, $matdbfile, \@zonedata, \@lines );
}

sub createfictitiousfiles
{
  # THIS CREATES THE FILES FOR THE MODELS FEATURING FICTITIOUS QUALITIES AIMED TO THE MAIN Modish PROGRAM,
  # MODIFIES THE MATERIALS DB AS REQUESTED
  # _AND_ PREPARES THE CONFIGURATION FILES FOR THE FICTITIOUS MODELS
  my ($conffile, $path, $zonenum) = @_;
  my $conffile_f1 = $conffile;
  my ($flaggeo, $flagconstrdb, $flagmatdb, $flagconstr);
  $conffile_f1 =~ s/\.cfg/\_f1\.cfg/;
  my $conffile_f2 = $conffile;
  $conffile_f2 =~ s/\.cfg/\_f2\.cfg/;
  my $conffile_f3 = $conffile;
  $conffile_f3 =~ s/\.cfg/\_f3\.cfg/;
  `cp -R -f $conffile $conffile_f1\n`;
  `cp -R -f $conffile $conffile_f2\n`;
  `cp -R -f $conffile $conffile_f3\n`;

  my ($constrdbfile, $matdbfile, $zonedataref, $conflinesref) = getconffilenames($conffile, $path, $zonenum);
  my @zonedata = @$zonedataref;
  my @conflines = @$conflinesref;
  my (@originals, @fictitia1, @fictitia2, @fictitia3 );

  push ( @originals, $constrdbfile);

  my $constrdbfile_f = $constrdbfile;
  $constrdbfile_f = $constrdbfile . "_f" ;
  push ( @fictitia1, $constrdbfile_f);
  push ( @fictitia2, $constrdbfile_f);
  push ( @fictitia3, $constrdbfile_f);

  push ( @originals, $matdbfile);

  my $matdbfile_f1 = $matdbfile;
  $matdbfile_f1 = $matdbfile . "_f1";
  push ( @fictitia1, $matdbfile_f1 );

  my $matdbfile_f2 = $matdbfile;
  $matdbfile_f2 = $matdbfile . "_f2";
  push ( @fictitia2, $matdbfile_f2 );

  push ( @fictitia3, $matdbfile_f1 );


  foreach my $datum (@zonedata)
  {
    my ( @tempbox_original, @tempbox_fictitia1, @tempbox_fictitia2, @tempbox_fictitia3 );
    my @array = @$datum;
    my $geofile = $array[1];
    push ( @tempbox_originals, $geofile );

    my $geofile_f = $geofile;
    $geofile_f =~ s/\.geo/_f\.geo/;

    my $geofile_f3 = $geofile;
    $geofile_f3 =~ s/\.geo/_f3\.geo/;

    push ( @tempbox_fictitia1, $geofile_f);
    push ( @tempbox_fictitia2, $geofile_f);
    push ( @tempbox_fictitia3, $geofile_f3);

    my $constrfile = $array[2];
    push ( @tempbox_originals, $constrfile);

    my $constrfile_f1 = $constrfile;
    $constrfile_f1 =~ s/\.con/_f1\.con/;
    push ( @tempbox_fictitia1, $constrfile_f1);

    my $constrfile_f2 = $constrfile;
    $constrfile_f2 =~ s/\.con/_f2\.con/;
    push ( @tempbox_fictitia2, $constrfile_f2);

    push ( @tempbox_fictitia3, $constrfile_f1);

    `cp -R -f $constrfile $constrfile_f1\n`; $flagconstr = "y";
    `cp -R -f $constrfile $constrfile_f2\n`; $flagconstr = "y";

    my $shdfile = $array[3];
    push ( @tempbox_originals, $shdfile);
    push ( @tempbox_fictitia1, $shdfile);
    push ( @tempbox_fictitia2, $shdfile);
    push ( @tempbox_fictitia3, $shdfile);

    my $zonenum_cfg = $array[0];
    push ( @tempbox_originals, $zonenum_cfg);
    push ( @tempbox_fictitia1, $zonenum_cfg);
    push ( @tempbox_fictitia2, $zonenum_cfg);
    push ( @tempbox_fictitia3, $zonenum_cfg);

    push ( @originals, [ @tempbox_originals ] );
    push ( @fictitia1, [ @tempbox_fictitia1 ] );
    push ( @fictitia2, [ @tempbox_fictitia2 ] );
    push ( @fictitia3, [ @tempbox_fictitia3 ] );
  }

  my ( @correctlines, $addline );
  open ( CONFFILE_F1, ">$conffile_f1");
  my @conflines2 = @conflines;

  foreach my $line (@conflines)
  {
    my $counter = 0;
    foreach my $elt ( @fictitia1 )
    {
      if ( not ( ref($elt) ) )
      {
        my $original = $originals[$counter];
        $elt =~ s/$path//;
        $original =~ s/$path//;
        if ( $elt )
        {
          $line =~ s/$original/$elt/;
        }
      }
      else
      {
        my @elts = @$elt;
        my @originalelts = @{$originals[$counter]};
        my $count = 0;
        foreach my $el ( @elts )
        {
          my $original = $originalelts[$count];
          $el =~ s/$path//;
          $original =~ s/$path//;
          if ( $el )
          {
            $line =~ s/$original/$el/;
          }
          $count++;
        }
      }

      if ( ( $counter == 0 ) and ( not ( $line =~ /^\*/ ) ) )
      {
        open( CORRECTCONF, $conffile ) or die;
        @correctlines = <CORRECTCONF>;
        close CORRECTCONF;
      }

      if ( @correctlines )
      {
        $addline = /^(.)$correctlines[ $counter ]/;
        if ( $addline )
        {
          $line = $addline . $line;
        }
      }
      $counter++;
    }
    print CONFFILE_F1 $line;
  }
  close CONFFILE_F1;

  open ( CONFFILE_F2, ">$conffile_f2");
  foreach my $line (@conflines2)
  {
    my $counter = 0;
    foreach my $elt ( @fictitia2 )
    {
      if ( not ( ref($elt) ) )
      {
        my $original = $originals[$counter];
        $elt =~ s/$path//;
        $original =~ s/$path//;
        if ( $elt )
        {
          $line =~ s/$original/$elt/;
        }
      }
      else
      {
        my @elts = @$elt;
        my @originalelts = @{$originals[$counter]};
        my $count = 0;
        foreach my $el ( @elts )
        {
          my $original = $originalelts[$count];
          $el =~ s/$path//;
          $original =~ s/$path//;
          if ( $el )
          {
            $line =~ s/$original/$el/;
          }
          $count++;
        }
      }
      if ( @correctlines )
      {
        $addline = /^(.)$correctlines[ $counter ]/;
        if ( $addline )
        {
          $line = $addline . $line;
        }
      }
      $counter++;
    }
    print CONFFILE_F2 $line;
  }
  close CONFFILE_F2;

  open ( CONFFILE_F1, "$conffile_f1");
  my @conflines3 = <CONFFILE_F1>;
  close CONFFILE_F1;

  open ( CONFFILE_F3, ">$conffile_f3");
  my $count = 0;
  foreach my $line (@conflines3)
  {
    my $redflag;
    if ( $$conflines3[ $count + 1] =~ /^# block entities:/ )
    {
      $redflag = "yes";
    }
    if ( @correctlines )
    {
      $addline = /^(.)$correctlines[ $count ]/;
      if ( $addline )
      {
        $line = $addline . $line;
      }
    }
    unless ( $redflag eq "yes" )
    {
      unless ( $line =~ /^\*shad_calc,/ )
      {
        print CONFFILE_F3 $line;
      }
      else
      {
        print CONFFILE_F3 "*shad_calc,none  # no temporal shading requested\n";
      }
    }
    $count++;
  }
  close CONFFILE_F3;

  #setroot( $conffile_f1, $path, $debug );
  #setroot( $conffile_f2, $path, $debug );

  return ($conffile, $conffile_f1, $conffile_f2, $conffile_f3, $constrdbfile, $constrdbfile_f,
  $matdbfile, $matdbfile_f1, $matdbfile_f2, $flagconstrdb, $flagmatdb, $flaggeo, $flagconstr, [ @originals ], [ @fictitia1], [ @fictitia2 ] , [ @fictitia3 ] );
}

sub definepath
{
  # THIS DEFINES THE PATH STARTING FROM THE PATH OF THE CONFIGURATION FILE. IT IS CALLED FROM sub modish
  my $launchfile = shift;
  my $path = $launchfile;
  $path =~ s/\/cfg.+// ;
  return ( $path );
}

sub readgeofile
{  # THIS READS A GEO FILE TO GET THE DATA OF THE REQUESTED SURFACES
  my $geofile = $_[0];
  my @transpsurfs = @{$_[1]};
  my $zonenum = $_[2];
  open ( GEOFILE, "$geofile") or die;
  my @lines = <GEOFILE>;
  close GEOFILE;
  my ( @geofilestruct, @transpelts, @obs );
  my %datalist;
  my $countsurf = 0;
  foreach my $surfnum ( @transpsurfs )
  {
    foreach my $line (@lines)
    {
      my @elts = split(/\s+|,/, $line);
      if ( $elts[0] eq "\*surf")
      {
        my $surfname = $elts[1];
        my $surfnum = $elts[12];
        my $parent = $elts[3];
        my $constr = $elts[6];
        # THIS POPULATES THE VARIABLE %surfslist (HASH - DICTIONARY - ASSOCIATIVE ARRAY) LINKING ZONES, SURFACES NAMES AND SURFACE NUMBER:

        $surfslist{ $zonenum }{ $surfnum }{surfname} = $surfname;
        $surfslist{ $zonenum }{ $surfname }{surfnum} = $surfnum;
        $datalist{ $zonenum }{ $surfnum }{ surfname } = $surfname;
        $datalist{ $zonenum }{ $surfnum }{ parent } = $parent;
        $datalist{ $zonenum }{ $surfnum }{ constr } = $constr;
        $datalist{ $zonenum }{ $surfnum }{ surfnum } = $surfnum;
        $datalist{ $zonenum }{ $surfnum }{ geofile } = $geofile;
        unless ( $parent eq "-" )
        {
          my $parentnum = $surfslist{ $zonenum }{ $parent }{surfnum};
          push ( @{ $datalist{ $zonenum }{ children }{ $parentnum } }, $surfnum );
          @{ $datalist{ $zonenum }{ children }{ $parentnum } } = uniq( @{ $datalist{ $zonenum }{ children }{ $parentnum } } );
        }
      }

      if ( $elts[0] eq "\*vertex")
      {
        my $x =  $elts[1];
        my $y =  $elts[2];
        my $z =  $elts[3];
        my $vertnum =  $elts[5];
        $datalist{ $zonenum }{ vertex }{ $vertnum } = [ $x, $y, $z ];
      }

      if ( $elts[0] eq "\*edges")
      {
        my $surfnum = $elts[ $#surfnum ];
        my $border = scalar( @elts - 3 );
        my @vertnums = @elts[ 1..$border ];
        $datalist{ $zonenum }{ $surfnum }{ edges }{ $surfnum } = [ @vertnums ];
      }

      if ( ($elts[0] eq "\*surf") and ( $surfnum == $elts[12] ) )
      {
        my $surfname = $elts[1];
        my $parent = $elts[3];
        my $constr = $elts[6];
        my $surfnum = $elts[12];
        push (@transpelts, [ $surfname, $parent, $constr, $surfnum, $geofile, $zonenum ] );
      }

      if ($elts[0] eq "\*obs")
      {
        my $obsconstr = $elts[10];
        my $obsname = $elts[9];
        my $obsnum = $elts[13];
        push (@obs, [ $obsname, $obsconstr, $obsnum ] );
      }
      if ( $countsurf == 0 )
      {
        push ( @geofilestruct, [ @elts ] );
      }
    }
    $countsurf++;
  }

  foreach ( @geofilestruct )
  {
    my $obsmaterial = $_->[9];
    my $obsnumber = $_->[12];
    if ( ( $_->[0] eq "#" ) and ( $_->[1] eq "*obs" ) )
    {
      $semaphore = 1;
    }
    if ( ( $semaphore == 1) and ( $_->[0] eq "*obs" ) )
    {
      push ( @obsconstr,$obsmaterial = $_->[9] );
    }
    $obsinfo{ $obsnumber } = $obsnumber;
    $obsinfo{ $obsmaterial } = $obsmaterial;
  }
  my @obsconstrset = uniq( @obsconstr );

  return ( \@transpelts, \@geofilestruct, \%surfslist, \@obs, \@obsconstrset, \%datalist );
}

sub readverts
{
  # THIS READS THE VERTEX NUMBERS OF THE REQUESTED SURFACES IN A GEO FILE
  my @transpelts = @{$_[0]};
  my $geofile = $_[1];
  my @geodata = @{$_[2]};
  my %datalist = %{$_[3]};
  my @winselts;
  foreach my $transpelt (@transpelts)
  {
    my $surfname = $transpelt->[0];
    my $parent = $transpelt->[1];
    my $constr = $transpelt->[2];
    my $surfnum = $transpelt->[3];
    my $geofile = $transpelt->[4];
    my $zonenum = $transpelt->[5];
    my @winelts;
    foreach my $datum (@geodata)
    {
      my @data = @$datum;
      if ( ($data[0] eq "*edges") and ( $data[$#data] == $surfnum ) )
      {
        push ( @winelts, [ [ @data[ 2..( $#data - 2 ) ] ], $surfnum ] );
        my @surfverts = @data[ 2..( $#data - 2 ) ];
        $datalist{ $zonenum }{ $surfnum }{vertnums} = [ @surfverts ];
      }
    }
    push ( @winselts, [ @winelts ] );
  }
  return ( \@winselts, \%datalist );
}

sub readcoords
{
  # THIS READS THE COORDINATES OF THE REQUESTED VERTEX NUMBERS
  my ( $winseltsref, $geofile, $geodataref, $datalistref, $transpeltsref ) = @_;
  my @winselts = @$winseltsref;
  my @geodata = @$geodataref;
  my %datalist = %$datalistref;
  my @transpelts = @$transpeltsref;
  my @allcoords;
  my $count = 1;
  foreach my $winseltref (@winselts)
  {
    my @transpelt = @{ $transpelts[ $count -1 ] };
    my $zonenum = $transpelt[5];

    my @winselt = @$winseltref;
    my @vertnums = @{ $winselt[0][0] };
    my $surfnum = $winselt[0][1];
    my @coords;
    foreach my $num (@vertnums)
    {
      foreach my $datum (@geodata)
      {
        my @data = @$datum;
        if ( ($data[0] eq "*vertex") and ( $data[5] == $num ) )
        {
          push ( @coords, [ [ @data[ 1..3 ] ], $num ] );
          $datalist{ $zonenum }{ $num }{vertcoords} = [ @data[ 1..3 ] ];
        }
      }
    }
    push ( @allcoords, [ @coords ] );
    $count++;
  }
  return (\@allcoords, \%datalist );
}

sub getcorners
{
  # THIS PACKS THE X, Y, AND Z COORDINATES OF THE VERTICES OF THE REQUESTED SURFACES INTO SUBARRAYS
  my ( $winscoordsref, $winseltsref ) = @_;
  my @winscoords = @$winscoordsref;
  my @winselts = @$winseltsref;
  my @packsurfsdata;
  my $countsurf = 0;
  foreach $surfcoordsref ( @winscoords )
  {
    my @surfcoords = @$surfcoordsref;
    my ( @xdata, @ydata, @zdata );
    my @packsurfdata;
    my $surfnum = $winselts[$countsurf][0][1];
    foreach my $coordsetref (@surfcoords)
    {
      my @coordset = @$coordsetref;
      push (@xdata, $coordset[0][0]);
      push (@ydata, $coordset[0][1]);
      push (@zdata, $coordset[0][2]);
    }
    push (@packsurfdata, [ @xdata ], [ @ydata ], [ @zdata ], $surfnum  );
    push ( @packsurfsdata, [ @packsurfdata ] );
    $countsurf++;
  }
  return ( @packsurfsdata );
}

sub findextremes
{
  # THIS FINDS THE MAXIMA AND THE MINIMA FOR EACH COORDINATE FOR THE REQUESTED SURFACE
  my @xyzcoords = @_;
  my @surfsdata;
  foreach my $coordsdataref ( @xyzcoords )
  {
    my @coordsdata = @$coordsdataref;
    my $count = 0;
    my @surfdata;
    foreach $coordstyperef (@coordsdata)
    {
      if ($count < 3)
      {
        my @coordstype = @$coordstyperef;
        my $extreme1 = max(@coordstype);
        my $extreme2 = min(@coordstype);
        my $countpos = 0;
        my (@extreme1positions, @extreme2positions);
        foreach my $elt ( @coordstype )
        {
          if ( $elt ~~ $extreme1 )
          {
            push ( @extreme1positions, $countpos );
          }
          if ( $elt ~~ $extreme2 )
          {
            push ( @extreme2positions, $countpos );
          }
          $countpos++;
        }
        push ( @surfdata, [ [ $extreme1, [ @extreme1positions ] ], [ $extreme2, [ @extreme2positions ] ] ] );
        $count++;
      }
      else
      {
        if ( $surfdata[0][0][1] ~~ $surfdata[1][1][1] )
        {
          my $swap = $surfdata[1][1];
          $surfdata[1][1] = $surfdata[1][0];
          $surfdata[1][0] = $swap;
        }

        my $surfnum = $coordstyperef;
        push ( @surfdata, $surfnum );
      }
    }
    push (@surfsdata, [ @surfdata ] );
  }
  return ( @surfsdata );
}

sub makecoordsgrid
{
  # THIS FORMS A GRID OVER EACH REQUESTED SURFACE
  my ($extremesref, $resolutionsref, $dirsvectorsrefsref) = @_;
  my @extremesdata = @$extremesref;
  my @resolutions = @$resolutionsref;
  my @dirsvectorsrefs = @$dirsvectorsrefsref;
  my @wholegrid;
  my $countsurf = 0;
  foreach my $surfcase ( @extremesdata )
  {
    my $dirsvectorsref = $dirsvectorsrefs[$countsurf];
    my @surfdata = @$surfcase;
    my $surf = pop @surfdata;
    my @coordspoints;
    my $count = 0;
    foreach ( @surfdata )
    {
      my $extreme1 = $_->[0][0];
      my $extreme2 = $_->[1][0];
      my @extreme1positions = @{$_->[0][1]};
      my @extreme2positions = @{$_->[1][1]};
      my $resolution = $resolutions[$counter];
      my $diffextremes = ( $extreme1 - $extreme2 );
      my $variation = ( $diffextremes / ( $resolution + 1) );
      my @coordpoints;
      my $othercount = 1;
      while ( $othercount < ( $resolution +1 ) )
      {
        my $compoundvariation = ( $variation * $othercount );
        my $coordvalue = ( $extreme2 + $compoundvariation );
        push ( @coordpoints, $coordvalue );
        $othercount++;
      }
      push ( @coordspoints, [ @coordpoints ] );
      $count++;
    }
    push ( @coordspoints, $surf, $dirsvectorsref );
    push ( @wholegrid, [ @coordspoints ] );
    $countsurf++;
  }
  return(@wholegrid);
}

sub makegrid
{ # THIS CONVERTS THE GRID DATA IN VERTEX FORM
  my @gridcoords = @_;
  my @gridsvertices;
  foreach my $surfdataref ( @gridcoords )
  {
    my @xyzcoords;
    my @surfdata = @$surfdataref;
    my @xdata = @{$surfdata[0]};
    my @ydata = @{$surfdata[1]};
    my @zdata = @{$surfdata[2]};
    my $surf = $surfdata[3];
    my $dirvectorsref = $surfdata[4];
    my $counter = 0;
    my @gridvertices;
    my ( @groups, @xyzdata );
    foreach my $xdatum (@xdata)
    {
      my $ydatum = $ydata[$counter];
      push ( @xyzdata, [ $xdatum, $ydatum ] );
      $counter++;
    }
    foreach my $elt (@xyzdata)
    {
      foreach my $zdatum ( @zdata )
      {
        my @group = @$elt;
        push ( @group, $zdatum );
        push ( @groups, [ @group ] );
      }
    }
    push ( @gridvertices, [ @groups ], $surf, $dirvectorsref );
    push ( @gridsvertices, [ @gridvertices ] );
  }
  return ( @gridsvertices );
}

sub adjust_dirvector
{  # THIS SCALES THE DIRECTION VECTORS TO EASE THE MANIPULATION OF THE GRIDS IN DETACHING THEM FROM THE SURFACES.
  my ( $vectorref, $distgrid ) = @_;
  my @vector = @$vectorref;
  my $denominator = ( 1 / $distgrid );
  my @adjusted_vector;
  foreach my $elt ( @vector )
  {
    my $adjusted_component = ( $elt / $denominator );
    $adjusted_component = sprintf ( "%.3f", $adjusted_component );
    push ( @adjusted_vector, $adjusted_component );
  }
  return ( @adjusted_vector );
}

sub adjustgrid
{  # THIS ADJUSTS THE GRIDS OF POINTS OVER THE REQUESTED SURFACES BY DETACHING THEM OF ABOUT 1 CM TOWARDS THE OUTSIDE.
  my ( $griddataref, $distgrid )  = @_;
  my @griddata = @$griddataref;
  my @adjustedsurfs;
  foreach my $elt ( @griddata )
  {
    my @surfdata = @$elt;
    my @vertexdatarefs = @{$surfdata[0]};
    my $surfnum = $surfdata[1];
    my @dirvector = @{$surfdata[2]};
    my @adjusted_dirvector = adjust_dirvector( \@dirvector, $distgrid );
    my @adjustedsurfs;
    foreach my $vertexref ( @vertexdatarefs )
    {
      my @vertexcoords = @$vertexref;
      my @adjustedvertex;
      $countcomp = 0;
      foreach my $el ( @vertexcoords )
      {
        my $component = $adjusted_dirvector[$countcomp];
        my $newel = ( $el + $component );
        push ( @adjustedvertex, $newel );
        $countcomp++;
      }
      push ( @adjustedsurfs, [ @adjustedvertex ] );
    }
    push ( @adjusteddata, [ [ @adjustedsurfs ], $surfnum, [ @dirvector ] ] );
  }
  return ( @adjusteddata );
}

sub treatshdfile
{ # THIS PREPARES THE SHDA FILES IN MEMORY FOR USE.
  my @lines = @_;
  my @newlines;
  my $count = 0;
  foreach my $line ( @lines )
  {
    my $lineafter = $lines[ $count + 1 ];
    my $linebefore = $lines[ $count - 1 ];
    my $linecontrol = $line;
    if ( ( $lineafter =~ /# direct - surface/ ) or ( $lineafter =~ /# diffuse - surface/ ) )
    {
      $linecontrol = "";
    }
    elsif ( ( $line =~ /# direct - surface/ ) or ( $line =~ /# diffuse - surface/ ) )
    {
      chomp $linebefore;
      $line = "$linebefore" . " " . "$line" ;
    }

    unless ( $linecontrol eq "" )
    {
      push ( @newlines, $line );
    }
    $count++;
  }
  return ( @newlines );
}


sub readshdfile
{ # THIS READS THE RELEVANT CONTENT OF THE SHDA FILE.
  my ( $shdfile ) = @_;
  my $shdafile = $shdfile . "a";
  if ( not ( -e $shdafile ) )#
  {
    say "\nExiting. A file \".shda\" must be present in the model folders for the operation to be performed.
    Now it isn't. To obtain that, a shading and insolation calculation must have been performed." and die;
  }
  my $tempfile = $shdafile;
  $tempfile =~ s/\.shda/\.temp\.shda/ ;

  open ( SHDAFILE, "$shdafile") or die;
  my @shdalines = <SHDAFILE>;
  close SHDAFILE,

  my (@filearray, @rawlines, @months);
  foreach my $line ( @shdalines )
  {
    push ( @rawlines, $line );
  }
  my @treatedlines = treatshdfile ( @rawlines );

  foreach my $line ( @treatedlines )
  { # THIS READS THE ".shda" FILES.
    my @elts = split(/\s+|,/, $line);
    if ( $line =~ /\* month:/ )
    {
      my $month = $elts[2];
      push ( @months, $month );
    }
    push ( @filearray, [ @elts ] );
  }

  open ( TEMP , ">$tempfile" ) or die;
  foreach my $line ( @treatedlines )
  {
    print TEMP $line;
  }
  close TEMP;
  return ( \@treatedlines, \@filearray, \@months );
}

sub tellsurfnames
{ # THIS RETURNS THE NAMES OF THE SURFACES.
  my ( $transpsurfsref, $geodataref ) = @_;
  my @transpsurfs = @$transpsurfsref;
  my @geodata = @$geodataref;
  my ( @containernums, @containernames, @nums, @names );
  my $count = 0;
  foreach my $surf ( @transpsurfs )
  {
    foreach my $rowref ( @geodata )
    {
      my @row = @$rowref;
      if ( ( $surf eq $row[12] ) and ( $row[0] eq "*surf" ) )
      {
        push ( @nums, $surf );
        push ( @names, $row[1] );
      }
      $count++;
    }
  }
  return ( \@nums, \@names );
}

sub getsurfshd
{ # THIS RETURN ALL THE DATA NEEDED FROM THE ".shda" FILE.
  my ( $shdfilearrayref, $monthsref, $surfnumsref, $surfnamesref ) = @_;
  my @shdfilearray = @$shdfilearrayref;
  my @months = @$monthsref;
  my @surfnums = @$surfnumsref;
  my @surfnames = @$surfnamesref;

  my @yearbag;
  foreach my $month ( @months )
  {
    my $semaphore = 0;
    my @monthbag;
    foreach my $rowref ( @shdfilearray )
    {
      my @row = @$rowref;
      if ( ( $row[0] eq "*") and ( $row[1] eq "month:" ) and ( $row[2] eq "$month" ) )
      {
        $semaphore = 1;
      }
      elsif ( ( $row[0] eq "*") and ( $row[1] eq "month:" ) and ( not ( $row[2] eq "$month" ) ) )
      {
        $semaphore = 0;
      }
      foreach my $surfname ( @surfnames )
      {
        if ( ( $row[25] eq "diffuse") and ( $row[27] eq "surface") and ( $row[28] eq "$surfname" ) and ( $semaphore == 1 ) )
        {
          push ( @monthbag, [ [ @row[0..23] ], $surfname ] );
        }
      }
    }
    push ( @yearbag, [ [ @monthbag ], $month ] );
  }
  return ( @yearbag );
}

sub checklight
{ # THIS LOOKS INTO THE "shda" DATA AND SEES WHEN DAYLIGHTING IS PRESENT.
  my ( $shdfilearrayref, $monthsref ) = @_;
  my @shdfilearray = @$shdfilearrayref;
  my @months = @$monthsref;

  my @yearbag;
  foreach my $month ( @months )
  {
    my @monthbag;
    my $countrow = 0;
    my $semaphore = 0;
    foreach my $rowref ( @shdfilearray )
    {
      my @row = @$rowref;
      if ( ( $row[0] eq "*") and ( $row[1] eq "month:" ) and ( $row[2] eq "$month" ) )
      {
        $semaphore = 1;
      }
      elsif ( ( $row[0] eq "*") and ( $row[1] eq "month:" ) and ( not ( $row[2] eq "$month" ) ) )
      {
        $semaphore = 0;
      }

      if ( ( $row[0] eq "surfaces") and ( $row[1] eq "insolated") and ( $semaphore == 1 ) )
      {
        my @bag;

        foreach my $el ( @{ $shdfilearray[ $countrow + 1 ] } )
        {
          if ( $el < 0 )
          {
            $el = 1;
            push ( @bag, $el );
          }
          else
          {
            $el = 0;
            push ( @bag, $el );
          }
        }
        push ( @monthbag, [ @bag ] );
      }
      $countrow++;
    }
    push ( @yearbag, [ [ @monthbag ], $month ] );
  }
  return ( @yearbag );
}

sub tellradfilenames
{ # THIS RETURNS THE NAMES OF THE RADIANCE FILES.
  my ( $path, $conffile_f1, $conffile_f2, $conffile_f3 ) = @_;

  my @confs = ( $conffile_f1, $conffile_f2, $conffile_f3 );
  my @result;
  foreach my $conf ( @confs )
  {
    my $confstripped = $conf;
    $confstripped =~ s/$path\/cfg\///;
    $confstripped =~ s/.cfg//;
    my $radoctfile = "$confstripped" . "_Extern.oct";
    my $rcffile = "$confstripped" . ".rcf" ;
    push ( @result, [ $conf, $radoctfile, $rcffile ] );
  }
  return( @result );
}

sub tellradnames
{
  my ( $conffile, $path, $radpath ) = @_;
  my $confroot = $conffile;
  $confroot =~ s/$path\/cfg\/// ;
  $confroot =~ s/\.cfg$// ;
  my $fileroot = "$path/$confroot";
  my $rcffile = "$radpath/$confroot.rcf" ;
  my $radoctfile = "$radpath/$confroot" . "_Extern.oct";
  my $riffile = $radoctfile;
  $riffile =~ s/\.oct$/\.rif/ ;
  my $skyfile = $radoctfile;
  $skyfile =~ s/\.oct$/\.sky/ ;
  my $radmatfile = $radoctfile;
  $radmatfile =~ s/\.oct$/\.mat/ ;
  my $radmatcopy = $radmatfile . ".copy";
  my $diffskyfile = $skyfile;
  $diffskyfile =~ s/\.sky$/_diff\.sky/ ;
  return ( $fileroot, $rcffile, $radoctfile, $riffile, $skyfile, $radmatfile, $radmatcopy, $diffskyfile );
}

sub adjustlaunch
{
  my ( $skyfile, $diffskyfile, $path, $radpath ) = @_;

  $skyfile_short = $skyfile;
  $skyfile_short =~ s/$radpath\///;
  $diffskyfile_short = $diffskyfile;
  $diffskyfile_short =~ s/$radpath\///;

  open( SKYFILE, "$skyfile" ) or die "Can't open $skyfile $!";
  my @lines = <SKYFILE>;
  close SKYFILE;
  open( DIFFSKYFILE, ">$diffskyfile" ) or die "$!";
  foreach my $line ( @lines )
  {
    $line =~ s/^3 (.+)$/3 0 0 0/ ;
    $line =~ s/^4 (.+)$/4 0 0 0 0/ ;
    print DIFFSKYFILE $line;
  }
  close DIFFSKYFILE;

  my $oldskyfile = $skyfile . ".old";
  `mv -f $skyfile $oldskyfile`;
  print REPORT "mv -f $skyfile $oldskyfile\n";
  `mv -f $diffskyfile $skyfile`;
  print REPORT "mv -f $diffskyfile $skyfile\n";
}

sub setrad
{
  # THIS CREATES THE RADIANCE SCENES.
  my ( $conffile, $radoctfile, $rcffile, $path, $radpath, $monthnum, $day, $hour, $countfirst, $exportconstrref, $exportreflref, $skycondition_ref, $countrad, $specularratios_ref, $calcprocedures_ref, $debug ) = @_;
  my %skycondition = %$skycondition_ref; print REPORT "\%skycondition: " . dump ( %skycondition );
  my @calcprocedures = @$calcprocedures_ref;
  if ( $debug == 1 )
  {
    $debugstr = ">>out.txt";
  }
  else
  {
    $debugstr = "";
  }

  my $skycond = $skycondition{$monthnum}; print REPORT "\$skycond: " . dump ( $skycond );

  my $radoctroot = $radoctfile;
  $radoctroot =~ s/$radoctfile/\.oct/ ;

  my $shortrcffile = $rcffile;
  $shortrcffile =~ s/$radpath\/// ; say REPORT "\$shortrcffile: $shortrcffile";

  my $skyfile = $rcffile;
  $skyfile =~ s/rif$/sky/ ;

  my $riffile = $rcffile;
  $riffile =~ s/\.rcf$/_Extern\.rif/ ;

  my $shortriffile = $riffile;
  $shortriffile =~ s/$radpath\/// ; say REPORT "\$shortriffile: $shortriffile";

  my $add;
  if ( $skycond eq "cloudy" ) { $add = "\nf"}
  if ( $skycond eq "overcast" ) { $add = "\nf\nf"} print REPORT "\$add: " . dump ( $add );

  my $moment;

  if ( ( ( $monthnum == 12 ) or ( $monthnum == 1 ) or ( $monthnum == 11 ) or ( $monthnum == 2 ) ) and ( $hour < 11 ) )
  { $moment = "a"; }
  elsif ( ( ( $monthnum == 12 ) or ( $monthnum == 1 ) or ( $monthnum == 11 ) or ( $monthnum == 2 ) ) and ( ( $hour == 11 ) or ( $hour == 12 ) or ( $hour == 13 ) ) )
  { $moment = "b"; }
  elsif  ( ( ( $monthnum == 12 ) or ( $monthnum == 1 ) or ( $monthnum == 11 ) or ( $monthnum == 2 ) ) and ( $hour > 13 ) )
  { $moment = "c"; }
  elsif ( ( ( $monthnum == 3 ) or ( $monthnum == 4 ) or ( $monthnum == 9 ) or ( $monthnum == 10 ) ) and ( $hour < 11 ) )
  { $moment = "d"; }
  elsif ( ( ( $monthnum == 3 ) or ( $monthnum == 4 ) or ( $monthnum == 9 ) or ( $monthnum == 10 ) ) and ( ( $hour == 11 ) or ( $hour == 12 ) or ( $hour == 13 ) ) )
  { $moment = "e"; }
  elsif  ( ( ( $monthnum == 3 ) or ( $monthnum == 4 ) or ( $monthnum == 9 ) or ( $monthnum == 10 ) ) and ( $hour > 13 ) )
  { $moment = "f"; }
  elsif  ( ( ( $monthnum == 5 ) or ( $monthnum == 6 ) or ( $monthnum == 7 ) or ( $monthnum == 8 ) ) and ( $hour < 11 ) )
  { $moment = "g"; }
  elsif  ( ( ( $monthnum == 5 ) or ( $monthnum == 6 ) or ( $monthnum == 7 ) or ( $monthnum == 8 ) ) and ( ( $hour == 11 ) or ( $hour == 12 ) or ( $hour == 13 ) ) )
  { $moment = "h"; }
  elsif  ( ( ( $monthnum == 5 ) or ( $monthnum == 6 ) or ( $monthnum == 7 ) or ( $monthnum == 8 ) ) and ( $hour > 13 ) )
  { $moment = "i"; }

  if ( not ( -e "$path/cfg/fix.sh" ) ) { `cp ./fix.sh $path/cfg/fix.sh`; }
  if ( not ( -e "$path/cfg/perlfix.pl" ) ) { `cp ./perlfix.pl $path/cfg/perlfix.pl`; }
  if ( not ( -e "$path/rad/fix.sh" ) ) { `cp ./fix.sh $path/rad/fix.sh`; }
  if ( not ( -e "$path/rad/perlfix.pl" ) ) { `cp ./perlfix.pl $path/rad/perlfix.pl`; }

  say REPORT "cd $path/rad/
e2r -file $conffile -mode text $debugstr <<YYY
c
$shortrcffile
a
a
$moment
1
n
d

d
$day $monthnum $hour$add
g
-
h
c
a
d
a
f
c
h
y
>
$shortriffile
-
-
YYY
.Done this.
";

`cd $path/rad/
e2r -file $conffile -mode text $debugstr <<YYY
c
$shortrcffile
a
a
$moment
1
n
d

d
$day $monthnum $hour
g
-
h
c
a
d
a
f
c
h
y
>
$shortriffile
-
-
YYY
`;

  if ( $countrad == 0 )
  {
    adjust_radmatfile( $exportconstrref, $exportreflref, $conffile, $path, \@specularratios );
  }
}

sub setroot
{ # THIS SETS THE MODELS' ROOT NAME.
  my ( $conffile, $path, $debug ) = @_;
  my $rootname = $conffile;
  $rootname =~ s/$path\/cfg\///;
  $rootname =~ s/\.cfg//;
  if ( $debug == 1 )
  {
    $debugstr = ">>out.txt";
  }
  else
  {
    $debugstr = "";
  }

  if ( not ( -e "$path/cfg/fix.sh" ) ) { `cp ./fix.sh $path/cfg/fix.sh`; }
  if ( not ( -e "$path/cfg/perlfix.pl" ) ) { `cp ./perlfix.pl $path/cfg/perlfix.pl`; }
  if ( not ( -e "$path/rad/fix.sh" ) ) { `cp ./fix.sh $path/rad/fix.sh`; }
  if ( not ( -e "$path/rad/perlfix.pl" ) ) { `cp ./perlfix.pl $path/rad/perlfix.pl`; }

print REPORT "cd $path/cfg
prj -file $conffile -mode text $debugstr <<YYY
b

s

$rootname

m
c
b
#
y
-
-
-
-

YYY
";
`cd $path/cfg
prj -file $conffile -mode text $debugstr <<YYY
b

s

$rootname

m
c
b
#
y
-
-
-
-

YYY
`;
}

sub populatelight
{ # THIS POPULATES THE DATA STRUCTURE DEDICATED TO SIGNAL THE DAYLIT HOURS.
  my @daylighthoursarr = @_;
  my %daylighthours;
  my $count = 0;
  foreach my $monthref ( @daylighthoursarr )
  {
    my @monthdata = @$monthref;
    my $month = $monthdata[1];
    $month =~ s/`//g;
    my @lithours = @{$monthdata[0][0]};
    $daylighthours{$month} = [ @lithours ] ;
    $count++;
  }
  return ( %daylighthours );
}


sub deg2rad
{
	my $degrees = shift;
	return ( ( $degrees / 180 ) * 3.14159265358979 );
}

sub rad2deg
{
	my $radians = shift;
	return ( ( $radians / 3.14159265358979 ) * 180 ) ;
}

sub rotate2d
{   # SELF-EXPLAINING.
    my ( $x, $y, $angle ) = @_;
    $angle = deg2rad( $angle );
    my $x_new = cos($angle)*$x - sin($angle)*$y;
    my $y_new = sin($angle)*$x + cos($angle)*$y;
  return ( $x_new, $y_new);
}

sub getdirvectors
{ # THIS GETS THE NEEDED DIRECTION VECTORS AT EACH GRID POINT DEPENDING FROM THE LAUNCH SETTINGS.
   ( $basevectorsref, $dirvectorref, $pointcoordsref ) = @_;
   my @basevectors = @$basevectorsref;;
   my @dirvector = @$dirvectorref;
   my @topcoords = @{$basevectors[0]};
   my @newdirvectors;
   my $xbase = $topcoords[0];
   my $ybase = $topcoords[1];
   my $zbase = $topcoords[2];
   my $xnew = $dirvector[0];
   my $ynew = $dirvector[1];
   my $znew = $dirvector[2];
   my $anglebasexz = acos($xbase);
   my $anglebaseyz = acos($zbase);
   my $anglenewxz = acos($xnew);
   my $anglenewyz = acos($znew);
   my $anglediffxz = ( $anglenewxz - $anglebasexz );
   my $anglediffyz = ( $anglenewyz - $anglebaseyz );
   foreach my $eltsref ( @basevectors )
   {
     my @elts = @$eltsref;
     my ( $x, $y, $z ) = @elts ;
     my ( $x_ok, $tempy ) = rotate2d( $x, $y, $anglediffxz );
     my ( $y_ok, $z_ok ) = rotate2d( $tempy, $z, $anglediffyz );
     $x_ok = sprintf ( "%.3f", $x_ok );
     $y_ok = sprintf ( "%.3f", $y_ok );
     $z_ok = sprintf ( "%.3f", $z_ok );
     push ( @newdirvectors, [ $x_ok, $y_ok, $z_ok ] );
   }
   return ( @newdirvectors );
}

sub pursue
{ # THIS CALCULATES THE IRRADIANCES BY THE MEANS OF RADIANCE.
  # RADIANCE EXAMPLE: echo 1 dat-0.01 2 0 -1 0 | rtrace  -I -ab 2 -lr 7 -h /home/luca/boxform/rad/boxform_f1_Extern.oct | rcalc -e '$1=179*(.265*$1+.670*$2+.065*$3)'
  $" = " ";
  my $dat = shift;
  my %d = %$dat;
  my $zonenum = $d{zonenum};
  my $geofile = $d{geofile};
  my $constrfile = $d{constrfile};
  my $shdfile = $d{shdfile};
  my @gridpoints = @{ $d{gridpoints} };
  my @shdsurfdata = @{ $d{shdsurfdata} };
  my @daylighthoursarr = @{ $d{daylighthoursarr} };
  my %daylighthours =  %{ $d{daylighthours} };
  my @shdfilearray = @{ $d{shdfilearray} };
  my $exportconstrref = $d{exportconstrref};
  my $exportreflref = $d{exportreflref};
  my $conffile = $d{conffile};
  my $path = $d{path};
  my $radpath = $d{radpath};
  my @basevectors = @{ $d{basevectors} };
  my @resolutions = @{ $d{resolutions} };
  my $dirvectorsnum = $d{dirvectorsnum};
  my @calcprocedures = @{ $d{calcprocedures} };
  my @specularratios = @{ $d{specularratios} };
  my $bounceambnum = $d{bounceambnum};
  my $bouncemaxnum = $d{bouncemaxnum};
  my ( $fict1ref, $fict2ref, $fict3ref ) = @{ $d{radfilesrefs} };
  my @surfsnums = @{ $d{transpsurfs} };

  my ( $conffile_f1, $radoctfile_f1, $rcffile_f1 ) = @$fict1ref;
  my ( $conffile_f2, $radoctfile_f2, $rcffile_f2 ) = @$fict2ref;
  my @conffiles = ( $conffile_f1, $conffile_f2, $conffile_f3 );
  my @radoctfiles = ( $radoctfile_f1, $radoctfile_f2  );
  my @rcffiles = ( $rcffile_f1, $rcffile_f2 );

  my $resolnumber = ( $resolutions[0] * $resolutions[1] );

  my $fileroot = $radoctfile_f1;
  $fileroot =~ s/_f1_Extern.oct//;
  my ( %irrs, %irrs_dir, %irrs_amb);
  my $setoldfiles = "on";
  my ( %surftests, %surftestsdiff, %surftestsdir, %irrs );

  my ( $totaldirect, $totalrad, $directratio, $diffuseratio );

  my $countfirst = 0;
  my $countrad = 0;
  foreach my $radoctfile ( @radoctfiles )
  {
    opendir( DIR, "$path/rad/" );
    my @names = grep( /\.rcf/ , readdir(DIR) );
    closedir( DIR );

    my $conffile = $conffiles[$countrad];

    my ( $fileroot, $rcffile, $radoctfile, $riffile, $skyfile, $radmatfile, $radmatcopy, $diffskyfile ) = tellradnames( $conffile, $path, $radpath );

    my $conffile_a = $conffile;
    $conffile_a =~ s/\.cfg$/_a\.cfg/ ;

    `cp -f $conffile $conffile_a`;
    print REPORT "cp -f $conffile $conffile_a\n";

    my ( $fileroot_a, $rcffile_a, $radoctfile_a, $riffile_a, $skyfile_a, $radmatfile_a, $radmatcopy_a, $diffskyfile_a ) = tellradnames( $conffile_a, $path, $radpath );

    my $countmonth = 0;
    foreach my $monthsdataref ( @daylighthoursarr )
    {
      my @monthsdata = @$monthsdataref;
      my @hourslight = @{$monthsdata[0][0]};
      my $month = $monthsdata[1];
      $month =~ s/`//g;
      my $monthnum = getmonthnum( $month );
      my $day = $days_inmonths{ $month };

      my $countsurf = 0;
      foreach my $surfref ( @gridpoints )
      {
        my @surfdata = @$surfref;
        my @pointrefs = @{ $surfdata[0] };
        my $surfnum = $surfdata[1];
        my @dirvector = @{ $surfdata[2] };
        my ( $dirvectorx, $dirvectory, $dirvectorz ) = @dirvector;

        my $countlithour = 0;
        my $counthour = 0;
        foreach my $hourlight ( @hourslight )
        {
          if ( $hourlight != 1 )
          {
            $countlithour++;
            my $hour = ( $counthour + 1) ;

            my $countpoint = 0;

            if ( ( $countmonth == 0 ) and ( $countsurf == 0 ) and ( $countlithour == 1 ) ) ### and ( $countpoint == 0 ) and ( $setoldfiles = "on" )
            {
              setroot( $conffile, $path, $debug);
              setrad( $conffile, $radoctfile, $rcffile, $path, $radpath, $monthnum, $day, $hour, $countfirst, $exportconstrref, $exportreflref, \%skycondition, $countrad, \@specularratios, \@calcprocedures, $debug );

              if ( $countrad == 1)
              {
                adjust_radmatfile( $exportconstrref, $exportreflref, $conffile, $path, \@specularratios );
                `cp -f $radmatfile $radmatcopy`;
                say REPORT "cp -f $radmatfile $radmatcopy";

                open ( FIXLIST, ">$path/rad/fixl.pl" ) or die( $! );
                print FIXLIST "$radmatfile\n";
                print FIXLIST "$radmatcopy\n";
                close FIXLIST;
              }
              $setoldfiles = "off";
            }

            #my $d = File::Modified->new(files=>[$radmatfile] );  #STARTDAEMON
            #while ( $go == 1 )
            #{
            #my ( @changes ) = $d->changed;
            #if ( @changes )
            #{
            #    `cp -f $radmatcopy $radmatfile`;
            #      say REPORT "cp -f $radmatcopy $radmatfile";
            #    $d->update();
            #  }
            #  sleep 0.05 ;
            #}

            #if ( $countrad == 1)
            #{
            # # my $go = 1;
            #  my $monitor = File::Monitor::Lite->new( in => "$path/rad/", name => "$radmatfile" );
            #  while ( $monitor->check() and sleep 0.01 )
            #  {
            #    if ( $monitor->modified )
            #    {
            #       `cp -f $radmatcopy $radmatfile`;
            #         say REPORT "cp -f $radmatcopy $radmatfile";
            #    }
            #  }
            #}


            #if ( $countrad == 1)
            #{
            #  `perl ./hack.pl "$path" "$radmatfile" "$radmatcopy" &`;

            #}

            ###setrad( $conffile, $radoctfile, $rcffile, $path, $radpath, $monthnum, $day, $hour, $countfirst, $exportconstrref, $exportreflref, \%skycondition, $countrad, \@specularratios, \@calcprocedures, $debug );

            #if ( $countrad == 1)
            #{
            #  $go = 2; #CLOSEDAEMON
            #}

            #$countfirst++;

            setrad( $conffile, $radoctfile, $rcffile, $path, $radpath, $monthnum, $day, $hour, $countfirst, $exportconstrref, $exportreflref, \%skycondition, $countrad, \@specularratios, \@calcprocedures, $debug );


            my $countpoint = 0;

            #my $pm4 = Parallel::ForkManager->new( $max_processes ); #Sets up the possibility of opening child processes
	    #DATA_LOOP:
            foreach my $pointref ( @pointrefs )
            {
              #my $pid4 = $pm4->start and next DATA_LOOP; # Begins the child process
              my @pointcoords = @$pointref;
              my ( $xcoord, $ycoord, $zcoord ) = @pointcoords;
              my $raddir = "$path/rad/";
              my $cfgpath = "$path/cfg/";
              my @dirvgroup = getdirvectors ( \@basevectors, \@dirvector );

              my $countdirvec = 0;
              foreach my $dirvector ( @dirvgroup )
              {
                my ( $valstring, $valstring1, $valstring2, $irr, $irr1, $irr2 );

                if ( ( $countrad == 0 ) or ( $countrad == 1 ) )
                {
                  $valstring = `cd $raddir \n echo $xcoord $ycoord $zcoord $dirvectorx $dirvectory $dirvectorz | rtrace  -I -ab $bounceambnum -lr $bouncemaxnum -h $radoctfile`;   say REPORT "TO SHELL: cd $raddir \n echo $xcoord $ycoord $zcoord $dirvectorx $dirvectory $dirvectorz | rtrace  -I -ab $bounceambnum -lr $bouncemaxnum -h $radoctfile";
		  my ( $x, $y, $z ) = ( $valstring =~ m/(.+)\t(.+)\t(.+)\t/ );
                  $irr = ( 179 * ( ( .265 * $x ) + ( .670 * $y ) + ( .065 * $z ) ) );
                }
                push ( @{ $surftests{$radoctfile}{$monthnum}{$surfnum}{$hour} }, $irr );
                $countdirvec++;
              }
              $countpoint++;
	      #$pm4->finish;
            }
            #say "Obtained total @{ $surftests{$radoctfile}{$monthnum}{$surfnum}{$hour} }";



            my $countpoint = 0;
            #my $pm = Parallel::ForkManager->new( $max_processes ); #Sets up the possibility of opening child processes
            foreach my $pointref ( @pointrefs )
            {
              #$pm->start and next; # Begins the child process
              my @pointcoords = @$pointref;
              my ( $xcoord, $ycoord, $zcoord ) = @pointcoords;
              my $raddir = "$path/rad/";
              my $cfgpath = "$path/cfg/";
              my @dirvgroup = getdirvectors ( \@basevectors, \@dirvector );

              my $countdirvec = 0;
              foreach my $dirvector ( @dirvgroup )
              {
                my ( $valstring, $valstring1, $valstring2, $irr, $irr1, $irr2 );

                if ( ( $countrad == 0 ) or ( $countrad == 1 ) )
                {
                  $valstring = `cd $raddir \n echo $xcoord $ycoord $zcoord $dirvectorx $dirvectory $dirvectorz | rtrace  -I -ab 0 -av 0 0 0 -lr $bouncemaxnum -h $radoctfile`;   say REPORT "TO SHELL: cd $raddir \n echo $xcoord $ycoord $zcoord $dirvectorx $dirvectory $dirvectorz | rtrace  -I -ab $bounceambnum -lr $bouncemaxnum -h $radoctfile";
                  my ( $x, $y, $z ) = ( $valstring =~ m/(.+)\t(.+)\t(.+)\t/ );
                  $irr = ( 179 * ( ( .265 * $x ) + ( .670 * $y ) + ( .065 * $z ) ) );
                }
                push ( @{ $surftestsdir{$radoctfile}{$monthnum}{$surfnum}{$hour} }, $irr );
                $countdirvec++;
              }
              $countpoint++;
              #$pm->finish;
            }
            #$pm->wait_all_children;

            #say "Obtained direct @{ $surftestsdir{$radoctfile}{$monthnum}{$surfnum}{$hour} }";




            my ( $meanvaluesurf, $meanvaluesurf_diff, $meanvaluesurf_dir );

            if ( @{ $surftests{$radoctfile}{$monthnum}{$surfnum}{$hour} } )
            {
              $meanvaluesurf = mean( @{ $surftests{$radoctfile}{$monthnum}{$surfnum}{$hour} } ); say "Calculating total irradiance: $meanvaluesurf, for surface $surfnum, zone $zonenum, month $monthnum, day $day, hour $hour, octree $radoctfile.\n" ;
            }

            if ( @{ $surftestsdir{$radoctfile}{$monthnum}{$surfnum}{$hour} } )
            {
              $meanvaluesurf_dir = mean( @{ $surftestsdir{$radoctfile}{$monthnum}{$surfnum}{$hour} } ); say "Calculating direct irradiance: $meanvaluesurf_dir, for surface $surfnum, zone $zonenum, month $monthnum, day $day, hour $hour, octree $radoctfile.\n" ;
            }

            $meanvaluesurf_diff = ( $meanvaluesurf - $meanvaluesurf_dir ); say "From those, obtaining diffuse irradiance: $meanvaluesurf_diff.";

            if ( $meanvaluesurf_diff and $surfnum and $hour )
            {
              $irrs{ $zonenum }{ $countrad +1 }{ $monthnum }{ $surfnum }{ $hour }{ meanirr } = $meanvaluesurf_diff;
            }
            if ( $meanvaluesurf_dir and $surfnum and $hour )
            {
              $irrs{ $zonenum }{ $countrad +1 }{ $monthnum }{ $surfnum }{ $hour }{ meandirirr } = $meanvaluesurf_dir;
            }
          }
          $counthour++;
        }
        $countsurf++;
      }
      $countmonth++;
    }
    $countrad++;
  }
  $" = ",";
  return ( \%irrs );
}

sub cleanblanks
{ # SELF-EXPLAINING.
  my @arr = @_;
  my @box;
  my $count = 0;
  foreach my $el ( @arr )
  {
    unless ( $el eq "" )
    {
      push ( @box, $el );
    }
    $count++;
  }
  return( @box );
}

sub createconstrdbfile
{ # THIS CREATES THE CONSTRUCTION DB FILE OF THE FICTITIOUS ESP-r MODELS.
  my ( $constrdbfile, $constrdbfile_f, $obsconstrsetref ) = @_;
  my @obsconstrset = @$obsconstrsetref;
  @obsconstrset = uniq( @obsconstrset );
  my ( @bigcopy, @updatedlines );
  open ( DBFILE, "$constrdbfile" ) or die;
  my @lines = <DBFILE>;
  close DBFILE;

#  my $topline; this is not used
  my $countline = 0;

# --- OLD CONSTR DATABASE ---
#   foreach my $line ( @lines )
#   { #THIS PUSHES IN @UPDATEDLINES THE CONSTR DATABASE EXCEPTED THE FIRST LINES (HEADER LINES)
# # This actually pushes all lines, including header lines, which explains the "if ( $countline > 2 )" below.
#     my @row = split( /\s+|,/ , $line);
#     @row = cleanblanks( @row );
#     my ( $oldnumber, $newnumber );
#     my $atline;
#     if ( $line =~ /\# no of composites/ )
#     {
#       $atline == $countline;
#       $oldnumber = $row[0];
#       $newnumber = ( $oldnumber + scalar( @obsconstrset ) );
#       $line =~ s/$oldnumber/$newnumber/;
#       push ( @updatedlines, $line );
#     }
#     else
#     {
#       push ( @updatedlines, $line );
#     }
#     $countline++;
#   }

# --- NEW CONSTR DATABASE ---
# Push database contents into @updatedlines.
# Add a category called "Modish_fict" while doing this.
  foreach my $line ( @lines )
  {
    push ( @updatedlines, $line );
    if ( $line =~ /^\*date,/ )
    {
      push ( @updatedlines, "*Category,Modish_fict,Modish fictitious constructions,fictitious versions of existing constructions used for shading factor modifier script Modish\n" );
    }
  }

# --- OLD CONSTR DATABASE ---
  # my $coun = 0;
  # foreach my $el ( @obsconstrset )
  # { #FOREARCH MATERIAL USED IN THE OBSTRUCTIONS, PUSHES THE CONSTRUCTION SOLUTIONS IN WHICH IT IS USED IN @COPY, AND PUSHES EACH [ @COPY ] IN @BIGCOPY
  #   my @copy;
  #   my $semaphore = 0;
  #   $countel = 0;
  #   $countline = 0;
  #   foreach my $line ( @updatedlines )
  #   {
  #     my @row = split( /\s+|,/ , $line);
  #     @row = cleanblanks( @row );
  #    # if ( $countline > 2 ) #WHY IS THIS?
  #    # {
  #       if ( $el eq $row[1] )
  #       {
  #         $semaphore = 1;
  #       }

  #       if ( ( $semaphore == 1 ) and ( $countel == 0) )
  #       {
  #         push ( @copy, "# layers  description   optics name   symmetry tag\n" );
  #         push ( @copy, $line );
  #         $countel++;
  #       }
  #       elsif ( ( $semaphore == 1 ) and ( $countel > 0) )
  #       {
  #         push ( @copy, $line );
  #         if (  ( $row[0] eq "#" ) and ( $row[1] eq "layers" ) and ( $row[2] eq "description" )  )
  #         {
  #           pop(@copy);
  #           $semaphore = 0;
  #         }
  #         $countel++;
  #       }

  #     #}
  #     $countline++;
  #   }
  #     say REPORT "\@copy " . dump(@copy);
  #   #if ( $coun == $#obsconstrset )
  #   #{
  #   #  @bigcopy = [ @copy ];
  #   #}
  #   push ( @bigcopy, [ @copy ] );
  #   $coun++;
  # }

# --- NEW CONSTR DATABASE ---
# If there are obstruction constructions, loop through each @updatedlines.
# If an obstruction construction is found, push this into @copy, and push each [ @copy ] into @bigcopy.
  my $semaphore = 0;
  my $nummatches = 0;
  my $numobsconstr = scalar @obsconstrset;
  my @copy;
  if ( $numobsconstr > 0 )
  {
    foreach my $line ( @updatedlines )
    {
      my @row = split( /,/ , $line);
      @row = cleanblanks( @row );
      if ( ( $semaphore == 0 ) and ( $row[0] == "*item" ) and ( any { $_ eq $row[1] } @obsconstrset ) )
      {
        $semaphore = 1;
      }
      if ( $semaphore == 1 )
      {
        push ( @copy, $line );
        if ( $row[0] =~ /\*end_item/ )
        {
          $semaphore = 0;
          push ( @bigcopy, [ @copy ] );
          undef ( @copy );
          $nummatches++;
          if ( $nummatches == $numobsconstr ) { last }
        }
      }
    }
  }

# --- OLD CONSTR DATABASE ---
  # my $cn = 0;
  # my ( @materials, @newmaterials, @newcopy, @newbigcopy );
  # my ( $newmatinssurf, $newmatextsurf );
  # my %exportconstr;
  # foreach my $copyref ( @bigcopy )
  # {
  #   my @constrlines = @$copyref;
  #   my $firstrow = $constrlines[1];
  #   my @row = split ( /\s+|,/ , $firstrow );
  #   @row = cleanblanks( @row );
  #   my $constrname = $row[1];
  #   my $newconstrname = $constrname;
  #   $newconstrname =~ s/\w\b// ;
  #   $newconstrname =~ s/\w\b// ;
  #   $newconstrname = "f_" . "$newconstrname";

  #   my $intlayer = $constrlines[3];
  #   my @row = split ( /\s+|,/ , $intlayer );
  #   @row = cleanblanks( @row );
  #   my $matintlayer = $row[2];
  #   my $newmatintlayer = $matintlayer;
  #   $newmatintlayer =~ s/\w\b// ;
  #   $newmatintlayer =~ s/\w\b// ;
  #   $newmatintlayer = "f_" . "$newmatintlayer";
  #   my $extlayer = $constrlines[$#constrlines];
  #   my @row = split ( /\s+|,/ , $extlayer );
  #   @row = cleanblanks( @row );
  #   my $matextlayer = $row[2];
  #   my $newmatextlayer = $matextlayer;
  #   $newmatextlayer =~ s/\w\b// ;
  #   $newmatextlayer =~ s/\w\b// ;
  #   $newmatextlayer = "f_" . "$newmatextlayer";
  #   push ( @materials, $matintlayer, $matextlayer );
  #   push ( @newmaterials, $newmatintlayer, $newmatextlayer );


  #   $constrlines[1] =~ s/$constrname/$newconstrname/g;
  #   $constrlines[3] =~ s/$matintlayer/$newmatintlayer/g;
  #   $constrlines[$#constrlines] =~ s/$matextlayer/$newmatextlayer/g;
  #   foreach my $line ( @constrlines )
  #   {
  #     push ( @newcopy, $line );
  #   }
  #   @newbigcopy = [ @newcopy ] ;
  #   #push ( @newbigcopy, [ @newcopy ] );
  #   $exportconstr{ $newconstrname }{ extlayer } = $newmatextlayer;
  #   $exportconstr{ $newconstrname }{ intlayer } = $newmatintlayer;
  #   $cn++;
  # }

# --- NEW CONSTR DATABASE ---
# In each [ @copy ], modify the:
# construction name and documentation,
# category,
# internal material name, and
# external material name.
# Store the old and new material names, and form a hash relating new materials to the new constructions.
  my ( @materials, @newmaterials, @newcopy, @newbigcopy );
  my %exportconstr;
  foreach my $copyref ( @bigcopy )
  {
    my @constrlines = @$copyref;
    my $onlyonelayer = 0;
    if ( $#constrlines == 5 ) { $onlyonelayer = 1 }

    my $firstrow = $constrlines[0];
    my @row = split ( /,/ , $firstrow );
    @row = cleanblanks( @row );
    my $constrname = $row[1];
    my $newconstrname = $constrname;
    if ( length($constrname) > 30 )
    {
      $newconstrname =~ s/\w\b// ;
      $newconstrname =~ s/\w\b// ;
    }
    $newconstrname = "f_" . "$newconstrname";

    my $intlayer = $constrlines[4];
    my @row = split ( / : |,/ , $intlayer );
    @row = cleanblanks( @row );
    my $matintlayer = $row[3];
    my $newmatintlayer = $matintlayer;
    if ( length($matintlayer) > 30 )
    {
      $newmatintlayer =~ s/\w\b// ;
      $newmatintlayer =~ s/\w\b// ;
    }
    $newmatintlayer = "f_" . "$newmatintlayer";
    push ( @materials, $matintlayer );
    push ( @newmaterials, $newmatintlayer );

    my ( $matextlayer, $newmatextlayer );
    unless ( $onlyonelayer == 1 )
    {
      my $extlayer = $constrlines[$#constrlines-1];
      my @row = split ( / : |,/ , $extlayer );
      @row = cleanblanks( @row );
      $matextlayer = $row[3];
      $newmatextlayer = $matextlayer;
      if ( length($matextlayer) > 30 )
      {
        $newmatextlayer =~ s/\w\b// ;
        $newmatextlayer =~ s/\w\b// ;
      }
      $newmatextlayer = "f_" . "$newmatextlayer";
      push ( @materials, $matextlayer );
      push ( @newmaterials, $newmatextlayer );
    }

    $constrlines[0] =~ s/$constrname/$newconstrname/;
    $constrlines[1] = "*itemdoc,fictitious version of construction " . $constrname . " created by Modish script\n";
    $constrlines[2] = "*incat,Modish_fict\n";
    $constrlines[4] =~ s/$matintlayer/$newmatintlayer/;
    unless ( $onlyonelayer == 1 ) { $constrlines[$#constrlines-1] =~ s/$matextlayer/$newmatextlayer/ }
    foreach ( @constrlines )
    {
      push ( @newcopy, $_ );
    }
    @newbigcopy = [ @newcopy ] ;
    $exportconstr{ $newconstrname }{ extlayer } = $newmatextlayer;
    $exportconstr{ $newconstrname }{ intlayer } = $newmatintlayer;
  }

  @materials = uniq( @materials );
  @newmaterials = uniq( @newmaterials );

  my %newmatnums;
  my $countmat = 1;
  foreach ( @newmaterials )
  {
    $newmatnums{$_} = $countmat;
    $countmat++;
  }

  my %matnums;
  $countmat = 1;
  foreach ( @materials )
  {
    $matnums{$_} = $countmat ;
    $countmat++;
  }

# --- OLD CONSTR DATABASE ---
  # my ( @lastbigcopy );
  # $countmat = 1;
  # foreach my $copyref ( @newbigcopy )
  # {
  #   my ( @lastcopy );
  #   my @constrlines = @$copyref;
  #   my $intlayer = $constrlines[3];
  #   my @row = split ( /\s+|,/ , $intlayer );
  #   @row = cleanblanks( @row );
  #   my $matintlayernum = $row[0];
  #   my $matintlayer = $row[2];

  #   my $extlayer = $constrlines[$#constrlines];
  #   my @row = split ( /\s+|,/ , $extlayer );
  #   @row = cleanblanks( @row );
  #   my $matextlayernum = $row[0];
  #   my $matextlayer = $row[2];

  #   my $newmatnumint = $newmatnums{$matintlayer};
  #   my $newmatnumext = $newmatnums{$matextlayer};
  #   $constrlines[3] =~ s/$matintlayernum/$newmatnumint/g;
  #   $constrlines[$#constrlines] =~ s/$matextlayernum/$newmatnumext/g;
  #   foreach my $line ( @constrlines )
  #   {
  #     push ( @lastcopy, $line );
  #   }
  #   push ( @lastbigcopy, [ @lastcopy ] );
  # }


# --- NEW CONSTR DATABASE ---
  my ( @lastbigcopy );
  $countmat = 1;
  foreach my $copyref ( @newbigcopy )
  {
    my @lastcopy;
    my @constrlines = @$copyref;
    my $onlyonelayer = 0;
    if ( $#constrlines == 5 ) { $onlyonelayer = 1 }

    my $intlayer = $constrlines[4];
    my @row = split ( / : |,/ , $intlayer );
    @row = cleanblanks( @row );
    my $matintlayernum = $row[1];
    my $matintlayer = $row[3];

    unless ( $onlyonelayer == 1 )
    {
      my $extlayer = $constrlines[$#constrlines-1];
      my @row = split ( / : |,/ , $extlayer );
      @row = cleanblanks( @row );
      my $matextlayernum = $row[1];
      my $matextlayer = $row[3];
    }

    my $newmatnumint = $newmatnums{$matintlayer};
    my $newmatnumext = $newmatnums{$matextlayer};
    $constrlines[4] =~ s/$matintlayernum/$newmatnumint/;
    unless ( $onlyonelayer == 1 ) { $constrlines[$#constrlines-1] =~ s/$matextlayernum/$newmatnumext/ }
    foreach my $line ( @constrlines )
    {
      push ( @lastcopy, $line );
    }
    push ( @lastbigcopy, [ @lastcopy ] );
  }

  foreach ( @lastbigcopy )
  {
    splice ( @updatedlines, $#updatedlines, 0, @$_ );
  }

  open ( CONSTRDBFILE_F, ">$constrdbfile_f" ) or die;
  foreach ( @updatedlines )
  {
    print CONSTRDBFILE_F $_;
  }
  close CONSTRDBFILE_F;

  return ( \@materials, \@newmaterials, \%matnums, \%newmatnums, \%exportconstr );
}

sub compareirrs
{ # THIS COMPARES THE IRRADIANCES TO OBTAIN THE IRRADIANCE RATIOS.
  my ( $zonefilelistsref, $irrsref, $computype, $calcprocedures_ref ) = @_;
  my %zonefilelists = %$zonefilelistsref;
  my %irrs = %$irrsref;
  my @calcprocedures = @$calcprocedures_ref;
  my %irrvars;
  foreach my $zonenum ( sort {$a <=> $b} ( keys %irrs ) )
  {
    my $shdfile = $zonefilelists{ $zonenum }{ shdfile };
    foreach my $monthnum ( sort {$a <=> $b} ( keys %{ $irrs{ $zonenum }{ 1 } } ) )
    {
      foreach my $surfnum ( sort {$a <=> $b} ( keys %{ $irrs{ $zonenum }{ 1 }{ $monthnum } } ) )
      {
        foreach my $hour ( sort {$a <=> $b} ( keys %{ $irrs{ $zonenum }{ 1 }{ $monthnum }{ $surfnum } } ) )
        {
          if ( not ( "unified" ~~ @calcprocedures ) )
          {
            my $surfirr = $irrs{ $zonenum }{ 1 }{ $monthnum }{ $surfnum }{ $hour }{ meanirr };
            my $whitesurfirr = $irrs{ $zonenum }{ 2 }{ $monthnum }{ $surfnum }{ $hour }{ meanirr };
            #my $surfirr_amb = $irrs{ $zonenum }{ 3 }{ $monthnum }{ $surfnum }{ $hour }{ meanirr };
            my $irrratio;

            if ( $computype eq "linear" )
            {
              if ( $surfirr == 0 ) { $surfirr = 0.0001 }
              if ( $whitesurfirr == 0 ) { $whitesurfirr = 0.0001 }
              $irrratio = ( $whitesurfirr / $surfirr );
            }

            if ( $computype eq "root" )
            {
              if ( $surfirr == 0 ) { $surfirr = 0.0001 }
              if ( $whitesurfirr == 0 ) { $whitesurfirr = 0.0001 }
              $irrratio = sqrt( $whitesurfirr / $surfirr );
            }

            $irrvars{ $zonenum }{ $monthnum }{ $surfnum }{ $hour }{ irrvar } = $irrratio;


            my $dirsurfirr = $irrs{ $zonenum }{ 1 }{ $monthnum }{ $surfnum }{ $hour }{ meandirirr };
            my $dirwhitesurfirr = $irrs{ $zonenum }{ 2 }{ $monthnum }{ $surfnum }{ $hour }{ meandirirr };
            #my $surfirr_amb = $irrs{ $zonenum }{ 3 }{ $monthnum }{ $surfnum }{ $hour }{ meanirr };
            my $dirirrratio;

            if ( $computype eq "linear" )
            {
              if ( $dirsurfirr == 0 ) { $dirsurfirr = 0.0001 }
              if ( $dirwhitesurfirr == 0 ) { $dirwhitesurfirr = 0.0001 }
              $dirirrratio = ( $dirwhitesurfirr / $dirsurfirr );
            }

            if ( $computype eq "root" )
            {
              if ( $dirsurfirr == 0 ) { $dirsurfirr = 0.0001 }
              if ( $dirwhitesurfirr == 0 ) { $dirwhitesurfirr = 0.0001 }
              $dirirrratio = sqrt( $dirwhitesurfirr / $dirsurfirr ) ;
            }

            $irrvars{ $zonenum }{ $monthnum }{ $surfnum }{ $hour }{ dirirrvar } = $dirirrratio;
          }
          else
          {
            my $diffsurfirr = $irrs{ $zonenum }{ 1 }{ $monthnum }{ $surfnum }{ $hour }{ meanirr };
            my $diffwhitesurfirr = $irrs{ $zonenum }{ 2 }{ $monthnum }{ $surfnum }{ $hour }{ meanirr };

            my $dirsurfirr = $irrs{ $zonenum }{ 1 }{ $monthnum }{ $surfnum }{ $hour }{ meandirirr };
            my $dirwhitesurfirr = $irrs{ $zonenum }{ 2 }{ $monthnum }{ $surfnum }{ $hour }{ meandirirr };

            my $surfirr = ( $diffsurfirr + $dirsurfirr );
            my $whitesurfirr = ( $diffwhitesurfirr + $dirwhitesurfirr );

            my ( $irrratio, $diffirrratio, $dirirrratio );

            if ( $surfirr == 0 ) { $surfirr = 0.0001 }
            if ( $whitesurfirr == 0 ) { $whitesurfirr = 0.0001 }
            $irrratio = ( $whitesurfirr / $surfirr );

            if ( $dirwhitesurfirr == 0 ) { $dirwhitesurfirr = 0.0001 }
            if ( $diffwhitesurfirr == 0 ) { $diffwhitesurfirr = 0.0001 }
            my $ratioproportion = ( $diffwhitesurfirr / $dirwhitesurfirr );
            $diffirrratio = ( $irrratio * $ratioproportion );
            $dirirrratio = ( $irrratio - $diffirrratio );

            $irrvars{ $zonenum }{ $monthnum }{ $surfnum }{ $hour }{ irrvar } = $diffirrratio;
            $irrvars{ $zonenum }{ $monthnum }{ $surfnum }{ $hour }{ dirirrvar } = $dirirrratio;
          }
          $countsurf++;
        }

        $counthour++;
      }
      $countmonth++;
    }
    $countzone++;
  }
  return ( \%irrvars );
}

sub fillhours
{ # THIS COMPLETES THE FILLING OF THE DATA STRUCTURES GIVING INFORMATION ABOUT THE DAYLIT HOURS.
  my ( $newhourvalsref, $monthname, $daylighthoursref ) = @_;
  my @hadhours = @$newhourvalsref;
  my %lithours = %$daylighthoursref;
  my @monthhours = @{ $lithours{ $monthname } };
  my @values;

  my $sunhoursnum = 0;
  foreach my $lightcond ( @monthhours )
  {
    unless ( $lightcond == 1 )
    {
      $sunhoursnum++;
    }
  }

  if ( $sunhoursnum == scalar( @hadhours ) )
  {
    my $counthr = 1;
    my $countlit = 0;
    foreach my $lightcond ( @monthhours )
    {
      if ( $lightcond == 1 )
      {
        push ( @values, "1.0000" );
      }
      else
      {
        push ( @values, $hadhours[ $countlit ] );
        $countlit++;
      }
      $counthr++;
    }
    return ( @values );
  }
}


sub modifyshda
{ # THIS MODIFIES THE ".shda" FILE ON THE BASIS OF THE IRRADIANCE RATIOS.
  my ( $comparedirrsref, $surfslistref, $zonefilelistsref, $shdfileslistref, $daylighthoursref, $irrvarsref, $threshold, $tempmod, $tempreport, $tempmoddir, $tempreportdir, $elm, $radtype, $calcprocedures_ref ) = @_; ##### CONDITION! "diffuse" AND "direct".
  my %surfslist = %$surfslistref;
  my %zonefilelists = %$zonefilelistsref;
  my %shdfileslist = %$shdfileslistref;
  my %daylighthours = %$daylighthoursref;
  my %irrvars = %$irrvarsref;
  my @calcprocedures = @$calcprocedures_ref;
  my ( @printcontainer, @monthnames, @pushmodline, @pushreportline, @mainbag, @mainoriginal );

  foreach my $zonenum ( sort {$a <=> $b} ( keys %irrvars ) )
  {
    my $inlinesref = $shdfileslist{ $zonenum };
    my @inlines = @$inlinesref;
    my $semaphore = 0;
    my ( $readmonthname, $readmonthnum );
    my $countline = 1;
    foreach my $line ( @inlines )
    {
      my $line2;
      my @row = split( /\s+|,/ , $line);
      my ( $readsurfname, $readsurfnum );
      if ( ( $row[0] eq "*" ) and ( $row[1] eq "month:" ) )
      {
        $semaphore = 1;
        $readmonthname = $row[2];
        $readmonthname =~ s/`//g;
        $readmonthnum = getmonthnum( $readmonthname );
      }
      if ( ( ( $row[0] eq "24" ) and ( $row[1] eq "hour" ) and ( $row[1] eq "surface" ) ) or ( $row[0] eq "*end" ) )
      {
        $semaphore = 0;
      }

      my ( @newhourvals, @newhourvals2, @were );
      foreach my $monthnum ( sort {$a <=> $b} ( keys %{ $irrvars{ $zonenum } } ) )
      {
        my $monthname = getmonthname( $monthnum );
        push ( @monthnames, $monthname );
        push ( @monthnames2, $monthname );

        foreach my $surfnum ( sort {$a <=> $b} ( keys %{ $irrvars{ $zonenum }{ $monthnum } } ) )
        {
          my $surfname = $surfslist{$zonenum}{$surfnum}{surfname};
          foreach my $hour ( sort {$a <=> $b} ( keys %{ $irrvars{ $zonenum }{ $monthnum }{ $surfnum } } ) )
          {

            my $irrvariation;
            if ( $radtype eq "diffuse" )
            {
              $irrvariation = $irrvars{ $zonenum }{ $monthnum }{ $surfnum }{ $hour }{ irrvar };
              #my $ambbase = $irrvars{ $zonenum }{ $monthnum }{ $surfnum }{ $hour }{ irramb }; #
            }
            elsif ( $radtype eq "direct" )
            {
              $irrvariation = $irrvars{ $zonenum }{ $monthnum }{ $surfnum }{ $hour }{ dirirrvar };
            }

            if ( ( $zonenum ) and ( $monthnum ) and ( $hour ) and ( $surfnum ) and ( $irrvariation ) and ( $surfname ) and ( $monthname ) and ( $surfnum eq $elm ) ) # I.E. IF ALL THE NEEDED DATA EXIST
            {
              if ( $semaphore == 1 )
              {
                if ( $row[27] eq "surface" )
                {
                  $readsurfname = $row[28];
                  $readsurfnum = $surfslist{$zonenum}{$readsurfname}{surfnum} ;
                  my @filledhourvals;
                  if ( ( $row[25] eq $radtype ) and ( $readsurfname eq $surfname ) )
                  {
                    my @hourvals = ( @row[ 0..23 ] );
                    my $counthour = 1;
                    foreach my $el ( @hourvals )
                    { # $el IS THE DIFFUSE SHADING FACTOR IN THE ORIGINAL SHDA FILE.
                      # %irrvariation IS THE IRRADIANCE DIFFERENCE BETWEEN THE "WHITE" MODEL AND THE "BLACK" MODEL.
                      # $ambase IS THE AMBIENT RADIATION WITHOUT SHADINGS

                      my ( $calcamount, $improvedguess, $newshadingvalue);
                      if ( $irrvariation > 1 )
                      {
                        $calcamount = ( 1 - $el ); # THIS IS THE RATIO OF NON-SHADED IRRADIATION AS CALCULATED BY THE ESP-r's ISH MODULE
                        $improvedguess = ( $calcamount * $irrvariation ); # THIS IS THE RATIO ABOVE CORRECTED BY MULTIPLYING IT BY THE IRRADIANCE RATIO TO TAKE REFLECTIONS INTO ACCOUNT.

                        my $num;
                        foreach my $el ( @calcprocedures )
                        {
                        	if ( $el eq ( $el + 0 ) )
                        	{
                        		$num = $el;
                        	}
                        }

                        $newshadingvalue = ( 1 - $improvedguess ); # AS THE NAME SAYS, THIS IS THE NEW SHADING FACTOR.
                      }
                      else
                      {
                        $newshadingvalue = $el; # IF THE IRRADIANCE RATIO IS < 1 DON'T CHANCE THE ORIGINAL DIFFUSE SHADING FACTOR.
                      }

                      if ( ( $counthour == $hour ) and ( $readmonthname eq $monthname ) and ( $readsurfnum == $surfnum ) ) # I.E.: IF THIS LINE IS THE RIGHT ONE...
                      {

                        if ( $newshadingvalue == 1 )
                        {
                          $newshadingvalue = "1.0000";
                        }
                        if ( ( $newshadingvalue > 0 ) and ( $newshadingvalue < 1 ) ) # IF THE VARIATION OF IRRADIANCE FROM MODEL A AND MODEL B IS NEGATIVE...
                        {  # ...INCREASE THE SHADING FACTOR ACCORDINGLY.
                          $newshadingvalue = sprintf ( "%.4f", $newshadingvalue ); # FORMAT THE NUMBER SO THAT IT HAS FOUR DECIMALS
                        }
                        if ( ( $newshadingvalue > -10 ) and ( $newshadingvalue < 0 ) )
                        {
                          $newshadingvalue = sprintf ( "%.3f", $newshadingvalue ); # IF THE NUMBER IS COMPRISED BETWEEN -10 AND = 0 FORMAT IT SO THAT IT HAS 3 DECIMALS
                        }
                        if ( ( $newshadingvalue > -100 ) and ( $newshadingvalue <= -10 ) )
                        {
                          $newshadingvalue = sprintf ( "%.2f", $newshadingvalue ); # IT THE NUMBER IS COMPRISED BETWEEN -100 AND = -10 FORMAT IT SO THAT IT HAS 2 DECIMALS
                        }


                        say REPORT "OLD SHADING VALUE " . dump( $el );
                        say REPORT "NEW SHADING VALUE " . dump( $newshadingvalue );
                        my $irrvariation = sprintf ( "%.4f", $irrvariation );   say REPORT "SPRINTING $irrvariation!";
                        push ( @newhourvals, $newshadingvalue);
                        push ( @newhourvals2, $irrvariation );
                        push ( @were, $el );
                      }
                      $counthour++;
                    }
                    say REPORT "IN MODIFISHDA \@newhourvals (NEW SHADING VALUES) " . dump(@newhourvals) . ", in monthnum: $monthnum, monthname: $monthname, surfnum: $surfnum, hour: $hour";
                    say REPORT "IN MODIFISHDA \@newhourvals2 (IRRADIANCE RATIOS)" . dump(@newhourvals2) . ", in monthnum: $monthnum, monthname: $monthname, surfnum: $surfnum, hour: $hour";
                    say REPORT "IN MODIFISHDA OLD SHADING VALUES WERE : " . dump(@were) . ", in monthnum: $monthnum, monthname: $monthname, surfnum: $surfnum, hour: $hour";

                    my @filledhourvals = fillhours( \@newhourvals, $monthname, \%daylighthours );

                    my @filledhourvals2 = fillhours( \@newhourvals2, $monthname, \%daylighthours );

                    if ( ( scalar ( @filledhourvals ) == 24 ) and ( $monthname eq $monthnames[0] ) )
                    {
                      shift @monthnames;
                      my @firstarr = @filledhourvals[ 0..11 ];
                      my @secondarr = @filledhourvals[ 12..$#filledhourvals ];
                      my $joinedfirst = join ( ' ' , @firstarr );
                      my $joinedsecond = join ( ' ' , @secondarr );
                      if ( $radtype eq "diffuse" )
                      {
                        my $newline = "$joinedfirst " . "$joinedsecond" . " # diffuse - surface " . "$readsurfname $monthname\n";
                        print TEMPMOD $newline;
                      }
                      elsif ( $radtype eq "direct" )#
                      {
                        my $newline = "$joinedfirst " . "$joinedsecond" . " # direct - surface " . "$readsurfname $monthname\n";
                        print TEMPMODDIR $newline;#
                      }
                    }

                    if ( ( scalar ( @filledhourvals2 ) == 24 ) and ( $monthname eq $monthnames2[0] ) )
                    {
                      shift @monthnames2;
                      my @firstarr2 = @filledhourvals2[ 0..11 ];
                      my @secondarr2 = @filledhourvals2[ 12..$#filledhourvals2 ];
                      my $joinedfirst2 = join ( ' ' , @firstarr2 );
                      my $joinedsecond2 = join ( ' ' , @secondarr2 );
                      if ( $radtype eq "diffuse" )
                      {
                        my $newline2 = "$joinedfirst2 " . "$joinedsecond2" . " # diffuse for surface " . "$readsurfname in $monthname\n";
                        print TEMPREPORT $newline2;
                      }
                      elsif ( $radtype eq "direct" )#
                      {
                        my $newline2 = "$joinedfirst2 " . "$joinedsecond2" . " # direct for surface " . "$readsurfname in $monthname\n";
                        print TEMPREPORTDIR $newline2;#
                      }
                    }
                  }
                }
              }
            }
            $countref++;
          }
        }
      }
    }
  }
}


sub getbasevectors
{ # THIS GETS THE PRE-COMPUTED EVENLY DISTRIBUTED N POINTS ON THE SURFACE OF A HEMISPHERE.
  my ( $dirvectorsnum ) = @_;
  my @basevectors;
  if ( $dirvectorsnum == 1 )
  {
    @basevectors = ( #[ 0, 0, 0 ] , # origin, base point of direction vector
        [ 0, 0, 1 ], # direction vector of high, central, vertical point
         ); # lowest vertices
  }
  if ( $dirvectorsnum == 5 )
  {
    @basevectors = ( #[ 0, 0, 0 ] , # origin, base point of direction vector
        [ 0, 0, 1 ], # direction vector of high, central, vertical point
        [ 0.7071, -0.7071, 0.4472 ] , [ 0.7071, 0.7071, 0.4472 ], [ -0.7071, 0.7071, 0.4472 ], [ -0.7071, -0.7071, 0.4472 ] ); # lowest vertices
  }
  elsif ( $dirvectorsnum == 17 )
  {
    @basevectors = ( #[ 0, 0, 0 ] , # origin, base point of direction vector
    [ 0, 0, 1 ], # direction vector of high, central, vertical point
    [ 0.1624, 0.4999, 0.8506 ], [ 0.1624, -0.4999, 0.8506 ], [ -0.2628, 0.8090, 0.5257 ], [ -0.2628, -0.8090, 0.5257 ],
    [ 0.2763, 0.8506, 0.4472 ], [ 0.2763, -0.8506, 0.4472 ], [ -0.4253, 0.3090, 0.8506 ], [ -0.4253, -0.3090, 0.8506,  ],
    [ 0.5257, 0.0, 0.8506 ], [ 0.5877, 0.8090, 0.0 ], [ 0.6881, 0.4999, 0.5257 ], [ 0.6881, -0.4999, 0.5257 ],
    [ -0.7236, 0.5257, 0.4472 ], [ -0.7236, -0.5257, 0.4472 ], [ -0.8506, 0.0, 0.5257 ], [ 0.8944, 0.0, 0.4472 ]
    ); # lowest vertices
  }
  return ( @basevectors );
}

sub createfictgeofile
{  # THIS MANAGES THE MODIFICATION OF THE FICTITIOUS GEO FILES FOR THE ZONE BY ADJUSTING THE OBSTRUCTION CONSTRUCTIONS TO FICTITIOUS EQUIVALENTS
  my ( $geofile, $obsconstrsetref, $geofile_f ) = @_;
  my @obsconstrset = @$obsconstrsetref;

  open ( GEOFILE, "$geofile" ) or die;
  my @lines = <GEOFILE>;
  close GEOFILE;

  open ( GEOFILE_F, ">$geofile_f" ) or die;

  foreach my $line ( @lines )
  {
    if ( $line =~ /^\*obs/ )
    {
      foreach my $obsconstr ( @obsconstrset )
      {
        my $newobsconstr = $obsconstr;
        if ( length($obsconstr) > 30 )
        {
          $newobsconstr =~ s/\w\b// ;
          $newobsconstr =~ s/\w\b// ;
        }
        $newobsconstr = "f_" . $newobsconstr;
        $line =~ s/$obsconstr/$newobsconstr/;
      }
      print GEOFILE_F $line;
    }
    else
    {
      print GEOFILE_F $line;
    }
  }
  close ( GEOFILE_F);
}


sub creatematdbfiles
{ # THIS MANAGES THE CREATION OF THE TWO FICTITIOUS MATERIALS DATABASES:
  # ONE FOR THE THE "UNREFLECTIVE" MODEL AND THE OTHER FOR THE "REFLECTIVE" ONE.
  my ( $materialsref, $newmaterialsref, $matnumsref,
  $newmatnumsref, $matdbfile, $matdbfile_f1, $matdbfile_f2, $calcprocedures_ref ) = @_;

  my @materials = @$materialsref; #NO MORE USED IN THIS PROCEDURE
  my @newmaterials = @$newmaterialsref; #NO MORE USED IN THIS PROCEDURE
  my $newmattotnum = scalar( @newmaterials ); #NO MORE USED IN THIS PROCEDURE
  my %matnums = %$matnumsref; #NO MORE USED IN THIS PROCEDURE
  my %newmatnums = %$newmatnumsref; #NO MORE USED IN THIS PROCEDURE
  my @calcprocedures = @{ $calcprocedures_ref };


  my ( @box, @matnames );
  my %exportrefl;
  foreach $el ( @calcprocedures )
  {
    if ( $el =~ /^(matname:)/ )
    {
      $el =~ s/^$1// ;
      push( @matnames, $el );
    }
  }

  open ( MATDBFILE, "$matdbfile" ) or die;
  my @lines = <MATDBFILE>;
  close MATDBFILE;

  my ( @bag, @row, @firstloop, @secondloop );
  my $class;
  my $semaphore = "off";
  foreach my $line ( @lines )
  {
    chomp $line;
    if ( $line =~ /^\*item/ )
    {
      @row = split( ",", $line );
      if ( $row[1] ~~ @matnames )
      {
        $semaphore = "on";
      }
      else
      {
        $semaphore = "off";
      }
    }

    my @e = split( ",", $line );
    if ( ( $e[0] =~ /^\d/ ) and ( $e[-1] =~ /\D$/ ) )
    {
      if ( $semaphore eq "off" )
      {
        if ( not( "diluted" ~~ @calcprocedures ) )
        {
          my $lin = "$e[0],$e[1],$e[2],$e[3],$e[4],0.990,0.990,$e[7],$e[8],$e[9]";
          push( @firstloop, $lin );
          my $linn = "$e[0],$e[1],$e[2],$e[3],$e[4],0.990,0.990,$e[7],$e[8],$e[9]";
          push( @secondloop, $linn );
        }
        elsif ( "diluted" ~~ @calcprocedures )
        {
          my $lin = "$e[0],$e[1],$e[2],$e[3],$e[4],$e[5],$e[6],$e[7],$e[8],$e[9]";
          push( @firstloop, $lin );
          my $linn = "$e[0],$e[1],$e[2],$e[3],$e[4],$e[5],$e[6],$e[7],$e[8],$e[9]";
          push( @secondloop, $linn );
        }
      }
      elsif ( $semaphore eq "on" )
      {
        $exportrefl{ $row[1] }{ absout } =  $e[5];
        $exportrefl{ $row[1] }{ absin } = $e[6];  );
        if ( not( "diluted" ~~ @calcprocedures ) )
        {
          my $lin = "$e[0],$e[1],$e[2],$e[3],$e[4],0.990,0.990,$e[7],$e[8],$e[9]";
          push( @firstloop, $lin );
          my $linn = "$e[0],$e[1],$e[2],$e[3],$e[4],$e[5],$e[6],$e[7],$e[8],$e[9]";
          push( @secondloop, $linn );
        }
        elsif ( "diluted" ~~ @calcprocedures )
        {
          my $lin = "$e[0],$e[1],$e[2],$e[3],$e[4],0.990,0.990,$e[7],$e[8],$e[9]";
          push( @firstloop, $lin );
          my $linn = "$e[0],$e[1],$e[2],$e[3],$e[4],$e[5],$e[6],$e[7],$e[8],$e[9]";
          push( @secondloop, $linn );
        }
      }
    }
    else
    {
      push( @firstloop, $line );
      push( @secondloop, $line );
    }
  }


  open( my $MATDBFILE_F1, ">>$matdbfile_f1" ) or die;
  foreach my $line ( @firstloop )
  {
    say $MATDBFILE_F1 $line ;
  }
  close $MATDBFILE_F1;

  open( my $MATDBFILE_F2, ">>$matdbfile_f2" ) or die;
  foreach my $line ( @secondloop )
  {
    say $MATDBFILE_F2 $line ;
  }
  close $MATDBFILE_F2;
  return ( \%exportrefl );
}


sub adjust_radmatfile
{ # THIS CHECKS IF THE RADIANCE MATERIALS FILE HAS BEEN PROPERLY MODIFIED. IF NOT, THIS DOES THE MODIFICATION. THIS IS USED WHEN THE SPECULAR FRACTIONS AND ROUGHNESSES IN THE MATERIALS DATABASE ARE ALL SET TO 0.
  my ( $exportconstrref, $exportreflref, $conffile, $path, $specularratios_ref ) = @_;
  my %exportconstr = %$exportconstrref;
  my %exportrefl = %$exportreflref;
  my $radmat_f2 = $conffile;
  my @specularratios = @$specularratios_ref;

  my %hs;
  foreach $el ( @specularratios )
  {
    my @row = split( ":", $el );
    {
      $row[0] = "_" . $row[0] ;
      $hs{$row[0]}{spec} = $row[1];
      $hs{$row[0]}{roughn} = $row[2];
    }
  }

  $radmat_f2 =~ s/$path\/cfg\///;
  $radmat_f2 =~ s/.cfg//;
  $radmat_f2 = $radmat_f2 . "_Extern.mat";
  $radmat_f2 = "$path/rad/$radmat_f2";
  my $radmattemp = $radmat_f2 . ".temp";
  `mv -f $radmat_f2 $radmattemp`;
  open( RADMATTEMP, "$radmattemp" ) or die;
  my @lines = <RADMATTEMP>;
  close RADMATTEMP;
  open( RADMAT_F2, ">$radmat_f2" ) or die;
  my $count = 0;
  my @constrs = keys %exportconstr;
  foreach ( @lines )
  {
    my ( $spec, $roughn );
    my $lin = $lines[ $count + 4 ];
    my @arr = split( /\s+/, $lin );
    if ( ( $_ =~ /^#/ ) and ( $_ =~ /ternal MLC Colours.../ ) )
    {
      my $description = $lines[ $count + 1 ] ;

      foreach my $const ( keys %hs )
      {
        if ( $description =~ /$const/ )
        {
          $spec = $hs{$const}{spec};
          $roughn = $hs{$const}{roughn};
          $lines[ $count + 4 ] = "5  $arr[1] $arr[2] $arr[3] $spec $roughn \n";
          last;
        }
      }
    }
    print RADMAT_F2 $lines[ $count ];
    $count++;
  }
  close RADMAT_F2;
}


sub calcdirvectors
{ # THIS CALCULATES THE NEEDED DIRECTION VECTORS AT EACH GRID POINT.
  my @winscoords = @_;
  my ( @groupbag );
  foreach my $surf ( @winscoords )
  {
    my ( @surfbag );
    foreach my $v ( @$surf )
    {
      my @fields = @$v;
      my $coordsref = $fields[0];
      my @coords = @$coordsref;
      my $vertex = Vector::Object3D::Point->new( x => $coords[0], y => $coords[1], z => $coords[2], );
      push ( @surfbag, $vertex);
    }

    my $polygon = Vector::Object3D::Polygon->new(vertices => [ @surfbag ]);
    my $normal_vector = $polygon->get_normal_vector;
    my ($x_, $y_, $z_) = $normal_vector->array;
    my ( $x, $y, $z ) = ( -$x_, -$y_, -$z_ );
    my $max = max( abs($x), abs($y), abs($z) );
    my @dirvector;
    unless ( $max == 0 )
    {
      $x = ( $x / $max );
      $y = ( $y / $max );
      $z = ( $z / $max );
      @dirvector =  ( $x, $y, $z );
    }
    else
    {
      @dirvector =  ( $x, $y, $z );
    }
    push ( @groupbag, [ @dirvector ] )
  }
  return ( @groupbag);
}

sub prunepoints
{ # IT PRUNES AWAY THE GRID POINTS FALLING OUTSIDE THE SURFACE.
  my ( $gridpoints_transitionalref, $xyzcoordsref ) = @_;
  my @gridpoints = @$gridpoints_transitionalref;
  my @vertstaken = @$xyzcoordsref;

  my @verts;
  foreach ( @vertstaken )
  {
    my @fields = @$_;
    my @xs = @{ $fields[0] };
    my @ys = @{ $fields[1] };
    my @zs = @{ $fields[2] };
    my $i = 0;
    my @bag;
    foreach ( @xs )
    {
      push ( @bag, [ $xs[ $i ], $ys[ $i ], $zs[ $i ] ] );
      $i++;
    }
    push ( @verts, [ @bag ] );
  }

  my ( @coords, @prunegridpoints );

  foreach my $v ( @gridpoints )
  {
    my @fields = @$v;
    my $coordsref = $fields[0];
    push( @coords, [ @$coordsref ] );
  }

  my ( @boxpointxy, @boxpointxz, @boxpointyz );
  foreach my $gridpoint ( @coords )
  {
    my ( @point_xys, @point_xzs, @point_yzs );
    foreach ( @$gridpoint )
    {
      push ( @point_xys, [ $_->[0], $_->[1] ] );
      push ( @point_xzs, [ $_->[0], $_->[2] ] );
      push ( @point_yzs, [ $_->[1], $_->[2] ] );
    }
    push ( @boxpointxy, [ @point_xys ] );
    push ( @boxpointxz, [ @point_xzs ] );
    push ( @boxpointyz, [ @point_yzs ] );
  }

  my ( @boxvertxy, @boxvertxz, @boxvertyz );
  foreach my $surf ( @verts )
  {
    my ( @vert_xys, @vert_xzs, @vert_yzs );
    foreach my $vert ( @$surf )
    {
      push ( @vert_xys, [ $vert->[0], $vert->[1] ] );
      push ( @vert_xzs, [ $vert->[0], $vert->[2] ] );
      push ( @vert_yzs, [ $vert->[1], $vert->[2] ] );
    }
    push ( @boxvertxy, [ @vert_xys ] );
    push ( @boxvertxz, [ @vert_xzs ] );
    push ( @boxvertyz, [ @vert_yzs ] );
  }

  my $count = 0;
  my ( $vert_xys, $vert_xzs, $vert_yzs, $polyxy, $polyxz, $polyyz );
  my ( @verts_xys, @verts_xzs, @verts_yzs);
  foreach my $case ( @boxvertxy )
  {
    $vert_xys = $boxvertxy[$count];
    $vert_xzs = $boxvertxz[$count];
    $vert_yzs = $boxvertyz[$count];
    $polyxy = Math::Polygon::Tree->new( $vert_xys );
    $polyxz = Math::Polygon::Tree->new( $vert_xzs );
    $polyyz = Math::Polygon::Tree->new( $vert_yzs );
    $count++;
  }

  my $count = 0;
  my @newbox;
  foreach my $caseref ( @gridpoints )
  {
    my @case = @$caseref;
    my $surfnum = $case[ 1 ];
    my $dirvector = $case[ 2 ];
    my @bag;
    foreach my $vert ( @{ $case[ 0 ] } )

    {
      my $xyref = $boxpointxy[ $count ][ 0 ];
      my $xzref = $boxpointxz[ $count ][ 0 ];
      my $yzref = $boxpointyz[ $count ][ 0 ];
      unless ( ( ( $polyxy->contains( $xyref ) ) == 0 ) and ( ( $polyxz->contains( $xzref ) ) == 0 ) and ( ( $polyyz->contains( $yzref ) ) == 0 ) )
      {
        push( @bag, $vert );
      }
    }
    push ( @newbox, [ [ @bag ], $surfnum, $dirvector ] );
    $count++;
  }
  return ( @newbox );
}


sub modish
{ # MAIN PROGRAM
  my @things = @_; say "THINGS: @things";
  my $modishdefpath;

  my $launchfile = shift( @things );
  my ( @restpars, @settings, @received );
  my @received = @things;

  if ( not ( @ARGV) )
  {
    foreach ( @received )
    {
      if ( not ( ref( $_ ) ) )
      {
        push( @restpars, $_ );
      }
      else
      {
        @settings = @{ $_ };
      }
    }
  }
  else
  {
    foreach ( @received )
    {
      if ( not ( ref( $_ ) ) )
      {
        push( @restpars, $_ );
      }
      else
      {
        push( @settings );
      }
    }
  }

  if ( scalar( @restpars ) == 0 ) { say "NO ZONE HAVE BEEN SPECIFIED. EXITING." and die; }

  my ( $conffile, $path, $zonenum, $dirvectorsnum, $bounceambnum, $bouncemaxnum, $distgrid, $threshold, $radpath );
  my ( @transpdata, @surfaces, @dirvectorsrefs, @transpsurfs, @resolutions, @treatedlines );

  say "Setting things up...\n";

  my $path = definepath( $launchfile );

  my $radpath = $path . "/rad";

  say REPORT


  ##################################################

  my $zonenum = $restpars[0];
  my @transpsurfs = @restpars[ 1..$#restpars ];

  if ( scalar( @{ $settings } ) == 0 )
  {
    if ( -e "$modishdefpath" )
    {
      require "$modishdefpath";
      @resolutions = @{ $defaults[0] };
      $dirvectorsnum = $defaults[1];
      $bounceambnum = $defaults[2];
      $bouncemaxnum = $defaults[3];
      $distgrid = $defaults[4];
      $threshold = $defaults[5];
    }
    elsif ( -e "./modish_defaults.pl" )
    {
      require "./modish_defaults.pl";
      @resolutions = @{ $defaults[0] };
      $dirvectorsnum = $defaults[1];
      $bounceambnum = $defaults[2];
      $bouncemaxnum = $defaults[3];
      $distgrid = $defaults[4];
      $threshold = $defaults[5];
    }
  }
  else
  {
    @resolutions = @{ $settings[0] };
    $dirvectorsnum = $settings[1];
    $bounceambnum = $settings[2];
    $bouncemaxnum = $settings[3];
    $distgrid = $settings[4];
    $threshold = $settings[5];
  }

  my $writefile = "$path/writefile.txt";
  open ( REPORT, ">$writefile" ) or die "Can't open $writefile !";

  if ( not ( @resolutions ) ) { @resolutions = ( 2, 2 ); };
  if ( not defined( $dirvectorsnum ) ) { $dirvectorsnum = 1; };
  if ( not defined( $bounceambnum ) ) { $bounceambnum = 1; };
  if ( not defined( $bouncemaxnum ) ) { $bouncemaxnum = 7; };
  if ( not defined( $distgrid ) ) { $distgrid = 0.01; };
  if ( not defined( $threshold ) ) { $threshold = 0.99; };
  if ( not defined( $computype ) ) { $computype = "linear"; };
  if ( not ( @calcprocedures ) ) { @calcprocedures = ( ); };
  if ( not ( @specularratios ) ) { @specularratios = ( ) }
  #if ( not defined( $max_processes ) ) { $max_processes = 1; };

  push ( @calcprocedures, "besides", "extra" ); # THESE SETTINGS WERE ONCE SPECIFIABLE IN THE CONFIGURATION FILE.
  # "complete" means that both reflections due to direct radiation and reflections due to
  # diffuse radiation are taken into account.
  # "besides" means that the specular ratio (direct reflectivity to diffuse reflectivity)
  # of the obstructions (reflectors) is also specified in the Radiance database.
  # "extra" means that also the specular ratio of all other materials is specified
  # in the Radiance database.


# Debug output from ESP-r (out.txt in /cfg and /rad), $debug = 1 to enable.
  my $debug = 0;
  if ( $debug == 1 )
  {
    say REPORT "ESP-r debug output activated.";
    if ( -e "$path/cfg/out.txt" )
    {
      say REPORT "rm $path/cfg/out.txt";
      `rm $path/cfg/out.txt`;
    }
    say REPORT "touch $path/cfg/out.txt";
    `touch $path/cfg/out.txt`;
    if ( -e "$path/rad/out.txt" )
    {
      say REPORT "rm $path/rad/out.txt";
      `rm $path/rad/out.txt`;
    }
    say REPORT "touch $path/rad/out.txt";
    `touch $path/rad/out.txt`;
  }

  my ( $conffile, $conffile_f1, $conffile_f2, $conffile_f3, $constrdbfile, $constrdbfile_f,
  $matdbfile, $matdbfile_f1, $matdbfile_f2, $flagconstrdb, $flagmatdb, $flaggeo, $flagconstr, $originalsref,
  $fictitia1ref, $fictitia2ref, $fictitia3ref ) = createfictitiousfiles( $launchfile, $path, $zonenum );

  my @basevectors = getbasevectors( $dirvectorsnum );

  my @originals = @$originalsref;
  my @fictitia1 = @$fictitia1ref;
  my @fictitia2 = @$fictitia2ref;
  my @fictitia3 = @$fictitia3ref;

  my ( @daylighthours);
  my %actiondata;
  my @zoneoriginals = @originals;
  shift(@zoneoriginals); shift(@zoneoriginals);
  my @zonefictitia1 = @fictitia1; # "BLACK" MODEL
  shift(@zonefictitia1); shift(@zonefictitia1);
  my @zonefictitia2 = @fictitia2; # "REFLECTIVE" MODEL
  shift(@zonefictitia2); shift(@zonefictitia2);
  my @zonefictitia3 = @fictitia3;
  shift(@zonefictitia3); shift(@zonefictitia3);

  my ( %zonefilelists, %fict1filelists, %fict2filelists, %fict3filelists );
  my @daylighthoursarr;
  my %daylighthours;
  my ( $exportreflref__, $exportconstrref__ );

  my $tempmod = "$launchfile.mod.temp";
  my ( $tempmoddir, $tempreportdir );
  if ( $^O eq "linux" ) # THESE LINES DEPEND FROM THE OPERATING SYSTEM.
  {
    $tempmod =~ s/$path\/cfg\///;
    $tempmod = "$path/tmp/$tempmod";
    unless ( -e "$path/tmp" )
    {
      `mkdir $path/tmp`;
      say REPORT "mkdir $path/tmp";
    }
  }
  elsif ( $^O eq "darwin" )
  { ; }

  say REPORT "\$tempmod $tempmod";
  open ( TEMPMOD, ">$tempmod" ) or die "$!";

  my $tempreport = "$launchfile.report.temp";
  if ( $^O eq "linux" ) # THESE LINES DEPEND FROM THE OPERATING SYSTEM.
  {
    $tempreport =~ s/$path\/cfg\///;
    $tempreport = "$path/tmp/$tempreport";
  }
  elsif ( $^O eq "darwin" )
  { ; }

  open ( TEMPREPORT, ">$tempreport" ) or die "$!";

  $tempmoddir = $tempmod . ".dir";
  open ( TEMPMODDIR, ">$tempmoddir" ) or die "$!";

  $tempreportdir = $tempreport . ".dir";
  open ( TEMPREPORTDIR, ">$tempreportdir" ) or die "$!";

  my @treatedlines;

  `cp -f ./fix.sh $path/rad/fix.sh`;
  say REPORT "cp -f ./fix.sh $path/rad/fix.sh\n";
  `chmod 755 $path/rad/fix.sh`;
  `chmod 755 ./fix.sh`;
  say REPORT "chmod 755 $path/rad/fix.sh\n";
  `cp -f ./perlfix.pl $path/rad/perlfix.pl`;
  say REPORT "cp -f ./perlfix.pl $path/rad/perlfix.pl\n";

  my $countzone = 1;
  foreach my $elt (@zoneoriginals)
  {
    my @zonefiles = @$elt;
    my @fict1files = @{ $zonefictitia1[ $countzone - 1 ] };
    my @fict2files = @{ $zonefictitia2[ $countzone - 1 ] };
    my @fict3files = @{ $zonefictitia3[ $countzone - 1 ] };
    my $geofile = $zonefiles[0];
    my $constrfile = $zonefiles[1];
    my $shdfile = $zonefiles[2];
    my $zonenum_cfg = $zonefiles[3];
    my $geofile_f = $fict1files[0];
    my $constrfile_fict = $fict1files[1];
    $zonefilelists{ $zonenum }{ geofile } = $geofile;
    $zonefilelists{ $zonenum }{ geofile_f } = $geofile_f;
    $zonefilelists{ $zonenum }{ constrfile } = $constrfile;
    $zonefilelists{ $zonenum }{ constrfile_f } = $constrfile_f;
    $zonefilelists{ $zonenum }{ shdfile } = $shdfile;

    my ( $transpeltsref, $geofilestructref, $surfslistref, $obsref, $obsconstrsetref, $datalistref ) = readgeofile( $geofile, \@transpsurfs, $zonenum );

    my @transpelts = @$transpeltsref;
    my @geodata = @$geofilestructref;
    my %surfslist = %$surfslistref;
    my @obsdata = @$obsref;
    my @obsconstrset = @$obsconstrsetref;
    my %datalist = %$datalistref;

    createfictgeofile( $geofile, \@obsconstrset, $geofile_f );

    setroot( $conffile_f1, $path, $debug );
    setroot( $conffile_f2, $path, $debug );

    my ( $materialsref, $newmaterialsref, $matnumsref, $newmatnumsref, $exportconstrref ) =
    createconstrdbfile( $constrdbfile, $constrdbfile_f, \@obsconstrset );

    my $exportreflref;

    $exportreflref = creatematdbfiles( $materialsref, $newmaterialsref, $matnumsref, $newmatnumsref,
      $matdbfile, $matdbfile_f1, $matdbfile_f2, \@calcprocedures );

    my ( $surfnumsref, $surfnamesref ) = tellsurfnames( \@transpsurfs, \@geodata );
    my @surfnums = @$surfnumsref;
    my @surfnames = @$surfnamesref;
    my ( $winseltsref, $datalistref ) = readverts( \@transpelts, $geofile, \@geodata, \%datalist );
    my @winselts = @$winseltsref;
    my %datalist = %$datalistref;
    my ( $winscoordsref, $datalistref ) = readcoords( \@winselts, $geofile, \@geodata, \%datalist, \@transpelts );
    my @winscoords = @$winscoordsref;
    my %datalist = %$datalistref;
    my @dirvectorsrefs = calcdirvectors( @winscoords );
    my @xyzcoords = getcorners( \@winscoords, \@winselts );
    my @extremes = findextremes( @xyzcoords );
    my @gridcoords = makecoordsgrid( \@extremes, \@resolutions, \@dirvectorsrefs );
    my @gridpoints_transitional = makegrid( @gridcoords );
    my @gridpoints_newtransitional = prunepoints( \@gridpoints_transitional, \@xyzcoords );
    my @gridpoints = adjustgrid( \@gridpoints_newtransitional, $distgrid );

    my ( $treatedlinesref, $filearrayref, $monthsref ) = readshdfile( $shdfile );
    @treatedlines = @$treatedlinesref;
    my @shdfilearray = @$filearrayref;
    my @months = @$monthsref;
    my @shdsurfdata = getsurfshd( \@shdfilearray, \@months, \@surfnums, \@surfnames );
    @daylighthoursarr = checklight( \@shdfilearray, \@months );
    %daylighthours = populatelight( @daylighthoursarr );
    $shdfileslist{ $zonenum } = \@treatedlines;
    $countzone++;

    my @radfilesrefs = tellradfilenames( $path, $conffile_f1, $conffile_f2, $conffile_f3 );
    my ( $hashirrsref, $irrvarsref );

    $hashirrsref = pursue( { zonenum => $zonenum, geofile => $geofile, constrfile => $constrfile, shdfile => $shdfile, gridpoints => \@gridpoints, shdsurfdata => \@shdsurfdata, daylighthoursarr => \@daylighthoursarr, daylighthours=> \%daylighthours, shdfilearray => \@shdfilearray, exportconstrref => $exportconstrref, exportreflref => $exportreflref, conffile => $conffile,  path => $path, radpath => $radpath, basevectors => \@basevectors, resolutions => \@resolutions, dirvectorsnum => $dirvectorsnum, calcprocedures => \@calcprocedures, specularratios => \@specularratios, bounceambnum => $bounceambnum, bouncemaxnum => $bouncemaxnum, radfilesrefs => \@radfilesrefs, conffile_f1 => $conffile_f1, conffile_f2 => $conffile_f2, conffile_f3 => $conffile_f3, transpsurfs=> \@transpsurfs } );

    $irrvarsref = compareirrs( \%zonefilelists, $hashirrsref, $computype, \@calcprocedures );

    foreach my $elm ( @transpsurfs )
    {
      my @transpsurfs;
      push ( @transpsurfs, $elm );
      say "Closing calculations for surface " . dump( @transpsurfs );
      modifyshda( \@comparedirrs, \%surfslist, \%zonefilelists, \%shdfileslist, \%daylighthours, $irrvarsref, $threshold, $tempmod, $tempreport,  $tempmoddir, $tempreportdir, $elm, "diffuse", \@calcprocedures );

      modifyshda( \@comparedirrs, \%surfslist, \%zonefilelists, \%shdfileslist, \%daylighthours, $irrvarsref, $threshold, $tempmod, $tempreport,  $tempmoddir, $tempreportdir, $elm, "direct", \@calcprocedures );
    }
  }

  close TEMPMOD;
  open ( TEMPMOD, "$tempmod" ) or die;
  my @tempmodlines = <TEMPMOD>;
  close TEMPMOD;
  @tempmodlines = uniq( @tempmodlines );

  close TEMPREPORT;
  open ( TEMPREPORT, "$tempreport" ) or die;
  my @tempreportlines = <TEMPREPORT>;
  close TEMPREPORT;
  @tempreportlines = uniq( @tempreportlines );

  close TEMPMODDIR;
  open ( TEMPMODDIR, "$tempmoddir" ) or die;
  my @tempmoddirlines = <TEMPMODDIR>;
  close TEMPMODDIR;
  @tempmoddirlines = uniq( @tempmoddirlines );

  close TEMPREPORTDIR;
  open ( TEMPREPORTDIR, "$tempreportdir" ) or die;
  my @tempreportdirlines = <TEMPREPORTDIR>;
  close TEMPREPORTDIR;
  @tempreportdirlines = uniq( @tempreportdirlines );

  setroot( $launchfile, $path, $debug);

  my $shdfile = $zonefilelists{ $zonenum }{ shdfile };
  my $shdafile = "$shdfile" . "a";
  my $shdafilemod = $shdafile;
  $shdafilemod =~ s/.shda/.mod.shda/;
  open ( SHDAMOD, ">$shdafilemod" ) or die;

  my $shdafilereport = $shdafile;
  $shdafilereport =~ s/.shda/.report.shda/;
  `cp -R -f $shdafile $shdafilereport`;
  open ( SHDAREPORT, ">>$shdafilereport" ) or die;
  print SHDAREPORT "# FOLLOWING, THE VERIFIED VARIATIONS (AS RATIOS) OF IRRADIANCES DUE TO REFLECTIONS BY OBSTRUCTIONS.\n";

  my $counter = 0;;
  foreach my $lin ( @tempreportlines )
  {
    my $lindir = $tempreportdirlines[ $counter ];
    print SHDAREPORT $lindir;
    print SHDAREPORT $lin;
    $counter++;
  }
  close SHDAREPORT;

  my @container;
  my ($currentmonth, $signal );
  foreach my $lin ( @treatedlines )
  {
    my @arr = split(/\s+|,/, $lin);
    if ( $lin =~ /^\* month:/ )
    {
      $currentmonth = $arr[2];
      $currentmonth =~ s/`//g;
    }

    if ( ( $lin =~ /24 hour external surface shading/ ) or ( $lin =~ /\* month:/ ) or ( $lin =~ /\* end/ ) or ( $lin =~ /\* end/ ) or ( $lin =~ /Shading and insolation data in db/ ) )
    {
      $signal = "on";
    }
    elsif ( $lin =~ /24 hour internal surface insolation/ )
    {
      $signal = "off";
    }

    my $count = 0;
    my $i = 0;
    foreach my $el ( @tempmodlines )
    {
      my $eldir = $tempmoddirlines[ $i ];
      my @modarrdir = split( /\s+|,/, $eldir );
      my @modarr = split( /\s+|,/, $el );
      if ( $signal eq "on" )
      {
        push( @arr, $currentmonth );
        if ( ( $arr[25] eq $modarrdir[25] ) and ( $arr[28] eq $modarrdir[28] ) and ( $arr[29] eq $modarrdir[29] ) )
        {
          $eldir =~ s/ $currentmonth?//;
          push( @container, $eldir );
          $count++;
          last;
        }
        elsif ( ( $arr[25] eq $modarr[25] ) and ( $arr[28] eq $modarr[28] ) and ( $arr[29] eq $modarr[29] ) )
        {
          $el =~ s/ $currentmonth?//;
          push( @container, $el );
          $count++;
          last;
        }
      }
      $i++;
    }

    if ( $count == 0 )
    {
      push( @container, $lin );
    }

  }


  my $signalins;

  foreach my $lin ( @container )
  {
    if ( ( $lin =~ / # diffuse - / ) or ( $lin =~ / # direct - / ) )
    {
      my  @arr = split(/\s+|,/, $lin);
      my @firstarr = @arr[ 0..11 ];
      my @secondarr = @arr[ 12..$#arr ];
      my $joinedfirst = join ( ' ' , @firstarr );
      my $joinedsecond = join ( ' ' , @secondarr );
      $lin = "$joinedfirst\n" . "$joinedsecond\n";
    }

    if ( "noins" ~~ @calcprocedures )
    {
      if ( ( $lin =~ /24 hour external surface shading/ ) or
        ( $lin =~ /\* month:/ ) or ( $lin =~ /\* end/ ) or
        ( $lin =~ /Shading and insolation data in db/ ) )
      {
        $signalins = "off";
        say REPORT "signalins off";
      }
      elsif ( $lin =~ /24 hour internal surface insolation/ )
      {
        $signalins = "on";
        say REPORT "signalins on";
      }
    }

    unless ( $signalins eq "on" )
    {
      print SHDAMOD $lin;
      say REPORT "I AM GOING TO PRINT THIS IN $shdafilemod: " . "$lin, because \$signalins is $signalins." ;
    }

  }
  close SHDAMOD;
}

if ( @ARGV )
{
  modish( @ARGV );
}

1;
