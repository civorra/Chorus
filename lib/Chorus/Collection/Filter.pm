package Chorus::Collection::Filter;

BEGIN {
  use Exporter;
  use vars qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

  @ISA         = qw(Exporter);
  @EXPORT      = qw();
  @EXPORT_OK   = qw($FILTER @_VFILTER);

  # %EXPORT_TAGS = ( );		# eg: TAG => [ qw!name1 name2! ];
}

use Chorus::Frame;
use Chorus::Collection::List qw($LIST);
use strict;

use constant DEBUG => 0;

# Methode
# -------
#
# découpage du motif en suite d'opérateurs/noeuds (frames)
#
# ^a.*?[cd]+(e+)(f{0,2}!a)$
#
# NODES ..
# N1(^) -> N2(a) -> N3(.*) -> N4([cd]+) -> N5(VAR1:e+) -> N6(VAR2:f{0,2}) -> N7(!a) -> N8($)

use constant COUNT_MAX_LIMIT => 100;

use constant ANYTHING => 1;         # ex .
use constant IS       => 2;         # ex a
use constant IS_NOT   => 3;         # ex !a

use constant EXACTLY_ONE  => 1;     # default
use constant ZERO_OR_MORE => 2;     # ex. b*
use constant ONE_OR_MORE  => 3;     # ex  b+
use constant INTERVALLE   => 4;     # ex  b{3,5} or b{3} (equiv b{3,3})

my %REGISTERED = ();                # Will store pre-compiled filters !!
our @_VFILTER  = ();                # filter matching variables array (equiv $1,$2 .. with regexp)

my $NODE_MOTIF = Chorus::Frame->new(

     _AFTER => sub {                # ex. ^a  [abc]+  (.*?) [01]{1,3}  !Z$ ...
        local $_ = shift;

        $SELF->set('head_only', 'y') if s/^\^//;
        $SELF->set('tail_only', 'y') if s/\$$//;

        s/\{(\d+),(\d+)\}// and do {
         my ($min, $max) = ($1, $2);

         $SELF->set('count_min', $min);
         $SELF->set('count_max', $max);
         $SELF->set('count_mode', INTERVALLE);
        };

        s/\{(\d+)}// and do {
         my $c = $1;
         $SELF->set('count_min', $c); my $node = new_node();
         $SELF->set('count_max', $c);
         $SELF->set('count_mode', INTERVALLE);
        };

        $SELF->set('match_mode', IS_NOT)   if s/\!//;

        $SELF->set('match_mode', ANYTHING) if s/\.//;

        ($SELF->set('count_mode', ZERO_OR_MORE), $SELF->set('count_min', 0), $SELF->set('count_max', COUNT_MAX_LIMIT)) if s/\*//;
        ($SELF->set('count_mode', ONE_OR_MORE),  $SELF->set('count_min', 1), $SELF->set('count_max', COUNT_MAX_LIMIT)) if s/\+//;

        $SELF->set('short', 'Y') if s/\?//;

        s/\[(.*?)\]/$1/;
        $SELF->set_sequence($_);
     },
);

