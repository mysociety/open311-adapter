package Integrations::Bartec;

use SOAP::Lite;
use Exporter;
use DateTime::Format::W3CDTF;
use Carp ();
use Moo;
use Cache::Memcached;
use Open311::Endpoint::Logger;
use JSON::MaybeXS;
use LWP::UserAgent;
use HTTP::Request::Common;
use Path::Tiny;
use SOAP::Lite;
use Try::Tiny;


with 'Role::Config';

# Using "with 'Role::Logger';" causes some issue with SOAP::Lite->proxy
# that I don't understand, so declare the attribute ourselves.
has logger => (
    is => 'lazy',
    default => sub { Open311::Endpoint::Logger->new },
);

has ua => (
    is => 'lazy',
    default => sub {
        LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter")
    },
);

sub credentials {
    my $config = $_[0]->config;
    return (
        $config->{username},
        $config->{password},
    );
}

has memcache_namespace  => (
    is => 'lazy',
    default => sub { $_[0]->config_filename }
);

has memcache => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        my $namespace = 'open311adapter:' . $self->memcache_namespace . ':';
        $namespace = "test:$namespace" if $ENV{TEST_MODE};
        new Cache::Memcached {
            'servers' => [ '127.0.0.1:11211' ],
            'namespace' => $namespace,
            'debug' => 0,
            'compress_threshold' => 10_000,
        };
    },
);

sub log_message {
    # uncoverable subroutine
    # uncoverable statement
    my ($msg) = @_;

    my $l = Open311::Endpoint::Logger->new;
    if ( ref($msg) eq 'HTTP::Request' || ref($msg) eq 'HTTP::Response' ) {
        $l->debug($msg->content);
    }
}

my $last_request;

sub log_errors {
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

has token => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        my $token = $self->memcache->get('token');
        unless ($token) {
            my $response = $self->Authenticate;
            unless ($response->{is_success}) {
                $self->logger->warn($response->{error});
                return;
            }
            $token = $response->{token};
            # only really cache this long enough to make the requests we need
            $self->memcache->set('token', $token, 300);
        }
        return $token;
    }
);

has status_map => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        my $statuses = $self->ServiceRequests_Statuses_Get;
        my %map;
        for my $status ( @{ $statuses->{ServiceStatus} } ) {
            $map{ $status->{ServiceTypeID} } ||= {};
            my $fms_status = $self->config->{status_map}->{ $status->{Status} };
            next unless $fms_status;
            $map{ $status->{ServiceTypeID} }->{$fms_status} = $status->{ID};
        }

        return \%map;
    }
);

has service_defaults => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        my $services = $self->ServiceRequests_Types_Get;

        my %defaults;
        for my $service ( @{ $services->{ServiceType} } ) {
            $defaults{ $service->{ID} } = {
                CrewID => $service->{DefaultCrew}->{ID},
                SLAID => $service->{DefaultSLA}->{ID},
                LandTypeID => $service->{DefaultLandType}->{ID},
            };
        }

        return \%defaults;
    }
);

has note_types => (
    is => 'lazy',
    default => sub {
        my $self = shift;

        my $types = $self->memcache->get('ServiceRequests_Notes_Types_Get');
        unless ($types) {
            $types = $self->_wrapper('ServiceRequests_Notes_Types_Get');
            delete $types->{SOM};
            $self->memcache->set('ServiceRequests_Notes_Types_Get', $types, 1800);
        }

        my %types = map { $_->{Description} => $_->{ID} } @{ $types->{ServiceNoteType} };

        return \%types;
    }
);

