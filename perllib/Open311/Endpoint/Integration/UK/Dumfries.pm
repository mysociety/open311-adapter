package Open311::Endpoint::Integration::UK::Dumfries;

use Moo;
extends 'Open311::Endpoint::Integration::AlloyV2';
with 'Role::Memcached';

use Encode;
use JSON::MaybeXS;
use Path::Tiny;

around BUILDARGS => sub {
    my ( $orig, $class, %args ) = @_;
    $args{jurisdiction_id} = 'dumfries_alloy';
    return $class->$orig(%args);
};

=head2 process_attributes

In addition to the default new request processing, this function:
* Finds or creates a contact and adds them under the C<contact.attribute_id> attribute.
* Sets the 'reported issue' (i.e. category) field by the incoming service_code.

=cut

sub process_attributes {
    my ($self, $args) = @_;

    my $attributes = $self->SUPER::process_attributes($args);

    my $contact_resource_id = $self->_find_or_create_contact($args);
    push @$attributes, {
        attributeCode => $self->config->{contact}->{attribute_id},
        value => [ $contact_resource_id ],
    };

    push @$attributes, {
        attributeCode => $self->config->{request_to_resource_attribute_manual_mapping}->{service_code},
        value => [ $args->{service_code_alloy} ],
    };

    return $attributes;
}

=head2 _get_service_code

Dumfries uses the actual Alloy item IDs from their subcategory list on Alloy
as Open311 service codes. This means we can hae different names shown for
groups/subcategories on FMS as well as the same subcategory name used
multiple times for different Alloy IDs (e.g. the 'Other' subcategory in their
'Trees' group has a different item ID to 'Other' in 'Grounds').

=cut

sub _get_service_code {
    my ($self, $group, $subcategory, $subcategory_config) = @_;

    return $subcategory_config->{id};
}


1;
