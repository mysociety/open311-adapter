package Open311::Endpoint;

=head1 NAME

Open311::Endpoint - a generic Open311 endpoint implementation

=cut

use Encode qw(encode_utf8);
use Web::Simple;

use JSON::MaybeXS;
use XML::Simple;

use Open311::Endpoint::Result;
use Open311::Endpoint::Service;
use Open311::Endpoint::Service::Request;
use Open311::Endpoint::Spark;
use Open311::Endpoint::Schema;

use MooX::HandlesVia;

use Data::Dumper;
use Scalar::Util 'blessed';
use List::Util 'first';
use Types::Standard ':all';

use DateTime::Format::W3CDTF;

with 'Role::Logger';

=head1 DESCRIPTION

An implementation of L<http://wiki.open311.org/GeoReport_v2> with a
dispatcher written as a L<Plack> application, designed to be easily
deployed.

This is a generic wrapper, designed to be a conformant Open311 server.
However, it knows nothing about your business logic!  You should subclass it
and provide the necessary methods.

=head1 SUBCLASSING

    package My::Open311::Endpoint;
    use Web::Simple;
    extends 'Open311::Endpoint';

See also t/open311/endpoint/Endpoint1.pm and Endpoint2.pm as examples.

=head2 methods to override

These are the important methods to override.  They are passed a list of
simple arguments, and should generally return objects like
L<Open311::Endpoint::Request>.

    services
    service
    post_service_request
    get_service_requests
    get_service_request
    requires_jurisdiction_ids
    check_jurisdiction_id

The dispatch framework will take care of actually formatting the output
into conformant XML or JSON.

TODO document better

=cut

sub services {
    # this should be overridden in your subclass!
    ();
}
sub service {
    # this stub implementation is a simple lookup on $self->services, and
    # should *probably* be overridden in your subclass!
    # (for example, to look up in App DB, with $args->{jurisdiction_id})

    my ($self, $service_code, $args) = @_;

    return first { $_->service_code eq $service_code } $self->services($args);
}

sub post_service_request {
    my ($self, $service, $args) = @_;

    die "abstract method post_service_request not overridden";
}

sub get_service_requests {
    my ($self, $args) = @_;
    die "abstract method get_service_requests not overridden";
}

sub get_service_request {
    my ($self, $service_request_id, $args) = @_;

    die "abstract method get_service_request not overridden";
}

sub requires_jurisdiction_ids {
    # you may wish to subclass this
    return shift->has_multiple_jurisdiction_ids;
}

sub service_request_content {
    '/open311/service_request';
}


sub check_jurisdiction_id {
    my ($self, $jurisdiction_id) = @_;

    # you may wish to override this stub implementation which:
    #   - always succeeds if no jurisdiction_id is set
    #   - accepts no jurisdiction_id if there is only one set
    #   - otherwise checks that the id passed is one of those set
    #
    return 1 unless $self->has_jurisdiction_ids;

    if (! defined $jurisdiction_id) {
        return $self->requires_jurisdiction_ids ? 1 : undef;
    }

    return first { $jurisdiction_id eq $_ } $self->get_jurisdiction_ids;
}

=head2 Configurable arguments

    * default_service_notice - default for <service_notice> if not
        set by the service or an individual request
    * jurisdictions - an array of jurisdiction_ids
        you may want to subclass the methods:
            - requires_jurisdiction_ids
            - check_jurisdiction_id 
    * default_identifier_type
        Open311 doesn't mandate what these types look like, but a backend
        server may! The module provides an example identifier type which allows
        ascii "word" characters .e.g [a-zA-Z0-9_] as an example default.
        You can also override these individually using:

        identifier_types => {
            api_key => '//str', # 
            jurisdiction_id => ...
            service_code => ...
            service_request_id  => ...
            # etc.
        }
    * request_class - class to instantiate for requests via new_request

=cut

has default_identifier_type => (
    is => 'ro',
    isa => Str,
    default => '/open311/example/identifier',
);

has identifier_types => (
    is => 'ro',
    isa => HashRef[Str],
    default => sub { {} },
    handles_via => 'Hash',
    handles => {
        get_identifier_type => 'get',
    },
);

around get_identifier_type => sub {
    my ($orig, $self, $type) = @_;
    return $self->$orig($type) // $self->default_identifier_type;
};

