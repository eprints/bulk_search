package EPrints::Plugin::Screen::Staff::EPrintBulkSearch;

@ISA = ( 'EPrints::Plugin::Screen::AbstractSearch' );

use strict;

sub new
{
  my( $class, %params ) = @_;

  my $self = $class->SUPER::new(%params);
     
  $self->{appears} = [
    {
      place => "admin_actions_editorial",
      position => 900,
    },
  ];

  return $self;
}

sub search_dataset
{
  my( $self ) = @_;

  return $self->{session}->get_repository->get_dataset( "eprint" );
}

sub search_filters
{
  my( $self ) = @_;

  return;
}

sub allow_export { return 1; }

sub allow_export_redir { return 1; }

sub can_be_viewed
{
  my( $self ) = @_;

  return $self->allow( "eprint/search/staff" );
}

sub from
{
  my( $self ) = @_;

  my $sconf = {
    staff => 1,
    dataset_id => "eprint",
    citation => $self->{session}->get_repository->get_conf( "search","advanced","citation" ),
    # order_methods => $self->{session}->get_repository->get_conf( "search","advanced","order_methods" ),
    # default_order => $self->{session}->get_repository->get_conf( "search","advanced","default_order"),

    order_methods => {
      "byyear"         => "-date/creators_name/title",
      "byyearoldest"   => "date/creators_name/title",
      "byname"         => "creators_name/-date/title",
      "bytitle"        => "title/creators_name/-date"
    },
    default_order => "byyear",
  };

  $sconf->{"search_fields"} = [
    { meta_fields => [ "eprintid" ] },
  ];

  $self->{processor}->{sconf} = $sconf;
  $self->SUPER::from;
}

sub _vis_level
{
  my( $self ) = @_;

  return "staff";
}

sub get_controls_before
{
  my( $self ) = @_;

  return $self->get_basic_controls_before;        
}

sub render_result_row
{
  my( $self, $session, $result, $searchexp, $n ) = @_;

  return $result->render_citation_link_staff(
    $self->{processor}->{sconf}->{citation},  #undef unless specified
    n => [$n,"INTEGER"]
  );
}

sub run_search
{
  my( $self ) = @_;

  # dont perform a normal search, hijack the eprintid and load it as a list of items
  # a normal search can cope with searching for a set of separte eprintid, only ranges or a single

  # my $list = $self->{processor}->{search}->perform_search();
  my $input_value = $self->{processor}->{search}->{searchfieldmap}->{eprintid}->{value};
  $input_value =~ s/[\t\n\r, ]+/ /g; # separators to space
  $input_value =~ s/[^0-9]/ /g; # non numbers to space
  $input_value =~ s/^ / /; # remove leading space
  $input_value =~ s/\s+/ /g; # Remove excess spaces
  my @ids = split(/ /, $input_value); # split on space to get a list of numbers

  my $order = $self->{session}->param( "order" ); # else undef is fine
  my $list = EPrints::List->new( session => $self->{session}, dataset => $self->search_dataset, ids => \@ids, order => $order );
  $list = $list->reorder( $order ) if $order; # actually sort by the order

  # Remove id's which do not relate to an eprints
  my @real_ids = ();
  $list->map( sub {
        my( $session, $dataset, $eprint ) = @_;

        push( @real_ids, $eprint->get_value('eprintid') );
  });
  $list = EPrints::List->new( session => $self->{session}, dataset => $self->search_dataset, ids => \@real_ids, order => $order );

  # normal search from here on

  my $error = $self->{processor}->{search}->{error};
  if( defined $error )
  {       
    $self->{processor}->add_message( "error", $error );
    $self->{processor}->{search_subscreen} = "form";
  }

  # we want to filter the search results by an arbitrary criteria
  my $dataset_id = $list->{dataset}->base_id();
  my $v = $self->{session}->get_conf( "login_required_for_${dataset_id}s", "enable" ); #if defined, callback function can be called, if set to 1 will hide abstracts to non-logged in users

  my $fn = $self->{session}->get_conf( "${dataset_id}s_access_restrictions_callback" );
  if( $v && defined $fn )
  {
    # if we are here then access to abstracts/search results etc are restricted by way of a callback fn
    my $sconf = $self->{processor}->{sconf};
    my $mode = $sconf->{mode} || "search";

    my $user = $self->{session}->current_user;
    my @ids;
    $list->map( sub
    {
      my( $session, $dataset, $item ) = @_;
      my $rv = &{$fn}( $item, $user, $mode );
      push @ids, $item->get_id() if $rv != 0;
      # print STDERR "[" . $item->get_id() . "]=[$rv]\n";
    } );
    $list = EPrints::List->new( session => $list->{session}, dataset => $list->{dataset}, ids => \@ids, order => $list->{order} );
  }

  if( $list->count == 0 && !$self->{processor}->{search}->{show_zero_results} )
  {
    $self->{processor}->add_message( "warning", $self->{session}->html_phrase( "lib/searchexpression:noresults") );
    $self->{processor}->{search_subscreen} = "form";
  }

  $self->{processor}->{results} = $list;
}       

sub render_search_form
{
  my( $self ) = @_;

  my $form = $self->{session}->render_form( "post" );
  $form->appendChild( $self->render_hidden_bits );
  $form->appendChild( $self->render_preamble );

  my $value = $self->{processor}->{search}->{searchfieldmap}->{eprintid}->{value};

  my $div = $self->{session}->make_element( "div", style=>"width: 100%; text-align: center;");
  $div->appendChild( $self->{session}->html_phrase( "Plugin/Screen/Staff/EPrintBulkSearch:preamble" ) );
  my $ta = $self->{session}->make_element( "textarea", name=>"eprintid", class=>"ep_form_text", rows=>"20", cols=>"50" );
  $ta->appendChild( $self->{session}->make_text( $value ) );
  $div->appendChild( $ta );
  $form->appendChild( $div );

  $form->appendChild( $self->render_controls );

  return( $form );
}

1;
