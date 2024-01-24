package Integrations::Confirm;

use v5.14;
use warnings;
use SOAP::Lite;
use Exporter;
use DateTime::Format::W3CDTF;
use Carp ();
use Moo;
use Open311::Endpoint::Logger;
use JSON::MaybeXS;
use LWP::UserAgent;
use HTTP::Request::Common;
use MIME::Base64 qw(encode_base64 decode_base64);
use Path::Tiny;

use vars qw(@ISA);
@ISA = qw(Exporter SOAP::Lite);

with 'Role::Config';
with 'Role::Memcached';

sub endpoint_url { $_[0]->config->{endpoint_url} }

sub credentials {
    my $config = $_[0]->config;
    return (
        $config->{username},
        $config->{password},
        $config->{tenant_id}
    );
}

# Using "with 'Role::Logger';" causes some issue with SOAP::Lite->proxy
# that I don't understand, so declare the attribute ourselves.
has logger => (
    is => 'lazy',
    default => sub { Open311::Endpoint::Logger->new(config_filename => $_[0]->config_filename) },
);

has ua => (
    is => 'lazy',
    default => sub {
        LWP::UserAgent->new(agent => "FixMyStreet/open311-adapter")
    },
);


=head2 enquiry_method_code

If the Confirm endpoint requires a particular EnquiryMethodCode for NewEnquiry
requests, override this in the subclass. Valid values can be found by calling
the GetCustomerLookup method on the endpoint.

=cut

has 'enquiry_method_code' => (
    is => 'lazy',
    default => sub { $_[0]->config->{enquiry_method_code} }
);


=head2 point_of_contact_code

Similar to enquiry_method_code, if the Confirm endpoint requires a particular
PointOfContactCode for NewEnquiry requests, override this in the subclass.
Valid values can be found by calling the GetCustomerLookup method on the endpoint.

=cut

has 'point_of_contact_code' => (
    is => 'lazy',
    default => sub { $_[0]->config->{point_of_contact_code} }
);


=head2 customer_type_code

Similar to enquiry_method_code/point_of_contact_code, if the Confirm endpoint requires a particular
CustomerTypeCode for NewEnquiry requests, override this in the subclass.
Valid values can be found by calling the GetCustomerLookup method on the endpoint.

=cut

has 'customer_type_code' => (
    is => 'lazy',
    default => sub { $_[0]->config->{customer_type_code} }
);


=head2 send_customer_ref_field

Set this config value to true to send the FixMyStreet report ID into the
CustomerReference field when raising enquiries, as required by some Confirm
clients.

=cut

has 'send_customer_ref_field' => (
    is => 'lazy',
    default => sub { $_[0]->config->{send_customer_ref_field} }
);


=head2 skip_enquiry_ref_field

Set this config value to true to not send the FixMyStreet report ID into the
EnquiryReference field when raising enquiries, as required by some Confirm
clients.

=cut

has 'skip_enquiry_ref_field' => (
    is => 'lazy',
    default => sub { $_[0]->config->{skip_enquiry_ref_field} }
);


=head2 service_enquiry_class_code

If a particular service requires an enquiry class code, we can look this up here

=cut

sub service_enquiry_class_code {
    my ($self, $service_code) = @_;
    my $lookup = $self->config->{service_enquiry_class_code} || {};
    return $lookup->{$service_code};
}


=head2 server_timezone

The timezone that the Confirm server is operating in. 'Europe/London' is almost
certainly what you want.

=cut

has 'server_timezone' => (
    is => 'lazy',
    default => sub { $_[0]->config->{server_timezone} }
);


=head2 completion_statuses

A list of enquiry status codes that determine whether job completion photos
should be looked up when fetching updates.

=cut

has completion_statuses => (
    is => 'lazy',
    default => sub { $_[0]->config->{completion_statuses} || [] }
);


=head2 base_url

The base URL that's used for job completion photo URLs. For mySociety
deployments this should be set to http://<vhost name>/

=cut

has base_url => (
    is => 'lazy',
    default => sub { $_[0]->config->{base_url}  }
);

