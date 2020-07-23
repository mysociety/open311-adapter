package Open311::Endpoint::Integration::AlloyV2;

use Digest::MD5 qw(md5_hex);
use Moo;
use Try::Tiny;
use DateTime::Format::W3CDTF;
use LWP::UserAgent;
use Types::Standard ':all';
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Open311::Endpoint::Role::ConfigFile';

with 'Role::Logger';

use Integrations::AlloyV2;
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
    default => 'Integrations::AlloyV2'
);

has date_parser => (
    is => 'ro',
    default => sub {
        DateTime::Format::W3CDTF->new;
    }
);

has alloy => (
    is => 'lazy',
    default => sub { $_[0]->integration_class->new(config_filename => $_[0]->jurisdiction_id) }
);

has config => (
    is => 'lazy',
    default => sub { $_[0]->alloy->config }
);

has group_in_service_code => (
    is => 'ro',
    default => 1
);

sub get_integration {
    return $_[0]->alloy;
}

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

has reverse_whitelist => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        my %reverse_whitelist;
        for my $group (sort keys %{ $self->service_whitelist }) {
            my $whitelist = $self->service_whitelist->{$group};
            for my $subcategory (sort keys %{ $whitelist }) {
                next if $subcategory eq 'resourceId';
                $reverse_whitelist{$subcategory} = $group;
            }
        }
        return \%reverse_whitelist;
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
    my $resource_id = $args->{attributes}->{asset_resource_id} || '';

    my $parent_attribute_id;


    my $resource = {
        # This appears to be shared amongst all asset types for now,
        # as everything is based off one design.
        designCode => $self->config->{rfs_design},


        # No way to include the SRS in the GeoJSON, sadly, so
        # requires another API call to reproject. Beats making
        # open311-adapter geospatially aware, anyway :)
        geometry => {
            type => "Point",
            coordinates => [$args->{long}, $args->{lat}],
        }
    };

    $self->_set_parent_attribute($resource, $resource_id);

    # The Open311 attributes received from FMS may not include all the
    # the attributes we need to fully describe the Alloy resource,
    # and indeed these may change on a per-source or per-council basis.
    # Call out to process_attributes which can manipulate the resource
    # attributes (apply defaults, calculate values) as required.
    # This may be overridden by a subclass for council-specific things.
    $resource->{attributes} = $self->process_attributes($source, $args);

    # XXX try this first so we bail if we can't upload the files
    my $files = [];
    if ( $self->config->{resource_attachment_attribute_id} && @{$args->{media_url}}) {
        $files = $self->upload_attachments($args);
    }

    # post it up
    my $response = $self->alloy->api_call(
        call => "item",
        body => $resource
    );

    my $item_id = $self->service_request_id_for_resource($response);

    # Upload any photos to Alloy and link them to the new resource
    # via the appropriate attribute
    if (@$files) {
        $self->_add_attachments_to_item($files, $item_id, $self->config->{resource_attachment_attribute_id});
    }

    # create a new Request and return it
    return $self->new_request(
        service_request_id => $item_id
    );

}

sub _add_attachments_to_item {
    my ($self, $files, $item_id, $attribute_id) = @_;

    my $item = $self->alloy->api_call(call => "item/$item_id");
    my $updated = {
        attributes => [{
            attributeCode => $attribute_id,
            value => $files
        }],
        signature => $item->{item}->{signature}
    };

    try {
        my $update = $self->alloy->api_call(
            call => "item/$item_id",
            method => 'PUT',
            body => $updated
        );
    } catch {
        # if we fail to update this then we shouldn't fall over as we want to avoid
        # creating duplicates of the report. However, if it's a signature mismatch
        # then try again in case it's been updated in the meantime.
        if ( $_ =~ /ItemSignatureMismatch/ ) {
            my $item = $self->alloy->api_call(call => "item/$item_id");
            $updated->{signature} = $item->{item}->{signature};
            try {
                my $update = $self->alloy->api_call(
                    call => "item/$item_id",
                    method => 'PUT',
                    body => $updated
                );
            } catch {
                warn $_;
            }
        } else {
            warn $_;
        }
    }
}

