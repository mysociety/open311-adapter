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

sub process_attributes {
    my ($self, $args) = @_;

    my $attributes = $self->SUPER::process_attributes($args);

    # Take the contact info from the service request and find/create
    # a matching contact
    my $contact_resource_id = $self->_find_or_create_contact($args);

    # For category we use the category and not the group
    my ( $group, $category ) = split('_', $args->{service_code});
    my $group_code = $self->_find_category_code($category) || $self->config->{default_category_attribute_value};
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
