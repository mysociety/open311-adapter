package Integrations::Verint;

use v5.14;
use warnings;
use SOAP::Lite; # +trace => [ qw/debug/ ];
use Exporter;
use Carp ();
use MIME::Base64;
use Tie::IxHash;

my %methods = (
'CreateRequest' => {
    soapaction => 'http://kana.com/dforms/Create',
    namespace => 'http://kana.com/dforms',
    parameters => [
      SOAP::Data->new(name => 'sch:name', type => 'sch:nonEmptyString', attr => {}),
      SOAP::Data->new(name => 'sch:data', type => 'sch:Data', attr => {'soapenc:arrayType' => undef}),
    ],
  },
);

use vars qw(@ISA $AUTOLOAD @EXPORT_OK %EXPORT_TAGS);
@ISA = qw(Exporter SOAP::Lite);
@EXPORT_OK = (keys %methods);
%EXPORT_TAGS = ('all' => [@EXPORT_OK]);

use Moo;
with 'Role::Config';

sub _call {
    my ($self, $method) = (shift, shift);

    my $name = UNIVERSAL::isa($method => 'SOAP::Data') ? $method->name : $method;
    my %method = %{$methods{$name}};

    my $config = $self->config;
    my $proxy;
    if ($name eq 'CreateRequest') {
        $proxy = $config->{'create_endpoint_url'};
    };

    $self->proxy($proxy || Carp::croak "No server address (proxy) specified")
        unless $self->proxy;

    my $auth_header = MIME::Base64::encode($config->{username} . ':' . $config->{password});
    $self->transport->http_request->header('Authorization' => 'Basic ' . $auth_header);

    my @templates = @{$method{parameters}};
    my @parameters = ();
    foreach my $param (@_) {
        my $template = shift @templates;
        my ($prefix,$typename) = SOAP::Utils::splitqname($template->type);
        my $method = 'as_'.$typename;
        my $result = $self->serializer->$method($param, $template->name, $template->type, $template->attr);
        push(@parameters, $template->value($result->[2]));
    }
        $self->endpoint($method{endpoint})
       ->ns($method{namespace})
       ->on_action(sub{qq!"$method{soapaction}"!});
    $self->serializer->register_ns("http://schemas.xmlsoap.org/wsdl/","wsdl");
    $self->serializer->register_ns("http://kana.com/dforms","tns");
    $self->serializer->register_ns("http://kana.com/dforms","sch");

    my $som = $self->SUPER::call($method => @parameters);
    if ($self->want_som) {
        return $som;
    }

    UNIVERSAL::isa($som => 'SOAP::SOM') ? wantarray ? $som->paramsall : $som->result : $som;
}

sub SOAP::Serializer::as_nonEmptyString {
    my ($self, $value, $name, $type, $attr) = @_;

    return [$name, {'type' => $type, %$attr}, $value];
}

sub SOAP::Serializer::as_Data {
    my ($self, $value, $name, $type, $attr) = @_;

    my $form = { 'sch:form-data' => [] };
    for my $key (keys %$value) {
        next unless $value->{$key};
        push @{$form->{'sch:form-data'}}, {
            'sch:field' => ixhash( 'sch:name' => $key, 'sch:value' => $value->{$key} )
        };
    }

    my @elem = make_soap_structure(%$form);

    return [$name, {'type' => $type, %$attr}, \@elem];
}

sub ixhash {
    tie (my %data, 'Tie::IxHash', @_);
    return \%data;
}

sub make_soap_structure {
    my @out;
    for (my $i=0; $i<@_; $i+=2) {
        my $name = $_[$i];
        my $v = $_[$i+1];
        my $val = $v;
        my $d = SOAP::Data->name($name);
        if (ref $v eq 'HASH') {
            $val = \SOAP::Data->value(make_soap_structure(%$v));
        } elsif (ref $v eq 'ARRAY') {
            my @map = map { make_soap_structure(%$_) } @$v;
            $val = \SOAP::Data->value(SOAP::Data->name('dummy' => @map));
        } else {
            $d->type('string');
        }
        push @out, $d->value($val);
    }

    return @out;
}

sub BEGIN {
    no strict 'refs';
    for my $method (qw(want_som)) {
        my $field = '_' . $method;
        *$method = sub {
            my $self = shift->new;
            @_ ? ($self->{$field} = shift, return $self) : return $self->{$field};
        };
    }
}

no strict 'refs';
for my $method (@EXPORT_OK) {
    my %method = %{$methods{$method}};
    *$method = sub {
        my $self = UNIVERSAL::isa($_[0] => __PACKAGE__)
            ? ref $_[0]
                ? shift # OBJECT
                # CLASS, either get self or create new and assign to self
                : (shift->self || __PACKAGE__->self(__PACKAGE__->new))
            # function call, either get self or create new and assign to self
            : (__PACKAGE__->self || __PACKAGE__->self(__PACKAGE__->new));
        $self->_call($method, @_);
    };
}

sub AUTOLOAD {
    my $method = substr($AUTOLOAD, rindex($AUTOLOAD, '::') + 2);
    return if $method eq 'DESTROY' || $method eq 'want_som';
    die "Unrecognized method '$method'. List of available method(s): @EXPORT_OK\n";
}

1;
