=head1 NAME

Open311::Endpoint::Integration::AlloyV2 - An integration with the Alloy backend

=head1 SYNOPSIS

This integration lets us post reports and updates to and from Alloy. It calls
posted reports 'inspections' and fetches reports as 'defects', and fetches
updates on both, but these are sometimes misnamed - 'inspections' are usually
defects in Alloy, and 'defects' could also be jobs.

=head1 CONFIGURATION

Alloy is entirely customisable, so a 'design' can contain any collection of
unique attributes. So our configuration needs to consist of a number of
mappings of data we hold to how it will fit into what is present in Alloy.

=cut

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
use Open311::Endpoint::Service::Request::Alloy;
use Open311::Endpoint::Service::Request::Update::mySociety;

use Path::Tiny;


has jurisdiction_id => (
    is => 'ro',
);

has '+request_class' => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::Request::Alloy',
);

has '+identifier_types' => (
    is => 'lazy',
    isa => HashRef[Any],
    default => sub {
        my $self = shift;
        return {
            # some service codes have spaces, ampersands, commas, etc
            service_code => { type => '/open311/regex', pattern => qr/^ [&,\.\w_\- \/\(\)]+ $/ax },
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

=head2 service_whitelist

This is a mapping of Alloy services, from group to categories, each category
being a key with value 1 or a map. (Not sure why.)
Both groups and categories can have an 'alias' field set in their maps. This lets you expose the group or category under a different name than used by Alloy.

=cut

has service_whitelist => (
    is => 'ro',
    default => sub {
        return {} if $ENV{TEST_MODE};
        die "Attribute Alloy::service_whitelist not overridden";
    }
);

=head2 update_store

Directory for storing reconstructions of Alloy items to save on API calls

=cut

has update_store => ( is => 'ro' );

=head1 DESCRIPTION

=head2 services

This returns a list of Alloy services from the C<service_whitelist>,
with no extra attributes possible.

=cut

sub services {
    my $self = shift;

    my @services = ();
    my %services;
    my %suffixes;
    for my $group (sort keys %{ $self->service_whitelist }) {

        my $group_config = $self->service_whitelist->{$group};
        my $group_alias;
        if (ref($group_config) eq 'HASH' && exists($group_config->{alias})) {
            $group_alias = $group_config->{alias};
        }
        my $group_name = $group_alias || $group;

        for my $subcategory (sort keys %{ $group_config }) {
            next if $subcategory eq 'alias';
            my $subcategory_config = $self->service_whitelist->{$group}->{$subcategory};
            my $subcategory_alias;
            if (ref($subcategory_config) eq 'HASH' && exists($subcategory_config->{alias})) {
                $subcategory_alias = $subcategory_config->{alias};
            }
            my $subcategory_name = $subcategory_alias || $subcategory;

            (my $code = $subcategory) =~ s/ /_/g;
            if ($subcategory_alias) {
                $code .= '_' . ++$suffixes{$code};
            }
            if ($services{$code}) {
                push @{$services{$code}->groups}, $group_name;
                next;
            }

            my %service = (
                service_name => $subcategory_name,
                description => $subcategory_name,
                service_code => $code,
                groups => [ $group_name ],
            );
            my $o311_service = $self->service_class->new(%service);
            push @services, $o311_service;
            $services{$code} = $o311_service;
        }
    }

    return @services;
}

=head2 post_service_request

Requests are posted to the C<rfs_design> configuration value. If an asset is
passed, its design is looked up, and that design's C<parent_attribute_name>
attribute is set as the item's parent. Attributes are processed by
L</process_attributes>. An item is then created in Alloy, and photos uploaded
and linked in the C<resource_attachment_attribute_id> attribute.

=cut

sub post_service_request {
    my ($self, $service, $args) = @_;
    die "No such service" unless $service;

    # this is a display only thing for the website
    delete $args->{attributes}->{emergency};

    # extract attribute values
    my $resource_id = $args->{attributes}->{asset_resource_id} || '';

    my $category = $args->{service_code};
    $category =~ s/(_\d+)+$//;
    $category =~ s/_/ /g;
    $args->{service_code_alloy} = $category;

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

=head2 _find_or_create_contact

This searches Alloy for the provided email, returning either the found item ID
or creating a new contact if none found.

=cut

sub _find_or_create_contact {
    my ($self, $args) = @_;

    if (my $contact = $self->_find_contact($args->{email})) {
        return $contact->{itemId};
    } else {
        return $self->_create_contact($args)->{item}->{itemId};
    }
}

=head2 _find_contact

This searches the C<contact.code> design in Alloy for either an email or phone,
using the C<contact.search_attribute_code_email> or
C<contact.search_attribute_code_phone> attributes.

=cut

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

=head2 _create_contact

This creates a C<contact.code> item. It gets defaults from
C<contact.attribute_defaults>, a mapping of attribute and value, and
C<contact.attribute_mapping> to map Open311 data to Alloy attribute.

=cut

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

=head2 post_service_request_update

This fetches the relevant item from Alloy and adds the update text to the
relevant attribute as given in either the C<inspection_attribute_mapping> or
C<defect_attribute_mapping> updates key. It also uploads a photo if given.

=cut

sub post_service_request_update {
    my ($self, $args) = @_;

    my $resource_id = $args->{service_request_id};
    my $item = $self->alloy->api_call(call => "item/$resource_id")->{item};

    my $attributes = $self->alloy->attributes_to_hash($item);
    my $attribute_code = $self->config->{inspection_attribute_mapping}->{updates} || $self->config->{defect_attribute_mapping}->{updates};
    my $updates = $attributes->{$attribute_code} || '';

    $updates = $self->_generate_update($args, $updates);

    my $updated_attributes = $self->update_additional_attributes($args);

    push @$updated_attributes, {
        attributeCode => $attribute_code,
        value => $updates
    };

    if ( $self->config->{resource_attachment_attribute_id} && (@{$args->{media_url}} || @{$args->{uploads}})) {
        my $attachment_code = $self->config->{resource_attachment_attribute_id};
        my $attachments = $attributes->{$attachment_code} || [];
        my $new_attachments = $self->upload_media($args);
        push(@$attachments, @$new_attachments);
        push @$updated_attributes, {
            attributeCode => $attachment_code,
            value => $attachments
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

=head2 get_service_request_updates

Fetching updates fetches both 'inspections' and 'defects'.

=cut

sub get_service_request_updates {
    my ($self, $args) = @_;

    if (my $dir = $self->update_store) {
        path($dir)->mkpath;
    }

    my @updates;
    push @updates, $self->_get_inspection_updates($args);
    push @updates, $self->_get_defect_updates($args);

    return sort { $a->updated_datetime <=> $b->updated_datetime } @updates;
}

=head3 'Inspections'

'Inspection' updates fetch the C<rfs_design> resources that have been updated
in the relevant time frame, fetching previous versions of each item.
It uses C<inspection_attribute_mapping> for attribute mapping:

=over 4

=item C<status>

Used to find the attribute to then use as a key in C<inspection_status_mapping>
to work out a state for the update.

=item C<reason_for_closure>

Used to find the attribute containing the external status code. It also, if the
status is closed, uses C<inspection_closure_mapping> to perhaps change to a
different status based on the C<reason_for_closure>.
C<status_and_closure_mapping> is a mapping from status to status and reason for
closure that can be used to override these at the end.

=item C<inspector_comments>

Used to find the attribute to look at to see if the comments have changed, for
providing as the text update.

=back

=cut

sub _get_inspection_updates {
    my ($self, $args) = @_;

    my $start_time = $self->date_to_dt($args->{start_date});
    my $end_time = $self->date_to_dt($args->{end_date});

    my @updates;

    my $mapping = $self->config->{inspection_attribute_mapping};
    return () unless $mapping;
    my $updates = $self->fetch_updated_resources($self->config->{rfs_design}, $args->{start_date}, $args->{end_date});

    my $assigned_to_users = $self->get_assigned_to_users(@$updates);

    for my $update (@$updates) {
        next unless $self->_accept_updated_resource($update);

        # We need to fetch all versions that changed in the time wanted
        my @version_ids = $self->get_versions_of_resource($update->{itemId});

        my $last_description = '';
        foreach my $date (@version_ids) {
            my $description_to_send = '';
            my $update_dt;

            # If we don't need to compare the comments field, we can
            # consider updates only within the desired date range
            if (!$mapping->{inspector_comments}) {
                $update_dt = $self->date_to_truncated_dt( $date );
                next unless $update_dt >= $start_time && $update_dt <= $end_time;
            }

            my $resource = $self->call_reconstruct($update->{itemId}, $date) or next;
            my $attributes = $self->alloy->attributes_to_hash($resource);

            my ($status, $reason_for_closure) = $self->_get_inspection_status($attributes, $mapping);

            # If we are checking if the comments field has changed, we will
            # have to fetch all the updates. Once we've fetched them we can
            # throw away the ones that don't match the date range.
            if ($mapping->{inspector_comments}) {
                my $description = $attributes->{$mapping->{inspector_comments} || ''} || '';
                # only want to put a description in the update if it's
                # changed, so compare it to the last one.
                $description_to_send = $description ne $last_description ? $description : '';
                $last_description = $description;

                $update_dt = $self->date_to_truncated_dt( $date );
                next unless $update_dt >= $start_time && $update_dt <= $end_time;
            }

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

            if ( my $assigned_to_user_id
                = $attributes->{ $mapping->{assigned_to_user} // '' }[0] )
            {
                my $assigned_to_user
                    = $assigned_to_users->{$assigned_to_user_id} ||= do {
                    # There is a possibility the assigned-to user is not
                    # already in the $assigned_to_users hash; do another
                    # lookup if so
                    $self->get_assigned_to_users($resource)
                        ->{$assigned_to_user_id}
                };

                $args{extras} = $assigned_to_user if $assigned_to_user;
            }

            push @updates, Open311::Endpoint::Service::Request::Update::mySociety->new( %args );
        }
    }

    return @updates;
}

sub get_assigned_to_users {
    # Currently for Northumberland only
    return {};
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

    my $reason_for_closure = $mapping->{reason_for_closure} && $attributes->{$mapping->{reason_for_closure}} ?
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

=head3 'Defects'

'Defect' updates can fetch more than one design from C<defect_resource_name>,
it being either a string or an array. This also fetches any items altered in
the time frame. It ignores any whose designCode matches any entry in
C<ignored_defect_types>. It has the possibility of working out the FMS ID from
an attribute, but this is unused.

It fetches the item's parents to find any that have a C<rfs_design> designCode,
assuming that's the 'inspection' associated with the 'defect' (or indeed, the
defect associated with the job).

It uses the C<defect_attribute_mapping> status entry to find the attribute
containing the status, and then uses C<defect_status_mapping> to map that
Alloy value to a status.

If the status is open or investigating and there is a linked defect, the update
is skipped.

Previous versions are fetched, as with 'inspections', their status worked out;
there are no text attributes checked here. It has some special code that I'm
not sure still applies, to prevent FMS adding phantom updates due to confusion
over external status codes.

=cut

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
        next if $self->_skip_job_update($linked_defect, $status);

        my @version_ids = $self->get_versions_of_resource($update->{itemId});
        foreach my $date (@version_ids) {
            my $update_dt = $self->date_to_truncated_dt($date);
            next unless $update_dt >= $start_time && $update_dt <= $end_time;

            my $resource = $self->call_reconstruct($update->{itemId}, $date) or next;
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

sub _skip_job_update {
    my ($self, $linked_defect, $status) = @_;

    return $linked_defect && ( $status eq 'open' || $status eq 'investigating' );
}

=head2 get_service_requests

This also uses the C<defect_resource_name>, either a string or an array, to
fetch any new reports in those designs. As with updates, it fetches any
resources updated in the time window. It ignores any in C<ignored_defect_types>
or any with a C<rfs_design> parent.

It uses C<defect_sourcetype_category_mapping> on the designCode to fetch a
default and a possible types mapping, which it uses to set a category if it
finds an attribute with a particular fixed list of matches. It also might
use the C<service_whitelist> to add the group name to the category.

If it doesn't match a category, or it's not a known category, it skips the
item. It also skips if it finds an attribute ending C<_FIXMYSTREET_ID>.

It fetches the geometry, converting any non-point into a point. It uses
C<defect_attribute_mapping> description key to fetch the description text,
status (plus C<defect_status_mapping> as with updates) to fetch a status,
requested_datetime to fetch the time, but always uses the fixed
attributes_itemsTitle for the title.

=cut

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
        $category =~ s/ /_/g;

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
            service_name => $cat_service->service_name,
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
    my $source_map = $self->config->{defect_sourcetype_category_mapping};
    my $category_map = $source_map->{ $defect->{designCode} } || $source_map->{default};
    my $category = $category_map->{default};

    if ( $category_map->{types} ) {
        my @attributes = @{$defect->{attributes}};
        my $type;

        for my $att (@attributes) {
            if ($att->{attributeCode} =~ /DefectType|DefectFaultType|lightingJobJobType/) {
                $type = $att->{value}->[0];
            }
        }

        $category = $category_map->{types}->{$type} if $type && $category_map->{types}->{$type};
    }

    return $category || '';
}

=head2 process_attributes

Normally extended by a particular integration subclass. This function
uses the C<resource_attribute_defaults> configuration to set any default
attributes, then loops through C<request_to_resource_attribute_mapping>
a mapping from passed-in attributes to Alloy attribute IDs, and then if
C<created_datetime_attribute_id> is set to an Alloy attribute, sets that
to the current time. Geometry is also set to the lat/long passed in.

=cut

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

    my @photos = ();
    my $ua = LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter");
    for (@$urls) {
        my $response = $ua->get($_);
        if ($response->is_success) {
            push @photos, $response;
        } else {
            $self->logger->warn("Unable to download attachment " . $_);
        }
    }
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

=head2 update_additional_attributes

Extended by a particular intregration subclass to update additional alloy attributes when processing a service request update.

=cut

sub update_additional_attributes {
    return [];
}

=head2 _search_for_code

This looks up the provided code design in Alloy, returning its data.

=cut

sub _search_for_code {
    my ($self, $code) = @_;
    my $results = $self->alloy->search({
        properties => {
            dodiCode => $code,
            attributes => ["all"],
            collectionCode => "Live"
        },
    });
    for (@$results) {
        $_->{attributes} = $self->alloy->attributes_to_hash($_);
    }
    return $results;
}

=head2 _find_category_code

This looks up the C<category_list_code> design in Alloy, and finds the entry
with a C<category_title_attribute> attribute that matches the provided
category.

=cut

sub _find_category_code {
    my ($self, $category) = @_;

    my $results = $self->_search_for_code($self->config->{category_list_code});
    for my $cat ( @{ $results } ) {
        return $cat->{itemId} if $cat->{attributes}{$self->config->{category_title_attribute}} eq $category;
    }
}

=head2 _find_group_code

This looks up the C<group_list_code> design in Alloy, finds the entry
with a C<group_title_attribute> attribute that matches the provided
group, and returns its item ID.

=cut

sub _find_group_code {
    my ($self, $group) = @_;
    my $results = $self->_search_for_code($self->config->{group_list_code});
    for my $grp ( @{ $results } ) {
        if ( $grp->{attributes}{$self->config->{group_title_attribute}} eq $group ) {
            return $grp->{itemId};
        }
    }
}

sub call_reconstruct {
    my ($self, $id, $date) = @_;

    my ($dir, $file);
    if ($dir = $self->update_store) {
        $file = path($dir)->child("$id-$date.json");
        if ($file->exists) {
            return decode_json($file->slurp_raw)->{item};
        }
    }

    my $resource = try {
        $self->alloy->api_call(call => "item-log/item/$id/reconstruct", body => { date => $date });
    };
    return unless $resource && ref $resource eq 'HASH'; # Should always be, but some test calls

    if ($file) {
        $file->spew_raw(encode_json($resource));
    }

    return $resource->{item};
}

1;
