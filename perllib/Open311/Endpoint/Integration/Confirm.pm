package Open311::Endpoint::Integration::Confirm;

use Moo;
use DateTime::Format::W3CDTF;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';
with 'Open311::Endpoint::Role::ConfigFile';
with 'Role::Logger';

use Open311::Endpoint::Service::UKCouncil::Confirm;
use Open311::Endpoint::Service::Attribute;
use Open311::Endpoint::Service::Request::Update::mySociety;
use Open311::Endpoint::Service::Request::Confirm;
use Integrations::Confirm;

use Path::Tiny;
use SOAP::Lite; # +trace => [ qw/method debug/ ];


has jurisdiction_id => (
    is => 'ro',
);


=head2 service_whitelist

Controls the mapping of Confirm service/subject codes to Open311 services.
Subclasses must override this or no Open311 services will be published!

Returns a hashref which groups services together and optionally provides
an overridden name for each service.

For example, the following hashref will publish 7 Open311 services:

{
    'Roads' => {
        RO_PH => 1,
        RO_GB => 1,
        RO_LP => "Faded Markings",
        RM_TR_1 => "Tree",
        RM_TR_2 => "Hedge",
    },
    'Lighting' => {
        LG_SL => 1,
        LG_BL => 1,
    }
}

5 services will be published with their group set to 'Roads', and two in
the 'Lighting' group. RO_PH, RO_GB, LG_SL, and LG_BL will take the subject
name from Confirm as their Open311 service name. RO_LP shows how the Confirm
default can be overridden, and this service will be published as 'Faded
Markings'. RM_TR_1 and RM_TR_2 will both map to Confirm RM_TR; this
enables one Confirm code to have multiple services.

I opted for a whitelist instead of a blacklist because Councils tend to have
hundreds of available service/subject codes in their Confirm instances but
typically only want to publish a small number (to begin with) on FixMyStreet.

=cut

has service_whitelist => (
    is => 'ro',
    default => sub {
        return {} if $ENV{TEST_MODE} || ($ENV{PLACK_ENV}||'') eq 'development';
        die "Attribute Confirm::service_whitelist not overridden";
    }
);

=head2 handle_jobs

Whether cobrand fetches jobs from Confirm alongside enquiries. This is
based on whether the cobrand has provided a list of services for jobs in its config.

=cut

has handle_jobs => (
    is => 'lazy',
    default => sub {
        return $_[0]->get_integration->config->{job_service_whitelist} ? 1 : 0;
    }
);

=head2 job_service_whitelist

Controls the mapping of Confirm job service/subject codes to Open311 services
(as opposed to service_whitelist, which handles enquiry services)

=cut

has job_service_whitelist => (
    is => 'ro',
    default => sub {
        return {};
    }
);

=head2 handle_defects

Whether cobrand fetches defects from Confirm alongside enquiries. This is
based on whether the cobrand has provided a list of services for defects in its config.

=cut

has handle_defects => (
    is => 'lazy',
    default => sub {
        return $_[0]->get_integration->config->{defect_service_mapping} ? 1 : 0;
    }
);

=head2 use_graphql_for_enquiries

Whether this integration fetches enquiries and enquiry updates using GraphQL.
This is based on the presence of the graphql_url in the Confirm integration
and graphql_key in config.

=cut

has use_graphql_for_enquiries => (
    is => 'lazy',
    default => sub {
        my $integ = $_[0]->get_integration;
        return ($integ->graphql_url && $integ->config->{graphql_key}) ? 1 : 0;
    }
);

=head2 defect_service_mapping

Controls the mapping of Confirm defect service/subject codes to Open311 services
(as opposed to service_whitelist, which handles enquiry services)

=cut

has defect_service_mapping => (
    is => 'ro',
    default => sub {
        return {};
    }
);

=head2 wrapped_services

Some Confirm installations are configured in a manner that encodes metadata
about enquiries in the subject code, instead of an attribute. For example,
rather than having a single "Pothole" category with a
"What size is the pothole?" => [ "small", "large" ] attribute, it may have two
individual subjects: "Small pothole" & "Large pothole". This presents a
problem if we want to display a user-friendly hierarchy of categories to a user
on FMS, as despite using groups the category lists may be very long.

This wrapped_services hashref allows us to present multiple Confirm subjects as
a single Open311 service (category), and the choice between the multiple wrapped
subjects is shown as a singlevaluelist attribute on the Open311 service.

Continuing the above example, let's say we want to present our two Confirm
subjects ('Small pothole', with code 'RD_PHS'; and 'Large pothole' with code
'RD_PHL') as a single 'Pothole' Open311 service. In the config YAML file, we'd
include the following 'wrapped_services' key:

  "wrapped_services": {
    "POTHOLES": {
      "group": "Road Defects",
      "name": "Pothole",
      "wraps": [
        "HM_PHS",
        "HM_PHL",
      ]
    },
  }

A single Open311 service called "Pothole" would be published at /services.xml
with a singlevaluelist attribute called "_wrapped_service_code" with two
options, one for each of the HM_PHS & HM_PHL subjects. Because these wrapped
services may have their own attributes, these will be merged together and
included on the Pothole service.

If a Confirm subject should be presented as its own Open311 category,
use the "passthrough" attribute rather than a "wraps" of length 1, e.g.:

  "wrapped_services": {
    "ST_STP4": {
      "passthrough": 1,
      "group": "Bridges and safety barriers",
    },
  }

The subject name as defined in service_whitelist will be used for the category
name.

Some caveats to note:

 - If wrapped_services is defined, *only* services from the definition will be
   published.
 - Services to be wrapped must be present in service_whitelist.

=cut

has wrapped_services => (
    is => 'ro',
    default => sub { undef }
);

=head2 private_services

