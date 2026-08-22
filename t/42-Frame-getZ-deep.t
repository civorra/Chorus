use strict;
use warnings;
use Test::More;
use Chorus::Frame;

# Mode Z vs Mode N — deep inheritance.
#
# IMPLEMENTATION DETAIL (from _getZ source):
#
# Single-step get('slot'):
#   Mode N: _inherited(frame, 'slot') → finds NEAREST ancestor's slot value;
#           then _value_N traverses THAT slot frame's _ISA chain (_VALUE first, then _DEFAULT, then _NEEDED)
#
#   Mode Z: _all_slot_frames(frame, 'slot') → collects ALL frames in the container's _ISA chain
#           that have 'slot'; then scans VALUATION_ORDER across ALL of them:
#           (_VALUE on all, then _DEFAULT on all, then _NEEDED on all).
#           Returns the first valuation key found, regardless of which ancestor provides it.
#
# The difference is observable when:
#   - The container's _ISA chain has multiple levels that each provide the slot
#   - Different valuation keys live at different levels
#
# Multi-step get('a b'):
#   Both modes: intermediate step 'a' uses _inherited (same).
#   Last step 'b': Mode N uses _value_N (traverses slot frame's _ISA);
#                  Mode Z uses _all_slot_frames on the intermediate frame.
#   → Multi-step difference mirrors the single-step difference.

sub reset_registry { Chorus::Frame::_reset() }
sub restore_n      { Chorus::Frame::setMode('N') }

# ---------------------------------------------------------------------------
# 1. Single-step, 3-level container hierarchy
#    p has val._DEFAULT, gp has val._VALUE
#    Mode N: stops at nearest (p), finds _DEFAULT → 'p_default'
#    Mode Z: collects [p->{val}, gp->{val}], scans _VALUE first → 'gp_value'
# ---------------------------------------------------------------------------

reset_registry();

my $gp1 = Chorus::Frame->new( val => { _VALUE   => 'gp_value'  } );
my $p1  = Chorus::Frame->new( _ISA => $gp1,
                               val  => { _DEFAULT => 'p_default' } );
my $c1  = Chorus::Frame->new( _ISA => $p1 );    # no local 'val'

Chorus::Frame::setMode('N');
is($c1->get('val'), 'p_default',
   'Mode N / 3-level: nearest ancestor (p) wins — returns _DEFAULT from p');

Chorus::Frame::setMode('Z');
is($c1->get('val'), 'gp_value',
   'Mode Z / 3-level: _VALUE at any level beats _DEFAULT at nearest — returns gp._VALUE');
restore_n();

# ---------------------------------------------------------------------------
# 2. Single-step, 4-level: _VALUE deep, _DEFAULT and _NEEDED at intermediate
#    Mode N: nearest ancestor (p) has _DEFAULT → 'p_default'
#    Mode Z: _VALUE anywhere beats _DEFAULT → finds ggp._VALUE
# ---------------------------------------------------------------------------

reset_registry();

my $ggp2 = Chorus::Frame->new( val => { _VALUE   => 'ggp_value'  } );
my $gp2  = Chorus::Frame->new( _ISA => $ggp2,
                                val  => { _NEEDED  => sub { 'gp_needed' } } );
my $p2   = Chorus::Frame->new( _ISA => $gp2,
                                val  => { _DEFAULT => 'p_default' } );
my $c2   = Chorus::Frame->new( _ISA => $p2 );

Chorus::Frame::setMode('N');
is($c2->get('val'), 'p_default',
   'Mode N / 4-level: nearest ancestor with any value wins (p._DEFAULT)');

Chorus::Frame::setMode('Z');
is($c2->get('val'), 'ggp_value',
   'Mode Z / 4-level: _VALUE anywhere in hierarchy wins (ggp._VALUE)');
restore_n();

# ---------------------------------------------------------------------------
# 3. Single-step: when ONLY _DEFAULT exists across the hierarchy
#    Both modes return the same value
# ---------------------------------------------------------------------------

reset_registry();

my $gp3 = Chorus::Frame->new( val => { _DEFAULT => 'gp_default' } );
my $p3  = Chorus::Frame->new( _ISA => $gp3 );
my $c3  = Chorus::Frame->new( _ISA => $p3 );

Chorus::Frame::setMode('N');
my $n3 = $c3->get('val');

Chorus::Frame::setMode('Z');
my $z3 = $c3->get('val');
restore_n();

is($n3, 'gp_default', 'Mode N: _DEFAULT-only hierarchy → gp._DEFAULT');
is($z3, 'gp_default', 'Mode Z: _DEFAULT-only hierarchy → same gp._DEFAULT (no _VALUE to prefer)');

# ---------------------------------------------------------------------------
# 4. Multi-step path (get('a b')): last-step N vs Z difference
#    This mirrors the existing test in 14-Frame-getZ-getN.t, extended to 3 levels.
#    Structure: f->{a} is a frame whose _ISA chain provides different 'b' valuations.
# ---------------------------------------------------------------------------

reset_registry();

my $b_proto = Chorus::Frame->new( _VALUE => 'b_from_proto' );

# a_frame's 'b' slot has _ISA => $b_proto and _DEFAULT
my $a_frame = Chorus::Frame->new(
    b => {
        _ISA     => $b_proto,
        _DEFAULT => 'b_default',
    }
);
my $f4 = Chorus::Frame->new( a => $a_frame );

# Mode N for get('a b'):
#   _getN($f4->{a}, 'b') → _value_N($a_frame->{b}) where $a_frame->{b}._ISA = $b_proto
#   Scans _VALUE on ($a_frame->{b}, $b_proto) → $b_proto has _VALUE → 'b_from_proto'
Chorus::Frame::setMode('N');
is($f4->get('a b'), 'b_from_proto',
   'Mode N / multi-step: _VALUE in slot._ISA chain wins over _DEFAULT');

# Mode Z for get('a b'):
#   Last step: _all_slot_frames($a_frame, 'b') = [$a_frame->{b}]
#              _VALUE on $a_frame->{b}: no; _DEFAULT: yes → 'b_default'
Chorus::Frame::setMode('Z');
is($f4->get('a b'), 'b_default',
   'Mode Z / multi-step: _DEFAULT on nearest slot frame wins (slot._ISA not traversed by Mode Z)');
restore_n();

# ---------------------------------------------------------------------------
# 5. setMode() is global — confirmed across multiple frames
# ---------------------------------------------------------------------------

reset_registry();

my $gp5 = Chorus::Frame->new( val => { _VALUE   => 'global_value'   } );
my $p5  = Chorus::Frame->new( _ISA => $gp5,
                               val  => { _DEFAULT => 'local_default' } );
my $c5a = Chorus::Frame->new( _ISA => $p5 );
my $c5b = Chorus::Frame->new( _ISA => $p5 );

Chorus::Frame::setMode('N');
is($c5a->get('val'), 'local_default', 'setMode(N) global: c5a returns nearest _DEFAULT');
is($c5b->get('val'), 'local_default', 'setMode(N) global: c5b returns nearest _DEFAULT');

Chorus::Frame::setMode('Z');
is($c5a->get('val'), 'global_value', 'setMode(Z) global: c5a returns deeper _VALUE');
is($c5b->get('val'), 'global_value', 'setMode(Z) global: c5b returns deeper _VALUE');

restore_n();
is($c5a->get('val'), 'local_default', 'After restore to Mode N: back to nearest _DEFAULT');

done_testing();
