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
use File::Temp qw(tempfile);
use Integrations::Aurora;
use Open311::Endpoint::Service::UKCouncil::Aurora;
use Try::Tiny;
use Open311::Endpoint::Service::Request::Update::mySociety;
use DateTime::Format::Strptime;

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

=head2 reverse_status_mapping

Table of statuses sent by Aurora and how they map to FMS statuses

=cut

has reverse_status_mapping => (
    is => 'ro',
    default => sub { $_[0]->endpoint_config->{reverse_status_mapping} }
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

Creates a contact if one doesn't already exist for the reporter's email, or phone number.
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

    $payload->{description} = $args->{attributes}->{title} . "\n\n" . $args->{attributes}->{description};
    if ($args->{address_string}) {
        $payload->{description} .= "\n\nLocation query entered: " . $args->{address_string};
    }
    if ($args->{attributes}->{report_url}) {
        $payload->{description} .= "\n\nView report on FixMyStreet: $args->{attributes}->{report_url}";
    }

    my $contact_id;
    my $email = $args->{email};
    my $phone = $args->{phone};
    if ($email) {
        $contact_id = $self->aurora->get_contact_id_for_email_address($email);
    }
    if (!$contact_id && $phone) {
        $contact_id = $self->aurora->get_contact_id_for_phone_number($phone);
    }
    if (!$contact_id) {
        $contact_id = $self->aurora->create_contact_and_get_id(
            $email,
            $args->{first_name},
            $args->{last_name},
            $phone,
        );
    }
    $payload->{contactId} = $contact_id;
    $payload->{attachments} = $self->_upload_media_as_attachments($args);

    # We have seen case creation fail the first time when an attachment is included
    # so always try once more in case of this or similar bugs.
    my $case_number;
    try {
        $case_number = $self->aurora->create_case_and_get_number($payload);
    } catch {
        $self->logger->error("First case create call failed with the following error, trying once more.\n" . $_);
        $case_number = $self->aurora->create_case_and_get_number($payload);
    };
    return $self->new_request(
        service_request_id => $case_number
    );
}

=head2 post_service_request_update

Adds a note to the case with the update text, with
any media also uploaded as attachments.

=cut

sub post_service_request_update {
    my ( $self, $args ) = @_;
    my $case_number = $args->{service_request_id};
    my $payload = {
        noteText => $args->{description},
    };
    $payload->{attachments} = $self->_upload_media_as_attachments($args);

    # We have seen add note fail the first time when an attachment is included
    # so always try once more in case of this or similar bugs.
    try {
        $self->aurora->add_note_to_case($case_number, $payload);
    } catch {
        $self->logger->error("First add note call failed with the following error, trying once more.\n" . $_);
        $self->aurora->add_note_to_case($case_number, $payload);
    };
    return Open311::Endpoint::Service::Request::Update->new(
        status => lc $args->{status},
        update_id => $args->{update_id},
    );
}

=head2 get_service_request_updates

Fetch updates list from Azure and filter to the relevant files.

=cut

sub get_service_request_updates {
    my ( $self, $args ) = @_;

    my $start;
    my $end;
    if ($args->{start_date}) {
        $start = DateTime::Format::W3CDTF->parse_datetime($args->{start_date});
    };
    if ($args->{end_date}) {
        $end = DateTime::Format::W3CDTF->parse_datetime($args->{end_date});
    };

    my @update_files = $self->aurora->fetch_update_names;
    my @updates = ();
    for (@update_files) {
        next if _skip_update_file($start, $end, $_->{Name});
        my $data = $self->aurora->fetch_update_file($_->{Name});
        next unless grep { $data->{Message}->{CaseTypeCode} } keys %{$self->reverse_status_mapping} || $_->{Name} =~ /CS_INSPECTION_PROMPTED/;

        my $id_no = @{$data->{Message}->{CaseEventHistory}};
        my $external_update = pop @{$data->{Message}->{CaseEventHistory}};
        my $update_date = DateTime::Format::W3CDTF->parse_datetime($external_update->{EventDateTime});
        my $formatter = DateTime::Format::Strptime->new(pattern => "%FT%T");
        $update_date =~ s/\.\d+$//;
        $update_date = $formatter->parse_datetime($update_date);
        $update_date->set_time_zone('Europe/London')->set_time_zone('UTC');

        my %update_args = (
            status => $_->{Name} =~ /CS_INSPECTION_PROMPTED/ ? 'investigating' : $self->reverse_status_mapping->{ $data->{Message}->{CaseTypeCode} },
            external_status_code => $data->{Message}->{CaseTypeCode},
            description => $_->{Name} =~ /CS_CLEAR_CASE/ ? $data->{Message}->{ClearanceReasonPortalText} : '',
            service_request_id => $data->{Message}->{ExternalReference},
            update_id => $data->{Message}->{ExternalReference} . '_' . $id_no,
            updated_datetime => $update_date,
        );

        push @updates, Open311::Endpoint::Service::Request::Update::mySociety->new( %update_args );
    }

    return @updates;
}

sub _skip_update_file {
    my ($start, $end, $file_name) = @_;

    return 1 unless $file_name =~ /_(CS_INSPECTION_PROMPTED|CS_CLEAR_CASE|CS_RECORD_CONTACT_EVENT|CS_MAINTENANCE_COMPLETED|CS_CHANGE_QUEUE|CS_RE_QUEUE)\.json/;

    return unless $start || $end;

    my ($year, $month, $day, $hour, $min, $sec) = $file_name =~ /^(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})/;
    my $file_date =  DateTime::Format::W3CDTF->parse_datetime($year . '-' . $month . '-' . $day . 'T' . $hour . ':' . $min . ':' . $sec);
    if ($start && $file_date < $start) {
        return 1;
    } elsif ($end && $file_date > $end) {
        return 1;
    };

};

sub _upload_media_as_attachments {
    my ( $self, $args ) = @_;
    my $attachment_ids = ();

    my $ua = LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter");
    foreach (@{$args->{media_url}}) {
        my $response = $ua->get($_);
        if ($response->is_success) {
            push @$attachment_ids,
                $self->aurora->upload_attachment_from_response_and_get_id($response);
        } else {
            $self->logger->warn("Unable to download media " . $_);
        }
    }

    foreach (@{$args->{uploads}}) {
        push @$attachment_ids,
            $self->aurora->upload_attachment_from_file_and_get_id($_->filename);
    }

    return [ map { { "id" => $_ } } @$attachment_ids ];
}

1;