sub _methods {
    return {
        'Authenticate' => {
            endpoint   => 'https://collapi.bartec-systems.com/CollAuth/Authenticate.asmx',
            soapaction => 'http://bartec-systems.com/Authenticate',
            namespace  => 'http://bartec-systems.com/',
            parameters => [
                SOAP::Data->new(name => 'user',     type => 'string'),
                SOAP::Data->new(name => 'password', type => 'string'),
            ],
        },
        'Premises_Get' => {
            endpoint   => 'https://collectiveapi.bartec-systems.com/API-R1531/CollectiveAPI.asmx',
            soapaction => 'http://bartec-systems.com/Premises_Get',
            namespace  => 'http://bartec-systems.com/',
            parameters => [],
        },
        'ServiceRequests_Types_Get' => {
            endpoint   => 'https://collectiveapi.bartec-systems.com/API-R1531/CollectiveAPI.asmx',
            soapaction => 'http://bartec-systems.com/ServiceRequests_Types_Get',
            namespace  => 'http://bartec-systems.com/',
            parameters => [
                SOAP::Data->new(name => 'token', type => 'string'),
            ],
        },
        'ServiceRequests_Notes_Types_Get' => {
            endpoint   => 'https://collectiveapi.bartec-systems.com/API-R1531/CollectiveAPI.asmx',
            soapaction => 'http://bartec-systems.com/ServiceRequests_Notes_Types_Get',
            namespace  => 'http://bartec-systems.com/',
            parameters => [
                SOAP::Data->new(name => 'token', type => 'string'),
            ],
        },
        'ServiceRequests_Updates_Get' => {
            endpoint   => 'https://collectiveapi.bartec-systems.com/API-R1531/CollectiveAPI.asmx',
            soapaction => 'http://bartec-systems.com/ServiceRequests_Updates_Get',
            namespace  => 'http://bartec-systems.com/',
            parameters => [
                SOAP::Data->new(name => 'token', type => 'string'),
                SOAP::Data->new(name => 'LastUpdated', type => 'dateTime'),
            ],
        },
        'ServiceRequests_History_Get' => {
            endpoint   => 'https://collectiveapi.bartec-systems.com/API-R1531/CollectiveAPI.asmx',
            soapaction => 'http://bartec-systems.com/ServiceRequests_History_Get',
            namespace  => 'http://bartec-systems.com/',
            parameters => [
                SOAP::Data->new(name => 'token', type => 'string'),
                SOAP::Data->new(name => 'ServiceRequestID', type => 'int'),
                #SOAP::Data->new(name => 'bar:ID', type => 'int'),
                SOAP::Data->new(name => 'Date', type => 'dateTime'),
            ],
        },
        'ServiceRequests_Create' => {
            endpoint   => 'https://collectiveapi.bartec-systems.com/API-R1531/CollectiveAPI.asmx',
            soapaction => 'http://bartec-systems.com/ServiceRequests_Create',
            namespace  => 'http://bartec-systems.com/',
            parameters => [],
        },
        'Service_Request_Document_Create' => {
            endpoint   => 'https://collectiveapi.bartec-systems.com/API-R1531/CollectiveAPI.asmx',
            soapaction => 'http://bartec-systems.com/Service_Request_Document_Create',
            namespace  => 'http://bartec-systems.com/',
            parameters => [],
        },
        'ServiceRequests_Notes_Create' => {
            endpoint   => 'https://collectiveapi.bartec-systems.com/API-R1531/CollectiveAPI.asmx',
            soapaction => 'http://bartec-systems.com/ServiceRequests_Notes_Create',
            namespace  => 'http://bartec-systems.com/',
            parameters => [],
        },
        'ServiceRequests_Get' => {
            endpoint   => 'https://collectiveapi.bartec-systems.com/API-R1531/CollectiveAPI.asmx',
            soapaction => 'http://bartec-systems.com/ServiceRequests_Get',
            namespace  => 'http://bartec-systems.com/',
            parameters => [
                SOAP::Data->new(name => 'token', type => 'string'),
                SOAP::Data->new(name => 'ServiceCode', type => 'string'),
            ],
        },
        'ServiceRequests_Detail_Get' => {
            endpoint   => 'https://collectiveapi.bartec-systems.com/API-R1531/CollectiveAPI.asmx',
            soapaction => 'http://bartec-systems.com/ServiceRequests_Detail_Get',
            namespace  => 'http://bartec-systems.com/',
            parameters => [
                SOAP::Data->new(name => 'token', type => 'string'),
                SOAP::Data->new(name => 'ServiceCode', type => 'string'),
            ],
        },
        'ServiceRequests_Statuses_Get' => {
            endpoint   => 'https://collectiveapi.bartec-systems.com/API-R1531/CollectiveAPI.asmx',
            soapaction => 'http://bartec-systems.com/ServiceRequests_Statuses_Get',
            namespace  => 'http://bartec-systems.com/',
            parameters => [
                SOAP::Data->new(name => 'token', type => 'string'),
            ],
        },
    };
}

sub endpoint {
    my ($self, $args) = @_;

    # uncoverable branch true
    if ( $self->config->{loglevel} && $self->config->{loglevel} eq 'debug' ) {
        SOAP::Lite->import( +trace => [ transport => \&log_message ] ); # uncoverable statement
    # uncoverable branch true
    } elsif ( not $ENV{TEST_MODE} ) {
        SOAP::Lite->import( +trace => [ fault => transport => \&log_errors ] ); #uncoverable statement
    }

    my $endpoint = SOAP::Lite->new();
    $endpoint->proxy( $args->{endpoint}, timeout => 360 )
       ->default_ns($args->{namespace})
       ->on_action(sub{qq!"$args->{soapaction}"!});
    $endpoint->autotype(0);
    $endpoint->serializer->register_ns('http://bartec-systems.com/', 'bar1');
    $endpoint->serializer->register_ns('http://www.bartec-systems.com', 'bar2');

    return $endpoint;
}

