package Open311::Endpoint::Integration::AlloyV2;

use Digest::MD5 qw(md5_hex);
use Moo;
use Try::Tiny;
use DateTime::Format::W3CDTF;
use LWP::UserAgent;
use JSON::MaybeXS;
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
            push @services, $o311_service;
        }
    }

    return @services;
}

sub post_service_request {
    my ($self, $service, $args) = @_;
    die "No such service" unless $service;

    # this is a display only thing for the website
    delete $args->{attributes}->{emergency};

    # extract attribute values
    my $resource_id = $args->{attributes}->{asset_resource_id} || '';

    my $parent_attribute_id;


    my $resource = {
        # This appears to be shared amongst all asset types for now,
        # as everything is based off one design.
        designCode => $self->config->{rfs_design},
    };

    $self->_set_parent_attribute($resource, $resource_id);

    # The Open311 attributes received from FMS may not include all the
    # the attributes we need to fully describe the Alloy resource,
    # and indeed these may change on a per-source or per-council basis.
    # Call out to process_attributes which can manipulate the resource
    # attributes (apply defaults, calculate values) as required.
    # This may be overridden by a subclass for council-specific things.
    $resource->{attributes} = $self->process_attributes($args);

    # XXX try this first so we bail if we can't upload the files
    my $files = [];
    if ( $self->config->{resource_attachment_attribute_id} && (@{$args->{media_url}} || @{$args->{uploads}})) {
        $files = $self->upload_media($args);
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
        my $attributes = [{ attributeCode => $self->config->{resource_attachment_attribute_id}, value => $files }];
        $self->_update_item($item_id, $attributes);
    }

    # create a new Request and return it
    return $self->new_request(
        service_request_id => $item_id
    );

}

sub _update_item {
    my ($self, $item_id, $attributes) = @_;

    my $item = $self->alloy->api_call(call => "item/$item_id");

    my $updated = {
        attributes => $attributes,
        signature => $item->{item}->{signature}
    };

    my $update;
    try {
        $update = $self->alloy->api_call(
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
                $update = $self->alloy->api_call(
                    call => "item/$item_id",
                    method => 'PUT',
                    body => $updated
                );
            } catch {
                $self->logger->warn($_);
            }
        } else {
            $self->logger->warn($_);
        }
    };

    return $update;
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
            die "no parent attribute id found for asset $resource_id with type $resource_type";
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

sub _find_or_create_contact {
    my ($self, $args) = @_;

    if (my $contact = $self->_find_contact($args->{email})) {
        return $contact->{itemId};
    } else {
        return $self->_create_contact($args)->{item}->{itemId};
    }
}

sub _find_contact {
    my ($self, $email, $phone) = @_;

    my ($attribute_code, $search_term);
    if ( $email ) {
        $search_term = $email;
        $attribute_code = $self->config->{contact}->{search_attribute_code_email};
    } elsif ( $phone ) {
        $search_term = $phone;
        $attribute_code = $self->config->{contact}->{search_attribute_code_phone};
    } else {
        return undef;
    }

    my $body = {
        properties => {
            dodiCode => $self->config->{contact}->{code},
            collectionCode => "Live",
            attributes => [ $attribute_code ],
        },
        children => [
            {
                type => "Equals",
                children => [
                    {
                        type => "Attribute",
                        properties => {
                            attributeCode => $attribute_code,
                        },
                    },
                    {
                        type => "String",
                        properties => {
                            value => [ $search_term ]
                        }
                    }
                ]
            }
        ]
    };

    my $results = $self->alloy->search($body);

    return undef unless @$results;
    my $contact = $results->[0];

    # Sanity check that the user we're returning actually has the correct email
    # or phone, just in case Alloy returns something
    my $a = $self->alloy->attributes_to_hash( $contact );
    return undef unless $a->{$attribute_code} && $a->{$attribute_code} eq $search_term;

    return $contact;
}

