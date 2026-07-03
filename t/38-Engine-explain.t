#!perl -T

# Tests for _EXPLAIN mode:
#   $agent->set('_EXPLAIN', 1) enables non-firing trace
#   explain_trace() returns arrayref of { rule, scope, blocked }
#   clear_explain() resets the trace
#   Rules that fire are NOT in the trace
#   _EXPLAIN does not interfere with normal engine behaviour
#   _EXPLAIN does not capture firings when disabled

use strict;
use Test::More tests => 16;
use Chorus::Frame;
use Chorus::Engine;

diag("Testing _EXPLAIN mode — Chorus::Engine $Chorus::Engine::VERSION, Perl $], $^X");

sub make_engine {
    my $e = Chorus::Engine->new();
    $e->set('BOARD', Chorus::Frame->new());
    return $e;
}

# -----------------------------------------------------------------------
# Test 1 : explain_trace on fresh engine — empty arrayref
# -----------------------------------------------------------------------
{
    my $e = make_engine();
    my $t = $e->explain_trace();
    is(ref $t, 'ARRAY', 'Test 1 - explain_trace returns arrayref on fresh engine');
    is(scalar @$t, 0,   'Test 1b - trace is empty on fresh engine');
}

# -----------------------------------------------------------------------
# Test 2 : _EXPLAIN off — non-firing rule NOT traced
# -----------------------------------------------------------------------
{
    my $e  = make_engine();
    my $f1 = Chorus::Frame->new(color => 'blue');
    $e->addrule(
        _ID    => 'only-red',
        _SCOPE => { x => sub { [fmatch(slot => 'color')] } },
        _APPLY => sub { my %o = @_; return unless ($o{x}{color}//'') eq 'red'; $o{x}->set('tagged','y'); 1 },
    );
    $e->loop();
    is(scalar @{ $e->explain_trace() }, 0, 'Test 2 - _EXPLAIN off: no trace recorded');
}

# -----------------------------------------------------------------------
# Test 3 : _EXPLAIN on — non-firing rule IS traced
# -----------------------------------------------------------------------
{
    my $e  = make_engine();
    $e->set('_EXPLAIN', 1);
    my $f1 = Chorus::Frame->new(color => 'blue');
    my $f2 = Chorus::Frame->new(color => 'red');
    $e->addrule(
        _ID    => 'only-red',
        _SCOPE => { x => sub { [fmatch(slot => 'color')] } },
        _APPLY => sub { my %o = @_; return unless ($o{x}{color}//'') eq 'red'; $o{x}->set('tagged','y'); 1 },
    );
    $e->loop();
    my $trace = $e->explain_trace();
    ok(scalar @$trace > 0,                     'Test 3 - _EXPLAIN on: trace has entries');
    # f1 (blue) should be traced; f2 (red) should fire, not traced
    my @non_fired = grep { !$_->{scope}{x}{tagged} } @$trace;
    ok(scalar @non_fired > 0,                  'Test 3b - non-fired frames in trace');
    is($non_fired[0]{rule}, 'only-red',        'Test 3c - correct rule _ID in trace');
    is($non_fired[0]{blocked}, 'APPLY',        'Test 3d - blocked reason is APPLY');
    ok(!$f1->tagged,                           'Test 3e - f1 (blue) not tagged (correct)');
    ok($f2->tagged,                            'Test 3f - f2 (red) tagged (rule fired)');
}

# -----------------------------------------------------------------------
# Test 4 : fired rules are NOT in the trace
#          Use _TERMINAL => 'solved' to stop after the first fire —
#          only one _APPLY call, returns true → not recorded in trace.
# -----------------------------------------------------------------------
{
    my $e = make_engine();
    $e->set('_EXPLAIN', 1);
    my $f = Chorus::Frame->new(color => 'blue');
    $e->addrule(
        _ID       => 'fire-and-stop',
        _SCOPE    => { x => sub { [fmatch(slot => 'color')] } },
        _APPLY    => sub { my %o = @_; $o{x}->set('done','y'); 1 },
        _TERMINAL => 'solved',
    );
    $e->loop();
    is(scalar @{ $e->explain_trace() }, 0, 'Test 4 - fired rule not recorded in trace');
    ok($f->done,                            'Test 4b - frame was tagged (rule did fire)');
}

# -----------------------------------------------------------------------
# Test 5 : clear_explain resets the trace
# -----------------------------------------------------------------------
{
    my $e = make_engine();
    $e->set('_EXPLAIN', 1);
    my $f = Chorus::Frame->new(color => 'blue');
    $e->addrule(
        _ID    => 'only-red',
        _SCOPE => { x => sub { [fmatch(slot => 'color')] } },
        _APPLY => sub { my %o = @_; return unless ($o{x}{color}//'') eq 'red'; 1 },
    );
    $e->loop();
    ok(scalar @{ $e->explain_trace() } > 0, 'Test 5 - trace has entries before clear');
    my $ret = $e->clear_explain();
    is($ret, $e,                             'Test 5b - clear_explain returns engine');
    is(scalar @{ $e->explain_trace() }, 0,  'Test 5c - trace empty after clear_explain');
}

# -----------------------------------------------------------------------
# Test 6 : _EXPLAIN does not affect engine correctness
# -----------------------------------------------------------------------
{
    my $e = make_engine();
    $e->set('_EXPLAIN', 1);
    my $f1 = Chorus::Frame->new(score => 3);
    my $f2 = Chorus::Frame->new(score => 7);
    $e->addrule(
        _ID    => 'high-score',
        _SCOPE => { x => sub { [fmatch(slot => 'score')] } },
        _APPLY => sub { my %o = @_; return unless $o{x}{score} > 5; $o{x}->set('winner','y'); 1 },
    );
    $e->loop();
    ok(!$f1->winner, 'Test 6 - _EXPLAIN on: low-score frame not tagged');
    ok($f2->winner,  'Test 6b - _EXPLAIN on: high-score frame tagged correctly');
}

done_testing();
