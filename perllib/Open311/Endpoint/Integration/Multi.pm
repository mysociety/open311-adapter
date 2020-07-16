package Open311::Endpoint::Integration::Multi;

use Moo;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';

use Open311::Endpoint::Schema;

has jurisdiction_id => (
    is => 'ro',
);

has integrations => (
    is => 'lazy',
    default => sub {
        my @integrations = map {
            (my $ref = ref $_) =~ s/.*:://;
            { name => $ref, class => $_ }
        } $_[0]->plugins;
        \@integrations;
    },
);

has integration_without_prefix => (
    is => 'ro',
);

sub _call {
    my ($self, $fn, $integration, @args) = @_;
    foreach (@{$self->integrations}) {
        next unless $_->{name} eq $integration;
        return $_->{class}->$fn(@args);
    }
}

sub _all {
    my ($self, $fn, $args) = @_;
    my @all;
    foreach (@{$self->integrations}) {
        my $name = $_->{name};
        my @results = $_->{class}->$fn($args);
        @results = map { [ $name, $_ ] } @results;
        push @all, @results;
    }
    return @all;
}

sub _map_with_new_id {
    my ($self, $attributes, @results) = @_;
    $attributes = [$attributes] unless ref $attributes eq 'ARRAY';
    @results = map {
        my ($name, $result) = @$_;
        if ($name eq $self->integration_without_prefix) {
            $result;
        } else {
            my %params;
            for my $attribute ( @$attributes ) {
                if ($attribute eq 'service') {
                    my %service_params = ( service_code => "$name-" . $result->service->service_code );
                    $params{service} = (ref $result->service)->new( %{ $result->service }, %service_params );
                } else {
                    $params{$attribute} = "$name-" . $result->$attribute;
                    # Also need to update the relevant request ID if it's an update
                    if ($attribute eq 'update_id') {
                        $params{service_request_id} = "$name-" . $result->service_request_id;
                    }
                }
            }
            (ref $result)->new(%$result, %params);
        }
    } @results;
    return @results;
}

sub _map_from_new_id {
    my ($self, $code) = @_;

    my $names = join('|', grep { $_ ne $self->integration_without_prefix } map { $_->{name} } @{$_[0]->integrations});
    my ($integration, $service_code) = $code =~ /^($names)-(.*)/;
    if (!$integration) {
        $integration = $self->integration_without_prefix;
        $service_code = $code;
    }
    return ($integration, $service_code);
}

=item

Loops through all children, extracting their services and rewriting their codes
to include which child the service has come from (in case any codes overlap).

=cut

sub services {
    my ($self, $args) = @_;
    my @services = $self->_all(services => $args);
    @services = $self->_map_with_new_id(service_code => @services);
    return @services;
}

=item

Given a combined service ID (integration-code), extract the integration and
code, call the relevant integration with the code, then return it with the code
prefixed again.

=cut

sub service {
    my ($self, $service_id, $args) = @_;
    # Extract integration from service code and pass to correct child
    my ($integration, $service_code) = $self->_map_from_new_id($service_id);
    my $service = $self->_call('service', $integration, $service_code, $args);
    ($service) = $self->_map_with_new_id(service_code => [$integration, $service]);
    return $service;
}

=item

As with an individual service, work out which integration to pass the call to,
but we also need to restore the original combined code before leaving, as the
parent will be calling service() again.

=cut

sub post_service_request {
    my ($self, $service, $args) = @_;
    # Extract integration from service code and set up to pass to child
    my ($integration, $service_code) = $self->_map_from_new_id($service->service_code);
    my $integration_args = { %$args, service_code => $service_code };
    # Strip off the integration part of the service code from the service object
    my $integration_service = (ref $service)->new(%$service, service_code => $service_code);

    my $result = $self->_call('post_service_request', $integration, $integration_service, $integration_args);
    ($result) = $self->_map_with_new_id(service_request_id => [$integration, $result]);
    return $result;
}

sub post_service_request_update {
    my ($self, $args) = @_;

    # Cobrand needs to send the service_code through with updates
    # (see Bexley's open311_munge_update_params in FMS for example)
    my ($integration, $service_code) = $self->_map_from_new_id($args->{service_code});
    my ($integration2, $service_request_id) = $self->_map_from_new_id($args->{service_request_id});
    die "$integration did not equal $integration2\n" if $integration ne $integration2;

    my $integration_args = {
        %$args,
        service_code => $service_code,
        service_request_id => $service_request_id,
    };

    my $result = $self->_call('post_service_request_update', $integration, $integration_args);
    ($result) = $self->_map_with_new_id(update_id => [$integration, $result]);
    return $result;
}

sub get_service_request_updates {
    my ($self, $args) = @_;
    my @updates = $self->_all(get_service_request_updates => $args);
    @updates = $self->_map_with_new_id(update_id => @updates);
    return @updates;
}

sub get_service_requests {
    my ($self, $args) = @_;

    my @requests = $self->_all(get_service_requests => $args);
    @requests = $self->_map_with_new_id(['service_request_id','service'] => @requests);
    return @requests;
}

__PACKAGE__->run_if_script;
