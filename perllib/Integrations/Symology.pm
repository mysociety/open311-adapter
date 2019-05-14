package Integrations::Symology;

use DateTime;
use SOAP::Lite;
use Exporter;
use Carp ();

sub endpoint_url { $_[0]->config->{endpoint_url} }

# Originally generated by SOAP::Lite, then edited. All unnecessary methods
# removed, endpoint made a method, 'tns:' added to all auto-generated
# parameters, wsdl/soap register_ns removed, new functions at end.

my %methods = (
SendRequestAdditionalGroup => {
    soapaction => 'http://www.symology.co.uk/services/SendRequestAdditionalGroup',
    namespace => 'http://www.symology.co.uk/services',
    parameters => [
      SOAP::Data->new(name => 'tns:ProcessID', type => 's:string', attr => {}),
      SOAP::Data->new(name => 'tns:Request', type => 'tns:RequestSend', attr => {}),
      SOAP::Data->new(name => 'tns:Customer', type => 'tns:CustomerSend', attr => {}),
      SOAP::Data->new(name => 'tns:AdditionalFields', type => 'tns:ArrayOfAdditionalFieldSend', attr => {}),
      SOAP::Data->new(name => 'tns:GroupFields', type => 'tns:ArrayOfAdditionalFieldSend', attr => {}),
    ], # end parameters
  }, # end SendRequestAdditionalGroup
SendEventAction => {
    soapaction => 'http://www.symology.co.uk/services/SendEventAction',
    namespace => 'http://www.symology.co.uk/services',
    parameters => [
      SOAP::Data->new(name => 'tns:ProcessID', type => 's:string', attr => {}),
      SOAP::Data->new(name => 'tns:EventAction', type => 'tns:EventActionSend', attr => {}),
    ], # end parameters
  }, # end SendEventAction
GetRequestAdditionalGroup => {
    soapaction => 'http://www.symology.co.uk/services/GetRequestAdditionalGroup',
    namespace => 'http://www.symology.co.uk/services',
    parameters => [
      SOAP::Data->new(name => 'tns:ServiceCode', type => 's:string', attr => {}),
      SOAP::Data->new(name => 'tns:InCRNo', type => 's:int', attr => {}),
      SOAP::Data->new(name => 'tns:InWebRequestID', type => 's:string', attr => {}),
      SOAP::Data->new(name => 'tns:InInterfaceType', type => 's:int', attr => {}),
    ], # end parameters
  }, # end GetRequestAdditionalGroup
); # end my %methods

use vars qw(@ISA $AUTOLOAD @EXPORT_OK %EXPORT_TAGS);
@ISA = qw(Exporter SOAP::Lite);
@EXPORT_OK = (keys %methods);
%EXPORT_TAGS = ('all' => [@EXPORT_OK]);

sub _call {
    my ($self, $method) = (shift, shift);
    my $name = UNIVERSAL::isa($method => 'SOAP::Data') ? $method->name : $method;
    my %method = %{$methods{$name}};
    $self->proxy($self->endpoint_url || Carp::croak "No server address (proxy) specified")
        unless $self->proxy;
    my @templates = @{$method{parameters}};
    my @parameters = ();
    foreach my $param (@_) {
        if (@templates) {
            my $template = shift @templates;
            my ($prefix,$typename) = SOAP::Utils::splitqname($template->type);
            my $method = 'as_'.$typename;
            # TODO - if can('as_'.$typename) {...}
            my $result = $self->serializer->$method($param, $template->name, $template->type, $template->attr);
            push(@parameters, $template->value($result->[2]));
        }
        else {
            push(@parameters, $param);
        }
    }
    $self->endpoint($self->endpoint_url)
       ->ns($method{namespace})
       ->on_action(sub{qq!"$method{soapaction}"!});
  $self->serializer->register_ns("http://microsoft.com/wsdl/mime/textMatching/","tm");
  $self->serializer->register_ns("http://schemas.xmlsoap.org/wsdl/soap12/","soap12");
  $self->serializer->register_ns("http://schemas.xmlsoap.org/wsdl/mime/","mime");
  $self->serializer->register_ns("http://www.w3.org/2001/XMLSchema","s");
  $self->serializer->register_ns("http://schemas.xmlsoap.org/wsdl/","wsdl");
  $self->serializer->register_ns("http://schemas.xmlsoap.org/wsdl/http/","http");
  $self->serializer->register_ns("http://schemas.xmlsoap.org/soap/encoding/","soapenc");
  $self->serializer->register_ns("http://www.symology.co.uk/services","tns");
    my $som = $self->SUPER::call($method => @parameters);
    if ($self->want_som) {
        return $som;
    }
    UNIVERSAL::isa($som => 'SOAP::SOM') ? wantarray ? $som->paramsall : $som->result : $som;
}

