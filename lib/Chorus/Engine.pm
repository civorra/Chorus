package Chorus::Engine;

use 5.006;
use strict;
use warnings;

our $VERSION = '1.05';

use Chorus::Frame;
use Chorus::Collection::Filter qw(@_VFILTER);
use YAML qw(LoadFile);

=head1 NAME

Chorus::Engine - A lightweight inference engine for rule-based reasoning over frames.

=head1 VERSION

Version 1.05

=head1 DESCRIPTION

C<Chorus::Engine> makes it easy to write rule-based systems in Perl.  Rules declare
their own working scope (C<_SCOPE>), so the engine only generates combinations that
are relevant to each rule rather than iterating over all objects.

An engine instance is itself a L<Chorus::Frame>.  All methods (C<loop>, C<addrule>,
C<solved>...) are slots on a shared prototype frame, accessible through inheritance.

The engine integrates naturally with L<Chorus::Frame>: use C<fmatch()> inside C<_SCOPE>
closures to target only frames that provide the slots your rule needs.

Optional YAML rule files can be loaded with C<loadRules()>; see L</YAML DSL> below.

=head1 SYNOPSIS

    use Chorus::Engine;

    my $agent = Chorus::Engine->new();

    $agent->addrule(

      _SCOPE => {
          a => sub { [ fmatch(slot => 'color') ] },   # dynamic -- re-evaluated each cycle
          b => [1, 2, 3],                              # static array_ref
      },

      _APPLY => sub {
          my %opts = @_;   # $opts{a} and $opts{b} hold one combination of _SCOPE values

          return unless $opts{a}->color eq 'blue';  # guard: rule does not apply
          $opts{a}->set('tagged', 'y');
          return 1;   # rule fired (something changed)
      },
    );

    $agent->loop();

=head1 METHODS

=head2 new

Creates a new engine instance.  The instance is a C<Chorus::Frame> that inherits
from the internal C<$ENGINE> prototype.

  my $agent = Chorus::Engine->new();
  my $agent = Chorus::Engine->new(_IDENT => 'MyAgent');   # named agent (used in debug output)

=head2 addrule

Adds a rule to the engine.

  $agent->addrule(
      _ID    => 'rule-name',    # optional -- used for deduplication; duplicates are skipped
      _SCOPE => {
          x => sub { [ fmatch(slot => 'slot_name') ] },   # dynamic scope
          y => \@static_list,                              # static scope
      },
      _APPLY => sub {
          my %opts = @_;
          return unless <condition>;   # rule does not apply
          # ... effects ...
          return 1;   # rule fired
      },
  );

Additional optional slots on the rule frame:

  _TERMINAL   'solved' or 'failed' -- auto-terminates the engine when the rule fires.
  _PREMISSES  Hashref of slot names used as metadata for reorder().

The C<_APPLY> sub receives one combination of C<_SCOPE> values as a hash.  It should
return a true value when it has made a change, or false/undef when it has not.

B<Important> -- rules with the same C<_ID> in the same agent are deduplicated: the
second definition is silently ignored.

=head2 loop

Enters the inference loop.  Calls C<applyrules()> repeatedly until no rule fires in
a full pass, or until the shared BOARD signals C<SOLVED> or C<FAILED>, or until
C<_MAX_CYCLES> (default: 10,000) is reached.

  $agent->loop();

=head2 applyrules

Runs one pass over all rules.  For each rule, evaluates C<_SCOPE> to get candidate
arrays, generates all combinations, and calls C<_APPLY> for each.  Returns a true
value if at least one rule fired.

This method is called internally by C<loop()>; you rarely need to call it directly.

=head2 cut

Exits the scope-combination loops of the current rule and moves to the next rule in
the same agent.

  $agent->cut();    # inside _APPLY

=head2 last

Exits the rule loop for the current agent and moves to the next agent.
Implies C<cut()>.

  $agent->last();   # inside _APPLY

=head2 replay

Restarts the current agent from its first rule.  Implies C<cut()>.

  $agent->replay();   # inside _APPLY

=head2 replay_all

Restarts the whole pipeline from the first agent (propagates up to
C<Chorus::Expert::process()>).  Implies C<cut()>.

  $agent->replay_all();   # inside _APPLY

=head2 solved

Signals successful termination.  Sets C<< BOARD->{SOLVED} >>, which stops all loops.

  $agent->solved();   # inside _APPLY

=head2 failed

Signals failed termination.  Sets C<< BOARD->{FAILED} >>, which stops all loops.

  $agent->failed();   # inside _APPLY

