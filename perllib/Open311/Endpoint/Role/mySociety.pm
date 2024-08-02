package Open311::Endpoint::Role::mySociety;

=head1 NAME

Open311::Endpoint::Role::mySociety - mySociety's proposed Open311 extensions

=head1 SYNOPSIS

See mySociety's 
L<blog post|https://www.mysociety.org/2013/02/20/open311-extended/>
and 
L<proposal|https://github.com/mysociety/FixMyStreet/wiki/Open311-FMS---Proposed-differences-to-Open311>
for a full explanation of the spec extension.

You can use the extensions as follows:

    package My::Open311::Endpoint;
    use Web::Simple;
    extends 'Open311::Endpoint';
    with 'Open311::Endpoint::Role::mySociety';

You will have to provide implementations of

    get_service_request_updates
    post_service_request_update

You will need to return L<Open311::Endpoint::Service::Request::Update>
objects.  However, the root L<Open311::Endpoint::Service::Request> is not
aware of updates, so you may may find it easier to ensure that the ::Service
objects you create (with get_service_request etc.) return
L<Open311::Endpoint::Service::Request::mySociety> objects.

=cut

use SOAP::Lite;
use Moo::Role;
no warnings 'illegalproto';

use Open311::Endpoint::Schema;

use Open311::Endpoint::Service::Request::mySociety;
has '+request_class' => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::Request::mySociety',
);

my $soap_logging_configured = 0;

around dispatch_request => sub {
    my ($orig, $self, @args) = @_;
    my @dispatch = $self->$orig(@args);

    if (!$soap_logging_configured) {
        $soap_logging_configured = 1;
        my $config = $self->logger->config;
        # uncoverable branch true
        if ( ($config->{min_log_level} || '') eq 'debug' ) {
            SOAP::Lite->import( +trace => [ transport => \&log_soap_message ] ); # uncoverable statement
        # uncoverable branch true
        } elsif ( not $ENV{TEST_MODE} ) {
            SOAP::Lite->import( +trace => [ fault => transport => \&log_soap_errors ] ); #uncoverable statement
        }
    }

    return (
        @dispatch,

        sub (GET + /servicerequestupdates + ?*) {
            my ($self, $args) = @_;
            $self->call_api( GET_Service_Request_Updates => $args );
        },

        sub (POST + /servicerequestupdates + %:@media_url~&* + **) {
            my ($self, $args, $uploads) = @_;

            my @files = grep { $_->is_upload } values %$uploads;
            $args->{uploads} = \@files;

            $self->call_api( POST_Service_Request_Update => $args );
        },

    );
};

my $log_identifier;
sub log_identifier {
    my $self = shift;
    $log_identifier = shift;
}

sub log_soap_message {
    # uncoverable subroutine
    # uncoverable statement
    my ($msg) = @_;

    my $l = Open311::Endpoint::Logger->new( config_filename => $log_identifier );
    if ( ref($msg) eq 'HTTP::Request' || ref($msg) eq 'HTTP::Response' ) {
        $l->debug($msg->content);
    }
}

my $last_request;

sub log_soap_errors {
    # uncoverable subroutine
    # uncoverable statement
    my ($msg) = @_;

    if ( ref($msg) eq 'HTTP::Response' &&
         $msg->content =~ /Errors><Result[^>]*>[1-9]|soap:Fault>/
       ) {
        my $l = Open311::Endpoint::Logger->new;
        $l->error("Req: $last_request\nRes: " . $msg->content);
    } elsif ( ref($msg) eq 'HTTP::Request' ) {
        $last_request = $msg->content;
    }
}

sub GET_Service_Request_Updates_input_schema {
    my $self = shift;
    return {
        type => '//rec',
        required => {
            $self->get_jurisdiction_id_required_clause,
        },
        optional => {
            $self->get_jurisdiction_id_optional_clause,
            api_key => $self->get_identifier_type('api_key'),
            start_date => '/open311/datetime',
            end_date   => '/open311/datetime',
        }
    };
}

sub GET_Service_Request_Updates_output_schema {
    my $self = shift;
    return {
        type => '//rec',
        required => {
            service_request_updates => {
                type => '//arr',
                contents => '/open311/service_request_update',
            },
        },
    };
}

sub GET_Service_Request_Updates {
    my ($self, $args) = @_;

    my @updates = $self->get_service_request_updates({
        jurisdiction_id => $args->{jurisdiction_id},
        start_date => $args->{start_date},
        end_date => $args->{end_date},
    });

    $self->format_updates(@updates);
}

sub POST_Service_Request_Update_input_schema {
    my ($self, $args) = @_;

    my $attributes = {
        type => '//rec',
        required => {
            $self->get_jurisdiction_id_required_clause,
            api_key => $self->get_identifier_type('api_key'),
            service_request_id => $self->get_identifier_type('service_request_id'),
            update_id => $self->get_identifier_type('update_id'),
            status => '/open311/status_extended_upper',
            updated_datetime => '/open311/datetime',
            description => '//str',
        },
        optional => {
            $self->get_jurisdiction_id_optional_clause,
            email => '//str',
            phone => '//str',
            last_name => '//str',
            first_name => '//str',
            title => '//str',
            media_url => { type => '//arr', contents => '//str' },
            uploads => { type => '//arr', contents => '//any' },
            account_id => '//str',
            service_request_id_ext => '//num',
            public_anonymity_required => Open311::Endpoint::Schema->enum('//str', 'TRUE', 'FALSE'),
            email_alerts_requested => Open311::Endpoint::Schema->enum('//str', 'TRUE', 'FALSE'),
            service_code => $self->get_identifier_type('service_code'),
        }
    };

    my $jurisdiction = $args->{jurisdiction_id} || '';

    # Bromley has a different update_id key than elsewhere
    if ($jurisdiction eq 'bromley') {
        $attributes->{required}{update_id_ext} = $self->get_identifier_type('update_id');
        delete $attributes->{required}{update_id};
    }

    # Allow attributes through for Oxfordshire XXX
    if ($jurisdiction eq 'oxfordshire') {
        for my $key (grep { /^attribute\[\w+\]$/ } keys %$args) {
            $attributes->{optional}{$key} = '//str';
        }
    }

    # Allow nsg_ref through for Bexley XXX
    if ($jurisdiction eq 'bexley') {
        if ($args->{'nsg_ref'}) {
	        $attributes->{optional}{'nsg_ref'} = '//str';
        }
    }

    return $attributes;
}

