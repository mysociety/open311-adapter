=head1 NAME

Open311::Endpoint::Integration::Aurora - An integration with Symology's Aurora platform.

=head1 SYNOPSIS

This integration:
* Creates cases for requests.
* Makes updates on the relevant cases.
* Fetches udpates on relevant cases.

=cut

package Open311::Endpoint::Integration::Aurora;

use strict;
use warnings;

use Moo;
use Integrations::Aurora;
use Open311::Endpoint::Service::UKCouncil::Aurora;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Role::EndpointConfig';
with 'Role::Logger';

=head1 CONFIGURATION

=cut

has integration_class => (is => 'ro', default => 'Integrations::Aurora');

has aurora => (
    is => 'lazy',
    default => sub { $_[0]->integration_class->new(config_filename => $_[0]->jurisdiction_id) },
);

sub get_integration {
    return $_[0]->aurora;
};

=head2 service_class

Uses the same service class as our Symology Insight integration.

=cut

has service_class  => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::UKCouncil::Aurora'
);

has jurisdiction_id => ( is => 'ro' );

=head2 category_mapping

A map from service_code to:

  name: The display name for the category
  group: Optional category group
  parameters: dictionary of default parameters to use

=cut

has category_mapping => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{category_mapping} }
);

=head1 BEHAVIOUR

=head2 services

Returns services based on the configured C<category_mapping>.

=cut

sub services {
    my $self = shift;
    my $services = $self->category_mapping;
    my @services = map {
        my $name = $services->{$_}{name};
        my $service = $self->service_class->new(
            service_name => $name,
            service_code => $_,
            description => $name,
            $services->{$_}{group} ? (group => $services->{$_}{group}) : (),
        );
    } keys %$services;
    return @services;
}

=head2 post_service_request

TODO

=cut

sub post_service_request {
    my ( $self, $service, $args ) = @_;
    die "unimplemented";
}

=head2 post_service_request_update

TODO

=cut

sub post_service_request_update {
    my ( $self, $service, $args ) = @_;
    die "unimplemented";
}

=head2 get_service_request_updates

TODO

=cut

sub get_service_request_updates {
    my ( $self, $service, $args ) = @_;
    die "unimplemented";
}

1;
