use strict;
use warnings;
use Test::More;
use Chorus::Frame;

# _NEEDED is NOT automatically cached: every get() re-evaluates the coderef
# unless the slot has been explicitly written via set() inside the coderef.
#
# This is documented in chorus-frame-advanced.md § _NEEDED — Lazy computation:
#   "Called once, result is NOT cached."
#   "Use explicit set() if computation is expensive."

sub reset_registry { Chorus::Frame::_reset() }

# ---------------------------------------------------------------------------
# 1. _NEEDED is re-evaluated on every get() without explicit caching
# ---------------------------------------------------------------------------

reset_registry();

my $call_count = 0;

my $f = Chorus::Frame->new(
    score => {
        _NEEDED => sub { $call_count++; 42 },
    },
);

$f->get('score');
$f->get('score');
$f->get('score');

is($call_count, 3, '_NEEDED re-evaluated on every get() — not cached automatically');

# ---------------------------------------------------------------------------
# 2. After explicit set() inside _NEEDED, _VALUE takes over — _NEEDED not called again
# ---------------------------------------------------------------------------

reset_registry();

my $call_count2 = 0;

my $g = Chorus::Frame->new(
    score => {
        _NEEDED => sub {
            $call_count2++;
            $SELF->set('score', 99);   # explicit cache via set() — writes _VALUE
            99;
        },
    },
);

my $v1 = $g->get('score');   # _NEEDED fires, sets _VALUE = 99
my $v2 = $g->get('score');   # _VALUE present → _NEEDED skipped
my $v3 = $g->get('score');   # _VALUE present → _NEEDED skipped

is($call_count2, 1, '_NEEDED called only once when self-caching via set()');
is($v1, 99, 'first get() returns computed value');
is($v2, 99, 'second get() returns cached _VALUE');
is($v3, 99, 'third get() returns cached _VALUE');

# ---------------------------------------------------------------------------
# 3. _NEEDED re-evaluation uses current Frame state each time
# ---------------------------------------------------------------------------

reset_registry();

my $h = Chorus::Frame->new(
    base  => 1,
    score => {
        _NEEDED => sub { $SELF->get('base') * 10 },
    },
);

my $r1 = $h->get('score');   # base = 1 → 10
$h->set('base', 3);
my $r2 = $h->get('score');   # base = 3 → 30 (re-evaluated, uses new base)

is($r1, 10, '_NEEDED uses frame state at call time (first call)');
is($r2, 30, '_NEEDED re-evaluates with updated frame state (second call)');

# ---------------------------------------------------------------------------
# 4. A DERIVED slot written via set() inside _NEEDED becomes visible to fmatch()
#    A slot only returned (not set) from _NEEDED is NOT a new fmatch-visible slot
# ---------------------------------------------------------------------------

reset_registry();

my $i = Chorus::Frame->new( base => 3 );

# Add a procedural slot that computes a derived slot and registers it via set()
$i->set('score', {
    _NEEDED => sub {
        my $v = $SELF->get('base') * 10;
        $SELF->set('score_cached', $v);   # write derived slot → registers in %REPOSITORY
        $v;
    },
});

my @before = fmatch(slot => 'score_cached');
is(scalar @before, 0, 'before _NEEDED fires: derived slot not yet registered for fmatch');

$i->get('score');   # triggers _NEEDED → $SELF->set('score_cached', 30) fires

my @after = fmatch(slot => 'score_cached');
is(scalar @after, 1, 'after _NEEDED with set(): derived slot registered and visible to fmatch');
is($after[0]->get('score_cached'), 30, 'derived slot holds the computed value');

done_testing();
