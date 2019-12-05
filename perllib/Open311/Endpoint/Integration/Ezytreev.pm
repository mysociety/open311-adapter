package Open311::Endpoint::Integration::Ezytreev;

use Moo;
use Integrations::Ezytreev;

extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Open311::Endpoint::Role::ConfigFile';

has integration_class => (
    is => 'ro',
    default => 'Integrations::Ezytreev'
);

has ezytreev => (
    is => 'lazy',
    default => sub { $_[0]->integration_class->new(config_filename => $_[0]->jurisdiction_id) }
);

sub services {
    my $self = shift;
    my @services = ();
    return @services;
}

sub service {
    my ($self, $service_code, $args) = @_;
    return first { $_->service_code eq $service_code } $self->services($args);
}

sub post_service_request {
    my ($self, $service, $args) = @_;
    die "abstract method post_service_request not implemented";
}

sub get_service_requests {
    my ($self, $args) = @_;
    die "abstract method get_service_requests not implemented";
}

sub get_service_request {
    my ($self, $service_request_id, $args) = @_;
    die "abstract method get_service_request not implemented";
}

__PACKAGE__->run_if_script;
