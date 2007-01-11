package ACIS::Citations::Search;

use strict;
use warnings;

use Carp;
use Carp::Assert;
use Encode;

use base qw( Exporter );
use vars qw( @EXPORT_OK );

@EXPORT_OK = qw( personal_search_by_names personal_search_by_documents 
                 personal_search_by_coauthors );

use Web::App::Common;

use ACIS::Citations::Utils;
use ACIS::Citations::Suggestions qw( get_cit_old_status find_cit_sug_citations );


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
my $select_citations;

sub prepare() {
  $acis = $ACIS::Web::ACIS;
  $sql  = $acis -> sql_object;
  $select_citations = select_citations_sql( $acis );
}



sub decode_citations_search_results {
  my $r = shift;
  my @cl;

  while ( $r and $r->{row} ) {
    my $c = { %{$r->{row}} };
    foreach ( qw( ostring nstring srcdoctitle srcdocauthors ) ) {    
      $c->{$_} = Encode::decode_utf8( $r->{row}{$_} );
    }
    debug "found: ", $c->{nstring};
    push @cl, $c;
    $r->next;
  }
  return \@cl;
}

sub search_for_document($) {
  my $docid = shift || die;
  if ( not $sql ) { prepare; }

  debug "search_for_documents: $docid";

  $sql -> prepare_cached( "$select_citations where trgdocid=?" );
  my $r = $sql -> execute( $docid );
  my $cl = decode_citations_search_results( $r );
  debug "search_for_documents: found ", scalar @$cl, " items";
  return $cl;
}


sub search_for_personal_names($) {
  my $names = shift || die;

  if ( not $sql ) { prepare; }

  debug "search_for_personal_names: $names (" , scalar @$names, " names)";

  my @cl = ();
  $sql -> prepare_cached( "$select_citations where MATCH (nstring) AGAINST (? IN BOOLEAN MODE)" );
  
  my $q = '';
  foreach ( @$names ) {
    debug "name: $_";
    $q .= '"'. $_ . '" ';
  }
  chop $q;

  my $r = $sql -> execute( $q );
  my $cl = decode_citations_search_results( $r );
  debug "search_for_personal_names: found ", scalar @$cl, " citations";
  return $cl;
}

sub search_for_personal_names_original($) {
  my $names = shift || die;

  if ( not $sql ) { prepare; }

  debug "search_for_personal_names: $names (" , scalar @$names, " names)";

  my @cl = ();
  $sql -> prepare_cached( "$select_citations where nstring REGEXP ?" );
  foreach ( @$names ) {
    my $n = $_;
    $n =~ s/([\.{}()|*?])/\\$1/g;
    debug "name: $n";
    my $r = $sql -> execute( "[[:<:]]$n\[[:>:]]" );
    while ( $r and $r->{row} ) {
      my $c = { %{$r->{row}} };
      foreach ( qw( ostring nstring srcdoctitle srcdocauthors ) ) {    
        $c->{$_} = Encode::decode_utf8( $r->{row}{$_} );
      }
      debug "found: ", $c->{nstring};
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

sub make_identified_n_refused ($) {
  my $rec = shift;

  $identified = {};
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
  my $psid = $rec->{sid};
  my $rp   = $rec->{contributions}{accepted} || [];
  my $rc   = $rec->{citations} ||= {};

  debug "personal_search_by_documents() for rec $psid";

  if ( not $sql ) { prepare; }

  my $meta = $rc->{meta} ||= {};
  my $autoadd = (defined $meta->{'auto-identified-auto-add'} ) ? $meta->{'auto-identified-auto-add'} : 1;
  my @added   = ();

  # build identified index and refused index
  make_identified_n_refused $rec;

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
        next if get_cit_old_status( $psid, $dsid, $_->{citid} );

        debug "citation: '", $_->{nstring} , "' is to be added to $dsid";
        $_->{autoadded}     = today(); # localtime( time );
        $_->{autoaddreason} = 'preidentified';
        identify_cit_to_doc( $rec, $dsid, $_ );
        push @added, [ $dsid, $_ ];
      }

    } else {
      debug "citation: '", $_->{nstring} , "' should be suggested to $dsid";
    } 
  }

  return ( \@added );
}





use ACIS::Citations::CitDocSim;

