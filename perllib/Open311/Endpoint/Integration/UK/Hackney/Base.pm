package Open311::Endpoint::Integration::UK::Hackney::Base;

use Moo;
extends 'Open311::Endpoint::Integration::AlloyV2';

sub service_request_content {
    '/open311/service_request_extended'
}

sub process_attributes {
    my ($self, $args) = @_;

    my $attributes = $self->SUPER::process_attributes($args);

    # The way the reporter's contact information gets included with a
    # inspection is cobrand-specific, so it's handled here.
    # Their Alloy set up attaches a "Contact" resource to the
    # inspection resource via the "caller" attribute.

    # Take the contact info from the service request and find/create
    # a matching contact
    my $contact_resource_id = $self->_find_or_create_contact($args);

    # Hackney has an item for each category (not group). Not every category on
    # the FMS side has a matching attribute value in Alloy, so the
    # default_category_attribute_value config value is used when the service
    # code doesn't exist in category_list_code, because a value is required by
    # Alloy.
    my $category_code = $self->_find_category_code($args->{service_code_alloy}) || $self->config->{default_category_attribute_value};
    push @$attributes, {
        attributeCode => $self->config->{request_to_resource_attribute_manual_mapping}->{category},
        value => [ $category_code ],
    };

    # Attach the caller to the inspection attributes
    push @$attributes, {
        attributeCode => $self->config->{contact}->{attribute_id},
        value => [ $contact_resource_id ],
    };

    return $attributes;

}

1;
