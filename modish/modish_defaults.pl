@defaults = ( [  2, 2 ], 1, 1, 2, 0.01, 0.99 );

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

@calcprocedures = ( "diluted" ); 
# "diluted" means that the two models from which the shading ratios are derived 
# are going to be the following: 1) a model in which all the surfaces are reflective, 
# excepted the obstructions, # which are black; 
# 2) a model in which everything is reflective.
# if @calcprocedures is instead left unspecified (empty), the two models 
# from which the shading ratios are derived are going to be the following:
# 1) a model in which everything is black, and 
# 2) a model in which all the surfaces are black, excepted the obstructions, 
# which are reflective.

%specularratios = ( );
# "roughnval" is the roughness value of obstructions (reflectors).
# "roughnroughval" is the roughness value of all other surfaces. 
# "specval" is the specular ratio of obstructions (reflectors).
# "specroughval" is the specular ratio of all other surfaces.
# All these values are optional.
# If they are specified, they override the values in the Radiance materials database. 
# Example:
# %specularratios = ( roughnval => 0, specval => 0.1, specroughval => 0, roughnroughval => 0 );

%skycondition = ( 1=> "clear", 2=> "clear", 3=> "clear", 4=> "clear", 5=> "clear", 6=> "clear", 7=> "clear", 8=> "clear", 9=> "clear", 10=> "clear", 11=> "clear", 12=> "clear" );
# PREVAILING CONDITION OF THE SKY FOR EACH MONTH, EXPRESSED WITH ITS NUMBER.
# THE OPTIONS ARE: "clear", "cloudy" and "overcast".
# IF NO VALUE IS SPECIFIED, THE DEFAULT IS "clear".

#$max_processes = 4; # NOT USABLE. LEFT AS A NOTE.
# MAXIMUM NUMBER OF PARALLEL CALLS TO RADIANCE.








