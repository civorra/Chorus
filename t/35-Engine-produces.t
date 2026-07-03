#!perl -T

# Tests for PRODUCES: / PRODUIT: YAML DSL key.
#
# PRODUCES: declares the list of slots written by a rule.
# It compiles to _PRODUCES => [...] on the rule Frame.
# The engine does not act on _PRODUCES itself — it is metadata
# for backward-chaining consumers (%RULE_PRODUCES index, Chorus::Planner).

use strict;
use Test::More tests => 10;
use Chorus::Frame;
use Chorus::Engine;
use File::Temp qw(tempdir);
use YAML qw(DumpFile);

diag("Testing PRODUCES:/PRODUIT: DSL key - Chorus::Engine $Chorus::Engine::VERSION, Perl $], $^X");

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
# Test 1 : PRODUCES (English) — single slot
# -----------------------------------------------------------------------
{
    my $e   = make_engine();
    my $dir = rule_dir(rule01 => {
        RULE     => 'tag-blue',
        PRODUCES => ['tagged'],
        FIND     => { x => { attribut => 'color' } },
        ACTION   => q{$x->set('tagged','y'); 1},
    });
    $e->loadRules($dir);
    my $rule = $e->{_RULES}[0];
    ok(defined $rule->{_PRODUCES},            'Test 1 - PRODUCES: _PRODUCES defined on rule Frame');
    is(ref $rule->{_PRODUCES}, 'ARRAY',       'Test 1b - _PRODUCES is an arrayref');
    is($rule->{_PRODUCES}[0], 'tagged',       'Test 1c - _PRODUCES[0] = tagged');
}

# -----------------------------------------------------------------------
# Test 2 : PRODUCES — multiple slots
# -----------------------------------------------------------------------
{
    my $e   = make_engine();
    my $dir = rule_dir(rule01 => {
        RULE     => 'domain-check',
        PRODUCES => ['frame_ok', 'domain_note'],
        FIND     => { f => { attribut => 'needs_domain' } },
        ACTION   => q{$f->set('frame_ok','OK'); 1},
    });
    $e->loadRules($dir);
    my $rule = $e->{_RULES}[0];
    is(scalar @{$rule->{_PRODUCES}}, 2,       'Test 2 - PRODUCES: two slots declared');
    is($rule->{_PRODUCES}[0], 'frame_ok',     'Test 2b - first slot = frame_ok');
    is($rule->{_PRODUCES}[1], 'domain_note',  'Test 2c - second slot = domain_note');
}

# -----------------------------------------------------------------------
# Test 3 : PRODUIT (French alias)
# -----------------------------------------------------------------------
{
    my $e   = make_engine();
    my $dir = rule_dir(rule01 => {
        REGLE   => 'verif-section',
        PRODUIT => ['ossature_ok', 'anomalie_ossature'],
        CHERCHER => { p => { attribut => 'besoin_ossature' } },
        EFFET   => q{$p->set('ossature_ok','OK'); 1},
    });
    $e->loadRules($dir);
    my $rule = $e->{_RULES}[0];
    ok(defined $rule->{_PRODUCES},               'Test 3 - PRODUIT alias: _PRODUCES defined');
    is($rule->{_PRODUCES}[0], 'ossature_ok',     'Test 3b - PRODUIT: first slot = ossature_ok');
    is($rule->{_PRODUCES}[1], 'anomalie_ossature', 'Test 3c - PRODUIT: second slot = anomalie_ossature');
}

# -----------------------------------------------------------------------
# Test 4 : No PRODUCES — _PRODUCES absent (not undef, not empty array)
# -----------------------------------------------------------------------
{
    my $e   = make_engine();
    my $dir = rule_dir(rule01 => {
        RULE   => 'no-produces',
        FIND   => { x => { attribut => 'color' } },
        ACTION => q{$x->set('tagged','y'); 1},
    });
    $e->loadRules($dir);
    my $rule = $e->{_RULES}[0];
    ok(!defined $rule->{_PRODUCES},  'Test 4 - no PRODUCES: _PRODUCES absent from rule Frame');
}

done_testing();
