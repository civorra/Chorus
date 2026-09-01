package ADA::Agent::Robustness::Helpers;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(consequence_class_table11);

# -------------------------------------------------------
# consequence_class_table11
# Source corpus: §5.1, Table 11 — UK Approved Document A 2013 (p.44)
# -------------------------------------------------------
# Signature: consequence_class_table11($use, $storeys, $floor_area_m2) → ($cc, $note)
# Returns: consequence class string ('CC1'|'CC2a'|'CC2b'|'CC3') and description.
#
# $use           : building use category (see Aliases in robustness.org)
# $storeys       : total number of storeys (basements excluded per Table 11 Note 2)
# $floor_area_m2 : max floor area per storey (m²) — relevant for retail/public
sub consequence_class_table11 {
    my ($use, $storeys, $floor_area_m2) = @_;
    $storeys       //= 1;
    $floor_area_m2 //= 0;

    # Houses (single occupancy residential)
    if ($use eq 'house') {
        return ('CC1',  'No additional measures required')        if $storeys <= 4;
        return ('CC2a', 'Effective horizontal ties required')     if $storeys == 5;
        return ('CC2b', 'Horizontal + vertical ties, or key element design, or notional removal check');
    }

    # Hotels, flats/apartments, other residential (non-house)
    if ($use =~ /^(hotel|flat|apartment|residential)$/) {
        return ('CC2a', 'Effective horizontal ties required')                   if $storeys <= 4;
        return ('CC2b', 'Horizontal + vertical ties or notional removal check') if $storeys <= 15;
        return ('CC3',  'Systematic risk assessment required — exceeds 15 storeys');
    }

    # Offices
    if ($use eq 'office') {
        return ('CC2a', 'Effective horizontal ties required')                   if $storeys <= 4;
        return ('CC2b', 'Horizontal + vertical ties or notional removal check') if $storeys <= 15;
        return ('CC3',  'Systematic risk assessment required — exceeds 15 storeys');
    }

    # Industrial
    if ($use eq 'industrial') {
        return ('CC2a', 'Effective horizontal ties required')       if $storeys <= 3;
        return ('CC3',  'Systematic risk assessment required — industrial > 3 storeys');
    }

    # Retail / retailing
    if ($use eq 'retail') {
        if ($storeys <= 3 && $floor_area_m2 < 2000) {
            return ('CC2a', 'Effective horizontal ties required');
        } elsif ($storeys <= 15 || ($storeys <= 15 && $floor_area_m2 < 5000)) {
            return ('CC2b', 'Horizontal + vertical ties or notional removal check');
        }
        return ('CC3', 'Systematic risk assessment required — exceeds limits');
    }

    # Educational (schools, colleges)
    if ($use =~ /^(school|educational)$/) {
        return ('CC2a', 'Effective horizontal ties required — single storey school') if $storeys == 1;
        return ('CC2b', 'Horizontal + vertical ties or notional removal check')      if $storeys <= 15;
        return ('CC3',  'Systematic risk assessment required — exceeds 15 storeys');
    }

    # Hospitals
    if ($use eq 'hospital') {
        return ('CC2b', 'Horizontal + vertical ties or notional removal check') if $storeys <= 3;
        return ('CC3',  'Systematic risk assessment required — hospital > 3 storeys');
    }

    # Public (members of public admitted)
    if ($use eq 'public') {
        return ('CC2a', 'Effective horizontal ties required')
            if $storeys <= 2 && $floor_area_m2 <= 2000;
        return ('CC2b', 'Horizontal + vertical ties or notional removal check')
            if $floor_area_m2 <= 5000;
        return ('CC3', 'Systematic risk assessment required — exceeds limits');
    }

    # Agricultural, rarely occupied → CC1
    if ($use =~ /^(agricultural|rarely_occupied)$/) {
        return ('CC1', 'No additional measures required');
    }

    # Car parks
    if ($use eq 'car_park') {
        return ('CC2b', 'Horizontal + vertical ties or notional removal check') if $storeys <= 6;
        return ('CC3',  'Systematic risk assessment required — car park > 6 storeys');
    }

    # Grandstands (> 5000 spectators always CC3; feed must pre-qualify)
    if ($use eq 'grandstand') {
        return ('CC3', 'Systematic risk assessment required — grandstand');
    }

    # Hazardous / unknown
    if ($use eq 'hazardous') {
        return ('CC3', 'Systematic risk assessment required — hazardous processes');
    }

    # Default fallback (unrecognised use → conservative CC2b)
    return ('CC2b', "Unrecognised building_use '$use' — conservative CC2b applied; verify manually");
}

1;
