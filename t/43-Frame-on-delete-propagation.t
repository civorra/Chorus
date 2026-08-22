use strict;
use warnings;
use Test::More;
use Chorus::Frame;

# Tests for _ON_DELETE with inter-frame propagation.
# Complements 32-Frame-on-delete.t (basic triggering).
# Tested here: _ON_DELETE calling set() on another frame, fmatch() inside
# _ON_DELETE, and cascade deletion (A._ON_DELETE deletes B).

sub reset_registry { Chorus::Frame::_reset() }

# ---------------------------------------------------------------------------
# 1. _ON_DELETE calls set() on another Frame
# ---------------------------------------------------------------------------

reset_registry();

my $other1 = Chorus::Frame->new( status => { _VALUE => 'active' } );
my $f1     = Chorus::Frame->new(
    tag        => 'primary',
    _ON_DELETE => sub {
        # When tag is deleted, mark $other1 as 'orphaned'
        $other1->set('status', 'orphaned');
    },
);

$f1->delete('tag');
is($other1->get('status'), 'orphaned',
   '_ON_DELETE: set() on another frame propagates the deletion side-effect');

# ---------------------------------------------------------------------------
# 2. _ON_DELETE uses fmatch() to find and update related frames
# ---------------------------------------------------------------------------

reset_registry();

my $ref_a = Chorus::Frame->new( belongs_to => 'group_x', value => 1 );
my $ref_b = Chorus::Frame->new( belongs_to => 'group_x', value => 2 );
my $ref_c = Chorus::Frame->new( belongs_to => 'group_y', value => 3 );  # different group

my $group = Chorus::Frame->new(
    group_id   => 'group_x',
    _ON_DELETE => sub {
        # When group is dissolved, mark all members as orphaned
        for my $member (fmatch(slot => 'belongs_to')) {
            $member->set('orphaned', 'Y') if ($member->get('belongs_to') // '') eq 'group_x';
        }
    },
);

$group->delete('group_id');

is($ref_a->get('orphaned'), 'Y',  '_ON_DELETE + fmatch: member A marked orphaned');
is($ref_b->get('orphaned'), 'Y',  '_ON_DELETE + fmatch: member B marked orphaned');
ok(!defined $ref_c->get('orphaned'), '_ON_DELETE + fmatch: non-member C untouched');

# ---------------------------------------------------------------------------
# 3. Cascade deletion: A._ON_DELETE calls delete() on B, triggering B._ON_DELETE
# ---------------------------------------------------------------------------

reset_registry();

my $b_on_delete_fired = 0;
my $b3 = Chorus::Frame->new(
    label      => 'b_label',
    _ON_DELETE => sub { $b_on_delete_fired++ },
);

my $a3 = Chorus::Frame->new(
    label      => 'a_label',
    _ON_DELETE => sub {
        # Cascade: deleting A triggers deletion of B's slot
        $b3->delete('label');
    },
);

$a3->delete('label');

is($b_on_delete_fired, 1,
   'cascade: A._ON_DELETE calls B.delete() which triggers B._ON_DELETE');

# ---------------------------------------------------------------------------
# 4. $SELF in _ON_DELETE is the Frame on which delete() was called
#    (even when another Frame's slot deletion is triggered from within)
# ---------------------------------------------------------------------------

reset_registry();

my $self_seen_4;
my $f4 = Chorus::Frame->new(
    data       => 'present',
    _ON_DELETE => sub { $self_seen_4 = $SELF },
);

$f4->delete('data');
is($self_seen_4, $f4, '$SELF in _ON_DELETE is the frame on which delete() was called');

# ---------------------------------------------------------------------------
# 5. _ON_DELETE + set() result is visible to fmatch() after deletion
# ---------------------------------------------------------------------------

reset_registry();

my $tracker = Chorus::Frame->new( count => { _VALUE => 0 } );
my $f5      = Chorus::Frame->new(
    item       => 'x',
    _ON_DELETE => sub {
        my $current = $tracker->get('count') // 0;
        $tracker->set('count', $current + 1);
    },
);

my @before = grep { ($_->get('count') // 0) == 0 } fmatch(slot => 'count');
is(scalar @before, 1, 'before deletion: tracker count = 0');

$f5->delete('item');

my @after = grep { ($_->get('count') // 0) == 1 } fmatch(slot => 'count');
is(scalar @after, 1,
   '_ON_DELETE increments count via set(); result visible to fmatch() after deletion');

done_testing();
