package Open311::Endpoint::Integration::UK::Northamptonshire;

use Moo;
extends 'Open311::Endpoint::Integration::Alloy';

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
    my $group_code = $self->config->{service_whitelist}->{$group}->{resourceId} + 0;
    $attributes->{$self->config->{request_to_resource_attribute_mapping}->{category}} = [ { resourceId => $group_code, command => "add" } ];

    # Attach the caller to the inspection attributes
    $attributes->{$self->config->{contact}->{attribute_id}} = [{
        resourceId => $contact_resource_id,
        command => 'add'
    }];

    return $attributes;

}

sub get_historic_updates {
    my ($self, $updates, $start_date, $end_date) = @_;

    # update to historic reports
    my $historic_updates = $self->fetch_updated_resources($self->config->{historic_resource_name}, $start_date);
    for my $update (@$historic_updates) {
        my $status = 'open';
        my ($service_request_id, $reason_for_closure);
        my @attributes = @{$update->{values}};
        for my $att (@attributes) {
            if ($att->{attributeCode} eq 'STU_INSPECTION_ST_USER_INSPECTION_-_ENQUIRY_-_MIGRATED_DATA_ATT_REASON_FOR_CLOSURE') {
                $reason_for_closure = $att->{value};
            }

            if ($att->{attributeCode} eq 'GRP_PROJECT_TASK_ATT_PROJECT_TASK_STATUS') {
                $status = $self->historic_status($att->{value}->{values}->[0]->{resourceId});
            }

            if ($att->{attributeCode} eq 'STU_INSPECTION_ST_USER_INSPECTION_-_ENQUIRY_-_MIGRATED_DATA_ATT_ENQUIRY_ID') {
                $service_request_id = $att->{value};
            }

        }

        $status = $self->get_historic_status_with_closure($status, $reason_for_closure);

        # subtract 20 seconds to make sure it passes FixMyStreet time checks
        # ideally this should use the time of the actual update but it's not really clear how to get this
        # out of the Alloy API so easier just to use the end date
        my $update_dt = DateTime::Format::W3CDTF->new->parse_datetime( $end_date )->add( seconds => -20 );

        my %args = (
            status => $status,
            update_id => $update->{version}->{resourceSystemVersionId},
            service_request_id => $service_request_id,
            description => '',
            updated_datetime => $update_dt,
        );

        push @$updates, Open311::Endpoint::Service::Request::Update::mySociety->new( %args );
    }
}

sub get_historic_requests {
    my ($self, $args) = @_;

    my %args;

    my $requests = $self->fetch_updated_resources($self->config->{historic_resource_name}, $args->{start_date});
    my @requests;
    for my $request (@$requests) {

        my ($code, $desc, $created, $orig_status, $status, $reason_for_closure, $updated);

        my @attributes = @{$request->{values}};
        for my $att (@attributes) {
            if ($att->{attributeCode} eq 'STU_INSPECTION_ST_USER_INSPECTION_-_ENQUIRY_-_MIGRATED_DATA_ATT_DESCRIPTION') {
                $args{description} = $att->{value};
            }

            if ($att->{attributeCode} eq 'STU_INSPECTION_ST_USER_INSPECTION_-_ENQUIRY_-_MIGRATED_DATA_ATT_ENQUIRY_ID') {
                $args{service_request_id} = $att->{value};
            }

            if ($att->{attributeCode} eq 'STU_INSPECTION_ST_USER_INSPECTION_-_ENQUIRY_-_MIGRATED_DATA_ATT_CLASS_DESCRIPTION') {
                $code = $att->{value};
            }

            if ($att->{attributeCode} eq 'STU_INSPECTION_ST_USER_INSPECTION_-_ENQUIRY_-_MIGRATED_DATA_ATT_CATEGORY_TYPE_DESCRIPTION') {
                $desc = $att->{value};
            }

            if ($att->{attributeCode} eq 'STU_INSPECTION_ST_USER_INSPECTION_-_ENQUIRY_-_MIGRATED_DATA_ATT_DATE_RECORDED') {
                $created = $att->{value};
            }

            if ($att->{attributeCode} eq 'STU_INSPECTION_ST_USER_INSPECTION_-_ENQUIRY_-_MIGRATED_DATA_ATT_ENQUIRY_REASON_DATE_CHANGED') {
                $updated = $att->{value};
            }

            if ($att->{attributeCode} eq 'STU_INSPECTION_ST_USER_INSPECTION_-_ENQUIRY_-_MIGRATED_DATA_ATT_ENQUIRY_STATUS__EXOR_FOR_REFERENCE_ONLY_') {
                $orig_status = $att->{value};
            }

            if ($att->{attributeCode} eq 'STU_INSPECTION_ST_USER_INSPECTION_-_ENQUIRY_-_MIGRATED_DATA_ATT_REASON_FOR_CLOSURE') {
                $reason_for_closure = $att->{value}->{values}->[0]->{resourceId};
            }

            if ($att->{attributeCode} eq 'GRP_PROJECT_TASK_ATT_PROJECT_TASK_STATUS') {
                $status = $self->historic_status($att->{value}->{values}->[0]->{resourceId});
            }
        }

        # this doesn't seem to be correctly represented in the statuses
        next if defined $orig_status && $orig_status eq 'WORK COMPLETE' && $status eq 'closed';

        $args{status} = $self->get_historic_status_with_closure($status, $reason_for_closure);
        next if $self->config->{historic_skip_import_status}->{$args{status}};

        my $category;
        if ($self->config->{service_whitelist}->{$code}->{$desc}) {
            $category = $desc;
        } elsif ( defined $self->config->{historic_category_mapping}->{$code}->{$desc} ) {
            $category = $self->config->{historic_category_mapping}->{$code}->{$desc};
        } else {
            $self->logger->debug("no map $code -- $desc");
            $category = "";
        }

        next unless $category;

        $args{latlong} = $self->get_latlong_from_request($request);

        my $service = Open311::Endpoint::Service->new(
            service_name => $category,
            service_code => $category,
        );
        $args{service} = $service;
        $args{requested_datetime} = DateTime::Format::W3CDTF->new->parse_datetime($created)->truncate( to => 'second' );
        $args{updated_datetime} = DateTime::Format::W3CDTF->new->parse_datetime($updated || $created)->truncate( to => 'second' );

        push @requests, Open311::Endpoint::Service::Request::ExtendedStatus->new( %args );
    }

    return @requests;
}

sub get_historic_status_with_closure {
    my ($self, $status, $reason_for_closure) = @_;

    return $status unless $status eq 'closed' && $reason_for_closure;

    return $self->config->{historic_inspection_closure_mapping}->{$reason_for_closure} || $status;
}

sub historic_status {
    my ($self, $status) = @_;

    return $self->config->{historic_status_mapping}->{lc $status} || 'open';
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
                                    $search_term
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
