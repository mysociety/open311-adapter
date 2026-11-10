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

=head2 trigger_status_mapping

Optional table of the Aurora triggers to fetch updates for (besides
C<CS_CLEAR_CASE>, which uses C<reverse_status_mapping>) and the FMS status
each one maps to, e.g.

  trigger_status_mapping:
    CS_CHANGE_QUEUE: open
    CS_MAINTENANCE_COMPLETED: fixed

If not set, a fixed set of triggers is used; see C<get_service_request_updates>.

=cut

has trigger_status_mapping => (
    is => 'lazy',
    default => sub { $_[0]->endpoint_config->{trigger_status_mapping} }
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
Uploads media provided as uploads or URLs as attachments. Those provided as
URLs also have that URL set as the attachment's C<externalUrl>.
Creates a case using these and also the default parameters set in
the C<category_mapping>.
The rest of the case is built by C<build_case_payload>, with the description
text coming from C<build_case_description>.

=cut

sub post_service_request {
    my ( $self, $service, $args ) = @_;

    my $service_code = $args->{service_code};
    my $category = $self->category_mapping->{$service_code};
    my $payload = $self->build_case_payload($args, $category);

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
    my $case_number = $self->aurora->create_case_and_get_number($payload);

    return $self->new_request(
        service_request_id => $case_number
    );
}

=head2 build_case_payload

Returns the case fields for a request, other than the contact and attachments,
starting from the default parameters set in the C<category_mapping>.
Subclasses can override this to change what is sent.

=cut

sub build_case_payload {
    my ( $self, $args, $category ) = @_;

    my $payload = { %{ $category->{parameters} || {} } };
    $payload->{easting} = $args->{attributes}->{easting};
    $payload->{northing} = $args->{attributes}->{northing};
    $payload->{usrn} = $args->{attributes}->{NSGRef};
    $payload->{internalAssetId} = $args->{attributes}->{UnitID};
    $payload->{externalReference} = "FMS" . $args->{attributes}->{fixmystreet_id};
    $payload->{locationText} = $args->{attributes}->{title};
    $payload->{description} = $self->build_case_description($args);

    return $payload;
}

=head2 build_case_description

Returns the description text for a case: the report's title and description,
followed by the location query and the report URL, if present.

=cut

sub build_case_description {
    my ( $self, $args ) = @_;

    my $description = $args->{attributes}->{title} . "\n\n" . $args->{attributes}->{description};
    if ($args->{address_string}) {
        $description .= "\n\nLocation query entered: " . $args->{address_string};
    }
    if ($args->{attributes}->{report_url}) {
        $description .= "\n\nView report on FixMyStreet: $args->{attributes}->{report_url}";
    }

    return $description;
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
    $self->aurora->add_note_to_case($case_number, $payload);
    return Open311::Endpoint::Service::Request::Update::mySociety->new(
        status => lc $args->{status},
        update_id => $args->{update_id},
    );
}

=head2 get_service_request_updates

Fetches files from Aurora's 'return path update' Azure storage container which contains a
snapshot of a case after one of the configured 'triggers' fires.

If C<trigger_status_mapping> is configured, only files for the triggers listed
there and for C<CS_CLEAR_CASE> are used. C<CS_CLEAR_CASE> updates have their
C<ClearanceReasonCode> mapped to an update status via the
C<reverse_status_mapping>, and are skipped if the code is not present there;
the code is passed on as the update's external status code. Updates for the
other triggers take their status from C<trigger_status_mapping> and have the
trigger name as their external status code.

Otherwise, the C<ClearanceReasonCode> is mapped to an update status via the
C<reverse_status_mapping>, with the exception of updates via the
C<CS_INSPECTION_PROMPTED> trigger which always map to 'investigating',
C<CS_MAINTENANCE_COMPLETED> which map to fixed with a code, and
C<CS_CHANGE_QUEUE> which send through a code but do not change state.

Updates via the C<CS_CLEAR_CASE> trigger have their description populated from the
C<ClearanceReasonPortalText> field, all others are blank.

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

    my @update_files = $self->aurora->fetch_update_filenames(_date_prefix($start, $end));
    my @updates = ();
    my $triggers = $self->_handled_triggers;
    for (@update_files) {
        my ($trigger) = $_->{Name} =~ /_(CS_[A-Z_]+)\.json/;
        next unless $trigger && $triggers->{$trigger};
        next if _skip_update_file($start, $end, $_->{Name});
        my $data = $self->aurora->fetch_update_file($_->{Name});
        my ($state, $external_status_code) = $self->_status_for_trigger(
            $trigger, $data->{Message}->{ClearanceReasonCode});
        next unless $state;

        my $id_no = @{$data->{Message}->{CaseEventHistory}};
        my $external_update = pop @{$data->{Message}->{CaseEventHistory}};
        my $update_date = DateTime::Format::W3CDTF->parse_datetime($external_update->{EventDateTime})
                            ->set_nanosecond(0)
                            ->set_time_zone('UTC');

        my $desc = $trigger eq 'CS_CLEAR_CASE' ? ($data->{Message}->{ClearanceReasonPortalText} // '') : '';
        # The exported text from Aurora has newlines stripped so they have been escaped
        # - unescaping them here.
        $desc =~ s/\\n/\n/g;

        my %update_args = (
            status => $state,
            external_status_code => $external_status_code,
            description => $desc,
            service_request_id => $data->{Message}->{CaseNumber},
            update_id => $data->{Message}->{CaseNumber} . '_' . $id_no,
            updated_datetime => $update_date,
        );

        push @updates, Open311::Endpoint::Service::Request::Update::mySociety->new( %update_args );
    }

    return @updates;
}

# The triggers whose update files we look at, as a lookup hash.
sub _handled_triggers {
    my $self = shift;

    my @triggers = $self->trigger_status_mapping
        ? ('CS_CLEAR_CASE', keys %{ $self->trigger_status_mapping })
        : qw(
            CS_INSPECTION_PROMPTED
            CS_CLEAR_CASE
            CS_RECORD_CONTACT_EVENT
            CS_MAINTENANCE_COMPLETED
            CS_CHANGE_QUEUE
            CS_RE_QUEUE
        );
    return { map { $_ => 1 } @triggers };
}

# Returns the update status and external status code for an update file with
# the given trigger and clearance code, or nothing if it should be skipped.
sub _status_for_trigger {
    my ($self, $trigger, $clearance_code) = @_;

    my $cleared_state = $clearance_code && $self->reverse_status_mapping->{$clearance_code};

    if (my $mapping = $self->trigger_status_mapping) {
        return ($cleared_state, $clearance_code) if $trigger eq 'CS_CLEAR_CASE';
        return ($mapping->{$trigger}, $trigger);
    }

    # No trigger_status_mapping configured, so the original fixed behaviour.
    return ('unchanged', $trigger) if $trigger eq 'CS_CHANGE_QUEUE';
    return ('fixed', $trigger) if $trigger eq 'CS_MAINTENANCE_COMPLETED';
    # NB this one passes on whatever clearance code the case has, if any,
    # rather than the trigger name.
    return ('investigating', $clearance_code) if $trigger eq 'CS_INSPECTION_PROMPTED';
    return ($cleared_state, $clearance_code);
}

sub _skip_update_file {
    my ($start, $end, $file_name) = @_;

    return unless $start || $end;

    my ($year, $month, $day, $hour, $min, $sec) = $file_name =~ /^(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})/;
    # Aurora names files using UK local time.
    my $file_date = DateTime->new(
        year => $year,
        month => $month,
        day => $day,
        hour => $hour,
        minute => $min,
        second => $sec,
        time_zone => 'Europe/London',
    );

    if ($start && $file_date < $start) {
        return 1;
    } elsif ($end && $file_date > $end) {
        return 1;
    };

    return 0;
};

