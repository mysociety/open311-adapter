package Open311::Endpoint::Integration::Alloy;

use Moo;
use DateTime::Format::W3CDTF;
use LWP::UserAgent;
use Types::Standard ':all';
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Open311::Endpoint::Role::ConfigFile';

with 'Role::Logger';

use Integrations::Alloy;
use Open311::Endpoint::Service::UKCouncil::Alloy;
use Open311::Endpoint::Service::Attribute;
use Open311::Endpoint::Service::Request::CanBeNonPublic;
use Open311::Endpoint::Service::Request::Update::mySociety;

use Path::Tiny;


around BUILDARGS => sub {
    my ($orig, $class, %args) = @_;
    die unless $args{jurisdiction_id}; # Must have one by here
    $args{config_file} //= path(__FILE__)->parent(5)->realpath->child("conf/council-$args{jurisdiction_id}.yml")->stringify;
    return $class->$orig(%args);
};

has jurisdiction_id => (
    is => 'ro',
);

has '+request_class' => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::Request::CanBeNonPublic',
);

has '+identifier_types' => (
    is => 'lazy',
    isa => HashRef[Any],
    default => sub {
        my $self = shift;
        return {
            # some service codes have spaces
            service_code => { type => '/open311/regex', pattern => qr/^ [\w_\- \/\(\)]+ $/ax },
        };
    },
);

has integration_class => (
    is => 'ro',
    default => 'Integrations::Alloy'
);

has alloy => (
    is => 'lazy',
    default => sub { $_[0]->integration_class->new(config_filename => $_[0]->jurisdiction_id) }
);

sub get_integration {
    return $_[0]->alloy;
}

has config => (
    is => 'lazy',
    default => sub { $_[0]->alloy->config }
);

=head2 service_class

Subclasses can override this to provide their own custom Service class, e.g.
if they want to have extra attributes on all services. We use the
UKCouncil::Alloy class which requests the asset's resource ID as a
separate attribute, so we can attach the defect to the appropriate asset
in Alloy.

=cut

has service_class  => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::UKCouncil::Alloy'
);


has service_whitelist => (
    is => 'ro',
    default => sub {
        return {} if $ENV{TEST_MODE};
        die "Attribute Alloy::service_whitelist not overridden";
    }
);

sub services {
    my $self = shift;

    my $request_to_resource_attribute_mapping = $self->config->{request_to_resource_attribute_mapping};
    my %remapped_resource_attributes = map { $_ => 1 } values %$request_to_resource_attribute_mapping;
    my %ignored_attributes = map { $_ => 1 } @{ $self->config->{ignored_attributes} };

    my $sources = $self->alloy->get_sources();
    my $source = $sources->[0]; # XXX Only one for now!

    my @services = ();
    for my $group (sort keys %{ $self->service_whitelist }) {
        my $whitelist = $self->service_whitelist->{$group};
        for my $subcategory (sort keys %{ $whitelist }) {
            next if $subcategory eq 'resourceId';
            my $name = $subcategory;
            my $code = $group . '_' . $name; # XXX What should it be...
            my %service = (
                service_name => $name,
                description => $name,
                service_code => $code,
                group => $group,
            );
            my $o311_service = $self->service_class->new(%service);

            for my $attrib (@{$source->{attributes}}) {
                my $overrides = $self->config->{service_attribute_overrides}{$attrib->{id}} || {};

                # If this attribute has a default provided by the config (resource_attribute_defaults)
                # or will be remapped from an attribute defined in Service::UKCouncil::Alloy
                # (request_to_resource_attribute_mapping) then we don't need to include it
                # in the Open311 service we send to FMS.
                next if $self->config->{resource_attribute_defaults}->{$attrib->{id}} ||
                    $remapped_resource_attributes{$attrib->{id}} || $ignored_attributes{$attrib->{id}};

                push @{$o311_service->attributes}, Open311::Endpoint::Service::Attribute->new(
                    code => $attrib->{id},
                    description => $attrib->{description},
                    datatype => $attrib->{datatype},
                    required => $attrib->{required},
                    values => $attrib->{values},
                    %$overrides,
                );
            }

            if ( $self->config->{emergency_text} && $self->service_whitelist->{$group}->{$subcategory}->{emergency} == 1 ) {
                push @{$o311_service->attributes}, Open311::Endpoint::Service::Attribute->new(
                    code => 'emergency',
                    variable => 0,
                    description => $self->config->{emergency_text},
                    datatype => 'text',
                );
            }

            push @services, $o311_service;
        }
    }

    return @services;
}