sub _create_contact {
    my ($self, $args) = @_;

    # For true/false values we have to use the JSON()->true/false otherwise
    # when we convert to JSON later we get 1/0 which then fails the validation
    # at the Alloy end
    # NB: have to use 'true'/'false' strings in the YAML for this to work. If we
    # use true/false then it gets passed in as something that gets converted to 1/0
    #
    # we could possibly use local $YAML::XS::Boolean = "JSON::PP" in the Config module
    # to get round all this but not sure if that would break something else.
    my $defaults = {
        map {
            $_ => $self->config->{contact}->{attribute_defaults}->{$_} =~ /^(true|false)$/
                ? JSON()->$1
                : $self->config->{contact}->{attribute_defaults}->{$_}
        } keys %{ $self->config->{contact}->{attribute_defaults} }
    };

    # phone cannot be null;
    $args->{phone} ||= '';

    # XXX should use the created time of the report?
    my $now = DateTime->now();
    my $created_time = DateTime::Format::W3CDTF->new->format_datetime($now);
    $args->{created} = $created_time;

    # include the defaults which map to themselves in the mapping
    my $remapping = {
        %{$self->config->{contact}->{attribute_mapping}},
        map {
            $_ => $_
        } keys %{ $self->config->{contact}->{attribute_defaults} }
    };

    $args = {
        %$args,
        %$defaults
    };

    my @attributes = @{ $self->alloy->update_attributes( $args, $remapping, []) };

    my $contact = {
        designCode => $self->config->{contact}->{code},
        attributes => \@attributes,
        geometry => undef,
    };

    return $self->alloy->api_call(
        call => "item",
        body => $contact
    );
}

sub post_service_request_update {
    my ($self, $args) = @_;

    my $resource_id = $args->{service_request_id};
    my $item = $self->alloy->api_call(call => "item/$resource_id")->{item};

    my $attributes = $self->alloy->attributes_to_hash($item);
    my $attribute_code = $self->config->{inspection_attribute_mapping}->{updates} || $self->config->{defect_attribute_mapping}->{updates};
    my $updates = $attributes->{$attribute_code} || '';

    $updates = $self->_generate_update($args, $updates);

    my $updated_attributes = [{
        attributeCode => $attribute_code,
        value => $updates
    }];

    if ( $self->config->{resource_attachment_attribute_id} && @{ $args->{media_url} }) {
        push @$updated_attributes, {
            attributeCode => $self->config->{resource_attachment_attribute_id},
            value => $self->upload_media($args)
        };
    }

    my $update = $self->_update_item($resource_id, $updated_attributes);

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

    my @updates;
    push @updates, $self->_get_inspection_updates($args);
    push @updates, $self->_get_defect_updates($args);

    return sort { $a->updated_datetime <=> $b->updated_datetime } @updates;
}