sub personal_search_by_names {
  my $rec  = shift || die;
  my $pretend = shift && die "pretend not supported"; 
  my $psid = $rec->{sid};
  my $rp   = $rec->{contributions}{accepted} || [];
  my $rc   = $rec->{citations} ||= {};

  debug "personal_search_by_names() for rec $psid";

  if ( not $sql ) { prepare; }

  # build identified index and refused index
  make_identified_n_refused $rec;

  # build list of doc sids (research profile)
  my $rpdslist = [];
  foreach ( @$rp ) {
    if ( $_->{sid} ) { push @$rpdslist, $_->{sid}; } 
  }
  my $docs = make_docs( $rec );

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
      $_ = normalize_string( $_ );
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

  my $meta = $rc->{meta} ||= {};

  # if user allows auto-additions, based on high similarity...
  my $autoadd = (defined $meta->{'auto-identified-auto-add'}) ? $meta -> {'auto-identified-auto-add'} : 1;
  my $sim_threshold = $meta ->{'auto-add-similarity-threshold'} 
    || $acis->config( 'citation-document-similarity-preselect-threshold' ) * 100; 

  # auto add
  my @added = ();

  foreach ( @$r ) {
    my $citation = $_;
    my $cid = $_->{srcdocsid} . '-' . $_->{checksum};
    my $citid = $_->{citid} || die;

    # compare to documents!    
    my @comp = compare_citation_to_docs( $_, $docs );

    # if no matching document were found
    if ( not scalar @comp ) { next; }

    my $target = $comp[0];
    my $simity = $comp[1];

    if ( $autoadd 
         and $simity >= $sim_threshold 
         and not get_cit_old_status( $psid, $target, $citid ) ) {

      debug "citation: '", $citation->{nstring} , "' should be added to $target";
      $citation->{autoadded}     = today(); 
      $citation->{autoaddreason} = 'similar';
      if ( not $pretend ) {
        identify_cit_to_doc( $rec, $target, $citation );
#        unless ( $acis->config( 'citations-disable-coauthor-auto-suggest' ) ) {
#          suggest_citation_to_coauthors($_, $psid, $target); ### XXX???
#        }
      }
      push @added, [ $target, $citation ];
    }
  }
   
  $meta ->{'last-searched-nameset-date'} = $rec -> {name}{'last-change-date'};

  # return if nothing else to do
  return() if not $autoadd;
  return(\@added);
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
  personal_search_by_documents( $rec );
  personal_search_by_names( $rec );
  personal_search_by_coauthors( $rec );
}



sub personal_search_by_coauthors {
  my $rec  = shift || die; 
  my $pretend = shift; # do not add it, just check
  my $psid = $rec->{sid};
  my $rp   = $rec->{contributions}{accepted} || [];
  my $rc   = $rec->{citations} ||= {};

  debug "personal_search_by_coauthors() for rec $psid";

  if ( not $sql ) { prepare; }

  my $meta = $rc->{meta} ||= {};
  my $autoadd = (defined $meta -> {'co-auth-auto-add'}) ? $meta -> {'co-auth-auto-add'} : 1;
  if ( !$autoadd ) { return (); }

  my @added   = ();

  # build identified index and refused index
  make_identified_n_refused $rec;

  # search 
  foreach ( @$rp ) {
    my $did  = $_->{id}  || next;
    my $dsid = $_->{sid} || next;
    
    my $sr = find_cit_sug_citations( undef, $dsid );
    my $r  = decode_citations_search_results( $sr );
    next if not scalar @$r;

    # process results
    filter_search_results( $r, $identified );
    filter_search_results( $r, $refused );
    next if not scalar @$r;
    
    if ( $autoadd ) {
      foreach ( @$r ) {
        next if get_cit_old_status( $psid, $dsid, $_->{citid} );

        debug "citation: '", $_->{nstring} , "' is to be added to $dsid";
        $_->{autoadded}     = today(); # localtime( time );
        $_->{autoaddreason} = delete $_->{reason};
        identify_cit_to_doc( $rec, $dsid, $_ );
        push @added, [ $dsid, $_ ];
      }
      
    } else {
      debug "citation: '", $_->{nstring} , "' should be suggested to $dsid";
    } 
  }

  return ( \@added );
}

sub identify_cit_to_doc {
  my ( $rec, $dsid, $citation ) = @_;

  identify_citation_to_doc( $rec, $dsid, $citation );

  # add to index
  my $cid = $citation->{srcdocsid} . '-' . $citation->{checksum};
  $identified -> {$cid} = $citation;
}


sub clear_up {
  undef $identified;
  undef $refused;
}




1;



