package Integrations::SalesForce::Rutland;

use Moo;
extends 'Integrations::SalesForce::Base';

use JSON::MaybeXS;

has 'requests_endpoint' => (
    is => 'ro',
    default => sub { shift->endpoint_url . 'FixMyStreet'; }
);

has 'services_endpoint' => (
    is => 'ro',
    default => sub { shift->endpoint_url . 'FixMyStreetInfoV2' }
);

has 'updates_endpoint' => (
    is => 'ro',
    default => sub { shift->endpoint_url . 'FixMyStreetUpdates' }
);

sub get_requests {
    my $self = shift;

    return $self->get($self->requests_endpoint . '?all');
}

sub get_request {
    my ($self, $id) = @_;

    return $self->get($self->requests_endpoint . '?id=' . $id);
}

sub post_request {
    my ($self, $service, $args) = @_;

    my $name = join(' ', ($args->{first_name}, $args->{last_name}));

    my $formatter = DateTime::Format::Strptime->new(pattern => '%FT%T%z');
    my $date = $formatter->format_datetime(DateTime->now());

    my $values = {
            agency_responsible__c => 'Rutland County Council',
            description__c => $args->{attributes}->{description},
            detail__c => $args->{attributes}->{description},
            interface_used__c => 'Web interface',
            lat__c => $args->{lat} + 0,
            long__c => $args->{long} + 0,
            agency_sent_datetime__c => $date,
            requested_datetime__c => $date,
            updated_datetime__c => $date,
            requestor_name__c => $name,
            contact_name__c => $name,
            status__c => 'open',
            Service_Area__c => $args->{service_code},
            title__c => $args->{attributes}->{title},
            service_request_id__c => $args->{attributes}->{external_id} + 0,
    };

    # add category specific attributes
    for my $extra (map { $_->code } @{ $service->attributes}) {
        next unless exists $args->{attributes}->{$extra};
        unless (exists $service->internal_attributes->{$extra}) {
            $values->{$extra} = $args->{attributes}->{$extra};
        }
    }

    $values->{contact_phone__c} = $args->{phone} if $args->{phone};
    $values->{contact_email__c} = $args->{email} if $args->{email};

    if ($args->{media_url}->[0]) {
        $values->{photos} = $args->{media_url};
    }

    my $data = [ $values ];

    my $json = encode_json($data);

    my $response = $self->post($self->requests_endpoint, encode_json($data));

    return $response->[0]->{Id};
}

sub post_update {
    my ($self, $args) = @_;

    my $data = [ {
        status__c => $args->{status},
        id => $args->{service_request_id},
        #update_comments_id__c => $args->{description},
        update_comments__c => $args->{description},
    } ];

    my $json = encode_json($data);
    my $response = $self->post($self->requests_endpoint, encode_json($data));

    return $response->[0]->{Id} || undef;
}

sub get_updates {
    my $self = shift;
    return $self->get($self->updates_endpoint . '?updates');
}

sub get_services {
    my ($self, $args) = @_;

    my $key = "get_services";
    my $expiry = 300; # cache all these API calls for 5 minutes
    my $services = $self->memcache->get($key);

    if ($services) {
        $self->logger->debug("Found memcached entry for $key");
        return @$services;
    }

    $self->logger->debug("No memcached entry found for $key. Fetching services from Salesforce");

    $services = [];
    my $response = $self->get($self->services_endpoint . '?summary');
    for my $service (@{ $response->{CategoryInformation} }) {
        push @$services, $service;
    }

    $self->memcache->set($key, $services, $expiry);

    return @$services;
}

sub get_service {
    my ($self, $id, $args) = @_;

    my $service = $self->get($self->services_endpoint . '?id=' . $id);

    return $service;
}

1;
