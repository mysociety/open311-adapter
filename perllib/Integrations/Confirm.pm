package Integrations::Confirm;

use SOAP::Lite;
use Exporter;
use DateTime::Format::W3CDTF;
use Carp ();
use Moo;
use Cache::Memcached;

use vars qw(@ISA);
@ISA = qw(Exporter SOAP::Lite);

sub endpoint_url { die "abstract method endpoint_url not overridden" }

sub credentials { die "abstract method credentials not overridden" }

# If the Confirm endpoint requires a particular EnquiryMethodCode for NewEnquiry
# requests, override this in the subclass. Valid values can be found by calling
# the GetCustomerLookup method on the endpoint.
has enquiry_method_code  => (
    is => 'ro',
    default => ''
);

# Similar to enquiry_method_code, if the Confirm endpoint requires a particular
# PointOfContactCode for NewEnquiry requests, override this in the subclass.
# Valid values can be found by calling the GetCustomerLookup method on the endpoint.
has point_of_contact_code  => (
    is => 'ro',
    default => ''
);

has server_timezone  => (
    is => 'ro',
    default => 'UTC'
);

has memcache_namespace  => (
    is => 'ro',
    default => 'confirm'
);

has memcache => (
    is => 'lazy',
    default => sub {
        my $self = shift;
        new Cache::Memcached {
            'servers' => [ '127.0.0.1:11211' ],
            'namespace' => 'open311adapter:' . $self->memcache_namespace . ':',
            'debug' => 0,
            'compress_threshold' => 10_000,
        };
    },
);

sub _methods {
    return {
        'ProcessFbi' => {
            soapaction => 'http://www.confirm.co.uk/schema/am/connector/webservice/ProcessFbi',
            namespace => 'http://www.confirm.co.uk/schema/am/connector/webservice',
            parameters => [],
        },
        'ProcessOperationsRequest' => {
            soapaction => 'http://www.confirm.co.uk/schema/am/connector/webservice/ProcessOperations',
            namespace => 'http://www.confirm.co.uk/schema/am/connector/webservice',
            parameters => [],
        },
    };
}