sub _date_prefix {
    my ($start, $end) = @_;

    return '' unless $start;
    $end ||= DateTime->now(time_zone => 'Europe/London');

    # Filenames use UK local time prefixes.
    my $start_str = $start->clone->set_time_zone('Europe/London')->strftime('%Y%m%d_%H%M%S');
    my $end_str = $end->clone->set_time_zone('Europe/London')->strftime('%Y%m%d_%H%M%S');

    return _common_prefix($start_str, $end_str);
};

sub _common_prefix {
    my ($a, $b) = @_;
    my $i = 0;
    my $max = length($a) < length($b) ? length($a) : length($b);
    $i++ while $i < $max && substr($a, $i, 1) eq substr($b, $i, 1);
    return substr($a, 0, $i);
}


# NOTE: Aurora silently fails if we upload an attachment to a case without a name.
sub _upload_media_as_attachments {
    my ( $self, $args ) = @_;
    my $attachments = ();

    my $ua = LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter");
    foreach (@{$args->{media_url}}) {
        my $response = $ua->get($_);
        if ($response->is_success) {
            push @$attachments, {
                id => $self->aurora->upload_attachment_from_response_and_get_id($response),
                name => $response->filename,
                externalUrl => $_,
            };
        } else {
            $self->logger->warn("Unable to download media " . $_);
        }
    }

    foreach (@{$args->{uploads}}) {
        push @$attachments, {
            id => $self->aurora->upload_attachment_from_file_and_get_id($_->tempname),
            name => $_->filename,
        };
    }

    return $attachments;
}

1;
