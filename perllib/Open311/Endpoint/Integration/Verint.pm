package Open311::Endpoint::Integration::Verint;

use Moo;
use DateTime::Format::W3CDTF;
use Integrations::Verint;
use Tie::IxHash;
use Open311::Endpoint::Service::UKCouncil

extends 'Open311::Endpoint';
with 'Role::EndpointConfig';
with 'Role::Logger';

has jurisdiction_id => ( is => 'ro' );

has integration_class => (
    is => 'ro',
    default => 'Integrations::Verint',
);

sub post_service_request {
    my ($self, $service, $args) = @_;

    die "No such service" unless $service;
    my $date = DateTime->now();

    my $form_name = $self->endpoint_config->{service_data}->{$service->service_code}->{form_name};

    my $integ = $self->integration_class->new;

    my $res = $integ->CreateRequest($self->endpoint_config, $form_name,
        ixhash(
            'txt_request_open_date' => $date,
            'txta_additional_location' => $args->{attributes}->{title},
            'txta_problem' => $args->{attributes}->{description},
            'le_typekey' => $args->{service_code},
            'txt_cust_info_first_name' => $args->{first_name},
            'txt_cust_info_last_name' => $args->{last_name},
            'eml_cust_info_email' => $args->{email},
            'txt_map_usrn' => $args->{attributes}->{usrn},
            'txt_map_uprn' => $args->{attributes}->{uprn},
        )
    );

    my $parsed_response = SOAP::Deserializer->deserialize( $res );
    my $body = $parsed_response->body->{CreateResponse};

    if ($body->{status} eq 'success') {
        return $self->new_request(
            service_request_id => $body->{ref},
        )
    }
}

sub ixhash {
    tie (my %data, 'Tie::IxHash', @_);
    return \%data;
}

sub services {
    my $self = shift;

    my $services = $self->endpoint_config->{service_whitelist};

    my @services = map {
            my $name = $services->{$_}{name};
            my $service = Open311::Endpoint::Service::UKCouncil->new(
                service_name => $name,
                service_code => $_,
                description => $name,
                $services->{$_}{group} ? (group => $services->{$_}{group}) : (),
        );
        } sort keys %$services;

    return @services;
}

1;
