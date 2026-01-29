package Open311::Endpoint::Integration::UK::Dumfries;

use Moo;
extends 'Open311::Endpoint::Integration::AlloyV2';
with 'Role::Memcached';

use Encode;
use JSON::MaybeXS;
use Path::Tiny;
use Try::Tiny;

around BUILDARGS => sub {
    my ( $orig, $class, %args ) = @_;
    $args{jurisdiction_id} = 'dumfries_alloy';
    return $class->$orig(%args);
};

sub service_request_content {
    '/open311/service_request_extended'
}

=head2 process_attributes

In addition to the default new request processing, this function:
* Finds or creates a contact and adds them under the C<contact.attribute_id> attribute.
* Sets the 'reported issue' (i.e. category) field by the incoming service_code.

=cut

sub process_attributes {
    my ($self, $args) = @_;

    my $attributes = $self->SUPER::process_attributes($args);

    my $contact_resource_id = $self->_find_or_create_contact($args);
    push @$attributes, {
        attributeCode => $self->config->{contact}->{attribute_id},
        value => [ $contact_resource_id ],
    };

    push @$attributes, {
        attributeCode => $self->config->{request_to_resource_attribute_manual_mapping}->{service_code},
        value => [ $args->{service_code_alloy} ],
    };

    return $attributes;
}

=head2 _get_service_code

Dumfries uses the actual Alloy item IDs from their subcategory list on Alloy
as Open311 service codes. This means we can hae different names shown for
groups/subcategories on FMS as well as the same subcategory name used
multiple times for different Alloy IDs (e.g. the 'Other' subcategory in their
'Trees' group has a different item ID to 'Other' in 'Grounds').

=cut

sub _get_service_code {
    my ($self, $group, $subcategory, $subcategory_config) = @_;

    return $subcategory_config->{id};
}

=head2 get_service_code_from_defect

For Dumfries, extract the service code directly from the defect's reported issue attribute.
If that's not set, fall back to using the sourcetype mapping from the config.

=cut