has oauth_token => (
    is => 'lazy',
    default => sub {
        my $self = shift;

        my $token = $self->memcache->get('oauth_token');
        unless ($token) {
            my ($username, $password, $tenant) = $self->credentials;
            my $url = $self->config->{web_url} . $tenant . "/oauth/token";
            my $req = POST $url, [ grant_type => "client_credentials" ];
            $req->authorization_basic($username, $password);
            my $response = $self->ua->request($req);
            unless ($response->is_success) {
                $self->logger->warn("Getting OAuth token failed: $url");
                return;
            }
            my $content = decode_json($response->content);
            $token = decode_base64($content->{access_token});
            $self->memcache->set('oauth_token', $token, time() + $content->{expires_in});
        }
        return $token;
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
    $self->proxy($self->endpoint_url || Carp::croak("No server address (proxy) specified"), timeout => 360);
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
  $self->serializer->register_ns("http://schemas.xmlsoap.org/wsdl/mime/","mime");
  $self->serializer->register_ns("http://www.confirm.co.uk/schema/am/connector/webservice","tns");
  $self->serializer->register_ns("http://schemas.xmlsoap.org/soap/encoding/","soapenc");
  $self->serializer->register_ns("http://microsoft.com/wsdl/mime/textMatching/","tm");
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

sub perform_request_graphql {
    my ($self, %args) = @_;

    my $uri = URI->new( $self->config->{graphql_url} );
    my $request = HTTP::Request->new(
        'POST',
        $uri,
    );
    $request->header(
        Authorization => 'Basic '
            . $self->config->{graphql_key}
    );
    $request->content_type('application/json; charset=UTF-8');

    my $query;
    if ( $args{type} eq 'job_types' ) {
        $query = $self->job_types_graphql_query();
    } elsif ( $args{type} eq 'jobs' ) {
        $query = $self->jobs_graphql_query(%args);
    } elsif ( $args{type} eq 'job_status_logs' ) {
        $query = $self->job_status_logs_graphql_query(%args);
    }

    my $body = {
        query => $query,
    };

    $request->content(encode_json($body));

    my $response = $self->ua->request($request);

    my $content = decode_json($response->content);

    return $content;
}

# GraphQL queries.
# Confirm docs: https://help.dudesolutions.com/Content/PDF/Confirm/v21.10/confirm-v21-10-web-api-specification.pdf
#
# We use GraphQL to fetch 'job' objects from Confirm.
# You can read about GraphQL at https://graphql.org/learn/
# BUT
# it appears that Confirm's implementation lacks some features, notably
# variable support (hence the use of string interpolation below). It also
# tends to ignore faulty filter definitions in favour of fetching everything.

sub job_status_logs_graphql_query {
    my ( $self, %args ) = @_;

    my @job_type_codes
        = keys %{ $self->config->{job_service_whitelist} // () };

    my @status_codes
        = keys %{ $self->config->{job_reverse_status_mapping} // () };

    my (
        $start_date,
        $end_date,
        $job_type_codes_str,
        $status_codes_str,
    ) = (
        $args{start_date},
        $args{end_date},
        join( ',', @job_type_codes ),
        join( ',', @status_codes ),
    );

    return <<GRAPHQL;
{
    jobStatusLogs(
        filter: {
            loggedDate: {
                greaterThanEquals: "$start_date"
                lessThanEquals: "$end_date"
            }
            statusCode: {
                inList: [ $status_codes_str ]
            }
        }
    ) {
        jobNumber
        key
        loggedDate
        statusCode

        job {
            jobType(
                filter: {
                    code: {
                        inList: [ $job_type_codes_str ]
                    }
                }
            ){
                code
            }
        }
    }
}
GRAPHQL
}

sub jobs_graphql_query {
    my ( $self, %args ) = @_;

    my @job_type_codes
        = keys %{ $self->config->{job_service_whitelist} // () };

    my @status_codes
        = keys %{ $self->config->{job_reverse_status_mapping} // () };

    my (
        $start_date,
        $end_date,
        $job_type_codes_str,
        $status_codes_str,
    ) = (
        $args{start_date},
        $args{end_date},
        join( ',', @job_type_codes ),
        join( ',', @status_codes ),
    );

    return <<"GRAPHQL"
{
    jobs (
        filter: {
            entryDate: {
                greaterThanEquals: "$start_date"
                lessThanEquals: "$end_date"
            }
        }
    ){
        jobType(
            filter: {
                code: {
                    inList: [ $job_type_codes_str ]
                }
            }
        ){
            code
            name
        }

        statusLogs (
            filter: {
                statusCode: {
                    inList: [ $status_codes_str ]
                }
            }
        ) {
            loggedDate
            statusCode
        }

        entryDate
        description
        geometry
        jobNumber

        priority {
            code
            name
        }
    }
}
GRAPHQL
}

sub job_types_graphql_query {
    return <<'GRAPHQL'
{
    jobTypes{
        code
        name
    }
}
GRAPHQL
}

sub GetJobStatusLogs {
    my ( $self, %args ) = @_;

    my $content
        = $self->perform_request_graphql( type => 'job_status_logs', %args );

    return $content->{data}{jobStatusLogs} // [];
}

sub GetJobs {
    my ($self, %args) = @_;

    my $content = $self->perform_request_graphql( type => 'jobs', %args );

    return [] unless $content->{data}{jobs};

    my @jobs;

    # Extra filtering.
    # I don't know how to filter out jobs with certain priorities in the
    # graphql (possibly a limitation of Confirm's implementation), so let's
    # do it here.
    for my $job ( @{$content->{data}{jobs}} ) {
        next
            if $self->config->{job_priority_blacklist}
            && $self->config->{job_priority_blacklist}{ $job->{priority}{code} };

        push @jobs, $job;
    }

    return \@jobs;
}

sub GetJobLookups {
    my $self = shift;

    my $lookups = $self->memcache->get('GetJobLookups');
    unless ($lookups) {
        $lookups = $self->perform_request_graphql(type => 'job_types');

        $self->memcache->set('GetJobLookups', $lookups, 1800);
    }

    return $lookups->{data}{jobTypes} // [];
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

    my %enq = (
        EnquiryNumber => 1,
        EnquiryX => $args->{attributes}->{easting},
        EnquiryY => $args->{attributes}->{northing},
        EnquiryDescription => substr($args->{description}, 0, 2000),
        ServiceCode => $service_code,
        SubjectCode => $subject_code,
    );
    unless ($args->{omit_logged_time}) {
        my $now = DateTime->now();
        $now->set_time_zone($self->server_timezone);
        my $logged_time = DateTime::Format::W3CDTF->new->format_datetime($now);

        $enq{LoggedTime} = $logged_time;
    }
    unless ( $self->config->{skip_enquiry_contact_fields} ) {
        $enq{ContactName} = $args->{first_name} . " " . $args->{last_name};
        $enq{ContactEmail} = $args->{email};
        $enq{ContactPhone} = $args->{phone};
    }
    unless ( $self->skip_enquiry_ref_field ) {
        $enq{EnquiryReference} = $args->{attributes}->{fixmystreet_id};
    }
    if ($args->{location}) {
        $enq{EnquiryLocation} = substr($args->{location}, 0, 2000);
    }
    if ($args->{notes}) {
        $enq{StatusLogNotes} = substr($args->{notes}, 0, 2000);
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

    if ($args->{external_system_number}) {
        $enq{ExternalSystemNumber} = $args->{external_system_number};
        $enq{ExternalSystemReference} = $args->{attributes}->{fixmystreet_id};
    }
    if (my $code = $self->service_enquiry_class_code($service_code)) {
        $enq{EnquiryClassCode} = $code;
    }

    my @elements = map {
        my $value = SOAP::Utils::encode_data($enq{$_});
        SOAP::Data->name($_ => $value)->type("")
    } keys %enq;

    my $tag_types = {
        singlevaluelist => 'EnqAttribValueCode',
        datetime => 'EnqAttribDateValue',
    };

    for my $code (map { $_->code } @{ $service->attributes }) {
        next unless exists $args->{attributes}->{$code};
        next if grep {$code eq $_} ('easting', 'northing', 'fixmystreet_id', 'closest_address');
        my $value = substr($args->{attributes}->{$code}, 0, 2000);

        # FMS will send a blank string if the user didn't make a selection in a
        # non-required singlevaluelist. In that case sending the blank string
        # to Confirm results in an error, so just skip over it.
        next if (!$value && $service_types{$code} eq 'singlevaluelist' && !$attributes_required{$code});

        my $tag = $tag_types->{$service_types{$code}} || 'EnqAttribStringValue';
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
    if (my $point_of_contact = ($args->{point_of_contact_code} || $self->point_of_contact_code)) {
        push @customer, SOAP::Data->name('PointOfContactCode' => SOAP::Utils::encode_data($point_of_contact))->type("");
    }
    if (my $customer_type = $self->customer_type_code) {
        push @customer, SOAP::Data->name('CustomerTypeCode' => SOAP::Utils::encode_data($customer_type))->type("");
    }
    if ( $self->send_customer_ref_field ) {
        push @customer, SOAP::Data->name('CustomerReference' => SOAP::Utils::encode_data($args->{attributes}->{fixmystreet_id}))->type("");
    }
    push @elements, SOAP::Data->name('EnquiryCustomer' => \SOAP::Data->value(@customer));

    if ($args->{media_url}->[0]) {
        foreach my $photo_url (@{ $args->{media_url} }) {
            my $notes = "View photo on FixMyStreet.";
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

    eval { $self->_store_enquiry_documents( $external_id, $args ) };
    warn "Document storage failed: $@" if $@;

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

# Confirm can be slow, so instead of uploading the documents now,
# store them and upload them in a bit
sub _store_enquiry_documents {
    my ($self, $enquiry_number, $args) = @_;

    my $dir = $self->config->{uploads_dir};
    return unless $enquiry_number && $self->config->{web_url} && $dir
        && (@{$args->{media_url}} || @{$args->{uploads}});

    $dir = path($dir);
    $dir->mkpath;

    my $data;
    $data->{media_url} = $args->{media_url} if @{$args->{media_url}};

    if (@{$args->{uploads}}) {
        my $uploads_dir = $dir->child($enquiry_number);
        $uploads_dir->mkpath;
        foreach (@{$args->{uploads}}) {
            my $out = $uploads_dir->child($_->basename);
            path($_)->copy($out);
            push @{$data->{uploads}}, "$out";
        }
    }

    $dir->child("$enquiry_number.json")->spew_utf8(encode_json($data));
}

# If the request succeeded and there are photos or uploaded files, upload
# them to the central enquiries API
sub upload_enquiry_documents {
    my ($self, $enquiry_number, $args) = @_;

    return unless $enquiry_number && $self->config->{web_url};

    my @photos = map {
        my $photo = $self->ua->get($_);
        unless ( $photo->is_success ) {
            my $msg = "[Confirm::upload_enquiry_documents] Couldn't fetch photo from URL $_ : " . $photo->status_line;
            $self->logger->warn($msg);
        }
        {
            documentName => $photo->filename,
            documentNotes => "Photo from problem reporter.",
            blobData => encode_base64($photo->content)
        } if $photo->is_success;
    } @{ $args->{media_url} };

    my @uploads = map {
        my $file = path($_);
        {
            documentName => $file->basename,
            documentNotes => "File from problem reporter.",
            blobData => encode_base64($file->slurp)
        };
    } @{ $args->{uploads} };

    return unless @photos or @uploads;

    my $body = {
        enquiryNumber => $enquiry_number,
        centralDocLinks => [ @photos, @uploads ]
    };

    $self->web_api_call("/centralEnquiries",
        Content_Type => 'application/json',
        Content => encode_json($body))
        or return;
    return 1;
}

sub web_api_call {
    my ($self, $url, %headers) = @_;
    my $token = $self->oauth_token or return;
    my ($username, $password, $tenant) = $self->credentials;
    my $full_url = $self->config->{web_url} . $tenant . $url;
    my $method = $headers{Content} ? 'post' : 'get';
    my $response = $self->ua->$method($full_url, AccessToken => $token, %headers);
    unless ($response->is_success) {
        $self->logger->warn("Couldn't fetch $url: " . $response->content);
        return;
    };
    return $response;
}

sub json_web_api_call {
    my ($self, $url, %headers) = @_;
    $headers{Content_Type} = 'application/json';
    my $response = $self->web_api_call($url, %headers) or return;
    return decode_json($response->content);
}

sub get_enquiry_json {
    my ($self, $enquiry_id) = @_;
    return $self->json_web_api_call("/enquiries/$enquiry_id");
}

sub documents_for_job {
    my ($self, $job_id) = @_;
    my $data = $self->json_web_api_call("/jobs/$job_id");
    return $data->{documents} || [];
}

sub get_job_photo {
    my ($self, $job_id, $photo_id) = @_;
    my $response = $self->web_api_call("/documents/0/JOB/$job_id/$photo_id") or return;
    my $type = $response->header('Content-Type') || '';
    return unless $type =~ m{image/(jpeg|pjpeg|gif|tiff|png)}i;
    return ( $type, $response->decoded_content );
}

1;
