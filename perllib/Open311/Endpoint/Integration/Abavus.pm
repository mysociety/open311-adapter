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
use Path::Tiny;
use DateTime::Format::W3CDTF;
use JSON::MaybeXS;
use Types::Standard ':all';
use URI::Escape;
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

=head2 anonymous_user

The user id to make reports against

=cut

has anonymous_user => (
    is => 'ro',
);

=head2 anonymous_user_updates

The user id to make updates against

=cut

has anonymous_user_updates => (
    is => 'ro',
);

=head2 catalogue_code

The Abavus catalogue code

=cut

has catalogue_code => (
    is => 'ro',
);

=head2 reverse_status_mapping

Map of Abavus status codes as keys to FMS codes as values

=cut

has reverse_status_mapping => (
    is => 'ro',
);

=head2 update_store

Directory for storing updates retrieved from Abavus as a record because /event/status is cleared once called

=cut

has update_store => (
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
                my $attr = { %$_ };
                if ($_->{values}) {
                    $attr->{values} = { map { $_ => $_ } @{$_->{values}} };
                }
                push @{$o311_service->attributes}, Open311::Endpoint::Service::Attribute->new(%$attr);
            }
            push @services, $o311_service;
        }
    }

    return @services;
}

sub post_service_request {
    my ($self, $service, $args) = @_;

    my $now = DateTime->now(time_zone => 'Europe/London');

    my $status;
    foreach (keys %{$self->reverse_status_mapping}) {
        if ('open' eq $self->reverse_status_mapping->{$_}) {
            $status = $_;
            last;
        }
    }

    my $serviceRequest = {
        'serviceRequest' => {
            'personNumber' => $self->anonymous_user,
            'languageCode' => 'EN',
            'submissionDate' => sprintf( '%02d', $now->day) . '-' . uc($now->month_abbr) . '-' . $now->year . ' ' . $now->hms, # example date: 21-APR-2023 13:06:00
            'catalogue' => {
                'code' => $self->catalogue_code,
            },
            'xReferences' => {
                'xReference' => {}
            },
            'status' => $status,
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
        foreach (qw/fixmystreet_id title description/) {
            $args->{$_} = $args->{attributes}->{$_};
        }
        $args->{photos} = scalar $args->{media_url} ? join( " ", @{ $args->{media_url} } ) : '';
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
                . '?questionCode=' . uri_escape($fields->{$field})
                . '&answer=' . uri_escape($args->{$field}),
            method => 'POST',
        );
    };

    my $extra_fields = $self->service_extra_data->{$args->{service_code}};

    for (@$extra_fields) {
        if ($args->{attributes}->{$_->{code}}) {
            my $response = $self->abavus->api_call(
                call => 'serviceRequest/questions/' . $report_id
                    . '?questionCode=' . uri_escape($_->{code})
                    . '&answer=' . uri_escape($args->{attributes}{$_->{code}}),
                method => 'POST',
            );
        }
    }
}

sub post_service_request_update {
    my ($self, $args) = @_;

    if ($args->{media_url}->[0]) {
        $args->{description} .= "\n\n[ This update contains a photo, see: " . $args->{media_url}->[0] . " ]";
    }

    my $w3c = DateTime::Format::W3CDTF->new;
    my $time = $w3c->parse_datetime($args->{updated_datetime});

    my $response = $self->abavus->api_call(
        call => "serviceRequest/notes/" . $args->{service_request_id},
        body => {
            userNumber => $self->anonymous_user_updates,
            otherSystemCode => "FMS",
            otherSytemUserID => "FMS",
            type => "FIX_MY_STREET_UPDATE",
            title => 'Update from FixMyStreet',
            content => $args->{description},
            notify => "N",
            creationDate => $time->strftime('%d-%m-%Y'),
            allowDuplicate => "Y",
        },
    );

    if ($response->{result}) {
        return Open311::Endpoint::Service::Request::Update::mySociety->new(
            service_request_id => $args->{service_request_id},
            status => lc $args->{status},
            update_id => $response->{id},
        );
    }
}

sub get_service_request_updates {
    my ($self, $args) = @_;

    my $fetched_updates = $self->abavus->api_call(call => 'serviceRequest/event/status');
    if ($fetched_updates->{message} eq 'No Events Found') {
        return ();
    }
    $self->_save_updates($fetched_updates);
    my @updates;
    for my $update (@{$fetched_updates->{serviceEvents}}) {
        my $ext_status = $update->{ServiceEvent}->{objectCode};
        my $fixmystreet_id;
        ($fixmystreet_id = $update->{ServiceEvent}->{otherSystemID}) =~ s/FMS//;
        if ($self->reverse_status_mapping->{$ext_status}) {
            my %update_args = (
                status => $self->reverse_status_mapping->{$ext_status},
                fixmystreet_id => $fixmystreet_id,
                external_status_code => $ext_status,
                description => '',
                update_id => $update->{ServiceEvent}->{guid},
                service_request_id => $update->{ServiceEvent}->{number},
            );
            push @updates, Open311::Endpoint::Service::Request::Update::mySociety->new( %update_args );
        } else {
            $self->logger->warn("external_status_code $ext_status has unmapped status: $ext_status");
        };
    };

    return @updates;
}

sub _save_updates {
    my ($self, $updates) = @_;

    my $dir = $self->update_store;
    path($dir)->mkpath;

    for my $update (@{$updates->{serviceEvents}}) {
        my $base = $update->{ServiceEvent}->{guid};
        path($dir)->child(time() . "-$base" . '.json')->spew_raw(encode_json($update));
    }
}

1;
