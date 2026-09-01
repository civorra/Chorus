package ADA::Feed;

use strict;
use warnings;
use Chorus::Frame;
use JSON ();
use Exporter 'import';

our @EXPORT_OK = qw(load_projet);

# ─────────────────────────────────────────────────────────────────────────────
# Phase 3 — Masonry spec prototype catalog
# ─────────────────────────────────────────────────────────────────────────────
# Each spec Frame represents one (masonry_unit_type, masonry_material,
# masonry_group) combination and carries the normative threshold slots:
#
#   min_str_A / min_str_B / min_str_C
#       Minimum declared compressive strength (N/mm²) from Table 6.
#       Absent (undef) for clay/CaSi blocks (→ Table 7) and manufactured_stone.
#
#   min_norm_str_A / min_norm_str_B / min_norm_str_C
#       Minimum normalised compressive strength (N/mm²) from Table 7.
#       Only set on clay and calcium_silicate block specs.
#
#   table7_required : 1
#       Flag indicating this spec uses Table 7 instead of Table 6.
#
# Wall frames inherit from the matching spec via _ISA (set at new() time).
# Rules read thresholds via $w->get("min_str_$cond") — which traverses _ISA
# transparently.  Prototypes are safe: they never carry 'besoin_masonry', so
# no masonry YAML rule will ever pick them up via fmatch(slot=>'besoin_masonry').
#
# fselect() (Minsky frame selection) is used in load_projet() to match each
# wall frame to its prototype: highest-scoring spec wins.
# ─────────────────────────────────────────────────────────────────────────────

sub _build_masonry_catalog {
    my @specs;

    # ── Table 6 — Clay and Calcium Silicate bricks (identical thresholds) ────
    for my $mat (qw(clay calcium_silicate)) {
        push @specs, Chorus::Frame->new(
            masonry_unit_type => 'brick', masonry_material => $mat, masonry_group => 1,
            min_str_A =>  6.0, min_str_B =>  9.0, min_str_C => 18.0,
        );
        push @specs, Chorus::Frame->new(
            masonry_unit_type => 'brick', masonry_material => $mat, masonry_group => 2,
            min_str_A =>  9.0, min_str_B => 13.0, min_str_C => 25.0,
        );
    }

    # ── Table 6 — Aggregate concrete brick (same thresholds as clay Gr 1/2) ──
    push @specs, Chorus::Frame->new(
        masonry_unit_type => 'brick', masonry_material => 'aggregate_concrete', masonry_group => 1,
        min_str_A =>  6.0, min_str_B =>  9.0, min_str_C => 18.0,
    );

    # ── No numeric minimum — AAC brick and manufactured stone ─────────────────
    # min_str_* intentionally absent: R02 interprets undef as "always acceptable"
    for my $mat (qw(aac manufactured_stone)) {
        push @specs, Chorus::Frame->new(
            masonry_unit_type => 'brick', masonry_material => $mat, masonry_group => 1,
        );
    }

    # ── Table 7 — Clay and Calcium Silicate blocks (normalised strength) ─────
    for my $mat (qw(clay calcium_silicate)) {
        push @specs, Chorus::Frame->new(
            masonry_unit_type => 'block', masonry_material => $mat, masonry_group => 1,
            table7_required => 1,
            min_norm_str_A =>  5.0, min_norm_str_B =>  7.5, min_norm_str_C => 15.0,
        );
        push @specs, Chorus::Frame->new(
            masonry_unit_type => 'block', masonry_material => $mat, masonry_group => 2,
            table7_required => 1,
            min_norm_str_A =>  8.0, min_norm_str_B => 11.0, min_norm_str_C => 21.0,
        );
    }

    # ── Table 6 — Aggregate concrete and AAC blocks ───────────────────────────
    for my $mat (qw(aggregate_concrete aac)) {
        for my $grp (1, 2) {
            push @specs, Chorus::Frame->new(
                masonry_unit_type => 'block', masonry_material => $mat, masonry_group => $grp,
                min_str_A => 2.9, min_str_B => 7.3, min_str_C => 7.3,
            );
        }
    }

    return @specs;
}