=head2 reorder

Re-sorts the rule list using a comparator function, then calls C<replay()>.
Useful for dynamically prioritising rules after a domain event.

  sub by_interest {
      my ($r1, $r2) = @_;
      return 1  if $r1->{_PREMISSES}{CAT_NOUN};
      return -1 if $r2->{_PREMISSES}{CAT_NOUN};
      return 0;
  }
  $agent->reorder(\&by_interest);

=head2 pause

Disables the engine until C<wakeup()> is called.  While paused, C<loop()> has no
effect.  Use this to skip agents that have nothing to do in the current context.

  $agent->pause();

=head2 wakeup

Re-enables a paused engine.

  $agent->wakeup();

=head2 loadRules

Loads all C<*.yml> files from a directory in alphabetical order, compiles each one
to a Perl C<addrule()> call, and evaluates it.

  $agent->loadRules('/path/to/rules/dir');
  $agent->loadRules('/path/to/rules/dir', debug => ['rule-name']);

Files are loaded sorted alphabetically; prefix filenames with C<R01->, C<R02->... to
control order.  Multiple calls accumulate rules.

Compilation errors are printed to STDERR with the generated code for inspection.

=head1 YAML DSL

Rules can be written in YAML instead of Perl.  Each file defines one rule:

  REGLE:     rule-name          # mandatory -- becomes _ID
  TERMINAL:  solved             # optional  -- 'solved' or 'failed'
  PREMISSES:                    # optional  -- metadata for reorder()
    - slot-name
  CHERCHER:                     # mandatory -- defines _SCOPE
    var:
      attribut: slot-name       # fmatch(slot => 'slot-name')
      filtre: '$_->score > 0'   # optional grep filter applied before _APPLY
  CONDITION: '$var->ok'         # optional -- return unless CONDITION
  EXCEPTION: 'defined $var->r'  # optional -- return if EXCEPTION
  EFFET: |                      # mandatory -- body of _APPLY (must return true when fired)
    $var->set('result', 42);
    1

B<Important> -- the last instruction of C<EFFET> must return a true value when the
rule has made a change.  If a conditional block may leave nothing modified, return
C<0> rather than C<1>:

  EFFET: |
    if ($var->score > 5) { $var->set('flag', 'KO'); return 1 }
    0

The C<codeEffect>, C<codeCondition>, C<codeException> and C<codeTest> slots on the
engine frame are called during compilation and default to the identity function.
Override them on a per-agent basis to implement a custom DSL on top of the YAML keys.

=head1 AUTHOR

Christophe Ivorra, C<< <ch.ivorra at free.fr> >>

=head1 BUGS

Please report bugs via the CPAN request tracker:
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Chorus-Engine>

=head1 SUPPORT

  perldoc Chorus::Engine

=over 4

=item * RT -- L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Chorus-Engine>

=item * AnnoCPAN -- L<http://annocpan.org/dist/Chorus-Engine>

=item * CPAN Ratings -- L<http://cpanratings.perl.org/d/Chorus-Engine>

=item * Search CPAN -- L<http://search.cpan.org/dist/Chorus-Engine/>

=back

=head1 SEE ALSO

L<Chorus::Frame>, L<Chorus::Expert>

=head1 LICENSE AND COPYRIGHT

Copyright 2013 Christophe Ivorra.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.

=cut

sub reorderRules {
    my ($funcall) = shift;
    return unless $funcall;
    $SELF->{_RULES} = [ sort { &{$funcall}($a,$b) } @{$SELF->{_RULES}} ];
    $SELF->replay;
}

# --

sub unchanged {
    return shift;
}



sub readRule {
  my (%opt) = @_;
  my $res;

     $opt{file} or do { warn "option file missing";        return };
  -f $opt{file} or do { warn "File not found : $opt{file}"; return };

  eval { $res = LoadFile($opt{file}) }; # load YAML

  (warn $@, return) if $@;

  return $res;

}