sub post_service_request {
    my ($self, $service, $args) = @_;
    die "No such service" unless $service;

    # Get the service code from the args/whatever
    # get the appropriate source type
    my $sources = $self->alloy->get_sources();
    my $source = $sources->[0]; # we only have one source at the moment

    # this is a display only thing for the website
    delete $args->{attributes}->{emergency};

    # extract attribute values
    my $resource_id = $args->{attributes}->{asset_resource_id} || 0;
    $resource_id =~ s/^\d+\.(\d+)$/$1/; # strip the unecessary layer id
    $resource_id += 0;

    my $parent_attribute_id;

    if ( $resource_id ) {
        # get the attribute id for the parents so alloy checks in the right place for the asset id
        my $resource_type = $self->alloy->api_call(
            call => "resource/$resource_id"
        )->{sourceTypeId};
        my $parent_attributes = $self->alloy->get_parent_attributes($resource_type);
        for my $attribute ( @$parent_attributes ) {
            if ( $attribute->{linkedSourceTypeId} eq $source->{source_type_id} ) {
                $parent_attribute_id = $attribute->{attributeId};
                last;
            }
        }

        unless ( $parent_attribute_id ) {
            my $msg = "no parent attribute id found for asset $resource_id with type $resource_type ($source->{source_type_id})";
            $self->logger->error($msg);
            die $msg;
        }
    }

    my ( $group, $category ) = split('_', $service->service_code);
    my $resource = {
        # This is seemingly fine to omit, inspections created via the
        # Alloy web UI don't include it anyway.
        networkReference => undef,

        # This appears to be shared amongst all asset types for now,
        # as everything is based off one design.
        sourceId => $source->{source_id},


        # No way to include the SRS in the GeoJSON, sadly, so
        # requires another API call to reproject. Beats making
        # open311-adapter geospatially aware, anyway :)
        geoJson => {
            type => "Point",
            coordinates => $self->reproject_coordinates($args->{long}, $args->{lat}),
        }
    };

    if ( $parent_attribute_id ) {
        # This is how we link this inspection to a particular asset.
        # The parent_attribute_id tells Alloy what kind of asset we're
        # linking to, and the resource_id is the specific asset.
        # It's a list so perhaps an inspection can be linked to many
        # assets, and maybe even many different asset types, but for
        # now one is fine.
        $resource->{parents} = {
            $parent_attribute_id => [ $resource_id ],
        };
    } else {
        $resource->{parents} = {};
    }

    # The Open311 attributes received from FMS may not include all the
    # the attributes we need to fully describe the Alloy resource,
    # and indeed these may change on a per-source or per-council basis.
    # Call out to process_attributes which can manipulate the resource
    # attributes (apply defaults, calculate values) as required.
    # This may be overridden by a subclass for council-specific things.
    $resource->{attributes} = $self->process_attributes($source, $args);

    # post it up
    my $response = $self->alloy->api_call(
        call => "resource",
        body => $resource
    );

    # create a new Request and return it
    return $self->new_request(
        service_request_id => $self->service_request_id_for_resource($response)
    );

}

