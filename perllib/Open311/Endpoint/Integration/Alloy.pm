package Open311::Endpoint::Integration::Alloy;

use Moo;
use DateTime::Format::W3CDTF;
use LWP::UserAgent;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Open311::Endpoint::Role::ConfigFile';

use Open311::Endpoint::Service::UKCouncil::Alloy;
use Open311::Endpoint::Service::Attribute;
use Open311::Endpoint::Service::Request::CanBeNonPublic;

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

has alloy => (
    is => 'lazy',
    default => sub { $_[0]->integration_class->new }
);

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
    default => sub { die "Attribute Alloy::service_whitelist not overridden"; }
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
        my $resource_type = $self->alloy->api_call("resource/$resource_id")->{sourceTypeId};
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
    my $response = $self->alloy->api_call("resource", undef, $resource);

    # create a new Request and return it
    return $self->new_request(
        service_request_id => $self->service_request_id_for_resource($response)
    );

}

sub service_request_id_for_resource {
    my ($self, $resource) = @_;

    # get the Alloy inspection reference
    # This may be overridden by subclasses depending on the council's workflow.
    # This default behaviour just uses the resource ID which will always
    # be present.
    return $resource->{resourceId};
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

    my $point = $self->alloy->api_call("projection/point", {
        x => $lon,
        y => $lat,
        srcCode => "4326",
        dstCode => "900913",
    });

    return [ $point->{x}, $point->{y} ];
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
        $self->alloy->api_call("file", {
            'model.folderId' => $folder_id,
            'model.name' => $_->filename
        }, $_->content, 1)->{resourceId};
    } @photos;

    # return a list of the form
    my @commands = map { {
        command => "add",
        resourceId => $_,
    } } @resource_ids;

    return \@commands;
}

1;