sub _call {
    my ($self, $method) = (shift, shift);
    my $name = UNIVERSAL::isa($method => 'SOAP::Data') ? $method->name : $method;
    my %method = %{ $self->_methods->{$name} };
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
  $self->serializer->register_ns("http://schemas.xmlsoap.org/wsdl/","wsdl");
  $self->serializer->register_ns("http://schemas.xmlsoap.org/soap/envelope/","soap");
  $self->serializer->register_ns("http://schemas.xmlsoap.org/wsdl/mime/","mime");
  $self->serializer->register_ns("http://www.confirm.co.uk/schema/am/connector/webservice","tns");
  $self->serializer->register_ns("http://schemas.xmlsoap.org/soap/encoding/","soapenc");
  $self->serializer->register_ns("http://microsoft.com/wsdl/mime/textMatching/","tm");
  $self->serializer->register_ns("http://schemas.xmlsoap.org/wsdl/soap12/","soap12");
  $self->serializer->register_ns("http://schemas.xmlsoap.org/wsdl/http/","http");
  $self->serializer->register_ns("http://www.w3.org/2001/XMLSchema","s");
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

sub ProcessFbi {
    my $self = shift;
    return $self->_call("ProcessFbi", @_);
}

sub ProcessOperationsRequest {
    my $self = shift;
    return $self->_call("ProcessOperationsRequest", @_);
}

sub perform_request {
    my $self = shift;

    my ($username, $password, $tenant) = $self->credentials;

    my @operations = map {
        SOAP::Data->name('Operation' => $_)
    } @_;

    my $request = SOAP::Data->name('Request' => \SOAP::Data->value(
        SOAP::Data->name('Authentication' => \SOAP::Data->value(
            SOAP::Data->name('Username' => SOAP::Utils::encode_data($username))->type(""),
            SOAP::Data->name('Password' => SOAP::Utils::encode_data($password))->type(""),
            SOAP::Data->name('DatabaseId' => SOAP::Utils::encode_data($tenant))->type(""),
        )),
        @operations
    ));

    return $self->ProcessOperationsRequest($request);
}

sub GetEnquiries {
    my $self = shift;

    my @operations = map {
        \SOAP::Data->name('GetEnquiry' => \SOAP::Data->value(
            SOAP::Data->name('EnquiryNumber' => SOAP::Utils::encode_data($_))->type("")
        ))
    } @_;

    my $responses = $self->perform_request(@operations)->{OperationResponse};
    $responses = [ $responses ] if (ref($responses) eq 'HASH'); # in case only one response came back

    return map { $_->{GetEnquiryResponse}->{Enquiry} } @$responses;
}

sub GetEnquiryLookups {
    my $self = shift;

    my $lookups = $self->memcache->get('GetEnquiryLookups');
    unless ($lookups) {
        $lookups = $self->perform_request(\SOAP::Data->name('GetEnquiryLookups')->type(""));
        $self->memcache->set('GetEnquiryLookups', $lookups, 1800);
    }

    return $lookups;
}

sub NewEnquiry {
    my ($self, $service, $args) = @_;

    my ($service_code, $subject_code) = split /_/, $args->{service_code};
    my %service_types = map { $_->code => $_->datatype } @{ $service->attributes };

    my %enq = (
        EnquiryNumber => 1,
        EnquiryX => $args->{attributes}->{easting},
        EnquiryY => $args->{attributes}->{northing},
        EnquiryReference => $args->{attributes}->{fixmystreet_id},
        EnquiryDescription => substr($args->{description}, 0, 2000),
        ServiceCode => $service_code,
        SubjectCode => $subject_code,
        ContactName => $args->{first_name} . " " . $args->{last_name},
        ContactEmail => $args->{email},
        ContactPhone => $args->{phone},
    );
    if ($args->{location}) {
        $enq{EnquiryLocation} = substr($args->{location}, 0, 2000);
    }
    if ($args->{assigned_officer}) {
        $enq{AssignedOfficerCode} = $args->{assigned_officer};
    }
    if ($args->{site_code}) {
        $enq{SiteCode} = $args->{site_code};
    }
    if ($args->{central_asset_id}) {
        $enq{CentralAssetId} = $args->{central_asset_id};
    }


    my @elements = map {
        my $value = SOAP::Utils::encode_data($enq{$_});
        SOAP::Data->name($_ => $value)->type("")
    } keys %enq;

    for my $code (keys %{ $args->{attributes} }) {
        next if grep {$code eq $_} ('easting', 'northing', 'fixmystreet_id');
        my $value = substr($args->{attributes}->{$code}, 0, 2000);
        my $tag = $service_types{$code} eq 'singlevaluelist' ? 'EnqAttribValueCode' : 'EnqAttribStringValue';
        push @elements, SOAP::Data->name('EnquiryAttribute' => \SOAP::Data->value(
            SOAP::Data->name('EnqAttribTypeCode' => SOAP::Utils::encode_data($code))->type(""),
            SOAP::Data->name($tag => SOAP::Utils::encode_data($value))->type(""),
        ));
    }

    my @customer = (
        SOAP::Data->name('CustomerEmail' => SOAP::Utils::encode_data($args->{email}))->type(""),
        SOAP::Data->name('CustomerPhone' => SOAP::Utils::encode_data($args->{phone}))->type(""),
        SOAP::Data->name('CustomerForename' => SOAP::Utils::encode_data($args->{first_name}))->type(""),
        SOAP::Data->name('CustomerSurname' => SOAP::Utils::encode_data($args->{last_name}))->type(""),
    );
    if (my $enquiry_method = $self->enquiry_method_code) {
        push @customer, SOAP::Data->name('EnquiryMethodCode' => SOAP::Utils::encode_data($enquiry_method))->type("");
    }
    if (my $point_of_contact = $self->point_of_contact_code) {
        push @customer, SOAP::Data->name('PointOfContactCode' => SOAP::Utils::encode_data($point_of_contact))->type("");
    }
    push @elements, SOAP::Data->name('EnquiryCustomer' => \SOAP::Data->value(@customer));

    if ($args->{media_url}->[0]) {
        foreach my $photo_url (@{ $args->{media_url} }) {
            my $notes = "Photo from problem reporter.";
            push @elements, SOAP::Data->name('EnquiryDocument' => \SOAP::Data->value(
                SOAP::Data->name('DocumentNotes' => SOAP::Utils::encode_data($notes))->type(""),
                SOAP::Data->name('DocumentLocation' => SOAP::Utils::encode_data($photo_url))->type(""),
            ));
        }
    }

    if ($args->{report_url}) {
        my $notes = "View report on FixMyStreet.";
        push @elements, SOAP::Data->name('EnquiryDocument' => \SOAP::Data->value(
            SOAP::Data->name('DocumentNotes' => SOAP::Utils::encode_data($notes))->type(""),
            SOAP::Data->name('DocumentLocation' => SOAP::Utils::encode_data($args->{report_url}))->type(""),
        ));
    }


    my $operation = \SOAP::Data->value(
        SOAP::Data->name('NewEnquiry' => \SOAP::Data->value(
            @elements
        ))
    );

    my $response = $self->perform_request($operation);

    if ($response->{Fault}) {
            die "NewEnquiry failed: " . $response->{Fault}->{Reason};
    }

    my $external_id = $response->{OperationResponse}->{NewEnquiryResponse}->{Enquiry}->{EnquiryNumber};

    return $external_id;
}


sub EnquiryUpdate {
    my ($self, $args) = @_;

    my $updated = $args->{updated_datetime};
    my $w3c = DateTime::Format::W3CDTF->new;
    my $updated_time = $w3c->parse_datetime( $updated );
    $updated_time->set_time_zone($self->server_timezone);
    $updated = $w3c->format_datetime($updated_time);

    my %enq = (
        EnquiryNumber => $args->{service_request_id},
        LogEffectiveTime => $updated, # NB this seems to be ignored?
        StatusLogNotes => substr($args->{description}, 0, 2000),
    );

    $enq{EnquiryStatusCode} = $args->{status_code} if $args->{status_code};

    my @elements = map {
        my $value = SOAP::Utils::encode_data($enq{$_});
        SOAP::Data->name($_ => $value)->type("")
    } keys %enq;

    my $operation = \SOAP::Data->value(
        SOAP::Data->name('EnquiryUpdate' => \SOAP::Data->value(
            @elements
        ))
    );

    my $response = $self->perform_request($operation);
    return $response;
}

sub GetEnquiryStatusChanges {
    my ($self, $start, $end) = @_;

    # The Confirm server seems to ignore timezone hints in the datetime
    # string, so we need to convert whatever $start/$end we've been given
    # into (Confirm) local time.
    my $w3c = DateTime::Format::W3CDTF->new;
    my $start_time = $w3c->parse_datetime( $start );
    $start_time->set_time_zone($self->server_timezone);
    $start = $w3c->format_datetime($start_time);

    my $end_time = $w3c->parse_datetime( $end );
    $end_time->set_time_zone($self->server_timezone);
    $end = $w3c->format_datetime($end_time);

    $start = SOAP::Utils::encode_data($start);
    $end = SOAP::Utils::encode_data($end);

    my $operation = \SOAP::Data->value(
        SOAP::Data->name('GetEnquiryStatusChanges' => \SOAP::Data->value(
            SOAP::Data->name('LoggedTimeFrom' => $start)->type(""),
            SOAP::Data->name('LoggedTimeTo' => $end)->type(""),
        ))
    );

    my $response = $self->perform_request($operation);

    my $status_changes = $response->{OperationResponse}->{GetEnquiryStatusChangesResponse};
    my $enquiries = $status_changes ? $status_changes->{UpdatedEnquiry} : [];
    $enquiries = [ $enquiries ] if (ref($enquiries) eq 'HASH');
    return $enquiries;
}

1;