sub post_service_request_update {
    my ($self, $args) = @_;

    my $resource_id = $args->{service_request_id};
    my $inspection = $self->alloy->api_call(call => "resource/$resource_id/full");

    my @attributes = @{ $inspection->{values} };
    my $updates = '';
    for my $attribute ( @attributes ) {
        if ($attribute->{attributeId} == $self->config->{inspection_attribute_mapping}->{updates}) {
            $updates = $attribute->{value};
        }
    }

    $updates = $self->_generate_update($args, $updates);

    my $updated = {
        attributes => {
            $self->config->{inspection_attribute_mapping}->{updates} => $updates
        },
        systemVersionId => $inspection->{version}->{resourceSystemVersionId},
    };

    if ( $self->config->{resource_attachment_attribute_id} && @{ $args->{media_url} }) {
        $updated->{attributes}->{$self->config->{resource_attachment_attribute_id}} = $self->upload_attachments($args);
    }

    my $update = $self->alloy->api_call(
        call => "resource/$resource_id",
        method => 'PUT',
        body => $updated
    );

    return Open311::Endpoint::Service::Request::Update::mySociety->new(
        status => lc $args->{status},
        update_id => $update->{systemVersionId},
    );
}

sub _generate_update {
    my ($self, $args, $updates) = @_;

    my $time = DateTime::Format::W3CDTF->new->parse_datetime($args->{updated_datetime});
    my $formatted_time = $time->ymd . " " . $time->hms;
    $updates .= "\nCustomer update at " . "$formatted_time" . "\n" . $args->{description};

    return $updates;
}

