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

sub inspection_status {
    my ($self, $defect) = @_;

    my $mapping = $self->config->{inspection_attribute_mapping};
    my $options = $self->config->{inspection_status_mapping};

    my $status = $defect->{$mapping->{status}} || '';
    my $outcome = $defect->{$mapping->{outcome}} || '';
    my $hwy_priority = $defect->{$mapping->{hwy_priority}} || '';
    my $se_priority = $defect->{$mapping->{se_priority}} || '';

    # unwrap values if necessary
    $status = $status->[0] if ref $status eq 'ARRAY';
    $outcome = $outcome->[0] if ref $outcome eq 'ARRAY';
    $hwy_priority = $hwy_priority->[0] if ref $hwy_priority eq 'ARRAY';
    $se_priority = $se_priority->[0] if ref $se_priority eq 'ARRAY';

    # Enquiry only has one priority, take whichever has a value.
    my $priority = $hwy_priority || $se_priority;

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

    return "IGNORE";
}

sub _skip_inspection_update {
    my ($self, $status) = @_;

    return 1 if $status eq 'IGNORE';
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

    # Sort by lastEditDate to get the most recent, with fallback to createdDate
    my @sorted = sort {
        my $date_a = $a->{lastEditDate} || $a->{createdDate} || '';
        my $date_b = $b->{lastEditDate} || $b->{createdDate} || '';
        $date_b cmp $date_a;
    } @inspections;

    return $sorted[0];
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