Some Confirm services should be marked as private in the Open311 service
metadata. This is implemented by including 'private' in the keywords for the
service.

This attribute should be an arrayref of Open311 service_code codes to mark as
private.

This also has the effect of marking fetched ServiceRequests for these services
as non_public.

=cut

has private_services => (
    is => 'ro',
    default => sub { [] }
);

=head2 ignored_attributes

Some Confirm attributes should never be published in the Open311 service
metadata.

This attribute should be an arrayref of Confirm attribute codes to ignore.

=cut

has ignored_attributes => (
    is => 'ro',
    default => sub { [] }
);

=head2 ignored_attribute_options

Some options Confirm attributes should never be published in the Open311 service
metadata.

This attribute should be an arrayref of Confirm attribute option codes to ignore.

=cut

has ignored_attribute_options => (
    is => 'ro',
    default => sub { [] }
);


=head2 attribute_overrides

Allows individual attributes' initialisers to be overridden.
Useful for, e.g. making Confirm mandatory fields not required by Open311,
setting the 'automated' field etc.

=cut

has attribute_overrides => (
    is => 'ro',
    default => sub { {} }
);


=head2 forward_status_mapping

Maps Open311 service request status codes to Confirm enquiry status codes.
This is used if incoming service request updates modify the service request
status.

If an Open311 code is omitted from this mapping then the Confirm enquiry status
won't be changed.

=cut

has forward_status_mapping => (
    is => 'ro',
    default => sub { {} }
);


=head2 reverse_status_mapping

Maps Confirm enquiry status codes to Open311 service request status codes.
Used for service request updates which are generated by enquiry updates in
Confirm, and for service requests initially fetched from Confirm.

All possible Confirm enquiry status values should be mapped to Open311 statuses.

=cut

has reverse_status_mapping => (
    is => 'ro',
    default => sub { {} }
);

=head2 job_reverse_status_mapping

Maps Confirm job status codes to Open311 service request status codes.
Used for service request updates which are generated by job updates in
Confirm, and for job service requests initially fetched from Confirm.

=cut

has job_reverse_status_mapping => (
    is => 'ro',
    default => sub { {} }
);

=head2 request_ignore_statuses

A list of Confirm enquiry status codes that means those Confirm enquiries
should be ignored when fetched.

=cut

has request_ignore_statuses => (
    is => 'ro',
    coerce => sub {
        my $l = shift;
        $l = [ $l ] unless ref $l eq 'ARRAY';
        return { map { $_ => 1 } @$l };
    },
    default => sub { [] }
);

=head2 service_class

Subclasses can override this to provide their own custom Service class, e.g.
if they want to have extra attributes on all services. By default we use the
UKCouncil::Confirm class which requests the FMS title/description in separate
attributes, as well as any asset information from the map.

=cut

has service_class  => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::UKCouncil::Confirm'
);


=head2 publish_service_update_text

This flag controls whether to include the text from enquiry
status logs in the get_service_request_updates output.
Some councils treat the text entered into Confirm as private
and publishing it via Open311 could cause various privacy issues.
Be sure the Confirm users have been consulted before turning this on!

=cut

has publish_service_update_text => (
    is => 'ro',
    default => 0
);


=head2 service_assigned_officers

Confirm has the ability to assign 'action officers' to enquiries, but doesn't
have the nous to assign different defaults for each service/subject code.
Subclasses can override this attribute to specificy the correct office code
to assign for new enquiries. The list of valid codes can be found with the
GetAllActionOfficers call to the Confirm SOAP endpoint.
This attribute should be a hashref mapping Open311 service codes to the
Confirm OfficerCode to assign to each. Not all service codes have to be
specified, only those you wish to override the default officer for.

=cut

has service_assigned_officers => (
    is => 'ro',
    default => sub { {} }
);


=head2 attribute_descriptions

Some Confirm attribute names can be quite opaque and not very helpful for the
end user. This mapping allows individual attribute names to be overridden.

=cut

has attribute_descriptions => (
    is => 'ro',
    default => sub { {} }
);

=head2 attribute_value_overrides

Some options Confirm attributes need a different name in the Open311 service
metadata. This attribute should be a hashref of Confirm service codes to a
hashref mapping attribute option name to their new name to use.

=cut

has attribute_value_overrides => (
    is => 'ro',
    default => sub { {} }
);

sub service_request_content {
    '/open311/service_request_extended'
}

has default_site_code => (
    is => 'ro',
    default => ''
);

has omit_logged_time => (
    is => 'ro',
    default => 0
);

=head2 cutoff_enquiry_date

A date before which you never want to return
enquiries from a get_service_requests call.

=cut

my $w3c = DateTime::Format::W3CDTF->new;

has cutoff_enquiry_date => (
    is => 'ro',
    coerce => sub { $w3c->parse_datetime($_[0]) },
);

has fetch_reports_private => (
    is => 'ro',
    default => 0,
);

has include_private_customer_details => (
    is => 'ro',
    default => 0,
);

has date_parser => (
    is => 'ro',
    default => sub { $w3c },
);


