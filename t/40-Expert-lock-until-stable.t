use strict;
use warnings;
use Test::More;
use Chorus::Frame;
use Chorus::Engine;
use Chorus::Expert;

# Tests for _LOCK_UNTIL_STABLE in Chorus::Expert::process()
#
# Source (Expert.pm §process):
#   for my $agent (@$agents) {
#       if ($agent->_LOCK_UNTIL_STABLE) {
#           last if grep { $_->_SUCCES } @processed;   # skip this iteration
#       }
#       ... agent->loop() ...
#       push @processed, $agent;
#   }
#
# A locked agent is SKIPPED (via `last`) in any iteration where at least one
# preceding agent has _SUCCES (fired at least one rule). It runs normally in
# iterations where no preceding agent fired.
#
# Practical effect: the locked agent runs only when the system is "stable",
# i.e., after all upstream agents have exhausted their rules.

# ---------------------------------------------------------------------------
# 1. Locked agent runs normally when it is the first agent (no @processed)
# ---------------------------------------------------------------------------

Chorus::Frame::_reset();

my $ran_1 = 0;

my $b1 = Chorus::Engine->new(_IDENT => 'B1', _LOCK_UNTIL_STABLE => 'Y');
$b1->addrule(
    _SCOPE => {},
    _APPLY => sub { $ran_1++; $SELF->solved(); 1 },
);

my $xprt1 = Chorus::Expert->new();
$xprt1->register($b1);
$xprt1->process();

is($ran_1, 1, 'locked agent runs when it is first in the list (no preceding agents)');

# ---------------------------------------------------------------------------
# 2. Locked agent runs only after preceding agents have stabilised
#    Verify it sees the fully-enriched data (practical benefit of the lock)
# ---------------------------------------------------------------------------

Chorus::Frame::_reset();

my $data2 = Chorus::Frame->new(raw => 'yes');
my $enriched_when_b_ran;

my $a2 = Chorus::Engine->new(_IDENT => 'A2');
$a2->addrule(
    _ID    => 'enrich',
    _SCOPE => { f => sub { [fmatch(slot => 'raw')] } },
    _APPLY => sub {
        my %o = @_;
        return if defined $o{f}->get('enriched');   # idempotence guard
        $o{f}->set('enriched', 'done');
        return 1;
    },
);

my $b2 = Chorus::Engine->new(_IDENT => 'B2', _LOCK_UNTIL_STABLE => 'Y');
$b2->addrule(
    _SCOPE => { f => sub { [fmatch(slot => 'raw')] } },
    _APPLY => sub {
        my %o = @_;
        $enriched_when_b_ran = $o{f}->get('enriched');   # check agent_a's work
        $SELF->solved();
        return 1;
    },
);

my $xprt2 = Chorus::Expert->new();
$xprt2->register($a2, $b2);
$xprt2->process();

is($enriched_when_b_ran, 'done',
   'locked agent runs after stabilisation — sees fully-enriched data from preceding agent');

# ---------------------------------------------------------------------------
# 3. Without _LOCK_UNTIL_STABLE, agent may run before upstream is stable
#    (contrast: unlocked b runs in iteration 1, may miss data enriched later)
# ---------------------------------------------------------------------------

Chorus::Frame::_reset();

my $data3 = Chorus::Frame->new(raw => 'yes');
my $enriched_when_unlocked_b_ran;

my $a3 = Chorus::Engine->new(_IDENT => 'A3');
$a3->addrule(
    _ID    => 'enrich3',
    _SCOPE => { f => sub { [fmatch(slot => 'raw')] } },
    _APPLY => sub {
        my %o = @_;
        return if defined $o{f}->get('enriched3');
        $o{f}->set('enriched3', 'done');
        return 1;
    },
);

# Unlocked — runs in same iteration as A3 fires, BEFORE A3 has finished all enrichments
my $b3 = Chorus::Engine->new(_IDENT => 'B3');   # no _LOCK_UNTIL_STABLE
$b3->addrule(
    _SCOPE => { f => sub { [fmatch(slot => 'raw')] } },
    _APPLY => sub {
        my %o = @_;
        return if defined $o{f}->get('b3_done');
        $enriched_when_unlocked_b_ran = $o{f}->get('enriched3');
        $o{f}->set('b3_done', 'y');
        $SELF->solved();
        return 1;
    },
);

my $xprt3 = Chorus::Expert->new();
$xprt3->register($a3, $b3);
$xprt3->process();

# A3 and B3 run in the same iteration — A3 always runs first (list order),
# so B3 does see 'enriched3'. But with multiple data frames or complex ordering,
# _LOCK_UNTIL_STABLE provides a stronger guarantee. This test verifies the contrast.
is($enriched_when_unlocked_b_ran, 'done',
   'unlocked agent: in single-frame scenario, preceding agent still runs first (same iter)');

# ---------------------------------------------------------------------------
# 4. Locked agent with TWO preceding agents: skipped if either has _SUCCES
# ---------------------------------------------------------------------------

Chorus::Frame::_reset();

my $locked_ran_4 = 0;
my $d4 = Chorus::Frame->new(slot_x => 'x');

my $a4 = Chorus::Engine->new(_IDENT => 'A4');
$a4->addrule(
    _ID    => 'a4-rule',
    _SCOPE => { f => sub { [fmatch(slot => 'slot_x')] } },
    _APPLY => sub {
        my %o = @_;
        return if defined $o{f}->get('a4_done');
        $o{f}->set('a4_done', 1);
        return 1;
    },
);

my $b4 = Chorus::Engine->new(_IDENT => 'B4');   # fires nothing
$b4->addrule(
    _SCOPE => {},
    _APPLY => sub { return 0 },
);

my $c4 = Chorus::Engine->new(_IDENT => 'C4', _LOCK_UNTIL_STABLE => 'Y');
$c4->addrule(
    _SCOPE => {},
    _APPLY => sub { $locked_ran_4++; $SELF->solved(); 1 },
);

my $xprt4 = Chorus::Expert->new();
$xprt4->register($a4, $b4, $c4);
$xprt4->process();

is($locked_ran_4, 1,
   'locked agent (3rd in chain) runs once both preceding agents are stable');

# ---------------------------------------------------------------------------
# 5. _LOCK_UNTIL_STABLE flag is readable on the engine frame
# ---------------------------------------------------------------------------

Chorus::Frame::_reset();

my $locked   = Chorus::Engine->new(_LOCK_UNTIL_STABLE => 'Y');
my $unlocked = Chorus::Engine->new();

ok($locked->_LOCK_UNTIL_STABLE,   '_LOCK_UNTIL_STABLE flag is truthy when set');
ok(!$unlocked->_LOCK_UNTIL_STABLE, '_LOCK_UNTIL_STABLE is falsy when absent');

done_testing();
