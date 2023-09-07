package Open311::Endpoint::Integration::ATAK;

use Moo;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Role::EndpointConfig';
with 'Role::Logger';

use POSIX qw(strftime);
use MIME::Base64 qw(encode_base64);
use Open311::Endpoint::Service::UKCouncil::ATAK;
use Integrations::ATAK;
use JSON::MaybeXS;
use DateTime::Format::W3CDTF;
use Path::Tiny;
use Try::Tiny;

has jurisdiction_id => (
    is => 'ro',
    required => 1,
);

sub get_integration {
    my ($self) = @_;

    $self->log_identifier($self->jurisdiction_id);
    my $atak = Integrations::ATAK->new(config_filename => $self->jurisdiction_id);
    return $atak;
}

sub services {
    my ($self) = @_;

    my $services = $self->endpoint_config->{services};
    my @services = map {
        my $name = $services->{$_}{name};
        my $service = Open311::Endpoint::Service::UKCouncil::ATAK->new(
            service_name => $name,
            service_code => $_,
            description => $name,
            $services->{$_}{group} ? (group => $services->{$_}{group}) : (),
            $services->{$_}{groups} ? (groups => $services->{$_}{groups}) : (),
        );
    } sort keys %$services;
    return @services;
}

sub post_service_request {
    my ($self, $service, $args) = @_;
    die "No such service" unless $service;
    die "Args must be a hashref" unless ref $args eq 'HASH';

    $self->logger->info("[ATAK] Creating issue for service " . $service->service_name);
    $self->logger->debug("[ATAK] POST service request args: " . encode_json($args));

    my @attachments;

    if ($args->{media_url}) {
        my $i = 1;
        @attachments = map {
            my $content_type = $_->content_type ? $_->content_type : 'image/jpeg';
            {
                filename => $_->filename,
                description => "Image " . $i++,
                data => "data:" . $content_type . ";base64," . encode_base64($_->content)
            }
        } $self->_get_attachments($args->{media_url});
    }

    my $issue_text = $self->_format_issue_text(
        $self->endpoint_config->{max_issue_text_characters},
        $service->service_name,
        $args->{attributes}->{location_name} || '',
        $args->{attributes}->{report_url},
        $args->{attributes}->{title},
        $args->{attributes}->{detail},
    );

    my $issue = {
        client_ref => $args->{attributes}->{fixmystreet_id},
        taken_on => strftime("%Y-%m-%dT%H:%M:%SZ", gmtime),
        project_code => $self->endpoint_config->{project_code},
        project_name => $self->endpoint_config->{project_name},
        issue => $issue_text,
        location_name => $args->{attributes}->{location_name} || '',
        caller => "",
        resolve_by => "",
        location => {
            type => 'Point',
            coordinates => [
                # Add zero to force numeric context
                $args->{long} + 0,
                $args->{lat} + 0,
            ],
        }
    };

    $self->logger->debug("[ATAK] Issue: " . encode_json($issue));

    if (@attachments) {
        $issue->{attachments} = \@attachments;
    }

    my $service_request_id = $self->get_integration->create_issue($issue);

    return $self->new_request(
        service_request_id => $service_request_id,
    )
}

sub _format_issue_text {
    my ($self, $char_limit, $category, $location_name, $url, $title, $detail) = @_;

    # Populate everything except the detail field which we may need to truncate.
    my $issue_text = sprintf(
        "Category: %s\nLocation: %s\n\nlocation of problem: %s\n\ndetail: %%s\n\nurl: %s\n\nSubmitted via FixMyStreet\n",
        $category, $location_name, $title, $url
    );

    # +2 for the not yet used format directive for detail (%s).
    my $max_detail_chars = $char_limit - length($issue_text) + 2;

    # We need at least 3 characters of leeway so we can use an ellipsis to indicate
    # the detail was truncated.
    # Note using horizontal ellipsis (U+2026) results in an internal server error.
    if ($max_detail_chars < 3 && length($detail) > $max_detail_chars) {
        die "Issue text is too large, even if we were to truncate the detail before inserting: " . $issue_text;
    }

    if (length($detail) > $max_detail_chars) {
        $detail = substr($detail, 0, $max_detail_chars - 3) . "...";
    }

    return sprintf($issue_text, $detail);

}

sub _get_attachments {
    my ($self, $urls) = @_;

    my @photos = ();
    my $ua = LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter");
    for (@$urls) {
        my $response = $ua->get($_);
        if ($response->is_success) {
            push @photos, $response;
        } else {
            $self->logger->error("[ATAK] Unable to download attachment: " . $_);
            $self->logger->debug("[ATAK] Photo response status: " . $response->status_line);
            $self->logger->debug("[ATAK] Photo response content: " . $response->decoded_content);
        }
    }
    return @photos;
}

