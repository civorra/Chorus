use strict;
use warnings;
use Test::More;
use Chorus::Frame;

# Tests for argument forwarding through get() / AUTOLOAD.
#
# From the POD:
#   "Arguments are forwarded when the resolved value is a coderef:
#    $f->slotname(@args);   # calls get('slotname'), then invokes the result with @args"
#
# Implementation: expand() in Frame.pm calls &$info(@args) when info is a CODE ref.

sub reset_registry { Chorus::Frame::_reset() }

# ---------------------------------------------------------------------------
# 1. AUTOLOAD forwards arguments to a plain coderef slot
# ---------------------------------------------------------------------------

reset_registry();

my $f = Chorus::Frame->new(
    greet => sub { my ($name) = @_; "Hello, $name!" },
);

is($f->greet('World'), 'Hello, World!', 'AUTOLOAD forwards args to coderef slot');

# ---------------------------------------------------------------------------
# 2. get('slot', @args) forwards arguments
# ---------------------------------------------------------------------------

reset_registry();

my $g = Chorus::Frame->new(
    add => sub { my ($x, $y) = @_; $x + $y },
);

is($g->get('add', 3, 4), 7, 'get("slot", @args) forwards arguments to coderef');

# ---------------------------------------------------------------------------
# 3. _NEEDED receives forwarded arguments
# ---------------------------------------------------------------------------

reset_registry();

my $h = Chorus::Frame->new(
    compute => {
        _NEEDED => sub { my ($factor) = @_; ($SELF->{base} // 1) * ($factor // 1) },
    },
    base => 5,
);

is($h->get('compute', 3), 15, '_NEEDED receives forwarded arguments via get()');

# ---------------------------------------------------------------------------
# 4. No args: coderef called with empty list
# ---------------------------------------------------------------------------

reset_registry();

my @received_args;
my $i = Chorus::Frame->new(
    noop => sub { @received_args = @_; 'done' },
);

$i->get('noop');
is(scalar @received_args, 0, 'no args: coderef called with empty list');

# ---------------------------------------------------------------------------
# 5. Path form forwards args to the terminal coderef
# ---------------------------------------------------------------------------

reset_registry();

my $inner = Chorus::Frame->new(
    fn => sub { my ($x) = @_; $x * 2 },
);
my $outer = Chorus::Frame->new( sub_frame => $inner );

is($outer->get('sub_frame fn', 6), 12, 'path form: args forwarded to terminal coderef');

# ---------------------------------------------------------------------------
# 6. _DEFAULT coderef also receives forwarded arguments
# ---------------------------------------------------------------------------

reset_registry();

my $j = Chorus::Frame->new(
    val => {
        _DEFAULT => sub { my ($prefix) = @_; "${prefix}_default" },
    },
);

is($j->get('val', 'test'), 'test_default', '_DEFAULT coderef receives forwarded args');

done_testing();