sub get_service_request_updates {
    my ($self, $args) = @_;

    my $w3c = DateTime::Format::W3CDTF->new;
    my $start_time = $w3c->parse_datetime($args->{start_date});
    my $end_time = $w3c->parse_datetime($args->{end_date});

    # updates to inspections
    my $updates = $self->fetch_updated_resources($self->config->{inspection_resource_name}, $args->{start_date});

    my @updates;

    my $sources = $self->alloy->get_sources();
    my $source = $sources->[0]; # XXX Only one for now!

    for my $update (@$updates) {
        # we only want updates to RFS inspections
        next unless $update->{sourceTypeId} eq $source->{source_type_id};

        # We need to fetch all versions that changed in the time wanted
        my @versions = $self->get_versions_of_resource($update->{resourceId});

        my $last_description = '';
        foreach (@versions) {
            my $resource = $self->alloy->api_call(call => "resource/$update->{resourceId}/full?systemVersion=$_->{id}");
            next unless $resource && ref $resource eq 'HASH'; # Should always be, but some test calls

            my $status = 'open';
            my $reason_for_closure = '';
            my $description = '';
            my @attributes = @{$resource->{values} || []};
            for my $att (@attributes) {
                # these might be specific to each design so will probably need
                # some config

                # status
                if ($att->{attributeId} == $self->config->{inspection_attribute_mapping}->{status}) {
                    $status = $self->inspection_status($att->{value}->{values}[0]->{resourceId});
                }

                # reason for closure
                if ($att->{attributeId} == $self->config->{inspection_attribute_mapping}->{reason_for_closure}) {
                    $reason_for_closure = $att->{value}->{values}[0] ? $att->{value}->{values}[0]->{resourceId} : '' ;
                }

                if ($att->{attributeId} == $self->config->{inspection_attribute_mapping}->{inspector_comments}) {
                    $description = $att->{value};
                }
            }

            # we don't care about the reason for closure unless the enquiry is closed so
            # blank it to stop us setting spurious external statuses
            if ( $status ne 'closed' ) {
                $reason_for_closure = '';
            }

            ($status, $reason_for_closure) = $self->process_update_state($status, $reason_for_closure);

            my $description_to_send = $description ne $last_description ? $description : '';
            $last_description = $description;

            # Now we have the description, can skip if update is not in our timeframe
            my $update_dt = $w3c->parse_datetime( $_->{date} )->truncate( to => 'second' );
            next unless $update_dt >= $start_time && $update_dt <= $end_time;

            if ($reason_for_closure) {
                $status = $self->get_status_with_closure($status, $reason_for_closure);
            }

            my %args = (
                status => $status,
                external_status_code => $reason_for_closure,
                update_id => $resource->{version}->{usedSystemVersionId},
                service_request_id => $update->{resourceId},
                description => $description_to_send,
                updated_datetime => $update_dt,
            );

            push @updates, Open311::Endpoint::Service::Request::Update::mySociety->new( %args );
        }
    }

    # updates to defects
    my $closure_mapping = $self->config->{inspection_closure_mapping};
    my %reverse_closure_mapping = map { $closure_mapping->{$_} => $_ } keys %{$closure_mapping};
    $updates = $self->fetch_updated_resources($self->config->{defect_resource_name}, $args->{start_date});
    for my $update (@$updates) {
        next if $self->is_ignored_category( $update );

        my $status = 'open';
        my $priority;
        my $description = '';
        my $fms_id = '';
        my $linked_defect;
        my @attributes = @{$update->{values}};
        for my $att (@attributes) {
            # these might be specific to each design so will probably need
            # some config
            # TODO: check if we are pulling back in description. It's a mandatory field in Alloy
            # so I suspect we should not be.
            #if ($att->{attributeId} == $self->config->{defect_attribute_mapping}->{description}) {
                #$description = $att->{value};
            #}

            # status
            if ($att->{attributeId} == $self->config->{defect_attribute_mapping}->{status}) {
                $status = $self->defect_status($att->{value});
            }

            if ($att->{attributeCode} =~ /_FIXMYSTREET_ID$/) {
                $linked_defect = 1;
                $fms_id = $att->{value};
            }

            if ($att->{attributeCode} =~ /_PRIORITIES/) {
                $priority = $att->{value}->{values}->[0]->{resourceId};
            }
        }

        my $service_request_id = $update->{resourceId};
        my $parents = $self->alloy->api_call(
            call => 'resource/' . $update->{resourceId} . '/parents'
        )->{details}->{parents};

        # if it has a parent that is an enquiry get the resource id of the inspection and use that
        # as the external id so updates are added to the report that created the inspection
        for my $parent (@$parents) {
            next unless $parent->{actualParentSourceTypeId} == $self->config->{defect_inspection_parent_id}; # request for service

            $linked_defect = 1;
            $service_request_id = $parent->{parentResId};
            $fms_id = undef;
        }

        # we don't care about linked defects until they have been scheduled
        next if $linked_defect && ( $status eq 'open' || $status eq 'investigating' );

        my $update_dt = $w3c->parse_datetime( $update->{version}->{startDate} )->truncate( to => 'second' );

        my %args = (
            status => $status,
            update_id => $update->{version}->{resourceSystemVersionId},
            service_request_id => $service_request_id,
            description => $description,
            updated_datetime => $update_dt,
        );

        if ($priority) {
            my $priority_details = $self->alloy->api_call(
                call => "resource/$priority"
            );

            $args{extras} = { priority => $priority_details->{title} || $priority };
        }

        # we need to set this to stop phantom updates being produced. This happens because
        # when an inspection is closed it always sets an external_status_code which we never
        # unset. Then when updates arrive from defects with no external_status_code the template
        # fetching code at FixMyStreet sees that the external_status_code has changed and fetches
        # the template. This means we always get an update even if nothing has changed. So, set
        # this to the external_status_code used when an inspection is marked for raising as a
        # defect. Only do this for 'action_scheduled' thouogh as otherwise the template lookup
        # will fail as it will be looking for status + ext code which won't match.
        if ( $status eq 'action_scheduled' && ( $fms_id || $linked_defect ) ) {
            $args{external_status_code} = $reverse_closure_mapping{'action_scheduled'};
        }
        $args{fixmystreet_id} = $fms_id if $fms_id;

        push @updates, Open311::Endpoint::Service::Request::Update::mySociety->new( %args );
    }

    return @updates;
}

