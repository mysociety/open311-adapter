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
use MIME::Base64 qw(encode_base64 decode_base64);
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
        'ServiceRequests_Types_Get' => {
            endpoint   => 'https://collectiveapi.bartec-systems.com/API-R1531/CollectiveAPI.asmx',
            soapaction => 'http://bartec-systems.com/ServiceRequests_Types_Get',
            namespace  => 'http://bartec-systems.com/',
            parameters => [
                SOAP::Data->new(name => 'token', type => 'string'),
            ],
        },
        'ServiceRequests_Updates_Get' => {
            endpoint   => 'https://collapi.bartec-systems.com/API-R152/CollectiveAPI.asmx',
            soapaction => 'http://bartec-systems.com/ServiceRequests_Updates_Get',
            namespace  => 'http://bartec-systems.com/',
            parameters => [
                SOAP::Data->new(name => 'bar:token', type => 'string'),
                SOAP::Data->new(name => 'bar:LastUpdated', type => 'dateTime'),
            ],
        },
        'ServiceRequests_History_Get' => {
            endpoint   => 'https://collapi.bartec-systems.com/API-R152/CollectiveAPI.asmx',
            soapaction => 'http://bartec-systems.com/ServiceRequests_History_Get',
            namespace  => 'http://bartec-systems.com/',
            parameters => [
                SOAP::Data->new(name => 'bar:token', type => 'string'),
                SOAP::Data->new(name => 'bar:ServiceRequestID', type => 'int'),
                #SOAP::Data->new(name => 'bar:ID', type => 'int'),
                SOAP::Data->new(name => 'bar:Date', type => 'dateTime'),
            ],
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

    my $endpoint = SOAP::Lite->new();
    $endpoint->proxy( $args->{endpoint}, timeout => 360 )
       ->default_ns($args->{namespace})
       ->on_action(sub{qq!"$args->{soapaction}"!});
    $endpoint->autotype(0);

    return $endpoint;
}

sub _call {
    my ($self, $args) = @_;
    my $name = UNIVERSAL::isa($args->{method} => 'SOAP::Data') ? $args->{method}->name : $args->{method};
    my %method = %{ $self->_methods->{$name} };

    my $endpoint = $self->endpoint( \%method );
    my @parameters = $self->_setup_soap_params($endpoint, $args->{method}, $name, $args->{args});

    my $som = $endpoint->call(SOAP::Data->name($name)->attr({ xmlns => $method{namespace} }), @parameters);
    UNIVERSAL::isa($som => 'SOAP::SOM') ? wantarray ? $som->paramsall : $som->result : $som;
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
    my ($self, $method) = (shift, shift);
    my $response;

    my @params = @_;
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
    return $self->_wrapper('ServiceRequests_Types_Get', @_);
}

sub ServiceRequests_Updates_Get {
    my $self = shift;
    return $self->_wrapper('ServiceRequests_Updates_Get', @_);
}

sub ServiceRequests_History_Get {
    my $self = shift;
    return $self->_wrapper('ServiceRequests_History_Get', @_);
}

sub ServiceRequests_Get {
    my $self = shift;
    return $self->_wrapper('ServiceRequests_Get', @_);
}

sub ServiceRequests_Statuses_Get {
    my $self = shift;
    return $self->_wrapper('ServiceRequests_Statuses_Get', @_);
}

1;
