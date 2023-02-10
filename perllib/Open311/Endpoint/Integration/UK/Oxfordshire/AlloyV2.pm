=head1 NAME

Open311::Endpoint::Integration::UK::Oxfordshire::AlloyV2 - Oxfordshire-specific parts of its Alloy integration

=head1 DESCRIPTION

=cut

package Open311::Endpoint::Integration::UK::Oxfordshire::AlloyV2;

use Moo;
extends 'Open311::Endpoint::Integration::AlloyV2';

use Open311::Endpoint::Service::UKCouncil::Alloy::Oxfordshire;

has service_class  => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::UKCouncil::Alloy::Oxfordshire'
);

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'oxfordshire_alloy_v2';
    return $class->$orig(%args);
};

sub service_request_content {
    '/open311/service_request_extended'
}

=head2 process_attributes

This calls the default function, but also tidies up C<closest_address> (which
is then used in an attribute mapping), sets the category attribute using
C<request_to_resource_attribute_manual_mapping>'s category key and
C<defect_sourcetype_category_mapping> to look up the category ID from there,
and if C<staff_role> was passed in, use C<defect_source_mapping> lookup on
that and C<request_to_resource_attribute_manual_mapping>'s source key to set
the correct attribute.

=cut

sub process_attributes {
    my ($self, $args) = @_;

    if ($args->{attributes}{closest_address}) {
        $args->{attributes}{closest_address} =~ s/^Nearest[^:]*: //;
        $args->{attributes}{closest_address} =~ s/\n+Nearest.*$//s;
    }

    my $attributes = $self->SUPER::process_attributes($args);

    # For category we use the category and not the group
    my ( $group, $category ) = split('_', $args->{service_code});

    # Config contains a mapping from ID to category name
    my $design = $self->config->{defect_resource_name};
    $design = $design->[0] if ref $design eq 'ARRAY';
    my $mapping = $self->config->{defect_sourcetype_category_mapping}{$design}{types};
    my %category_to_id = reverse %$mapping;
    my $group_code = $category_to_id{$category} || $self->config->{default_category_attribute_value};

    push @$attributes, {
        attributeCode => $self->config->{request_to_resource_attribute_manual_mapping}->{category},
        value => [ $group_code ],
    };

    # We also might have a source to associate
    if (my $staff_role = $args->{attributes}{staff_role}) {
        my $mapping = $self->config->{defect_source_mapping};
        if (my $code = $mapping->{$staff_role}) {
            push @$attributes, {
                attributeCode => $self->config->{request_to_resource_attribute_manual_mapping}->{source},
                value => [$code],
            };
        }
    }

    return $attributes;

}

=head2 is_ignored_category

Overriding the default of ignoring C<ignored_defect_types>, we instead
ignore any report or update which has a status of open (Proposed).

=cut

sub is_ignored_category {
    my ($self, $defect) = @_;

    my $status = $self->defect_status($self->alloy->attributes_to_hash($defect));
    return 1 if $status eq 'open';
}

1;
