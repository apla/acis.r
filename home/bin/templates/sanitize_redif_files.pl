
# this script checks every ReDIF file in the ReDIF output directory
# against the records table: if the ReDIF file exists, but the record
# is not in the records table, or the userdata file is not present, or
# the userdata file does not point to that record (by short-id), then
# the original ReDIF file should be removed. 

# this does not cover removing the AMF files and the profile pages. If
# a ReDIF file was left lingering, then the AMF and profile page are
# probably these too.

use Carp::Assert;

use sql_helper;

use warnings;

require ACIS::Web;
use Web::App::Common; 

my $safe_mode = 0;
foreach ( @::ARGV ) {
  if ( m/^--safe$/ ) {
    $safe_mode = 1;
    undef $_;
  }
}
clear_undefined( \@::ARGV );

sub p (@) {
  print @_, "\n";
}


my $acis = ACIS::Web -> new( homedir => $homedir );
assert( $acis );

my $sql = $acis -> sql_object;
$sql -> prepare( "select id,userdata_file from records where shortid =?" );


my $count = 0;
my $redif_dir = $acis -> config( "metadata-ReDIF-output-dir" );
if ( open FLIST, "find $redif_dir -type f -name '*.rdf'|" ) {
  while ( <FLIST> ) {
    if ( m!/(p[a-z]+\d+)\.rdf! ) {
      chomp;
      my $rfile = $_;
      my $sid  = $1;
      my $res  = $sql -> execute( $sid );
      my $cleanup;

      if ( $res and $res->{row} ) {
        my $id   = $res ->{row}{id};
        my $file = $res ->{row}{'userdata_file'};
        
        if ( not $file ) {
          p "$sid,$id - no file $file";
          next; 
        }
        
        if ( -e $file ) {
          if ( open UD, "<", $file ) {
            my @content = <UD>;
            my $content = join '', @content;
            close UD;
            if ( not $content ) {
              p "file is empty: $file (id: $id)";
              next;
            }
            
            my $test = "<sid>$sid</sid>";
            
            if ( index( $content, $test ) > 0 ) {
              #        print ".";
              next;
            } else {
              p "$sid: didn't find the right record in $file (id: $id)";
	      $cleanup = 1;
            }

          } else {
            p "$sid: can't open $file";
	    $cleanup = 1;
          }
          
        } else {
          p "$sid: no such file: $file";
	  $cleanup = 1;
        }
        
      } else {
	  $cleanup = 1;
	  p "$sid: no such record";
      }

      if ($cleanup) {
	if (not $safe_mode) {
	    unlink $rfile;
	    p "> $rfile removed";
	}
      }

    }
  }
}


close FLIST;

__END__