sub process_service_request_args {
    my $self = shift;
    my $args = shift;

    if ($args->{address_string}) {
        $args->{description} .= "\n\nLocation query entered: " . $args->{address_string};
    }

    # The Service::UKCouncil::Confirm class requests several metadata attributes
    # which we need to bump up from the attributes hashref to the $args passed
    # to Integrations::Confirm->NewEnquiry
    foreach (qw/report_url site_code central_asset_id description/) {
        if (defined $args->{attributes}->{$_}) {
            $args->{$_} = $args->{attributes}->{$_};
            delete $args->{attributes}->{$_};
        }
    }

    if (my $assigned_officer = $self->service_assigned_officers->{$args->{service_code}}) {
        $args->{assigned_officer} = $assigned_officer;
    }

    # Some Confirm installations should have enquiries matched against a
    # default SiteCode if it wasn't specified from FMS.
    if (!$args->{site_code} && $self->default_site_code) {
        $args->{site_code} = $self->default_site_code;
    }

    if ( my $loc = delete $args->{attributes}{location} ) {
        # Some cobrands such as Gloucestershire will have set a custom
        # 'location' in the 'attributes' field, so use this.
        $args->{location} = $loc;
    } else {
        # Otherwise use 'title' from 'attributes'.
        # Because Open311 doesn't support a 'title' field for service
        # requests, FMS concatenates the report title and description together
        # in the description field. We want to put the title/description in
        # different fields in Confirm, so they're sent as individual Open311
        # attributes which we put directly in $args so NewEnquiry can do the
        # right thing.
        $args->{location} = $args->{attributes}->{title};
    }
    # Delete title in either case
    delete $args->{attributes}->{title};

    # Any asset information is appended to the Confirm location field, if
    # present, as Confirm doesn't have a specific way of allowing us to
    # identify assets that we've come across yet.
    if ( defined $args->{attributes}->{asset_details} ) {
        if ( $args->{attributes}->{asset_details} ) {
            $args->{location} .= "\nAsset information:\n" . $args->{attributes}->{asset_details};
        }
        delete $args->{attributes}->{asset_details};
    }

    return $args;
}

has '+request_class' => (
    is => 'ro',
    default => 'Open311::Endpoint::Service::Request::Confirm',
);

has 'integration_class' => (
    is => 'ro',
    default => 'Integrations::Confirm',
);

sub get_integration {
    my $self = shift;
    my $integ = $self->integration_class;
    $integ = $integ->on_fault(sub { my($soap, $res) = @_; die ref $res ? $res->faultstring : $soap->transport->status, "\n"; });
    $integ->config_filename($self->jurisdiction_id);
    $self->log_identifier($self->jurisdiction_id);
    return $integ;
}

sub post_service_request {
    my ($self, $service, $args) = @_;
    die "No such service" unless $service;

    my $integ = $self->get_integration;

    if ($args->{attributes}->{_wrapped_service_code}) {
        my ($wrapped_service) = grep { $_->service_code eq $args->{attributes}->{_wrapped_service_code} } $self->_services;
        die "No such wrapped service" unless $wrapped_service;
        $service = $wrapped_service;
        delete $args->{attributes}->{_wrapped_service_code};
    }

    $args = $self->process_service_request_args($args);

    if ($self->omit_logged_time) {
        $args->{omit_logged_time} = 1;
    }

    my $new_id = $integ->NewEnquiry($service, $args);

    die "Couldn't create Enquiry in Confirm" unless defined $new_id;

    my $request = $self->new_request(
        service_request_id => $new_id,
    );

    return $request;
}

sub post_service_request_update {
    my ($self, $args) = @_;

    if ($args->{media_url}->[0]) {
        $args->{description} .= "\n\n[ This update contains a photo, see: " . $args->{media_url}->[0] . " ]";
    }

    if (my $status_code = $self->forward_status_mapping->{$args->{status}}) {
        $args->{status_code} = $status_code;
    }

    my $response = $self->get_integration->EnquiryUpdate($args);
    my $enquiry = $response->{OperationResponse}->{EnquiryUpdateResponse}->{Enquiry};
    my $update_id = $enquiry->{EnquiryNumber} .  "_" . $enquiry->{EnquiryLogNumber};

    return Open311::Endpoint::Service::Request::Update::mySociety->new(
        service_request_id => $enquiry->{EnquiryNumber},
        status => lc $args->{status},
        update_id => $update_id,
    );

}