sub _call {
    my ($self, $args) = @_;
    my $name = UNIVERSAL::isa($args->{method} => 'SOAP::Data') ? $args->{method}->name : $args->{method};
    my %method = %{ $self->_methods->{$name} };

    my $endpoint = $self->endpoint( \%method );
    my @parameters = $self->_setup_soap_params($endpoint, $args->{method}, $name, $args->{args});

    my $som = $endpoint->call(SOAP::Data->name($name)->attr({ xmlns => $method{namespace} }), @parameters);
    my $res = $som->result;
    $res->{SOM} = $som;
    return $res;
}

sub _setup_soap_params {
    my ($self, $endpoint, $method, $name, $args) = @_;
    my %method = %{ $self->_methods->{$name} };

    my @templates = @{$method{parameters}};
    my @parameters = ();
    foreach my $param (@{ $args }) {
        if (@templates) {
            my $template = shift @templates;
            my ($prefix,$typename) = SOAP::Utils::splitqname($template->type);
            my $method = 'as_'.$typename;
            my $result = $endpoint->serializer->$method($param, $template->name, $template->type, $template->attr);
            push(@parameters, $template->value($result->[2]));
        }
        else {
            push(@parameters, $param);
        }
    }

    return @parameters;
}

sub Authenticate {
    my $self = shift;

    my $response = $self->_call({ method => 'Authenticate', args => [ $self->credentials ]});

    my $errors = $response->{Errors};
    if ($errors) {
        return {
            is_success => 0,
            error => $errors->{Error}->{Message},
        }
    }

    return {
        is_success => 1,
        token => $response->{Token}->{TokenString},
    };
}

sub _wrapper {
    my ($self, $method, $no_token) = (shift, shift, shift);
    my $response;

    my @params = @_;
    unshift @params, $self->token unless $no_token;
    try {
        $response = $self->_call( { method=> $method, args => \@params } );

        my $error = $response->{Errors};
        die $error if $error && $error->{Message} eq 'Invalid Token';
    } catch {
        $self->memcache->delete('token');
        $response = $self->_call({ method => $method, args => \@params });
    };

    return $response;
}


sub ServiceRequests_Types_Get {
    my $self = shift;
    my $types = $self->memcache->get('ServiceRequests_Types_Get');
    unless ($types) {
        $types = $self->_wrapper('ServiceRequests_Types_Get', @_);
        delete $types->{SOM};
        $self->memcache->set('ServiceRequests_Types_Get', $types, 1800);
    }

    return $types;
}

sub Premises_Get {
    my ($self, $args) = @_;

    my %base = (
        token => $self->token,
        UPRN => undef,
    );

    my %params;
    if ( $args->{bbox} ) {
        my $bbox = $args->{bbox};
        %params = (
            Bounds => {
                # top left
                Point1 => {
                    attr => { xmlns => 'http://www.bartec-systems.com' },
                    Metric => { attr => { Latitude => $bbox->{max}->{lat}, Longitude => $bbox->{min}->{lon} } }
                },
                # bottom right
                Point2 => {
                    attr => { xmlns => 'http://www.bartec-systems.com' },
                    Metric => { attr => { Latitude => $bbox->{min}->{lat}, Longitude => $bbox->{max}->{lon} } }
                }
            }
        );
    } elsif ( $args->{usrn} && !$args->{address} && !$args->{street} ) {
        %params = (
            USRN => $args->{usrn},
        );
    } else {
        %params = (
            USRN => $args->{usrn},
            ParentUPRN => undef,
            Address2 => $args->{address} ? '%' . $args->{address} . '%' : '',
            Street => uc $args->{street},
        );
    }

    my %req = (
        %base,
        %params
    );

    my $elem = SOAP::Data->value( make_soap_structure( %req ) );

    my $r = $self->_wrapper('Premises_Get', 1, $elem);
    return $r;
}

