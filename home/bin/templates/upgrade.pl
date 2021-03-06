use strict;

#my $name;
my $verno;
my $old;

sub p {}; 
#sub p { print @_, "\n"; }

p "$0 debugings:";

if ( -f 'VERSION' ) {
  $old = `cat VERSION`;
}

if ( $old and     
     $old =~ 
     m!^([\w\-\,\.\s]+?)\s+(\d[\.\d\w]+)\s+(\d{4}-\d{2}-\d{2})\s\[(\w+)\]! ){
  #$name  = $1;
  $verno = $2;

} else {
  warn "no old version";
  $verno = '0.0';
}

$verno = normalize( $verno );
p "current verno: $verno";

my %index = ();
my @call;

if ( opendir BIN, "bin/" ) {
  my @scripts = readdir BIN;
  foreach ( @scripts ) {
    if ( $_ =~ /^upgrade_to_(\d[\d\.]+)$/ ) {
      p "script: $_";
      my $numberstring;
      if ( ($numberstring=normalize($1)) gt $verno ) {
        p "number: $numberstring";
        p "would run it";
        $index{$_} = $numberstring;
        push @call, $_;
      }
    }
  }
}

p "\@call before sort: ", join( ' ', @call ); 
@call = sort { $index{$a} cmp $index{$b} } @call;
p "\@call after sort: ", join( ' ', @call ); 

my $upgrade_flag = "state/service.blocked";
my $upgrade_flag_set;
if (scalar @call) {
  if ( not -f $upgrade_flag ) {
    system( "echo >$upgrade_flag" ); 
    $upgrade_flag_set=1;
  }
}

foreach ( @call ) {
  print "Now will run: $_\n";
  system( "bin/$_" ) == 0
    or warn "failed to execute: $?";

  if ($? == -1) {
    print "failed to execute: $!\n";

  } elsif ($? & 127) {
    printf "child died with signal %d, %s coredump\n",
      ($? & 127),  ($? & 128) ? 'with' : 'without';
    die;
  }
}

if ($upgrade_flag_set) {  
  unlink $upgrade_flag; 
}
if (scalar @call) {
  print "upgrade finished\n";
}

END {
  if ($upgrade_flag_set and -f $upgrade_flag) { 
    print "upgrade-in-progress flag is being left: $upgrade_flag\n";
  }
}

exit 0;


sub normalize {
  my $v = shift;
  $v =~ s/\.(\d+)/ sprintf( ".%05d", $1 ) /ge;
  return $v;
}

