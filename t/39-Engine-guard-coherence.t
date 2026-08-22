use strict;
use warnings;
use Test::More;
use Chorus::Engine;

# Tests for Chorus::Engine::_check_guard_coherence()
#
# This private function is called by loadRules() for each parsed YAML rule.
# It warns when the slot tested in EXCEPTION: "defined $f->{X}" is NOT written
# by the rule's ACTION/EFFET via $f->set('X', ...).
#
# A mismatch means the rule could be silently bypassed in projects where 'X' is
# pre-populated — a correctness bug invisible at test time on simple sandboxes.

# Helper: call the private function and capture any warning emitted
sub check_coherence {
    my ($rule, $file) = @_;
    my $warned = '';
    local $SIG{__WARN__} = sub { $warned .= $_[0] };
    Chorus::Engine::_check_guard_coherence($rule, $file // 'test.yml');
    return $warned;
}

# ---------------------------------------------------------------------------
# 1. No warning when guard slot is written by the action (coherent rule)
# ---------------------------------------------------------------------------

my $w = check_coherence({
    REGLE     => 'coherent-rule',
    EXCEPTION => 'defined $p->{result_ok}',
    EFFET     => '$p->set(\'result_ok\', \'OUI\'); 1',
});

is($w, '', 'no warning when guard slot matches a slot written by EFFET');

# ---------------------------------------------------------------------------
# 2. Warning emitted when guard slot is NOT written by the action
# ---------------------------------------------------------------------------

my $w2 = check_coherence({
    REGLE     => 'mismatch-rule',
    EXCEPTION => 'defined $p->{result_ok}',
    EFFET     => '$p->set(\'other_slot\', \'value\'); 1',
});

ok($w2 ne '', 'warning emitted when guard slot is not written by ACTION');
like($w2, qr/GUARD MISMATCH/, 'warning message contains "GUARD MISMATCH"');
like($w2, qr/mismatch-rule/,  'warning message contains the rule name');
like($w2, qr/result_ok/,      'warning message contains the guard slot name');

# ---------------------------------------------------------------------------
# 3. No warning when there is no EXCEPTION clause
# ---------------------------------------------------------------------------

my $w3 = check_coherence({
    REGLE => 'no-exception-rule',
    EFFET => '$p->set(\'slot\', 1); 1',
});

is($w3, '', 'no warning when rule has no EXCEPTION clause');

# ---------------------------------------------------------------------------
# 4. No warning when ACTION has no set() calls (cannot validate)
# ---------------------------------------------------------------------------

my $w4 = check_coherence({
    REGLE     => 'no-set-rule',
    EXCEPTION => 'defined $p->{result_ok}',
    EFFET     => '$p->solved(); 1',
});

is($w4, '', 'no warning when ACTION has no set() calls (validation skipped)');

# ---------------------------------------------------------------------------
# 5. English aliases: RULE + ACTION also detected
# ---------------------------------------------------------------------------

my $w5 = check_coherence({
    RULE      => 'english-mismatch',
    EXCEPTION => 'defined $w->{conformance_ok}',
    ACTION    => '$w->set(\'strength_ok\', \'OUI\'); 1',
});

ok($w5 ne '', 'warning emitted with English aliases (RULE/ACTION)');
like($w5, qr/english-mismatch/, 'warning contains English rule name');

# ---------------------------------------------------------------------------
# 6. Guard slot pattern: "defined $var->{slot}" — different variable name
# ---------------------------------------------------------------------------

my $w6 = check_coherence({
    REGLE     => 'var-name-rule',
    EXCEPTION => 'defined $element->{flag}',
    EFFET     => '$element->set(\'other\', 1); 1',
});

ok($w6 ne '', 'guard detection works regardless of variable name ($element->{flag})');

# ---------------------------------------------------------------------------
# 7. Multiple set() calls — guard slot written among others → no warning
# ---------------------------------------------------------------------------

my $w7 = check_coherence({
    REGLE     => 'multi-set-rule',
    EXCEPTION => 'defined $p->{guard}',
    EFFET     => '$p->set(\'intermediate\', 1); $p->set(\'guard\', \'done\'); 1',
});

is($w7, '', 'no warning when guard slot is one of multiple written slots');

# ---------------------------------------------------------------------------
# 8. Warning contains the suggested fix
# ---------------------------------------------------------------------------

my $w8 = check_coherence({
    REGLE     => 'fix-hint-rule',
    EXCEPTION => 'defined $p->{wrong_guard}',
    EFFET     => '$p->set(\'actual_result\', \'OUI\'); 1',
});

like($w8, qr/Suggested fix/, 'warning includes a suggested fix');
like($w8, qr/actual_result/,  'suggested fix references the actually written slot');

done_testing();