sub get_service_code_from_defect {
    my ($self, $defect) = @_;

    my $mapping = $self->config->{defect_attribute_mapping};

    # Try to get service_code from attribute first
    if ($mapping && $mapping->{service_code}) {
        my $attributes = $self->alloy->attributes_to_hash($defect);
        my $service_code = $attributes->{$mapping->{service_code}};
        $service_code = $service_code->[0] if ref $service_code eq 'ARRAY';
        return $service_code if $service_code;
    }

    # Fall back to using sourcetype category mapping
    my $subcategory_name = $self->get_defect_category($defect);
    $self->logger->debug("get_defect_category returned: '" . ($subcategory_name // 'undef') . "' for defect " . $defect->{itemId} . " (design: " . $defect->{designCode} . ")");
    return unless $subcategory_name;

    # Find the service_code for this subcategory name in the service_whitelist
    # Since subcategories can appear under multiple parent categories,
    # we'll return the first match
    # Do case-insensitive comparison to handle naming variations
    my $whitelist = $self->config->{service_whitelist};
    for my $category (keys %$whitelist) {
        my $subcategories = $whitelist->{$category};
        for my $subcat_name (keys %$subcategories) {
            if (lc($subcat_name) eq lc($subcategory_name)) {
                return $subcategories->{$subcat_name}->{id};
            }
        }
    }

    return;
}

=head2 service

For Dumfries, we need to handle the case where the service_code from Alloy
is a base ID (e.g., 64f1dc207e262328e7cf803a) but our service_whitelist has
IDs with suffixes (e.g., 64f1dc207e262328e7cf803a_1, 64f1dc207e262328e7cf803a_2)
because the same subcategory is reused across multiple categories.

We match the base ID and return the first matching service.

=cut

sub service {
    my ($self, $service_code) = @_;

    # Try exact match first (standard behavior)
    my @services = $self->services;
    for my $service (@services) {
        return $service if $service->service_code eq $service_code;
    }

    # If no exact match, try prefix match (for IDs with _1, _2 suffixes)
    for my $service (@services) {
        my $whitelist_code = $service->service_code;
        # Check if whitelist code starts with the service_code followed by underscore and digit
        if ($whitelist_code =~ /^\Q$service_code\E_\d+$/) {
            return $service;
        }
    }

    return;
}

=head2 _extra_search_properties

For Dumfries, we need to include both Live and Archive collections when
fetching updated resources from Alloy.

=cut

sub _extra_search_properties {
    my ($self) = @_;
    return { collectionCode => ["Live", "Archive"] };
}

=head2 _get_service_requests_resource

For Dumfries, we override the defect fetching to use the service_code directly
from the defect attributes instead of relying on category mapping.

=cut

sub _get_service_requests_resource {
    my ($self, $resource_name, $args) = @_;

    my $requests = $self->fetch_updated_resources($resource_name, $args->{start_date}, $args->{end_date});
    my @requests;
    my $mapping = $self->config->{defect_attribute_mapping};

    for my $request (@$requests) {
        my %request_args;

        next if $self->skip_fetch_defect( $request );

        # Get service_code directly from the defect
        my $service_code = $self->get_service_code_from_defect($request);
        unless ($service_code) {
            $self->logger->warn("No service_code found for defect $request->{itemId} in " . $self->jurisdiction_id);
            next;
        }

        # Look up the service (this will handle _1, _2 suffix matching)
        my $service_obj = $self->service($service_code);
        unless ($service_obj) {
            $self->logger->warn("No service found for defect $request->{itemId}, service_code $service_code in " . $self->jurisdiction_id);
            next;
        }

        $request_args{latlong} = $self->get_latlong_from_request($request);

        unless ($request_args{latlong}) {
            my $geometry = $request->{geometry}{type} || 'unknown';
            $self->logger->error("Defect $request->{itemId}: don't know how to handle geometry: $geometry");
            next;
        }

        my $attributes = $self->alloy->attributes_to_hash($request);

        # Get description if mapping exists
        if ($mapping->{description}) {
            $request_args{description} = $self->get_request_description($attributes->{$mapping->{description}}, $request);
        }

        ( $request_args{status}, $request_args{external_status_code} ) = $self->defect_status($attributes);

        # Skip defects with IGNORE status
        if ($request_args{status} && $request_args{status} eq 'IGNORE') {
            next;
        }

        $request_args{title} = $attributes->{attributes_itemsTitle};
        $request_args{service} = $service_obj;
        $request_args{service_request_id} = $request->{itemId};
        $request_args{requested_datetime} = $self->date_to_truncated_dt( $attributes->{$mapping->{requested_datetime}} ) if $mapping->{requested_datetime};
        $request_args{updated_datetime} = $self->date_to_truncated_dt( $attributes->{$mapping->{requested_datetime}} ) if $mapping->{requested_datetime};

        my $service_request = $self->new_request( %request_args );

        push @requests, $service_request;
    }

    return @requests;
}

=head2 _get_inspection_status

The Open311 status of a defect in Alloy depends on multiple fields - status,
priority, and outcome.

Because it'd be better to not hardcode these dependencies, the
`inspection_status_mapping` config for Dumfries is a list of objects that we
iterate through to find one that matches the values of those fields on this
defect.

If any of status/outcome/priority are set to null in the
inspection_status_mapping list then those attributes are ignored when
considering if that entry matches.

If we fall off the end of the list with no matches we return 'IGNORE' so the
defect/update is skipped.

=cut

# Mapping is passed in here, but then ignored and looked up again - tidy up the ALloy 'external status code' code? TODO
sub _get_inspection_status {
    my ($self, $defect, $mapping) = @_;
    return $self->inspection_status($defect);
}

sub _get_defect_status {
    my ($self, $defect, $mapping) = @_;
    return $self->inspection_status($defect);
}

sub defect_status {
    my ($self, $attribs, $report, $linked_defect) = @_;
    return $self->inspection_status($attribs, $report, $linked_defect);
}

sub inspection_status {
    my ($self, $defect, $report, $linked_defect) = @_;

    my $mapping = $self->config->{inspection_attribute_mapping};
    my $options = $self->config->{inspection_status_mapping};

    my $status = $defect->{$mapping->{status}} || '';
    my $outcome = $defect->{$mapping->{outcome}} || '';
    my $hwy_priority = $defect->{$mapping->{hwy_priority}} || '';
    my $se_priority = $defect->{$mapping->{se_priority}} || '';
    my $triage_priority = $defect->{$mapping->{triage_priority}} || '';

    # unwrap values if necessary
    $status = $status->[0] if ref $status eq 'ARRAY';
    $outcome = $outcome->[0] if ref $outcome eq 'ARRAY';
    $hwy_priority = $hwy_priority->[0] if ref $hwy_priority eq 'ARRAY';
    $se_priority = $se_priority->[0] if ref $se_priority eq 'ARRAY';
    $triage_priority = $triage_priority->[0] if ref $triage_priority eq 'ARRAY';

    # Enquiry only has one priority, take whichever has a value.
    my $priority = $hwy_priority || $se_priority || $triage_priority;

    for my $opt (@$options) {
        unless (defined $opt->{result}) {
            die "Missing 'result' value - please check inspection_status_mapping in config";
        }
        # if the entry in config has some values undefined then consider those fields a match
        my $s = defined $opt->{status}   ? $opt->{status}   eq $status   : 1;
        my $o = defined $opt->{outcome}  ? $opt->{outcome}  eq $outcome  : 1;
        my $p = defined $opt->{priority} ? $opt->{priority} eq $priority : 1;

        # choose this status iff all three things match
        if ($s && $o && $p) {
            # construct an external status code based on the three attribute values
            my $ext = join ":", $status, $outcome, $priority;
            return ($opt->{result}, $ext);
        }
    }

    my $item_id = $report->{itemId} || '';
    $self->logger->warn("Ignoring update for $item_id with status: $status outcome: $outcome priority: $priority");
    return "IGNORE";
}

sub _skip_inspection_update {
    my ($self, $status) = @_;

    return 1 if $status eq 'IGNORE';
}

sub _skip_job_update {
    my ($self, $defect, $status) = @_;

    return 1 if $status eq 'IGNORE';
}

=head2 get_service_request

Override to add media_url support for jobs attached to the defect.

=cut

sub get_service_request {
    my ($self, $service_request_id, $args) = @_;

    # Call parent implementation to get the basic service request
    my $request_obj = $self->SUPER::get_service_request($service_request_id, $args);
    return unless $request_obj;

    # Fetch the defect item to get job media URLs
    my $response = $self->alloy->api_call(call => "item/$service_request_id");
    my $defect = $response->{item};
    return $request_obj unless $defect;

    # Add media URLs from associated jobs
    my $media_urls = $self->_get_job_media_urls($defect);
    if (@$media_urls) {
        $request_obj->{media_url} = $media_urls;
    }

    return $request_obj;
}

=head2 _get_job_media_urls

For a given defect, fetch any associated jobs and return media URLs for their attachments.

=cut

sub _get_job_media_urls {
    my ($self, $defect) = @_;

    my @media_urls;
    my $defect_id = $defect->{itemId};

    # Get the job IDs from the defect's RaisedJobs attribute
    my $attributes = $self->alloy->attributes_to_hash($defect);
    my $job_ids = $attributes->{attributes_defectsRaisingJobsRaisedJobs};

    unless ($job_ids) {
        $self->logger->debug("Defect $defect_id has no raised jobs");
        return \@media_urls;
    }

    # Get inspection attachments to exclude from job attachments
    my %inspection_attachment_ids;
    my $inspection_ids = $attributes->{attributes_defectsWithInspectionsDefectInspection};
    if ($inspection_ids) {
        $inspection_ids = [ $inspection_ids ] unless ref $inspection_ids eq 'ARRAY';
        for my $inspection_id (@$inspection_ids) {
            my $inspection = $self->alloy->api_call(call => "item/$inspection_id");
            if ($inspection && $inspection->{item}) {
                my $inspection_attrs = $self->alloy->attributes_to_hash($inspection->{item});
                my $inspection_attachments = $inspection_attrs->{attributes_filesAttachableAttachments};
                if ($inspection_attachments) {
                    $inspection_attachments = [ $inspection_attachments ] unless ref $inspection_attachments eq 'ARRAY';
                    $inspection_attachment_ids{$_} = 1 for @$inspection_attachments;
                }
            }
        }
        if (%inspection_attachment_ids) {
            $self->logger->debug("Defect $defect_id has " . scalar(keys %inspection_attachment_ids) . " inspection attachment(s) to exclude");
        }
    }

    # Normalize to array
    $job_ids = [ $job_ids ] unless ref $job_ids eq 'ARRAY';
    $self->logger->debug("Defect $defect_id has " . scalar(@$job_ids) . " raised job(s)");

    # For each job, fetch it and get any attachments
    for my $job_id (@$job_ids) {
        my $job = $self->alloy->api_call(call => "item/$job_id");
        unless ($job && $job->{item}) {
            $self->logger->warn("Failed to fetch job $job_id for defect $defect_id");
            next;
        }

        my $job_attributes = $self->alloy->attributes_to_hash($job->{item});
        my $attachment_ids = $job_attributes->{attributes_filesAttachableAttachments};
        unless ($attachment_ids) {
            $self->logger->debug("Job $job_id has no attachments");
            next;
        }

        # Normalize to array
        $attachment_ids = [ $attachment_ids ] unless ref $attachment_ids eq 'ARRAY';
        $self->logger->debug("Job $job_id has " . scalar(@$attachment_ids) . " attachment(s)");

        # Build media URLs for each attachment
        my $api_url = $self->config->{api_url};
        for my $attachment_id (@$attachment_ids) {
            # Skip attachments that are also on the inspection
            if ($inspection_attachment_ids{$attachment_id}) {
                $self->logger->debug("Skipping attachment $attachment_id (already on inspection)");
                next;
            }

            # Fetch the file item to check its filename
            my $file = $self->alloy->api_call(call => "item/$attachment_id");
            unless ($file && $file->{item}) {
                $self->logger->warn("Failed to fetch file $attachment_id for job $job_id");
                next;
            }

            my $file_attrs = $self->alloy->attributes_to_hash($file->{item});
            my $filename = $file_attrs->{attributes_filesOriginalName} || '';
            
            # Skip files that match the pattern \d+\.\d\.full\.*
            # These are auto-generated copies from FixMyStreet
            if ($filename =~ /^\d+\.\d+\.full\./) {
                $self->logger->debug("Skipping auto-generated file: $filename");
                next;
            }

            # Build media URL using base_url and photo endpoint pattern
            my $base_url = $self->config->{base_url};
            unless ($base_url) {
                $self->logger->warn("No base_url configured, skipping media_url for attachment $attachment_id");
                next;
            }
            my $jurisdiction_id = $self->jurisdiction_id;
            my $media_url = "${base_url}photos?jurisdiction_id=${jurisdiction_id}&item=${attachment_id}";
            push @media_urls, $media_url;
            $self->logger->debug("Added media_url: $media_url (filename: $filename)");
        }
    }

    return \@media_urls;
}

=head2 _get_inspection_updates_design

Override to add media_url support for jobs attached to the inspection/defect.

=cut

sub _get_inspection_updates_design {
    my ($self, $design, $args) = @_;

    # Call parent to get the base updates
    my @updates = $self->SUPER::_get_inspection_updates_design($design, $args);

    # For each update, fetch the associated resource and add media URLs
    # Also handle special case for latest_inspection_time
    for my $update (@updates) {
        my $service_request_id = $update->service_request_id;
        
        # Fetch the resource to get job media URLs
        my $response = $self->alloy->api_call(call => "item/$service_request_id");
        my $report = $response->{item};

        if ($report) {
            my $media_urls = $self->_get_job_media_urls($report);
            if (@$media_urls) {
                # Note: media_url is read-only, so we need to recreate the update object
                # with the media_url included
                $update->{media_url} = $media_urls;
            }

            # Handle special case for latest_inspection_time
            # The join may return data from any inspection, not necessarily the latest
            # So we always fetch the latest inspection ourselves to get the correct completion time
            my $mapping = $self->config->{inspection_attribute_mapping};
            if ($mapping && $mapping->{extra_attributes} && $mapping->{extra_attributes}{latest_inspection_time}) {
                my $latest_inspection = $self->_find_latest_inspection($report);
                if ($latest_inspection) {
                    my $inspection_attrs = $self->alloy->attributes_to_hash($latest_inspection);
                    my $completion_time = $inspection_attrs->{attributes_tasksCompletionTime};

                    if ($completion_time) {
                        $completion_time = $completion_time->[0] if ref $completion_time eq 'ARRAY';
                        $update->{extras}{latest_inspection_time} = $completion_time;
                    } else {
                        $update->{extras}{latest_inspection_time} = 'NOT COMPLETE';
                    }
                }
            }
        }
    }

    return @updates;
}

=head2 _get_defect_updates

For Dumfries, defects are the same as inspections (both use rfs_design).
We get all updates via _get_inspection_updates_design, so skip defect updates
to avoid duplicates.

=cut

sub _get_defect_updates {
    my ($self, $args) = @_;
    return ();
}


=head2 post_service_request_update

For Dumfries we need to create a new inspection on the original defect.
We do this by fetching the most recent existing inspection (if present)
and using it as a template for the new one, but use the comment text and
datetime of the FMS comment.

Inspections are attached to the original defect from FMS slightly differently
depending on the category.

 - Some have the inspection linked via the attributes_defectsWithInspectionsDefectInspection attribute on the defect
 - Some have the inspection as a parent on the defect - we can use the /parents API call

If no inspection is found we die with an error

=cut

sub post_service_request_update {
    my ($self, $args) = @_;

    my $resource_id = $args->{service_request_id};

    # Fetch the defect from Alloy
    my $defect = $self->alloy->api_call(call => "item/$resource_id")->{item};

    # Look up the inspection using one of the mentioned processes
    my $inspection_ref = $self->_find_latest_inspection($defect);

    unless ($inspection_ref) {
        $self->logger->error("No inspection found for defect $resource_id during POST Service Request Update");
        die "No inspection found for defect $resource_id";
    }

    # Fetch the full inspection details
    my $inspection = $self->alloy->api_call(call => "item/$inspection_ref->{itemId}")->{item};

    # Build a new inspection based on the existing one
    my $new_inspection = {
        designCode => $inspection->{designCode},
        geometry => $inspection->{geometry},
    };

    # Set the defect as the parent of this inspection so it's linked properly
    # This ensures the new inspection is attached to the same defect
    if ($inspection->{parents}) {
        # Copy the parent structure from the existing inspection
        # This should maintain the link to the defect
        $new_inspection->{parents} = $inspection->{parents};
    }

    # Copy all attributes from the template inspection, excluding computed/read-only ones
    # and attributes that should not be set on new inspections
    my @new_attributes;

    # Get mapping config for update parameters to inspection attributes
    my $update_to_inspection_mapping = $self->config->{update_to_inspection_attribute_mapping} || {};

    # Check which mapped attributes exist on the template inspection
    # Different inspection types have different schemas
    my %template_has_attr;
    for my $attr (@{$inspection->{attributes}}) {
        $template_has_attr{$attr->{attributeCode}} = 1;
    }

    # List of computed/read-only attributes that should not be copied
    my %skip_attributes = (
        attributes_itemsTitle => 1,
        attributes_itemsSubtitle => 1,
        attributes_inspectionsInspectionNumber => 1,  # Auto-generated
        attributes_tasksIssuedTime => 1,  # Should not be set on new inspections
        attributes_tasksCompletionTime => 1,
        attributes_tasksStatus => 1,
    );

    # Add any attributes from the mapping to the skip list, as we'll set them separately
    for my $attr_code (values %$update_to_inspection_mapping) {
        $skip_attributes{$attr_code} = 1 if $attr_code;
    }

    for my $attr (@{$inspection->{attributes}}) {
        next if $skip_attributes{$attr->{attributeCode}};

        push @new_attributes, {
            attributeCode => $attr->{attributeCode},
            value => $attr->{value},
        };
    }

    # when raising new inspections we need to set them to the 'Issued' status.
    push @new_attributes, {
        attributeCode => 'attributes_tasksStatus',
        value => ['5bc5bdd281d088d177342c73'], # XXX move to config
    };

    # Apply mappings from the incoming update to inspection attributes
    # Only apply if the template inspection has these attributes (schema compatibility)
    if (my $raised_time_attr = $update_to_inspection_mapping->{updated_datetime}) {
        if ($template_has_attr{$raised_time_attr}) {
            push @new_attributes, {
                attributeCode => $raised_time_attr,
                value => $args->{updated_datetime},
            };
        }
    }

    if (my $description_attr = $update_to_inspection_mapping->{description}) {
        if ($args->{description} && $template_has_attr{$description_attr}) {
            push @new_attributes, {
                attributeCode => $description_attr,
                value => $args->{description},
            };
        }
    }

    if ($self->config->{resource_attachment_attribute_id}
        && ($args->{media_url} || $args->{uploads})) {
        my $attachment_code = $self->config->{resource_attachment_attribute_id};
        my $new_attachments = $self->upload_media($args);
        if ($new_attachments && @$new_attachments) {
            my ($existing) = grep { $_->{attributeCode} eq $attachment_code } @new_attributes;
            if ($existing) {
                my $existing_value = $existing->{value};
                $existing_value = [ $existing_value ] unless ref $existing_value eq 'ARRAY';
                push @$existing_value, @$new_attachments;
                $existing->{value} = $existing_value;
            } else {
                push @new_attributes, {
                    attributeCode => $attachment_code,
                    value => $new_attachments,
                };
            }
        }
    }

    $new_inspection->{attributes} = \@new_attributes;

    # Create the new inspection in Alloy
    my $response = $self->alloy->api_call(
        call => "item",
        body => $new_inspection
    );

    my $new_inspection_id = $response->{item}->{itemId};

    # Update the defect to link to the new inspection
    # Add the new inspection ID to the defect's inspection list attribute
    $self->_link_inspection_to_defect($defect, $new_inspection_id);

    # Return the update with the combined ID
    return Open311::Endpoint::Service::Request::Update::mySociety->new(
        status => lc $args->{status},
        update_id => $resource_id . "_" . $new_inspection_id,
    );
}

=head2 _link_inspection_to_defect

Updates the defect to add the new inspection ID to its
attributes_defectsWithInspectionsDefectInspection attribute.

=cut

sub _link_inspection_to_defect {
    my ($self, $defect, $new_inspection_id) = @_;

    my $defect_id = $defect->{itemId};

    # Find the current inspection IDs on the defect
    my $inspection_attr_code = 'attributes_defectsWithInspectionsDefectInspection';
    my @current_inspection_ids;

    for my $attr (@{$defect->{attributes}}) {
        if ($attr->{attributeCode} eq $inspection_attr_code) {
            @current_inspection_ids = ref $attr->{value} eq 'ARRAY'
                ? @{$attr->{value}}
                : ($attr->{value});
            last;
        }
    }

    # Add the new inspection ID to the list
    push @current_inspection_ids, $new_inspection_id;

    # For Alloy PUT, we only need to send the attributes we're changing
    # plus the signature for optimistic locking
    my $updated_defect = {
        attributes => [
            {
                attributeCode => $inspection_attr_code,
                value => \@current_inspection_ids,
            }
        ],
        signature => $defect->{signature},
    };

    # Update the defect in Alloy
    try {
        $self->alloy->api_call(
            call => "item/$defect_id",
            method => 'PUT',
            body => $updated_defect
        );
    } catch {
        # If we get a signature mismatch, refetch and retry
        if ( $_ =~ /ItemSignatureMismatch/ ) {
            my $fresh_defect = $self->alloy->api_call(call => "item/$defect_id")->{item};

            # Get the fresh inspection list and add our new inspection
            my @fresh_inspection_ids;
            for my $attr (@{$fresh_defect->{attributes}}) {
                if ($attr->{attributeCode} eq $inspection_attr_code) {
                    @fresh_inspection_ids = ref $attr->{value} eq 'ARRAY'
                        ? @{$attr->{value}}
                        : ($attr->{value});
                    last;
                }
            }
            push @fresh_inspection_ids, $new_inspection_id;

            # Retry with fresh signature and updated inspection list
            try {
                $self->alloy->api_call(
                    call => "item/$defect_id",
                    method => 'PUT',
                    body => {
                        attributes => [
                            {
                                attributeCode => $inspection_attr_code,
                                value => \@fresh_inspection_ids,
                            }
                        ],
                        signature => $fresh_defect->{signature},
                    }
                );
            } catch {
                die "Failed to link inspection $new_inspection_id to defect $defect_id: $_";
            }
        } else {
            die "Failed to link inspection $new_inspection_id to defect $defect_id: $_";
        }
    };
}

sub _find_latest_inspection {
    my ($self, $defect) = @_;

    my $defect_id = $defect->{itemId};
    my @inspections;

    # First, check if the defect has a direct link to inspections via attributes
    # Convert attributes array to hash for easier lookup
    my $attributes = {};
    for my $attr (@{$defect->{attributes}}) {
        $attributes->{$attr->{attributeCode}} = $attr->{value};
    }

    # Check for the inspection link attribute on the defect
    my $inspection_ids = $attributes->{attributes_defectsWithInspectionsDefectInspection};
    if ($inspection_ids) {
        # Inspection IDs are stored in the defect's attributes
        my @ids = ref $inspection_ids eq 'ARRAY' ? @$inspection_ids : ($inspection_ids);

        # Fetch full details for each inspection
        for my $id (@ids) {
            my $inspection = $self->alloy->api_call(call => "item/$id")->{item};
            push @inspections, $inspection;
        }
    }

    # If no inspection found via attributes, try parent relationship
    if (!@inspections) {
        my $parents = $self->alloy->api_call(call => "item/$defect_id/parents")->{results};
        @inspections = grep { $_->{designCode} =~ /inspection/i } @$parents;
    }

    return unless @inspections;

    # Sort by attributes_tasksRaisedTime to get the most recent inspection
    # Fall back to lastEditDate, then createdDate, then itemId
    my @sorted = sort {
        my $attrs_a = $self->alloy->attributes_to_hash($a);
        my $attrs_b = $self->alloy->attributes_to_hash($b);

        my $time_a = $attrs_a->{attributes_tasksRaisedTime} || $a->{lastEditDate} || $a->{createdDate} || $a->{itemId};
        my $time_b = $attrs_b->{attributes_tasksRaisedTime} || $b->{lastEditDate} || $b->{createdDate} || $b->{itemId};

        $time_b cmp $time_a;
    } @inspections;

    return $sorted[0];
}

=head2 get_photo

Fetch a photo from Alloy by its file item ID.

=cut

sub get_photo {
    my ($self, $args) = @_;

    my $item_id = $args->{item};
    unless ($item_id) {
        $self->logger->error("get_photo called without item parameter");
        return [ 400, [ 'Content-Type', 'text/plain' ], [ 'Missing item parameter' ] ];
    }

    # Fetch the file from Alloy
    my $content;
    my $content_type = 'image/jpeg'; # default

    # First, get the file metadata to determine content type
    try {
        my $file_item = $self->alloy->api_call(call => "item/$item_id");
        if ($file_item && $file_item->{item}) {
            my $attrs = $self->alloy->attributes_to_hash($file_item->{item});
            my $filename = $attrs->{attributes_filesOriginalName} || '';
            if ($filename =~ /\.png$/i) {
                $content_type = 'image/png';
            } elsif ($filename =~ /\.gif$/i) {
                $content_type = 'image/gif';
            } elsif ($filename =~ /\.jpe?g$/i) {
                $content_type = 'image/jpeg';
            }
        }
    } catch {
        $self->logger->warn("Failed to fetch file metadata for $item_id: $_");
    };

    # Now fetch the actual file content
    try {
        $content = $self->alloy->api_call_raw(
            call => "file/$item_id",
        );
    } catch {
        $self->logger->error("Failed to fetch photo $item_id: $_");
        return [ 404, [ 'Content-Type', 'text/plain' ], [ 'Photo not found' ] ];
    };

    return [ 404, [ 'Content-Type', 'text/plain' ], [ 'Photo not found' ] ] unless $content;
    return [ 200, [ 'Content-Type', $content_type ], [ $content ] ];
}

sub _attach_files_to_service_request {
    my ($self, $item_id, $files) = @_;

    $self->SUPER::_attach_files_to_service_request($item_id, $files);


    # now we need to find the inspection for this defect (waiting up to 60
    # seconds for it) and then attach these files to that too.
    my $inspection_ref;
    my $defect;
    for (1..6) {
        sleep 10; # might as well sleep now rather than at end of loop as workflow will definitely not have created inspection yet.
        $defect = $self->alloy->api_call(call => "item/$item_id")->{item};
        $inspection_ref = $self->_find_latest_inspection($defect);
        last if $inspection_ref;
    }
    if ($inspection_ref) {
        $self->SUPER::_attach_files_to_service_request($inspection_ref->{itemId}, $files);
    } else {
        $self->logger->warn("No inspection found for defect $item_id during POST Service Request");
    }
}

1;