sub get_service_request_updates {
    my ($self, $args) = @_;

    my $integ = $self->get_integration;
    my %completion_statuses = map { $_ => 1} @{ $integ->completion_statuses };

    my @updates = ();

    if ($self->use_graphql_for_enquiries) {
        my $w3c = DateTime::Format::W3CDTF->new;
        my $start_time = $w3c->parse_datetime( $args->{start_date} );
        $start_time->set_time_zone($integ->server_timezone);
        my $start = $w3c->format_datetime($start_time);

        my $end_time = $w3c->parse_datetime( $args->{end_date} );
        $end_time->set_time_zone($integ->server_timezone);
        my $end = $w3c->format_datetime($end_time);

        my $query = <<GRAPHQL;
{
  enquiryStatusLogs(
    filter: {
      loggedDate: {
        lessThanEquals: "$end"
        greaterThanEquals: "$start"
      }
    }
  ) {
    enquiryNumber
    enquiryStatusCode
    logNumber
    loggedDate
    notes
    centralEnquiry {
      subjectCode
      serviceCode
    }
  }
}
GRAPHQL
        my $results =$integ->perform_request_graphql(query => $query)->{data}->{enquiryStatusLogs};
        for my $status_log (@$results) {
            my $enquiry_id = $status_log->{enquiryNumber};
            my $update_id = $enquiry_id . "_" . $status_log->{logNumber};
            my $ts = $self->date_parser->parse_datetime($status_log->{loggedDate})->truncate( to => 'second' );
            $ts->set_time_zone($integ->server_timezone);
            my $description = $self->publish_service_update_text ?
                ($status_log->{notes} || "") :
                "";
            my $status = $self->reverse_status_mapping->{$status_log->{enquiryStatusCode}};
            next if $status && $status eq 'IGNORE';
            if (!$status) {
                $self->logger->warn("Missing reverse status mapping for EnquiryStatus Code $status_log->{enquiryStatusCode} (EnquiryNumber $enquiry_id)");
                $status = "open";
            }

            my $media_urls;
            if ($completion_statuses{$status_log->{enquiryStatusCode}}) {
                # This enquiry has been marked as complete by this update;
                # see if there's a photo.
                $media_urls = $self->photo_urls_for_update($enquiry_id); # XXX we should instead get this all in one GraphQL query, above
            }

            push @updates, Open311::Endpoint::Service::Request::Update::mySociety->new(
                status => $status,
                update_id => $update_id,
                service_request_id => $enquiry_id,
                description => $description,
                updated_datetime => $ts,
                external_status_code => $status_log->{enquiryStatusCode},
                $media_urls ? ( media_url => $media_urls ) : (),
            );
        }
    } else {
        my $enquiries = $integ->GetEnquiryStatusChanges(
            $args->{start_date},
            $args->{end_date}
        );

        for my $enquiry (@$enquiries) {
            my $status_logs = $enquiry->{EnquiryStatusLog};
            $status_logs = [ $status_logs ] if (ref($status_logs) eq 'HASH');
            for my $status_log (@$status_logs) {
                my $enquiry_id = $enquiry->{EnquiryNumber};
                my $update_id = $enquiry_id . "_" . $status_log->{EnquiryLogNumber};
                my $ts = $self->date_parser->parse_datetime($status_log->{LoggedTime})->truncate( to => 'second' );
                $ts->set_time_zone($integ->server_timezone);
                my $description = $self->publish_service_update_text ?
                    ($status_log->{StatusLogNotes} || "") :
                    "";
                my $status = $self->reverse_status_mapping->{$status_log->{EnquiryStatusCode}};
                next if $status && $status eq 'IGNORE';
                if (!$status) {
                    $self->logger->warn("Missing reverse status mapping for EnquiryStatus Code $status_log->{EnquiryStatusCode} (EnquiryNumber $enquiry->{EnquiryNumber})");
                    $status = "open";
                }

                my $media_urls;
                if ($completion_statuses{$status_log->{EnquiryStatusCode}}) {
                    # This enquiry has been marked as complete by this update;
                    # see if there's a photo.
                    $media_urls = $self->photo_urls_for_update($enquiry_id);
                }

                push @updates, Open311::Endpoint::Service::Request::Update::mySociety->new(
                    status => $status,
                    update_id => $update_id,
                    service_request_id => $enquiry_id,
                    description => $description,
                    updated_datetime => $ts,
                    external_status_code => $status_log->{EnquiryStatusCode},
                    $media_urls ? ( media_url => $media_urls ) : (),
                );
            }
        }
    }

    if ( $self->handle_jobs ) {
        $self->_get_service_request_updates_for_jobs($integ, $args, \@updates);
    }
    if ( $self->handle_defects ) {
        $self->_get_service_request_updates_for_defects($integ, $args, \@updates);
    }

    return @updates;
}

sub _get_service_request_updates_for_jobs {
    my ($self, $integ, $args, $updates) = @_;

    return unless $self->handle_jobs;

    my $status_logs = $integ->GetJobStatusLogs(
        start_date => $args->{start_date},
        end_date   => $args->{end_date},
    );

    for my $log ( @{$status_logs} ) {
        my $status
            = $self->job_reverse_status_mapping->{ $log->{statusCode} };

        if (!$status) {
            # This shouldn't happen given that we filter by status code
            # in graphql. But just in case, default to open.
            $self->logger->warn(
                "Missing reverse job status mapping for statusCode $log->{statusCode} (jobNumber $log->{jobNumber})"
            );
            $status = "open";
        }

        my $dt
            = $self->date_parser->parse_datetime( $log->{loggedDate} )
            ->truncate( to => 'second' );
        $dt->set_time_zone( $integ->server_timezone );

        push @$updates,
            Open311::Endpoint::Service::Request::Update::mySociety->new(
            status               => $status,
            update_id            => 'JOB_' . $log->{key},
            service_request_id   => 'JOB_' . $log->{jobNumber},
            updated_datetime     => $dt,
            external_status_code => $log->{statusCode},
            description          => '',
        );
    }
}

sub _get_service_request_updates_for_defects {
    my ($self, $integ, $args, $updates) = @_;

    return unless $self->handle_defects;

    my $status_logs = $integ->GetDefectStatusLogs(
        start_date => $args->{start_date},
        end_date   => $args->{end_date},
    );

    for my $log ( @{$status_logs} ) {
        my $status
            = $self->job_reverse_status_mapping->{ $log->{statusCode} };

        if (!$status) {
            # This shouldn't happen given that we filter by status code
            # in graphql. If it does, just ignore this update.
            $self->logger->warn(
                "Missing reverse job status mapping for statusCode $log->{statusCode} (jobNumber $log->{jobNumber})"
            );
            next;
        }

        my $dt
            = $self->date_parser->parse_datetime( $log->{loggedDate} )
            ->truncate( to => 'second' );
        $dt->set_time_zone( $integ->server_timezone );

        for my $defect ( @{$log->{job}->{defects}} ) {
            push @$updates,
                Open311::Endpoint::Service::Request::Update::mySociety->new(
                status               => $status,
                update_id            => 'DEFECT_' . $defect->{defectNumber} . "_" . $log->{key},
                service_request_id   => 'DEFECT_' . $defect->{defectNumber},
                updated_datetime     => $dt,
                external_status_code => $log->{statusCode},
                description          => $defect->{targetDate} || '',
            );
        }
    }
}

sub photo_filter {
    my ($self, $doc) = @_;
    return $doc->{fileName} =~ /jpe?g/i;
}

