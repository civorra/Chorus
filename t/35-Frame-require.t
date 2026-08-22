use strict;
use warnings;
use Test::More;
use Chorus::Frame;

sub reset_registry { Chorus::Frame::_reset() }

# ---------------------------------------------------------------------------
# 1. _REQUIRE returning REQUIRE_FAILED blocks the write
# ---------------------------------------------------------------------------

reset_registry();

my $f = Chorus::Frame->new(
    score => {
        _VALUE   => 10,
        _REQUIRE => sub { my ($v) = @_; return REQUIRE_FAILED if $v < 0; 1 },
    },
);

$f->set('score', -5);
is($f->get('score'), 10, '_REQUIRE: negative value blocked, original value preserved');

# ---------------------------------------------------------------------------
# 2. _REQUIRE returning 1 allows the write
# ---------------------------------------------------------------------------

reset_registry();

my $g = Chorus::Frame->new(
    score => {
        _VALUE   => 10,
        _REQUIRE => sub { my ($v) = @_; return REQUIRE_FAILED if $v < 0; 1 },
    },
);

$g->set('score', 42);
is($g->get('score'), 42, '_REQUIRE: valid value allowed, slot updated');

# ---------------------------------------------------------------------------
# 3. _BEFORE is NOT called when _REQUIRE blocks
# ---------------------------------------------------------------------------

reset_registry();

my $before_fired = 0;
my $h = Chorus::Frame->new(
    val => {
        _VALUE   => 'initial',
        _REQUIRE => sub { REQUIRE_FAILED },   # always blocks
        _BEFORE  => sub { $before_fired = 1 },
    },
);

$h->set('val', 'new');
is($before_fired, 0, '_BEFORE is not called when _REQUIRE blocks the write');

# ---------------------------------------------------------------------------
# 4. _AFTER is NOT called when _REQUIRE blocks
# ---------------------------------------------------------------------------

reset_registry();

my $after_fired = 0;
my $i = Chorus::Frame->new(
    val => {
        _VALUE   => 'initial',
        _REQUIRE => sub { REQUIRE_FAILED },   # always blocks
        _AFTER   => sub { $after_fired = 1 },
    },
);

$i->set('val', 'new');
is($after_fired, 0, '_AFTER is not called when _REQUIRE blocks the write');

# ---------------------------------------------------------------------------
# 5. $SELF inside _REQUIRE is the frame on which set() was called
# ---------------------------------------------------------------------------

reset_registry();

my $self_in_require;
my $j = Chorus::Frame->new(
    val => {
        _VALUE   => 'ok',
        _REQUIRE => sub { $self_in_require = $SELF; 1 },
    },
);

$j->set('val', 'new');
is($self_in_require, $j, '$SELF inside _REQUIRE is the frame on which set() was called');

# ---------------------------------------------------------------------------
# 6. _REQUIRE inherited through the SLOT frame's own _ISA
# ---------------------------------------------------------------------------
# _REQUIRE is looked up via _getN on the slot sub-Frame.
# If the slot Frame itself declares an _ISA that carries _REQUIRE, it fires.
# Note: _REQUIRE from the *containing* Frame's _ISA is NOT automatically applied
# when the child Frame does not already have a local slot Frame.

reset_registry();

my $slot_proto = Chorus::Frame->new(
    _REQUIRE => sub { my ($v) = @_; return REQUIRE_FAILED if $v eq 'forbidden'; 1 },
);

my $f_req = Chorus::Frame->new(
    val => {
        _VALUE => 'default',
        _ISA   => $slot_proto,   # slot frame inherits _REQUIRE from slot_proto
    },
);

$f_req->set('val', 'forbidden');
is($f_req->get('val'), 'default', '_REQUIRE inherited through slot _ISA blocks the write');

$f_req->set('val', 'allowed');
is($f_req->get('val'), 'allowed', '_REQUIRE inherited through slot _ISA allows valid value');

# ---------------------------------------------------------------------------
# 7. _REQUIRE receives the new value as argument
# ---------------------------------------------------------------------------

reset_registry();

my $received;
my $k = Chorus::Frame->new(
    val => {
        _VALUE   => 'old',
        _REQUIRE => sub { $received = $_[0]; 1 },
    },
);

$k->set('val', 'new_value');
is($received, 'new_value', '_REQUIRE receives the new value as argument');

# ---------------------------------------------------------------------------
# 8. REQUIRE_FAILED constant equals -1
# ---------------------------------------------------------------------------

is(REQUIRE_FAILED, -1, 'REQUIRE_FAILED constant equals -1');

done_testing();
