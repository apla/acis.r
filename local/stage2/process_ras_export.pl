#!/usr/bin/perl

use strict;
use warnings;
use citec;

use vars qw($log_file $dbh $DBName $username );
do '/home/adnetec/RePEc/zzz/conf/citec.conf';

$log_file = 'process_ras_export.log';
$dbh = citec::connect($DBName,$username);

my $input = shift @ARGV;

if ( !-f $input or !-r _ ) {
  die "can't read $input";
}

open INPUT, "<$input" 
  or die "can't open $input";

my $findref_st = $dbh->prepare( "select id from REFERENCIA where docid=? and md5=?" ) or die;
my $addst = $dbh->prepare( "replace into CITA (cita,escitado,ref_cita,fecha) values (?,?,?,NOW())" ) or die;
my $delst = $dbh->prepare( "delete from CITA where cita=? and escitado=?" ) or die;

while( <INPUT> ) {
  chomp;
  my ($srcdocid,$md5,$trgdocid,$event) = split( /\t/, $_ );
  if ( not $event 
       or not $srcdocid 
       or not $trgdocid ) { next; }
  my $r = $findref_st->execute( $srcdocid, $md5 );
  my $array = $findref_st->fetchrow_arrayref
    if $r;
  my $refid = $array->[0]
    if $array;
  
  if (not $refid) {
    print "no reference: $srcdocid $md5\n";
  }
  $refid ||= '';
  if ( $event eq 'added' 
       or $event eq 'autoadded' ) {
#    print "add $refid -> $trgdocid\n";
    $addst->execute( $srcdocid, $trgdocid, $refid );
  } elsif ( $event eq 'unidentified' ) {
#    print "drop $refid -> $trgdocid\n";
    $delst->execute( $srcdocid, $trgdocid );
  }
}
