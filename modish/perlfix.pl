#!/usr/bin/perl

if ( -e "./fixl.pl" )
{
	
	open ( FIXL, "./fixl.pl" ) or die( $! );
	my @files = <FIXL>;
	close FIXL;
	$" = " ";
	print "FILES: @files\n";
	my $to = $files[0];
	chomp( $to );
	print "TO: $to\n";
	
	my $from = $files[1];
	chomp( $from );
	print "FROM: $from\n";
	
	`cp -f $from $to`;
	print "WHAT I AM DOING IS: cp -f $from $to \n";
}