sub photo_urls_for_update {
    my ($self, $enquiry_id) = @_;
    my $integ = $self->get_integration;

    my $enquiry = $integ->get_enquiry_json($enquiry_id) or return;
    my $job_id = $enquiry->{jobNumber};
    my $documents = $integ->documents_for_job($job_id) or return;

    my @ids = map { $_->{documentNo} } grep { $self->photo_filter($_) } @$documents;
    return unless @ids;

    my $jurisdiction_id = $self->jurisdiction_id;
    my @urls = map { $integ->config->{base_url} . "photo/completion?jurisdiction_id=$jurisdiction_id&job=$job_id&photo=$_" } @ids;

    return \@urls;
}

sub services {
    my $self = shift;
    my @services = $self->_services;

    @services = $self->_wrap_services(@services) if defined $self->wrapped_services;

    push @services, $self->job_services;

    push @services, $self->defect_services;

    return @services;
}

sub _services {
    my $self = shift;

    my $integ = $self->get_integration;

    my $response = $integ->GetEnquiryLookups();
    my $confirm_services = $response->{OperationResponse}->{GetEnquiryLookupsResponse}->{TypeOfService};

    my $available_attributes = $self->_parse_attributes($response);

    my %ignored_attribs = map { $_ => 1 } @{$self->ignored_attributes};
    my %private_services = map { $_ => 1 } @{$self->private_services};

    my %services = ();
    for my $service (@$confirm_services) {
        my $servicename = $service->{ServiceName};
        my $servicecode = $service->{ServiceCode};

        my $subjects = $service->{EnquirySubject};
        $subjects = [ $subjects ] if (ref($subjects) eq 'HASH');

        for my $subject (@$subjects) {
            my $code = $servicecode . "_" . $subject->{SubjectCode};

            my $subjectattributes = $subject->{SubjectAttribute};
            $subjectattributes = [ $subjectattributes ] if (ref($subjectattributes) eq 'HASH');

            my @attribs = map {
                $available_attributes->{$_->{EnqAttribTypeCode}}
            } grep {
                !$ignored_attribs{$_->{EnqAttribTypeCode}}
            } @$subjectattributes;

            $services{$code} = {
                service => $service,
                subject => $subject,
                attribs => \@attribs,
            };
        }
    }

    my @services = ();
    my %service_codes;
    my $fetch_all_services = 0;
    my $service_whitelist = $fetch_all_services ? { '' => 'DUMMY' } : $self->service_whitelist;
    for my $group (sort keys %$service_whitelist) {
        my $whitelist = $fetch_all_services ? \%services : $self->service_whitelist->{$group};
        for my $code (keys %{ $whitelist }) {
            my $confirm_code = _normalise_service_code($code);
            my $subject = $services{$confirm_code}->{subject};
            if (!$subject) {
                $self->logger->error("$confirm_code doesn't exist in Confirm.");
                next;
            }
            my $name = $subject->{SubjectName};
            $name = $whitelist->{$code} if !$fetch_all_services && $whitelist->{$code} ne 1;
            if ( defined $service_codes{ $code } ) {
                push @{$service_codes{$code}->{groups}}, $group;
            } else {
                $service_codes{$code} = {
                    service_name => $name,
                    service_code => $code,
                    description => $name,
                    $group ? (groups => [$group]) : (),
                    keywords => $private_services{$code} ? [qw/ private /] : [],
                };
            }
        }
    }
    for my $code (sort keys %service_codes) {
        my $confirm_code = _normalise_service_code($code);
        my %service = %{ $service_codes{$code} };
        my $o311_service = $self->service_class->new(%service);
        for (@{$services{$confirm_code}->{attribs}}) {
            push @{$o311_service->attributes}, $_;
        }
        push @services, $o311_service;
    }

    return @services;
}

sub job_services {
    my $self = shift;

    return () unless $self->handle_jobs;

    my $integ = $self->get_integration;
    my $possible_services = $integ->GetJobLookups;

    $possible_services = {
        map { $_->{code} => $_ } @$possible_services
    };

    my @services;
    my %service_codes;

    my $service_whitelist = $self->job_service_whitelist;

    for my $code (keys %{ $service_whitelist }) {
        if (!$possible_services->{$code}) {
            $self->logger->error("Job type $code doesn't exist in Confirm.");
            next;
        }

        my $name;
        $name = $service_whitelist->{$code}
            if $service_whitelist->{$code} ne 1;
        $name ||= $possible_services->{$code}{name};

        $service_codes{$code} = {
            service_name   => $name,
            service_code   => $code,
            description    => $name,
            keywords       => [ qw/inactive/ ],
        };
    }

    for my $code (sort keys %service_codes) {
        my %service = %{ $service_codes{$code} };
        my $o311_service = $self->service_class->new(%service);
        push @services, $o311_service;
    }

    return @services;
}

sub defect_services {  # XXX factor together with jobs?
    my $self = shift;

    return () unless $self->handle_defects;

    my $integ = $self->get_integration;
    my $possible_services = $integ->GetDefectLookups;

    $possible_services = {
        map { $_->{code} => $_ } @$possible_services
    };

    my @services;
    my %service_codes;

    my $service_whitelist = $self->defect_service_mapping;

    for my $code (keys %{ $service_whitelist }) {
        if (!$possible_services->{$code}) {
            $self->logger->error("Defect type $code doesn't exist in Confirm.");
            next;
        }

        # The values in defect_service_mapping are hashrefs and the contents
        # determine if/how we create services.
        # service_alias: this key indicates fetched defects will appear in an
        #                existing service from service_whitelist, so don't create
        #                a new service now.
        # defect_alias: this key means fetched defects will have their code remapped
        #               to another defect type (e.g. you want multiple defect types to
        #               appear under a single category on FMS), don't create a service now.
        # group/category: create a service for this defect type with the given group & name.
        my $cfg = $service_whitelist->{$code};
        next unless $cfg->{group} && $cfg->{category};

        $service_codes{"DEFECT_" . $code} = {
            service_name   => $cfg->{category},
            service_code   => "DEFECT_" . $code,
            description    => $cfg->{category},
            keywords       => [ qw/inactive/ ],
            groups         => [ $cfg->{group} ],
        };
    }

    for my $code (sort keys %service_codes) {
        my %service = %{ $service_codes{$code} };
        my $o311_service = $self->service_class->new(%service);
        push @services, $o311_service;
    }

    return @services;
}

