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

sub get_integration {
    my $self = shift;
    my $integ = $self->integration_class;
    $integ = $integ->on_fault(sub { my($soap, $res) = @_; die ref $res ? $res->faultstring : $soap->transport->status, "\n"; });
    $integ->want_som(1);
    $integ->config_filename($self->jurisdiction_id);
    return $integ;
}

sub post_service_request {
    my ($self, $service, $args) = @_;

    die "No such service" unless $service;
    my $date = DateTime->now();

    my $services = $self->endpoint_config->{service_whitelist};
    my $service_cfg = $services->{$service->service_code};

    my $integ = $self->get_integration;

    my $result = $integ->CreateRequest($service_cfg->{form_name},
        ixhash(
            # Location
            le_gis_lat => $args->{lat},
            le_gis_lon => $args->{long},
            txt_easting => $args->{attributes}->{easting},
            txt_northing => $args->{attributes}->{northing},
            txt_map_usrn => $args->{attributes}->{usrn},
            txt_map_uprn => $args->{attributes}->{uprn},
            # Metadata
            txt_request_open_date => $date->datetime . "Z",
            le_typekey => $service_cfg->{typekey},
            # Person
            txt_cust_info_first_name => $args->{first_name},
            txt_cust_info_last_name => $args->{last_name},
            eml_cust_info_email => $args->{email},
            tel_cust_info_phone => $args->{phone},
            # Report
            txta_problem => $args->{attributes}->{title},
            txta_problem_details => $args->{attributes}->{description},
        )
    );
    die "Failed" unless $result;
    $result = $result->method;
    die "Failed" unless $result;
    my $status = $result->{status};
    my $ref = $result->{ref};
    die "$status $ref" unless $status eq 'success';


    return $self->new_request(
        service_request_id => $ref,
    )
}

=head2 services

This returns a list of Verint services from the service_whitelist.

=cut

sub services {
    my $self = shift;

    my $services = $self->endpoint_config->{service_whitelist};

    my @services = map {
        my $cfg = $services->{$_};
        my $name = $cfg->{name};
        my $service = Open311::Endpoint::Service::UKCouncil->new(
            service_name => $name,
            service_code => $_,
            description => $name,
            $cfg->{group} ? (group => $cfg->{group}) : (),
            allow_any_attributes => 1,
        );
    } sort keys %$services;

    return @services;
}

sub ixhash {
    tie (my %data, 'Tie::IxHash', @_);
    return \%data;
}

1;
