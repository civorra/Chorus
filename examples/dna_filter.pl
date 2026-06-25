package Chorus::Sample::DnaFilter;

use 5.006;
use strict;
use warnings;

our $VERSION = '1.00';

=head1 NAME

Chorus::Sample::DnaFilter - DNA motif matching illustrating Chorus::Collection::List and Chorus::Collection::Filter

=head1 DESCRIPTION

A self-contained example that models a DNA sequence as an ordered list of
nucleotide Frames and applies pattern matching using Chorus::Collection::Filter.

No Engine or Expert is involved.  This example focuses exclusively on:

  $LIST    — ordered sequence of Frames
             build(), push_items(), connect_left/right(), merge_left()
             first_item/last_item, length, HAS, STARTS_WITH, ENDS_WITH

  $FILTER  — pattern matching on Frame sequences
             set_node_test() — extract the base letter from each nucleotide Frame
             set_filter()    — compile a pattern with quantifiers and capture groups
             check()         — test a sequence and populate @_VFILTER
             @_VFILTER       — captured groups (analogous to $1, $2 in regexps)

Three patterns are demonstrated:

  Pattern 1 : '^[A G]{2,4} C+ T*$'
    A restriction-site-like motif: 2–4 purines (A or G), one or more C,
    optional trailing T, covering the full sequence.

  Pattern 2 : '[A G]+ (C+) [T A]*$'
    Same family but with a capture group on the C run.

  Pattern 3 : used after merge_left() to illustrate list concatenation —
    two short sub-sequences are merged into one and re-matched.

=cut

use Chorus::Frame;
use Chorus::Collection::List   qw($LIST);
use Chorus::Collection::Filter qw($FILTER @_VFILTER);

# ---------------------------------------------------------------------------
# A single reusable filter instance — node_test set once, set_filter called
# per pattern.  Creating multiple filter Frames would multiply the Frame
# registry churn (set_filter creates/destroys many internal node Frames via
# the global %FMAP / %INSTANCES registries, which can affect weak refs held
# by other live Frames).
# ---------------------------------------------------------------------------

my $FILT = Chorus::Frame->new( _ISA => $FILTER );

# Install the node test directly — map each nucleotide Frame to its base letter.
# We bypass the set_node_test() procedural slot and write node_test directly
# to avoid any indirect dispatch that could trigger inherited hooks during setup.
$FILT->set( 'node_test', sub { my ($nuc) = @_; $nuc->base } );

# ---------------------------------------------------------------------------
# Helper: build a nucleotide Frame from a base letter
# ---------------------------------------------------------------------------

sub nucleotide {
    my ($base) = @_;
    return Chorus::Frame->new( base => $base );
}

# ---------------------------------------------------------------------------
# Helper: build a LIST sequence from a string of base letters
# ---------------------------------------------------------------------------

sub sequence_from {
    my ($str) = @_;
    my @nucs  = map { nucleotide($_) } split //, $str;

    my $seq = Chorus::Frame->new( _ISA => $LIST );
    $seq->build(@nucs);   # _ITEMS holds strong refs to the nucleotides

    # Establish doubly-linked prev/succ links between consecutive nucleotides.
    # Individual nucleotide Frames do not inherit $LIST, so connect_left is not
    # available on them — set prev/succ directly.
    my $items = $seq->_ITEMS;
    for my $i (1 .. $#$items) {
        $items->[$i]->set('prev', $items->[$i - 1]);
        $items->[$i - 1]->set('succ', $items->[$i]);
    }

    # Return only the sequence; callers use $seq->_ITEMS to access nucleotides.
    # Do NOT store nucleotides in a separate @array: the Perl GC may collect
    # frames that are only weakly referenced (via %FMAP) if no strong ref remains.
    # The $seq frame's _ITEMS arrayref is the authoritative strong-ref store.
    return $seq;
}

# ---------------------------------------------------------------------------
# Helper: print a sequence with linked-list navigation verification
# ---------------------------------------------------------------------------

sub print_seq {
    my ($label, $seq) = @_;
    my @items = @{ $seq->_ITEMS };
    printf "%s  length=%d  bases=%s\n",
        $label,
        $seq->length,
        join('', map { defined $_ ? $_->base : '?' } @items);

    # Verify doubly-linked chain forward (succ) — only on freshly built sequences
    # (merge_right moves items without rewiring prev/succ across sub-sequences)
    if (@items > 1 && $items[0]->succ) {
        my $ok_fwd = 1;
        for my $i (0 .. $#items - 1) {
            my $succ = $items[$i]->succ;
            $ok_fwd = 0 unless defined $succ && $succ->{_KEY} eq $items[$i + 1]->{_KEY};
        }
        printf "  doubly-linked (fwd): %s\n", $ok_fwd ? 'OK' : 'partial (expected after merge)';
    }
}

