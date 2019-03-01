#!/usr/bin/env perl

use Try::Tiny;

use Integrations::Alloy::Northamptonshire;
use feature qw/say/;

my $i = Integrations::Alloy::Northamptonshire->new();

for my $defect_type ( keys %{ $i->config->{defect_sourcetype_category_mapping} } ) {
    my $defect_source;

    try {
        $defect_source = $i->api_call("source-type/$defect_type");
    } catch {
        say "failed to get source type $defect_type";
        divider();
        next;
    };

    say "$defect_type (" . $defect_source->{keyPropertyValueCode} . ')';
    say '=' x 10;

    my $type_att;
    for my $att ( @{ $defect_source->{attributes} } ) {
        if ( $att->{code} =~ /DEFECT_TYPE/ ) {
            $type_att = $att;
            last;
        }
    }

    unless ( $type_att ) {
        say "no defect types for this defect";
        divider();
        next;
    }

    say "attribute id is " . $type_att->{attributeId};

    my $graph_rel_id = $type_att->{parentGraphRelationshipConfigId};

    my $rel = $i->api_call("graph-config-relationship/$graph_rel_id");

    my $child_type_id = $rel->{childSourceTypeId};

    my $child_type = $i->api_call("source?sourceTypeId=$child_type_id");

    my $child_source = $child_type->{sources}->[0]->{sourceId};

    my $types = $i->api_call("resource?sourceId=$child_source");

    for my $res ( @{ $types->{resources} } ) {
        my $id = $res->{resourceId};
        my $desc = $res->{title};

        say "$desc: $id";
    }

    divider();
}

sub divider {
    say;
    say '-' x 80;
    say
}
