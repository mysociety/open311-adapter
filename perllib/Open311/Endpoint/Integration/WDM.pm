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


sub parse_w3c_datetime {
    my ($self, $dt_string) = @_;

    $dt_string =~ s/\.\d+//;
    my $w3c = DateTime::Format::W3CDTF->new;
    my $dt = $w3c->parse_datetime($dt_string);

    return $dt;
}

sub post_service_request {
    my ($self, $service, $args) = @_;
    my $new_id = $self->get_integration->post_request($service, $args);

    my $request = $self->new_request(
        service_request_id => $new_id,
    );

    return $request;
}

sub post_service_request_update {
    my ($self, $args) = @_;

    my $status = lc $args->{status};

    if ($status) {
        $args->{status} = $status;
    }

    my $response = $self->get_integration->post_update($args);

    return Open311::Endpoint::Service::Request::Update::mySociety->new(
        status => lc $args->{status},
        service_request_id => $args->{service_request_id},
        update_id => $response->{update_id},
        updated_datetime => $response->{update_time},
    );
}

sub get_service_request_updates {
    my ($self, $args) = @_;
    my $updates = $self->get_integration->get_updates({ start_date => $args->{start_date}, end_date => $args->{end_date} });

    my @updates;

    for my $update ( @$updates ) {
        my $service_request_id = $update->{EXTERNAL_SYSTEM_REFERENCE};
        $service_request_id =~ s/\s*$//;
        # ignore non FMS references
        next unless $service_request_id =~ /^\d+$/;
        my $customer_reference = $update->{ENQUIRY_REFERENCE};
        $customer_reference =~ s/\s*$//;
        push @updates, Open311::Endpoint::Service::Request::Update::mySociety->new(
            status => lc $update->{STATUS},
            update_id => $update->{UpdateID},
            service_request_id => $service_request_id,
            customer_reference => $customer_reference,
            description => $update->{COMMENTS},
            updated_datetime => $self->parse_w3c_datetime($update->{UPDATE_TIME}),
        );
    }

    return @updates;
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
