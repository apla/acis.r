package ACIS::Citations::Search;

use strict;
use warnings;

use Carp;
use Carp::Assert;
use Encode;

use base qw( Exporter );
use vars qw( @EXPORT_OK );

@EXPORT_OK = qw( personal_search_by_names personal_search_by_documents );

use Web::App::Common;

use ACIS::Citations::Utils qw( build_citations_index today );
use ACIS::Citations::Suggestions qw( load_coauthor_suggestions_new );
use ACIS::Citations::SimMatrix qw( load_similarity_matrix );


# exportable:
# 
#   search_for_document( docid )
#             - find pre-identified citations [30 min]
#
#   search_for_personal_names( names ) - [30 min]
#             - names must be a set of normalized strings
#
#   compare_citation_to_doc( $cit, $doc ) 
#             - find out similarity value and store it [60 min]
#
#   filter_search_results( $results, $filterset )
#             - used to filter out identified or refused citations [45 min]
#
#   sort_search_results( $results, $matrix ) [45 min]
#
#


my $acis;
my $sql;

sub prepare() {
  $acis = $ACIS::Web::ACIS;
  $sql  = $acis -> sql_object;
}


sub search_for_document($) {
  my $docid = shift || die;
  if ( not $sql ) { prepare; }

  debug "search_for_documents: $docid";

  $sql -> prepare_cached( "select * from citations where trgdocid=?" );
  my $r = $sql -> execute( $docid );
  my @cl = ();
  while ( $r and $r->{row} ) {
    my $c = { %{$r->{row}} };
    $c->{ostring} = Encode::decode_utf8( $c->{ostring} );
    $c->{nstring} = Encode::decode_utf8( $c->{nstring} );
    push @cl, $c;
    $r->next;
  }
  debug "search_for_documents: found ", scalar @cl, " items";
  return \@cl;
}


sub search_for_personal_names($) {
  my $names = shift || die;

  if ( not $sql ) { prepare; }

  debug "search_for_personal_names: $names (" , scalar @$names, " names)";

  my @cl = ();
  $sql -> prepare_cached( "select * from citations where nstring REGEXP ?" );
  foreach ( @$names ) {
    my $n = $_;
    $n =~ s/([\.{}()|*?])/\\$1/g;
    my $r = $sql -> execute( "[[:<:]]$n\[[:>:]]" );
    while ( $r and $r->{row} ) {
      my $c = { %{$r->{row}} };
      $c->{ostring} = Encode::decode_utf8( $c->{ostring} );
      $c->{nstring} = Encode::decode_utf8( $c->{nstring} );
      push @cl, $c;
      $r->next;
    }
  }

  debug "search_for_personal_names: found ", scalar @cl, " citations";
  return \@cl;
  
}


sub test_search() {
  require ACIS::Web;
  # home=> '/home/ivan/proj/acis.zet'
  my $acis = ACIS::Web->new(  );
  search_for_document( 'repec:fdd:fodooo:555' );
  search_for_personal_names( [ 'JOHN MAKLORVICH', 'KATZ HARRY', 'KATZ, HARRY'  ] );
}



sub filter_search_results($$) {
  my ( $results, $filterset ) = @_;

  # $filterset is a hash of the form { "srcdocsid-checksum" => citation }
  # as generated by build_citations_index in ACIS::Citations::Utils.

  foreach ( @$results ) {
    my $key = $_->{srcdocsid} . '-' . $_->{checksum};
    if ( $filterset->{$key} ) {
      undef $_;
    }
  }

  return clear_undefined $results;
  # clear_undefined returns the number of items cleared
}

my $identified;
my $refused;
my $identified_for_sid;

sub make_identified_n_refused ($) {
  my $rec = shift;

  if ( $identified ) {
    if ( $identified_for_sid eq $rec->{sid} ) { return; }
    else { undef $identified; }
  }

  $identified_for_sid = $rec->{sid} || die;
  $identified ||= {};
  my $identified_hl = $rec->{citations}{identified} || {};
  my $refused_l     = $rec->{citations}{refused}    || [];
    
  foreach ( keys %$identified_hl ) {
    my $list = $identified_hl ->{$_};
    build_citations_index $list, $identified;
  }

  $refused = build_citations_index $refused_l;
}


