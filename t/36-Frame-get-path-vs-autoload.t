use strict;
use warnings;
use Test::More;
use Chorus::Frame;

# Tests for the behavioural difference between:
#   $f->get('foo bar baz')   -- path form: ONE get() call, $SELF = $f throughout
#   $f->foo->bar->baz        -- chained AUTOLOAD: THREE get() calls, $SELF shifts at each step
#
# Source mechanism (Frame.pm):
#   get() calls pushself($frame) ONCE at entry and popself() at exit.
#   Internal traversal (_getN) uses _inherited() for intermediate steps and
#   never calls pushself/popself, so $SELF stays the root frame.
#   AUTOLOAD delegates each step to a full get() call, which pushes/pops $SELF.

sub reset_registry { Chorus::Frame::_reset() }

# ---------------------------------------------------------------------------
# 1. Path form: $SELF = root frame ($f) when _NEEDED on 'baz' fires
# ---------------------------------------------------------------------------

reset_registry();

my $self_seen;

my $baz_frame = Chorus::Frame->new(
    _NEEDED => sub { $self_seen = $SELF; 'baz_value' },
);
my $bar_frame = Chorus::Frame->new( baz => $baz_frame );
my $foo_frame = Chorus::Frame->new( bar => $bar_frame );
my $f1        = Chorus::Frame->new( foo => $foo_frame );

my $val = $f1->get('foo bar baz');

is($val, 'baz_value', 'path form: correct value returned via _NEEDED');
is($self_seen, $f1,   'path form: $SELF inside _NEEDED is the root frame ($f)');

# ---------------------------------------------------------------------------
# 2. Chained AUTOLOAD: $SELF = intermediate frame when _NEEDED on 'baz' fires
# ---------------------------------------------------------------------------

reset_registry();

my $self_seen_chain;

my $baz_frame2 = Chorus::Frame->new(
    _NEEDED => sub { $self_seen_chain = $SELF; 'baz_value2' },
);
my $bar_frame2 = Chorus::Frame->new( baz => $baz_frame2 );
my $foo_frame2 = Chorus::Frame->new( bar => $bar_frame2 );
my $f2         = Chorus::Frame->new( foo => $foo_frame2 );

my $val2 = $f2->foo->bar->baz;

is($val2, 'baz_value2', 'chained form: correct value returned via _NEEDED');
isnt($self_seen_chain, $f2,        'chained form: $SELF is NOT the root frame');
is($self_seen_chain,   $bar_frame2, 'chained form: $SELF is the frame from which baz is accessed');

# ---------------------------------------------------------------------------
# 3. Path form: _NEEDED on intermediate step NOT evaluated
#    _inherited() returns the raw sub-Frame object, bypassing _value_N
# ---------------------------------------------------------------------------

reset_registry();

my $foo_needed_fired = 0;

my $foo_sub_frame = Chorus::Frame->new(
    _NEEDED => sub { $foo_needed_fired++; Chorus::Frame->new(result => 'computed') },
);

# 'foo' is stored as a slot holding a sub-Frame that has _NEEDED
# For path traversal, _getN uses _inherited('foo') → returns the sub-Frame object directly,
# without evaluating _NEEDED (which would only fire if foo were the FINAL step).
my $f3 = Chorus::Frame->new( foo => $foo_sub_frame );

# Evaluate 'foo' as final step → _NEEDED fires
$foo_needed_fired = 0;
my $res_final = $f3->get('foo');
is($foo_needed_fired, 1, 'path form: _NEEDED fires when foo is the FINAL step');

# Now evaluate 'foo result' as a two-step path → foo is an intermediate step
$foo_needed_fired = 0;
# _getN('foo result'): intermediate step 'foo' uses _inherited → raw sub-Frame returned,
# _NEEDED does NOT fire; final step 'result' is evaluated on that sub-Frame.
my $res_path = $f3->get('foo result');
is($foo_needed_fired, 0, 'path form: _NEEDED on intermediate step NOT evaluated');
is($res_path, undef,     'path form: path into _NEEDED sub-Frame returns undef (result not set on it)');

# ---------------------------------------------------------------------------
# 4. Chained AUTOLOAD: _NEEDED on intermediate step IS evaluated
# ---------------------------------------------------------------------------

reset_registry();

my $foo_needed_count = 0;
my $computed_frame   = Chorus::Frame->new( result => 'from_computed' );

my $foo_sub2 = Chorus::Frame->new(
    _NEEDED => sub { $foo_needed_count++; $computed_frame },
);

my $f4 = Chorus::Frame->new( foo => $foo_sub2 );

# $f4->foo calls get('foo') → evaluates _NEEDED → returns $computed_frame
# $computed_frame->result calls get('result') → returns 'from_computed'
my $res_chain = $f4->foo->result;

is($foo_needed_count, 1,              'chained form: _NEEDED on intermediate step IS evaluated');
is($res_chain,        'from_computed', 'chained form: result from computed frame is correct');

# ---------------------------------------------------------------------------
# 5. Path form single level: $SELF = the frame itself (baseline)
# ---------------------------------------------------------------------------

reset_registry();

my $self_single;

my $f5 = Chorus::Frame->new(
    label => sub { $self_single = $SELF; 'hello' },
);

$f5->get('label');
is($self_single, $f5, 'single-level get: $SELF is the frame itself');

# ---------------------------------------------------------------------------
# 6. $SELF stack is correctly restored after nested get() calls
# ---------------------------------------------------------------------------

reset_registry();

my $outer_self_before;
my $outer_self_after;
my $inner_self;

my $inner = Chorus::Frame->new(
    x => sub { $inner_self = $SELF; 'inner_x' },
);

my $outer = Chorus::Frame->new(
    a => sub {
        $outer_self_before = $SELF;
        $inner->get('x');             # nested get() — pushes/pops $SELF internally
        $outer_self_after = $SELF;    # must be restored to $outer
        'outer_a'
    },
);

$outer->get('a');

is($outer_self_before, $outer, '$SELF stack: before nested get(), $SELF = outer frame');
is($inner_self,        $inner, '$SELF stack: inside nested get(), $SELF = inner frame');
is($outer_self_after,  $outer, '$SELF stack: after nested get() returns, $SELF restored to outer');

done_testing();
