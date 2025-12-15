=head1 NAME

Open311::Endpoint::Integration::Aurora - An integration with Symology's Aurora platform.

=head1 SYNOPSIS

This integration:
* Creates cases for requests.
* Makes updates on the relevant cases.
* Fetches udpates on relevant cases.

=cut

package Open311::Endpoint::Integration::Aurora;

use strict;
use warnings;

use Moo;
use Integrations::Aurora;
use Open311::Endpoint::Service::UKCouncil::Aurora;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Role::EndpointConfig';
with 'Role::Logger';

=head1 CONFIGURATION

=cut

has integration_class => (is => 'ro', default => 'Integrations::Aurora');

has aurora => (
    is => 'lazy',
    default => sub { $_[0]->integration_class->new(config_filename => $_[0]->jurisdiction_id) },
);

sub get_integration {
    return $_[0]->aurora;
};

=head2 service_class

Uses the same service class as our Symology Insight integration.

=cut

has service_class  => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::UKCouncil::Aurora'
);

has jurisdiction_id => ( is => 'ro' );

=head2 category_mapping

A map from service_code to:

  name: The display name for the category
  group: Optional category group
  parameters: dictionary of default parameters to use

=cut

has category_mapping => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{category_mapping} }
);

=head1 BEHAVIOUR

=head2 services

Returns services based on the configured C<category_mapping>.

=cut

sub services {
    my $self = shift;
    my $services = $self->category_mapping;
    my @services = map {
        my $name = $services->{$_}{name};
        my $service = $self->service_class->new(
            service_name => $name,
            service_code => $_,
            description => $name,
            $services->{$_}{group} ? (group => $services->{$_}{group}) : (),
        );
    } keys %$services;
    return @services;
}

=head2 post_service_request

Creates a contact if one doesn't already exist for the reporter's email.
Uploads media provided as uploads or URLs as attachments.
Creates a case using these and also the default parameters set in
the C<category_mapping>.
Calls C<populate_description> for description text.

=cut

sub post_service_request {
    my ( $self, $service, $args ) = @_;

    my $service_code = $args->{service_code};
    my $category = $self->category_mapping->{$service_code};
    my $payload = $category->{parameters} || {};
    $payload->{easting} = $args->{attributes}->{easting};
    $payload->{northing} = $args->{attributes}->{northing};
    $payload->{usrn} = $args->{attributes}->{NSGRef};
    $payload->{internalAssetId} = $args->{attributes}->{UnitID};
    $payload->{externalReference} = "FMS" . $args->{attributes}->{fixmystreet_id};

    $payload->{description} = $args->{description};
    if ($args->{address_string}) {
        $payload->{description} .= "\n\nLocation query entered: " . $args->{address_string};
    }
    if ($args->{attributes}->{report_url}) {
        $payload->{description} .= "\n\nView report on FixMyStreet: $args->{attributes}->{report_url}";
    }


    my $email = $args->{email};
    my $contact_id = $self->aurora->get_contact_id_for_email_address($email);
    if (!$contact_id) {
        $contact_id = $self->aurora->create_contact_and_get_id(
            $email,
            $args->{first_name},
            $args->{last_name},
            $args->{phone},
        );
    }
    $payload->{contactId} = $contact_id;
    $payload->{attachments} = $self->_upload_media_as_attachments($args);

    my $case_number = $self->aurora->create_case_and_get_number($payload);
    return $self->new_request(
        service_request_id => $case_number
    );
}

=head2 post_service_request_update

TODO

=cut

sub post_service_request_update {
    my ( $self, $service, $args ) = @_;
    die "unimplemented";
}

=head2 get_service_request_updates

TODO

=cut

sub get_service_request_updates {
    my ( $self, $service, $args ) = @_;
    die "unimplemented";
}

sub _upload_media_as_attachments {
    my ( $self, $args ) = @_;
    my $attachment_ids = ();

    my $ua = LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter");
    foreach (@{$args->{media_url}}) {
        my $response = $ua->get($_);
        if ($response->is_success) {
            push @$attachment_ids,
                $self->aurora->upload_attachment_and_get_id($response->filename);
        } else {
            $self->logger->warn("Unable to download media " . $_);
        }
    }

    foreach (@{$args->{uploads}}) {
        push @$attachment_ids,
            $self->aurora->upload_attachment_and_get_id($_->filename);
    }

    return [ map { { "id" => $_ } } @$attachment_ids ];
}

1;
