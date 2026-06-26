package TimberFrame::Agent::QualifyMaterial;

use strict;
use warnings;
use Chorus::Engine;
use Chorus::Frame;

# Business knowledge helpers — produced by chorus-feed
# Imported BEFORE loadRules() to be available in YAML ACTIONs (eval)
use TimberFrame::Agent::QualifyMaterial::Helpers qw(
    _strength_class_rank
    _min_class_rank_for_type
);

use Exporter 'import';
our @EXPORT_OK = qw($agent);

our $agent;

sub build {
    my ($class, %opts) = @_;
    my $base = $opts{base_dir} // '.';

    $agent = Chorus::Engine->new(
        _IDENT      => 'QualifyMaterial',
        _MAX_CYCLES => $opts{max_cycles} // 10_000,
    );

    # ⚠️ Inject helpers into Chorus::Engine namespace BEFORE loadRules()
    # YAML ACTIONs are eval'd inside Chorus::Engine — the helper must be
    # visible in Chorus::Engine:: at eval time.
    {
        no strict 'refs';
        *{'Chorus::Engine::_strength_class_rank'}     = \&_strength_class_rank;
        *{'Chorus::Engine::_min_class_rank_for_type'} = \&_min_class_rank_for_type;
    }

    $agent->loadRules("$base/rules/qualify-material");

    return $agent;
}

1;
