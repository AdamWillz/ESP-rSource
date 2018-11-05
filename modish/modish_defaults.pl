@defaults = ( [  2, 2 ], 5, 1, 2, 0.01, 0.99 );

### The above line means: ( [ resolution_x, resolution_y ], $dirvectorsnum, $bounceambnum, $bouncemaxnum, $distgrid, $threshold )
### resolution_x, resolution_y are the gridding values

### The value "$dirvectorsnum" controls the numbers of direction vectors that are used for
### computing the irradiances at each point of each grid over the surfaces. The values that currently
### can be chosen are 1, 5 and 9. When the points are more than 1, they are evenly distributed
### on a hemisphere following a geodetic pattern.

### $bounceambnum are the number of the bounces of the diffuse light which are taken into account

# $bouncemaxnum are the number of the bounces of the direct light which are taken into account

# $distgrid is the distance of the grid in meter out of the surfaces which are tamen into account

# $threshold is the threshold under which the changes of shading value are not taken into account.
# A value of "1" means that if the new shading value is increased instead of decreased in place of the old one,
# the change is not executed.

$computype = "linear";
# OPTIONS: "linear" and "root" (i.e. square root). THE RELATION ACCORDING TO WHICH THE SHADING RATIOS ARE CALCULATED.

@calcprocedures = ( "matname:Aluminium", "diluted" );
# "diluted" means that the two models from which the shading ratios are derived
# are going to be the following: 1) a model in which all the surfaces are reflective,
# excepted the obstructions, # which are black;
# 2) a model in which everything is reflective.
# if @calcprocedures is instead left unspecified (empty), the two models
# from which the shading ratios are derived are going to be the following:
# 1) a model in which everything is black, and
# 2) a model in which all the surfaces are black, excepted the obstructions,
# which are reflective.
# With "matname:name_of_a_materia" the name of a material
# which has been assigned to the reflective obstructions can be specified.
# This is essential for the calculations. This material may duplicate another material
# in the database, but its name must be unique. It is indeed better if this material
# is not shared by objects which are not reflective obstructions.
# The materials used in this manner for the reflective obstructions may be more than
# one, but all of them have to be declared in @calcprocedures as described.
# Giving to the materials used in the reflective obstructions their own class
# in the materials database can help to keep everything clear.

@specularratios = ( "reflector:0.03:0.05" );
# Here values of the kind "construction:specularratio:roughnessvalue"
# should be specified. For example, "reflector:0.03:0.05".
# The textual element ("reflector") is the name
# of a construction. The first number is the specular ratio
# for that construction. The second number is the roughness value.
# Specifying those values here makes possible
# to override the values specified in a Radiance database.
# (for example, the "0"s that may be in the database
# by defaul as regards specular ratios and the roughness values).

%skycondition = ( 1=> "clear", 2=> "clear", 3=> "clear", 4=> "clear", 5=> "clear", 6=> "clear", 7=> "clear", 8=> "clear", 9=> "clear", 10=> "clear", 11=> "clear", 12=> "clear" );
# PREVAILING CONDITION OF THE SKY FOR EACH MONTH, EXPRESSED WITH ITS NUMBER.
# THE OPTIONS ARE: "clear", "cloudy" and "overcast".
# IF NO VALUE IS SPECIFIED, THE DEFAULT IS "clear".

$max_processes = 7; # NOT USABLE. LEFT AS A NOTE.
# MAXIMUM NUMBER OF PARALLEL CALLS TO RADIANCE.
