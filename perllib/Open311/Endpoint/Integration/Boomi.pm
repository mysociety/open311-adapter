package Open311::Endpoint::Integration::Boomi;

use Moo;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Role::EndpointConfig';
with 'Role::Logger';

use POSIX qw(strftime);
use MIME::Base64 qw(encode_base64);
use Open311::Endpoint::Service::UKCouncil::Boomi;
use Integrations::Surrey::Boomi;
use JSON::MaybeXS;
use DateTime::Format::W3CDTF;
use Path::Tiny;
use Try::Tiny;

has jurisdiction_id => (
    is => 'ro',
    required => 1,
);

has boomi => (
    is => 'lazy',
    default => sub { $_[0]->integration_class->new(config_filename => $_[0]->jurisdiction_id) }
);

has integration_class => (
    is => 'ro',
    default => 'Integrations::Surrey::Boomi',
);



sub service {
    my ($self, $id, $args) = @_;

    my $service = Open311::Endpoint::Service::UKCouncil::Boomi->new(
        service_name => $id,
        service_code => $id,
        description => $id,
        type => 'realtime',
        keywords => [qw/ /],
        allow_any_attributes => 1,
    );

    return $service;
}


sub services {
    my ($self) = @_;

    # Boomi doesn't provide a list of services; they're just created as
    # contacts in the FMS admin.

    return ();
}

sub post_service_request {
    my ($self, $service, $args) = @_;

    die "Args must be a hashref" unless ref $args eq 'HASH';

    $self->logger->info("[Boomi] Creating issue");
    $self->logger->debug("[Boomi] POST service request args: " . encode_json($args));

    my $ticket = {
        integrationId => $self->endpoint_config->{integrationId},
        subject => $args->{attributes}->{title},
        status => 'open',
        description => $args->{attributes}->{description},
        location => {
            latitude => $args->{lat},
            longitude => $args->{long},
            easting => $args->{attributes}->{easting},
            northing => $args->{attributes}->{northing},
        },
        requester => {
            fullName => $args->{first_name} . " " . $args->{last_name},
            email => $args->{email},
            phone => $args->{attributes}->{phone},
        },
        customFields => [
            {
                id => 'category',
                values => [ $args->{attributes}->{group} ],
            },
            {
                id => 'subCategory',
                values => [ $args->{attributes}->{category} ],
            },
            {
                id => 'fixmystreet_id',
                values => [ $args->{attributes}->{fixmystreet_id} ],
            },
        ],
    };
    my $service_request_id = $self->boomi->upsertHighwaysTicket($ticket);

    return $self->new_request(
        service_request_id => $service_request_id,
    )
}



sub get_service_request_updates {
    my ($self, $args) = @_;

    # TBC

    return ();

}



1;