# ─────────────────────────────────────────────────────────────────────────────
# Mandatory slots per element type — extracted from KB Catalogue des Frames
# ─────────────────────────────────────────────────────────────────────────────
# Building types → processed by ADA::Agent::Geometry (targeting: type_element)
# Wall types      → processed by ADA::Agent::Wall (targeting: besoin_wall)
#                   besoin_wall is pre-populated here for wall Frames (the
#                   Geometry agent only sets it for building Frames; wall Frames
#                   receive it directly from the Feed — they are always in scope).
# Foundation slots (soil_type, wall_load_kn_m, etc.) only required on
# external_wall Frames that reach Agent::Foundation — we do not validate them
# here as they are downstream-optional (foundation check is conditional on
# masonry completing). The agent's CONDITION guards handle missing values safely.
# ─────────────────────────────────────────────────────────────────────────────
my %SLOTS_REQUIS = (
    # ── Building types ───────────────────────────────────────────────────────
    'residential_building' => [qw(
        id type_element height_m width_w1_m num_storeys floor_area_m2
    )],
    'non_residential_building' => [qw(
        id type_element height_m width_m
    )],
    'annexe' => [qw(
        id type_element height_m
    )],
    # ── Chimney type ─────────────────────────────────────────────────────────
    'masonry_chimney' => [qw(
        id type_element chimney_height_m chimney_least_width_m
    )],
    # ── Wall types ───────────────────────────────────────────────────────────
    # Phase 2: num_storeys_building is now read via the optional 'building_ref'
    # inter-frame link → slot 'building' on the Frame.
    # masonry/R01 and wall/R03 use the link when present, fall back to the direct
    # slot otherwise (backward-compatible with project files that don't have building_ref).
    'external_wall' => [qw(
        id type_element wall_type thickness_mm height_m length_m
    )],
    'internal_wall' => [qw(
        id type_element thickness_mm storey_height_m
    )],
    'parapet_wall' => [qw(
        id type_element parapet_type thickness_mm height_m
    )],
    # Phase 1: height_m and buttressing_thickness_mm are resolved via the optional
    # 'supports_ref' inter-frame link → slot 'supports' on the Frame.
    # R05/R08 use the link when present, fall back to direct slots otherwise
    # (backward-compatible with project files without supports_ref).
    'buttressing_wall' => [qw(
        id type_element buttressing_length_m
    )],
);

# Wall-type elements that receive besoin_wall pre-populated by the Feed.
# (Building-type elements receive it from ADA::Agent::Geometry R01/R02/R03.)
my %WALL_TYPES = map { $_ => 1 }
    qw(external_wall internal_wall parapet_wall buttressing_wall);