sub get_service_request_updates {
    my ($self, $args) = @_;
    my $w3c = DateTime::Format::W3CDTF->new;
    my $start_time = $w3c->parse_datetime($args->{start_date})->epoch;
    my $end_time = $w3c->parse_datetime($args->{end_date})->epoch;

    my $update_storage_raw = path($self->endpoint_config->{update_storage_file})->slurp_raw;
    my $updates;
    try {
        $updates = decode_json($update_storage_raw);
    } catch {
        $self->logger->error("[ATAK] Error parsing update storage file: $_");
        $updates = [];
    };

    my @updates_to_send;

    foreach my $update (@$updates) {
        next if $update->{time} > $end_time;
        last if $update->{time} < $start_time;

        my %args = (
            status => $update->{fms_status},
            external_status_code => $update->{atak_status},
            update_id => $update->{issue_reference} . '_' . $update->{time},
            service_request_id => $update->{task_id},
            description => $update->{description},
            updated_datetime => DateTime->from_epoch(epoch => $update->{time}),
        );
        push @updates_to_send, Open311::Endpoint::Service::Request::Update::mySociety->new( %args );
    }
    return @updates_to_send;

}

sub init_update_gathering_files {
    my ($self, $start_from) = @_;

    my $issue_status_tracking_file = $self->endpoint_config->{issue_status_tracking_file};
    my $update_storage_file = $self->endpoint_config->{update_storage_file};

    if (-e $issue_status_tracking_file && ! -z $issue_status_tracking_file) {
        die $issue_status_tracking_file . " already exists and is not empty. Aborting.";
    }
    if (-e $update_storage_file && ! -z $update_storage_file) {
        die $update_storage_file . " already exists and is not empty. Aborting.";
    }

    path($issue_status_tracking_file)->spew_raw(encode_json({
        latest_update_seen_time => $start_from->epoch,
        issues => {}
    }));

    path($update_storage_file)->spew_raw('[]');
}

sub gather_updates {
    my $self = shift;
    my $status_tracking_fh = path($self->endpoint_config->{issue_status_tracking_file})->openrw_raw({ locked => 1 });
    read $status_tracking_fh, my $tracked_statuses_raw, -s $status_tracking_fh;
    my $tracked_statuses = decode_json($tracked_statuses_raw);

    my $update_storage_raw = path($self->endpoint_config->{update_storage_file})->slurp_raw;
    my $updates = decode_json($update_storage_raw);

    my $issue_created_cutoff = DateTime->now->subtract(days => $self->endpoint_config->{issue_status_tracking_max_age_days});
    $self->_delete_old_tracked_issues($tracked_statuses, $issue_created_cutoff);

    my $update_cutoff = DateTime->now->subtract(days => $self->endpoint_config->{update_storage_max_age_days});
    $self->_delete_old_updates($updates, $update_cutoff);

    push @$updates, @{$self->_fetch_and_apply_updated_issues_info($tracked_statuses, $issue_created_cutoff)};

    # Descending time.
    @$updates = sort { $b->{time} <=> $a->{time} } @$updates;

    my $new_tracked_statuses_raw = encode_json($tracked_statuses);
    my $new_updates_storage_raw = encode_json($updates);

    path($self->endpoint_config->{update_storage_file})->spew_raw($new_updates_storage_raw);

    seek $status_tracking_fh, 0, 0;
    truncate $status_tracking_fh, 0;
    print $status_tracking_fh $new_tracked_statuses_raw;
    close $status_tracking_fh;
}

sub _delete_old_tracked_issues {
    my ($self, $tracked_statuses, $cutoff) = @_;
    while (my ($reference, $state) = each %{$tracked_statuses->{issues}}) {
        if ($state->{created_time} < $cutoff->epoch) {
            delete $tracked_statuses->{issues}{$reference};
        }
    }
}

sub _delete_old_updates {
    my ($self, $updates, $cutoff) = @_;
    @$updates = grep { $_->{time} >= $cutoff->epoch } @$updates;
}

