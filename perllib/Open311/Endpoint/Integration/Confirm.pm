package Open311::Endpoint::Integration::Confirm;

use Moo;
extends 'Open311::Endpoint';
with 'Open311::Endpoint::Role::mySociety';

use Open311::Endpoint::Service::UKCouncil::Confirm;
use Open311::Endpoint::Service::Attribute;
use Open311::Endpoint::Service::Request::Update::mySociety;

use SOAP::Lite; # +trace => [ qw/method debug/ ];


=head2 service_whitelist

Controls the mapping of Confirm service/subject codes to Open311 services.
Subclasses must override this or no Open311 services will be published!

Returns a hashref which groups services together and optionally provides
an overridden name for each service.

For example, the following hashref will publish 5 Open311 services:

{
    'Roads' => {
        RO_PH => 1,
        RO_GB => 1,
        RO_LP => "Faded Markings",
    },
    'Lighting' => {
        LG_SL => 1,
        LG_BL => 1,
    }
}

3 services will be published with their group set to 'Roads', and two in
the 'Lighting' group. RO_PH, RO_GB, LG_SL, and LG_BL will take the subject
name from Confirm as their Open311 service name. RO_LP shows how the Confirm
default can be overridden, and this service will be published as 'Faded
Markings'.

I opted for a whitelist instead of a blacklist because Councils tend to have
hundreds of available service/subject codes in their Confirm instances but
typically only want to publish a small number (to begin with) on FixMyStreet.

=cut

has service_whitelist => (
    is => 'ro',
    default => sub { die "Attribute Confirm::service_whitelist not overridden"; }
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
Confirm.

All possible Confirm enquiry status values should be mapped to Open311 statuses.

=cut

has reverse_status_mapping => (
    is => 'ro',
    default => sub { {} }
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

    # Open311 doesn't support a 'title' field for service requests, so FMS
    # concatenates the report title and description together in the description
    # field. We want to put the title/description in different fields in
    # Confirm, so they're sent as individual Open311 attributes which we
    # put directly in $args so NewEnquiry can do the right thing.
    $args->{location} = $args->{attributes}->{title};
    delete $args->{attributes}->{title};

    # Any asset information is appended to the Confirm location field, if
    # present, as Confirm doesn't have a specific way of allowing us to
    # identify assets that we've come across yet.
    if ( defined $args->{attributes}->{asset_details} ) {
        $args->{location} .= "\nAsset information:\n" . $args->{attributes}->{asset_details};
        delete $args->{attributes}->{asset_details};
    }

    return $args;
}

sub get_integration {
    my $self = shift;
    return $self->integration_class->on_fault(sub { my($soap, $res) = @_; die ref $res ? $res->faultstring : $soap->transport->status, "\n"; });
}

sub post_service_request {
    my ($self, $service, $args) = @_;
    die "No such service" unless $service;

    my $integ = $self->get_integration;

    $args = $self->process_service_request_args($args);

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
        status => lc $args->{status},
        update_id => $update_id,
    );

}


sub get_service_request_updates {
    my ($self, $args) = @_;

    my $integ = $self->get_integration;
    my $enquiries = $integ->GetEnquiryStatusChanges(
        $args->{start_date},
        $args->{end_date}
    );

    my $w3c = DateTime::Format::W3CDTF->new;
    my @updates = ();

    for my $enquiry (@$enquiries) {
        my $status_logs = $enquiry->{EnquiryStatusLog};
        $status_logs = [ $status_logs ] if (ref($status_logs) eq 'HASH');
        for my $status_log (@$status_logs) {
            my $enquiry_id = $enquiry->{EnquiryNumber};
            my $update_id = $enquiry_id . "_" . $status_log->{EnquiryLogNumber};
            my $ts = $w3c->parse_datetime($status_log->{LogEffectiveTime});
            $ts->set_time_zone($integ->server_timezone);
            my $description = $self->publish_service_update_text ?
                ($status_log->{StatusLogNotes} || "") :
                "";
            my $status = $self->reverse_status_mapping->{$status_log->{EnquiryStatusCode}};
            if (!$status) {
                print STDERR "Missing reverse status mapping for EnquiryStatus Code $status_log->{EnquiryStatusCode} (EnquiryNumber $enquiry->{EnquiryNumber})\n";
                $status = "open";
            }

            push @updates, Open311::Endpoint::Service::Request::Update::mySociety->new(
                status => $status,
                update_id => $update_id,
                service_request_id => $enquiry_id,
                description => $description,
                updated_datetime => $ts,
            );
        }
    }
    return @updates;
}


sub services {
    my $self = shift;

    my $integ = $self->get_integration;

    my $response = $integ->GetEnquiryLookups();
    my $confirm_services = $response->{OperationResponse}->{GetEnquiryLookupsResponse}->{TypeOfService};

    my $available_attributes = $self->_parse_attributes($response);

    my %ignored_attribs = map { $_ => 1 } @{$self->ignored_attributes};

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
    for my $group (keys %{ $self->service_whitelist }) {
        my $whitelist = $self->service_whitelist->{$group};
        for my $code (keys %{ $whitelist }) {
            my $subject = $services{$code}->{subject};
            if (!$subject) {
                printf("$code doesn't exist in Confirm.\n");
                next;
            }
            my $name = $whitelist->{$code} eq 1 ? $subject->{SubjectName} :  $whitelist->{$code};
            my %service = (
                service_name => $name,
                service_code => $code,
                description => $name,
                group => $group,
            );
            my $o311_service = $self->service_class->new(%service);
            for (@{$services{$code}->{attribs}}) {
                push @{$o311_service->attributes}, $_;
            }
            push @services, $o311_service;
        }
    }
    return @services;
}

sub get_service_request {
    my ($self, $id) = @_;

    my $response = $self->get_integration->GetEnquiry($id);

    return Open311::Endpoint::Service::Request->new();
}


sub _parse_attributes {
    my ($self, $response) = @_;

    my %attributes = ();

    my $attribute_types = $response->{OperationResponse}->{GetEnquiryLookupsResponse}->{EnquiryAttributeType};

    my %ignored_options = map { $_ => 1 } @{$self->ignored_attribute_options};

    for (@$attribute_types) {
        my $code = $_->{EnqAttribTypeCode};

        my $required = $_->{MandatoryFlag} eq 'true' ? 1 : 0;
        my $desc = $self->attribute_descriptions->{$code} || $_->{EnqAttribTypeName};
        my $enquiry_attributes = $_->{EnquiryAttributeValue};
        $enquiry_attributes = [ $enquiry_attributes ] if (ref($enquiry_attributes) eq 'HASH');
        my %values = map {
            if ($ignored_options{$_->{EnqAttribValueCode}}) {
                ()
            } else {
                $_->{EnqAttribValueCode} => $_->{EnqAttribValueName}
            }
        } @{ $enquiry_attributes };
        my $type = %values ? 'singlevaluelist' : 'string';


        # printf "\n\nXXXXXXXX $code\n\n\n" if $type eq 'singlevaluelist';

        $attributes{$code} = Open311::Endpoint::Service::Attribute->new(
            code => $code,
            description => $desc,
            datatype => $type,
            required => $required,
            values => \%values,
        );
    }

    return \%attributes;
}

1;