sub ServiceRequests_Create {
    my ($self, $service, $values) = @_;

    my $dt = DateTime->now(time_zone => 'Europe/London');
    my $time = DateTime::Format::W3CDTF->new->format_datetime($dt);

    my $status_id = $self->status_map->{$values->{service_code}}->{open};

    my %req = (
        token => $self->token,
        UPRN => $values->{uprn},
        ServiceStatusID => $status_id,
        DateRequested => $time,
        ServiceTypeID => $values->{service_code},
        serviceLocationDescription => $values->{attributes}->{closest_address},
        ServiceRequest_Location => {
            Metric => {
                attr => { xmlns => 'http://www.bartec-systems.com' },
                Latitude => $values->{lat} * 1,
                Longitude => $values->{long} * 1,
            },
        },
        #source => $values->{Source},
        ExternalReference => $values->{attributes}->{fixmystreet_id},
        reporterContact => {
            Forename => { attr => { xmlns => 'http://www.bartec-systems.com/ServiceRequests_Create.xsd' }, value => $values->{first_name} },
            Surname => { attr => { xmlns => 'http://www.bartec-systems.com/ServiceRequests_Create.xsd' }, value => $values->{last_name} },
            Email => { attr => { xmlns => 'http://www.bartec-systems.com/ServiceRequests_Create.xsd'} , value => $values->{email} },
            ReporterType => { attr => { xmlns => 'http://www.bartec-systems.com/ServiceRequests_Create.xsd'}, value => $values->{ReporterType} },
        },
    );

    my %data = (
        %{ $self->service_defaults->{$values->{service_code} } },
        %req
    );

    my $elem = SOAP::Data->value( make_soap_structure( %data ) );

    return $self->_wrapper('ServiceRequests_Create', 1, $elem);
}

sub Service_Request_Document_Create {
    my ($self, $args) = @_;

    my $dt = DateTime->now(time_zone => 'Europe/London');
    my $time = DateTime::Format::W3CDTF->new->format_datetime($dt);

    my %req = (
        'bar1:token' => $self->token,
        'bar1:ServiceRequestID' => $args->{srid},
        'bar1:Public' => 'true',
        'bar1:DateTaken' => $time,
        'bar1:Comment' => 'Photo uploaded from FixMyStreet',
        'bar1:AttachedDocument' => {
            'bar2:FileExtension' => 'jpg',
            'bar2:ID' => $args->{id},
            'bar2:Name' => $args->{name},
            'bar2:Document' => $args->{content},
        }
    );

    my $elem = SOAP::Data->value( make_soap_structure( %req ) );

    return $self->_wrapper('Service_Request_Document_Create', 1, $elem);
}

sub ServiceRequests_Notes_Create {
    my ($self, $args) = @_;

    my %req = (
        'token' => $self->token,
        'ServiceRequestID' => $args->{srid},
        'NoteTypeID' => $args->{note_type},
        'Note' => $args->{note},
        'Comment' => 'Note added by FixMyStreet',
    );

    my $elem = SOAP::Data->value( make_soap_structure( %req ) );

    return $self->_wrapper('ServiceRequests_Notes_Create', 1, $elem);
}

sub ServiceRequests_Updates_Get {
    my $self = shift;
    return $self->_wrapper('ServiceRequests_Updates_Get', 0, @_);
}

sub ServiceRequests_History_Get {
    my $self = shift;
    return $self->_wrapper('ServiceRequests_History_Get', 0, @_);
}

sub ServiceRequests_Get {
    my $self = shift;
    return $self->_wrapper('ServiceRequests_Get', 0, @_);
}

sub ServiceRequests_Detail_Get {
    my $self = shift;
    return $self->_wrapper('ServiceRequests_Detail_Get', 0, @_);
}

sub ServiceRequests_Statuses_Get {
    my $self = shift;
    my $statuses = $self->memcache->get('ServiceRequests_Statuses_Get');
    unless ($statuses) {
        $statuses = $self->_wrapper('ServiceRequests_Statuses_Get', 0, @_);
        delete $statuses->{SOM};
        $self->memcache->set('ServiceRequests_Statuses_Get', $statuses, 1800);
    }

    return $statuses;
}

sub make_soap_structure {
    my @out;
    for (my $i=0; $i<@_; $i+=2) {
        my $name = $_[$i];
        my $v = $_[$i+1];
        if (ref $v eq 'HASH') {
            my $attr = delete $v->{attr};
            my $value = delete $v->{value};

            my $d = SOAP::Data->name($name => $value ? $value : \SOAP::Data->value(make_soap_structure(%$v)));

            $d->attr( $attr ) if $attr;
            push @out, $d;
        } elsif (ref $v eq 'ARRAY') {
            push @out, map { SOAP::Data->name($name => \SOAP::Data->value(make_soap_structure(%$_))) } @$v;
        } else {
            push @out, SOAP::Data->name($name => $v);
        }
    }
    return @out;
}

1;
