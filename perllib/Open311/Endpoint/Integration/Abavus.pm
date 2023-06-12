=head1 NAME

Open311::Endpoint::Integration::Abavus - An integration with the Abavus CRM system

=head1 SYNOPSIS

This integration lets us post reports to the Abavus CRM and fetch updates on those reports.
It calls Abavus reports serviceRequests.

=head1 CONFIGURATION

Abavus has its api detailed on SwaggerHub https://app.swaggerhub.com/apis/iTouchVisionLimited/api/8.0.6

=cut

package Open311::Endpoint::Integration::Abavus;

use Moo;
use DateTime::Format::W3CDTF;
use JSON::MaybeXS;
use Types::Standard ':all';
use DateTime;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Open311::Endpoint::Role::ConfigFile';

with 'Role::Logger';

use Integrations::Abavus;
use Open311::Endpoint::Service::Attribute;
use Open311::Endpoint::Service::Request::Update::mySociety;

=head1 DESCRIPTION

=head2 jurisdiction_id

Has the jurisdiction_id for matching reports to abavus

=cut

has jurisdiction_id => (
    is => 'ro',
);

=head2 integration_class

Set the core class for integrating with Abavus

=cut

has integration_class => (
    is => 'ro',
    default => 'Integrations::Abavus'
);

=head2 abavus

Set the abavus config file as 'abavus'

=cut

has abavus => (
    is => 'lazy',
    default => sub { $_[0]->integration_class->new(config_filename => $_[0]->jurisdiction_id) }
);

=head2 service_list

This is a mapping of Abavus services to use for categories populating FMS

=cut

has service_list => (
    is => 'ro',
);

=head2 service_code_fields

This is a mapping of the fields required for a new service request from the FMS to the
Abavus ones, which are different for every category

=cut

has service_code_fields => (
    is => 'ro',
);

=head2 service_class

Subclasses can override this to provide their own custom Service class, e.g.
if they want to have extra attributes on all services. We use the
UKCouncil class

=cut

has service_class  => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::UKCouncil'
);

=head2 service_extra_data

This is a mapping of extra questions to be added to FMS and mapped to a service
request in abavus

=cut

has service_extra_data => (
    is => 'ro',
);

=head2 get_integration

Set the integration as Abavus

=cut

sub get_integration {
    return $_[0]->abavus;
};

=head2 services

This returns a list of Abavus categories as defined in the configuration file.

=cut

sub services {
    my $self = shift;
    my @services = ();
    for my $group (sort keys %{ $self->service_list }) {
        my $servicelist = $self->service_list->{$group};
        for my $subcategory (sort keys %{ $servicelist }) {
            my $code = $subcategory;
            my $name = $servicelist->{$code};
            my %service = (
                service_name => $name,
                description => $name,
                service_code => $code,
                group => $group,
            );
            my $o311_service = $self->service_class->new(%service);

            my $data = $self->service_extra_data->{$code};
            foreach (@$data) {
                push @{$o311_service->attributes}, Open311::Endpoint::Service::Attribute->new(%$_);
            }
            push @services, $o311_service;
        }
    }

    return @services;
}

sub post_service_request {
    my ($self, $service, $args) = @_;

    my $now = DateTime->now(time_zone => 'Europe/London');

    my $serviceRequest = {
        'serviceRequest' => {
            'personNumber' => '1540991', # Default person given by Abavus. May need to check with Bucks
            'languageCode' => 'EN',
            'submissionDate' => sprintf( '%02d', $now->day) . '-' . uc($now->month_abbr) . '-' . $now->year . ' ' . $now->hms, # example date: 21-APR-2023 13:06:00
            'catalogue' => {
                'code' => 'FIX_MY_STREET_2323_F'
            },
            'xReferences' => {
                'xReference' => {}
            },
            'status' => 'FMS_-_OPEN_8402_S', # OPEN_8189_S in example but now using tech spec code
            'location' => {
                'latitude' => $args->{lat},
                'longitude' => $args->{long},
            },
            'form' => {
                'code' => $args->{service_code}
            },
        }
    };

    my $response = $self->abavus->api_call(
        call => 'serviceRequest',
        body => $serviceRequest
    );

    if ($response->{result}) {
        $self->abavus->api_call(
            call => 'serviceRequest/integrationReference/' . $response->{id}
            . '?reference=' . $args->{attributes}{fixmystreet_id}
            . '&systemCode=FMS',
            method => 'PUT'
        );
        $args->{full_name} = $args->{first_name} . ' ' . $args->{last_name};
        $args->{fixmystreet_id} = $args->{attributes}{fixmystreet_id};
        $args->{title} = $args->{attributes}{title};
        $args->{photos} = scalar $args->{media_url} ? join( ",", @{ $args->{media_url} } ) : '';
        $self->add_question_responses($response->{id}, $args);
    }

    if ($response->{result}) {
        return $self->new_request(
        service_request_id => $response->{id}
    )};
}

sub add_question_responses {
    my ($self, $report_id, $args) = @_;

    my $fields = $self->service_code_fields->{$args->{service_code}};
    for my $field (keys %$fields) {
        my $response = $self->abavus->api_call(
            call => 'serviceRequest/questions/' . $report_id
                . '?questionCode=' . $fields->{$field}
                . '&answer=' . $args->{$field},
            method => 'POST',
        );
    };

    my $extra_fields = $self->service_extra_data->{$args->{service_code}};

    for (@$extra_fields) {
        if ($args->{attributes}->{$_->{code}}) {
            my $response = $self->abavus->api_call(
                call => 'serviceRequest/questions/' . $report_id
                    . '?questionCode=' . $_->{code}
                    . '&answer=' . $args->{attributes}{$_->{code}},
                method => 'POST',
            );
        }
    }
}

1;
