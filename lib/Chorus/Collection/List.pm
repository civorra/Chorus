package Chorus::Collection::List;

BEGIN {
  use Exporter;
  use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

  @ISA         = qw(Exporter);
  @EXPORT      = qw();
  @EXPORT_OK   = qw($LIST);

  # %EXPORT_TAGS = ( );		# eg: TAG => [ qw!name1 name2! ];
}

use Chorus::Frame;
use strict;

use constant DEFAULT_CONTAINER_NAME => '_CONTAINER';

our $LIST = Chorus::Frame->new(

    container_name => sub {
      $SELF->_CONTAINER_NAME || DEFAULT_CONTAINER_NAME
    },

    set_container_name => sub {
      $SELF->set('_CONTAINER_NAME', shift);
    },

    #    build :
    #      - Fills List _ITEMS with array @_
    #      - set container to $SELF for each elements of array @_,
    #
    build => sub {
      my $ref = $SELF;
      my $contname = $SELF->container_name;
      $_->set($contname, $ref) for (@_);
      $SELF->set('_ITEMS', [@_]);
      return $SELF;
    },


    #  merge_left :
    #    injecte a gauche des elements de $SELF les elements
    #    des listes (references a des Chorus::Collection::List) passees en argument
    #    les listes initiales sont videes (elements deplaces)
    #
    merge_left => sub {

      my $ref = $SELF;
      my $lst = $SELF->_ITEMS;
      my $contname = $SELF->container_name;

      foreach my $l (@_ ) { # @_ = array of List references !!
        $_->set($contname, $ref) for (@{$l->_ITEMS}); # change container before merging
      }

      unshift @{$lst}, map { @{$_->_ITEMS}; } @_;
      $_->set('_ITEMS', []) for (@_); # reset/clear items from initial Lists
      return $SELF;
    },

    #  merge_right :
    #    injecte a droite des elements de $SELF les elements
    #    des listes (references a des Chorus::Collection::List) passées en argument
    #    les listes initiales sont videes (elements deplaces)
    #
    merge_right => sub {

      my $ref = $SELF;
      my $lst = $SELF->_ITEMS;
        my $contname = $SELF->container_name;

      foreach my $l (@_ ) { # @_ can be multiple
        $_->set($contname, $ref) for (@{$l->_ITEMS});
      }

      push @{$lst}, map { @{$_->_ITEMS}; } @_;
      $_->set('_ITEMS', []) for (@_);
      return $SELF;
    },

    #  connect_left : Double chainage (prev & succ) a gauche de $SELF
    #
    connect_left  => sub {
      my $to   = shift;
      return unless $to;
      my $self = $SELF;        # capture before $to->set() overwrites $SELF
      $self->set('prev', $to);
      $to->set('succ', $self);
    },

    #  connect_right : Double chainage (prev & succ) a droite de $SELF
    #
    connect_right  => sub {
      my $to   = shift;
      my $self = $SELF;        # capture before $to->set() overwrites $SELF
      $self->set('succ', $to);
      $to->set('prev', $self);
    },

    #  unshift_items : ajout d'éléments à gauche de $SELF
    #
    unshift_items => sub {# set_lemma :
  #
  # * Controle qu'il n'existe plus d'ambiguité sur le lemme (même si la catégorie est résolue )
  # * si OK, pose le flag '_CHECK_LEMMA' (cf agent Lemma.pm)
  # * attribue le slot _LEMMA qui renseigne :
  #     - _VALUE : la valeur de 'lemma' dans la forme retenue
  #     - _ITEM  : la structure complète de la forme retenue
  #
      my $ref = $SELF;
      my $contname = $SELF->container_name;
      $_->set($contname, $ref) for @_;
      my $l = $SELF->_ITEMS;
      unshift @{$l}, @_;
      $SELF->set('_ITEMS', $l);
      return $SELF;
    },

    #  push_items : ajout d'éléments à droite de $SELF
    #
    push_items => sub {
      my $ref = $SELF;
      my $contname = $SELF->container_name;
      $_->set($contname, $ref) for @_;
      my $l = $SELF->_ITEMS;
      push @{$l}, @_;
      $SELF->set('_ITEMS', $l);
      return $SELF;
    },

    # -- Searching items

    first_item => sub {
      return $SELF->_ITEMS->[0];
    },

    last_item  => sub {
      return unless $SELF->_ITEMS->[0];
      $SELF->_ITEMS->[scalar(@{$SELF->_ITEMS}) - 1];
    },

    length => sub { scalar @{$SELF->_ITEMS} },

    # TODO : useful methods
    #
    # find => sub { my ($call) = @_; grep &{$call}, @{$SELF->_ITEMS}; },
    # grep => sub { my ($call) = @_; grep &{$call}, @{$SELF->_ITEMS}; },
    # map  => sub { my ($call) = @_; map  $call @{$SELF->_ITEMS}; },

    # HAS         => sub { my ($slot) = @_; return   grep { $_->is($slot) } @{$SELF->_ITEMS}; },                   # ALLOW _LEMMA UNSOLVED
    # HAS_NO      => sub { my ($slot) = @_; return ! grep { $_->is($slot) } @{$SELF->_ITEMS}; },                   # ALLOW _LEMMA UNSOLVED
    #
    HAS  => sub {
      my ($slot) = @_;
      for (@{$SELF->_ITEMS}) {
         return $_ if $_->$slot;
      }
      return;
    },
    HAS_NO => sub { ! $SELF->HAS(@_) },

    # STARTS_WITH => sub { my ($slot) = @_; my $w = $SELF->_ITEMS; return $w->[0]->is($slot); },                   # ALLOW _LEMMA UNSOLVED
    # ENDS_WITH   => sub { my ($slot) = @_; my $w = $SELF->_ITEMS; return $w->[scalar(@{$w}) - 1]->is($slot); },   # ALLOW _LEMMA UNSOLVED
    #
    STARTS_WITH => sub { my ($slot) = @_; my $w = $SELF->_ITEMS; return $w->[0]->$slot; },
    ENDS_WITH   => sub { my ($slot) = @_; my $w = $SELF->_ITEMS; return $w->[scalar(@{$w}) - 1]->$slot; },

    _ITEMS => {
      _NEEDED => sub { $SELF->set('_ITEMS',[])}
    },

);

END {}

1;