my $NODE_FILTER = Chorus::Frame->new(

   match_mode  => { _DEFAULT => IS },
   count_mode  => { _DEFAULT => EXACTLY_ONE },
   count_min   => { _DEFAULT => 1 },
   count_max   => { _DEFAULT => 1 },

   connect_left => sub {
     my $prev = shift or return;
     $SELF->set('prev', $prev);
     my $s = $SELF;
     $prev->set('succ', $s); # DEV - what is $SELF here ???
   },

   set_sequence => sub {
       local $_ = shift;
       $SELF->set('_sequence_test', { map { $_ => 'y' } split(/\s+/) } );
   },

   reset_var => sub {
       $SELF->set('_VAR',[]);
   },

   succes => sub {
      print STDERR "\t SUCCESS !\n" if DEBUG;
      return 1;
   },

   fails => sub {
      my $mess = shift || '';
      print STDERR "\t FAILS - $mess !\n" if DEBUG;
      return;
   },

   sequence_match => sub {
      local $_ = shift;     # may be [] !!
      my $l = scalar(@$_);

      if($l == 0) {
        return 1 if $SELF->count_min == 0;
        return $SELF->fails('list empty')
      }

     # traiter le cas sequence match + list too short !!
     # ..

      # return $SELF->fails('list too short')  if $l < $SELF->count_min;
      return $SELF->fails('list too long')  if $l > $SELF->count_max;

     my @sequence = map { $SELF->_FILTER->node_test($_) } @$_;

     if ($SELF->match_mode == IS_NOT) {
        return $SELF->fails('IS_NOT : failed') if grep {
          ref($_) eq 'ARRAY' ? grep { $SELF->_sequence_test->{$_} } @$_ : $SELF->_sequence_test->{$_}
        } @sequence;
        return 1;
     }

     return $SELF->fails('CASE-1') if $SELF->match_mode != ANYTHING and grep {
          ref($_) eq 'ARRAY' ? !grep { $SELF->_sequence_test->{$_} } @$_ : !$SELF->_sequence_test->{$_}
        } @sequence;
     return 1;
   },

   match => sub {

       local $_  = shift; # the sequence to test (array ref) - may_be EMPTY !!

       print STDERR "\nDEBUG\t Node : " . $SELF->motif . "\t Testing : " . join(' ', map { $SELF->_FILTER->node_test($_) } @$_) . "\n" if DEBUG;

       if ($SELF->sequence_match($_)) { # node test : success on $_ (always an array ref)

         my $next = shift;

         if ($SELF->succ) {             # not on last node (tail_only always false)

             if ($next) {    	        # not on last item in tested sequence

                if ($SELF->short) {

                   ($SELF->set('_VAR', $_), return 1) if $SELF->succ->match([$next], @_);
                   return 1 if $SELF->match([@$_, $next], @_);
                   return $SELF->match([$next], @_) unless ($SELF->head_only); # on passe $_

                } else { # on priorise un resultat long

                   return 1 if $SELF->match([@$_, $next], @_); #  cas de head_only
                   ($SELF->set('_VAR', $_), return 1) if $SELF->succ->match([$next], @_);
                   return $SELF->match([$next], @_) unless $SELF->head_only; # on passe $_

                }

                return $SELF->fails;
             }

             # $next is undefined
             #
             if ($SELF->short) {
               if ($SELF->count_min == 0) {
                ($SELF->set('_VAR', []), return 1) if $SELF->succ->match($_);
               }

               $SELF->set('_VAR', $_);
               return $SELF->succ->match([]); # some nodes remaining on the right;
             } else {
               if ($SELF->count_min == 0) {
               ($SELF->set('_VAR', []), return 1) if $SELF->succ->match($_);
               $SELF->set('_VAR', $_); return $SELF->succ->match([]);
               } else {
               ($SELF->set('_VAR', $_), return 1) if $SELF->succ->match([]);
               return $SELF->fails;
               }
             }

         } else { # on last node

           if ($next) {
            return ($SELF->match([@$_, $next], @_) or $SELF->match([$next], @_)) if $SELF->tail_only;
            ($SELF->set('_VAR', $_), return 1) if $SELF->count_max == 1 or $SELF->short;
            ($SELF->set('_VAR', [@$_, $next]), return 1) if $SELF->match([@$_, $next], @_);
           }

           # $next is undefined
           #
           $SELF->set('_VAR', $_);
           return 1;
         }

       } else {

        # SEQUENCE DID NOT MATCH CURRENT NODE !!
        #
        # Attention l'echec pu etre du à une sequence bonne mais trop courte  Ex. count_min > 1 !!*
        # à traiter ..

       if ($SELF->succ) { # Seq failed but NOT on last node

         # Cas : short,count_min,count_max,succ,next !!
         #
         # cas : head_only, tail_only,

         if ($SELF->head_only) {
           if ($SELF->count_min == 0) {
             $SELF->set('_VAR', []);
             return $SELF->succ->match($_, @_);
           }
           return $SELF->fails;
         }
         #
         # NO HEAD ONLY

         if ($SELF->short) { # priorité a une correspondance courte
	     ($SELF->set('_VAR', []), return 1) if $SELF->count_min == 0 and $SELF->succ->match($_, @_);
	     my $next = shift;
	     return $SELF->match([$next], @_) if $next;
	     return $SELF->fails;
         } else {
	     my $next = shift;
	     return 1 if $next and $SELF->match([$next], @_);
	     ($SELF->set('_VAR', []), return 1) if $SELF->count_min == 0 and $SELF->succ->match($_, $next, @_);
	     return $SELF->fails;
         }

       } else { # last node

        my $next = shift;

        if ($next) {

          if ($SELF->short) {

          ($SELF->set('_VAR', []), return 1) if $SELF->count_min == 0;
          return $SELF->match([$next], @_) unless $SELF->head_only;
          return $SELF->fails;

           } else {

            return 1 if !$SELF->head_only and $SELF->match([$next], @_);
            ($SELF->set('_VAR', []), return 1) if $SELF->count_min == 0;
            return $SELF->fails;
           }

        } else { # next undefined
          ($SELF->set('_VAR', []), return 1) if $SELF->count_min == 0;
          return $SELF->fails;
        }

       } # last node

     }
   }
);