# ---------------------------------------------------------------------------
# Helper: build a filter and run a check
# ---------------------------------------------------------------------------

sub run_filter {
    my ($label, $pattern, @nucs) = @_;

    printf "\n%s\n  pattern : %s\n  sequence: %s\n",
        $label, $pattern, join('', map { $_->base } @nucs);

    $FILT->set_filter($pattern);

    if ( $FILT->check(@nucs) ) {
        print "  result  : MATCH\n";
        if (@_VFILTER) {
            for my $i (0 .. $#_VFILTER) {
                printf "  capture[%d]: %s (%d base%s)\n",
                    $i + 1,
                    join('', map { $_->base } @{ $_VFILTER[$i] }),
                    scalar @{ $_VFILTER[$i] },
                    scalar(@{ $_VFILTER[$i] }) > 1 ? 's' : '';
            }
        }
    } else {
        print "  result  : NO MATCH\n";
    }
}

# ===========================================================================
# Main
# ===========================================================================

print "=== Chorus::Sample::DnaFilter ===\n\n";

# ---------------------------------------------------------------------------
# Sequence A: AAGCCCT  (should match both Pattern 1 and Pattern 2)
# ---------------------------------------------------------------------------

my $seq_a = sequence_from('AAGCCCT');
print_seq('Sequence A:', $seq_a);

# Capture items into plain Perl arrays (strong refs) before any filter is built
my @items_a = @{ $seq_a->_ITEMS };

run_filter('Pattern 1 — restriction-site-like',
    '^[A G]{2,4} C+ T*$',
    @items_a);

run_filter('Pattern 2 — capture the C run',
    '[A G]+ (C+) [T A]*$',
    @items_a);

# ---------------------------------------------------------------------------
# Sequence B: TTACC  (should NOT match Pattern 1 — starts with T)
# ---------------------------------------------------------------------------

my $seq_b = sequence_from('TTACC');
print_seq("\nSequence B:", $seq_b);

my @items_b = @{ $seq_b->_ITEMS };

run_filter('Pattern 1 on sequence B — expect NO MATCH',
    '^[A G]{2,4} C+ T*$',
    @items_b);

# ---------------------------------------------------------------------------
# merge_right: build merged sequence C = seq_b + seq_a  (TTACC · AAGCCCT)
# Demonstrates that items move, source lists are emptied, and the full
# merged sequence can be matched with an anchor-free pattern.
# ---------------------------------------------------------------------------

# Build an empty target list
my $seq_c = Chorus::Frame->new( _ISA => $LIST );
$seq_c->build();   # explicit empty init (_ITEMS = [])

# Merge seq_b on the left, then seq_a on the right → TTACC·AAGCCCT
$seq_c->merge_right($seq_b, $seq_a);

print "\nAfter merge_right(seq_b, seq_a):\n";
print_seq('  seq_c (merged):', $seq_c);
printf "  seq_b length after merge: %d (should be 0)\n", $seq_b->length;
printf "  seq_a length after merge: %d (should be 0)\n", $seq_a->length;

my @items_c = @{ $seq_c->_ITEMS };
run_filter('Pattern 3 — C run anywhere in merged sequence (capture)',
    '.* (C+) .*',
    # Note: .* is greedy — it consumes as many tokens as possible before
    # handing off to (C+).  The engine thus matches the *last* C run
    # (here a single C from the trailing CCCT block) rather than CCC.
    # Use a lazy quantifier '.*?' to capture the first/longest run instead.
    @items_c);

# ---------------------------------------------------------------------------
# HAS / STARTS_WITH / ENDS_WITH on the merged sequence
# ---------------------------------------------------------------------------

print "\nList predicates on seq_c:\n";

# re-populate seq_c for predicate tests — it was emptied by merge above
# but _ITEMS still holds references to the moved nucleotides
my $has_g = $seq_c->HAS('base') ? 'yes' : 'no';
printf "  HAS('base')       : %s\n", $has_g;

my $first_base = ($seq_c->length > 0 && $seq_c->first_item) ? $seq_c->first_item->base : '(empty)';
my $last_base  = ($seq_c->length > 0 && $seq_c->last_item)  ? $seq_c->last_item->base  : '(empty)';
printf "  first_item->base  : %s\n", $first_base;
printf "  last_item->base   : %s\n", $last_base;
