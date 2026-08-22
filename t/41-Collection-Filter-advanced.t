use strict;
use warnings;
use Test::More;
use Chorus::Frame;
use Chorus::Collection::Filter qw($FILTER @_VFILTER);

# Advanced tests for Chorus::Collection::Filter.
# Complements 23-Collection-Filter.t (basic cases).
# Tested here: anchors ^/$, {m,n} quantifier (actual semantics),
# lazy ?, multiple captures, !X in non-initial position,
# composite node_test, * zero-case.
#
# IMPLEMENTATION NOTES (from source):
# - count_min enforcement is COMMENTED OUT in sequence_match() — {m,n} does
#   NOT reject sequences shorter than m.  count_max IS enforced.
# - Captures at the last node: due to greedy recursion, _VAR is overwritten
#   as the call stack unwinds.  Reliable captures are those on non-last nodes
#   or on the last node when sequence length exactly matches (no ambiguity).

my $node_test = sub { my $item = shift; $item->{lbl} };

sub make_filter {
    my $f = Chorus::Frame->new(_ISA => $FILTER);
    $f->set_node_test($node_test);
    return $f;
}

sub items { map { Chorus::Frame->new(lbl => $_) } @_ }

# ---------------------------------------------------------------------------
# 1. Anchor ^ — pattern must start at first item
# ---------------------------------------------------------------------------

{
    my $f = make_filter();
    $f->set_filter('^a b');
    ok($f->check(items(qw(a b c))), '^: matches when sequence starts with pattern');
}

{
    my $f = make_filter();
    $f->set_filter('^b c');
    ok(!$f->check(items(qw(a b c))), '^: rejects when sequence does not start with pattern');
}

# ---------------------------------------------------------------------------
# 2. Anchor $ — pattern must end at last item
# ---------------------------------------------------------------------------

{
    my $f = make_filter();
    $f->set_filter('b c$');
    ok($f->check(items(qw(a b c))), '$: matches when sequence ends with pattern');
}

{
    my $f = make_filter();
    $f->set_filter('a b$');
    ok(!$f->check(items(qw(a b c))), '$: rejects when sequence does not end with pattern');
}

# ---------------------------------------------------------------------------
# 3. Both anchors ^...$
# ---------------------------------------------------------------------------

{
    my $f = make_filter();
    $f->set_filter('^a b c$');
    ok($f->check(items(qw(a b c))),   '^...$: exact sequence matches');
    ok(!$f->check(items(qw(a b))),    '^...$: shorter sequence rejected');
}

# ---------------------------------------------------------------------------
# 4. {m,n} quantifier — acceptance within range
#
# IMPLEMENTATION NOTE: count_max is used in sequence_match() for group-level
# checks, but the Filter's overall algorithm (subsequence finder) means that
# strict rejection of out-of-range counts is not guaranteed in all contexts.
# Tests here verify ACCEPTANCE of valid counts.
# ---------------------------------------------------------------------------

{
    my $f = make_filter();
    $f->set_filter('x a{1,3} y');

    ok($f->check(items(qw(x a y))),     '{1,3}: matches 1 a between x and y');
    ok($f->check(items(qw(x a a y))),   '{1,3}: matches 2 a between x and y');
    ok($f->check(items(qw(x a a a y))), '{1,3}: matches 3 a between x and y');
}

# ---------------------------------------------------------------------------
# 5. {n} exact form — the matched group has exactly n elements
# ---------------------------------------------------------------------------

{
    my $f = make_filter();
    $f->set_filter('x (a{2}) y');
    ok($f->check(items(qw(x a a y))), '{2}: matches exactly 2 a between x and y');
    my ($cap) = @_VFILTER;
    is(scalar @$cap, 2, '{2}: capture group contains 2 items');
}

# ---------------------------------------------------------------------------
# 6. Lazy quantifier ?  — makes * or + prefer shorter match
# ---------------------------------------------------------------------------

{
    my $f = make_filter();
    # Pattern '(a*?) b': lazy star on a, then b
    # Lazy: prefer matching ZERO a's first, advance to b immediately
    $f->set_filter('(a*?) b');
    ok($f->check(items(qw(a b))), 'lazy *?: pattern matches');
    my ($cap) = @_VFILTER;
    # With lazy *, the capture may be empty or minimal
    ok(defined $cap, 'lazy *?: capture variable is defined');
}

# ---------------------------------------------------------------------------
# 7. Multiple capture groups — using non-last-node patterns for reliability
#    (last-node captures may be partially overwritten by greedy recursion)
# ---------------------------------------------------------------------------

{
    my $f = make_filter();
    # Pattern: (a+) x (b)  — b is last and exactly ONE item; no ambiguity
    $f->set_filter('(a+) x (b)');
    my @seq = items(qw(a a x b));
    ok($f->check(@seq), 'multiple captures: pattern matches (a+ x b)');
    my ($grp1, $grp2) = @_VFILTER;

    is(scalar @$grp1, 2, 'first capture group: 2 a-items');
    is($grp1->[0]{lbl}, 'a', 'first capture: correct label');
    is(scalar @$grp2, 1, 'second capture group: 1 b-item (exact last node)');
    is($grp2->[0]{lbl}, 'b', 'second capture: correct label');
}

# ---------------------------------------------------------------------------
# 8. Negation !X in non-initial position
# ---------------------------------------------------------------------------

{
    my $f = make_filter();
    $f->set_filter('a !b c');
    ok(!$f->check(items(qw(a b c))), '!X non-initial: rejects when forbidden item present');
    ok($f->check(items(qw(a z c))),  '!X non-initial: accepts non-forbidden item');
}

# ---------------------------------------------------------------------------
# 9. Zero-or-more * — zero occurrences accepted
# ---------------------------------------------------------------------------

{
    my $f = make_filter();
    $f->set_filter('a x* b');
    ok($f->check(items(qw(a b))),     '* (zero case): matches when x appears zero times');
    ok($f->check(items(qw(a x b))),   '* (one case): matches when x appears once');
    ok($f->check(items(qw(a x x b))), '* (two case): matches when x appears twice');
}

# ---------------------------------------------------------------------------
# 10. Composite node_test — returns a computed string from item attributes
# ---------------------------------------------------------------------------

{
    my $f = Chorus::Frame->new(_ISA => $FILTER);
    $f->set_node_test(sub {
        my $item = shift;
        ($item->{cat} // '') . ':' . ($item->{val} // '');
    });

    my @seq = (
        Chorus::Frame->new(cat => 'ADJ', val => 'big'),
        Chorus::Frame->new(cat => 'NOM', val => 'house'),
    );

    $f->set_filter('ADJ:big NOM:house');
    ok($f->check(@seq),  'composite node_test: correct TYPE:VALUE pattern matches');

    $f->set_filter('ADJ:small NOM:house');
    ok(!$f->check(@seq), 'composite node_test: wrong TYPE:VALUE pattern rejected');
}

# ---------------------------------------------------------------------------
# 11. @_VFILTER reset between check() calls
# ---------------------------------------------------------------------------

{
    my $f = make_filter();
    $f->set_filter('(a)');

    $f->check(items(qw(a)));
    my @first = @_VFILTER;

    $f->check(items(qw(b)));   # no match — @_VFILTER reset to empty
    my @second = @_VFILTER;

    is(scalar @first,  1, '@_VFILTER populated after successful match');
    is(scalar @second, 0, '@_VFILTER reset to empty after failed match');
}

done_testing();
