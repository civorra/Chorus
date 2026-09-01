package ADA::Agent::Geometry::Helpers;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(
    max_height_from_table_c
);

# -------------------------------------------------------
# max_height_from_table_c
# Source corpus: Diagram 7, Table c (p.23) — Maximum allowable building height (metres)
# -------------------------------------------------------
# Signature: max_height_from_table_c($factor_s, $site_type, $coast_distance_km)
#            → $height_m | undef
#
# Returns the maximum allowable building height in metres from Table c of
# Diagram 7, given:
#   $factor_s         — wind Factor S (S = V × O × A), integer or float 25–44
#   $site_type        — 'country' or 'town'
#   $coast_distance_km — distance to coast in km (determines band: <2 / 2–20 / >50)
#
# Returns undef when:
#   - $factor_s is not provided (undef)
#   - $site_type is not provided (undef)
#   - The cell in Table c is empty for that (Factor S, site_type, coast_band) combination
#     (meaning the site is outside the scope of this guidance for that exposure)
#
# ⚠ CORRECTION: Factor S=34, country >50km = 8.5m
#   The PDF source printed "87.5" — this is a known defect in the source document.
#   Corrected value documented in corpus/004-uk-approved-doc-a-2013-vision.md
#   and in agent/chorus/geometry.org.
#
# Note (i) from Table c: sites in town < 300m from the edge of the town should
# be assumed to be in country terrain. This must be handled at feed time.
#
# Called by: R01-residential-geometry, R02-non-residential-geometry, R03-annexe-geometry
sub max_height_from_table_c {
    my ($factor_s, $site_type, $coast_km) = @_;

    # Cannot compute without Factor S and site type
    return undef unless defined $factor_s && defined $site_type;

    # Determine coast band
    my $coast_band;
    if (defined $coast_km) {
        if    ($coast_km <  2)  { $coast_band = 'lt2'    }
        elsif ($coast_km <= 20) { $coast_band = '2to20'  }
        else                    { $coast_band = 'gt50'   }
    } else {
        # No coast distance provided — use most favourable band (gt50)
        $coast_band = 'gt50';
    }

    # Table c — Maximum allowable building height (metres)
    # Source corpus: Diagram 7, Table c (p.23)
    # Index: factor_s - 25  (S=25 → index 0, S=44 → index 19)
    # Empty cells → undef (outside guidance scope)
    #
    # ⚠ Correction: S=34, country gt50 = 8.5 (PDF source defect: was "87.5")
    my %TABLE_C = (
        country => {
            lt2   => [15,   11.5,  8,    5.5,  4,    3,    undef, undef, undef, undef,
                      undef, undef, undef, undef, undef, undef, undef, undef, undef, undef],
            '2to20' => [15, 13.5, 11,   8,    6.5,  5,    4,    3.5,  3,    undef,
                      undef, undef, undef, undef, undef, undef, undef, undef, undef, undef],
            gt50  => [15,   15,   14.5, 11,   8.5,  6.5,  5.5,  4.5,  3.5,  3,
                      undef, undef, undef, undef, undef, undef, undef, undef, undef, undef],
        },
        town => {
            lt2   => [15,   15,   15,   15,   12.5, 10,   8.5,  7,    6,    5.5,
                      4.5,  4,    3.5,  3,    undef, undef, undef, undef, undef, undef],
            '2to20' => [15, 15,   15,   15,   15,   12.5, 11,   9.5,  8,    7,
                      6.5,  5.5,  5,    4.5,  4,    3.5,  3,    undef, undef, undef],
            gt50  => [15,   15,   15,   15,   15,   15,   13.5, 11.5, 10,   8.5,
                      7.5,  6.5,  6,    5.5,  5,    4.5,  4,    3.5,  3.5,  3],
        },
    );

    # Normalise site_type
    $site_type = lc($site_type // '');
    return undef unless exists $TABLE_C{$site_type};
    return undef unless exists $TABLE_C{$site_type}{$coast_band};

    # Round Factor S to nearest integer; clamp to 25–44 range
    my $s_int = int($factor_s + 0.5);
    return 15    if $s_int < 25;   # below minimum → 15m applies (Table c ≤25 row)
    return undef if $s_int > 44;   # above maximum → outside guidance scope

    my $idx = $s_int - 25;
    return $TABLE_C{$site_type}{$coast_band}[$idx];
}

1;
