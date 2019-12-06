package Integrations::Uniform;

use DateTime::Format::W3CDTF;
use HTTP::Cookies;
use SOAP::Lite;
use Exporter;
use Carp ();

sub endpoint_url { $_[0]->config->{endpoint_url} }

my $cookies = HTTP::Cookies->new(ignore_discard => 1);

my %methods = (
'LogonToConnector' => {
    soapaction => 'http://www.caps-solutions.co.uk/webservices/connectors/common/actions/LogonToConnector',
    namespace => 'http://www.caps-solutions.co.uk/webservices/connectors/75/servicerequest/service',
    parameters => [
        SOAP::Data->new(name => 'tns:UniformLoginCredentials', type => 'tns:LoginCredentials', attr => {}),
    ], # end parameters
  }, # end LogonToConnector
'LogoffFromConnector' => {
    soapaction => 'http://www.caps-solutions.co.uk/webservices/connectors/common/actions/LogoffFromConnector',
    namespace => 'http://www.caps-solutions.co.uk/webservices/connectors/75/servicerequest/service',
    parameters => [
    ], # end parameters
  }, # end LogoffFromConnector
'GetConnectorLoginStatus' => {
    soapaction => 'http://www.caps-solutions.co.uk/webservices/connectors/common/actions/GetConnectorLoginStatus',
    namespace => 'http://www.caps-solutions.co.uk/webservices/connectors/75/servicerequest/service',
    parameters => [
    ], # end parameters
  }, # end GetConnectorLoginStatus

'GetCnCodeList' => {
    soapaction => 'http://www.caps-solutions.co.uk/webservices/connectors/common/actions/GetCnCodeList',
    namespace => 'http://www.caps-solutions.co.uk/webservices/connectors/75/servicerequest/service',
    parameters => [
        SOAP::Data->new(name => 'tns:ListName', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end GetCnCodeList

'SubmitGeneralServiceRequest' => {
    soapaction => 'http://www.caps-solutions.co.uk/webservices/connectors/servicerequest/actions/SubmitGeneralServiceRequest',
    namespace => 'http://www.caps-solutions.co.uk/webservices/connectors/731/servicerequest/messagetypes',
    parameters => [
        SOAP::Data->new(name => 's4:SubmittedGeneralServiceRequest', type => 's4:SubmittedGeneralServiceRequestType', attr => {}),
    ], # end parameters
  }, # end SubmitGeneralServiceRequest
'SubmitDogServiceRequest' => {
    soapaction => 'http://www.caps-solutions.co.uk/webservices/connectors/servicerequest/actions/SubmitDogServiceRequest',
    namespace => 'http://www.caps-solutions.co.uk/webservices/connectors/75/servicerequest/service',
    parameters => [
        SOAP::Data->new(name => 's4:SubmittedDogServiceRequest', type => 's4:SubmittedDogServiceRequestType', attr => {}),
    ], # end parameters
  }, # end SubmitDogServiceRequest

'GetGeneralServiceRequestByReferenceValue' => {
    soapaction => 'http://www.caps-solutions.co.uk/webservices/connectors/servicerequest/actions/GetGeneralServiceRequestByReferenceValue',
    namespace => 'http://www.caps-solutions.co.uk/webservices/connectors/731/servicerequest/messagetypes',
    parameters => [
        SOAP::Data->new(name => 's5:ReferenceValue', type => 'xsd:string', attr => {}),
    ], # end parameters
  }, # end GetGeneralServiceRequestByReferenceValue
'GetChangedServiceRequestRefVals' => {
    soapaction => 'http://www.caps-solutions.co.uk/webservices/connectors/servicerequest/actions/GetChangedServiceRequestRefVals',
    namespace => 'http://www.caps-solutions.co.uk/webservices/connectors/731/servicerequest/messagetypes',
    parameters => [
        SOAP::Data->new(name => 's5:LastUpdated', type => 'xsd:dateTime', attr => {}),
    ], # end parameters
  }, # end GetChangedServiceRequestRefVals

'AddVisitsToInspection' => {
    soapaction => 'http://www.caps-solutions.co.uk/webservices/connectors/servicerequest/actions/AddVisitsToInspection',
    namespace => 'http://www.caps-solutions.co.uk/webservices/connectors/731/servicerequest/messagetypes',
    parameters => [
        SOAP::Data->new(name => 's9:InspectionIdentifier', type => 'xsd:string', attr => {}),
        SOAP::Data->new(name => 's5:Visits', type => 's9:ArrayOfSubmittedVisitType', attr => {}),
    ], # end parameters
  }, # end AddVisitsToInspection
'AddActionsToVisit' => {
    soapaction => 'http://www.caps-solutions.co.uk/webservices/connectors/servicerequest/actions/AddActionsToVisit',
    namespace => 'http://www.caps-solutions.co.uk/webservices/connectors/731/servicerequest/messagetypes',
    parameters => [
        SOAP::Data->new(name => 's9:VisitIdentifier', type => 'xsd:string', attr => {}),
        SOAP::Data->new(name => 's5:Actions', type => 's9:ArrayOfSubmittedActionType', attr => {}),
    ], # end parameters
  }, # end AddActionsToVisit

); # end my %methods

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
    $self->proxy($self->endpoint_url || Carp::croak "No server address (proxy) specified");
    $self->transport->cookie_jar($cookies);
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
  $self->serializer->{'_attr'}{'{http://schemas.xmlsoap.org/soap/envelope/}encodingStyle'} = undef;
  $self->serializer->register_ns("http://www.caps-solutions.co.uk/schema/uniform/75/common/uniformtypes","s8");
  $self->serializer->register_ns("http://www.caps-solutions.co.uk/schema/uniform/731/servicerequest/sr/srtypes","s4");
  $self->serializer->register_ns("http://schemas.xmlsoap.org/wsdl/mime/","mime");
  $self->serializer->register_ns("http://www.caps-solutions.co.uk/webservices/connectors/74b/servicerequest/messagetypes","s0");
  $self->serializer->register_ns("http://www.caps-solutions.co.uk/webservices/connectors/75/servicerequest/service","tns");
  $self->serializer->register_ns("http://www.caps-solutions.co.uk/schema/uniform/74b/servicerequest/sr/srtypes","s2");
  $self->serializer->register_ns("http://schemas.xmlsoap.org/soap/encoding/","soapenc");
  $self->serializer->register_ns("http://schemas.xmlsoap.org/soap/envelope/","soap");
  $self->serializer->register_ns("http://schemas.xmlsoap.org/wsdl/soap12/","soap12");
  $self->serializer->register_ns("http://www.caps-solutions.co.uk/webservices/connectors/731/servicerequest/messagetypes","s5");
  $self->serializer->register_ns("http://schemas.xmlsoap.org/wsdl/","wsdl");
  $self->serializer->register_ns("http://www.w3.org/2001/XMLSchema","s");
  $self->serializer->register_ns("http://www.w3.org/2001/XMLSchema","xsd");
  $self->serializer->register_ns("http://schemas.xmlsoap.org/wsdl/http/","http");
  $self->serializer->register_ns("http://microsoft.com/wsdl/mime/textMatching/","tm");
  $self->serializer->register_ns("http://www.caps-solutions.co.uk/schema/uniform/75/servicerequest/sr/srtypes","s7");
  $self->serializer->register_ns("http://www.caps-solutions.co.uk/schema/uniform/72b/common/uniformtypes","s1");
  $self->serializer->register_ns("http://www.caps-solutions.co.uk/schema/uniform/74b/common/uniformtypes","s3");
  $self->serializer->register_ns("http://www.caps-solutions.co.uk/schema/uniform/731/xi/xitypes","s9");
  $self->serializer->register_ns("http://www.caps-solutions.co.uk/schema/uniform/74b/xi/xitypes","s10");
  $self->serializer->register_ns("http://www.caps-solutions.co.uk/webservices/connectors/75/servicerequest/messagetypes","s6");
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
# ALl below is added

use strict;
use warnings;

#SRRECHOW
#RECEPHOW    APPCTN ARCH BCOFF BCVIST CACS CILOFF CONTCT COUNC CSP DCADMN DCENF DCOFF DCSITE EDO EMAIL ENGS ENVIRO FAX FIRE HIGHWY INTMEM LBRO LEASE
#            LETTER LICENC OCCUPR OOH OWNER PERSON POLICE RIPOFF SANDR TELE TSDOOR VISIT WANDC
#EHAREATM    DM E ED1 ED2 F0 F1-5 GI JO KH KW MS N NP NW RS S SAQ W 
#SRCUSTTYPE  EMPEE or NEIBOU or OCC(upier) or OFFICR or PUBLIC or THIRD or UNKNWN or CLLR or MEM_MP or LICENC
#SRCLOSEACT  ADVICE CANCEL CAT1_2 FORCAT HMOLIC LEAFLE LETTER MON NFA NOTSOC OCC(upied) PAID PH_NOT PROSEC(ution) REFER REVISI SEIZED SOC TREAT UNOCC WARBA WARBR _AVOID
#SRKIND      A(SB) C(ontract) D(og) E(high hedges) F(ood) G(eneral) H(ousing) K(licensing) L(HMO) N(oise) P(est) R(esidential) S(pecial) W(aste/recycling) X(taxi) Y(health and safety)
#SRRECTYPE   ANSMEL ANTCOM ANTCOU ANTDOM APCD1 APCD2 APCD3 APCL1 NO. ... WRV

sub SOAP::Serializer::as_SubmittedGeneralServiceRequestType {
    my ($self, $value, $name, $type, $attr) = @_;

    my $dt = DateTime->now(time_zone => 'Europe/London');
    my $time = DateTime::Format::W3CDTF->new->format_datetime($dt);

    my %xtra;
    foreach (keys %{$value->{xtra}}) {
        push @{$xtra{XtraValues}{SR_Xtra}}, {
            FieldName => $_,
            FieldValue => $value->{xtra}{$_},
        };
    }

    my $elem = \SOAP::Data->value( make_soap_structure('s4',
        ServiceRequestIdentification => {
            ReceptionReference => '',
            AlternativeReferences => {
                's1:AlternativeReference' => {
                    's1:ReferenceType' => 'FMS',
                    's1:ReferenceValue' => $value->{fixmystreet_id},
                },
            },
        },
        ComplaintType => $value->{service_code}, # SRRECTYPE
        SubmittedSiteLocation => {
            UPRN => $value->{uprn},
            MapEast => $value->{easting},
            MapNorth => $value->{northing},
        },
        NatureOfComplaint => $value->{description},
        HowComplaintReceived => 'FMS', # SRRECHOW
        Customers => {
            SubmittedCustomer => {
                SubmittedCustomerDetails => {
                    CustomerTypeCode => 'PUBLIC', # SRCUSTTYPE
                    CustomerName => {
                        FullName => $value->{name},
                    },
                    SubmittedContactDetails => {
                        SubmittedContactDetail => [
                            { ContactTypeCode => 'EMAIL', ContactAddress => $value->{email} },
                            $value->{phone} ? { ContactTypeCode => 'PHONEH', ContactAddress => $value->{phone} } : (),
                        ]
                    },
                    TimeReceived => $time,
                }
            }
        },
        TimeReceived => $time,
        %xtra,
    ));
    return [$name, $attr, $elem];
}

sub SOAP::Serializer::as_SubmittedDogServiceRequestType {
    my ($self, $value, $name, $type, $attr) = @_;
    return $self->as_SubmittedGeneralServiceRequestType($value, $name, $type, $attr);
}

sub SOAP::Serializer::as_LoginCredentials {
    my ($self, $value, $name, $type, $attr) = @_;

    my $elem = \SOAP::Data->value( make_soap_structure('tns',
        DatabaseID => $value->{database},
        UniformUserName => $value->{username},
        UniformPassword => $value->{password},
    ));
    return [$name, $attr, $elem];
}

sub make_soap_structure {
    my $namespace = shift;
    my @out;
    for (my $i=0; $i<@_; $i+=2) {
        my $name = $_[$i] =~ /:/ ? $_[$i] : "$namespace:$_[$i]";
        my $v = $_[$i+1];
        if (ref $v eq 'HASH') {
            push @out, SOAP::Data->name($name => \SOAP::Data->value(make_soap_structure($namespace, %$v)));
        } elsif (ref $v eq 'ARRAY') {
            push @out, map { SOAP::Data->name($name => \SOAP::Data->value(make_soap_structure($namespace, %$_))) } @$v;
        } else {
            push @out, SOAP::Data->name($name => $v)->type('string');
        }
    }
    return @out;
}

sub SOAP::Serializer::as_ArrayOfSubmittedVisitType {
    my ($self, $value, $name, $type, $attr) = @_;

    my $v = [
        VisitTypeCode => 'EHCUR',
        ScheduledDateOfVisit => $value->{updated_datetime},
        OfficerCode => 'EHCALL',
        Comments => $value->{description},
    ];
    my $elem = \SOAP::Data
        ->name('s9:SubmittedVisit' => [ make_soap_structure('s9', @$v) ])
        ->attr({'xsi:type' => 's9:SubmittedVisitType'});

    return [$name, $attr, $elem];
}

sub SOAP::Serializer::as_ArrayOfSubmittedActionType {
    my ($self, $value, $name, $type, $attr) = @_;

    my $v = [
        ActionCode => 'EHPCU',
        OfficerCode => 'EHCALL',
        DueDate => $value->{updated_datetime},
    ];
    my $elem = \SOAP::Data
        ->name('s9:SubmittedAction' => [ make_soap_structure('s9', @$v) ])
        ->attr({'xsi:type' => 's9:SubmittedActionType'});

    return [$name, $attr, $elem];
}

1;
