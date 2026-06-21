#!perl -T

use strict;
use Test::More tests => 8;
use Chorus::Frame;
use Chorus::Engine;
use Chorus::Expert;

diag("Testing Chorus::Expert $Chorus::Expert::VERSION, Perl $], $^X");

# Test 1 : new() crée bien un objet Chorus::Expert
{
  my $xprt = Chorus::Expert->new();
  isa_ok($xprt, 'Chorus::Expert', 'Test 1 - new() creates a Chorus::Expert object');
  Chorus::Expert->_reset();
}

# Test 2 : register() injecte BOARD sur chaque agent
{
  my $xprt = Chorus::Expert->new();
  my $e    = Chorus::Engine->new();
  $xprt->register($e);
  ok($e->BOARD, 'Test 2 - register() sets BOARD on engine');
  Chorus::Expert->_reset();
}

# Test 3 : register() injecte EXPERT (back-ref) sur chaque agent
{
  my $xprt = Chorus::Expert->new();
  my $e    = Chorus::Engine->new();
  $xprt->register($e);
  is($e->EXPERT, $xprt, 'Test 3 - register() sets EXPERT back-ref on engine');
  Chorus::Expert->_reset();
}

# Test 4 : BOARD est le même objet pour tous les agents enregistrés
{
  my $xprt       = Chorus::Expert->new();
  my ($e1, $e2)  = (Chorus::Engine->new(), Chorus::Engine->new());
  $xprt->register($e1, $e2);
  is($e1->BOARD, $e2->BOARD, 'Test 4 - BOARD is shared between agents');
  Chorus::Expert->_reset();
}

# Test 5 : process($input) expose INPUT sur le BOARD partagé
{
  my $xprt = Chorus::Expert->new();
  my $e    = Chorus::Engine->new();
  my $seen;
  $xprt->register($e);
  $e->addrule(
    _SCOPE => { x => [1] },
    _APPLY => sub {
      $seen = $e->BOARD->INPUT;
      $e->solved();
      return 1;
    }
  );
  $xprt->process('hello');
  is($seen, 'hello', 'Test 5 - process($input) sets BOARD->INPUT');
  Chorus::Expert->_reset();
}

# Test 6 : process() retourne 1 quand un agent appelle solved()
{
  my $xprt = Chorus::Expert->new();
  my $e    = Chorus::Engine->new();
  $xprt->register($e);
  $e->addrule(
    _SCOPE => { x => [1] },
    _APPLY => sub { $e->solved(); return 1; }
  );
  my $res = $xprt->process();
  is($res, 1, 'Test 6 - process() returns 1 on SOLVED');
  Chorus::Expert->_reset();
}

# Test 7 : process() retourne undef quand un agent appelle failed()
{
  my $xprt = Chorus::Expert->new();
  my $e    = Chorus::Engine->new();
  $xprt->register($e);
  $e->addrule(
    _SCOPE => { x => [1] },
    _APPLY => sub { $e->failed(); return 1; }
  );
  my $res = $xprt->process();
  ok(!defined($res), 'Test 7 - process() returns undef on FAILED');
  Chorus::Expert->_reset();
}

# Test 8 : multi-agents — les agents sont appelés dans l'ordre d'enregistrement
{
  my $xprt      = Chorus::Expert->new();
  my ($e1, $e2) = (Chorus::Engine->new(), Chorus::Engine->new());
  my @order;
  $xprt->register($e1);
  $xprt->register($e2);
  $e1->addrule(
    _SCOPE => { x => [1] },
    _APPLY => sub { push @order, 'e1'; return; }
  );
  $e2->addrule(
    _SCOPE => { x => [1] },
    _APPLY => sub { push @order, 'e2'; $e2->solved(); return 1; }
  );
  $xprt->process();
  is_deeply(\@order, ['e1', 'e2'], 'Test 8 - agents called in registration order');
  Chorus::Expert->_reset();
}

done_testing();
