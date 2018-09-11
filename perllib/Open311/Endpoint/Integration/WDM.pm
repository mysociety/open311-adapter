package Open311::Endpoint::Integration::WDM;

use Moo;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';

use DateTime::Format::Strptime;

use Integrations::WDM;
use Open311::Endpoint::Service::UKCouncil::Oxfordshire;
use Open311::Endpoint::Service::Request::ExtendedStatus;

has service_class  => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::UKCouncil::Oxfordshire'
);

has service_request_content => (
    is => 'ro',
    default => '/open311/service_request_extended'
);

has '+request_class' => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::Request::ExtendedStatus',
);


sub get_integration {
    my $self = shift;
    return $self->integration_class->new;
}

sub post_service_request {
    my ($self, $service, $args) = @_;
    my $new_id = $self->get_integration->post_request($service, $args);

    my $request = $self->new_request(
        service_request_id => $new_id,
    );

    return $request;
}


sub service {
    my ($self, $id, $args) = @_;

    my $service = Open311::Endpoint::Service::UKCouncil::Oxfordshire->new(
        service_name => $id,
        service_code => $id,
        description => $id,
        type => 'realtime',
        keywords => [qw/ /],
    );

    return $service;
}

1;