sub get_service_requests {
    my ($self, $args) = @_;

    my $requests = $self->fetch_updated_resources($self->config->{defect_resource_name}, $args->{start_date});
    my @requests;
    for my $request (@$requests) {
        my %args;

        next if $self->is_ignored_category( $request );

        my $has_enquiry_parent = 0;
        my $parents = $self->alloy->api_call(
            call => 'resource/' . $request->{resourceId} . '/parents'
        )->{details}->{parents};
        for my $parent (@$parents) {
            next unless $parent->{actualParentSourceTypeId} == $self->config->{defect_inspection_parent_id}; # request for service

            $has_enquiry_parent = 1;
        }

        next if $has_enquiry_parent;

        my $category = $self->get_defect_category( $request );
        (my $service_name = $category) =~ s/^.*_//;
        unless ($category) {
            warn "No category found for defect $request->{resourceId}, source type $request->{sourceTypeId} in " . $self->jurisdiction_id . "\n";
            next;
        }

        my $category_service = $self->service($category);
        unless ($category_service) {
            warn "No matching service for $category for defect $request->{resourceId} in " . $self->jurisdiction_id . "\n";
            next;
        }

        $args{latlong} = $self->get_latlong_from_request($request);

        unless ($args{latlong}) {
            my $geometry = $request->{geometry}->{featureGeom}->{geometry};
            $self->logger->error("Defect $request->{resourceId}: don't know how to handle geometry: $geometry->{type}");
            warn "Defect $request->{resourceId}: don't know how to handle geometry: $geometry->{type}\n";
            next;
        }

        my $has_fixmystreet_id;
        my @attributes = @{$request->{values}};
        for my $att (@attributes) {

            if ($att->{attributeId} == $self->config->{defect_attribute_mapping}->{description}) {
                $args{description}= $att->{value};
            }
            if ($att->{attributeId} == $self->config->{defect_attribute_mapping}->{status}) {
                $args{status} = $self->defect_status($att->{value});
            }

            if ($att->{attributeCode} =~ /_FIXMYSTREET_ID$/) {
                $has_fixmystreet_id = 1 if $att->{value};
            }

            if ($att->{attributeCode} =~ /_PRIORITIES/) {
                $args{extras} = {priority => $att->{value}->{values}->[0]->{resourceId}};
            }
        }

        next if $has_fixmystreet_id;

        $args{description} = $self->get_request_description($args{description}, $request);

        my $service = Open311::Endpoint::Service->new(
            service_name => $service_name,
            service_code => $category,
        );
        $args{title} = $request->{title};
        $args{service} = $service;
        $args{service_request_id} = $request->{resourceId};
        $args{requested_datetime} = DateTime::Format::W3CDTF->new->parse_datetime( $request->{version}->{startDate})->truncate( to => 'second' );
        $args{updated_datetime} = DateTime::Format::W3CDTF->new->parse_datetime( $request->{version}->{startDate})->truncate( to => 'second' );

        push @requests, Open311::Endpoint::Service::Request::ExtendedStatus->new( %args );
    }

    return @requests;
}

sub fetch_updated_resources {
    my ($self, $code, $start_date) = @_;

    my @results;

    my $page = 1;
    my $pages = 1;
    while ($page <= $pages) {
        my $result = $self->alloy->api_call(
            call => "search/resource-fetch?page=$page",
            body => {
            aqsNode => {
                type => "FETCH",
                properties => {
                    entityType => "SOURCE_TYPE_PROPERTY_VALUE",
                    entityCode => $code
                },
                children => [
                    {
                        type => "GREATER_THAN",
                        children => [
                            {
                                type => "RESOURCE_PROPERTY",
                                properties => {
                                    resourcePropertyName => "lastEditDate"
                                }
                            },
                            {
                                type => "DATE",
                                properties => {
                                    value => [
                                        $start_date
                                    ]
                                }
                            }
                        ]
                    }
                ]
            }
        });

        $pages = $result->{totalPages};
        $page++;

        push @results, @{ $result->{results} }
    }

    return \@results;
}

sub inspection_status {
    my ($self, $status) = @_;

    return $self->config->{inspection_status_mapping}->{$status} || 'open';
}

sub process_update_state {
    my ($self, $status, $reason_for_closure) = @_;

    return ($status, $reason_for_closure);
}

sub get_status_with_closure {
    my ($self, $status, $reason_for_closure) = @_;

    return $self->config->{inspection_closure_mapping}->{$reason_for_closure} || $status;
}

