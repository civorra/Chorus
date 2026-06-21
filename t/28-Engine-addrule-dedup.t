#!perl -T

# Tests for addrule() duplicate _ID detection (DEBUG-01 §10)
#
# When two YAML files (or two addrule() calls) declare the same REGLE:/
# _ID, the second must be silently skipped with a warning — the rule
# must not fire twice per cycle.

use strict;
use Test::More tests => 7;
use Chorus::Frame;
use Chorus::Engine;
use File::Temp qw(tempdir);
use YAML qw(DumpFile);

diag("Testing Chorus::Engine::addrule duplicate _ID detection, Perl $], $^X");

sub make_engine {
    my $e = Chorus::Engine->new();
    $e->set('BOARD', Chorus::Frame->new());
    return $e;
}

# Capture warnings into an arrayref
sub capture_warnings (&) {
    my ($code) = @_;
    my @warns;
    local $SIG{__WARN__} = sub { push @warns, @_ };
    $code->();
    return \@warns;
}

# -----------------------------------------------------------------------
# Test 1-2 : addrule() direct — doublon détecté, warning émis
# -----------------------------------------------------------------------
{
    Chorus::Frame::_reset();

    my $e = make_engine();
    $e->addrule(_ID => 'my-rule', _SCOPE => {}, _APPLY => sub { });
    is(scalar @{$e->{_RULES}}, 1, 'Test 1 - première règle chargée');

    my $warns = capture_warnings {
        $e->addrule(_ID => 'my-rule', _SCOPE => {}, _APPLY => sub { });
    };
    ok((grep { /duplicate rule _ID 'my-rule'/ } @$warns),
        "Test 2 - doublon via addrule() émet un warning");
}

# -----------------------------------------------------------------------
# Test 3 : après doublon, _RULES ne contient toujours qu'une règle
# -----------------------------------------------------------------------
{
    Chorus::Frame::_reset();

    my $e = make_engine();
    $e->addrule(_ID => 'my-rule', _SCOPE => {}, _APPLY => sub { });

    capture_warnings { $e->addrule(_ID => 'my-rule', _SCOPE => {}, _APPLY => sub { }) };

    is(scalar @{$e->{_RULES}}, 1,
        'Test 3 - _RULES contient 1 seule règle après doublon');
}

# -----------------------------------------------------------------------
# Test 4-5 : règles sans _ID ou avec _ID distincts — pas de dédup
# -----------------------------------------------------------------------
{
    Chorus::Frame::_reset();

    my $e = make_engine();
    $e->addrule(_SCOPE => {}, _APPLY => sub { });
    $e->addrule(_SCOPE => {}, _APPLY => sub { });
    is(scalar @{$e->{_RULES}}, 2, 'Test 4 - deux règles sans _ID coexistent');

    $e->addrule(_ID => 'rule-a', _SCOPE => {}, _APPLY => sub { });
    $e->addrule(_ID => 'rule-b', _SCOPE => {}, _APPLY => sub { });
    is(scalar @{$e->{_RULES}}, 4, 'Test 5 - deux règles avec _ID distincts coexistent');
}

# -----------------------------------------------------------------------
# Test 6-7 : doublon via loadRules() — deux fichiers YAML même REGLE
# La règle ne doit s'appliquer qu'une fois par frame
# -----------------------------------------------------------------------
{
    Chorus::Frame::_reset();

    my $e  = make_engine();
    my $f1 = Chorus::Frame->new(color => 'blue');

    my $dir = tempdir(CLEANUP => 1);
    DumpFile("$dir/R01-tag.yml", {
        REGLE     => 'tag-frame',
        CHERCHER  => { x => { attribut => 'color' } },
        EXCEPTION => q{$x->{count}},
        EFFET     => q{$x->set('count', ($x->{count} || 0) + 1); 1},
    });
    DumpFile("$dir/R02-tag-dup.yml", {
        REGLE     => 'tag-frame',       # même _ID !
        CHERCHER  => { x => { attribut => 'color' } },
        EXCEPTION => q{$x->{count}},
        EFFET     => q{$x->set('count', ($x->{count} || 0) + 1); 1},
    });

    my $warns = capture_warnings { $e->loadRules($dir) };
    ok((grep { /duplicate rule _ID 'tag-frame'/ } @$warns),
        "Test 6 - loadRules() émet un warning pour le doublon YAML");

    $e->loop();

    is($f1->count, 1,
        "Test 7 - règle dupliquée en YAML ne s'applique qu'une fois (count=1)");
}

done_testing();