sub get_service_request {
    my ($self, $id) = @_;

    my $response = $self->get_integration->GetEnquiry($id);

    return Open311::Endpoint::Service::Request->new();
}


sub get_service_requests {
    my ($self, $args) = @_;

    my $integ = $self->get_integration;
    my @requests;
    my @services = $self->services;
    # Some Confirm configurations map multiple Open311 services to one Confirm
    # service/subject code - these are indicated with a _1/_2/etc suffix in
    # service_whitelist. When fetching Enquiries from Confirm we join the
    # service & subject code with _ and lookup the corresponding Open311
    # service, which might fail if only the _1 suffixed version exists. So here
    # we build a list of services to match against by stripping any _1/etc
    # suffixes. As a result the first matching service will be used.
    my %services = map {
        _normalise_service_code($_->{service_code}) => $_
    } reverse @services;
    my %private_services = map { $_ => 1 } @{$self->private_services};

    # Enquiries

    my $updated_enquiries = $integ->GetEnquiryStatusChanges(
        $args->{start_date},
        $args->{end_date}
    );
    my @enquiry_ids = map {
        $_->{EnquiryNumber}
    } @$updated_enquiries;

    my @enquiries = $integ->GetEnquiries(@enquiry_ids);
    for my $enquiry ( @enquiries ) {
        my $code = $enquiry->{ServiceCode} . "_" . $enquiry->{SubjectCode};
        my $service = $services{$code};
        my $status = $self->reverse_status_mapping->{$enquiry->{EnquiryStatusCode}};
        next if $status && $status eq 'IGNORE';

        unless ($service || ($service = $self->_find_wrapping_service($code, \@services))) {
            $self->logger->warn("no service for service code $code");
            next;
        }

        next if $self->request_ignore_statuses->{$enquiry->{EnquiryStatusCode}};

        unless ($status) {
            # Default to 'open' if the status doesn't appear in the reverse mapping,
            # which is the same as we do for service request updates.
            $self->logger->warn("no reverse mapping for status code $enquiry->{EnquiryStatusCode} (Enquiry $enquiry->{EnquiryNumber})");
            $status = 'open';
        }

        unless ($enquiry->{EnquiryY} && $enquiry->{EnquiryX}) {
            $self->logger->warn("no easting/northing for Enquiry $enquiry->{EnquiryNumber}");
            next;
        }

        my $createdtime = $self->date_parser->parse_datetime($enquiry->{EnquiryLogTime})->truncate( to => 'second' );
        $createdtime->set_time_zone($integ->server_timezone);
        next if $self->cutoff_enquiry_date && $createdtime < $self->cutoff_enquiry_date;

        my $updatedtime = $self->date_parser->parse_datetime($enquiry->{LoggedTime})->truncate( to => 'second' );
        $updatedtime->set_time_zone($integ->server_timezone);

        my %args = (
            service => $service,
            service_request_id => $enquiry->{EnquiryNumber},
            description => $enquiry->{EnquiryDescription},
            address => $enquiry->{EnquiryLocation} || '',
            requested_datetime => $createdtime,
            updated_datetime => $updatedtime,
            # NB: these are EPSG:27700 easting/northing
            latlong => [ $enquiry->{EnquiryY}, $enquiry->{EnquiryX} ],
            status => $status,
        );

        if ( $self->fetch_reports_private || $private_services{$code} ) {
            $args{non_public} = 1;
        }

        if ( $self->include_private_customer_details ) {
            my $json = $integ->get_enquiry_json($enquiry->{EnquiryNumber});
            if (my $customers = ( $json->{customers} || [] )) {
                my $customer = $customers->[0];
                $args{contact_name}  = $customer->{contact}->{fullName} || '';
                $args{contact_email} = $customer->{contact}->{email} || '';
            }
        }

        my $request = $self->new_request( %args );

        push @requests, $request;
    }

    if ($self->handle_jobs) {
        $self->_get_service_requests_for_jobs($integ, \%services, $args, \@requests);
    }

    if ($self->handle_defects) {
        $self->_get_service_requests_for_defects($integ, \%services, $args, \@requests);
    }

    return @requests;
}

=head2 _get_service_requests_for_jobs

Fetches any jobs from Confirm (if feature is enabled) for the given timespan,
and appends them to the $requests array as Open311 ServiceRequests.

=cut