sub defect_status {
    my ($self, $status) = @_;

    return $self->config->{defect_status_mapping}->{$status} || 'open';
}

sub service_request_id_for_resource {
    my ($self, $resource) = @_;

    # get the Alloy inspection reference
    # This may be overridden by subclasses depending on the council's workflow.
    # This default behaviour just uses the resource ID which will always
    # be present.
    return $resource->{resourceId};
}

sub get_time_for_version {
    my ($self, $resource_id, $version_id) = @_;

    my $versions = $self->alloy->api_call(call => "resource/$resource_id/versions");

    # sometimes we don't seem to get back a matching version number in which case use
    # the start time of the largest version that is smaller than the one we asked for.
    # worst case scenario, fall back to the current time.
    my $max = 0;
    my $no_version = 1;
    my $time;
    for my $version ( @$versions ) {
        if ($version->{currentSystemVersionId} eq $version_id) {
            $time = $version->{startDate};
            $no_version = 0;
            last;
        } elsif ( $version->{currentSystemVersionId} > $max && $version->{currentSystemVersionId} < $version_id ) {
            $time = $version->{startDate};
            $max = $version->{currentSystemVersionId};
        }
    }

    $self->logger->debug("Failed to match version $version_id for resource $resource_id") if $no_version;

    unless ( $time ) {
        $time = DateTime::Format::W3CDTF->new->format_datetime( DateTime->now() );
    }

    return $time;
}

sub get_versions_of_resource {
    my ($self, $resource_id) = @_;

    my $versions = $self->alloy->api_call(call => "resource/$resource_id/versions");

    my @versions = ();
    for my $version ( @$versions ) {
        push @versions, { id => $version->{currentSystemVersionId}, date => $version->{startDate} };
    }

    @versions = sort { $a->{id} <=> $b->{id} } @versions;
    return @versions;
}

sub get_latlong_from_request {
    my ($self, $request) = @_;

    my $latlong;

    my $geometry = $request->{geometry}->{featureGeom}->{geometry};

    if ( $geometry->{type} eq 'Point') {
        $latlong = $self->deproject_coordinates($geometry->{coordinates}[0], $geometry->{coordinates}[1]);
    } elsif ( $geometry->{type} eq 'LineString') {
        my @points = @{ $geometry->{coordinates} };
        my $half = int( @points / 2 );
        $latlong = $self->deproject_coordinates($points[$half]->[0], $points[$half]->[1]);
    } elsif ( $geometry->{type} eq 'Polygon') {
        my @points = @{ $geometry->{coordinates}->[0] };
        my ($max_x, $max_y, $min_x, $min_y) = ($points[0]->[0], $points[0]->[1], $points[0]->[0], $points[0]->[1]);
        foreach my $point ( @points ) {
            $max_x = $point->[0] if $point->[0] > $max_x;
            $max_y = $point->[1] if $point->[1] > $max_y;

            $min_x = $point->[0] if $point->[0] < $min_x;
            $min_y = $point->[1] if $point->[1] < $min_y;
        }
        my $x = $min_x + ( ( $max_x - $min_x ) / 2 );
        my $y = $min_y + ( ( $max_y - $min_y ) / 2 );
        $latlong = $self->deproject_coordinates($x, $y);
    }

    return $latlong;
}

sub get_request_description {
    my ($self, $desc) = @_;

    return $desc;
}

sub is_ignored_category {
    my ($self, $defect) = @_;

    return grep { $defect->{sourceTypeId} eq $_ } @{ $self->config->{ ignored_defect_types } };
}