# --

sub new_node {
   return Chorus::Frame->new(
     _ISA  => $NODE_FILTER,
     motif => { _ISA => $NODE_MOTIF }
   );
}

# --

our $FILTER = Chorus::Frame->new(

    _ISA            => $LIST,                     # equiv $Chorus::Collection::List::LIST
    _CONTAINER_NAME => '_FILTER',

    set_filter => sub {

      local $_   = shift;                         # Ex. ^[ADV VRB]+ .* (PREP{0,1}) !ADJ*? (NOM ADJ+)$
      my $prev   = undef;

      $SELF->build();                             # init to empty

      while($_) {

        my $node = new_node();                    # init node
        s/^\s+//o;                                # ~ trim left
        my $m = s/^(\^)//o ? $1 : '';             # init node motif (set ^ filter)

        $node->set('openvar',  'Y') if s/^\(//o;

        SWITCH: {

          $m .= $1 if s/^(\!)//o;                 # negation

          s/^(\[.*?\])// and do {                 # OR operator - default is AND (~THEN)

            $m .= $1;
            $m .= $1 if s/^(\{.*?\})//o;
            $m .= $1 if s/^([*+])//o;
            $m .= '?' if s/^\?//o;

            $node->set('closevar', 'Y') if s/^\)//o;

            $m .= '$' if s/^\$$//o;

            $node->set('motif', $m);
            $node->connect_left($prev);
            $SELF->push_items($node);             # $SELF is a $Chorus::Collection::List::LIST

            last SWITCH;
          };

          $node->set('closevar', 'Y') if s/^(\S+?)\)/$1/o;

          s/^(\S+)// and do {

            $m .= $1;
            $node->set('motif', $m);
            $node->connect_left($prev);
            $SELF->push_items($node);

            last SWITCH;
          };

        } # SWITCH

        $prev = $node;
      }
    },

    set_vars => sub {
        @_VFILTER  = ();  # reset global
        my $var = undef;
        for (@{$SELF->_ITEMS}) {
          $var = [] if $_->openvar;
          push @$var, @{$_->_VAR} if $var;
          if ($_->closevar) {
            push @_VFILTER, $var;
            undef $var;
          }
        }
    },

    node_test => sub {
      _DEFAULT => sub { shift }      # par défaut : identité F(X) -> X (retourne un frame !!??)
    },

    set_node_test => sub {
      $SELF->set('node_test', shift) # custom sub()
    },


    check => sub {

      print STDERR "TESTING SEQUENCE : " . join(' ', map { $_->flexion . ':' . $SELF->node_test($_) } @_) . "\n" if DEBUG;
      print STDERR "DEBUG CHECK - Filter nodes : " .join(' ', map { $_->motif } @{$SELF->_ITEMS} ) . "\n" if DEBUG;

      $_->reset_var() for (@{$SELF->_ITEMS});             # reset nodes

      # if ($SELF->first_item->match([], @_)) {           # MUST WORK !!
      #
      if ($SELF->first_item->match([shift || ()], @_)) {  # works but not the solution
         $SELF->set_vars();                               # build global
         return 1;
      }

      @_VFILTER  = ();                                    # reset global
      return;
    }

);

END {}

1;
