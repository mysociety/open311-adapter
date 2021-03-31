package Open311::Endpoint::Integration::Echo;

use v5.14;

use Moo;
use JSON::MaybeXS;

extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Open311::Endpoint::Role::ConfigFile';
with 'Role::Logger';

use Integrations::Echo;
use Open311::Endpoint::Service::Attribute;
use Open311::Endpoint::Service::UKCouncil::Echo;
use Open311::Endpoint::Service::Request::Update;

has jurisdiction_id => ( is => 'ro' );

# A mapping from event type ID (or string if multiple event
# types behind one service) to event type description
has service_whitelist => ( is => 'ro' );

# A mapping of service code and Echo service ID to event type
# (used for the case of multiple event types behind one service)
has service_to_event_type => ( is => 'ro' );

# A mapping when a particular event type requires a particular
# service, not the service chosen by the user
has service_id_override => ( is => 'ro' );

# A mapping from event type data field name to Open311 request field name
has data_key_open311_map => ( is => 'ro' );

# A mapping of event type data field name and its default, for any request
has default_data_all => ( is => 'ro' );

# A mapping of event type to data field defaults only for that event type
has default_data_event_type => ( is => 'ro' );

has service_class => ( is => 'ro', default => 'Open311::Endpoint::Service::UKCouncil::Echo' );

sub services {
    my $self = shift;

    my $services = $self->service_whitelist;
    my @services = map {
        my $id = $_;
        my $name = $services->{$_};
        my $service = $self->service_class->new(
            service_name => $name,
            service_code => $_,
            description => $name,
            group => 'Waste',
            allow_any_attributes => 1,
        );
        $service;
    } sort keys %$services;
    return @services;
}

has integration_class => (
    is => 'ro',
    default => 'Integrations::Echo'
);

sub get_integration {
    my $self = shift;
    my $integ = $self->integration_class->new(
        config_filename => $self->jurisdiction_id,
    );
    return $integ;
}

# For each event type data field, we will take a value
# from the main request if mapped, provided attributes,
# or any given defaults
sub check_for_data_value {
    my ($self, $name, $args, $request, $parent_name) = @_;

    my $value;
    if ($parent_name) {
        my $full_name = $parent_name . '_' . $name;
        $value = $self->_get_data_value($full_name, $args, $request);
    }
    unless (defined $value) {
        $value = $self->_get_data_value($name, $args, $request);
    }
    return $value;
}

sub _get_data_value {
    my ($self, $name, $args, $request) = @_;
    (my $name_with_underscores = $name) =~ s/ /_/g;
    return $args->{$self->data_key_open311_map->{$name}} if $self->data_key_open311_map->{$name};
    return $args->{attributes}{$name_with_underscores} if length $args->{attributes}{$name_with_underscores};
    return $self->default_data_all->{$name} if $self->default_data_all->{$name};
    return $self->default_data_event_type->{$request->{event_type}}{$name}
        if $self->default_data_event_type->{$request->{event_type}}{$name};
    return undef;
}

sub post_service_request {
    my ($self, $service, $args) = @_;
    die "No such service\n" unless $service;

    my $request = $self->process_service_request_args($args);
    $self->logger->debug(encode_json($request));

    my $integ = $self->get_integration;

    # Look up extra data fields
    my $event_type = $integ->GetEventType($request->{event_type});
    foreach my $type (@{$event_type->{Datatypes}->{ExtensibleDatatype}}) {
        my $row = { id => $type->{Id} };
        $row->{value} = $self->check_for_data_value($type->{Name}, $args, $request);

        if ($type->{ChildDatatypes}) {
            foreach (@{$type->{ChildDatatypes}{ExtensibleDatatype}}) {
                my $subrow = { id => $_->{Id} };
                $subrow->{value} = $self->check_for_data_value($_->{Name}, $args, $request, $type->{Name});
                push @{$row->{childdata}}, $subrow if defined $subrow->{value};
            }
        }

        push @{$request->{data}}, $row if defined $row->{value} || $row->{childdata};
    }

    my $response = $integ->PostEvent($request);
    die "Failed\n" unless $response;

    $request = $self->new_request(
        service_request_id => $response->{EventGuid},
    );
    return $request;
}

sub process_service_request_args {
    my $self = shift;
    my $args = shift;

    my $event_type = $args->{service_code};
    my $service = $args->{attributes}{service_id} || '';
    my $uprn = $args->{attributes}{uprn};
    my $fixmystreet_id = $args->{attributes}{fixmystreet_id} || '';

    # Missed collections have different event types depending
    # on the service
    $event_type = $self->service_to_event_type->{$event_type}{$service}
        if $self->service_to_event_type->{$event_type}{$service};

    # e.g. the new container event type always uses a
    # specific service, not the collection service
    $service = $self->service_id_override->{$event_type}
        if $self->service_id_override->{$event_type};

    my $request = {
        event_type => $event_type,
        service => $service,
        uprn => $uprn,
        client_reference => "FMS-$fixmystreet_id",
        data => [],
    };

    return $request;
}

sub post_service_request_update {
    my ($self, $args) = @_;

    my $response = $self->get_integration->PerformEventAction($args);
    return Open311::Endpoint::Service::Request::Update->new(
        status => lc $args->{status},
        update_id => $response->{EventActionGuid},
    );
}

1;
