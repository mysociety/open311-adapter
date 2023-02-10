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
    #my $group_code = $self->_find_group_code($group);
    my $cat_code = $self->_find_category_code($category);
    #push @$attributes, {
    #    attributeCode => $self->config->{request_to_resource_attribute_manual_mapping}->{group},
    #    value => [ $group_code ],
    #};
    push @$attributes, {
        attributeCode => $self->config->{request_to_resource_attribute_manual_mapping}->{category},
        value => [ $cat_code ],
    };

    return $attributes;
}

#sub _find_group_code {
#    my ($self, $group) = @_;
#
#    my $results = $self->_search_for_code($self->config->{group_list_code});
#    for my $group (@$results) {
#        return $group->{itemId} if $group->{attributes}{$self->config->{group_title_attribute}} eq $group;
#    }
#}

1;