sub _get_inspection_updates {
    my ($self, $args) = @_;

    my $start_time = $self->date_to_dt($args->{start_date});
    my $end_time = $self->date_to_dt($args->{end_date});

    my @updates;

    my $mapping = $self->config->{inspection_attribute_mapping};
    return () unless $mapping;
    my $updates = $self->fetch_updated_resources($self->config->{rfs_design}, $args->{start_date}, $args->{end_date});
    for my $update (@$updates) {
        next unless $self->_accept_updated_resource($update);

        # We need to fetch all versions that changed in the time wanted
        my @version_ids = $self->get_versions_of_resource($update->{itemId});

        my $last_description = '';
        foreach my $date (@version_ids) {
            next unless $self->_valid_update_date($update, $date);
            # we have to fetch all the updates as we need them to check if the
            # comments have changed. once we've fetched them we can throw away the
            # ones that don't match the date range.
            my $resource = try {
                $self->alloy->api_call(call => "item-log/item/$update->{itemId}/reconstruct", body => { date => $date });
            };
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

sub _valid_update_date { return 1; }

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

    if ( my $map = $self->config->{status_and_closure_mapping}->{$status} ) {
        $status = $map->{status};
        $reason_for_closure = $map->{reason_for_closure};
    }

    return ($status, $reason_for_closure);
}

sub _get_defect_updates {
    my ( $self, $args ) = @_;

    my @updates;
    my $resources = $self->config->{defect_resource_name};
    $resources = [ $resources ] unless ref $resources eq 'ARRAY';
    foreach (@$resources) {
        push @updates, $self->_get_defect_updates_resource($_, $args);
    }
    return @updates;
}

sub _get_defect_updates_resource {
    my ($self, $resource_name, $args) = @_;

    my $start_time = $self->date_to_dt($args->{start_date});
    my $end_time = $self->date_to_dt($args->{end_date});

    my @updates;
    my $closure_mapping = $self->config->{inspection_closure_mapping};
    my %reverse_closure_mapping = map { $closure_mapping->{$_} => $_ } keys %{$closure_mapping};

    my $updates = $self->fetch_updated_resources($resource_name, $args->{start_date}, $args->{end_date});
    for my $update (@$updates) {
        next if $self->is_ignored_category( $update );

        my $linked_defect;
        my $attributes = $self->alloy->attributes_to_hash($update);

        my $service_request_id = $update->{itemId};

        my $fms_id = $self->_get_defect_fms_id( $attributes );

        ($linked_defect, $service_request_id) = $self->_get_defect_inspection($update, $service_request_id);
        $fms_id = undef if $linked_defect;

        # we don't care about linked defects until they have been scheduled
        my $status = $self->defect_status($attributes);
        next if $linked_defect && ( $status eq 'open' || $status eq 'investigating' );

        my @version_ids = $self->get_versions_of_resource($update->{itemId});
        foreach my $date (@version_ids) {
            next unless $self->_valid_update_date($update, $date);

            my $update_dt = $self->date_to_truncated_dt($date);
            next unless $update_dt >= $start_time && $update_dt <= $end_time;

            my $resource = try {
                $self->alloy->api_call(call => "item-log/item/$update->{itemId}/reconstruct", body => { date => $date });
            };
            next unless $resource && ref $resource eq 'HASH'; # Should always be, but some test calls

            $resource = $resource->{item};
            my $attributes = $self->alloy->attributes_to_hash($resource);
            my $status = $self->defect_status($attributes);

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

    my $resources = $self->config->{defect_resource_name};
    $resources = [ $resources ] unless ref $resources eq 'ARRAY';
    my @requests;
    foreach (@$resources) {
        push @requests, $self->_get_service_requests_resource($_, $args);
    }
    return @requests;
}

sub _get_service_requests_resource {
    my ($self, $resource_name, $args) = @_;

    my $requests = $self->fetch_updated_resources($resource_name, $args->{start_date}, $args->{end_date});
    my @requests;
    my $mapping = $self->config->{defect_attribute_mapping};
    for my $request (@$requests) {
        my %args;

        next if $self->skip_fetch_defect( $request );

        my $category = $self->get_defect_category( $request );
        unless ($category) {
            $self->logger->warn("No category found for defect $request->{itemId}, source type $request->{designCode} in " . $self->jurisdiction_id);
            next;
        }

        my $cat_service = $self->service($category);
        unless ($cat_service) {
            $self->logger->warn("No service found for defect $request->{itemId}, category $category in " . $self->jurisdiction_id);
            next;
        }

        $args{latlong} = $self->get_latlong_from_request($request);

        unless ($args{latlong}) {
            my $geometry = $request->{geometry}{type} || 'unknown';
            $self->logger->error("Defect $request->{itemId}: don't know how to handle geometry: $geometry");
            next;
        }

        my $attributes = $self->alloy->attributes_to_hash($request);
        $args{description} = $self->get_request_description($attributes->{$mapping->{description}}, $request);
        $args{status} = $self->defect_status($attributes);

        #XXX check this no longer required
        next if grep { $_ =~ /_FIXMYSTREET_ID$/ && $attributes->{$_} } keys %{ $attributes };

        my $service = Open311::Endpoint::Service->new(
            service_name => $category,
            service_code => $category,
        );
        $args{title} = $attributes->{attributes_itemsTitle};
        $args{service} = $service;
        $args{service_request_id} = $request->{itemId};
        $args{requested_datetime} = $self->date_to_truncated_dt( $attributes->{$mapping->{requested_datetime}} );
        $args{updated_datetime} = $self->date_to_truncated_dt( $attributes->{$mapping->{requested_datetime}} );

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
    my ($self, $code, $start_date, $end_date) = @_;

    my @results;

    my $body_base = {
        properties =>  {
            dodiCode => $code,
            attributes => ["all"],
        },
        children => [{
            type => "And",
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
            }, {
                type =>  "LessThan",
                children =>  [{
                    type =>  "ItemProperty",
                    properties =>  {
                        itemPropertyName =>  "lastEditDate"
                    }
                },
                {
                    type =>  "DateTime",
                    properties =>  {
                        value =>  [$end_date]
                    }
                }]
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
    my ($self, $defect) = @_;

    my $mapping = $self->config->{defect_attribute_mapping};
    my $status = $defect->{$mapping->{status}};

    $status = $status->[0] if ref $status eq 'ARRAY';
    return $self->config->{defect_status_mapping}->{$status} || 'open';
}

sub skip_fetch_defect {
    my ( $self, $defect ) = @_;

    return 1 if $self->is_ignored_category( $defect ) ||
        $self->_get_defect_inspection_parents( $defect );

    return 0;
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

    my $attributes = $request->{attributes};
    my @attribs = grep { $_->{attributeCode} eq 'attributes_itemsGeometry' } @$attributes;
    return unless @attribs;
    my $geometry = $attribs[0]->{value};

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
            if ($att->{attributeCode} =~ /DefectType|DefectFaultType|lightingJobJobType/) {
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
    my ($self, $args) = @_;

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
    push @remapped, {
        attributeCode => "attributes_itemsGeometry",
        value => {
            type => "Point",
            coordinates => [$args->{long}, $args->{lat}],
        }
    };

    return \@remapped;
}

sub _get_defect_fms_id { return undef; }

sub _get_defect_inspection {
    my ($self, $defect, $service_request_id) = @_;

    my $linked_defect;
    my @inspections = $self->_get_defect_inspection_parents($defect);
    if (@inspections) {
        $linked_defect = 1;
        $service_request_id = $inspections[0];
    }
    return ($linked_defect, $service_request_id);
}

sub _get_defect_inspection_parents {
    my ($self, $defect) = @_;

    my $parents = $self->alloy->api_call(call => "item/$defect->{itemId}/parents")->{results};
    my @linked_defects;
    foreach (@$parents) {
        push @linked_defects, $_->{itemId} if $_->{designCode} eq $self->config->{rfs_design};
    }

    return @linked_defects;
}

sub _get_attachments {
    my ($self, $urls) = @_;

    my $ua = LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter");
    my @photos = map {
        $ua->get($_);
    } @$urls;

    return @photos;
}

sub upload_media {
    my ($self, $args) = @_;

    if ( @{ $args->{media_url} }) {
        return $self->upload_urls( $args->{media_url} );
    } elsif ( @{ $args->{uploads} } ) {
        return $self->upload_attachments( $args->{uploads} );
    }
}

sub upload_urls {
    my ($self, $media_urls) = @_;

    # download the photo from provided URLs
    my @photos = $self->_get_attachments($media_urls);

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

sub upload_attachments {
    my ($self, $uploads) = @_;

    my @resource_ids = map {
        $self->alloy->api_call(
            call => "file",
            filename => $_->filename,
            body=> path($_)->slurp,
            is_file => 1
        )->{fileItemId};
    } @{ $uploads };

    return \@resource_ids;
}

sub _find_category_code {
    my ($self, $category) = @_;

    my $results = $self->alloy->search( {
            properties => {
                dodiCode => $self->config->{category_list_code},
                attributes => ["all"],
                collectionCode => "Live"
            },
        }
    );

    for my $cat ( @{ $results } ) {
        my $a = $self->alloy->attributes_to_hash($cat);
        return $cat->{itemId} if $a->{$self->config->{category_title_attribute}} eq $category;
    }
}

1;