has default_service_notice => (
    is => 'ro',
    isa => Maybe[Str],
    predicate => 1,
);

has jurisdiction_ids => (
    is => 'ro',
    isa => Maybe[ArrayRef],
    default => sub { [] },
    handles_via => 'Array',
    handles => {
        has_jurisdiction_ids => 'count',
        get_jurisdiction_ids => 'elements',
    }
);

has request_class => (
    is => 'ro',
    isa => Str,
    default => 'Open311::Endpoint::Service::Request',
);

sub new_request {
    my ($self, %args) = @_;
    return $self->request_class->new( %args );
}

=head2 Other accessors

You may additionally wish to replace the following objects.

    * schema - Data::Rx schema for validating Open311 protocol inputs and
               outputs
    * spark  - methods for munging base data-structure for output
    * json   - JSON output object
    * xml    - XML::Simple output object

=cut

has schema => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        Open311::Endpoint::Schema->new( endpoint => $self ),
    },
    handles => {
        rx => 'schema',
        format_boolean => 'format_boolean',
    },
);

sub learn_additional_types {
    # my ($self, $rx) = @_;
    ## no-op, but override in ::Role or implementation!
}

has spark => (
    is => 'lazy',
    default => sub {
        Open311::Endpoint::Spark->new();
    },
);

has json => (
    is => 'lazy',
    default => sub {
        JSON->new->utf8->pretty->allow_blessed->convert_blessed;
    },
);

has xml => (
    is => 'lazy',
    default => sub {
        XML::Simple->new( 
            NoAttr=> 1, 
            KeepRoot => 1, 
            SuppressEmpty => 0,
        );
    },
);

has w3_dt => (
    is => 'lazy',
    default => sub { DateTime::Format::W3CDTF->new },
);

has time_zone => (
    is => 'ro',
    default => 'Europe/London',
);

sub maybe_inflate_datetime {
    my ($self, $dt) = @_;
    return unless $dt;
    return $self->w3_dt->parse_datetime($dt);
}

=head2 Dispatching

The method dispatch_request returns a list of all the dispatcher routines
that will be checked in turn by L<Web::Simple>.

You may extend this in a subclass, or with a role.

=cut