sub codeRule {
    my ($engine, $rule, %opts) = @_;    # internal struct from YAML

    return unless defined $rule;

    my $res = '';

    my $rulename  = $rule->{REGLE}     || '';
    my $premisses = $rule->{PREMISSES} || [];
    my $scp       = $rule->{CHERCHER};
    my $terminal  = $rule->{TERMINAL}  || '';

    $res .= "\n  _ID        => '$rulename',\n";
    $res .= "  _TERMINAL  => '$terminal',\n" if $terminal;
    $res .= ( "  _PREMISSES => {\n    " . join( ",\n    ", map {"$_ => 'Y'"} @$premisses ) . "\n  },\n" ) if scalar(@$premisses);
    $res .= "  _SCOPE => {\n    ";
    $res .= join( ",\n    ", map { "$_ => sub { [ " . $engine->setScope( $scp->{$_} ) . ' ] }' } keys( %{$scp} ) );
    $res .= "\n  },\n\n";

    my $scope_mapping = join( ";\n", map {"my \$$_ = \$opts{$_}"} keys( %{$scp} ) );
    my $exception     = $rule->{EXCEPTION} ? ( '   return if ' . $engine->setException( $rule->{EXCEPTION} ) . ';' ) : '# none';
    my $condition     = $engine->setCondition( $rule->{CONDITION} );
    my $guard         = $condition ? "return unless $condition;" : '# no condition';
    my $effect        = $engine->setEffect( $rule->{EFFET} );

    $res .= <<EOT;

  _APPLY => sub {
    my (%opts) = \@_;
    $scope_mapping;

    $guard

    # Exceptions
    #
    $exception

    # Effects - last instructions SHOULD return TRUE (if something happened) !!
    #
    $effect;
  }
EOT

    if ( $opts{debug}->{$rulename} ) {
        print "Rule : $rulename ->\n";
        print "$res\n";
        print( '-' x 20 . "\n" );
    }

  return $res;
}

sub loadRules {
    my ( $dir, %opts ) = @_;

    opendir( my $dh, $dir ) || do {
        warn "Can't opendir $dir: $!";
        return;
    };

    my @ruleFiles = grep { /\.yml$/i && -f "$dir/$_" } readdir($dh);
    closedir $dh;

    for ( sort @ruleFiles ) {

        my $debug = $opts{debug} || 'NONE';
        $debug = [ $debug ] unless ref($debug) eq 'ARRAY';
	$debug = { map { $_ => 'Y' } @$debug };
 
        my $code = '$SELF->addrule(' . codeRule( $SELF, readRule( file => "$dir/$_" ), debug => $debug ) . ');';

        eval $code;

        if ($@) {
            print STDERR "error with rule $_ : $@";
            print STDERR "code was :\n$code\n";
        }

    }

    return $SELF;
}

sub applyrules {

  my $apply_rec;
  $apply_rec = sub {
    my ($rule, $stillworking) = @_;
    my (%opt, $res);

    return $stillworking unless $rule;

    my %scope = map {
         my $s = $rule->get("_SCOPE $_");
         $_ => ref($s) eq 'ARRAY' ? $s : [$s || ()]
       } grep { $_ ne '_KEY'} keys(%{$rule->{_SCOPE}});

    my $i    = 0;
    my $head = 'JUMP: {' . join('', map { $i++; 'foreach my $k' . $i . ' (@{$scope{' . $_ . '}}) {$opt{' . $_ . '}=$k' . $i . ';' } keys(%scope));
    my $body = '$res = $rule->_APPLY(%opt); if ($res && $rule->{_TERMINAL}) { $SELF->solved() if $rule->{_TERMINAL} eq "solved"; $SELF->failed() if $rule->{_TERMINAL} eq "failed"; } last JUMP if $SELF->{_LAST} or $SELF->{_CUT} or $SELF->{_REPLAY} or $SELF->{_REPLAY_ALL} or do { my $_b=$SELF->get(\'BOARD\'); $_b && ($_b->{SOLVED} || $_b->{FAILED}) }';
    my $tail = '}' x scalar(keys(%scope)) . '}';

    eval $head . $body . $tail;
    warn $@ if $@;

    $stillworking ||= $res;

    delete $SELF->{_CUT}  if $SELF->{_CUT};
    { my $_b = $SELF->get('BOARD'); $SELF->{_QUEUE} = [] if $SELF->{_LAST} or $SELF->{_REPLAY} or $SELF->{_REPLAY_ALL} or ($_b && ($_b->{SOLVED} || $_b->{FAILED})); }
    delete $SELF->{_LAST} if $SELF->{_LAST};

    return if $SELF->{_REPLAY} or $SELF->{_REPLAY_ALL};

    $SELF->{_SUCCES} ||= $stillworking;

    return $stillworking unless $SELF->{_QUEUE}->[0];
    return $apply_rec->(shift @{$SELF->{_QUEUE}}, $stillworking);
  };

  return if $SELF->{_SLEEPING};
  $SELF->{_QUEUE} = [ @{$SELF->{_RULES} || [] } ];
  return $apply_rec->(shift @{$SELF->{_QUEUE}});
}

