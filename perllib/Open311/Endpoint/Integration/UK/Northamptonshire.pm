package Open311::Endpoint::Integration::UK::Northamptonshire;

use Moo;
extends 'Open311::Endpoint::Integration::Alloy';

use List::Util 'first';

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

sub service_request_id_for_resource {
    my ($self, $resource) = @_;

    my $attribute_id = $self->config->{inspection_id_attribute};
    my $attribute = first { $_->{attributeId} eq $attribute_id } @{ $resource->{values} };

    # We can't default to e.g. resourceId because it'll make later
    # identification of this resource very complicated.
    die "Couldn't find inspection ID for resource" unless $attribute && $attribute->{value};

    return $attribute->{value};
}

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


    # Attach the caller to the inspection attributes
    # TODO The caller attribute isn't present in the design yet...! XXX
    #
    $attributes->{$self->config->{contact}->{attribute_id}} = $contact_resource_id;

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

    my $attributes = {
        %{ $self->config->{contact}->{attribute_defaults} }
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