sub _fetch_and_apply_updated_issues_info {
    my ($self, $tracked_statuses, $created_cutoff) = @_;

    my $latest_update_seen = DateTime->from_epoch(epoch => $tracked_statuses->{latest_update_seen_time});
    my $now = DateTime->now;

    $self->logger->debug(sprintf(
            "[ATAK] Querying for issues updated between %s and %s.",
            $latest_update_seen,
            $now,
        ));

    my $response = $self->get_integration->list_updated_issues($latest_update_seen, $now);

    if (!$response) {
        # Equivalent to no updates.
        $tracked_statuses->{latest_update_seen_time} = $now->epoch;
        return [];
    }

    if (!$response->{tasks}) {
        $self->logger->warn("[ATAK] No 'tasks' field found in the list updated issues response.");
        return [];
    }

    my @updates;
    my $w3c = DateTime::Format::W3CDTF->new;
    foreach my $issue (@{ $response->{tasks} }) {
        # Assumes list is already ordered in ascending update time.

        my $time_created = $w3c->parse_datetime($issue->{task_d_created}) if $issue->{task_d_created};
        my $time_approved = $w3c->parse_datetime($issue->{task_d_approved}) if $issue->{task_d_approved};
        my $time_planned = $w3c->parse_datetime($issue->{task_d_planned}) if $issue->{task_d_planned};
        my $time_completed = $w3c->parse_datetime($issue->{task_d_completed}) if $issue->{task_d_completed};
        my @ordered_times = sort grep { defined } ($time_created, $time_approved, $time_planned, $time_completed);
        my $most_recent_time = pop @ordered_times;

        my $issue_reference = $issue->{client_ref};
        if (!$issue_reference) {
            $self->logger->warn("[ATAK] No  client reference field found on updated issue. Skipping.");
            next;
        }

        if ($most_recent_time && $most_recent_time > $latest_update_seen) {
            if ($most_recent_time > $now) {
                # For some reason, we've been given an update beyond our query range.
                # In this case, we limit the latest_update_seen to end of the query range
                # just in case this 'future' time would cause us to miss other updates.
                $self->logger->warn(sprintf(
                        "[ATAK] The update time for issue %s is %s which is beyond the maximum time queried for %s.",
                        $issue_reference, $most_recent_time, $now
                    )
                );
                $latest_update_seen = $now;
            } else {
                $latest_update_seen = $most_recent_time;
            }
        }


        if (!$time_created) {
            $self->logger->warn(sprintf(
                    "[ATAK] No created time field found on updated issue %s. Skipping.",
                    $issue_reference
                ));
            next;
        }

        if ($time_created < $created_cutoff) {
            $self->logger->debug(sprintf(
                    "[ATAK] Updated issue %s was created on %s which is older than the cutoff %s. Skipping.",
                    $issue_reference,
                    $time_created,
                    $created_cutoff,
                ));
            next;
        }

        my $task_comments = $issue->{task_comments};
        if (!$task_comments) {
            $self->logger->warn(sprintf(
                    "[ATAK] No task comments field found on updated issue %s. Skipping.",
                    $issue_reference
                ));
            next;
        }

        # Assumes no prefix is a substring of another prefix.
        my $atak_status;
        my $mapped_fms_status;
        my $description;
        foreach my $candidate_atak_status (keys %{$self->endpoint_config->{atak_status_to_fms_status}}) {
            if ($candidate_atak_status eq substr $task_comments, 0, length($candidate_atak_status)) {
                $atak_status = $candidate_atak_status;
                $mapped_fms_status = $self->endpoint_config->{atak_status_to_fms_status}->{$atak_status};
                $description = substr $task_comments, length($atak_status);
                # Left trim the description.
                $description =~ s/^\s+// if $description;
                last;
            }
        }

        if (!$mapped_fms_status) {
            $self->logger->debug(sprintf(
                    "[ATAK] Updated issue %s has unmapped ATAK status '%s'. Skipping.",
                    $issue_reference,
                    $task_comments
                ));
            next;
        }

        my $existing_tracking = $tracked_statuses->{issues}->{$issue_reference};

        unless ($existing_tracking && $existing_tracking->{atak_status} eq $atak_status) {
            $tracked_statuses->{issues}->{$issue_reference} = {
                task_id => $issue->{task_p_id},
                fms_status => $mapped_fms_status,
                atak_status => $atak_status,
                issue_reference => $issue_reference,
                updated_time => $most_recent_time->epoch,
                created_time => $time_created->epoch,
                description => $description || '',
            };
            my $update = {
                task_id => $issue->{task_p_id},
                fms_status => $mapped_fms_status,
                atak_status => $atak_status,
                issue_reference => $issue_reference,
                time => $most_recent_time->epoch,
                description => $description || '',
            };
            $self->logger->debug(sprintf(
                    "[ATAK] Adding new update:\n%s",
                    encode_json($update)
                ));

            push @updates, $update;
        } else {
            $self->logger->debug(sprintf(
                    "[ATAK] Updated issue %s has not changed from tracked ATAK status '%s'. Skipping.",
                    $issue_reference,
                    $atak_status
                ));
        }
    }

    $tracked_statuses->{latest_update_seen_time} = $latest_update_seen->epoch;

    return \@updates;
}

1;
