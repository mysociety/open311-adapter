=head1 NAME

Open311::Endpoint::Integration::Echo - An integration with the Echo backend

=head1 SYNOPSIS

This integration lets us post reports (as Events) and updates (as Event
Actions) to Echo. There is no way to fetch updates, these are instead
pushed to us by Echo or fetched directly.

=cut

package Open311::Endpoint::Integration::Echo;

use v5.14;
use utf8;

use Moo;
use JSON::MaybeXS;
use MIME::Base64 qw(encode_base64);

extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Open311::Endpoint::Role::ConfigFile';
with 'Role::Logger';

use Integrations::Echo;
use Open311::Endpoint::Service::Attribute;
use Open311::Endpoint::Service::UKCouncil::Echo;
use Open311::Endpoint::Service::Request::Update::mySociety;

has jurisdiction_id => ( is => 'ro' );

=head1 CONFIGURATION

=head2 service_whitelist

A mapping from event type ID (or string if multiple event types behind one
service) to event type description. Groups are also supported, by having
a sub-mapping under the group name. For example:

  service_whitelist:
    102: 'Request new container'
    missed: 'Report missed collection'
    Graffiti and fly-posting:
      201: 'Offensive graffiti'
      202: 'Non-offensive graffit

=cut

has service_whitelist => ( is => 'ro' );

=head2 waste_services

A list of which service codes are waste services,
so that information can be passed back.

=cut

has waste_services => ( is => 'ro', default => sub { [] } );

=head2 service_mapping