sub _set_parent_attribute {
    my ($self, $resource, $resource_id) = @_;

    my $parent_attribute_id;
    if ( $resource_id ) {
        ## get the attribute id for the parents so alloy checks in the right place for the asset id
        my $resource_type = $self->alloy->api_call(
            call => "item/$resource_id"
        )->{item}->{designCode};
        $parent_attribute_id = $self->alloy->get_parent_attributes($resource_type);

        unless ( $parent_attribute_id ) {
            my $msg = "no parent attribute id found for asset $resource_id with type $resource_type";
            $self->logger->error($msg);
            die $msg;
        }
    }

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
}

sub post_service_request_update {
    my ($self, $args) = @_;

    my $resource_id = $args->{service_request_id};
    my $inspection = $self->alloy->api_call(call => "item/$resource_id")->{item};

    my $attributes = $self->alloy->attributes_to_hash($inspection);
    my $updates = $attributes->{$self->config->{inspection_attribute_mapping}->{updates}} || '';

    $updates = $self->_generate_update($args, $updates);

    my $updated = {
        attributes => [{
            attributeCode => $self->config->{inspection_attribute_mapping}->{updates},
            value => $updates
        }],
        signature => $inspection->{signature}, # XXX check this is correct
    };

    if ( $self->config->{resource_attachment_attribute_id} && @{ $args->{media_url} }) {
        push @{ $updated->{attributes} }, {
            attributeCode => $updated->{attributes}->{$self->config->{resource_attachment_attribute_id}},
            value => $self->upload_attachments($args)
        };
    }

    my $update = $self->alloy->api_call(
        call => "item/$resource_id",
        method => 'PUT',
        body => $updated
    );

    return Open311::Endpoint::Service::Request::Update::mySociety->new(
        status => lc $args->{status},
        update_id => $update->{item}->{signature}, # $args->{service_request_id} . "_$id_date", # XXX check this
    );
}

sub _generate_update {
    my ($self, $args, $updates) = @_;

    my $time = $self->date_to_dt($args->{updated_datetime});
    my $formatted_time = $time->ymd . " " . $time->hms;
    my $text = "Customer update at " . "$formatted_time" . "\n" . $args->{description};
    $updates = $updates ? "$updates\n$text" : $text;

    return $updates;
}

sub get_service_request_updates {
    my ($self, $args) = @_;

    my $start_time = $self->date_to_dt($args->{start_date});
    my $end_time = $self->date_to_dt($args->{end_date});

    my @updates;

    push @updates, $self->_get_inspection_updates($args, $start_time, $end_time);
    push @updates, $self->_get_defect_updates($args, $start_time, $end_time);

    return @updates;
}

sub _get_inspection_updates {
    my ($self, $args, $start_time, $end_time) = @_;

    my @updates;

    my $updates = $self->fetch_updated_resources($self->config->{rfs_design}, $args->{start_date});
    my $mapping = $self->config->{inspection_attribute_mapping};
    for my $update (@$updates) {
        next unless $self->_accept_updated_resource($update, $start_time, $end_time);

        # We need to fetch all versions that changed in the time wanted
        my @version_ids = $self->get_versions_of_resource($update->{itemId});

        my $last_description = '';
        foreach my $date (@version_ids) {
            # we have to fetch all the updates as we need them to check if the
            # comments have changed. once we've fetched them we can throw away the
            # ones that don't match the date range.
            my $resource = $self->alloy->api_call(call => "item-log/item/$update->{itemId}/reconstruct", body => { date => $date });
            next unless $resource && ref $resource eq 'HASH'; # Should always be, but some test calls

            $resource = $resource->{item};
            my $attributes = $self->alloy->attributes_to_hash($resource);

            my ($status, $reason_for_closure) = $self->_get_inspection_status($attributes, $mapping);

            # only want to put a description in the update if it's changed so compare
            # it to the last one.
            my $description = $attributes->{$mapping->{inspector_comments}} || '';
            my $description_to_send = $description ne $last_description ? $description : '';
            $last_description = $description;

            my $update_dt = $self->date_to_truncated_dt( $date );
            next unless $update_dt >= $start_time && $update_dt <= $end_time;

            (my $id_date = $date) =~ s/\D//g;
            my $id = $update->{itemId} . "_$id_date";

            my %args = (
                status => $status,
                external_status_code => $reason_for_closure,
                update_id => $resource->{signature},
                service_request_id => $update->{itemId},
                description => $description_to_send,
                updated_datetime => $update_dt,
            );

            push @updates, Open311::Endpoint::Service::Request::Update::mySociety->new( %args );
        }
    }

    return @updates;
}

