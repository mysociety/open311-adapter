package Open311::Endpoint::Integration::UK::Northamptonshire;

use Moo;
extends 'Open311::Endpoint::Integration::Alloy';

use List::Util 'first';
use JSON::MaybeXS;

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'northamptonshire_alloy';
    return $class->$orig(%args);
};

use Integrations::Alloy::Northamptonshire;

has integration_class => (
    is => 'ro',
    default => 'Integrations::Alloy::Northamptonshire'
);

has service_request_content => (
    is => 'ro',
    default => '/open311/service_request_extended'
);

sub process_attributes {
    my ($self, $source, $args) = @_;

    my $attributes = $self->SUPER::process_attributes($source, $args);

    # The way the reporter's contact information gets included with a
    # inspection is Northamptonshire-specific, so it's handled here.
    # Their Alloy set up attaches a "Contact" resource to the
    # inspection resource via the "caller" attribute.

    # Take the contact info from the service request and find/create
    # a matching contact
    my $contact_resource_id = $self->_find_or_create_contact($args);

    # For category we use the group and not the category
    my ( $group, $category ) = split('_', $args->{service_code});
    $attributes->{$self->config->{request_to_resource_attribute_mapping}->{category}} = $group;

    # Attach the caller to the inspection attributes
    # TODO The caller attribute isn't present in the design yet...! XXX
    #
    $attributes->{$self->config->{contact}->{attribute_id}} = [{
        resourceId => $contact_resource_id,
        command => 'add'
    }];

    return $attributes;

}

sub _find_or_create_contact {
    my ($self, $args) = @_;

    if (my $contact = $self->_find_contact($args->{email})) {
        return $contact->{resourceId};
    } else {
        return $self->_create_contact($args)->{resourceId};
    }
}

sub _find_contact {
    my ($self, $email) = @_;

    my $entity_code = $self->config->{contact}->{search_entity_code};
    my $attribute_code = $self->config->{contact}->{search_attribute_code};

    my $results = $self->alloy->api_call("search/resource", undef, {
        aqsNode => {
            type => "SEARCH",
            properties => {
                entityType => "SOURCE_TYPE",
                entityCode => $entity_code
            },
            children => [
                {
                    type => "EQUALS",
                    children => [
                        {
                            type => "ATTRIBUTE",
                            properties => {
                                attributeCode => $attribute_code
                            }
                        },
                        {
                            type => "STRING",
                            properties => {
                                value => [
                                    $email
                                ]
                            }
                        }
                    ]
                }
            ]
        }
    });

    return undef unless $results->{totalHits};
    return $results->{results}[0]->{result};
}

sub _create_contact {
    my ($self, $args) = @_;

    # For true/false values we have to use the JSON()->true/false otherwise
    # when we convert to JSON later we get 1/0 which then fails the validation
    # at the Alloy end
    # NB: have to use 'true'/'false' strings in the YAML for this to work. If we
    # use true/false then it gets passed in as something that gets converted to 1/0
    #
    # we could possibly use local $YAML::XS::Boolean = "JSON::PP" in the Config module
    # to get round all this but not sure if that would break something else.
    my $attributes = {
        map {
            $_ => $self->config->{contact}->{attribute_defaults}->{$_} =~ /^(true|false)$/
                ? JSON()->$1
                : $self->config->{contact}->{attribute_defaults}->{$_}
        } keys %{ $self->config->{contact}->{attribute_defaults} }
    };

    # phone cannot be null;
    $args->{phone} ||= '';

    my $remapping = $self->config->{contact}->{attribute_mapping} || {};
    for my $key ( keys %$remapping ) {
        $attributes->{$remapping->{$key}} = $args->{$key};
    }

    # do not think this is needed now
    #my $now = DateTime->now();
    #my $created_time = DateTime::Format::W3CDTF->new->format_datetime($now);
    #$attributes->{$self->config->{contact}->{acceptance_datetime_attribute}} = $created_time;

    my $contact = {
        sourceId => $self->config->{contact}->{source_id},
        attributes => $attributes,
        geoJson => undef,
        startDate => undef,
        endDate => undef,
        networkReference => undef,
        parents => {},
        colour => undef
    };

    return $self->alloy->api_call("resource", undef, $contact);
}

1;
