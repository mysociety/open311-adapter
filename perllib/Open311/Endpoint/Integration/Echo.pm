package Open311::Endpoint::Integration::Echo;

use v5.14;
use warnings;

use Moo;
use JSON::MaybeXS;

extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Open311::Endpoint::Role::ConfigFile';
with 'Role::Logger';

use Integrations::Echo;
use Open311::Endpoint::Service::Attribute;
use Open311::Endpoint::Service::UKCouncil::Echo;

around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    die unless $args{jurisdiction_id}; # Must have one by here
    $args{config_file} //= path(__FILE__)->parent(5)->realpath->child("conf/council-$args{jurisdiction_id}.yml")->stringify;
    return $class->$orig(%args);
};

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

sub log_and_die {
    my ($self, $msg) = @_;
    $self->logger->error($msg);
    die "$msg\n";
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
    my ($self, $name, $args, $request) = @_;
    my $value;
    (my $name_with_underscores = $name) =~ s/ /_/g;
    $value = $args->{$self->data_key_open311_map->{$name}} if $self->data_key_open311_map->{$name};
    $value = $args->{attributes}{$name_with_underscores} if $args->{attributes}{$name_with_underscores};
    $value = $self->default_data_all->{$name} if $self->default_data_all->{$name};
    $value = $self->default_data_event_type->{$request->{event_type}}{$name}
        if $self->default_data_event_type->{$request->{event_type}}{$name};
    return $value;
}

sub post_service_request {
    my ($self, $service, $args) = @_;
    $self->log_and_die("No such service") unless $service;

    my $request = $self->process_service_request_args($args);
    $self->logger->debug(encode_json($request));

    my $integ = $self->get_integration;

    # Look up extra data fields
    my $event_type = $integ->GetEventType($request->{event_type});
    foreach (@{$event_type->{Datatypes}->{ExtensibleDatatype}}) {
        my $row = { id => $_->{Id} };
        $row->{value} = $self->check_for_data_value($_->{Name}, $args, $request);

        if ($_->{ChildDatatypes}) {
            foreach (@{$_->{ChildDatatypes}{ExtensibleDatatype}}) {
                my $subrow = { id => $_->{Id} };
                $subrow->{value} = $self->check_for_data_value($_->{Name}, $args, $request);
                push @{$row->{childdata}}, $subrow if $subrow->{value};
            }
        }

        push @{$request->{data}}, $row if $row->{value} || $row->{childdata};
    }

    my $response = $integ->PostEvent($request);
    $self->log_and_die('Failed') unless $response;

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
        data => [],
    };

    return $request;
}

1;