sub get_defect_category {
    my ($self, $defect) = @_;
    my $mapping = $self->config->{defect_sourcetype_category_mapping}->{ $defect->{sourceTypeId} };

    my $category = $mapping->{default};

    if ( $mapping->{types} ) {
        my @attributes = @{$defect->{values}};
        my $type;

        for my $att (@attributes) {
            if ($att->{attributeCode} =~ /DEFECT_TYPE/ ) {
                $type = $att->{value}->{values}->[0]->{resourceId};
            }
        }

        $category = $mapping->{types}->{$type} if $mapping->{types}->{$type};
    }

    return '' unless $category;

    my %reverse_whitelist;
    for my $group (sort keys %{ $self->service_whitelist }) {
        my $whitelist = $self->service_whitelist->{$group};
        for my $subcategory (sort keys %{ $whitelist }) {
            next if $subcategory eq 'resourceId';
            $reverse_whitelist{$subcategory} = $group;
        }
    }

    my $cat_group = $reverse_whitelist{$category} || '';
    return $cat_group . '_' . $category;
}

sub process_attributes {
    my ($self, $source, $args) = @_;

    # Make a clone of the received attributes so we can munge them around
    my $attributes = { %{ $args->{attributes} } };

    # We don't want to send all the received Open311 attributes to Alloy
    foreach (qw/report_url fixmystreet_id northing easting asset_resource_id title description category/) {
        delete $attributes->{$_};
    }

    # TODO: Right now this applies defaults regardless of the source type
    # This is OK whilst we have a single design, but we might need to
    # have source-type-specific defaults when multiple designs are in use.
    my $defaults = $self->config->{resource_attribute_defaults} || {};

    # Some of the Open311 service attributes need remapping to Alloy resource
    # attributes according to the config...
    my $remapping = $self->config->{request_to_resource_attribute_mapping} || {};
    my $remapped = {};
    for my $key ( keys %$remapping ) {
        $remapped->{$remapping->{$key}} = $args->{attributes}->{$key};
    }

    # service code is a special case
    my ( $group, $category ) = split('_', $args->{service_code});
    my $group_code = $self->config->{service_whitelist}->{$group}->{resourceId};
    $remapped->{$remapping->{category}} = [ { resourceId => $group_code, command => "add" } ];

    $attributes = {
        %$attributes,
        %$defaults,
        %$remapped,
    };

    # Set the creation time for this resource to the current timestamp.
    # TODO: Should this take the 'confirmed' field from FMS?
    if ( $self->config->{created_datetime_attribute_id} ) {
        my $now = DateTime->now();
        my $created_time = DateTime::Format::W3CDTF->new->format_datetime($now);
        $attributes->{$self->config->{created_datetime_attribute_id}} = $created_time;
    }


    # Upload any photos to Alloy and link them to the new resource
    # via the appropriate attribute
    if ( $self->config->{resource_attachment_attribute_id} && $args->{media_url}) {
        $attributes->{$self->config->{resource_attachment_attribute_id}} = $self->upload_attachments($args);
    }

    return $attributes;
}

sub reproject_coordinates {
    my ($self, $lon, $lat) = @_;

    my $point = $self->alloy->api_call(
        call => "projection/point",
        params => {
            x => $lon,
            y => $lat,
            srcCode => "4326",
            dstCode => "900913",
        }
    );

    return [ $point->{x}, $point->{y} ];
}

sub deproject_coordinates {
    my ($self, $lon, $lat) = @_;

    my $point = $self->alloy->api_call(
        call => "projection/point",
        params => {
            x => $lon,
            y => $lat,
            dstCode => "4326",
            srcCode => "900913",
        }
    );

    return [ $point->{y}, $point->{x} ];
}

sub upload_attachments {
    my ($self, $args) = @_;

    # grab the URLs and download its content
    my $media_urls = $args->{media_url};

    # Grab each photo from FMS
    my $ua = LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter");
    my @photos = map {
        $ua->get($_);
    } @$media_urls;

    my $folder_id = $self->config->{attachment_folder_id};

    # upload the file to the folder, with a FMS-related name
    my @resource_ids = map {
        $self->alloy->api_call(
            call => "file",
            params => {
                'model.folderId' => $folder_id,
                'model.name' => $_->filename
            },
            body=> $_->content,
            is_file => 1
        )->{resourceId};
    } @photos;

    # return a list of the form
    my @commands = map { {
        command => "add",
        resourceId => $_,
    } } @resource_ids;

    return \@commands;
}

1;