sub personal_search_by_documents {
  my $rec  = shift || die; 
  my $mat  = shift;
  my $psid = $rec->{sid};
  my $rp   = $rec->{contributions}{accepted} || [];
  my $rc   = $rec->{citations} ||= {};

  debug "personal_search_by_documents() for rec $psid";

  if ( not $sql ) { prepare; }

  my $autoadd = $rc->{meta}{'auto-identified-auto-add'} || 1;
  my @added   = ();

  # build identified index and refused index
  make_identified_n_refused $rec;


  $mat ||= load_similarity_matrix( $psid );
  $mat -> upgrade( $acis, $rec );

  # search 
  foreach ( @$rp ) {
    my $did  = $_->{id}  || next;
    my $dsid = $_->{sid} || next;
    
    my $r = search_for_document( $did );
    next if not scalar @$r;

    # process results
    filter_search_results( $r, $identified );
    filter_search_results( $r, $refused );
    next if not scalar @$r;

    if ( $autoadd ) {
      foreach ( @$r ) {
        debug "citation: '", $_->{nstring} , "' should be added to $dsid";
        $_->{autoadded}     = today(); # localtime( time );
        $_->{autoaddreason} = 'preidentified';
        identify_cit_to_doc( $rec, $dsid, $_ );
        $mat->remove_citation( $_ );
        push @added, [ $dsid, $_ ];
      }

    } else {
      $mat -> add_new_citations( $r, $dsid );
    } 
  }

  return ( \@added );
}





sub personal_search_by_names {
  my $rec  = shift;
  my $mat  = shift;
  my $psid = $rec->{sid};
  my $rp   = $rec->{contributions}{accepted} || [];
  my $rc   = $rec->{citations} ||= {};

  debug "personal_search_by_names() for rec $psid";

  if ( not $sql ) { prepare; }

  # build identified index and refused index
  make_identified_n_refused $rec;


  # list of names
  my $names;
  debug "preparing the nameset";
  {
    my $variations = $rec -> {name}{variations};
    assert( $variations );
    assert( ref $variations eq 'ARRAY' );
    my @namelist = sort { length( $b ) <=> length( $a ) } @$variations;
    # normalize the names or at least remove final dots
    foreach ( @namelist ) {
      s/\.$//;
    }
    $names = \@namelist;
  }
  

  # search 
  my $r = search_for_personal_names( $names );
  debug "\$r: ", scalar @$r;

  # filter
  debug "filtering...";
  filter_search_results( $r, $identified );
  filter_search_results( $r, $refused );
  debug "\$r: ", scalar @$r;
  return() if not scalar @$r;

  # load the matrix
  $mat ||= load_similarity_matrix( $psid );
  $mat-> upgrade( $acis, $rec );

  # filter known suggestions
  my $known = $mat -> filter_out_known( $r );
  my $new   = $r;
  debug "\$new: ", scalar @$new;
  my $n=0;
  foreach ( @$new ) {
    $n++;
    debug "$n: ", $_->{nstring};
  }


  # compare to documents!
  $mat -> add_new_citations( $new );

  # if user allows auto-additions, based on high similarity...
  my $autoadd = $rc->{meta}{'auto-identified-auto-add'} || 1;
  my $sim_threshold = $rc->{meta}{'auto-add-similarity-threshold'} 
    || $acis->config( 'citation-document-similarity-preselect-threshold' ) * 100; 

  # now find, which of the newly added citations have high
  # similarity value (but to only one of the documents)
  
  $rc->{meta}{'last-searched-nameset-date'} = $rec -> {name}{'last-change-date'};

  # return if nothing else to do
  return() if not $autoadd;

  # auto add
  my @added = ();
  foreach ( @$new ) {
    my $citation = $_;
    my $cid = $_->{srcdocsid} . '-' . $_->{checksum};
    my $candidate;

    foreach ( @$rp ) {
      my $doc  = $_;
      my $dsid = $_->{sid} || next;

      my $l = $mat->{citations}{$cid}{$dsid};
      
      for ( @$l ) {
        if ( $_->[1]{reason} eq 'similar' 
             and $_->[1]{similar} >= $sim_threshold ) {
          # similarity is high enough
          if ( $candidate ) {
            # more than one candidate, abort; XXX ???
            undef $candidate;
            last;

          } else {
            $candidate = $dsid;
          }
        }
      }
    }

    if ( $candidate ) {
      debug "citation: '", $citation->{nstring} , "' should be added to $candidate";
      $citation->{autoadded}     = today(); 
      $citation->{autoaddreason} = 'similar';
      identify_cit_to_doc( $rec, $candidate, $citation );
      $mat->remove_citation( $citation );
      push @added, [ $candidate, $citation ];
      # XXX Should I add here a call to 
      #suggest_citation_to_authors($_, $psid, $candidate)
      # ? for co-authorship claims? TBD
    }

  }
  return(\@added);
}