sub POST_Service_Request_Update_output_schema {
    my $self = shift;
    return {
        type => '//rec',
        required => {
            service_request_updates => {
                type => '//arr',
                contents => {
                    type => '//rec',
                    required => {
                        update_id => $self->get_identifier_type('update_id')
                    },
                    optional => {
                        account_id => '//str',
                    },
                },
            },
        },
    };
}

sub POST_Service_Request_Update {
    my ($self, $args) = @_;

    for my $k (keys %$args) {
        if ($k =~ /^attribute\[(\w+)\]$/) {
            my $value = delete $args->{$k};
            $args->{attributes}{$1} = $value;
        }
    }

    my $service_request_update = $self->post_service_request_update( $args );

    return {
        service_request_updates => [
            map {
                +{
                    update_id => $_->update_id,
                    $_->has_account_id ? ( account_id => $_->account_id ) : (),
                }
            } $service_request_update,
        ],
    };
}

sub format_updates {
    my ($self, @updates) = @_;
    return {
        service_request_updates => [
            map {
                my $update = $_;
                +{
                    (
                        map {
                            $_ => $update->$_,
                        }
                        qw/
                            update_id
                            service_request_id
                            status
                            description
                            /
                    ),
                    (
                        map {
                            ($update->can($_) && $update->$_ )? ($_ => $update->$_) : (),
                        }
                        qw/
                            external_status_code
                            customer_reference
                            fixmystreet_id
                            /
                    ),
                    (
                        map {
                            my $value = $update->$_->[0];
                            $_ => $value || '';
                        }
                        qw/
                            media_url
                            /
                    ),
                    (
                        map {
                            $_ => $self->w3_dt->format_datetime( $update->$_ ),
                        }
                        qw/
                            updated_datetime
                        /
                    ),
                    (
                        ( $update->can('extras') && %{ $update->extras } ) ?
                        ( extras => { map { $_ => $update->extras->{$_} } keys %{ $update->extras } } )
                        : ()
                    ),
                }
            } @updates
        ]
    };
}

sub get_service_request_updates {
    my ($self, $args) = @_;
    die "abstract method get_service_request_updates not overridden";
}

sub post_service_request_update {
    my ($self, $args) = @_;
    die "abstract method post_service_request_update not overridden";
}

sub learn_additional_types {
    my ($self, $schema) = @_;
    $schema->learn_type( 'tag:wiki.open311.org,GeoReport_v2:rx/status_extended',
        Open311::Endpoint::Schema->enum('//str',
            'open',
            'closed',
            'fixed',
            'in_progress',
            'planned',
            'action_scheduled',
            'investigating',
            'duplicate',
            'not_councils_responsibility',
            'no_further_action',
            'internal_referral',
            'cancelled',
            'reopen',
            'for_triage',
        )
    );
    $schema->learn_type( 'tag:wiki.open311.org,GeoReport_v2:rx/status_extended_upper',
        Open311::Endpoint::Schema->enum('//str',
            'OPEN',
            'CLOSED',
            'FIXED',
            'IN_PROGRESS',
            'PLANNED',
            'ACTION_SCHEDULED',
            'INVESTIGATING',
            'DUPLICATE',
            'NOT_COUNCILS_RESPONSIBILITY',
            'NO_FURTHER_ACTION',
            'INTERNAL_REFERRAL',
            'CANCELLED',
            'REOPEN',
            'FOR_TRIAGE',
        )
    );
    $schema->learn_type( 'tag:wiki.open311.org,GeoReport_v2:rx/service_request_update',
        {
            type => '//rec',
            required => {
                service_request_id => $self->get_identifier_type('service_request_id'),
                update_id => $self->get_identifier_type('update_id'),
                status => '/open311/status_extended',
                updated_datetime => '/open311/datetime',
                description => '//str',
                media_url => '//str',
            },
            optional => {
                external_status_code => '//str',
                customer_reference => '//str',
                fixmystreet_id => '//str',
                extras => {
                    type => '//map',
                    values => '//str',
                }
            },
        }
    );
    $schema->learn_type( 'tag:wiki.open311.org,GeoReport_v2:rx/service_request_extended',
        {
            type => '//rec',
            required => {
                service_request_id => $self->get_identifier_type('service_request_id'),
                status => '/open311/status_extended',
                service_name => '//str',
                service_code => $self->get_identifier_type('service_code'),
                requested_datetime => '/open311/datetime',
                updated_datetime => '/open311/datetime',
                address => '//str',
                address_id => '//str',
                zipcode => '//str',
                lat => '//num',
                long => '//num',
                media_url => '//str',
            },
            optional => {
                title => '//str',
                request => '//str',
                description => '//str',
                agency_responsible => '//str',
                service_notice => '//str',
                non_public => '//str',
                contact_name => '//str',
                contact_email => '//str',
            },
        }
    );
}

1;