sub BEGIN {
    no strict 'refs';
    for my $method (qw(want_som)) {
        my $field = '_' . $method;
        *$method = sub {
            my $self = shift->new;
            @_ ? ($self->{$field} = shift, return $self) : return $self->{$field};
        }
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
    }
}

sub AUTOLOAD {
    my $method = substr($AUTOLOAD, rindex($AUTOLOAD, '::') + 2);
    return if $method eq 'DESTROY' || $method eq 'want_som';
    die "Unrecognized method '$method'. List of available method(s): @EXPORT_OK\n";
}

# ---
# All below is added

sub SOAP::Serializer::as_ArrayOfAdditionalFieldSend {
    my ($self, $value, $name, $type, $attr) = @_;

    my $v = [
          { FieldLine => 17, ValueType => 1, DataValue => $value },
    ];
    my $elem = \SOAP::Data
        ->name('AdditionalFieldSend' => map { [ make_soap_structure(%$_) ] } @$v)
        ->attr({'xsi:type' => 'AdditionalFieldSend'});
    return [$name, {'xsi:type' => $type, %$attr}, $elem];
}

sub SOAP::Serializer::as_RequestSend {
    my ($self, $value, $name, $type, $attr) = @_;

    my $dt = DateTime->now(time_zone => 'Europe/London');
    my $elem = \SOAP::Data->value( make_soap_structure(
        $value->{NSGRef} ? (NSGRef => $value->{NSGRef}) : (), # Might not be optional in end
        $value->{RegionSite} ? (RegionSite => $value->{RegionSite}) : (), # Might not be optional in end
        $value->{UnitID} ? (UnitID => $value->{UnitID}) : (), # Also UnitName, UnitNumber
        RecordedDate => $dt->strftime('%Y-%m-%d'),
        RecordedTime => $dt->strftime('%H:%M:%S'),
        UserName => $value->{UserName},
        RequestType => $value->{RequestType},
        Priority => $value->{Priority} || 'N',
        AnalysisCode1 => $value->{AnalysisCode1},
        AnalysisCode2 => $value->{AnalysisCode2},
        # Location => '',
        ExternalRef => $value->{fixmystreet_id},
        Description => $value->{Description}, # With attributes appended
        Easting => $value->{easting},
        Northing => $value->{northing},
        InWebRequestID => $value->{fixmystreet_id},
        ServiceCode => $value->{ServiceCode},
        # Information extracted from Street Gaz database
        NextAction => $value->{NextAction},
        NextInspection => '',
        NextActionUserName => '',
        NextNotify => '0',
        ActionDescription => '',
        CreateLACode => $value->{CreateLACode} || '0',
    ));
    return [$name, {'xsi:type' => 'tns:RequestSend', %$attr}, $elem];
}

sub SOAP::Serializer::as_CustomerSend {
    my ($self, $value, $name, $type, $attr) = @_;

    my $dt = DateTime->now();
    my $elem = \SOAP::Data->value( make_soap_structure(
          CustomerFullName => $value->{name},
          CustomerTelNo => $value->{phone},
          #minOccurs="0" maxOccurs="1" name="CustomerReference"
          CustomerEmail => $value->{email},
          CustomerType => 'PB',
          ContactType => $value->{contributed_by} ? 'TL' : 'OL',
          InitialDate => $dt->strftime('%Y-%m-%d'),
          InitialTime => $dt->strftime('%H:%M:%S'),
          ReceivedDate => $dt->strftime('%Y-%m-%d'),
          ReceivedTime => $dt->strftime('%H:%M:%S'),
    ));
    return [$name, {'xsi:type' => 'tns:CustomerSend', %$attr}, $elem];
}

sub SOAP::Serializer::as_EventActionSend {
    my ($self, $value, $name, $type, $attr) = @_;

    my $elem = \SOAP::Data->value( make_soap_structure(
        ServiceCode => $value->{ServiceCode},
        CRNo => $value->{CRNo},
        WebRequestID => $value->{fixmystreet_id},
        EventType => 'CCA',
        EventDescription => '',
        UserName => $value->{UserName},
        Description => $value->{Description},
    ));
    return [$name, {'xsi:type' => 'tns:EventActionSend', %$attr}, $elem];
}

sub make_soap_structure {
    my @out;
    for (my $i=0; $i<@_; $i+=2) {
        my $name = "tns:$_[$i]";
        my $v = $_[$i+1];
        #if (ref $v eq 'HASH') {
        #    push @out, SOAP::Data->name($name => \SOAP::Data->value(make_soap_structure(%$v)));
        if (ref $v eq 'ARRAY') {
            my $type = shift @$v;
            push @out,
                SOAP::Data->name($name => [
                    SOAP::Data
                        ->name($type => map { [ make_soap_structure(%$_) ] } @$v)
                        ->attr({'xsi:type' => $type})
                ])
                ->attr({'soapenc:arrayType' => "ro:$type" . "[]"});
        } else {
            push @out, SOAP::Data->name($name => $v)->type('xsi:string');
        }
    }
    return @out;
}

1;