sub _get_service_requests_for_jobs {
    my ($self, $integ, $services, $args, $requests) = @_;

    return unless $self->handle_jobs;

    my $jobs = $integ->GetJobs(
        start_date => $args->{start_date},
        end_date   => $args->{end_date},
    );

    for my $job (@$jobs) {
        my $job_id = $job->{jobNumber};

        unless ( $job->{geometry} ) {
            $self->logger->warn("geometry data missing for job $job_id");
            next;
        }

        # Of form e.g. 'POINT (-2.07951462 51.88413492)'
        my ($geo) = $job->{geometry} =~ s/POINT \((.+)\)/$1/r;
        my ( $lon, $lat ) = split / /, $geo;

        unless ( $lon && $lat ) {
            $self->logger->warn("no lat/lon for job $job_id");
            next;
        }

        my $service = $services->{ $job->{jobType}{code} };
        unless ($service) {
            # Should not happen given that we filter by job type in graphql
            $self->logger->warn( "no service for job type code "
                    . $job->{jobType}{code}
                    . " for job $job_id" );
            next;
        }

        my $last_status_log = $job->{statusLogs}[-1];
        unless ($last_status_log) {
            $self->logger->warn( "no status logs for job type code "
                    . $job->{jobType}{code}
                    . " for job $job_id" );
            next;
        }

        my $status = $self->job_reverse_status_mapping
            ->{ $last_status_log->{statusCode} };
        unless ($status) {
            # This shouldn't happen given that we filter by status code
            # in graphql. But just in case, default to open.
            $self->logger->warn( "no reverse mapping for job status code "
                    . $last_status_log->{statusCode}
                    . " for job $job_id" );
            $status = 'open';
        }

        my $createdtime
            = $self->date_parser->parse_datetime( $job->{entryDate} )
            ->truncate( to => 'second' );
        $createdtime->set_time_zone( $integ->server_timezone );
        next
            if $self->cutoff_enquiry_date
            && $createdtime < $self->cutoff_enquiry_date;

        my $updatedtime = $self->date_parser->parse_datetime( $last_status_log->{loggedDate} )
            ->truncate( to => 'second' );
        $updatedtime->set_time_zone( $integ->server_timezone );

        my %args = (
            service => $service,
            service_request_id => 'JOB_' . $job_id,
            description => $job->{description},
            requested_datetime => $createdtime,
            updated_datetime => $updatedtime,
            # NOTE These are NOT EPSG:27700 easting/northing, unlike
            # enquiries above
            latlong => [ $lat, $lon ],
            status => $status,
        );

        my $request = $self->new_request( %args );

        push @$requests, $request;
    }
}

=head2 _get_service_requests_for_defects

Fetches any defects from Confirm (if feature is enabled) for the given timespan,
and appends them to the $requests array as Open311 ServiceRequests.

NB this has some quite Aberdeenshire-specific behaviour baked in.

=cut

sub _get_service_requests_for_defects {
    my ($self, $integ, $services, $args, $requests) = @_;

    return unless $self->handle_defects;

    my $defects = $integ->GetDefects(
        start_date => $args->{start_date},
        end_date   => $args->{end_date},
    );

    DEFECT: for my $defect (@$defects) {
        my $defect_id = $defect->{defectNumber};

        unless ( $defect->{easting} && $defect->{northing} ) {
            $self->logger->warn("easting/northing data missing for defect $defect_id");
            next;
        }

        my $service = $self->_find_defect_service($defect->{defectType}->{code}, $services);
        unless ($service) {
            # Should not happen given that we filter by defect type in graphql
            $self->logger->warn( "no service for defect type code "
                    . $defect->{defectType}->{code}
                    . " for defect $defect_id" );
            next;
        }

        my $createdtime
            = $self->date_parser->parse_datetime( $defect->{loggedDate} )
            ->truncate( to => 'second' );
        $createdtime->set_time_zone( $integ->server_timezone );
        next
            if $self->cutoff_enquiry_date
            && $createdtime < $self->cutoff_enquiry_date;

        # Skip this defect if any of the enquiries on it match our own
        # externalSystemNumber
        for my $enq (@{ $defect->{enquiries} }) {
            my $cenq = $enq->{centralEnquiry} || {};
            my $num = $cenq->{externalSystemNumber};
            next DEFECT if $num && $num eq $integ->external_system_number;
        }


        my $status = "planned"; # XXX Aberdeenshire
        my $updatedtime = $createdtime;

        # if there's a job then we take the status & update time from that
        if ($defect->{job} && $defect->{job}->{currentStatusLog}) {
            my $log = $defect->{job}->{currentStatusLog};
            $status = $self->job_reverse_status_mapping->{ $log->{statusCode} };

            if (!$status) {
                $self->logger->warn(
                    "Missing reverse job status mapping for statusCode $log->{statusCode} (defectNumber $defect_id})"
                );
                next; # don't import defects we don't know the status of
            }

            $updatedtime
                = $self->date_parser->parse_datetime( $log->{loggedDate} )
                ->truncate( to => 'second' );
            $updatedtime->set_time_zone( $integ->server_timezone );
        }

        my $description = $self->_description_for_defect($defect, $service);

        my %args = (
            service => $service,
            service_request_id => 'DEFECT_' . $defect_id,
            description => $description,
            requested_datetime => $createdtime,
            updated_datetime => $updatedtime,
            # NOTE These are NOT EPSG:27700 easting/northing, unlike
            # enquiries above
            latlong => [ $defect->{northing}, $defect->{easting} ],
            status => $status,
        );

        my $request = $self->new_request( %args );

        push @$requests, $request;
    }
}

sub _description_for_defect {
    my ($self, $defect, $service) = @_;

    return $defect->{description} || '';
}

=head2 _find_defect_service

For incoming defects we may wish to send them to FMS to appear in an existing
category that's used for new enquiries. We may also want to remap the defect type
code to another so multiple defect types appear under one category on FMS.

This function parses the defect_service_mapping config and returns
the correct Service to be applied to the ServiceRequest that's created.

=cut

sub _find_defect_service {
    my ($self, $code, $services) = @_;

    my $service_whitelist = $self->defect_service_mapping;
    my $cfg = $service_whitelist->{$code};

    return unless $cfg;

    # The values in defect_service_mapping are hashrefs and the contents
    # determine what service to use for this defect.
    # service_alias: this key indicates fetched defects will appear in an
    #                existing service from service_whitelist, so look that up.
    # defect_alias: this key means fetched defects will have their code remapped
    #               to another defect type (e.g. you want multiple defect types to
    #               appear under a single category on FMS), so find that.
    # group/category: means there is a specific service for this defect type

    if ( $cfg->{group} && $cfg->{category} ) {
        return $services->{ "DEFECT_$code" };
    } elsif ( my $enq_code = $cfg->{service_alias} ) {
        return $services->{$enq_code}; # NB $services here has the normalised codes, so be sure to strip _1/_2 suffixes from config
    } elsif ( my $def_code = $cfg->{defect_alias} ) {
        return $self->_find_defect_service($def_code, $services);
    }
}