sub dispatch_request {
    my $self = shift;

    sub (/**) {
        my ($self) = @_;
        $self->format_response('');
    },

    sub (.*) {
        my ($self, $ext) = @_;
        $self->format_response($ext);
    },

    sub (GET + /services + ?*) {
        my ($self, $args) = @_;
        $self->call_api( GET_Service_List => $args );
    },

    sub (GET + /services/** + ?*) {
        my ($self, $service_id, $args) = @_;
        $self->call_api( GET_Service_Definition => $service_id, $args );
    },

    sub (POST + /requests + %:@media_url~&@* + **) {
        my ($self, $args, $uploads) = @_;

        # We use '@*' to capture parameters as multiple in the hashref to handle attributes with multiple values.
        # This puts every value in array, regardless of whether it's singleton or empty, which we don't want.
        # The following block 'un-arrays' the value in these cases.

        while (my ($key, $value) = each %$args) {
            next if $key eq 'media_url';
            my $length = scalar @$value;
            if ($length == 1) {
                $args->{$key} = $value->[0];
            } elsif ($length == 0) {
                $args->{$key} = "";
            }
        }

        my @files = grep {
            $_->is_upload
        } values %$uploads;
        $args->{uploads} = \@files;
        $self->call_api( POST_Service_Request => $args, );
    },

    sub (GET + /tokens/*) {
        return Open311::Endpoint::Result->error( 400, 'not implemented' );
    },

    sub (GET + /requests + ?*) {
        my ($self, $args) = @_;
        $self->call_api( GET_Service_Requests => $args );
    },

    sub (GET + /requests/* + ?*) {
        my ($self, $service_request_id, $args) = @_;
        $self->call_api( GET_Service_Request => $service_request_id, $args );
    },
}

sub GET_Service_List_input_schema {
    return shift->get_jurisdiction_id_validation;
}

sub GET_Service_List_output_schema {
    return {
        type => '//rec',
        required => {
            services => {
                type => '//arr',
                contents => '/open311/service',
            },
        }
    };
}

sub GET_Service_List {
    my ($self, $args) = @_;

    my @services = map {
        my $service = $_;
        {
            keywords => (join ',' => @{ $service->keywords } ),
            metadata => $self->format_boolean( $service->has_attributes ),
            @{$service->groups} ? (groups => $service->groups) : (group => $service->group),
            map { $_ => $service->$_ }
                qw/ service_name service_code description type /,
        }
    } $self->services($args);
    return {
        services => \@services,
    };
}

sub GET_Service_Definition_input_schema {
    my $self = shift;
    return {
        type => '//seq',
        contents => [
            $self->get_identifier_type('service_code'),
            $self->get_jurisdiction_id_validation,
        ],
    };
}

sub GET_Service_Definition_output_schema {
    return {
        type => '//rec',
        required => {
            service_definition => {
                type => '/open311/service_definition',
            },
        }
    };
}

sub GET_Service_Definition {
    my ($self, $service_id, $args) = @_;

    my $service = $self->service($service_id, $args) or return;
    my $order = 0;
    my $service_definition = {
        service_definition => {
            service_code => $service_id,
            attributes => [
                map {
                    my $attribute = $_;
                    my %optional = $attribute->automated ?
                        ( automated => $attribute->automated ) :
                        ();
                    {
                        order => ++$order,
                        variable => $self->format_boolean( $attribute->variable ),
                        required => $self->format_boolean( $attribute->required ),
                        %optional,
                        $attribute->has_values ? (
                            values => [
                                map { 
                                    my ($key, $name) = @$_;
                                    +{ 
                                        key => $key, 
                                        name => $name,
                                    }
                                } $self->service_attribute_values( $attribute )
                            ]) : (),
                        map { $_ => $attribute->$_ } 
                            qw/ code datatype datatype_description description /,
                    }
                } $service->get_attributes,
            ],
        },
    };
    return $service_definition;
}

sub service_attribute_values {
    my ( $self, $attribute ) = @_;

    if ( $attribute->has_sorted_values ) {
        return map { [ $_ => $attribute->values->{$_} ] } $attribute->get_sorted_values;
    } else {
        return sort { $a->[0] cmp $b->[0] } $attribute->values_kv;
    }
}

sub POST_Service_Request_input_schema {
    my ($self, $args) = @_;

    my $service_code = $args->{service_code};
    unless ($service_code && $args->{api_key}) {
        # return a simple validator
        # to give a nice error message
        return {
            type => '//rec',
            required => { 
                service_code => $self->get_identifier_type('service_code'), 
                api_key => $self->get_identifier_type('api_key') },
            rest => '//any',
        };
    }

    my $service = $self->service($service_code, $args)
        or return; # we can't fetch service, so signal error TODO

    my %attributes = ( required => {}, optional => {} );
    for my $attribute ($service->get_attributes) {
        my $section = $attribute->required ? 'required' : 'optional';
        my $key = sprintf 'attribute[%s]', $attribute->code;
        my $def = $attribute->schema_definition;

        $attributes{ $section }{ $key } = $def;
    }

    for my $key (grep { /^attribute\[.+\]$/ } keys %$args) {
        next if $attributes{optional}{$key} || $attributes{required}{$key};

        $attributes{optional}{$key} = '//str';
        $self->logger->warn("Unknown attribute: $key") unless $service->allow_any_attributes;
    }

    # we have to supply at least one of these, but can supply more
    my @address_options = (
        { lat => '//num', long => '//num' },
        { address_string => '//str' },
        { address_id => '//str' },
    );

    my @address_schemas;
    while (my $address_required = shift @address_options) {
        push @address_schemas,
        {
            type => '//rec',
            required => {
                service_code => $self->get_identifier_type('service_code'),
                api_key => $self->get_identifier_type('api_key'),
                %{ $attributes{required} },
                %{ $address_required },
                $self->get_jurisdiction_id_required_clause,
            },
            optional => {
                email => '//str',
                device_id => '//str',
                account_id => '//str',
                first_name => '//str',
                last_name => '//str',
                phone => '//str',
                description => '//str',
                media_url => { type => '//arr', contents => '//str' },
                uploads => { type => '//arr', contents => '//any' },
                %{ $attributes{optional} || {}},
                (map %$_, @address_options),
                $self->get_jurisdiction_id_optional_clause,
            },
        };
    }

    return { 
            type => '//any',
            of => \@address_schemas,
        };
}

sub POST_Service_Request_output_schema {
    my ($self, $args) = @_;

    my $service_code = $args->{service_code};
    my $service = $self->service($service_code, $args);

    my %return_schema = (
        ($service->type eq 'realtime') ? ( service_request_id => $self->get_identifier_type('service_request_id') ) : (),
        ($service->type eq 'batch')    ? ( token => '//str' ) : (),
    );

    return {
        type => '//rec',
        required => {
            service_requests => {
                type => '//arr',
                contents => {
                    type => '//rec',
                    required => {
                        %return_schema,
                    },
                    optional => {
                        service_notice => '//str',
                        account_id => '//str',

                    },
                },
            },
        },
    };
}

sub POST_Service_Request {
    my ($self, $args) = @_;

    # TODO pass this through instead of calculating again?
    my $service_code = $args->{service_code};
    my $service = $self->service($service_code, $args);

    for my $k (keys %$args) {
        if ($k =~ /^attribute\[(.+)\]$/) {
            my $value = delete $args->{$k};
            $args->{attributes}{$1} = $value;
        }
    }

    my @service_requests = $self->post_service_request( $service, $args );
        
    return {
        service_requests => [
            map {
                my $service_notice = 
                    $_->service_notice 
                    || $service->default_service_notice
                    || $self->default_service_notice;
                +{
                    ($service->type eq 'realtime') ? ( service_request_id => $_->service_request_id ) : (),
                    ($service->type eq 'batch')    ? ( token => $_->token ) : (),
                    $service_notice ? ( service_notice => $service_notice ) : (),
                    $_->has_account_id ? ( account_id => $_->account_id ) : (),
                }
            } @service_requests,
        ],
    };
}

sub GET_Service_Requests_input_schema {
    my $self = shift;
    return {
        type => '//rec',
        required => {
            $self->get_jurisdiction_id_required_clause,
        },
        optional => {
            $self->get_jurisdiction_id_optional_clause,,
            api_key => $self->get_identifier_type('api_key'),
            service_request_id => {
                type => '/open311/comma',
                contents => $self->get_identifier_type('service_request_id'),
            },
            service_code => {
                type => '/open311/comma',
                contents => $self->get_identifier_type('service_code'),
            },
            start_date => '/open311/datetime',
            end_date   => '/open311/datetime',
            status => {
                type => '/open311/comma',
                contents => '/open311/status',
            },
        },
    };
}

sub GET_Service_Requests_output_schema {
    my ($self, $args) = @_;
    return {
        type => '//rec',
        required => {
            service_requests => {
                type => '//arr',
                contents => $self->service_request_content($args),
            },
        },
    };
}

sub GET_Service_Requests {
    my ($self, $args) = @_;

    my @service_requests = $self->get_service_requests({

        jurisdiction_id => $args->{jurisdiction_id},
        start_date => $args->{start_date},
        end_date => $args->{end_date},

        map {
            $args->{$_} ?
                ( $_ => [ split ',' => $args->{$_} ] )
              : ()
        } qw/ service_request_id service_code status /,
    });

    $self->format_service_requests(@service_requests);
}

sub GET_Service_Request_input_schema {
    my $self = shift;
    return {
        type => '//seq',
        contents => [
            $self->get_identifier_type('service_request_id'),
            $self->get_jurisdiction_id_validation,
        ],
    };
}

sub GET_Service_Request_output_schema {
    my $self = shift;
    return {
        type => '//rec',
        required => {
            service_requests => {
                type => '//seq', # e.g. a single service_request
                contents => [
                    '/open311/service_request',
                ]
            },
        },
    };
}

sub GET_Service_Request {
    my ($self, $service_request_id, $args) = @_;

    my $service_request = $self->get_service_request($service_request_id, $args);

    $self->format_service_requests($service_request);
}

sub format_service_requests {
    my ($self, @service_requests) = @_;
    return {
        service_requests => [
            map {
                my $request = $_;
                +{
                    (
                        map {
                            $_ => $request->$_,
                        }
                        qw/
                            service_request_id
                            status
                            service_name
                            service_code
                            address
                            address_id
                            zipcode
                            lat
                            long
                            / 
                    ),
                    (
                        map {
                            my $value = $request->$_->[0];
                            $_ => $value || '';
                        }
                        qw/
                            media_url
                            /
                    ),
                    (
                        map {
                            if (my $dt = $request->$_) {
                                $_ => $self->w3_dt->format_datetime( $dt )
                            }
                            else {
                                ()
                            }
                        }
                        qw/
                            requested_datetime
                            updated_datetime
                        /
                    ),
                    (
                        map {
                            my $value = $request->$_;
                            $value ? ( $_ => $value ) : (),
                        }
                        qw/
                            description
                            agency_responsible
                            service_notice
                            /
                    ),
                    (
                        map {
                            my $value = $request->$_;
                            $value ? ( $_ => $value ) : (),
                        }
                        @{ $request->optional_fields }
                    ),
                }
            } @service_requests,
        ],
    };
}

sub has_multiple_jurisdiction_ids {
    return shift->has_jurisdiction_ids > 1;
}

sub get_jurisdiction_id_validation {
    my $self = shift;

    # jurisdiction_id is documented as "Required", but with the note
    # 'This is only required if the endpoint serves multiple jurisdictions'
    # i.e. it is optional as regards the schema, but the server may choose 
    # to error if it is not provided.
    return {
        type => '//rec',
        ($self->requires_jurisdiction_ids ? 'required' : 'optional') => { 
            jurisdiction_id => $self->get_identifier_type('jurisdiction_id'),
        },
    };
}

sub get_jurisdiction_id_required_clause {
    my $self = shift;
    $self->requires_jurisdiction_ids ? (jurisdiction_id => $self->get_identifier_type('jurisdiction_id')) : ();
}

sub get_jurisdiction_id_optional_clause {
    my $self = shift;
    $self->requires_jurisdiction_ids ? () : (jurisdiction_id => $self->get_identifier_type('jurisdiction_id'));
}

sub call_api {
    my ($self, $api_name, @args) = @_;
    
    my $api_method = $self->can($api_name)
        or die "No such API $api_name!";

    if (my $input_schema_method = $self->can("${api_name}_input_schema")) {
        my $input_schema = $self->$input_schema_method(@args)
            or return Open311::Endpoint::Result->error( 400,
                'Bad request' );

        my $schema = $self->rx->make_schema( $input_schema );
        my $input = (scalar @args == 1) ? $args[0] : [@args];
        eval {
            $schema->assert_valid( $input );
        };
        if ($@) {
            return Open311::Endpoint::Result->error( 400,
                "Error in input for $api_name",
                split /\n/, $@,
                # map $_->struct, @{ $@->failures }, # bit cheeky, spec suggests it wants strings only
            );
        }
    }

    my $data = eval { $self->$api_method(@args) };
    if (my $err = $@) {
        $self->logger->error($err);
        return Open311::Endpoint::Result->error(500 => $err);
    } elsif (!$data) {
        return Open311::Endpoint::Result->error(404 => 'Resource not found');
    }

    if (my $output_schema_method = $self->can("${api_name}_output_schema")) {
        my $definition = $self->$output_schema_method(@args);
        my $schema = $self->rx->make_schema( $definition );
        eval {
            $schema->assert_valid( $data );
        };
        if ($@) {
            use Data::Dumper;
            return Open311::Endpoint::Result->error( 500,
                "Error in output for $api_name",
                Dumper($data),
                split /\n/, $@,
                # map $_->struct, @{ $@->failures },
            );
        }
    }

    return Open311::Endpoint::Result->success( $data );
}

sub format_response {
    my ($self, $ext) = @_;
    response_filter {
        my $response = shift;
        return $response unless blessed $response;
        my $status = $response->status;
        my $data = $response->data;
        if ($ext eq 'json') {
            return [
                $status, 
                [ 'Content-Type' => 'application/json' ],
                [ $self->json->encode( 
                    $self->spark->process_for_json( $data ) 
                )]
            ];
        }
        elsif ($ext eq 'xml') {
            return [
                $status,
                [ 'Content-Type' => 'text/xml' ],
                [ qq(<?xml version="1.0" encoding="utf-8"?>\n),
                  encode_utf8($self->xml->XMLout(
                    $self->spark->process_for_xml( $data )
                ))],
            ];
        }
        else {
            return [
                404,
                [ 'Content-Type' => 'text/plain' ],
                [ 'Bad extension. We support .xml and .json' ],
            ] 
        }
    }
}

=head1 AUTHOR and LICENSE

    hakim@mysociety.org 2014

This is released under the same license as FixMyStreet.
see https://github.com/mysociety/fixmystreet/blob/master/LICENSE.txt

=cut

__PACKAGE__->run_if_script;
