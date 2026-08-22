#!perl -T

use Test::More;
use Chorus::Frame;

diag( "Testing Chorus::Frame::set $Chorus::Frame::VERSION, Perl $], $^X" );

my ($before, $after);

sub test_BEFORE_AFTER {
	
   my $f1 = Chorus::Frame->new (
    val => {
 	 _BEFORE => sub { 
 	 	    $SELF->set('BEFORE', "BEFORE FROM F1") 
 	  },
 	  
 	 _AFTER => sub { 
 	 	$SELF->set('AFTER', "AFTER FROM F1") 
 	  }
    }
  );

  my $f2 = Chorus::Frame->new (
    val => { 
     _ISA => $f1->{val},
 	 _AFTER => sub {
 	 	$SELF->set('AFTER', "AFTER FROM F2") 
 	 }
    }
  );

  my $f3 = Chorus::Frame->new (
    val => {
      _ISA  => $f2->{val},
      _VALUE => 'current VALUE'	
    }
  );
  
  $f3->set('val', 'something');
  
  $before = $f3->BEFORE; 
  $after  = $f3->AFTER; 
}

# --

test_BEFORE_AFTER();

is($before, 'BEFORE FROM F1', 'TESTING BEFORE');
is($after, 'AFTER FROM F2', 'TESTING AFTER');

# ---------------------------------------------------------------------------
# $SELF in _AFTER is the frame on which set() was called
# ---------------------------------------------------------------------------

Chorus::Frame::_reset();

my $self_in_after;
my $root = Chorus::Frame->new(
    val => {
        _VALUE => 'initial',
        _AFTER => sub { $self_in_after = $SELF },
    },
);
$root->set('val', 'changed');
is($self_in_after, $root, '$SELF in _AFTER is the frame on which set() was called');

# ---------------------------------------------------------------------------
# $SELF in _AFTER is overwritten by a nested set() on another frame — pitfall
# ---------------------------------------------------------------------------

Chorus::Frame::_reset();

my ($self_before_nested, $self_after_nested);
my $other = Chorus::Frame->new( x => { _VALUE => 0 } );
my $main  = Chorus::Frame->new(
    val => {
        _VALUE => 'init',
        _AFTER => sub {
            $self_before_nested = $SELF;    # $SELF = $main here
            $other->set('x', 1);            # nested set() → $SELF temporarily shifts to $other
            $self_after_nested = $SELF;     # ⚠️ $SELF restored to $main after set() returns
        },
    },
);
$main->set('val', 'new');
is($self_before_nested, $main, '$SELF = root frame at start of _AFTER');
is($self_after_nested,  $main, '$SELF restored after nested set() returns (pushself/popself)');

# ---------------------------------------------------------------------------
# Capture pattern: my $ctx = $SELF prevents loss of context across nested set()
# ---------------------------------------------------------------------------

Chorus::Frame::_reset();

my $ctx_preserved;
my $other2 = Chorus::Frame->new( y => { _VALUE => 0 } );
my $main2  = Chorus::Frame->new(
    val => {
        _VALUE => 'init',
        _AFTER => sub {
            my $ctx = $SELF;            # capture immediately
            $other2->set('y', 99);      # nested set() — $SELF shifts internally but ctx is safe
            $ctx_preserved = $ctx;      # ctx still holds $main2
        },
    },
);
$main2->set('val', 'trigger');
is($ctx_preserved, $main2, 'captured $ctx = $SELF is preserved across nested set()');

done_testing();


