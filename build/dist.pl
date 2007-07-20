#!/usr/bin/perl

#   This is the release packaging script for ACIS.  It increments
#   version numbers and saves it (along with the current date) into the
#   VERSION file of ACIS.  It updates extra/ directory with the recent
#   versions of the extra modules, if neccessary.  (via
#   get_latest_extra.pl)
#
#   Use: 
#
#      perl dist.pl [-f] [VERSION_NUMBER]
# 
#   The -f flag instructs the script to make a full release, ie. with
#   the extra components (modules).  If you do not, it makes just an
#   update release.
# 

use strict;

my $fullrelease = 0;
foreach (@ARGV) {
  if (m!-f!) {
    $fullrelease = 1;
    undef $_;
    last;
  }
}

my $newversion;
foreach( @ARGV ) {
  if ($_) {
    $newversion = $_;
    last;
  }
}

my $fullver = `cat VERSION`;
chomp $fullver;

my $name;
my $prev_verno;
my $prev_date;
my $prev_issue;

if ( $fullver =~ 
     m!^([\w\-\,\.\s]+?)\s+(\d[\.\d\w]+)\s+(\d{4}-\d{2}-\d{2})\s\[(\w+)\]! ){
  $name        = $1;
  $prev_verno  = $2;
  $prev_date   = $3;
  $prev_issue  = $4;

} else {
  die "can't parse VERSION";
}

my $issue;
my $date;
my $verno;


my $today = `date +\%F`;
chomp $today;

my $todayfull = `date`;
chomp $todayfull;

my $today8dig = $today; 
$today8dig =~ s!-!!g;

$date = $today;


# prepare the version number
if ( $newversion ) {
  $verno = $newversion; # just from the command line

} else { # increment the previous version
  my @ver = split /\./, $prev_verno;
  my $pos = 2;  
  $ver[$pos] ++;
  $verno = join( '.', @ver );
}

# make issue index, a letter
if ( $today eq $prev_date ) {
  if ($issue eq 'z') {  $issue = '@';  }
  $issue = chr( ord( $prev_issue )+1 );

} else { 
  $issue = 'a';
}

my $version = "$verno-$today8dig$issue";
my $fullrelease_string = '';
if($fullrelease) {
  $version .= '.with-libs';
  $fullrelease_string = ' with libs';
}

my $VERSION = "$name $verno $date \[$issue]$fullrelease_string\n".
  $todayfull . "\n";
print $VERSION, "file: $version\n";

if ( open VER, '>', 'VERSION' ) {
  print VER $VERSION;
  close VER;
}

system 'rm -rf extra/*';
if ( $fullrelease ) {
  require 'build/get_latest_extra.pl';
}


system "perl Makefile.PL";
system "make dist VERSION=$version";
system "cvs commit -m 'release $version' VERSION";
print "$name-$version.tar.gz\n";