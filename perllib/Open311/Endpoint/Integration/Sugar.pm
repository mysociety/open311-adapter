=head1 NAME

Open311::Endpoint::Integration::Sugar - An integration with the Sugar CRM system

=head1 SYNOPSIS

This integration lets us populate categories, send reports to the Sugar CRM system
#, fetch updates on cases, send updates to cases and fetch reports

=cut

package Open311::Endpoint::Integration::Sugar;

use Moo;

extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Open311::Endpoint::Role::ConfigFile';

use Integrations::Rest;
use DateTime::Format::W3CDTF;
use Open311::Endpoint::Service::Request::ExtendedStatus;
use Open311::Endpoint::Service::Request::Update::mySociety;
use Open311::Endpoint::Service::UKCouncil::Canals;

=head2 jurisdiction_id

Has the jurisdiction_id for matching reports to sugar

=cut

has jurisdiction_id => (
    is => 'ro',
);

=head2 integration_class

Set the core class for integrating with Sugar

=cut

has integration_class => (
    is => 'ro',
    default => 'Integrations::Rest'
);

=head2 sugar

Instantiate the configuration as sugar.

The REST integration requires a 'caller' for identifying logging messages

=cut

has rest => (
    is => 'lazy',
    default => sub { $_[0]->integration_class->new(
        config_filename => $_[0]->jurisdiction_id,
        caller => 'Sugar',
    ) }
);

=head2 api_calls

Mapping of keys to api call strings

=cut

has api_calls => (
    is => 'ro',
);

=head2 username and password

Login username and password required to get an access token

=cut

has username => (
    is => 'ro',
);

has password => (
    is => 'ro',
);

has client_id => (
    is => 'ro',
);

=head2 access_token

API calls must pass an access_token which is fetched using the username and password.
It lasts an hour which should be enough for the lifetime of open311 requests so
no need to save the refresh token

=cut

has access_token => (
    is => 'rw',
);

=head2 crm_user_id

Owner id of incidents created by FMS

=cut

has crm_user_id => (
    is => 'ro',
);

has headers => (
    is => 'lazy',
    default => sub {{
        'accept' => 'application/json',
        'Authorization' => 'Bearer ' . $_[0]->access_token,
        'Content-Type' => 'application/json',
    }},
);

=head2 service_list

This is a mapping of Sugar services to use for categories populating FMS.

=cut

has service_list => (
    is => 'ro',
);

=head2 service_extra_data

This is a mapping of Sugar attributes. Most categories
will have an  asset_id and some have extra questions

=cut

has service_extra_data => (
    is => 'ro',
);

has '+request_class' => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::Request::ExtendedStatus',
);

=head2 category_mapping

This is a mapping of the FMS category or group
to the Sugar CRM value for the category

=cut

has 'category_mapping' => (
    is => 'ro',
);

=head2 reverse_status_mapping

This is a mapping of statuses from Sugar to FMS

=cut

has reverse_status_mapping => (
  is => 'ro',
);

=head2 service_class

Subclasses can override this to provide their own custom Service class, e.g.
if they want to have extra attributes on all services.

=cut

has service_class  => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::UKCouncil::Canals',
);

=head2 get_integration

Set the integration as 'sugar' which is a Rest integration

=cut

sub get_integration {
    return $_[0]->rest;
};

sub services {
    my $self = shift;

    my @services = ();
    for my $service_code (sort keys %{ $self->service_list }) {
        my $name = $self->service_list->{$service_code}{name};
        my $group = $self->service_list->{$service_code}{group};
        my %service = (
                service_name => $name . ' (CRT: ' . $group . ')',
                description => $name,
                service_code => $service_code,
                group => $group,
            );
        my $o311_service = $self->service_class->new(%service);
        my $extra = $self->service_list->{$service_code}{service_extra_data};
        foreach (@$extra) {
            $_->{datatype} = 'singlevaluelist';
            push @{$o311_service->attributes}, Open311::Endpoint::Service::Attribute->new(%$_);
        }
        push @services, $o311_service;
    }
    return @services;
}

=head2 do_login

