=head1 NAME

Open311::Endpoint::Integration::Cams - An integration with the CAMS Public Right of Way system

=head1 SYNOPSIS

This integration lets us post reports to the CAMS CRM and fetch status changes on those reports.

=head1 CONFIGURATION

We received an API list from CAMS

=cut

package Open311::Endpoint::Integration::Cams;

use Moo;

extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::ConfigFile';

use Data::UUID;
use Integrations::Rest;
use MIME::Base64 qw(encode_base64);

=head2 jurisdiction_id

Has the jurisdiction_id for matching reports to cams

=cut

has jurisdiction_id => (
    is => 'ro',
);

=head2 integration_class

Set the core class for integrating with Cams

=cut

has integration_class => (
    is => 'ro',
    default => 'Integrations::Rest'
);

=head2 cams

Instantiate the configuartion as cams.

The REST integration requires a 'caller' for identifying logging messages
and we are setting the optional allow_nonref as the webtracking number
is returned as a string

=cut

has cams => (
    is => 'lazy',
    default => sub { $_[0]->integration_class->new(
        config_filename => $_[0]->jurisdiction_id,
        caller => 'CAMS',
        allow_nonref => 1
    ) }
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

=head2 userId and access_token

Some API calls must pass a token in the .aspxauth header and the userid in the endpoint.

This is set by sending login credentials to the login endpoint and retrieving the userid and access_token

=cut

has access_token => (
    is => 'rw',
);

has userId => (
    is => 'rw',
);

=head2 service_list

This is a mapping of CAMS services to use for categories populating FMS. CAMS Desktop does
not require the service code returning, so I've removed the slash from the service code they
have as it fails our validation for a legitimate service code

=cut

has service_list => (
    is => 'ro',
);

=head2 service_extra_data

This is a mapping of CAMS attributes. All questions should
have hidden fields for data from the PROW assets layer

=cut

has service_extra_data => (
    is => 'ro',
);

=head2 service_class

Subclasses can override this to provide their own custom Service class, e.g.
if they want to have extra attributes on all services. We use the
UKCouncil class as need the Easting and Northing

=cut

has service_class  => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::UKCouncil'
);

=head2 api_calls

Mapping of keys to api call strings

=cut

has api_calls => (
    is => 'ro',
);

=head2 get_integration

Set the integration as 'cams'

=cut

sub get_integration {
    return $_[0]->cams;
};

=head2 services

This returns a list of CAMS categories as defined in the configuration file.

It adds hidden fields for all categories to accomodate data expected from the
PROW asset layers.

For the FMS category name will use the second index of the service_name if it exists which should
be a friendly name, otherwise will use the default provided by CAMS Desktop

=cut

sub services {
    my $self = shift;

    my @services = ();
    for my $group (sort keys %{ $self->service_list }) {
        my $servicelist = $self->service_list->{$group};
        for my $id (sort keys %{ $servicelist }) {
            my $code = $id;
            my $name = $servicelist->{$id}->{'service_name'}[1] || $servicelist->{$id}->{'service_name'}[0];
            my %service = (
                service_name => $name,
                description => $name,
                service_code => $code,
                group => $group,
            );
            my $o311_service = $self->service_class->new(%service);

            my $data = $self->service_extra_data;
            foreach (@$data) {
                $_->{datatype} = 'string';
                $_->{automated} = 'hidden_field';
                push @{$o311_service->attributes}, Open311::Endpoint::Service::Attribute->new(%$_);
            }
            push @services, $o311_service;
        }
    }

    return @services;
}

=head2 do_login

Prior to calls requiring authorisation we need to log in and set the userId and access_token

=cut

sub do_login {
    my $self = shift;

    my $user_details = $self->cams->api_call(
        (
            call => $self->api_calls->{login},
            method => 'POST',
            headers => {
                content_length => '0',
                username => $self->username,
                password => $self->password,
            }
        )
    );

    $self->access_token($user_details->{access_token});
    $self->userId($user_details->{userId});
};

=head2 post_service_request

Authorise with the login so we can send an authorisation token and
create and post the json fields

=cut

sub post_service_request {
    my ($self, $service, $args) = @_;

    $self->do_login;

    my $TypeDescr;
    for my $category (keys %{ $self->service_list }) {
        for my $id (keys %{ $self->service_list->{$category}}) {
            if ($id eq $args->{service_code}) {
                $TypeDescr = $self->service_list->{$category}->{$id}->{service_name}[0];
                last;
            }
        }
    }

    my $serviceRequest = {
        'Info' => {
            TypeDescr => $TypeDescr,
            StatusDescr => 'Unresolved',
        },
        'Maint' => {
            Location => $args->{attributes}->{title},
            Problem => $args->{attributes}->{description},
            Easting => $args->{attributes}->{easting},
            Northing => $args->{attributes}->{northing},
            AdminArea => $args->{attributes}->{AdminArea},
            LinkCode => $args->{attributes}->{LinkCode},
            LinkType => $args->{attributes}->{LinkType},
        }
    };

    my $ug = Data::UUID->new;
    my $uuid = $ug->to_string($ug->create());
    my $response = $self->cams->api_call(
        call => $self->api_calls->{insert} . $uuid,
        body => $serviceRequest,
        headers => { '.aspxauth' => $self->access_token }
    );

    if ($response) {
        $self->_add_service_request_images($uuid, $args->{media_url}) if $args->{media_url}->[0] && $args->{media_url}->[0];
        return $self->new_request(
            service_request_id => $response
        )
    }
}

=head2 _add_service_request_images

Images for a service request are uploaded separately using the UID
generated to submit the service request in the path.

=cut

sub _add_service_request_images {
    my ($self, $uuid, $media_urls) = @_;

    my @attachments = map {
        my $content_type = $_->content_type ? $_->content_type : 'image/jpeg';
        {
            content_type => $content_type,
            body => 'data:' . $content_type . ';base64,' . encode_base64($_->content),
        }
    } $self->_get_attachments($media_urls);

    $self->do_login;

    for my $image (@attachments) {
        my $response = $self->cams->api_call(
            call => $self->api_calls->{'upload_files'} . $uuid,
            headers => { '.aspxauth' => $self->access_token },
            body => $image->{body},
            content_type => $image->{content_type},
        );
    }

    return;
}

=head2 _get_attachments

Fetch attachements from FMS for a report. Will only work for
public reports.

Straight copy from ATAK - may need to start a utils role.

=cut

sub _get_attachments {
    my ($self, $urls) = @_;

    my @photos = ();
    my $ua = LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter");
    for (@$urls) {
        my $response = $ua->get($_);
        if ($response->is_success) {
            push @photos, $response;
        } else {
            $self->logger->error("[CAMS] Unable to download attachment: " . $_);
            $self->logger->debug("[CAMS] Photo response status: " . $response->status_line);
            $self->logger->debug("[CAMS] Photo response content: " . $response->decoded_content);
        }
    }
    return @photos;
}

1;
