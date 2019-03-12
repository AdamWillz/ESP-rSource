#!/usr/bin/perl
use strict;
use warnings;
# Inputs
my $sPathToBin="/usr/esru/devel";

# Run tester
#=========================
system("perl tester.pl -v  --databases $sPathToBin $sPathToBin/bin/bps --ref_loc $sPathToBin/bin/ --test_loc $sPathToBin/bin/ --create_historical_archive Devel_Base.tar.gz") == 0 or die "system tester.pl failed: $?";