Prior to calls requiring authorisation we need to log in and set the access_token

=cut

sub _do_login {
    my $self = shift;

    my $user_details = $self->rest->api_call(
            call => $self->api_calls->{login},
            method => 'POST',
            body => {
                grant_type => 'password',
                platform => 'mobile',
                username => $self->username,
                password => $self->password,
                client_id => $self->client_id,
            }
    );

    $self->access_token($user_details->{access_token});
};

=head2 post_service_request

Authorise with the login so we can get an authorisation token
for posting the report.

There are two postings to Sugar - one an Incident and one a
Case.

We also need to find/create a user id to go with the Case

=cut

sub post_service_request {
    my ($self, $service, $args) = @_;

    $args->{attributes}{group} = $self->category_mapping->{$service->group};
    $args->{attributes}{category} = $self->category_mapping->{$service->description};

    $self->_do_login;
    my $incident_id = $self->_create_incident($args);
    my $case_id = $self->_create_case($args, $incident_id);

    return $self->new_request(
                              service_request_id => "$incident_id--$case_id",
                             );
};

sub _create_incident {
    my ($self, $args) = @_;

    my %defaults = (
                    resolution => 'Accepted',
                    type => 'Administration',
                    status => 'New',
                    priority => '',
                   );
    my $description = $args->{attributes}->{description};
    my $extra_list = $self->service_list->{ $args->{service_code} }->{service_extra_data} || [];
    for my $question (@$extra_list) {
        if ( $args->{attributes}->{ $question->{code} } ) {
            $description .= "\n\n" . $question->{datatype_description} . ': ' . $args->{attributes}->{ $question->{code} };
        }
    };
    my $serviceRequest = {
                          %defaults,
                          fms_category => $args->{attributes}{group},
                          fms_subcategory => $args->{attributes}{category},
                          location_description => $args->{attributes}->{nearest_address},
                          name => $args->{attributes}->{title},
                          description => $description,
                          latitude => $args->{lat}, # as float
                          longitude => $args->{long}, # as float
                          original_fms_id => $args->{attributes}->{fixmystreet_id},
                          latest_fms_id => $args->{attributes}->{fixmystreet_id},
                          fms_public_url => $args->{attributes}->{report_url},
                          media_url => $args->{media_url}->[0] ? join(',', @{ $args->{media_url} }) : '',
                         };

    my $response = $self->rest->api_call(
                                          call => $self->api_calls->{incidents},
                                          headers => $self->headers,
                                          body => $serviceRequest,
                                         );

    return $response->{id};
}

sub _create_case {
    my ($self, $args, $incident_id) = @_;

    my $primary_contact_id = $self->_get_user(
                                              first_name => $args->{first_name},
                                              last_name => $args->{last_name},
                                              email => $args->{email},
                                             );
    my %defaults = (
                     'type' => 'General Query',
                     'crt_l1_contact_purpose_c' => 'operational_issue_reporting',
                     'crt_l2_reason_c' => 'navigation_asset',
                     'source' => 'FixMyStreet',
                     'priority' => '',
                    );

    my $serviceRequest = {
                          %defaults,
                          name => $args->{attributes}->{title},
                          description => $args->{attributes}->{description},
                          primary_contact_id => $primary_contact_id,
                          crt_location_description_c => '', #nearest_address?
                         };

    my $call = $self->api_calls->{case};
    $call =~ s/{incident ID}/$incident_id/;

    my $response = $self->rest->api_call(
                                          call => $call,
                                          headers => $self->headers,
                                          body => $serviceRequest,
                                         );
    return $response->{related_record}->{id};
}

=head2 _get_user

We need a primary contact id from Sugar to log a case.

If there are multiple users returned, it's an error but contains required data,
so we need to deal with an error response.

=cut