sub _accept_updated_resource {
    my ($self, $update) = @_;

    # we only want updates to RFS inspections
    return 1 if $update->{designCode} eq $self->config->{rfs_design};
}

sub _get_inspection_status {
    my ($self, $attributes, $mapping) = @_;

    my $status = 'open';
    if ($attributes->{$mapping->{status}}) {
        my $status_code = $attributes->{$mapping->{status}}->[0];
        $status = $self->inspection_status($status_code);
    }

    my $reason_for_closure = $attributes->{$mapping->{reason_for_closure}} ?
        $attributes->{$mapping->{reason_for_closure}}->[0] :
        '';

    if ($reason_for_closure) {
        $status = $self->get_status_with_closure($status, $reason_for_closure);
    }

    ($status, $reason_for_closure) = $self->_status_and_closure_mapping($status, $reason_for_closure);

    return ($status, $reason_for_closure);
}

sub _status_and_closure_mapping {
    my ($self, $status, $reason_for_closure) = @_;

    if ( my $map = $self->config->{status_and_closure_mappping}->{$status} ) {
        $status = $map->{status};
        $reason_for_closure = $map->{reason_for_closure};
    }

    return ($status, $reason_for_closure);
}

sub _get_defect_updates {
    my ( $self, $args, $start_time, $end_time ) = @_;

    my @updates;
    # updates to defects
    my $closure_mapping = $self->config->{inspection_closure_mapping};
    my %reverse_closure_mapping = map { $closure_mapping->{$_} => $_ } keys %{$closure_mapping};

    my $mapping = $self->config->{defect_attribute_mapping};

    my $updates = $self->fetch_updated_resources($self->config->{defect_resource_name}, $args->{start_date});
    for my $update (@$updates) {
        next if $self->is_ignored_category( $update );

        my $linked_defect;
        my $attributes = $self->alloy->attributes_to_hash($update);

        my $service_request_id = $update->{itemId};

        # XXX check no longer required
        my $fms_id;
        if (my @ids = grep { $_ =~ /StreetDoctorID/ && $attributes->{$_} } keys %{ $attributes } ) {
            $fms_id = $ids[0];
        }

        # if it has a parent that is an enquiry get the resource id of the inspection and use that
        # as the external id so updates are added to the report that created the inspection
        for my $attribute (keys %$attributes) {
            if ( $attribute =~ /DefectInspection/) { # request for service
                $linked_defect = 1;
                $service_request_id = $attributes->{$attribute}->[0];
                $fms_id = undef;
                last;
            }
        }

        # we don't care about linked defects until they have been scheduled
        my $status = $self->defect_status($attributes->{$mapping->{status}});
        next if $linked_defect && ( $status eq 'open' || $status eq 'investigating' );

        my @version_ids = $self->get_versions_of_resource($update->{itemId});
        foreach my $date (@version_ids) {

            my $update_dt = $self->date_to_truncated_dt($date);
            my $resource = $self->alloy->api_call(call => "item-log/item/$update->{itemId}/reconstruct", body => { date => $date });
            next unless $resource && ref $resource eq 'HASH'; # Should always be, but some test calls

            $resource = $resource->{item};
            my $attributes = $self->alloy->attributes_to_hash($resource);
            my $status = $self->defect_status($attributes->{$mapping->{status}});

            my %args = (
                status => $status,
                update_id => $resource->{signature},
                service_request_id => $service_request_id,
                description => '',
                updated_datetime => $update_dt,
            );

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
    }

    return @updates;
}

sub get_service_requests {
    my ($self, $args) = @_;

    my $requests = $self->fetch_updated_resources($self->config->{defect_resource_name}, $args->{start_date});
    my @requests;
    my $mapping = $self->config->{defect_attribute_mapping};
    for my $request (@$requests) {
        my %args;

        next if $self->is_ignored_category( $request );

        my $linked_defect;
        for my $parent_info (@{ $request->{parents} } ) {
            $linked_defect = 1 if $parent_info->{attribute} =~ 'Request'; # request for service
        }
        next if $linked_defect;

        my $category = $self->get_defect_category( $request );
        unless ($category) {
            warn "No category found for defect $request->{itemId}, source type $request->{designCode} in " . $self->jurisdiction_id . "\n";
            next;
        }

        my $cat_service = $self->service($category);
        unless ($cat_service) {
            warn "No service found for defect $request->{itemId}, category $category in " . $self->jurisdiction_id . "\n";
            next;
        }

        $args{latlong} = $self->get_latlong_from_request($request);

        unless ($args{latlong}) {
            my $geometry = $request->{geometry};
            $self->logger->error("Defect $request->{itemId}: don't know how to handle geometry: $geometry->{type}");
            warn "Defect $request->{itemId}: don't know how to handle geometry: $geometry->{type}\n";
            next;
        }

        my $attributes = $self->alloy->attributes_to_hash($request);
        $args{description} = $self->get_request_description($attributes->{$mapping->{description}}, $request);
        $args{status} = $self->defect_status($attributes->{$mapping->{status}}->[0]);

        #XXX check this no longer required
        next if grep { $_ =~ /_FIXMYSTREET_ID$/ && $attributes->{$_} } keys %{ $attributes };

        my $service = Open311::Endpoint::Service->new(
            service_name => $category,
            service_code => $category,
        );
        $args{title} = $request->{title};
        $args{service} = $service;
        $args{service_request_id} = $request->{itemId};
        $args{requested_datetime} = $self->date_to_truncated_dt( $request->{start} );
        $args{updated_datetime} = $self->date_to_truncated_dt( $request->{start} );

        my $request = $self->new_request( %args );

        push @requests, $request;
    }

    return @requests;
}

sub get_request_description {
    my ($self, $desc) = @_;

    return $desc;
}

sub fetch_updated_resources {
    my ($self, $code, $start_date) = @_;

    my @results;

    my $body_base = {
        properties =>  {
            dodiCode => $code,
            attributes => ["all"],
        },
        children => [{
            type =>  "GreaterThan",
            children =>  [{
                type =>  "ItemProperty",
                properties =>  {
                    itemPropertyName =>  "lastEditDate"
                }
            },
            {
                type =>  "DateTime",
                properties =>  {
                    value =>  [$start_date]
                }
            }]
        }]
    };

    return $self->alloy->search( $body_base );
}

sub inspection_status {
    my ($self, $status) = @_;

    return $self->config->{inspection_status_mapping}->{$status} || 'open';
}

sub get_status_with_closure {
    my ($self, $status, $reason_for_closure) = @_;

    return $status unless $status eq 'closed';

    return $self->config->{inspection_closure_mapping}->{$reason_for_closure} || $status;
}

sub defect_status {
    my ($self, $status) = @_;

    $status = $status->[0] if ref $status eq 'ARRAY';
    return $self->config->{defect_status_mapping}->{$status} || 'open';
}

sub service_request_id_for_resource {
    my ($self, $resource) = @_;

    # get the Alloy inspection reference
    # This may be overridden by subclasses depending on the council's workflow.
    # This default behaviour just uses the resource ID which will always
    # be present.
    return $resource->{item}->{itemId};
}

sub get_versions_of_resource {
    my ($self, $resource_id) = @_;

    my $versions = $self->alloy->api_call(call => "item-log/item/$resource_id")->{results};

    my @version_ids = ();
    for my $version ( @$versions ) {
        push @version_ids, $version->{date};
    }

    @version_ids = sort(@version_ids);
    return @version_ids;
}

sub date_to_dt {
    my ($self, $date) = @_;

    return $self->date_parser->parse_datetime($date);
}

sub date_to_truncated_dt {
    my ($self, $date) = @_;

    return $self->date_to_dt($date)->truncate( to => 'second' );
}

sub get_latlong_from_request {
    my ($self, $request) = @_;

    my $latlong;

    my $geometry = $request->{geometry};

    if ( $geometry->{type} eq 'Point') {
        # convert from string because the validation expects numbers
        my ($x, $y) = map { $_ * 1 } @{ $geometry->{coordinates} };
        $latlong = [$y, $x];
    } elsif ( $geometry->{type} eq 'LineString') {
        my @points = @{ $geometry->{coordinates} };
        my $half = int( @points / 2 );
        $latlong = [ $points[$half]->[1], $points[$half]->[0] ];
    } elsif ( $geometry->{type} eq 'MultiLineString') {
        my @points;
        my @segments = @{ $geometry->{coordinates} };
        for my $segment (@segments) {
            push @points, @$segment;
        }
        my $half = int( @points / 2 );
        $latlong = [ $points[$half]->[1], $points[$half]->[0] ];
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
        $latlong = [ $y, $x ];
    }

    return $latlong;
}

sub is_ignored_category {
    my ($self, $defect) = @_;

    return grep { $defect->{designCode} eq $_ } @{ $self->config->{ ignored_defect_types } };
}

sub get_defect_category {
    my ($self, $defect) = @_;
    my $mapping = $self->config->{defect_sourcetype_category_mapping}->{ $defect->{designCode } };

    my $category = $mapping->{default};

    if ( $mapping->{types} ) {
        my @attributes = @{$defect->{attributes}};
        my $type;

        for my $att (@attributes) {
            if ($att->{attributeCode} =~ /DefectType/ ) {
                $type = $att->{value}->[0];
            }
        }

        $category = $mapping->{types}->{$type} if $type && $mapping->{types}->{$type};
    }

    return '' unless $category;
    return $category unless $self->group_in_service_code;

    my $group = $self->reverse_whitelist->{$category} || '';

    return "${group}_$category";
}

sub process_attributes {
    my ($self, $source, $args) = @_;

    # TODO: Right now this applies defaults regardless of the source type
    # This is OK whilst we have a single design, but we might need to
    # have source-type-specific defaults when multiple designs are in use.
    my $defaults = $self->config->{resource_attribute_defaults} || {};
    my @defaults = map { { value => $defaults->{$_}, attributeCode => $_} } keys %$defaults;

    # Some of the Open311 service attributes need remapping to Alloy resource
    # attributes according to the config...
    my $remapping = $self->config->{request_to_resource_attribute_mapping} || {};

    my @remapped = (
        @defaults,
        @{ $self->alloy->update_attributes( $args->{attributes}, $remapping, []) }
    );

    # Set the creation time for this resource to the current timestamp.
    # TODO: Should this take the 'confirmed' field from FMS?
    if ( $self->config->{created_datetime_attribute_id} ) {
        my $now = DateTime->now();
        my $created_time = DateTime::Format::W3CDTF->new->format_datetime($now);
        push @remapped, {
            attributeCode => $self->config->{created_datetime_attribute_id},
            value => $created_time
        };
    }

    return \@remapped;
}


sub _get_attachments {
    my ($self, $urls) = @_;

    my $ua = LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter");
    my @photos = map {
        $ua->get($_);
    } @$urls;

    return @photos;
}

sub upload_attachments {
    my ($self, $args) = @_;

    # grab the URLs and download its content
    my $media_urls = $args->{media_url};

    my @photos = $self->_get_attachments($args->{media_url});

    my $folder_id = $self->config->{attachment_folder_id};

    # upload the file to the folder, with a FMS-related name
    my @resource_ids = map {
        $self->alloy->api_call(
            call => "file",
            filename => $_->filename,
            body=> $_->content,
            is_file => 1
        )->{fileItemId};
    } @photos;

    return \@resource_ids;
}

sub _find_category_code {
    my ($self, $category) = @_;

    my $results = $self->alloy->search( {
            properties => {
                dodiCode => $self->config->{category_list_code},
                collectionCode => "Live"
            },
        }
    );

    for my $cat ( @{ $results } ) {
        return $cat->{itemId} if $cat->{title} eq $category;
    }
}

1;