sub load_projet {
    my ($fichier) = @_;

    open my $fh, '<', $fichier
        or die "Cannot open $fichier: $!\n";
    my $json = do { local $/; <$fh> };
    close $fh;

    my $data     = JSON->new->utf8->decode($json);
    my @elements = @{ $data->{elements} };

    # ── Validation pass — check types and required slots ─────────────────────
    for my $elem (@elements) {
        my $id   = $elem->{id}           // die "Element without 'id'\n";
        my $type = $elem->{type_element} // $elem->{type}
            or die "Element '$id' without 'type_element'\n";

        # Normalise: if 'type' was used instead of 'type_element', fix it
        $elem->{type_element} //= delete $elem->{type} if defined $elem->{type};

        my $requis = $SLOTS_REQUIS{$type};
        unless ($requis) {
            warn "Type '$type' (element '$id') out-of-scope for ADA sandbox — skipped\n";
            next;
        }

        for my $slot (@$requis) {
            die "Required slot '$slot' missing for '$id' (type: $type)\n"
                unless defined $elem->{$slot};
        }
    }

    # ── Phase 3 — build the masonry spec prototype catalog ───────────────────
    # Created here (inside load_projet) so that Chorus::Frame::_reset() between
    # test runs does not leave stale frame references in the catalog.
    my @masonry_catalog = _build_masonry_catalog();

    # ── Inter-frame reference fields ──────────────────────────────────────────
    # Maps JSON '*_ref' field names to the Frame slot name that receives the
    # resolved Frame object.  Add new entries here to support additional links.
    # Rules read the resolved slot via $frame->get('slot_name').
    my %REF_FIELDS = (
        supports_ref => 'supports',   # Phase 1: buttressing_wall → external_wall
        building_ref => 'building',   # Phase 2: wall → building Frame
    );

    # ── _inject_masonry_spec — shared by both passes ──────────────────────────
    # Phase 3: fselect() matches (masonry_unit_type, masonry_material, masonry_group)
    # against the catalog and injects the winning spec as _ISA in %slots before
    # Chorus::Frame->new() is called.  This must run in both passes so that
    # elements without any *_ref field (pass 1) also inherit normative thresholds.
    my $inject_masonry = sub {
        my ($slots) = @_;
        return unless defined $slots->{masonry_unit_type};
        my $spec = fselect(
            masonry_unit_type => $slots->{masonry_unit_type},
            masonry_material  => $slots->{masonry_material}  // '',
            masonry_group     => $slots->{masonry_group}     // 1,
            _from             => \@masonry_catalog,
        );
        return unless defined $spec;
        $slots->{_ISA} = defined($slots->{_ISA})
            ? [ ref($slots->{_ISA}) eq 'ARRAY' ? @{$slots->{_ISA}} : $slots->{_ISA}, $spec ]
            : $spec;
    };

    # ── Pass 1 — create all frames that have no inter-frame references ────────
    # Frames with any *_ref field are deferred to pass 2 so that their target
    # frame already exists when the Frame reference is passed to new().
    # Passing the reference at new() time avoids setting _PARENT_KEY on the
    # target frame (which would happen via set() after the fact).
    my (%frames_by_id, @frames_pass1, @deferred);

    for my $elem (@elements) {
        my $type = $elem->{type_element} or next;
        next unless $SLOTS_REQUIS{$type};   # skip out-of-scope types

        my $has_ref = grep { defined $elem->{$_} } keys %REF_FIELDS;
        if ($has_ref) {
            push @deferred, $elem;
        } else {
            my %slots = %$elem;
            $inject_masonry->(\%slots);                    # Phase 3 — _ISA injection
            my $frame = Chorus::Frame->new(%slots);
            if ($WALL_TYPES{$type}) {
                $frame->set('besoin_wall', 'Y');
            }
            $frames_by_id{ $elem->{id} } = $frame;
            push @frames_pass1, $frame;
        }
    }

    # ── Pass 2 — create frames with inter-frame references ────────────────────
    # Each *_ref field is resolved to the target Frame object and passed to new()
    # under the slot name defined in %REF_FIELDS.  The *_ref keys are stripped
    # so they do not become domain slots on the Frame.
    my @frames_pass2;

    for my $elem (@deferred) {
        my $id   = $elem->{id};
        my $type = $elem->{type_element};

        my %slots = %$elem;

        for my $ref_field (keys %REF_FIELDS) {
            my $slot_name = $REF_FIELDS{$ref_field};
            my $ref_id    = delete $slots{$ref_field} // next;  # skip if absent

            my $target = $frames_by_id{$ref_id}
                or die "Element '$id': $ref_field '$ref_id' not found "
                     . "(check id spelling or element order in JSON)\n";

            $slots{$slot_name} = $target;   # Frame ref at new() — no _PARENT_KEY side-effect
        }

        $inject_masonry->(\%slots);                        # Phase 3 — _ISA injection

        my $frame = Chorus::Frame->new(%slots);
        if ($WALL_TYPES{$type}) {
            $frame->set('besoin_wall', 'Y');
        }
        $frames_by_id{$id} = $frame;
        push @frames_pass2, $frame;
    }

    return (@frames_pass1, @frames_pass2);
}

1;
