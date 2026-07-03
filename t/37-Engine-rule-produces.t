#!perl -T

# Tests for %_RULE_PRODUCES index:
#   addrule() with _PRODUCES populates $agent->{_RULE_PRODUCES}
#   loadRules() with PRODUCES: key populates the index via addrule()
#   rule_produces($slot) queries the per-agent index
#   Expert::register() merges agents' indices
#   $expert->rule_produces($slot) queries the merged index

use strict;
use Test::More tests => 17;
use Chorus::Frame;
use Chorus::Engine;
use Chorus::Expert;
use File::Temp qw(tempdir);
use YAML qw(DumpFile);

diag("Testing %_RULE_PRODUCES index — Chorus::Engine $Chorus::Engine::VERSION, Perl $], $^X");

sub make_engine {
    my $e = Chorus::Engine->new();
    $e->set('BOARD', Chorus::Frame->new());
    return $e;
}

sub rule_dir {
    my %rules = @_;
    my $dir = tempdir(CLEANUP => 1);
    DumpFile("$dir/$_.yml", $rules{$_}) for keys %rules;
    return $dir;
}

# -----------------------------------------------------------------------
# Test 1 : addrule() with _PRODUCES populates _RULE_PRODUCES
# -----------------------------------------------------------------------
{
    my $e = make_engine();
    $e->addrule(
        _ID       => 'domain-check',
        _PRODUCES => ['frame_ok', 'domain_note'],
        _SCOPE    => { f => [] },
        _APPLY    => sub { 1 },
    );
    my $rules = $e->rule_produces('frame_ok');
    is(ref $rules, 'ARRAY',              'Test 1 - rule_produces returns arrayref');
    is(scalar @$rules, 1,                'Test 1b - one rule produces frame_ok');
    is($rules->[0]{_ID}, 'domain-check', 'Test 1c - correct rule _ID');
    my $rules2 = $e->rule_produces('domain_note');
    is(scalar @$rules2, 1,               'Test 1d - domain_note also indexed');
}

# -----------------------------------------------------------------------
# Test 2 : rule_produces on unknown slot returns []
# -----------------------------------------------------------------------
{
    my $e = make_engine();
    my $rules = $e->rule_produces('no_such_slot');
    is(ref $rules, 'ARRAY',   'Test 2 - unknown slot: returns arrayref');
    is(scalar @$rules, 0,     'Test 2b - unknown slot: empty arrayref');
}

# -----------------------------------------------------------------------
# Test 3 : multiple rules producing the same slot
# -----------------------------------------------------------------------
{
    my $e = make_engine();
    $e->addrule(_ID => 'r1', _PRODUCES => ['shared_slot'], _SCOPE => { f => [] }, _APPLY => sub { 1 });
    $e->addrule(_ID => 'r2', _PRODUCES => ['shared_slot'], _SCOPE => { f => [] }, _APPLY => sub { 1 });
    my $rules = $e->rule_produces('shared_slot');
    is(scalar @$rules, 2, 'Test 3 - two rules indexed for shared_slot');
    my @ids = sort map { $_->{_ID} } @$rules;
    is($ids[0], 'r1', 'Test 3b - first rule is r1');
    is($ids[1], 'r2', 'Test 3c - second rule is r2');
}

# -----------------------------------------------------------------------
# Test 4 : loadRules() with PRODUCES: key
# -----------------------------------------------------------------------
{
    my $e   = make_engine();
    my $dir = rule_dir(rule01 => {
        RULE     => 'fire-check',
        PRODUCES => ['fire_ok', 'fire_note'],
        FIND     => { f => { attribut => 'needs_fire' } },
        ACTION   => q{$f->set('fire_ok','OK'); 1},
    });
    $e->loadRules($dir);
    my $rules = $e->rule_produces('fire_ok');
    is(scalar @$rules, 1,            'Test 4 - loadRules PRODUCES: indexed');
    is($rules->[0]{_ID}, 'fire-check', 'Test 4b - correct rule from YAML');
    my $rules2 = $e->rule_produces('fire_note');
    is(scalar @$rules2, 1,           'Test 4c - fire_note also indexed from YAML');
}

# -----------------------------------------------------------------------
# Test 5 : Expert::register() merges _RULE_PRODUCES from all agents
# -----------------------------------------------------------------------
{
    my $e1 = Chorus::Engine->new();
    my $e2 = Chorus::Engine->new();
    $e1->addrule(_ID => 'a1-rule', _PRODUCES => ['slot_a', 'slot_shared'],
                 _SCOPE => { f => [] }, _APPLY => sub { 1 });
    $e2->addrule(_ID => 'a2-rule', _PRODUCES => ['slot_b', 'slot_shared'],
                 _SCOPE => { f => [] }, _APPLY => sub { 1 });
    my $xprt = Chorus::Expert->new();
    $xprt->register($e1, $e2);

    # Per-agent index still intact
    is(scalar @{ $e1->rule_produces('slot_a') }, 1,      'Test 5 - e1 per-agent index: slot_a');
    is(scalar @{ $e2->rule_produces('slot_b') }, 1,      'Test 5b - e2 per-agent index: slot_b');

    # Expert merged index
    my $ra = $xprt->rule_produces('slot_a');
    is(scalar @$ra, 1,                                   'Test 5c - expert: slot_a from e1');
    my $rb = $xprt->rule_produces('slot_b');
    is(scalar @$rb, 1,                                   'Test 5d - expert: slot_b from e2');
    my $rs = $xprt->rule_produces('slot_shared');
    is(scalar @$rs, 2,                                   'Test 5e - expert: slot_shared from both agents');
}

done_testing();