A mapping of 'service code' to service code (used when the
incoming service codes don't match that actually in use).

=cut

has service_mapping => ( is => 'ro', default => sub { {} } );

=head2 service_extra_data

This lets you list extra attributes that should be added for a particular
category. It is a mapping from service code to a sub-mapping of attribute key
and "1" (for a non-required hidden field), a text string description
for a textarea required question field, or a hash for a dropdown list

=cut

has service_extra_data => ( is => 'ro', default => sub { {} } );

=head2 service_to_event_type

A mapping of service code and Echo service ID to event type (used
for the case of multiple event types behind one service).

=cut

has service_to_event_type => ( is => 'ro', default => sub { {} } );

=head2 service_id_override

A mapping when a particular event type requires a particular
service, not the service chosen by the user

=cut

has service_id_override => ( is => 'ro' );

=head2 data_key_open311_map

A mapping from event type data field name to Open311 request field name, for
fields that are not attributes (e.g. first_name, email). Can be restricted to a
particular event type ID by having it as a submapping under the event type ID.

=cut

has data_key_open311_map => ( is => 'ro', default => sub { {} } );

=head2 data_key_attribute_map

A mapping from event type data field name to Open311 attribute field name.
Ideally, things are passed through from FMS with the same name, but this is for
if they are not. As above, can be restricted to a particular event type ID with
a submapping. The general mapping only applies to non-waste services, but an
event type ID submapping can apply to anything.

=cut

has data_key_attribute_map => ( is => 'ro', default => sub { {} } );

=head2 default_data_all

A mapping of event type data field name and its default, for any request.

=cut

has default_data_all => ( is => 'ro', default => sub { {} } );

=head2 default_data_event_type

A mapping of event type to data field defaults only for that event type.

=cut

has default_data_event_type => ( is => 'ro', default => sub { {} } );

=head2 client_reference_prefix

A prefix to use in the default client reference (with FMS ID appended).

=cut

has client_reference_prefix => ( is => 'ro', default => 'FMS' );

has service_class => ( is => 'ro', default => 'Open311::Endpoint::Service::UKCouncil::Echo' );

has ua => (
    is => 'lazy',
    default => sub {
        LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter")
    },
);

=head1 DESCRIPTION

=head2 services

This returns a list of Echo services from the service_whitelist, and whether
they are waste servies or not. It includes any attributes listed in the
C<service_extra_data> configuration.

=cut

sub services {
    my $self = shift;

    my $services = $self->service_whitelist;
    my %waste_services = map { $_ => 1 } @{$self->waste_services};
    my %services;
    my @services = map {
        my ($group, $cats);
        if (ref $services->{$_} eq 'HASH') {
            # Group + services
            $group = $_;
            $cats = $services->{$_};
        } else {
            # Just a service
            $cats = { $_ => $services->{$_} };
        }
        my @services;
        foreach (sort keys %$cats) {
            if ($services{$_}) {
                push @{$services{$_}->groups}, $group;
                next;
            }
            my $name = $cats->{$_};
            my $service = $self->service_class->new(
                service_name => $name,
                service_code => $_,
                description => $name,
                $waste_services{$_} ? (
                    group => 'Waste',
                    keywords => ['waste_only']
                ) : $group ? (
                    groups => [$group]
                ) : (),
                allow_any_attributes => 1,
            );

            my $data = $self->service_extra_data->{$_};
            foreach (sort keys %$data) {
                my %params;
                if ($data->{$_} eq '1') {
                    %params = (
                        code => $_,
                        description => $_,
                        required => 0,
                        datatype => 'string',
                        automated => 'hidden_field',
                    );
                } elsif (ref $data->{$_} eq 'HASH') {
                    %params = (
                        code => $_,
                        description => $data->{$_}{description},
                        required => 1,
                        datatype => 'singlevaluelist',
                        values => $data->{$_}{choices}
                    );
                } else {
                    %params = (
                        code => $_,
                        description => $data->{$_},
                        required => 1,
                        datatype => 'text',
                    );
                }
                push @{$service->attributes}, Open311::Endpoint::Service::Attribute->new(%params);
            }
            push @services, $service;
            $services{$_} = $service;
        }
        @services;
    } sort keys %$services;
    return @services;
}

has integration_class => (
    is => 'ro',
    default => 'Integrations::Echo'
);

sub get_integration {
    my $self = shift;
    my $integ = $self->integration_class->new(
        config_filename => $self->jurisdiction_id,
    );
    $self->log_identifier($self->jurisdiction_id);
    return $integ;
}

=head2 check_for_data_value

Any attributes passed to us are checked to see if their names match against any
of the extensible data on the relevant event type. Spaces can be replaced by
underscores, and a full Parent_Name can be used for sub-data elements. Defaults
can be looked up in C<default_data_all> and C<default_data_event_type>.

=cut

# For each event type data field, we will take a value
# from the main request if mapped, provided attributes,
# or any given defaults
sub check_for_data_value {
    my ($self, $name, $args, $request, $parent_name) = @_;
    my ($value, $full_name);
    $full_name = $parent_name . '_' . $name if $parent_name;

    if ($full_name) {
        $value = $self->_get_data_value($full_name, $args, $request);
    }
    unless (defined $value) {
        $value = $self->_get_data_value($name, $args, $request);
    }
    return $value;
}

sub _get_data_value {
    my ($self, $name, $args, $request) = @_;
    my $event_type = $request->{event_type};
    my %waste_services = map { $_ => 1 } @{$self->waste_services};
    (my $name_with_underscores = $name) =~ s/ /_/g;
    # skip emails if it's an anonymous user
    return undef if $self->data_key_open311_map->{$name} && $self->data_key_open311_map->{$name} eq 'email' && $args->{attributes}->{contributed_as} && $args->{attributes}->{contributed_as} eq 'anonymous_user';
    return $args->{attributes}{$name_with_underscores} if length $args->{attributes}{$name_with_underscores};

    return $args->{$self->data_key_open311_map->{$event_type}{$name}} if $self->data_key_open311_map->{$event_type}{$name};
    return $args->{$self->data_key_open311_map->{$name}} if $self->data_key_open311_map->{$name};

    return $args->{attributes}{$self->data_key_attribute_map->{$event_type}{$name}}
        if $self->data_key_attribute_map->{$event_type}{$name};
    return $args->{attributes}{$self->data_key_attribute_map->{$name}}
        if $self->data_key_attribute_map->{$name} && !$waste_services{$event_type};

    return $self->default_data_all->{$name} if $self->default_data_all->{$name};
    return $self->default_data_event_type->{$event_type}{$name}
        if $self->default_data_event_type->{$event_type}{$name};
    if ($name eq 'Image') {
        my @encoded;
        if (@{$args->{media_url}}) {
            foreach (@{$args->{media_url}}) {
                my $photo = $self->ua->get($_);
                push @encoded, encode_base64($photo->content, '');
            }
        } elsif (@{$args->{uploads}}) {
            foreach (@{$args->{uploads}}) {
                my $photo = path($_)->slurp;
                push @encoded, encode_base64($photo, '');
            }
        }
        return join('::', @encoded) if @encoded;
    }
    return undef;
}

=head2 post_service_request

This function processes the incoming arguments, looks up the relevant event
type in Echo, tries to match any incoming data to the fields in the event type,
and then posts a new event to Echo. If you need multiple entries for a data
field, you can pass in multiple values separated by C<::>.

=cut

sub post_service_request {
    my ($self, $service, $args) = @_;
    die "No such service\n" unless $service;

    my $request = $self->process_service_request_args($args);
    $self->logger->debug(encode_json($request));

    my $integ = $self->get_integration;

    # Look up extra data fields
    my $event_type = $integ->GetEventType($request->{event_type});
    my $data = Integrations::Echo::force_arrayref($event_type->{Datatypes}, 'ExtensibleDatatype');
    foreach my $type (@$data) {
        my $row = { id => $type->{Id} };
        my $value = $self->check_for_data_value($type->{Name}, $args, $request);

        my %extra;
        my $extra_count = 0;
        if ($type->{ChildDatatypes}) {
            my $moredata = Integrations::Echo::force_arrayref($type->{ChildDatatypes}, 'ExtensibleDatatype');
            foreach (@$moredata) {
                my $subrow = { id => $_->{Id} };
                my $value = $self->check_for_data_value($_->{Name}, $args, $request, $type->{Name});
                if (defined $value) {
                    my ($first, @rest) = split /::/, $value, -1;
                    $subrow->{value} = $first;
                    push @{$row->{childdata}}, $subrow;
                    if (@rest) {
                        $extra{$_->{Id}} = \@rest;
                        $extra_count = @rest;
                    }
                }
            }
        } elsif ($type->{Name} eq 'Image' && $value) {
            my ($first, @rest) = split /::/, $value, -1;
            $row->{value} = $first;
            if (@rest) {
                $extra{$type->{Id}} = \@rest;
                $extra_count = @rest;
            }
        } else {
            $row->{value} = $value;
        }

        push @{$request->{data}}, $row if defined $value || $row->{childdata};
        for (my $i=0; $i<$extra_count; $i++) {
            if ($row->{childdata}) {
                my @childdata;
                foreach (@{$row->{childdata}}) {
                    my $subrow = { %$_ };
                    if ($extra{$_->{id}}) {
                        $subrow->{value} = $extra{$_->{id}}->[$i];
                    }
                    push @childdata, $subrow;
                }
                $row = { %$row, childdata => \@childdata };
            } elsif ($extra{$row->{id}}) {
                $row = { %$row, value => $extra{$row->{id}}->[$i] };
            }
            push @{$request->{data}}, $row;
        }
    }

    my $response = $integ->PostEvent($request);
    die "Failed\n" unless $response;

    $request = $self->new_request(
        service_request_id => $response->{EventGuid},
    );
    return $request;
}

=head2 client_reference

If we're passed a C<client_reference> attribute, use that directly, otherwise
use the configured prefix plus the C<fixmystreet_id>.

=cut

sub client_reference {
    my ($self, $args) = @_;
    my $prefix = $self->client_reference_prefix;
    my $id = $args->{attributes}{fixmystreet_id};
    my $client_reference = "$prefix-$id";
    if ( $args->{attributes}{client_reference} ) {
        $client_reference = $args->{attributes}{client_reference};
    }
    return $client_reference;
}

=head2 process_service_request_args

Using the configuration, this constructs a request object from the incoming data.
The service or event_type (service code) may be overridden or changed.

=cut

sub process_service_request_args {
    my $self = shift;
    my $args = shift;

    # Strip off any extra data added as a suffix in FMS config
    # to reuse event type with multiple category names
    # - ie 2951, 2951_1 and 2951_2 should be posted as 2951
    # as that is the actual EventTypeId
    my ($event_type) = split /_/, $args->{service_code};
    my $service = $args->{attributes}{service_id} || '';
    my $uprn = $args->{attributes}{uprn};
    my $client_reference = $self->client_reference($args);

    # Sometimes we need to map our incoming service IDs
    $service = $self->service_mapping->{$service}
        if $self->service_mapping->{$service};

    # Missed collections have different event types depending
    # on the service
    $event_type = $self->service_to_event_type->{$event_type}{$service}
        if $self->service_to_event_type->{$event_type}{$service};

    # e.g. the new container event type always uses a
    # specific service, not the collection service
    $service = $self->service_id_override->{$event_type}
        if $self->service_id_override->{$event_type};

    my $request = {
        event_type => $event_type,
        service => $service,
        uprn => $uprn,
        usrn => $args->{attributes}{usrn},
        lat => $args->{lat},
        long => $args->{long},
        client_reference => $client_reference,
        data => [],
    };

    # We may want to raise the event with a specific GUID or reservation
    # which has been passed in as an extended attribute.
    if (my $guid = $args->{attributes}{GUID}) {
       $request->{guid} = $guid;
    }
    if (my $reservation = $args->{attributes}{reservation}) {
       $request->{reservation} = [ split /::/, $reservation ];
    }

    return $request;
}

=head2 post_service_request_update

This takes an incoming update and, if it has text content, posts it as an Event
Action on the relevant event.

=cut

sub post_service_request_update {
    my ($self, $args) = @_;

    my $update_id;
    if ($args->{description}) {
        my $response = $self->get_integration->PerformEventAction($args);
        $update_id = $response->{EventActionGuid};
    } else {
        $update_id = 'BLANK';
    }

    return Open311::Endpoint::Service::Request::Update::mySociety->new(
        status => lc $args->{status},
        update_id => $update_id,
    );
}

=head2 get_service_request_updates

This is not possible, so we have a blank function in order to not error when
used as part of a Multi integration.

=cut

sub get_service_request_updates { }

=head2 update_event_payment

Given an update args and an arrayref of payment details, update the event
to add those details. This is currently only for SLWP, and includes
hard-coded SLWP IDs.

=cut

sub update_event_payment {
    my ($self, $args, $payments) = @_;

    my $integ = $self->get_integration;
    my $event = $integ->GetEvent($args->{service_request_id});
    my $data = [];
    foreach (@$payments) {
        $_->{amount} =~ s/£//;
        push @$data, {
            # Could GetEventType and loop through it all to find these IDs out but for just this seemed okay
            id => 27409,
            childdata => [
                { id => 27410, value => $_->{ref} },
                { id => 27411, value => $_->{amount} },
            ],
        };
    }
    $integ->UpdateEvent({ id => $event->{Id}, data => $data });
    $args->{description} = ''; # Blank out so nothing sent to Echo now
}

1;