=head2 _find_wrapping_service

For Confirm integrations that are using wrapped services, this method is used to
find the Open311 Service that wraps a given service/subject code from Confirm.
This is needed so we can fetch enquiries from Confirm and give them the correct
Open311 service code.

NB this only finds the first matching Service that wraps the code.

=cut

sub _find_wrapping_service {
    my ($self, $code, $services) = @_;

    return unless defined $self->wrapped_services;

    for my $service (@$services) {
        return $service if $code eq $service->service_code;
        my @attributes = @{ $service->attributes };
        my ($wrapped_codes) = grep { $_->code eq '_wrapped_service_code' } @attributes;
        next unless $wrapped_codes;
        return $service if grep { $_ eq $code } keys %{ $wrapped_codes->values };
    }
}

sub _parse_attributes {
    my ($self, $response) = @_;

    my %attributes = ();

    my $attribute_types = $response->{OperationResponse}->{GetEnquiryLookupsResponse}->{EnquiryAttributeType};

    my %ignored_options = map { $_ => 1 } @{$self->ignored_attribute_options};

    # sometimes the EnquiryAttribute call returns a hash so wrap it in an array
    $attribute_types = [ $attribute_types ] if $attribute_types && ref $attribute_types ne 'ARRAY';
    for (@$attribute_types) {
        my $code = $_->{EnqAttribTypeCode};
        my $flag = $_->{EnqAttribTypeFlag} || '';

        my $required = $_->{MandatoryFlag} eq 'true' ? 1 : 0;
        my $desc = $self->attribute_descriptions->{$code} || $_->{EnqAttribTypeName};
        my $enquiry_attributes = $_->{EnquiryAttributeValue};
        $enquiry_attributes = [ $enquiry_attributes ] if (ref($enquiry_attributes) eq 'HASH');
        my %values = map {
            if ($ignored_options{$_->{EnqAttribValueCode}}) {
                ()
            } else {
                my $name = $_->{EnqAttribValueName};
                $name = $self->attribute_value_overrides->{$code}->{$name} || $name;
                $_->{EnqAttribValueCode} => $name
            }
        } @{ $enquiry_attributes };
        my $type = $flag eq 'D' ? 'datetime' : %values ? 'singlevaluelist' : 'string';


        # printf "\n\nXXXXXXXX $code\n\n\n" if $type eq 'singlevaluelist';

        my %optional = ();
        if (defined $self->attribute_overrides->{$code}) {
            %optional = %{ $self->attribute_overrides->{$code} };
        }

        $attributes{$code} = Open311::Endpoint::Service::Attribute->new(
            code => $code,
            description => $desc,
            datatype => $type,
            required => $required,
            values => \%values,
            %optional,
        );

    }

    return \%attributes;
}

sub _wrap_services {
    my $self = shift;
    my @original_services = @_;

    my %original_services = map { $_->service_code => $_ } @original_services;

    my @services = ();
    for my $code (sort keys %{$self->wrapped_services}) {
        if ($self->wrapped_services->{$code}->{passthrough}) {
            my $original_service = $original_services{$code};
            my $wrapped_group = $self->wrapped_services->{$code}->{group};
            $wrapped_group = [$wrapped_group] if ( $wrapped_group && ref $wrapped_group ne 'ARRAY' );
            $original_service->groups($wrapped_group || $original_service->groups);
            push @services, $original_service;
            next;
        }

        my %wrapped_services = map { $_ => $original_services{$_}->service_name } @{ $self->wrapped_services->{$code}->{wraps} };

        my $desc = $self->wrapped_services->{$code}->{description} || "What is the issue?";
        my @attributes = (
            Open311::Endpoint::Service::Attribute->new(
                code => "_wrapped_service_code",
                description => $desc,
                datatype => "singlevaluelist",
                required => 1,
                values => \%wrapped_services,
            ),
        );
        my %seen_attributes = (_wrapped_service_code => 1);

        # The wrapped services may have their own attributes, so merge
        # them all together (stripping duplicates) and include them in
        # the wrapping service.
        for my $wrapped_service ( map { $original_services{$_} } @{ $self->wrapped_services->{$code}->{wraps} }) {
            foreach (@{ $wrapped_service->attributes }) {
                next if $seen_attributes{$_->{code}};
                push @attributes, $_;
                $seen_attributes{$_->{code}} = 1;
            }
        }

        my $groups = $self->wrapped_services->{$code}->{group};
        $groups = [$groups] if $groups && ref $groups ne 'ARRAY';
        my %service = (
            service_name => $self->wrapped_services->{$code}->{name},
            service_code => $code,
            description => $self->wrapped_services->{$code}->{name},
            groups => $groups,
            attributes => \@attributes,
        );
        my $o311_service = $self->service_class->new(%service);
        push @services, $o311_service;
    }

    return @services;
}

sub get_completion_photo {
    my ($self, $args) = @_;

    my ($content_type, $content) = $self->get_integration->get_job_photo($args->{job}, $args->{photo});
    return [ 404, [ 'Content-type', 'text/plain' ], [ 'Not found' ] ] unless $content;

    return [ 200, [ 'Content-type', $content_type ], [ $content ] ];
}

sub _normalise_service_code {
    my $code = shift;
    my ($serv, $subj, $extra) = split /_/, $code;
    return $code unless defined $subj; # In case it's e.g. a job code with no _
    return join("_", $serv, $subj);
}

1;
