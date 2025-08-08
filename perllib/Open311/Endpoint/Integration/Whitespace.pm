=head1 NAME

Open311::Endpoint::Integration::Whitespace - An integration with the Whitespace backend

=head1 SYNOPSIS

This integration lets us post reports (via the CreateWorksheet API) to Whitespace.
There is no way to fetch updates, these are instead pushed to us by Whitespace.

=cut

package Open311::Endpoint::Integration::Whitespace;

use v5.14;

use Moo;
use Integrations::Whitespace;
use Open311::Endpoint::Service::UKCouncil::Whitespace;
use Open311::Endpoint::Service::Request::Update::mySociety;
use JSON::MaybeXS;

extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Open311::Endpoint::Role::ConfigFile';
with 'Role::EndpointConfig';
with 'Role::Logger';

has jurisdiction_id => ( is => 'ro' );

has category_mapping => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{category_mapping} }
);

has service_class  => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::UKCouncil::Whitespace',
);

has integration_class => (is => 'ro', default => 'Integrations::Whitespace');

has whitespace => (
    is => 'lazy',
    default => sub { $_[0]->integration_class->new(config_filename => $_[0]->jurisdiction_id) },
);

sub get_integration {
    $_[0]->log_identifier($_[0]->jurisdiction_id);
    return $_[0]->whitespace;
}

sub services {
    my ($self) = @_;

    my $services = $self->category_mapping;

    my @services = map {
        my $service = $services->{$_};
        my $name = $service->{name};

        $self->service_class->new(
            service_name => $name,
            service_code => $_,
            description => $name,
            keywords => ['waste_only'],
            $service->{group} ? (group => $service->{group}) : (),
            $service->{groups} ? (groups => $service->{groups}) : (),
        );
    } sort keys %$services;

    return @services;
}

sub post_service_request {
    my ($self, $service, $args) = @_;

    $self->logger->info("post_service_request(" . $service->service_code . ")");
    $self->logger->debug("post_service_request arguments: " . encode_json($args));

    my $integration = $self->get_integration;

    $args->{attributes}{quantity} ||= 1;

    my $service_item_name = $args->{attributes}->{service_item_name};
    $service_item_name = 'bulky' if $args->{service_code} eq 'bulky_collection';

    my $worksheet_id = $integration->CreateWorksheet({
        service_code => $args->{service_code},
        uprn => $args->{attributes}->{uprn},
        service_item_name => $service_item_name,
        worksheet_reference => $args->{attributes}->{fixmystreet_id},
        worksheet_message => $self->_worksheet_message($args),

        # Report/request
        assisted_yn => $args->{attributes}->{assisted_yn},
        location_of_containers => $args->{attributes}->{location_of_containers},

        # Request
        location_of_letterbox => $args->{attributes}->{location_of_letterbox},
        quantity => $args->{attributes}->{quantity},

        # Bulky
        bulky_parking => $args->{attributes}->{bulky_parking},
        bulky_location => $args->{attributes}->{bulky_location},
        round_instance_id => $args->{attributes}->{round_instance_id},
        collection_date => $args->{attributes}->{collection_date},
        bulky_items => [ split /::/, $args->{attributes}->{bulky_items} || '' ],
    });

    my $request = $self->new_request(
        service_request_id => $worksheet_id,
    );

    return $request;
}

sub post_service_request_update {
    my ($self, $args) = @_;

    if ($args->{description} =~ m/^Booking cancelled/) {
        $self->get_integration->CancelWorksheet({
            worksheet_id => $args->{service_request_id}
        });
    }
    my $update_id = 'BLANK';
    return Open311::Endpoint::Service::Request::Update::mySociety->new(
        status => lc $args->{status},
        update_id => $update_id,
    );
}

sub _worksheet_message {
    my ($self, $args) = @_;

    return $args->{description};
}

=head2 get_service_request_updates

This is not possible, so we have a blank function in order to not error when
used as part of a Multi integration.

=cut

sub get_service_request_updates { }

1;
