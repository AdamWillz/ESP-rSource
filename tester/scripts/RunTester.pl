#!/usr/bin/perl
use strict;
use warnings;
# ====================================================================
# RunTester.pl
# Author: Adam Wills
# Date: Sep 2018

# DESCRIPTION:
# This script retrieves an ESP-r historical archive stored on Google
# drive, and runs tester.pl between a local compiled version of ESP-r
# and the archive.
# 

# ====================================================================
use Data::Dumper;

# GLOBALS
my @sCMDs; # Commands to download existing archive on Google Drive
my $iExit=0;

# INPUTS
my $ggID = "1s4Etf4QGrng7FouDcyNi8LXlXvYn0Spx"; # Google id for archive being retrieved
my $sPathToBin="/usr/esru/test/bin/";

# INTERMEDIATES
my $sGGfilename;

# Download the archive
#=========================
push(@sCMDs,'ggID=\''. $ggID .'\'');
push(@sCMDs,'ggURL=\'https://drive.google.com/uc?export=download\'');
push(@sCMDs,'filename="$(curl -sc /tmp/gcokie "${ggURL}&id=${ggID}" | grep -o \'="uc-name.*</span>\' | sed \'s/.*">//;s/<.a> .*//\')"');
push(@sCMDs,'getcode="$(awk \'/_warning_/ {print $NF}\' /tmp/gcokie)"');
push(@sCMDs,'curl -Lb /tmp/gcokie "${ggURL}&confirm=${getcode}&id=${ggID}" -o "${filename}"');
open(my $fh, '>',"GetArchive.sh") or die "Could not write GetArchive.sh $!\n";
print $fh '#!/bin/bash'."\n";
foreach my $scmd (@sCMDs) {
    print $fh $scmd."\n";
};
print $fh 'echo $filename';
close $fh;
# Run retrieval script and get file name
$sGGfilename=`bash GetArchive.sh`;
$sGGfilename=~ s/^\s+|\s+$//g ;     # remove both leading and trailing whitespace

# Run tester
#=========================
system("perl tester.pl -v $sPathToBin"."bps --test_loc $sPathToBin --historical_archive $sGGfilename") == 0 or die "system tester.pl failed: $?";

# Interrogate output
#=========================
open(my $fid, '<',"bps_test_report.txt") or die "Could not read bps_test_report.txt $!\n";
my @sAllData = <$fid>;
close $fid;
my $i=0;
until($sAllData[$i] =~ m/(Comparison of Numerical results)/) {$i++;}
$i+=2;
if($sAllData[$i] =~ m/(No differences were found in numerical output)/) {
    print "No differences were found in numerical output\n";
    exit 0;
} else {
    print "Numerical differences were found!!\n";
    exit 2;
};