# --

my $ENGINE = Chorus::Frame->new(

  cut         => sub { $SELF->{_CUT}        = 'Y' }, # returns true
  last        => sub { $SELF->{_LAST}       = 'Y' }, # returns true
  replay      => sub { $SELF->{_REPLAY}     = 'Y' }, # (returned value ignored)
  replay_all  => sub { $SELF->{_REPLAY_ALL} = 'Y' }, # (returned value ignored)

  loop    => sub {
    $SELF->{_SUCCES} = 0;
    my $max = $SELF->get('_MAX_CYCLES') // 10_000;
    my $cycles = 0;
    while ( applyrules() ) {
      my $b = $SELF->get('BOARD');
      last if $b and ($b->{SOLVED} or $b->{FAILED});
      if (++$cycles >= $max) {
        warn "Chorus::Engine - loop() reached max cycles ($max) without convergence\n";
        last;
      }
    }
  },

  solved  => sub { $SELF->BOARD->{SOLVED} = 'Y'; return },
  failed  => sub { $SELF->BOARD->{FAILED} = 'Y'; return },

  pause   => sub { $SELF->{_SLEEPING} = 'Y' },
  wakeup  => sub { $SELF->delete('_SLEEPING')},

  addrule => sub {
    my @rule_def = @_;
    my %args = @rule_def;
    if (my $id = $args{_ID}) {
      if (grep { $_->{_ID} && $_->{_ID} eq $id } @{$SELF->{_RULES}}) {
        warn "Chorus::Engine - addrule: duplicate rule _ID '$id' — skipped\n";
        return;
      }
    }
    push @{$SELF->{_RULES}}, Chorus::Frame->new(@rule_def);
  },

  reorder => \&reorderRules,

  setFilter => sub {
    my ($f) = @_;
    return '' unless $f;
    $f = [ $f ] unless ref($f) eq 'ARRAY';
    return 'grep { ' . join(' and ', map { $SELF->codeTest($_) } @$f) . ' }'; # ET implicite
  },

  setScope => sub {
    my ($desc) = @_;
    return $SELF->setFilter($desc->{filtre}) . " fmatch(slot => '" . $desc->{attribut} . "')";
  },

  setCondition => sub {
    my ($c) = @_;
    return '' unless $c;
    $c = [ $c ] unless ref($c) eq 'ARRAY';
    return join("\n      or ", map { $SELF->codeCondition($_) } @$c); # OU implicite
  },

  setException => sub {
    my ($c) = @_;
    return '' unless $c;
    $c = [ $c ] unless ref($c) eq 'ARRAY';
    return join("\n      or ", map { $SELF->codeException($_) } @$c); # OU implicite
  },

  setEffect => sub {
    my ($ef) = @_;
    return '' unless $ef;
    $ef = [ $ef ] unless ref($ef) eq 'ARRAY';
    return join(";\n    ", map { $SELF->codeEffect($_) } @$ef); # ET séquentiel
  },

  codeEffect    => { _DEFAULT => \&unchanged }, # default (no change) unless provided by agents !
  codeCondition => { _DEFAULT => \&unchanged },
  codeException => { _DEFAULT => \&unchanged },
  codeTest      => { _DEFAULT => \&unchanged },

  loadRules => \&loadRules,
);

sub new {
    shift;                                            # get rid of clasical bless $class here !!
    my $res = Chorus::Frame->new( _RULES => [], @_ ); # may already contains _ISA !
    $res->_inherits($ENGINE);                         # -> possible multiple inheritance !!
    return $res;
}

=head1 AUTHOR

Christophe Ivorra, C<< <ch.ivorra at free.fr> >>

=head1 BUGS

Please report bugs via the CPAN request tracker:
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Chorus-Engine>

=head1 SUPPORT

  perldoc Chorus::Engine

=over 4

=item * RT -- L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Chorus-Engine>

=item * AnnoCPAN -- L<http://annocpan.org/dist/Chorus-Engine>

=item * CPAN Ratings -- L<http://cpanratings.perl.org/d/Chorus-Engine>

=item * Search CPAN -- L<http://search.cpan.org/dist/Chorus-Engine/>

=back

=head1 SEE ALSO

L<Chorus::Frame>, L<Chorus::Expert>

=head1 LICENSE AND COPYRIGHT

Copyright 2013 Christophe Ivorra.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See L<http://dev.perl.org/licenses/> for more information.

=cut

1; # End of Chorus::Engine
