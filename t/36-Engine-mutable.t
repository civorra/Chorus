#!perl -T

# Tests for _MUTABLE_SLOTS support:
#   set_mutable($frame, @slots)   — marks slots as mutable on a Frame
#   mutable_slots($frame)         — returns { slot => 1, ... } or {}
#   is_mutable($frame, $slot)     — 1 if mutable, '' otherwise
#
# _MUTABLE_SLOTS is metadata for Chorus::Planner and simulation — the engine
# itself does not act on it.

use strict;
use Test::More tests => 15;
use Chorus::Frame;
use Chorus::Engine;

diag("Testing _MUTABLE_SLOTS (set_mutable/mutable_slots/is_mutable) - Chorus::Engine $Chorus::Engine::VERSION, Perl $], $^X");

my $agent = Chorus::Engine->new();
$agent->set('BOARD', Chorus::Frame->new());

# -----------------------------------------------------------------------
# Test 1 : set_mutable — _MUTABLE_SLOTS set on the Frame
# -----------------------------------------------------------------------
{
    my $f = Chorus::Frame->new(strength_class => 'C18', stud_spacing_mm => 400);
    $agent->set_mutable($f, 'strength_class', 'stud_spacing_mm');
    ok(defined $f->{_MUTABLE_SLOTS},                   'Test 1 - set_mutable: _MUTABLE_SLOTS defined');
    is(ref $f->{_MUTABLE_SLOTS}, 'HASH',               'Test 1b - _MUTABLE_SLOTS is a hashref');
    ok($f->{_MUTABLE_SLOTS}{strength_class},           'Test 1c - strength_class flagged mutable');
    ok($f->{_MUTABLE_SLOTS}{stud_spacing_mm},          'Test 1d - stud_spacing_mm flagged mutable');
    ok(!$f->{_MUTABLE_SLOTS}{type_element},            'Test 1e - type_element not in _MUTABLE_SLOTS');
}

# -----------------------------------------------------------------------
# Test 2 : mutable_slots — returns hashref
# -----------------------------------------------------------------------
{
    my $f = Chorus::Frame->new(strength_class => 'C24');
    $agent->set_mutable($f, 'strength_class');
    my $ms = $agent->mutable_slots($f);
    is(ref $ms, 'HASH',                                'Test 2 - mutable_slots returns hashref');
    ok($ms->{strength_class},                          'Test 2b - strength_class in mutable_slots');
}

# -----------------------------------------------------------------------
# Test 3 : mutable_slots on Frame with no _MUTABLE_SLOTS — returns {}
# -----------------------------------------------------------------------
{
    my $f = Chorus::Frame->new(color => 'blue');
    my $ms = $agent->mutable_slots($f);
    is(ref $ms, 'HASH',                                'Test 3 - no _MUTABLE_SLOTS: returns hashref');
    is(scalar keys %$ms, 0,                            'Test 3b - empty hashref when no mutable slots');
}

# -----------------------------------------------------------------------
# Test 4 : is_mutable — true for declared slot, false otherwise
# -----------------------------------------------------------------------
{
    my $f = Chorus::Frame->new(strength_class => 'C18', type_element => 'stud');
    $agent->set_mutable($f, 'strength_class');
    is($agent->is_mutable($f, 'strength_class'), 1,    'Test 4 - is_mutable: declared slot returns 1');
    is($agent->is_mutable($f, 'type_element'),   '',   'Test 4b - is_mutable: undeclared slot returns ""');
}

# -----------------------------------------------------------------------
# Test 5 : is_mutable on Frame with no _MUTABLE_SLOTS — always false
# -----------------------------------------------------------------------
{
    my $f = Chorus::Frame->new(color => 'blue');
    is($agent->is_mutable($f, 'color'), '',            'Test 5 - is_mutable on plain Frame returns ""');
}

# -----------------------------------------------------------------------
# Test 6 : set_mutable returns the Frame (chainable)
# -----------------------------------------------------------------------
{
    my $f = Chorus::Frame->new(x => 1);
    my $ret = $agent->set_mutable($f, 'x');
    is($ret, $f,                                       'Test 6 - set_mutable returns the Frame');
}

# -----------------------------------------------------------------------
# Test 7 : set_mutable replaces previous declaration
# -----------------------------------------------------------------------
{
    my $f = Chorus::Frame->new(a => 1, b => 2, c => 3);
    $agent->set_mutable($f, 'a', 'b');
    $agent->set_mutable($f, 'c');          # replaces previous
    ok(!$agent->is_mutable($f, 'a'),       'Test 7 - set_mutable replaces: a no longer mutable');
    ok($agent->is_mutable($f, 'c'),        'Test 7b - set_mutable replaces: c now mutable');
}

done_testing();
