=head1 NAME

Open311::Endpoint::Integration::UK::BuckinghamshireAlloy - Buckinghamshire-specific parts of its Alloy integration

=head1 DESCRIPTION

=cut

package Open311::Endpoint::Integration::UK::BuckinghamshireAlloy;

use Moo;
extends 'Open311::Endpoint::Integration::AlloyV2';

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'buckinghamshire_alloy';
    return $class->$orig(%args);
};

sub service_request_content {
    '/open311/service_request_extended'
}

=head2 process_attributes

This calls the default function, but also finds or creates a contact,
using C<contact.attribute_id> configuration for the attribute key to set.

It sets a category attribute using
C<request_to_resource_attribute_manual_mapping>'s category key, and potentially
a group too, searching Alloy for the relevant entry.

=cut

sub process_attributes {
    my ($self, $args) = @_;

    my $attributes = $self->SUPER::process_attributes($args);

    my $contact_resource_id = $self->_find_or_create_contact($args);
    push @$attributes, {
        attributeCode => $self->config->{contact}->{attribute_id},
        value => [ $contact_resource_id ],
    };

    my ($group, $category) = split('_', $args->{service_code});
    my ($cat_code, $group_code) = $self->_find_category_and_group_codes($category);
    $group_code = $group_code->[0] if ref $group_code eq 'ARRAY';
    push @$attributes, {
       attributeCode => $self->config->{request_to_resource_attribute_manual_mapping}->{group},
       value => [ $group_code ],
    };
    push @$attributes, {
        attributeCode => $self->config->{request_to_resource_attribute_manual_mapping}->{category},
        value => [ $cat_code ],
    };

    return $attributes;
}

=head2 _find_category_and_group_codes

This looks up the C<category_list_code> design in Alloy, and finds the entry
with a C<category_title_attribute> attribute that matches the provided
category.

It returns the entry's C<itemId> and the value of its
C<category_group_attribute> attribute, the latter of which is required when
creating new defects in Bucks Alloy.

=cut

sub _find_category_and_group_codes {
    my ($self, $category) = @_;

    my $results = $self->_search_for_code($self->config->{category_list_code});
    for my $cat ( @{ $results } ) {
        if ( $cat->{attributes}{$self->config->{category_title_attribute}} eq $category ) {
            return ($cat->{itemId}, $cat->{attributes}{$self->config->{category_group_attribute}});
        }
    }
}

=head2 _get_inspection_status

This uses the default way of looking up the status mapping, but then
looks up the status in Alloy in order to fetch the external status code
stored there to send back to FMS.

=cut

sub _get_inspection_status {
    my ($self, $attributes, $mapping) = @_;

    my $status = 'open';
    my $ext_code;
    if ($attributes->{$mapping->{status}}) {
        my $status_code = $attributes->{$mapping->{status}}->[0];
        $status = $self->inspection_status($status_code);

        my $status_obj = $self->alloy->api_call(call => "item/$status_code");
        $status_obj = $status_obj->{item};
        my $status_attributes = $self->alloy->attributes_to_hash($status_obj);
        $ext_code = $status_attributes->{$mapping->{external_status_code}};
    }
    return ($status, $ext_code);
}

1;
