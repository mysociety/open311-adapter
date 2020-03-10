package Open311::Endpoint::Integration::UK::Northamptonshire;

use Moo;
extends 'Open311::Endpoint::Integration::Alloy';

use JSON::MaybeXS;

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    $args{jurisdiction_id} = 'northamptonshire_alloy';
    return $class->$orig(%args);
};

sub service_request_content {
    '/open311/service_request_extended'
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

    # For category we use the group and not the category
    my ( $group, $category ) = split('_', $args->{service_code});
    my $group_code = $self->config->{service_whitelist}->{$group}->{resourceId} + 0;
    $attributes->{$self->config->{request_to_resource_attribute_mapping}->{category}} = [ { resourceId => $group_code, command => "add" } ];

    # Attach the caller to the inspection attributes
    $attributes->{$self->config->{contact}->{attribute_id}} = [{
        resourceId => $contact_resource_id,
        command => 'add'
    }];

    return $attributes;

}

sub get_request_description {
    my ($self, $desc, $req) = @_;

    my $cat = $self->get_defect_category($req);
    $cat =~ s/^.*_//;

    my $priority;
    my @attributes = @{$req->{values}};

    for my $att (@attributes) {
        if ($att->{attributeCode} =~ /PRIORITIES/ ) {
            $priority = $att->{value}->{values}->[0]->{resourceId};
        }
    }

    if ($priority) {
        my $priority_details = $self->alloy->api_call(
            call => "resource/$priority"
        );

        my $timescale = $priority_details->{title};
        $timescale =~ s/P\d+, P\d+ - (.*)/$1/;

        my %reverse_whitelist;
        for my $group (sort keys %{ $self->service_whitelist }) {
            my $whitelist = $self->service_whitelist->{$group};
            for my $subcategory (sort keys %{ $whitelist }) {
                next if $subcategory eq 'resourceId';
                $reverse_whitelist{$subcategory} = $group;
            }
        }

        my $group = $reverse_whitelist{$cat} || '';

        $desc = "Our Inspector has identified a $group defect at this location and has issued a works ticket to repair under the $cat category. We aim to complete this work within the next $timescale.";
    }

    return $desc;
}

sub process_update_state {
    my ($self, $status, $reason_for_closure) = @_;

    if ( $status eq 'further_investigation' ) {
        $status = 'investigating';
        $reason_for_closure = 'further'
    }

    return ($status, $reason_for_closure);
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
    my ($self, $email, $phone) = @_;

    my $entity_code = $self->config->{contact}->{search_entity_code};
    my ($attribute_code, $search_term);
    if ( $email ) {
        $search_term = $email;
        $attribute_code = $self->config->{contact}->{search_attribute_code_email};
    } elsif ( $phone ) {
        $search_term = $phone;
        $attribute_code = $self->config->{contact}->{search_attribute_code_phone};
    } else {
        return undef;
    }

    my $results = $self->alloy->api_call(
        call => "search/resource",
        body => {
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
                                        $search_term
                                    ]
                                }
                            }
                        ]
                    }
                ]
            }
        }
    );

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

    return $self->alloy->api_call(
        call => "resource",
        body => $contact
    );
}

sub _generate_update {
    my ($self, $args, $updates) = @_;

    my @contacts = map { $args->{$_} } grep { $args->{$_} } qw/ email phone /;
    my $time = DateTime::Format::W3CDTF->new->parse_datetime($args->{updated_datetime});
    my $formatted_time = $time->ymd . " " . $time->hms;
    $updates .= sprintf(
        "\nCustomer %s %s [%s] update at %s\n%s",
        $args->{first_name},
        $args->{last_name},
        join(',', @contacts),
        $formatted_time,
        $args->{description}
    );

    return $updates;
}

1;