sub _get_user {
    my ($self, %args) = @_;
    $self->rest->return_json_error(1);
    my $response = $self->rest->api_call(
                                          call => $self->api_calls->{contact},
                                          headers => $self->headers,
                                          body => {
                                                   first_name => $args{first_name},
                                                   last_name => $args{last_name},
                                                   email1 => $args{email},
                                                  },
                                        );
    $self->rest->return_json_error(0);
    return $response->{id} if $response->{id};
    return shift(@{$response->{contacts}}) if $response->{contacts}; # Actually, this is just ids I think

    # Revisit and make the error logging a part of Rest.pm
    $self->rest->logger->error('Caught error');
    $self->rest->logger->error($response);
}

sub get_service_requests {
    my ($self, $args) = @_;

    if (!$args->{start_date}) {
        $args->{start_date} = DateTime->now->set_time_zone('Europe/London') - DateTime::Duration->new( days => 1 );
    };

    if (!$args->{end_date}) {
        $args->{end_date} = DateTime->now->set_time_zone('Europe/London');
    }

    $self->_do_login;
    my $filter = _generate_filter(
                  '[modified_user_id][$not_equals]=' . $self->{crm_user_id},
                  '[date_modified][$gte]=' . (DateTime::Format::W3CDTF->parse_datetime($args->{start_date})),
                  '[date_modified][$lte]=' . (DateTime::Format::W3CDTF->parse_datetime($args->{end_date})),
                  '[publish_on_fms_c][$equals]=' . 1,
                 );

    my $response = $self->rest->api_call(
                                         call => $self->api_calls->{incidents} . $filter,
                                         headers => $self->headers,
                                        );

    my @reports;
    for my $incident (@{ $response->{records} }) {
        my $date = DateTime::Format::W3CDTF->parse_datetime($incident->{date_entered});
        my $service_code = $self->_lookup_service_code($incident->{fms_category}, $incident->{fms_subcategory});

        push @reports, $self->new_request(
                                          service => $self->service($service_code),
                                          status => $self->reverse_status_mapping->{ $incident->{status} },
                                          service_request_id => $incident->{id},
                                          title => $incident->{name},
                                          description => $incident->{description},
                                          updated_datetime => $date,
                                          requested_datetime => $date,
                                          latlong => [$incident->{latitude}, $incident->{longitude}],
                                         );

    }

    return @reports;
}

sub get_service_request_updates {
    my ($self, $args) = @_;

    if (!$args->{start_date}) {
        $args->{start_date} = DateTime->now->set_time_zone('Europe/London') - DateTime::Duration->new( days => 1 );
    };

    if (!$args->{end_date}) {
        $args->{end_date} = DateTime->now->set_time_zone('Europe/London');
    }

    $self->_do_login;
    my $filter = _generate_filter
      (
       '[last_sync_date][$gte]=' . (DateTime::Format::W3CDTF->parse_datetime($args->{start_date})),
       '[last_sync_date][$lte]=' . (DateTime::Format::W3CDTF->parse_datetime($args->{end_date})),
      );

    my $response = $self->rest->api_call
      (
       call => $self->api_calls->{incidents} . $filter,
       headers => $self->headers,
      );

    my @updates;
    foreach my $update (@{ $response->{records} }) {
        my $date = DateTime::Format::W3CDTF->parse_datetime($update->{last_sync_date});
        (my $update_id_formatted = $date) =~ s/://g;
        my $service_code = $self->_lookup_service_code($update->{fms_category}, $update->{fms_subcategory});

        my %args = (
            status => $self->reverse_status_mapping->{ $update->{status} },
            external_status_code => $update->{status},
            fixmystreet_id => $update->{original_fms_id},
            update_id => $update_id_formatted,
            service_request_id => $service_code,
            description => "",
            updated_datetime => $date,
                   );
        push @updates, Open311::Endpoint::Service::Request::Update::mySociety->new( %args );
    }
    return @updates;
}

sub _lookup_service_code {
    my ($self, $category, $group) = @_;

    my ($service) = grep { $_->description eq $category && $_->group eq $group } $self->services;

    return $service->service_code;
}

sub _generate_filter {
    my @filter = @_;

    my $filter = '?';
    my $count = 0;
    for my $arg (@filter) {
        $filter .= 'filter[' . $count . ']' . $arg . "&";
        $count++;
    };
    chop $filter;

    return $filter;
}

1;
