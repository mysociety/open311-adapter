package Integrations::Confirm;

use SOAP::Lite;
use Exporter;
use DateTime::Format::W3CDTF;
use Carp ();
use Moo;
use Cache::Memcached;

use vars qw(@ISA);
@ISA = qw(Exporter SOAP::Lite);

sub endpoint_url { $_[0]->config->{endpoint_url} }

sub credentials {
    my $config = $_[0]->config;
    return (
        $config->{username},
        $config->{password},
        $config->{tenant_id}
    );
}

# If the Confirm endpoint requires a particular EnquiryMethodCode for NewEnquiry
# requests, override this in the subclass. Valid values can be found by calling
# the GetCustomerLookup method on the endpoint.
has 'enquiry_method_code' => (
    is => 'lazy',
    default => sub { $_[0]->config->{enquiry_method_code} }
);

# Similar to enquiry_method_code, if the Confirm endpoint requires a particular
# PointOfContactCode for NewEnquiry requests, override this in the subclass.
# Valid values can be found by calling the GetCustomerLookup method on the endpoint.
has 'point_of_contact_code' => (
    is => 'lazy',
    default => sub { $_[0]->config->{point_of_contact_code} }
);

has 'server_timezone' => (
    is => 'lazy',
    default => sub { $_[0]->config->{server_timezone} }
);

has memcache_namespace  => (
    is => 'lazy',
    default => sub { $_[0]->config_filename }
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
    my $opts = ref $_[-1] eq 'HASH' ? pop : {};

    my @operations = map {
        SOAP::Data->name('Operation' => $_)
    } @_;

    my ($username, $password, $tenant) = $self->credentials;

    my $request = SOAP::Data->name('Request' => \SOAP::Data->value(
        SOAP::Data->name('Authentication' => \SOAP::Data->value(
            SOAP::Data->name('Username' => SOAP::Utils::encode_data($username))->type(""),
            SOAP::Data->name('Password' => SOAP::Utils::encode_data($password))->type(""),
            SOAP::Data->name('DatabaseId' => SOAP::Utils::encode_data($tenant))->type(""),
        )),
        @operations
    ));

    my $response = $self->ProcessOperationsRequest($request);
    die $response->{Fault}->{Reason} if ($response->{Fault} && !$opts->{return_on_fault});

    return $response;
}

sub GetEnquiries {
    my $self = shift;

    # avoid errors if called with no enquiries to fetch
    return () unless @_;

    my @operations = map {
        \SOAP::Data->name('GetEnquiry' => \SOAP::Data->value(
            SOAP::Data->name('EnquiryNumber' => SOAP::Utils::encode_data($_))->type("")
        ))
    } @_;

    # Confirm can be very slow to return results for calls containing lots
    # of GetEnquiry operations, and in some cases can hit the 300 second timeout
    # on their end. We work around this by breaking the operations into smaller
    # batches and requesting a few at a time.
    my @enquiries = ();
    my $batch_size = 10;
    while ( my @batch = splice @operations, 0, $batch_size ) {
        my $responses = $self->perform_request(@batch)->{OperationResponse};
        $responses = [ $responses ] if (ref($responses) eq 'HASH'); # in case only one response came back
        push @enquiries, map { $_->{GetEnquiryResponse}->{Enquiry} } @$responses;
    }

    return @enquiries;
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

    my ($service_code, $subject_code) = split /_/, $service->service_code;
    my %service_types = map { $_->code => $_->datatype } @{ $service->attributes };
    my %attributes_required = map { $_->code => $_->required } @{ $service->attributes };

    my $now = DateTime->now();
    $now->set_time_zone($self->server_timezone);
    my $logged_time = DateTime::Format::W3CDTF->new->format_datetime($now);

    my %enq = (
        EnquiryNumber => 1,
        EnquiryX => $args->{attributes}->{easting},
        EnquiryY => $args->{attributes}->{northing},
        EnquiryReference => $args->{attributes}->{fixmystreet_id},
        EnquiryDescription => substr($args->{description}, 0, 2000),
        LoggedTime => $logged_time,
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
        next if grep {$code eq $_} ('easting', 'northing', 'fixmystreet_id', 'closest_address');
        my $value = substr($args->{attributes}->{$code}, 0, 2000);

        # FMS will send a blank string if the user didn't make a selection in a
        # non-required singlevaluelist. In that case sending the blank string
        # to Confirm results in an error, so just skip over it.
        next if (!$value && $service_types{$code} eq 'singlevaluelist' && !$attributes_required{$code});

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
        LoggedTime => $updated,
        StatusLogNotes => substr($args->{description}, 0, 2000),
    );

    $enq{EnquiryStatusCode} = $args->{status_code} if $args->{status_code};

    my $response = $self->perform_request($self->operation_for_update(\%enq), { return_on_fault => 1});

    return $response unless $response->{Fault};

    # Confirm rejects an update if it appears to be older than any existing
    # updates on an enquiry.
    # In this case, we resubmit the update using the current timestamp instead
    # of the updated_datetime value received over Open311.
    # To ensure this doesn't cause unexpected status changes within Confirm
    # we don't set the EnquiryStatusCode in this resubmission.
    my $reason = $response->{Fault}->{Reason};
    die $reason unless $reason =~ /Logged Date [\d\/:\s]+ must be greater than the Effective Date/;

    delete $enq{EnquiryStatusCode} if $enq{EnquiryStatusCode};
    delete $enq{LoggedTime} if $enq{LoggedTime};
    return $self->perform_request($self->operation_for_update(\%enq));
}

sub operation_for_update {
    my ($self, $enq) = @_;

    my @elements = map {
        my $value = SOAP::Utils::encode_data($enq->{$_});
        SOAP::Data->name($_ => $value)->type("")
    } keys %$enq;

    return \SOAP::Data->value(
        SOAP::Data->name('EnquiryUpdate' => \SOAP::Data->value(
            @elements
        ))
    );
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
