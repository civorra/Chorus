package Chorus::Expert;

use 5.006;
use strict;
use warnings;

our $VERSION = '1.05';

=head1 NAME

Chorus::Expert - Orchestrator for one or more Chorus::Engine agents working on a shared task.

=head1 VERSION

Version 1.05

=head1 DESCRIPTION

C<Chorus::Expert> does three things:

=over 4

=item 1.

Registers one or more L<Chorus::Engine> agents.

=item 2.

Provides every agent with a shared L<Chorus::Frame> called B<BOARD>, used for
inter-agent communication and to carry the input to the pipeline.

=item 3.

Runs a C<do/until> loop over the agents until one of them signals C<SOLVED> or
C<FAILED>.

=back

=head1 SYNOPSIS

  use Chorus::Expert;
  use Chorus::Engine;

  my $agent1 = Chorus::Engine->new(_IDENT => 'Enrich');
  $agent1->addrule( ... );

  my $agent2 = Chorus::Engine->new(_IDENT => 'Validate');
  $agent2->addrule( ... );

  my $xprt = Chorus::Expert->new();
  $xprt->register($agent1, $agent2);

  my $ok = $xprt->process($input);   # 1 = solved, undef = failed

=head1 METHODS

=head2 new

Creates a new C<Chorus::Expert> instance with an empty agent list and a fresh
shared BOARD frame.

  my $xprt = Chorus::Expert->new();

B<Note> -- arguments passed to C<new()> are currently ignored.  To override
C<_MAX_ITER>, assign directly after construction:

  my $xprt = Chorus::Expert->new();
  $xprt->{_MAX_ITER} = 50_000;   # default is 10,000

=head2 register

Registers one or more agents.  Each agent receives:

=over 4

=item * C<BOARD> -- the shared frame, accessible as C<< $agent->BOARD >>.

=item * C<EXPERT> -- a back-reference to this expert instance.

=back

  $xprt->register($agent1, $agent2, $agent3);

Agents are stored in registration order, which determines the order in which
C<process()> calls their C<loop()> method.

The termination agent (the one that calls C<solved()>) should be registered
B<last>.

=head2 debug

Enables verbose output to STDERR for the main process loop.

  $xprt->debug(1);   # enable
  $xprt->debug(0);   # disable

=head2 process

Runs the pipeline.

  my $ok = $xprt->process();           # no input
  my $ok = $xprt->process($something); # $something available as $agent->BOARD->INPUT

The main loop iterates over all registered agents in order, calling C<loop()>
on each one, until C<BOARD->{SOLVED}> or C<BOARD->{FAILED}> is set.  It respects
C<_REPLAY> and C<_REPLAY_ALL> signals from the agents.

An agent tagged with C<_LOCK_UNTIL_STABLE> is skipped when any earlier agent in
the current iteration has already succeeded (C<_SUCCES> is true).  This allows
priority-based sequencing without explicit coupling.

If C<_MAX_ITER> full iterations complete without termination, a warning is emitted
and C<process()> returns C<undef>.

Returns C<1> if C<SOLVED>, C<undef> if C<FAILED> or if C<_MAX_ITER> is exceeded.

=cut

use Chorus::Frame;

use constant DEFAULT_MAX_ITER => 10_000;

sub new {
  my $class = shift;
  return bless {
    _agents => [],
    _board  => Chorus::Frame->new(),
  }, $class;
}

sub register {
  my $this  = shift;
  my $board = $this->{_board};
  $_->set('BOARD',  $board) for @_;   # BOARD shared between agents of this instance
  $_->set('EXPERT', $this)  for @_;   # each agent can talk back to me
  push @{ $this->{_agents} }, @_;
  return $this;
}

# --

sub debug {
  my ($this, $level) = @_;
  $this->{_DEBUG} = $level;
}

sub process {
  my ($this, $input) = @_;
  my $board   = $this->{_board};
  my $agents  = $this->{_agents};
  $board->set('INPUT', $input);
  my $max_iter = $this->{_MAX_ITER} // DEFAULT_MAX_ITER;
  my $iter = 0;
  do {
       if (++$iter > $max_iter) {
           warn "Chorus::Expert - process() reached max iterations ($max_iter) without SOLVED or FAILED\n";
           return;
       }
       my @processed = ();
       for my $agent (@$agents) {

          if ($agent->_LOCK_UNTIL_STABLE ) {
             print STDERR "Chorus::Expert - Agent $agent->{_IDENT} is tagged with LOCK_UNTIL_STABLE\n" if $this->{_DEBUG};
             last if grep { $_->_SUCCES } @processed;
             print STDERR "Chorus::Expert - None of agents [" . join (',', map { $_->{_IDENT} || 'NO_NAME' } @processed) . "] have succeeded\n" if $this->{_DEBUG};
          }

          do {

            if ($agent->_REPLAY) {
              print STDERR "Chorus::Expert - REPLAYING AGENT $agent->{_IDENT} NOW.\n" if $this->{_DEBUG};
              $agent->delete('_REPLAY');
            }

            print STDERR "Chorus::Expert - LOOPING ON AGENT $agent->{_IDENT} NOW.\n" if $this->{_DEBUG};
            $agent->loop() unless $board->SOLVED or $board->FAILED;

         } while($agent->_REPLAY);

         push @processed, $agent;

          if ($agent->_REPLAY_ALL) {
            print STDERR "Chorus::Expert - WILL REPLAY ALL AGENTS NOW.\n" if $this->{_DEBUG};
            $agent->delete('_REPLAY_ALL');
            last;
          }
       }
  } until ($board->{SOLVED} or $board->{FAILED});

  ($board->delete('SOLVED'), return 1) if $board->{SOLVED};
  ($board->delete('FAILED'), return  ) if $board->{FAILED};
}

=head1 AUTHOR

Christophe Ivorra, C<< <ch.ivorra at free.fr> >>

=head1 BUGS

Please report bugs via the CPAN request tracker:
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Chorus-Engine>

=head1 SUPPORT

  perldoc Chorus::Expert

=over 4

=item * RT -- L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Chorus-Expert>

=item * AnnoCPAN -- L<http://annocpan.org/dist/Chorus-Expert>

=item * CPAN Ratings -- L<http://cpanratings.perl.org/d/Chorus-Expert>

=item * Search CPAN -- L<http://search.cpan.org/dist/Chorus-Expert/>

=back

=head1 SEE ALSO

L<Chorus::Frame>, L<Chorus::Engine>

=head1 LICENSE AND COPYRIGHT

Copyright 2013 Christophe Ivorra.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.

=cut

END { }

1; # End of Chorus::Expert