sub identify_cit_to_doc($$$) {
  my ( $rec, $dsid, $citation ) = @_;
  delete $citation->{reason};
  delete $citation->{time};

  my $citations = $rec->{citations}    ||= {};
  my $cidentified = $citations->{identified} ||= {};
  my $doclist   = $cidentified->{$dsid} ||= [];
  push @$doclist, $citation;

  # add to index
  my $cid = $citation->{srcdocsid} . '-' . $citation->{checksum};
  $identified -> {$cid} = $citation;

  debug "added citation $cid to identified for $dsid";
}


sub test_personal_citations_search {
  require ACIS::Web;
  my $acis = ACIS::Web->new(  );
  my $sql = $acis -> sql_object;
  $sql ->prepare( "delete from cit_suggestions where psid='ptestsid0' ");
  $sql ->execute;

  require ACIS::Web::UserData;
  my $udata = load ACIS::Web::UserData ( 'local/tests/testuserdata.xml' );
  my $rec = $udata->{records}[0] || die;
  debug "id: ", $rec->{id};

  my $names = $rec->{contributions}{autosearch}{'names-list'} || die;
  my $mat   = load_similarity_matrix( $rec->{sid} );
  
  $mat -> upgrade( $acis, $rec );
  $mat -> run_maintenance();

  personal_search_by_documents( $rec, $mat );
  personal_search_by_names( $rec, $mat );
  personal_search_by_coauthors( $rec, $mat );
}



sub personal_search_by_coauthors {
  my $rec  = shift || die; 
  my $mat  = shift;
  my $psid = $rec->{sid};
  my $rp   = $rec->{contributions}{accepted} || [];
  my $rc   = $rec->{citations} ||= {};

  debug "personal_search_by_coauthors() for rec $psid";

  if ( not $sql ) { prepare; }

  my $autoadd = $rc->{meta}{'co-auth-auto-add'} || 1;
  if ( !$autoadd ) { return (); }

  my @added   = ();

  # build identified index and refused index
  make_identified_n_refused $rec;

  if ( not $mat ) {
    $mat = load_similarity_matrix( $psid );
    $mat -> upgrade( $acis, $rec );
  }

  my $r = load_coauthor_suggestions_new( $psid );

  filter_search_results( $r, $identified );
  filter_search_results( $r, $refused );

  foreach ( @$r ) {
    my $dsid = $_->{dsid};
    my $citation = $_;
    my $reason = $_->{reason};

    # a suggestion becomes just a citation
    # copied 3 lines from ::SimMatrix
    delete $_->{dsid};
    delete $_->{psid};
    delete $_->{new};
    
    $citation->{autoadded}     = today(); 
    $citation->{autoaddreason} = $reason;
    identify_cit_to_doc( $rec, $dsid, $citation );
    $mat->remove_citation( $citation );
    push @added, [ $dsid, $citation ];
  }

  return ( \@added );
}









1;



