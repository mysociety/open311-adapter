package Open311::Endpoint::Integration::UK::Hackney::Base;

use Moo;
extends 'Open311::Endpoint::Integration::AlloyV2';

has '+group_in_service_code' => (
    is => 'ro',
    default => 0
);

sub service_request_content {
    '/open311/service_request_extended'
}

# basic services creating without setting up attributes from Alloy
sub services {
    my $self = shift;

    my @services = ();
    my %categories = ();
    for my $group (sort keys %{ $self->service_whitelist }) {
        my $whitelist = $self->service_whitelist->{$group};
        for my $subcategory (sort keys %{ $whitelist }) {
            $categories{$subcategory} ||= [];
            push @{ $categories{$subcategory} }, $group;
        }
    }

    for my $category (sort keys %categories) {
        my $name = $category;
        my $code = $name;
        my %service = (
            service_name => $name,
            description => $name,
            service_code => $code,
            groups => $categories{$category},
        );
        my $o311_service = $self->service_class->new(%service);

        push @services, $o311_service;
    }

    return @services;
}

sub process_attributes {
    my ($self, $args) = @_;

    my $attributes = $self->SUPER::process_attributes($args);

    # The way the reporter's contact information gets included with a
    # inspection is Northamptonshire-specific, so it's handled here.
    # Their Alloy set up attaches a "Contact" resource to the
    # inspection resource via the "caller" attribute.

    # Take the contact info from the service request and find/create
    # a matching contact
    my $contact_resource_id = $self->_find_or_create_contact($args);

    # Unlike Northants, Hackney has an item for each category (not group).
    # Not every category on the FMS side has a matching attribute value in Alloy,
    # so the default_category_attribute_value config value is used when the
    # service code doesn't exist in category_list_code, because a value is
    # required by Alloy.
    my $group_code = $self->_find_category_code($args->{service_code}) || $self->config->{default_category_attribute_value};
    push @$attributes, {
        attributeCode => $self->config->{request_to_resource_attribute_manual_mapping}->{category},
        value => [ $group_code ],
    };

    # Attach the caller to the inspection attributes
    push @$attributes, {
        attributeCode => $self->config->{contact}->{attribute_id},
        value => [ $contact_resource_id ],
    };

    return $attributes;

}

1;
